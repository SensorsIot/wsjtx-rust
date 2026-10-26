//! Windows COM objects never leave the capture thread. No default endpoint selection.
use super::*;
use ::windows::{
    Win32::{
        Foundation::{CloseHandle, HANDLE, WAIT_FAILED},
        Media::Audio::*,
        System::{
            Com::*, Performance::*, SystemInformation::GetSystemTimePreciseAsFileTime, Threading::*,
        },
    },
    core::PCWSTR,
};
use std::sync::mpsc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub struct InputDevice {
    pub id: String,
    pub name: String,
}
struct Apartment;
impl Apartment {
    fn new() -> Result<Self, SourceError> {
        // SAFETY: balanced initialization on this calling thread only.
        unsafe {
            CoInitializeEx(None, COINIT_MULTITHREADED)
                .ok()
                .map_err(|_| SourceError::Unavailable)?;
        }
        Ok(Self)
    }
}
impl Drop for Apartment {
    fn drop(&mut self) {
        // SAFETY: matching successful thread-local initialization.
        unsafe {
            CoUninitialize();
        }
    }
}
struct Event {
    handle: HANDLE,
    wake: Arc<Mutex<Option<usize>>>,
}
impl Drop for Event {
    fn drop(&mut self) {
        // SAFETY: sole owner, capture use ends before this drop.
        if let Ok(mut wake) = self.wake.lock() {
            *wake = None;
        }
        let _ = unsafe { CloseHandle(self.handle) };
    }
}
struct Mix(*mut WAVEFORMATEX);
impl Drop for Mix {
    fn drop(&mut self) {
        // SAFETY: pointer was allocated by GetMixFormat with COM task allocator.
        unsafe {
            CoTaskMemFree(Some(self.0.cast()));
        }
    }
}
fn enumerator() -> Result<IMMDeviceEnumerator, SourceError> {
    // SAFETY: caller has initialized COM; requested class/interface match.
    unsafe {
        CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)
            .map_err(|_| SourceError::Unavailable)
    }
}
pub fn enumerate_inputs() -> Result<Vec<InputDevice>, SourceError> {
    let _apartment = Apartment::new()?;
    let enumerator = enumerator()?;
    // SAFETY: live local interfaces, valid capture/active flags; returned IDs freed once.
    unsafe {
        let collection = enumerator
            .EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE)
            .map_err(|_| SourceError::Unavailable)?;
        let mut result = Vec::new();
        for i in 0..collection
            .GetCount()
            .map_err(|_| SourceError::Unavailable)?
        {
            let device = collection.Item(i).map_err(|_| SourceError::Unavailable)?;
            let id = device.GetId().map_err(|_| SourceError::Unavailable)?;
            let text = id.to_string().map_err(|_| SourceError::Unavailable);
            CoTaskMemFree(Some(id.0.cast()));
            let text = text?;
            let store = device
                .OpenPropertyStore(STGM_READ)
                .map_err(|_| SourceError::Unavailable)?;
            let mut value = store
                .GetValue(&::windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName)
                .map_err(|_| SourceError::Unavailable)?;
            let label =
                ::windows::Win32::System::Com::StructuredStorage::PropVariantToStringAlloc(&value);
            let _ = ::windows::Win32::System::Com::StructuredStorage::PropVariantClear(&mut value);
            let name = match label {
                Ok(name) => {
                    let result = name.to_string();
                    CoTaskMemFree(Some(name.0.cast()));
                    result.map_err(|_| SourceError::Unavailable)?
                }
                Err(_) => return Err(SourceError::Unavailable),
            };
            result.push(InputDevice { id: text, name });
        }
        Ok(result)
    }
}
/// Provider-independent system correlation; external UTC accuracy remains unknown.
pub fn system_clock() -> Option<ClockCorrelation> {
    // SAFETY: writable stack outputs, documented process-wide QPC/time APIs.
    unsafe {
        let (mut frequency, mut before, mut after) = (0, 0, 0);
        QueryPerformanceFrequency(&mut frequency).ok()?;
        if frequency <= 0 {
            return None;
        }
        QueryPerformanceCounter(&mut before).ok()?;
        let utc = GetSystemTimePreciseAsFileTime();
        QueryPerformanceCounter(&mut after).ok()?;
        let scale = |n: i64| u64::try_from(i128::from(n) * 10_000_000 / i128::from(frequency)).ok();
        ClockCorrelation::bracket(
            scale(before)?,
            (u64::from(utc.dwHighDateTime) << 32) | u64::from(utc.dwLowDateTime),
            scale(after)?,
        )
    }
}
fn format(mix: &Mix) -> Result<NativeFormat, SourceError> {
    // SAFETY: GetMixFormat owns WAVEFORMATEX plus its cbSize bytes until Mix drops.
    unsafe {
        let base = std::ptr::read_unaligned(mix.0);
        NativeFormat::from_wave_format(std::slice::from_raw_parts(
            mix.0.cast(),
            18 + usize::from(base.cbSize),
        ))
    }
}
/// Owns cancellation and join acknowledgement, never an apartment-bound COM interface.
pub struct CaptureHandle {
    queue: Option<Arc<PacketQueue>>,
    thread: Option<JoinHandle<()>>,
    opened: mpsc::Receiver<Result<(Arc<PacketQueue>, NativeFormat), SourceError>>,
    done: mpsc::Receiver<Result<(), SourceError>>,
    cancel: Arc<AtomicBool>,
    wake: Arc<Mutex<Option<usize>>>,
    finished: Option<Result<(), SourceError>>,
}
impl CaptureHandle {
    pub fn begin(endpoint_id: &str) -> Result<Self, SourceError> {
        if endpoint_id.is_empty() || endpoint_id.len() > 2048 || endpoint_id.contains('\0') {
            return Err(SourceError::Unavailable);
        }
        let id = endpoint_id.to_owned();
        let (started_tx, opened) = mpsc::sync_channel(1);
        let (done_tx, done) = mpsc::sync_channel(1);
        let cancel = Arc::new(AtomicBool::new(false));
        let thread_cancel = cancel.clone();
        let wake = Arc::new(Mutex::new(None));
        let thread_wake = wake.clone();
        let thread = thread::Builder::new()
            .name("radio-capture".into())
            .spawn(move || {
                let result = capture(&id, started_tx, thread_cancel, thread_wake);
                let _ = done_tx.send(result);
            })
            .map_err(|_| SourceError::Unavailable)?;
        Ok(Self {
            queue: None,
            thread: Some(thread),
            opened,
            done,
            cancel,
            wake,
            finished: None,
        })
    }
    pub fn poll_open(&mut self) -> Option<Result<(Arc<PacketQueue>, NativeFormat), SourceError>> {
        match self.opened.try_recv() {
            Ok(Ok((queue, format))) => {
                self.queue = Some(queue.clone());
                Some(Ok((queue, format)))
            }
            Ok(Err(e)) => Some(Err(e)),
            Err(mpsc::TryRecvError::Empty) => None,
            Err(mpsc::TryRecvError::Disconnected) => Some(Err(SourceError::Unavailable)),
        }
    }
    pub fn request_stop(&self) {
        self.cancel.store(true, Ordering::Release);
        if let Ok(wake) = self.wake.lock()
            && let Some(raw) = *wake
        {
            // SAFETY: the event owner clears this slot under the same mutex before closing it.
            let _ = unsafe { SetEvent(HANDLE(raw as *mut std::ffi::c_void)) };
        }
        if let Some(queue) = &self.queue {
            queue.cancel();
        }
    }
    /// Nonblocking close acknowledgement. A failed Stop remains a retained lease.
    pub fn poll_close(&mut self) -> Option<Result<(), SourceError>> {
        if self.finished.is_none()
            && let Ok(result) = self.done.try_recv()
        {
            self.finished = Some(result);
        }
        if self
            .thread
            .as_ref()
            .is_some_and(|thread| thread.is_finished())
            && let Some(thread) = self.thread.take()
            && thread.join().is_err()
        {
            self.finished = Some(Err(SourceError::FailedClose));
        }
        if self.thread.is_some() {
            None
        } else {
            self.finished
        }
    }
    pub fn stop(&mut self) -> Result<(), SourceError> {
        self.request_stop();
        let start = Instant::now();
        loop {
            if let Some(result) = self.poll_close() {
                return result;
            }
            if start.elapsed() >= Duration::from_millis(250) {
                return Err(SourceError::FailedClose);
            }
            thread::sleep(Duration::from_millis(1));
        }
    }
}
impl Drop for CaptureHandle {
    fn drop(&mut self) {
        self.request_stop();
        let _ = self.poll_close();
    }
}

