//! Observation of real work through the decoder's own cancel callback, its port for
//! cancellation: a cancel point answers `false` for its first `n` calls and `true` after.
use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

#[derive(Default)]
struct Answers {
    calls: usize,
    last_false: Option<Instant>,
    first_true: Option<Instant>,
}
/// A cancel callback of plain values: `false` for its first `n` calls, `true` from call
/// n + 1 on, counting calls from every thread.
pub struct CancelPoint {
    n: usize,
    answers: Mutex<Answers>,
}
impl CancelPoint {
    pub fn after(n: usize) -> Self {
        Self {
            n,
            answers: Mutex::new(Answers::default()),
        }
    }
    /// The callback: one call of the decoder's `cancel()`.
    pub fn cancelled(&self) -> bool {
        let now = Instant::now();
        let mut answers = self.answers.lock().unwrap();
        answers.calls += 1;
        let call = answers.calls;
        if call == self.n.max(1) {
            answers.last_false = Some(now);
        }
        let cancelled = call > self.n;
        if cancelled {
            answers.first_true.get_or_insert(now);
        }
        cancelled
    }
    pub fn calls(&self) -> usize {
        self.answers.lock().unwrap().calls
    }
    /// The instant of call n, its last `false` answer; for `after(0)`, the instant of call 1.
    pub fn last_false_at(&self) -> Option<Instant> {
        self.answers.lock().unwrap().last_false
    }
    pub fn first_true_at(&self) -> Option<Instant> {
        self.answers.lock().unwrap().first_true
    }
    /// Bounds the decoder's work from its last unanswered check (call n) to its return.
    pub fn record_return(
        &self,
        context: &serde_json::Value,
        started: Instant,
        returned: Instant,
        kind: &str,
    ) {
        let accepted = self.first_true_at().and(self.last_false_at());
        let latency = accepted.and_then(|accepted| returned.checked_duration_since(accepted));
        eprintln!(
            "RESOURCE_PHASE_RETURN {}",
            serde_json::json!({"context":context,"invocation_kind":kind,
            "invocation_wall_seconds":returned.duration_since(started).as_secs_f64(),
            "original_token_cancel_observed":self.first_true_at().is_some(),
            "cancel_to_kernel_return_seconds":latency.map(|duration|duration.as_secs_f64()),
            "kernel_return_within250ms":latency.map(|duration|duration<=Duration::from_millis(250)),
            "cpu_time_measured":false,"manager_ack_release_or_terminal_proved":false})
        );
        assert!(
            latency.is_some(),
            "timing evidence requires the original token's actual phase cancellation"
        );
        assert!(
            latency.unwrap() <= Duration::from_millis(250),
            "kernel cancellation-return exceeds necessary250ms sub-bound; this is not manager acceptance evidence"
        );
    }
}

#[cfg(not(debug_assertions))]
pub struct PollTiming {
    pub returned_at: Instant,
    polls: usize,
    pending: usize,
    maximum: Duration,
}
#[cfg(not(debug_assertions))]
pub fn poll_to_completion<F: std::future::Future>(
    future: F,
    context: &serde_json::Value,
) -> (F::Output, PollTiming) {
    use std::task::{Context, Poll, Waker};
    let mut future = std::pin::pin!(future);
    let mut cx = Context::from_waker(Waker::noop());
    let began = Instant::now();
    let mut timing = PollTiming {
        returned_at: began,
        polls: 0,
        pending: 0,
        maximum: Duration::ZERO,
    };
    loop {
        let started = Instant::now();
        let result = future.as_mut().poll(&mut cx);
        let returned = Instant::now();
        let wall = returned.duration_since(started);
        timing.polls += 1;
        timing.maximum = timing.maximum.max(wall);
        let ready = matches!(&result, Poll::Ready(_));
        if !ready {
            timing.pending += 1;
        }
        eprintln!(
            "RESOURCE_FUTURE_POLL {}",
            serde_json::json!({"context":context,"poll":timing.polls,
            "started_seconds":started.duration_since(began).as_secs_f64(),"wall_seconds":wall.as_secs_f64(),
            "ready":ready,"cpu_time_measured":false})
        );
        if let Poll::Ready(value) = result {
            timing.returned_at = returned;
            eprintln!(
                "RESOURCE_FUTURE_SUMMARY {}",
                serde_json::json!({"context":context,"polls":timing.polls,
                "pending":timing.pending,"maximum_poll_wall_seconds":timing.maximum.as_secs_f64(),
                "poll_wall_sufficient_for50ms_cpu":timing.maximum<=Duration::from_millis(50),
                "over50ms_disposition":"CPU quantum unproved by wall timing; measureCPU rather than infer CPU violation",
                "cpu_time_measured":false,"manager_ack_release_or_terminal_proved":false})
            );
            return (value, timing);
        }
    }
}
// Timing: compute
#[test]
fn cancel_point_answers_true_from_the_call_after_n() {
    fn shared<T: Sync>(_: &T) {}
    let point = CancelPoint::after(2);
    shared(&point);
    assert!(!point.cancelled());
    assert_eq!(point.last_false_at(), None);
    assert!(!point.cancelled());
    let call_n = point
        .last_false_at()
        .expect("the instant of call n is set at call n");
    assert_eq!(point.first_true_at(), None);
    assert!(point.cancelled());
    let first_true = point.first_true_at().expect("set at call n + 1");
    assert!(first_true >= call_n);
    assert!(point.cancelled());
    assert_eq!(point.calls(), 4);
    assert_eq!(point.last_false_at(), Some(call_n));
    assert_eq!(point.first_true_at(), Some(first_true));

    // Calls from two threads count together.
    let point = CancelPoint::after(2);
    std::thread::scope(|scope| {
        scope.spawn(|| assert!(!point.cancelled()));
    });
    assert!(!point.cancelled());
    std::thread::scope(|scope| {
        scope.spawn(|| assert!(point.cancelled()));
    });
    assert_eq!(point.calls(), 3);

    // after(0): call 1 answers true and is the instant the bound runs from.
    let point = CancelPoint::after(0);
    assert!(point.cancelled());
    assert_eq!(point.last_false_at(), point.first_true_at());
    assert!(point.last_false_at().is_some());
}

pub fn cases() -> serde_json::Value {
    serde_json::from_str(include_str!(
        "../../../../fixtures/decoder/resource-cases.json"
    ))
    .unwrap()
}

#[cfg(not(debug_assertions))]
pub fn pinned_samples(name: &str) -> Vec<f32> {
    let cases = cases();
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
    pinned_samples_no_probe(name)
}

/// Reads the pinned WAV without checking its hash; `pinned_samples` checks it first.
/// This reader deliberately never starts a verifier/probe descendant.
#[cfg(not(debug_assertions))]
pub fn pinned_samples_no_probe(name: &str) -> Vec<f32> {
    let cases = cases();
    let case = cases["samples"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["mode"] == name)
        .unwrap();
    let path = std::path::PathBuf::from(std::env::var_os("WSTX_DECODER_CACHE").unwrap())
        .join(case["id"].as_str().unwrap())
        .join("000000_000000.wav");
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
                    data.as_chunks::<2>()
                        .0
                        .iter()
                        .map(|b| i16::from_le_bytes(*b) as f32 / 32768.)
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
