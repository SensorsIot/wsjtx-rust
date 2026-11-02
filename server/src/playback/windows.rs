//! WASAPI shared-mode event-driven render. COM objects never leave the output thread.
//! Exact endpoint ID, no default-device fallback; 48 kHz mix formats only.
use super::*;
use ::windows::{
    Win32::{
        Foundation::{CloseHandle, HANDLE, WAIT_FAILED},
        Media::Audio::*,
        System::{Com::*, Threading::*},
    },
    core::PCWSTR,
};
use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
    mpsc,
};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

struct Shared {
    program: Mutex<Option<Renderer>>,
    state: Mutex<OutputState>,
    stop: AtomicBool,
    /// Milliseconds since `origin` of the last observed device consumption.
    progress_ms: std::sync::atomic::AtomicU64,
    origin: Instant,
}
/// One open output stream. Dropping or `stop` closes it within 250 ms.
pub struct Output {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
}
struct Apartment;
impl Drop for Apartment {
    fn drop(&mut self) {
        // SAFETY: matching successful initialization on this thread.
        unsafe { CoUninitialize() };
    }
}
struct Event(HANDLE);
impl Drop for Event {
    fn drop(&mut self) {
        // SAFETY: sole owner; the render loop has ended.
        let _ = unsafe { CloseHandle(self.0) };
    }
}
struct Mix(*mut WAVEFORMATEX);
impl Drop for Mix {
    fn drop(&mut self) {
        // SAFETY: allocated by GetMixFormat with the COM task allocator.
        unsafe { CoTaskMemFree(Some(self.0.cast())) };
    }
}
impl Output {
    /// Opens `endpoint_id` and starts streaming silence; waits at most 1 s for the open.
    pub fn open(endpoint_id: &str) -> Result<Self, OutputError> {
        Self::open_abortable(endpoint_id, &AtomicBool::new(false))
    }
    /// As `open`; gives up at once when `abort` is set (priority halt).
    pub fn open_abortable(endpoint_id: &str, abort: &AtomicBool) -> Result<Self, OutputError> {
        if endpoint_id.is_empty() || endpoint_id.len() > 2048 || endpoint_id.contains('\0') {
            return Err(OutputError::Unavailable);
        }
        let shared = Arc::new(Shared {
            program: Mutex::new(None),
            state: Mutex::new(OutputState::Opening),
            stop: AtomicBool::new(false),
            progress_ms: std::sync::atomic::AtomicU64::new(0),
            origin: Instant::now(),
        });
        let (opened_tx, opened) = mpsc::sync_channel(1);
        let id = endpoint_id.to_owned();
        let worker = shared.clone();
        let thread = thread::Builder::new()
            .name("transmit-output".into())
            .spawn(move || {
                raise_thread_priority();
                let result = render(&id, &worker, &opened_tx);
                if let Ok(mut state) = worker.state.lock() {
                    *state = match result {
                        Ok(()) => OutputState::Closed,
                        Err(e) => OutputState::Failed(e),
                    };
                }
                let _ = opened_tx.try_send(Err(result.err().unwrap_or(OutputError::Unavailable)));
            })
            .map_err(|_| OutputError::Unavailable)?;
        let mut output = Self {
            shared,
            thread: Some(thread),
        };
        let deadline = Instant::now() + Duration::from_secs(1);
        let received = loop {
            if abort.load(Ordering::Acquire) {
                break Err(mpsc::RecvTimeoutError::Timeout);
            }
            match opened.recv_timeout(Duration::from_millis(5)) {
                Err(mpsc::RecvTimeoutError::Timeout) if Instant::now() < deadline => {}
                other => break other,
            }
        };
        match received {
            Ok(Ok(())) => Ok(output),
            Ok(Err(e)) => {
                output.stop();
                Err(e)
            }
            Err(_) => {
                output.stop();
                Err(OutputError::Unavailable)
            }
        }
    }
    pub fn play(&self, source: Source, scale: f32) -> Result<(), OutputError> {
        match self.state() {
            OutputState::Ready => {}
            OutputState::Failed(e) => return Err(e),
            _ => return Err(OutputError::Unavailable),
        }
        *self
            .shared
            .program
            .lock()
            .map_err(|_| OutputError::Unavailable)? = Some(Renderer::new(source, scale));
        *self
            .shared
            .state
            .lock()
            .map_err(|_| OutputError::Unavailable)? = OutputState::Playing;
        Ok(())
    }
    /// Device state; a render thread that ended, or made no consumption progress for
    /// STALL_MS while playing, is reported lost (render watchdog).
    pub fn state(&self) -> OutputState {
        let state = self
            .shared
            .state
            .lock()
            .map(|s| *s)
            .unwrap_or(OutputState::Failed(OutputError::DeviceLost));
        if state == OutputState::Playing {
            let now = self.shared.origin.elapsed().as_millis() as u64;
            let last = self.shared.progress_ms.load(Ordering::Acquire);
            if self.thread.as_ref().is_none_or(JoinHandle::is_finished)
                || now.saturating_sub(last) > super::STALL_MS
            {
                return OutputState::Failed(OutputError::DeviceLost);
            }
        }
        state
    }
    /// Stops writing program samples at once; callable from any thread.
    pub fn stopper(&self) -> Arc<dyn Fn() + Send + Sync> {
        let shared = self.shared.clone();
        Arc::new(move || {
            if let Ok(mut program) = shared.program.lock() {
                *program = None;
            }
            shared.stop.store(true, Ordering::Release);
        })
    }
    pub fn stop(&mut self) {
        (self.stopper())();
        let start = Instant::now();
        if let Some(thread) = self.thread.take() {
            while !thread.is_finished() && start.elapsed() < Duration::from_millis(250) {
                thread::sleep(Duration::from_millis(1));
            }
            if thread.is_finished() {
                let _ = thread.join();
            }
        }
    }
}
impl Drop for Output {
    fn drop(&mut self) {
        self.stop();
    }
}
fn render(
    id: &str,
    shared: &Shared,
    opened: &mpsc::SyncSender<Result<(), OutputError>>,
) -> Result<(), OutputError> {
    let lost = |_| OutputError::DeviceLost;
    // SAFETY: balanced per-thread COM initialization; every interface stays on this thread.
    unsafe {
        CoInitializeEx(None, COINIT_MULTITHREADED)
            .ok()
            .map_err(|_| OutputError::Unavailable)?;
    }
    let _apartment = Apartment;
    let wide: Vec<u16> = id.encode_utf16().chain(Some(0)).collect();
    // SAFETY: NUL-terminated owned ID, local COM interfaces, buffers used only between
    // GetBuffer and ReleaseBuffer with the frame count the client granted.
    unsafe {
        let event =
            Event(CreateEventW(None, false, false, None).map_err(|_| OutputError::Unavailable)?);
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)
                .map_err(|_| OutputError::Unavailable)?;
        let device = enumerator
            .GetDevice(PCWSTR(wide.as_ptr()))
            .map_err(|_| OutputError::Unavailable)?;
        let client: IAudioClient = device
            .Activate(CLSCTX_ALL, None)
            .map_err(|_| OutputError::Unavailable)?;
        let mix = Mix(client
            .GetMixFormat()
            .map_err(|_| OutputError::UnsupportedFormat)?);
        if mix.0.is_null() {
            return Err(OutputError::UnsupportedFormat);
        }
        let base = std::ptr::read_unaligned(mix.0);
        let format = NativeFormat::from_wave_format(std::slice::from_raw_parts(
            mix.0.cast(),
            18 + usize::from(base.cbSize),
        ))
        .map_err(|_| OutputError::UnsupportedFormat)?;
        if format.rate != 48_000 {
            return Err(OutputError::UnsupportedFormat);
        }
        client
            .Initialize(
                AUDCLNT_SHAREMODE_SHARED,
                AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                // 100-ns units.
                i64::from(super::RENDER_BUFFER_MS) * 10_000,
                0,
                mix.0,
                None,
            )
            .map_err(|_| OutputError::Unavailable)?;
        client
            .SetEventHandle(event.0)
            .map_err(|_| OutputError::Unavailable)?;
        let writer: IAudioRenderClient =
            client.GetService().map_err(|_| OutputError::Unavailable)?;
        let capacity = client
            .GetBufferSize()
            .map_err(|_| OutputError::Unavailable)?;
        let silent = AUDCLNT_BUFFERFLAGS_SILENT.0 as u32;
        let primed = capacity.min(super::SILENCE_FRAMES);
        writer.GetBuffer(primed).map_err(lost)?;
        writer.ReleaseBuffer(primed, silent).map_err(lost)?;
        client.Start().map_err(|_| OutputError::Unavailable)?;
        *shared.state.lock().map_err(|_| OutputError::Unavailable)? = OutputState::Ready;
        let _ = opened.try_send(Ok(()));
        let frame_bytes = format.frame_bytes();
        let now = || shared.origin.elapsed().as_millis() as u64;
        let mut progress = super::Progress::new(now());
        progress.wrote(primed);
        let result = (|| {
            while !shared.stop.load(Ordering::Acquire) {
                if WaitForSingleObject(event.0, 10) == WAIT_FAILED {
                    return Err(OutputError::DeviceLost);
                }
                let padding = client.GetCurrentPadding().map_err(lost)?;
                progress.observe(padding, now());
                shared
                    .progress_ms
                    .store(progress.last_progress_ms(), Ordering::Release);
                let mut program = shared.program.lock().map_err(|_| OutputError::DeviceLost)?;
                match super::plan_fill(program.as_ref(), padding, capacity) {
                    super::Fill::Nothing => {}
                    super::Fill::Finished => {
                        *program = None;
                        *shared.state.lock().map_err(|_| OutputError::DeviceLost)? =
                            OutputState::Finished;
                    }
                    super::Fill::Silence(frames) => {
                        writer.GetBuffer(frames).map_err(lost)?;
                        writer.ReleaseBuffer(frames, silent).map_err(lost)?;
                        progress.wrote(frames);
                    }
                    super::Fill::Program(frames) => {
                        let buffer = writer.GetBuffer(frames).map_err(lost)?;
                        let bytes =
                            std::slice::from_raw_parts_mut(buffer, frames as usize * frame_bytes);
                        if let Some(renderer) = program.as_mut() {
                            renderer.fill(format, bytes, frames as usize);
                        }
                        writer.ReleaseBuffer(frames, 0).map_err(lost)?;
                        progress.wrote(frames);
                    }
                }
            }
            Ok(())
        })();
        let stopped = client.Stop().map_err(lost);
        result.and(stopped)
    }
}

