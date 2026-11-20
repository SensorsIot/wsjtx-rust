//! The decoder resource harness of `server/tests/decoder_signal.rs`: owned worker and
//! monitor peers, bounded lines and commands, the guardian handshake, the source and host
//! identities and the concurrency qualification of a round. It names no product type.
use serde_json::Value;
use std::{
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        Arc, Mutex,
        mpsc::{Receiver, sync_channel},
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

pub struct ResourcePeer {
    pub child: Child,
    input: Option<ChildStdin>,
    messages: Option<Receiver<Result<Value, String>>>,
    reader: Option<JoinHandle<()>>,
    pub cleanup: Arc<Mutex<Option<Value>>>,
}
impl ResourcePeer {
    pub fn spawn(command: &mut Command, marked: bool) -> Self {
        let child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("spawn owned resource peer");
        // Own the process before any fallible pipe/reader setup.
        let mut peer = Self {
            child,
            input: None,
            messages: None,
            reader: None,
            cleanup: Arc::new(Mutex::new(None)),
        };
        peer.input = peer.child.stdin.take();
        let stdout = peer.child.stdout.take().expect("owned stdout");
        let (sender, receiver) = sync_channel(4);
        peer.messages = Some(receiver);
        peer.reader = Some(std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let line = match resource_line(&mut reader) {
                    Ok(Some(line)) => line,
                    Ok(None) => break,
                    Err(error) => {
                        let _ = sender.send(Err(error));
                        break;
                    }
                };
                let line = match std::str::from_utf8(&line) {
                    Ok(line) => line,
                    Err(error) => {
                        let _ = sender.send(Err(error.to_string()));
                        break;
                    }
                };
                let json = if marked {
                    let Some((_, suffix)) = line.split_once("WSTX_RESOURCE ") else {
                        continue;
                    };
                    suffix
                } else {
                    line
                };
                let message = serde_json::from_str(json).map_err(|error| error.to_string());
                if sender.send(message).is_err() {
                    break;
                }
            }
        }));
        peer
    }
    pub fn send(&mut self, value: Value) {
        let bytes = serde_json::to_vec(&value).unwrap();
        assert!(bytes.len() <= 4096);
        let input = self.input.as_mut().expect("owned input open");
        input.write_all(&bytes).unwrap();
        input.write_all(b"\n").unwrap();
        input.flush().unwrap();
    }
    pub fn receive(&self, seconds: u64) -> Value {
        self.messages
            .as_ref()
            .unwrap()
            .recv_timeout(Duration::from_secs(seconds))
            .expect("bounded owned peer reply")
            .expect("valid bounded resource JSON")
    }
    pub fn wait(&mut self, seconds: u64) {
        let status = self.wait_status(seconds);
        assert!(status.success(), "owned peer exit {status}");
    }
    pub fn wait_status(&mut self, seconds: u64) -> std::process::ExitStatus {
        self.input.take();
        let deadline = Instant::now() + Duration::from_secs(seconds);
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                return status;
            }
            assert!(Instant::now() < deadline, "owned peer exit timeout");
            std::thread::sleep(Duration::from_millis(5));
        }
    }
}
impl Drop for ResourcePeer {
    fn drop(&mut self) {
        self.input.take();
        let kill_attempted = !matches!(self.child.try_wait(), Ok(Some(_)));
        let kill_error = if kill_attempted {
            self.child.kill().err().map(|error| error.to_string())
        } else {
            None
        };
        let waited = self.child.wait();
        // A blocked bounded sender must be released before joining its reader.
        self.messages.take();
        let reader_joined = self
            .reader
            .take()
            .is_none_or(|reader| reader.join().is_ok());
        let receipt = serde_json::json!({"kill_attempted":kill_attempted,"kill_error":kill_error,
            "wait_succeeded":waited.is_ok(),"exit_code":waited.as_ref().ok().and_then(|status|status.code()),
            "wait_error":waited.as_ref().err().map(|error|error.to_string()),"reader_joined":reader_joined});
        if let Ok(mut audit) = self.cleanup.lock() {
            *audit = Some(receipt);
        }
    }
}
pub fn resource_line(reader: &mut impl BufRead) -> Result<Option<Vec<u8>>, String> {
    let mut line = Vec::new();
    loop {
        let available = reader.fill_buf().map_err(|error| error.to_string())?;
        if available.is_empty() {
            return if line.is_empty() {
                Ok(None)
            } else {
                Err("truncated resource line".into())
            };
        }
        let count = available
            .iter()
            .position(|&b| b == b'\n')
            .map_or(available.len(), |i| i + 1);
        if line.len() + count > 8192 {
            return Err("resource line exceeds8192bytes".into());
        }
        let complete = available[count - 1] == b'\n';
        line.extend_from_slice(&available[..count]);
        reader.consume(count);
        if complete {
            return Ok(Some(line));
        }
    }
}
pub fn resource_guardian_before_probes(case: &str) {
    assert!(matches!(case, "matrix" | "busy"));
    assert_eq!(
        std::env::var("WSTX_RESOURCE_GUARDIAN_CASE").as_deref(),
        Ok(case),
        "resource selection requires its exact guardian context before probes"
    );
    let nonce = std::env::var("WSTX_RESOURCE_GUARDIAN_NONCE")
        .expect("resource selection requires a guardian nonce before probes");
    assert!(
        nonce.len() == 32
            && nonce
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)),
        "guardian nonce must be32 lowercase hexadecimal characters"
    );
    let ready = serde_json::to_vec(&serde_json::json!({
        "v":1,"case":case,"nonce":nonce,"pid":std::process::id()
    }))
    .unwrap();
    assert!(ready.len() <= 512);
    eprintln!("WSTX_GUARDIAN_READY {}", String::from_utf8(ready).unwrap());
    std::io::stderr().flush().unwrap();
    let stdin = std::io::stdin();
    let line = resource_line(&mut stdin.lock())
        .expect("bounded guardian GO line")
        .expect("guardian stdin closed before GO");
    let payload = line
        .strip_prefix(b"WSTX_GUARDIAN_GO ")
        .expect("guardian GO prefix");
    #[derive(serde::Deserialize)]
    #[serde(deny_unknown_fields)]
    struct GuardianGo {
        v: u8,
        case: String,
        nonce: String,
    }
    let go: GuardianGo = serde_json::from_slice(payload).expect("guardian GO JSON");
    assert_eq!(
        (go.v, go.case.as_str(), go.nonce.as_str()),
        (1, case, nonce.as_str()),
        "guardian GO must have exactly the expected version, case and nonce"
    );
}
pub fn resource_emit(value: Value) {
    let bytes = serde_json::to_vec(&value).unwrap();
    assert!(bytes.len() <= 8000);
    println!("WSTX_RESOURCE {}", String::from_utf8(bytes).unwrap());
    std::io::stdout().flush().unwrap();
}
pub fn resource_helper() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../python/windows_process_metrics.py")
}
pub fn resource_python() -> &'static str {
    if cfg!(windows) { "python" } else { "python3" }
}
struct ResourceCapture {
    child: Child,
    readers: Vec<JoinHandle<()>>,
}
impl Drop for ResourceCapture {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
        for reader in self.readers.drain(..) {
            let _ = reader.join();
        }
    }
}
pub fn resource_capture(command: &mut Command, seconds: u64) -> std::process::Output {
    use std::io::Read;
    let child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut owned = ResourceCapture {
        child,
        readers: Vec::new(),
    };
    let stdout = owned.child.stdout.take().unwrap();
    let stderr = owned.child.stderr.take().unwrap();
    let (sender, receiver) = sync_channel(2);
    let start = Instant::now();
    for (index, stream) in [Box::new(stdout) as Box<dyn Read + Send>, Box::new(stderr)]
        .into_iter()
        .enumerate()
    {
        let sender = sender.clone();
        owned.readers.push(std::thread::spawn(move || {
            let mut bytes = Vec::new();
            let result = stream
                .take(65537)
                .read_to_end(&mut bytes)
                .map_err(|e| e.to_string())
                .and_then(|_| {
                    if bytes.len() > 65536 {
                        Err("bounded command output exceeded64KiB".to_owned())
                    } else {
                        Ok(bytes)
                    }
                });
            let _ = sender.send((index, result));
        }));
    }
    drop(sender);
    let mut output = [Vec::new(), Vec::new()];
    for _ in 0..2 {
        let remaining = Duration::from_secs(seconds)
            .checked_sub(start.elapsed())
            .expect("owned command deadline");
        let (index, bytes) = receiver
            .recv_timeout(remaining)
            .expect("owned command output deadline");
        output[index] = bytes.expect("bounded owned command output");
    }
    let status = loop {
        if let Some(status) = owned.child.try_wait().unwrap() {
            break status;
        }
        assert!(
            start.elapsed() < Duration::from_secs(seconds),
            "owned command exit deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    };
    std::process::Output {
        status,
        stdout: std::mem::take(&mut output[0]),
        stderr: std::mem::take(&mut output[1]),
    }
}
/// The reference label follows the observed host identity, never an unconditional claim.
pub fn resource_host_scope() -> Value {
    let computer = std::env::var("COMPUTERNAME").unwrap_or_default();
    let query = resource_capture(
        Command::new("reg").args([
            "query",
            r"HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0",
            "/v",
            "ProcessorNameString",
        ]),
        10,
    );
    let processor = String::from_utf8_lossy(&query.stdout)
        .lines()
        .find_map(|line| {
            line.split_once("REG_SZ")
                .map(|(_, name)| name.trim().to_owned())
        })
        .unwrap_or_default();
    let reference = query.status.success()
        && computer.eq_ignore_ascii_case(RESOURCE_REFERENCE_COMPUTER)
        && processor.contains("Ryzen 9 3900X");
    serde_json::json!({"computer_name":computer,"processor_name":processor,
        "label":if reference {"reference PC HB9BLA (AMD Ryzen 9 3900X, 32 GB, Windows 11)"} else {"supplemental, not reference"}})
}
const RESOURCE_REFERENCE_COMPUTER: &str = "DESKTOP-HB9BLA";
pub fn resource_hash(path: &Path) -> String {
    let output = resource_capture(Command::new(resource_python()).args(["-c", "import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())"])
        .arg(path),10);
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap().trim().to_owned()
}
pub fn resource_metrics_source_identity() -> Value {
    let output = resource_capture(
        Command::new(resource_python())
            .args(["-c", "import hashlib,json,pathlib,sys; raw=pathlib.Path(sys.argv[1]).read_bytes(); canonical=raw.replace(b'\\r\\n',b'\\n'); assert b'\\r' not in canonical, 'bare CR is not an admitted source representation'; print(json.dumps({'raw_sha256':hashlib.sha256(raw).hexdigest(),'canonical_lf_sha256':hashlib.sha256(canonical).hexdigest()}))"])
            .arg(resource_helper()),
        10,
    );
    assert!(output.status.success());
    serde_json::from_slice(&output.stdout).unwrap()
}
pub fn resource_source() -> String {
    let clean = resource_capture(
        Command::new("git")
            .arg("-C")
            .arg(env!("CARGO_MANIFEST_DIR"))
            .args(["status", "--porcelain"]),
        10,
    );
    assert!(
        clean.status.success() && clean.stdout.is_empty(),
        "resource evidence requires clean committed candidate"
    );
    let output = resource_capture(
        Command::new("git")
            .arg("-C")
            .arg(env!("CARGO_MANIFEST_DIR"))
            .args(["rev-parse", "HEAD"]),
        10,
    );
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap().trim().to_owned()
}
pub fn resource_sample(
    monitor: &mut ResourcePeer,
    sequence: u64,
    pid: u32,
    creation: u64,
) -> Value {
    monitor.send(serde_json::json!({"op":"sample","id":sequence}));
    let value = monitor.receive(10);
    assert_eq!(value["pid"], pid);
    assert_eq!(value["creation_filetime"], creation);
    assert_eq!(value["id"], sequence);
    assert_eq!(value["unit"], "bytes");
    assert!(value["private_usage"].as_u64().unwrap() > 0);
    assert!(value["lifetime_peak_commit"].as_u64().unwrap() > 0);
    value
}
#[cfg(windows)]
pub fn resource_borrowed_child_handle(child: &Child) -> u64 {
    use std::os::windows::io::AsRawHandle;
    child.as_raw_handle() as usize as u64
}
#[cfg(not(windows))]
pub fn resource_borrowed_child_handle(_child: &Child) -> u64 {
    panic!("Windows owned-process handle qualification required")
}
pub fn resource_bind_monitor(worker: &ResourcePeer) -> (ResourcePeer, u64) {
    assert!(worker.child.id() > 0);
    let mut command = Command::new(resource_python());
    command.arg(resource_helper()).args([
        "--pid",
        &worker.child.id().to_string(),
        "--parent-handle",
        &resource_borrowed_child_handle(&worker.child).to_string(),
    ]);
    let monitor = ResourcePeer::spawn(&mut command, false);
    let bound = monitor.receive(10);
    assert_eq!(bound["state"], "bound");
    assert_eq!(bound["pid"], worker.child.id());
    let creation = bound["creation_filetime"].as_u64().unwrap();
    assert!(creation > 0);
    (monitor, creation)
}
pub fn resource_qualify_round(dispatch: &[u64], replies: &[Value]) -> Value {
    const SKEW_NS: u64 = 50_000_000;
    const CLOCK_MARGIN_NS: u64 = 5_000_000;
    assert!(
        matches!(replies.len(), 1 | 4) && dispatch.len() == replies.len(),
        "actual one/four round cardinality"
    );
    assert!(
        dispatch.windows(2).all(|pair| pair[1] >= pair[0]),
        "monotonic release timestamps"
    );
    let dispatch_skew = dispatch.last().unwrap() - dispatch.first().unwrap();
    assert!(
        dispatch_skew <= SKEW_NS,
        "barrier release qualification exceeds50ms"
    );
    let mut starts = Vec::new();
    let mut ends = Vec::new();
    let mut differences = Vec::new();
    for reply in replies {
        let start = reply["started_unix_ns"].as_u64().unwrap();
        let end = reply["ended_unix_ns"].as_u64().unwrap();
        let duration = reply["monotonic_duration_ns"].as_u64().unwrap();
        assert!(
            start > 0 && duration > 0 && end >= start,
            "real completed interval"
        );
        let difference = (end - start).abs_diff(duration);
        assert!(
            difference <= CLOCK_MARGIN_NS,
            "wall/monotonic clock qualification exceeds5ms"
        );
        let seconds = reply["seconds"].as_f64().unwrap();
        assert!(
            seconds.is_finite() && ((seconds * 1e9) - duration as f64).abs() <= 1.,
            "same monotonic duration in both representations"
        );
        starts.push(start);
        ends.push(end);
        differences.push(difference);
    }
    let latest_start = *starts.iter().max().unwrap();
    let earliest_start = *starts.iter().min().unwrap();
    let start_spread = latest_start - earliest_start;
    assert!(
        start_spread <= SKEW_NS,
        "actual four-worker start spread exceeds50ms qualification"
    );
    let overlap = if replies.len() == 4 {
        let lower = latest_start.checked_add(CLOCK_MARGIN_NS).unwrap();
        let upper = ends.iter().min().unwrap().saturating_sub(CLOCK_MARGIN_NS);
        assert!(
            upper > lower,
            "four actual kernel intervals have no qualified common overlap"
        );
        Some(upper - lower)
    } else {
        None
    };
    serde_json::json!({"qualified":true,"workers":replies.len(),"dispatch_skew_ns":dispatch_skew,
        "actual_start_spread_ns":start_spread,"wall_monotonic_discrepancy_ns":differences,
        "boundary_margin_ns":CLOCK_MARGIN_NS,"qualified_common_overlap_ns":overlap,
        "measurement_qualification_only":true,"padding_or_serialized_work_used":false})
}
