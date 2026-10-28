#![forbid(unsafe_code)]
//! Independent physical-boundary fixture; no production codec or device handle.
use std::{
    collections::VecDeque,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use wstx_rust::radio_control::{
    self as cat, actor::Actor, catalogue::Catalogue, executor::Transport,
};

pub(crate) struct Rig {
    pub writes: Vec<Vec<u8>>,
    pub exchanges: Vec<(Instant, Option<Instant>, u64)>,
    pub setups: Vec<(Instant, Option<Instant>)>,
    pub closed: bool,
    frequency: [u8; 5],
}
struct Port {
    rig: Arc<Mutex<Rig>>,
    pending: VecDeque<u8>,
    ready: Instant,
    remaining: usize,
    setup: Option<usize>,
    exchange: Option<usize>,
    connection_cancel: Option<usize>,
    slow: bool,
}
fn check(deadline: Instant, cancel: &AtomicBool) -> cat::Result<()> {
    if cancel.load(Ordering::Acquire) {
        Err(cat::Error::Cancelled)
    } else if Instant::now() >= deadline {
        Err(cat::Error::Timeout)
    } else {
        Ok(())
    }
}
impl Transport for Port {
    fn physical_identity(&self) -> Option<&str> {
        Some("independent-civ-fixture-7300")
    }
    fn configure(&mut self, baud: u32) -> cat::Result<()> {
        if baud == 9600 {
            Ok(())
        } else {
            Err(cat::Error::InvalidConfiguration)
        }
    }
    fn write(
        &mut self,
        bytes: &[u8],
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> cat::Result<usize> {
        check(deadline, cancel)?;
        if bytes.len() < 6
            || bytes[..4] != [0xfe, 0xfe, 0x94, 0xe0]
            || bytes.last() != Some(&0xfd)
            || !self.pending.is_empty()
        {
            return Err(cat::Error::Protocol);
        }
        let body = &bytes[4..bytes.len() - 1];
        let now = Instant::now();
        let identity = std::ptr::from_ref(cancel) as usize;
        let connection = *self.connection_cancel.get_or_insert(identity);
        let mut rig = self.rig.lock().unwrap();
        if body == [6, 1, 1] {
            if self.remaining != 0 {
                return Err(cat::Error::Protocol);
            }
            self.remaining = 9;
            self.setup = Some(rig.setups.len());
            rig.setups.push((now, None));
        }
        if self.remaining > 0 {
            let allowed = match 9 - self.remaining {
                0 => body == [6, 1, 1],
                1 | 6 => body == [4],
                2 => body == [0x1a, 6, 1, 1],
                3 | 7 => body == [0x1a, 6],
                4 => body.len() == 6 && body[0] == 5,
                5 | 8 => body == [3],
                _ => false,
            };
            if !allowed {
                return Err(cat::Error::Protocol);
            }
        }
        let delay = if self.slow && self.remaining > 0 {
            470
        } else if self.slow && body == [0x1c, 0] && identity != connection {
            800
        } else {
            0
        };
        let reply = match body {
            [3] => {
                let mut b = vec![3];
                b.extend(rig.frequency);
                b
            }
            [4] => vec![4, 1, 1],
            [0x1a, 6] => vec![0x1a, 6, 1, 1],
            [0x1c, 0] => vec![0x1c, 0, 0],
            [0x0f] => vec![0x0f, 0],
            [6, 1, 1] | [0x1a, 6, 1, 1] => vec![0xfb],
            [5, a, b, c, d, e] => {
                let value = [*a, *b, *c, *d, *e];
                // Four literal independent dial vectors from FSD4.7.5/Icom BCD.
                if ![
                    [0, 0x40, 7, 7, 0],
                    [0, 0x75, 4, 7, 0],
                    [0, 0x40, 7, 0x14, 0],
                    [0, 0, 8, 0x14, 0],
                ]
                .contains(&value)
                {
                    return Err(cat::Error::Protocol);
                }
                rig.frequency = value;
                vec![0xfb]
            }
            _ => return Err(cat::Error::Protocol),
        };
        rig.writes.push(bytes.to_vec());
        self.exchange = Some(rig.exchanges.len());
        rig.exchanges.push((now, None, delay));
        drop(rig);
        self.pending.extend([0xfe, 0xfe, 0xe0, 0x94]);
        self.pending.extend(reply);
        self.pending.push_back(0xfd);
        self.ready = now + Duration::from_millis(delay);
        if self.remaining > 0 {
            self.remaining -= 1;
        }
        Ok(bytes.len())
    }
    fn read(
        &mut self,
        bytes: &mut [u8],
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> cat::Result<usize> {
        while Instant::now() < self.ready {
            check(deadline, cancel)?;
            std::thread::sleep(Duration::from_millis(1));
        }
        check(deadline, cancel)?;
        let count = bytes.len().min(3).min(self.pending.len());
        for b in bytes.iter_mut().take(count) {
            *b = self.pending.pop_front().unwrap();
        }
        if self.pending.is_empty() {
            let now = Instant::now();
            let mut rig = self.rig.lock().unwrap();
            if let Some(index) = self.exchange.take() {
                rig.exchanges[index].1 = Some(now);
            }
            if self.remaining == 0
                && let Some(index) = self.setup.take()
            {
                rig.setups[index].1 = Some(now);
            }
        }
        Ok(count)
    }
    fn quiet(&mut self, deadline: Instant, cancel: &AtomicBool) -> cat::Result<()> {
        check(deadline, cancel)
    }
    fn close(&mut self) -> cat::Result<()> {
        self.rig.lock().unwrap().closed = true;
        Ok(())
    }
}
pub(crate) fn actor(
    profile: String,
    boot: String,
    revision: u64,
    slow: bool,
) -> (Arc<Actor>, Arc<Mutex<Rig>>) {
    let rig = Arc::new(Mutex::new(Rig {
        writes: Vec::new(),
        exchanges: Vec::new(),
        setups: Vec::new(),
        closed: false,
        frequency: [0, 0x40, 7, 7, 0],
    }));
    let physical = rig.clone();
    let actor = Arc::new(
        Actor::begin(
            cat::Configuration::parse("COM3").unwrap(),
            cat::Authority {
                profile_id: profile,
                boot_id: boot,
                profile_revision: revision,
                resource_id: "independent-civ-fixture-7300".into(),
                connection_generation: 1,
            },
            Catalogue::builtin().unwrap(),
            move |_, _| {
                Ok(Port {
                    rig: physical,
                    pending: VecDeque::new(),
                    ready: Instant::now(),
                    remaining: 0,
                    setup: None,
                    exchange: None,
                    connection_cancel: None,
                    slow,
                })
            },
        )
        .unwrap(),
    );
    let deadline = Instant::now() + Duration::from_secs(2);
    while actor.snapshot().unwrap().state == cat::State::Connecting && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(actor.snapshot().unwrap().state, cat::State::Ready);
    (actor, rig)
}