/// Independent audio lifecycle. Opening/closing never block the receive worker.
pub struct AudioController {
    endpoint_id: String,
    lifecycle: Lifecycle,
    handle: Option<CaptureHandle>,
    live: Option<LiveSource>,
    epochs: EpochLatch,
    origin: Instant,
    failure_reported: bool,
}
impl AudioController {
    pub fn new(endpoint_id: String) -> Result<Self, SourceError> {
        if endpoint_id.is_empty() || endpoint_id.len() > 2048 || endpoint_id.contains('\0') {
            return Err(SourceError::Unavailable);
        }
        Ok(Self {
            endpoint_id,
            lifecycle: Lifecycle::default(),
            handle: None,
            live: None,
            epochs: EpochLatch::default(),
            origin: Instant::now(),
            failure_reported: false,
        })
    }
    fn now(&self) -> u64 {
        u64::try_from(self.origin.elapsed().as_millis()).unwrap_or(u64::MAX)
    }
    pub fn start(&mut self) -> Result<(), SourceError> {
        if self.handle.is_some() || self.lifecycle.wanted {
            return Err(SourceError::Unavailable);
        }
        self.lifecycle.request_start();
        self.failure_reported = false;
        self.open();
        Ok(())
    }
    fn open(&mut self) {
        match CaptureHandle::begin(&self.endpoint_id) {
            Ok(handle) => {
                self.handle = Some(handle);
                self.lifecycle.state = AudioState::Opening;
            }
            Err(error) => self.lifecycle.failed(error, self.now()),
        }
    }
    pub fn status(&self) -> AudioStatus {
        self.lifecycle.status(self.now())
    }
    pub fn selected_endpoint(&self) -> &str {
        &self.endpoint_id
    }
    pub fn request_stop(&mut self) {
        self.lifecycle.request_stop();
        self.failure_reported = false;
        if let Some(live) = &mut self.live {
            live.stop();
        }
        if let Some(handle) = &self.handle {
            handle.request_stop();
        } else {
            self.lifecycle.closed();
        }
    }
    fn lose(&mut self, error: SourceError) {
        if let Some(mut live) = self.live.take() {
            live.stop();
            self.epochs = std::mem::take(&mut live.epochs);
        }
        if let Some(handle) = &self.handle {
            handle.request_stop();
        }
        self.lifecycle.failed(error, self.now());
        self.failure_reported = false;
    }
    fn service(&mut self) {
        if self.lifecycle.state == AudioState::Opening {
            let result = self.handle.as_mut().and_then(CaptureHandle::poll_open);
            if let Some(result) = result {
                match result {
                    Ok((queue, format)) => match LiveSource::new(queue, format) {
                        Ok(mut live) => {
                            live.epochs = std::mem::take(&mut self.epochs);
                            self.live = Some(live);
                            self.lifecycle.running();
                        }
                        Err(error) => self.lose(error),
                    },
                    Err(error) => self.lose(error),
                }
            }
        }
        if matches!(
            self.lifecycle.state,
            AudioState::Closing | AudioState::Unavailable
        ) && let Some(result) = self.handle.as_mut().and_then(CaptureHandle::poll_close)
        {
            if result == Err(SourceError::FailedClose) {
                self.lifecycle.state = AudioState::Unavailable;
                self.lifecycle.error = Some(SourceError::FailedClose);
                self.lifecycle.retry_at = None;
                return;
            }
            self.handle = None;
            if let Some(mut live) = self.live.take() {
                self.epochs = std::mem::take(&mut live.epochs);
            }
            if !self.lifecycle.wanted {
                self.lifecycle.closed();
            }
        }
        if self.handle.is_none() && self.lifecycle.due(self.now()) {
            self.open();
        }
    }
}
impl SampleSource for AudioController {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        if self.lifecycle.state == AudioState::Running {
            self.live.as_ref().and_then(SampleSource::descriptor)
        } else {
            None
        }
    }
    fn poll(&mut self) -> SourcePoll {
        self.service();
        if self.lifecycle.state == AudioState::Running
            && let Some(live) = &mut self.live
        {
            let result = live.poll();
            if let SourcePoll::Failed(error) = result {
                self.lose(error);
                self.failure_reported = true;
                return SourcePoll::Failed(error);
            }
            return result;
        }
        if self.lifecycle.state == AudioState::Unavailable && !self.failure_reported {
            self.failure_reported = true;
            return SourcePoll::Failed(self.lifecycle.error.unwrap_or(SourceError::Unavailable));
        }
        SourcePoll::Pending
    }
    fn acknowledge_epoch(
        &mut self,
        counter: u64,
        descriptor: Arc<SourceDescriptor>,
        timing: SourceTiming,
    ) -> Result<(), SourceError> {
        if self.lifecycle.state != AudioState::Running {
            return Err(SourceError::StaleAcknowledgement);
        }
        self.live
            .as_mut()
            .ok_or(SourceError::StaleAcknowledgement)?
            .acknowledge_epoch(counter, descriptor, timing)
    }
}
fn capture(
    id: &str,
    started: mpsc::SyncSender<Result<(Arc<PacketQueue>, NativeFormat), SourceError>>,
    cancel: Arc<AtomicBool>,
    wake: Arc<Mutex<Option<usize>>>,
) -> Result<(), SourceError> {
    let mut published = None;
    let result = (|| {
        let _apartment = Apartment::new()?;
        let enumerator = enumerator()?;
        let id: Vec<u16> = id.encode_utf16().chain(Some(0)).collect();
        // SAFETY: NUL-terminated owned ID and local COM interfaces; no automatic conversion flags.
        unsafe {
            let event = Event {
                handle: CreateEventW(None, false, false, None)
                    .map_err(|_| SourceError::Unavailable)?,
                wake: wake.clone(),
            };
            if let Ok(mut slot) = wake.lock() {
                *slot = Some(event.handle.0 as usize);
            }
            let device = enumerator
                .GetDevice(PCWSTR(id.as_ptr()))
                .map_err(|_| SourceError::Unavailable)?;
            let client: IAudioClient = device
                .Activate(CLSCTX_ALL, None)
                .map_err(|_| SourceError::Unavailable)?;
            let mix = Mix(client
                .GetMixFormat()
                .map_err(|_| SourceError::UnsupportedFormat)?);
            if mix.0.is_null() {
                return Err(SourceError::UnsupportedFormat);
            }
            let format = format(&mix)?;
            client
                .Initialize(
                    AUDCLNT_SHAREMODE_SHARED,
                    AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                    1_000_000,
                    0,
                    mix.0,
                    None,
                )
                .map_err(|_| SourceError::Unavailable)?;
            if client
                .GetBufferSize()
                .map_err(|_| SourceError::Unavailable)?
                > format.rate / 2
            {
                return Err(SourceError::UnsupportedFormat);
            }
            client
                .SetEventHandle(event.handle)
                .map_err(|_| SourceError::Unavailable)?;
            let reader: IAudioCaptureClient =
                client.GetService().map_err(|_| SourceError::Unavailable)?;
            let queue = PacketQueue::new(format)?;
            published = Some(queue.clone());
            if cancel.load(Ordering::Acquire) {
                return Err(SourceError::Cancelled);
            }
            client.Start().map_err(|_| SourceError::Unavailable)?;
            if started.send(Ok((queue.clone(), format))).is_err() {
                let _ = client.Stop();
                return Err(SourceError::Cancelled);
            }
            let mut last_clock = system_clock();
            let mut checked = Instant::now();
            let mut failure = None;
            while !cancel.load(Ordering::Acquire) && !queue.cancelled.load(Ordering::Acquire) {
                if WaitForSingleObject(event.handle, 20) == WAIT_FAILED {
                    failure = Some(SourceError::Unavailable);
                    break;
                }
                if checked.elapsed() >= Duration::from_secs(1) {
                    let next = system_clock();
                    if ClockCorrelation::observe(&mut last_clock, next) {
                        queue.loss.store(true, Ordering::Release);
                    }
                    checked = Instant::now();
                }
                loop {
                    if cancel.load(Ordering::Acquire) || queue.cancelled.load(Ordering::Acquire) {
                        break;
                    }
                    let size = match reader.GetNextPacketSize() {
                        Ok(n) => n,
                        Err(_) => {
                            failure = Some(SourceError::Unavailable);
                            break;
                        }
                    };
                    if size == 0 {
                        break;
                    }
                    let (mut ptr, mut frames, mut flags, mut frame, mut qpc) =
                        (std::ptr::null_mut(), 0, 0, 0, 0);
                    if reader
                        .GetBuffer(
                            &mut ptr,
                            &mut frames,
                            &mut flags,
                            Some(&mut frame),
                            Some(&mut qpc),
                        )
                        .is_err()
                    {
                        failure = Some(SourceError::Unavailable);
                        break;
                    }
                    // SAFETY: buffer valid until ReleaseBuffer; SILENT permits a null pointer and is never dereferenced.
                    if frames as usize > MAX_NATIVE_PACKET || (ptr.is_null() && flags & SILENT == 0)
                    {
                        queue.loss.store(true, Ordering::Release);
                    } else {
                        let bytes = if flags & SILENT != 0 {
                            &[][..]
                        } else {
                            std::slice::from_raw_parts(ptr, frames as usize * format.frame_bytes())
                        };
                        queue.push(bytes, frames as usize, frame, qpc, flags);
                    }
                    if reader.ReleaseBuffer(frames).is_err() {
                        failure = Some(SourceError::Unavailable);
                        break;
                    }
                }
                if failure.is_some() {
                    break;
                }
            }
            let stopped = client.Stop().map_err(|_| SourceError::FailedClose);
            if let Some(error) = failure {
                return Err(error);
            }
            stopped
        }
    })();
    if let Err(error) = result {
        if let Some(queue) = published {
            queue.fail(error);
        } else {
            let _ = started.send(Err(error));
        }
    }
    result
}

#[cfg(test)]
impl AudioController {
    /// Software-only driver boundary: no Windows endpoint is opened.
    pub fn packet_fixture(
        endpoint_id: String,
        format: NativeFormat,
    ) -> Result<(Self, Arc<PacketQueue>), SourceError> {
        let queue = PacketQueue::new(format)?;
        let (opened_tx, opened) = mpsc::sync_channel(1);
        let (done_tx, done) = mpsc::sync_channel(1);
        let cancel = Arc::new(AtomicBool::new(false));
        let worker_cancel = cancel.clone();
        let worker_queue = queue.clone();
        let thread = thread::spawn(move || {
            let _ = opened_tx.send(Ok((worker_queue, format)));
            while !worker_cancel.load(Ordering::Acquire) {
                thread::sleep(Duration::from_millis(1));
            }
            let _ = done_tx.send(Ok(()));
        });
        let mut controller = Self::new(endpoint_id)?;
        controller.lifecycle.request_start();
        let wake = Arc::new(Mutex::new(None));
        controller.handle = Some(CaptureHandle {
            queue: Some(queue.clone()),
            thread: Some(thread),
            opened,
            done,
            cancel,
            wake,
            finished: None,
        });
        Ok((controller, queue))
    }
}
