//! Test-thread-local observation of real work; only the caller's cancel token may change.
use std::{
    cell::RefCell,
    marker::PhantomData,
    rc::Rc,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Phase {
    DetectionRow,
    FecCheck,
    FecRow,
    FecIteration,
    RecoveryRank,
    RecoveryCheck,
    RecoveryTrial,
    SubtractionForward,
    SubtractionCommit,
}
#[derive(Clone, Default)]
pub(super) struct Report {
    pub counts: [usize; 9],
    pub first_fec_word: Option<[u8; 174]>,
}
struct Observer {
    cancel: Arc<AtomicBool>,
    cancel_on: Option<Phase>,
    report: Arc<Mutex<Report>>,
}
thread_local! {
    static CURRENT: RefCell<Option<Observer>> = const { RefCell::new(None) };
}
pub(super) struct Guard {
    previous: Option<Observer>,
    report: Arc<Mutex<Report>>,
    _thread: PhantomData<Rc<()>>,
}
impl Guard {
    pub fn report(&self) -> Report {
        self.report.lock().unwrap().clone()
    }
}
impl Drop for Guard {
    fn drop(&mut self) {
        CURRENT.with(|slot| *slot.borrow_mut() = self.previous.take());
    }
}
pub(super) fn install(cancel: Arc<AtomicBool>, cancel_on: Option<Phase>) -> Guard {
    let report = Arc::new(Mutex::new(Report::default()));
    let previous = CURRENT.with(|slot| {
        slot.replace(Some(Observer {
            cancel,
            cancel_on,
            report: report.clone(),
        }))
    });
    Guard {
        previous,
        report,
        _thread: PhantomData,
    }
}
pub(super) fn hit(phase: Phase) {
    CURRENT.with(|slot| {
        if let Some(observer) = slot.borrow().as_ref() {
            observer.report.lock().unwrap().counts[phase as usize] += 1;
            if observer.cancel_on == Some(phase) {
                observer.cancel.store(true, Ordering::SeqCst);
            }
        }
    });
}
pub(super) fn fec_word(hard: [u8; 174]) {
    hit(Phase::FecIteration);
    CURRENT.with(|slot| {
        if let Some(observer) = slot.borrow().as_ref() {
            observer
                .report
                .lock()
                .unwrap()
                .first_fec_word
                .get_or_insert(hard);
        }
    });
}

#[test]
fn observer_is_thread_local_and_restores_nested_original_token() {
    let original = Arc::new(AtomicBool::new(false));
    let outer = install(original.clone(), Some(Phase::DetectionRow));
    std::thread::spawn(|| hit(Phase::DetectionRow))
        .join()
        .unwrap();
    assert!(!original.load(Ordering::SeqCst));
    let nested = Arc::new(AtomicBool::new(false));
    {
        let _inner = install(nested.clone(), Some(Phase::DetectionRow));
        hit(Phase::DetectionRow);
        assert!(nested.load(Ordering::SeqCst));
        assert!(!original.load(Ordering::SeqCst));
    }
    hit(Phase::DetectionRow);
    assert!(original.load(Ordering::SeqCst));
    assert_eq!(outer.report().counts[Phase::DetectionRow as usize], 1);
}

pub(super) fn cases() -> serde_json::Value {
    serde_json::from_str(include_str!(
        "../../../fixtures/decoder/resource-cases.json"
    ))
    .unwrap()
}

#[cfg(not(debug_assertions))]
pub(super) fn pinned_samples(mode: super::Mode) -> Vec<f32> {
    let cases = cases();
    let name = if mode == super::Mode::Ft8 {
        "ft8"
    } else {
        "ft4"
    };
    let case = cases["samples"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["mode"] == name)
        .unwrap();
    let root = std::path::PathBuf::from(
        std::env::var_os("WSTX_DECODER_CACHE")
            .expect("resource proof requires explicitly prepared WSTX_DECODER_CACHE"),
    );
    let path = root
        .join(case["id"].as_str().unwrap())
        .join("000000_000000.wav");
    let verified = std::process::Command::new(if cfg!(windows) { "python" } else { "python3" })
        .args(["-c", "import hashlib,pathlib,sys; assert hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()==sys.argv[2]"])
        .arg(&path).arg(case["sha256"].as_str().unwrap()).status().unwrap();
    assert!(verified.success(), "independently pinned D1 input hash");
    let bytes = std::fs::read(path).unwrap();
    assert_eq!(&bytes[..4], b"RIFF");
    assert_eq!(&bytes[8..12], b"WAVE");
    let mut samples = None;
    let mut format = false;
    let mut offset = 12;
    while offset + 8 <= bytes.len() {
        let length = u32::from_le_bytes(bytes[offset + 4..offset + 8].try_into().unwrap()) as usize;
        let data = &bytes[offset + 8..offset + 8 + length];
        match &bytes[offset..offset + 4] {
            b"fmt " => {
                assert_eq!(u16::from_le_bytes(data[..2].try_into().unwrap()), 1);
                assert_eq!(u16::from_le_bytes(data[2..4].try_into().unwrap()), 1);
                assert_eq!(u32::from_le_bytes(data[4..8].try_into().unwrap()), 12000);
                assert_eq!(u16::from_le_bytes(data[14..16].try_into().unwrap()), 16);
                format = true;
            }
            b"data" => {
                assert_eq!(data.len() % 2, 0);
                samples = Some(
                    data.chunks_exact(2)
                        .map(|b| i16::from_le_bytes(b.try_into().unwrap()) as f32 / 32768.)
                        .collect::<Vec<_>>(),
                );
            }
            _ => {}
        }
        offset += 8 + length + length % 2;
    }
    assert!(format);
    let samples = samples.unwrap();
    assert_eq!(samples.len(), case["frames"].as_u64().unwrap() as usize);
    samples
}
