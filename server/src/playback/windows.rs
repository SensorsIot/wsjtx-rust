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
        if endpoint_id.is_empty() || endpoint_id.len() > 2048 || endpoint_id.contains('\0') {
            return Err(OutputError::Unavailable);
        }
        let shared = Arc::new(Shared {
            program: Mutex::new(None),
            state: Mutex::new(OutputState::Opening),
            stop: AtomicBool::new(false),
        });
        let (opened_tx, opened) = mpsc::sync_channel(1);
        let id = endpoint_id.to_owned();
        let worker = shared.clone();
        let thread = thread::Builder::new()
            .name("transmit-output".into())
            .spawn(move || {
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
        match opened.recv_timeout(Duration::from_secs(1)) {
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
    pub fn state(&self) -> OutputState {
        self.shared
            .state
            .lock()
            .map(|s| *s)
            .unwrap_or(OutputState::Failed(OutputError::DeviceLost))
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
                200_000,
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
        writer.GetBuffer(capacity).map_err(lost)?;
        writer.ReleaseBuffer(capacity, silent).map_err(lost)?;
        client.Start().map_err(|_| OutputError::Unavailable)?;
        *shared.state.lock().map_err(|_| OutputError::Unavailable)? = OutputState::Ready;
        let _ = opened.try_send(Ok(()));
        let frame_bytes = format.frame_bytes();
        let result = (|| {
            while !shared.stop.load(Ordering::Acquire) {
                if WaitForSingleObject(event.0, 10) == WAIT_FAILED {
                    return Err(OutputError::DeviceLost);
                }
                let padding = client.GetCurrentPadding().map_err(lost)?;
                let available = capacity.saturating_sub(padding);
                let mut program = shared.program.lock().map_err(|_| OutputError::DeviceLost)?;
                let drained = program.as_ref().is_some_and(Renderer::exhausted);
                if drained && padding == 0 {
                    *program = None;
                    *shared.state.lock().map_err(|_| OutputError::DeviceLost)? =
                        OutputState::Finished;
                }
                if available == 0 {
                    continue;
                }
                let buffer = writer.GetBuffer(available).map_err(lost)?;
                match program.as_mut().filter(|p| !p.exhausted()) {
                    Some(renderer) => {
                        let bytes = std::slice::from_raw_parts_mut(
                            buffer,
                            available as usize * frame_bytes,
                        );
                        renderer.fill(format, bytes, available as usize);
                        writer.ReleaseBuffer(available, 0).map_err(lost)?;
                    }
                    None => writer.ReleaseBuffer(available, silent).map_err(lost)?,
                }
            }
            Ok(())
        })();
        let stopped = client.Stop().map_err(lost);
        result.and(stopped)
    }
}

/// WstxTransmit::TransmitClock: Some(true) when Windows reports that a time service is
/// disciplining the system clock (time adjustment enabled), Some(false) when it is not,
/// None when the query fails.
pub fn system_time_disciplined() -> Option<bool> {
    let (mut adjustment, mut increment) = (0u64, 0u64);
    let mut disabled = ::windows::core::BOOL(1);
    // SAFETY: writable stack outputs of a documented process-wide query.
    unsafe {
        ::windows::Win32::System::SystemInformation::GetSystemTimeAdjustmentPrecise(
            &mut adjustment,
            &mut increment,
            &mut disabled,
        )
        .ok()?;
    }
    Some(!disabled.as_bool())
}