static EXIT_GUARD: std::sync::OnceLock<Box<dyn Fn() + Send + Sync>> = std::sync::OnceLock::new();
unsafe extern "system" fn console_exit(_: u32) -> ::windows::core::BOOL {
    if let Some(guard) = EXIT_GUARD.get() {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(guard));
    }
    // Not handled: the default handler then ends the process as before.
    ::windows::core::BOOL(0)
}
/// WstxTransmit::ExitRelease: runs `guard` (stop audio, one bounded off-only PTT release)
/// on Ctrl+C, Ctrl+Break, console close, logoff and shutdown before the default exit.
pub fn install_exit_guard(guard: Box<dyn Fn() + Send + Sync>) -> bool {
    if EXIT_GUARD.set(guard).is_err() {
        return false;
    }
    // SAFETY: a static handler with the documented signature, registered once.
    unsafe {
        ::windows::Win32::System::Console::SetConsoleCtrlHandler(Some(console_exit), true).is_ok()
    }
}

/// Keeps this real-time audio thread ahead of the parallel decode workers, which use all
/// but one logical CPU at normal priority (#57 CL-057-02; #49 render stalls under load).
fn raise_thread_priority() {
    // SAFETY: GetCurrentThread returns this thread's pseudo-handle, which needs no close;
    // SetThreadPriority changes only this thread's scheduling. A failure keeps the default.
    let _ = unsafe { SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST) };
}
