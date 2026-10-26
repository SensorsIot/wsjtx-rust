//! Exclusive, overlapped serial I/O. This value stays on the CAT actor thread.
use super::{Configuration, Error, Result, executor::Transport};
use ::windows::{
    Win32::{
        Devices::Communication::*,
        Foundation::*,
        Storage::FileSystem::*,
        System::{IO::*, Threading::*},
    },
    core::{HRESULT, PCWSTR},
};
use std::{
    fs::{File, OpenOptions},
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

struct Pending {
    overlapped: Box<OVERLAPPED>,
    buffer: Vec<u8>,
    event: HANDLE,
}
impl Pending {
    fn new(buffer: Vec<u8>) -> Result<Self> {
        // SAFETY: unnamed manual-reset event with no security descriptor or borrowed state.
        let event = unsafe { CreateEventW(None, true, false, None) }.map_err(map)?;
        Ok(Self {
            overlapped: Box::new(OVERLAPPED {
                hEvent: event,
                ..Default::default()
            }),
            buffer,
            event,
        })
    }
}
impl Drop for Pending {
    fn drop(&mut self) {
        // SAFETY: Pending is destroyed only after kernel completion, or deliberately retained.
        let _ = unsafe { CloseHandle(self.event) };
    }
}
pub struct SerialTransport {
    handle: Option<HANDLE>,
    pending: Option<Pending>,
    identity: String,
    ownership: Option<File>,
}
#[derive(Debug)]
pub struct SerialEndpoint {
    pub port: u16,
    pub instance_id: String,
    interface_path: Vec<u16>,
}
struct Devices(::windows::Win32::Devices::DeviceAndDriverInstallation::HDEVINFO);
impl Drop for Devices {
    fn drop(&mut self) {
        // SAFETY: sole ownership of the device information set, never a serial handle.
        let _ = unsafe {
            ::windows::Win32::Devices::DeviceAndDriverInstallation::SetupDiDestroyDeviceInfoList(
                self.0,
            )
        };
    }
}
/// Read-only exact COM-name discovery. Never opens a UART or changes its lines.
pub fn resolve_endpoint(port: u16) -> Result<SerialEndpoint> {
    use ::windows::Win32::Devices::{
        DeviceAndDriverInstallation::*, Properties::DEVPROP_TYPE_STRING,
        SerialCommunication::DEVPKEY_DeviceInterface_Serial_PortName,
    };
    if !(1..=256).contains(&port) {
        return Err(Error::InvalidConfiguration);
    }
    // GUID_DEVINTERFACE_COMPORT from Microsoft's serial device-interface contract.
    let class = ::windows::core::GUID::from_u128(0x86e0d1e0_8089_11d0_9ce4_08003e301f73);
    // SAFETY: valid class GUID, present interfaces only, no window or device activation.
    let set = Devices(
        unsafe {
            SetupDiGetClassDevsW(
                Some(&class),
                PCWSTR::null(),
                None,
                DIGCF_PRESENT | DIGCF_DEVICEINTERFACE,
            )
        }
        .map_err(map)?,
    );
    let expected = format!("COM{port}");
    let mut selected = None;
    for index in 0..256 {
        let mut interface = SP_DEVICE_INTERFACE_DATA {
            cbSize: std::mem::size_of::<SP_DEVICE_INTERFACE_DATA>() as u32,
            ..Default::default()
        };
        // SAFETY: correctly sized output; information set and GUID remain live.
        if let Err(error) =
            unsafe { SetupDiEnumDeviceInterfaces(set.0, None, &class, index, &mut interface) }
        {
            if error.code() == HRESULT::from_win32(ERROR_NO_MORE_ITEMS.0) {
                return selected.ok_or(Error::Unavailable);
            }
            return Err(map(error));
        }
        let mut kind = DEVPROP_TYPE_STRING;
        let mut property = [0u8; 64];
        let mut required = 0;
        // SAFETY: bounded property buffer; exact serial PortName key, never friendly-name matching.
        if unsafe {
            SetupDiGetDeviceInterfacePropertyW(
                set.0,
                &interface,
                &DEVPKEY_DeviceInterface_Serial_PortName,
                &mut kind,
                Some(&mut property),
                Some(&mut required),
                0,
            )
        }
        .is_err()
        {
            continue;
        }
        if kind != DEVPROP_TYPE_STRING || !(2..=64).contains(&required) || required % 2 != 0 {
            continue;
        }
        let units: Vec<u16> = property[..required as usize]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|v| u16::from_le_bytes([v[0], v[1]]))
            .collect();
        if units.last() != Some(&0)
            || String::from_utf16(&units[..units.len() - 1])
                .ok()
                .as_deref()
                != Some(expected.as_str())
        {
            continue;
        }
        if selected.is_some() {
            return Err(Error::ResourceInUse);
        }
        let mut required = 0;
        // SAFETY: size query only; returned size is bounded before allocation.
        let _ = unsafe {
            SetupDiGetDeviceInterfaceDetailW(set.0, &interface, None, 0, Some(&mut required), None)
        };
        if !(8..=8192).contains(&required) {
            return Err(Error::Limit);
        }
        let mut storage = vec![0usize; (required as usize).div_ceil(std::mem::size_of::<usize>())];
        let detail = storage
            .as_mut_ptr()
            .cast::<SP_DEVICE_INTERFACE_DETAIL_DATA_W>();
        let mut device = SP_DEVINFO_DATA {
            cbSize: std::mem::size_of::<SP_DEVINFO_DATA>() as u32,
            ..Default::default()
        };
        // SAFETY: aligned allocation contains at least required bytes; records belong to same set.
        unsafe {
            (*detail).cbSize = std::mem::size_of::<SP_DEVICE_INTERFACE_DETAIL_DATA_W>() as u32;
            SetupDiGetDeviceInterfaceDetailW(
                set.0,
                &interface,
                Some(detail),
                required,
                None,
                Some(&mut device),
            )
            .map_err(map)?;
        }
        let mut id = [0u16; 1024];
        // SAFETY: bounded initialized ID buffer and device record obtained from this set.
        unsafe { SetupDiGetDeviceInstanceIdW(set.0, &device, Some(&mut id), None) }.map_err(map)?;
        let end = id.iter().position(|v| *v == 0).ok_or(Error::Limit)?;
        let instance_id = String::from_utf16(&id[..end]).map_err(|_| Error::Protocol)?;
        if instance_id.is_empty() {
            return Err(Error::Protocol);
        }
        // SAFETY: successful detail query provides the UTF-16 path in this owned allocation.
        let path = unsafe {
            std::slice::from_raw_parts((*detail).DevicePath.as_ptr(), (required as usize - 4) / 2)
        };
        let end = path.iter().position(|v| *v == 0).ok_or(Error::Protocol)?;
        selected = Some(SerialEndpoint {
            port,
            instance_id,
            interface_path: path[..=end].to_vec(),
        });
    }
    Err(Error::Limit)
}
pub(crate) fn claim_identity(identity: &str, lock_root: &Path) -> Result<File> {
    if identity.is_empty() || identity.len() > 1024 {
        return Err(Error::InvalidConfiguration);
    }
    std::fs::create_dir_all(lock_root).map_err(|_| Error::Unavailable)?;
    // Reversible encoding avoids hashing collisions and filesystem metacharacters.
    let name: String = identity
        .to_ascii_uppercase()
        .as_bytes()
        .iter()
        .map(|v| format!("{v:02x}"))
        .collect();
    let mut path = lock_root.to_path_buf();
    for chunk in name.as_bytes().chunks(120) {
        path.push(std::str::from_utf8(chunk).map_err(|_| Error::InvalidConfiguration)?);
    }
    std::fs::create_dir_all(&path).map_err(|_| Error::Unavailable)?;
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(path.join("owner.lock"))
        .map_err(|_| Error::Unavailable)?;
    file.try_lock().map_err(|error| match error {
        std::fs::TryLockError::WouldBlock => Error::ResourceInUse,
        std::fs::TryLockError::Error(_) => Error::Unavailable,
    })?;
    Ok(file)
}
impl SerialTransport {
    #[cfg(test)]
    #[allow(
        dead_code,
        reason = "Only the native fixture target consumes this private test constructor"
    )]
    pub(crate) fn from_owned_test_handle(handle: std::os::windows::io::OwnedHandle) -> Self {
        use std::os::windows::io::IntoRawHandle;
        Self {
            handle: Some(HANDLE(handle.into_raw_handle())),
            pending: None,
            identity: "owned-test-pipe".into(),
            ownership: None,
        }
    }

    /// Resolve the selected endpoint and open its immutable OS interface path.
    pub fn open(
        configuration: &Configuration,
        lock_root: &Path,
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> Result<Self> {
        configuration.validate()?;
        check(deadline, cancel)?;
        let endpoint = resolve_endpoint(configuration.port)?;
        check(deadline, cancel)?;
        let identity = endpoint.instance_id;
        let ownership = claim_identity(&identity, lock_root)?;
        check(deadline, cancel)?;
        // SAFETY: validated COM path is NUL-terminated; exclusive access, no inherited handle.
        // Physical USB SEND/CW/RTTY inhibit must be verified before calling open.
        let handle = unsafe {
            CreateFileW(
                PCWSTR(endpoint.interface_path.as_ptr()),
                GENERIC_READ.0 | GENERIC_WRITE.0,
                FILE_SHARE_MODE(0),
                None,
                OPEN_EXISTING,
                FILE_FLAG_OVERLAPPED,
                None,
            )
        }
        .map_err(map)?;
        let mut result = Self {
            handle: Some(handle),
            pending: None,
            identity,
            ownership: Some(ownership),
        };
        if let Err(error) = check(deadline, cancel).and_then(|_| result.configure(9600)) {
            if result.close().is_err() {
                return Err(Error::FailedClose);
            }
            return Err(error);
        }
        Ok(result)
    }
    fn handle(&self) -> Result<HANDLE> {
        self.handle.ok_or(Error::Unavailable)
    }
    fn finish(&mut self, deadline: Instant, cancel: &AtomicBool) -> Result<usize> {
        let handle = self.handle()?;
        let mut aborted = None;
        let mut abort_deadline = None;
        loop {
            let pending = self.pending.as_mut().ok_or(Error::Protocol)?;
            let mut transferred = 0;
            // SAFETY: pinned heap OVERLAPPED and buffer remain owned until completion.
            let result = unsafe {
                GetOverlappedResult(handle, &*pending.overlapped, &mut transferred, false)
            };
            match result {
                Ok(()) => return aborted.map_or(Ok(transferred as usize), Err),
                Err(error) if error.code() == HRESULT::from_win32(ERROR_IO_INCOMPLETE.0) => {}
                Err(error) if error.code() == HRESULT::from_win32(ERROR_OPERATION_ABORTED.0) => {
                    return Err(aborted.unwrap_or(Error::Cancelled));
                }
                Err(error) => return Err(map(error)),
            }
            if aborted.is_none()
                && let Err(error) = check(deadline, cancel)
            {
                aborted = Some(error);
                abort_deadline = Some(Instant::now() + Duration::from_millis(250));
                // SAFETY: exact pending operation belongs to this live handle and thread.
                let _ = unsafe { CancelIoEx(handle, Some(&*pending.overlapped)) };
            }
            if abort_deadline.is_some_and(|end| Instant::now() >= end) {
                return Err(Error::FailedClose);
            }
            // SAFETY: event remains owned by pending, which cannot be dropped during this wait.
            let wait = unsafe { WaitForSingleObject(pending.event, 20) };
            if wait == WAIT_FAILED {
                return Err(Error::FailedClose);
            }
        }
    }
    fn io(
        &mut self,
        buffer: Vec<u8>,
        read: bool,
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> Result<(usize, Vec<u8>)> {
        check(deadline, cancel)?;
        if self.pending.is_some() {
            return Err(Error::FailedClose);
        }
        let handle = self.handle()?;
        self.pending = Some(Pending::new(buffer)?);
        let pending = self.pending.as_mut().ok_or(Error::Protocol)?;
        // SAFETY: owned buffer and pinned OVERLAPPED are retained through all completion paths.
        let started = unsafe {
            if read {
                ReadFile(
                    handle,
                    Some(&mut pending.buffer),
                    None,
                    Some(&mut *pending.overlapped),
                )
            } else {
                WriteFile(
                    handle,
                    Some(&pending.buffer),
                    None,
                    Some(&mut *pending.overlapped),
                )
            }
        };
        if let Err(error) = started
            && error.code() != HRESULT::from_win32(ERROR_IO_PENDING.0)
        {
            self.pending.take();
            return Err(map(error));
        }
        let result = self.finish(deadline, cancel);
        if result == Err(Error::FailedClose) {
            return Err(Error::FailedClose);
        }
        let pending = self.pending.take().ok_or(Error::Protocol)?;
        result.map(|count| (count, pending.buffer.clone()))
    }
}
impl Transport for SerialTransport {
    fn physical_identity(&self) -> Option<&str> {
        Some(&self.identity)
    }
    fn configure(&mut self, baud: u32) -> Result<()> {
        if ![4800, 9600, 19200, 38400, 57600, 115200].contains(&baud) {
            return Err(Error::InvalidConfiguration);
        }
        if self.pending.is_some() {
            return Err(Error::FailedClose);
        }
        let handle = self.handle()?;
        let expected = DCB {
            DCBlength: std::mem::size_of::<DCB>() as u32,
            BaudRate: baud,
            _bitfield: 1,
            ByteSize: 8,
            Parity: NOPARITY,
            StopBits: ONESTOPBIT,
            XonChar: 0x11,
            XoffChar: 0x13,
            ..Default::default()
        };
        let timeouts = COMMTIMEOUTS {
            ReadIntervalTimeout: u32::MAX,
            ReadTotalTimeoutConstant: 20,
            ReadTotalTimeoutMultiplier: 0,
            WriteTotalTimeoutConstant: 0,
            WriteTotalTimeoutMultiplier: 0,
        };
        let mut actual = DCB {
            DCBlength: expected.DCBlength,
            ..Default::default()
        };
        let mut actual_timeouts = COMMTIMEOUTS::default();
        // SAFETY: live exclusive serial handle; all fixed-size structures valid and initialized.
        unsafe {
            SetCommState(handle, &expected).map_err(map)?;
            SetCommTimeouts(handle, &timeouts).map_err(map)?;
            GetCommState(handle, &mut actual).map_err(map)?;
            GetCommTimeouts(handle, &mut actual_timeouts).map_err(map)?;
        }
        if actual.BaudRate != baud
            || actual.ByteSize != 8
            || actual.Parity != NOPARITY
            || actual.StopBits != ONESTOPBIT
            || actual._bitfield != 1
            || actual_timeouts != timeouts
        {
            return Err(Error::Unavailable);
        }
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize> {
        if bytes.len() > 32 {
            return Err(Error::Limit);
        }
        self.io(bytes.to_vec(), false, deadline, cancel)
            .map(|v| v.0)
    }
    fn read(&mut self, bytes: &mut [u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize> {
        if bytes.len() > 256 {
            return Err(Error::Limit);
        }
        let (count, data) = self.io(vec![0; bytes.len()], true, deadline, cancel)?;
        if count > bytes.len() {
            return Err(Error::Protocol);
        }
        bytes[..count].copy_from_slice(&data[..count]);
        Ok(count)
    }
    fn quiet(&mut self, deadline: Instant, cancel: &AtomicBool) -> Result<()> {
        let mut bytes = [0; 256];
        let mut total = 0;
        while Instant::now() < deadline {
            match self.read(&mut bytes, deadline, cancel) {
                Ok(count) => {
                    total += count;
                    if total > 4096 {
                        return Err(Error::Limit);
                    }
                }
                Err(Error::Timeout) => return Ok(()),
                Err(error) => return Err(error),
            }
        }
        if cancel.load(Ordering::Acquire) {
            Err(Error::Cancelled)
        } else {
            Ok(())
        }
    }
    fn close(&mut self) -> Result<()> {
        if self.pending.is_some() {
            let cancel = AtomicBool::new(true);
            if self.finish(Instant::now(), &cancel) == Err(Error::FailedClose) {
                return Err(Error::FailedClose);
            }
            self.pending.take();
        }
        if let Some(handle) = self.handle {
            // SAFETY: no outstanding operation; this thread is the sole handle owner.
            unsafe { CloseHandle(handle) }.map_err(|_| Error::FailedClose)?;
            self.handle = None;
        }
        self.ownership.take();
        Ok(())
    }
}
impl Drop for SerialTransport {
    fn drop(&mut self) {
        if self.close().is_err() {
            // An unacknowledged kernel operation retains memory, handle and lease until process exit.
            if let Some(pending) = self.pending.take() {
                std::mem::forget(pending)
            }
            if let Some(lease) = self.ownership.take() {
                std::mem::forget(lease)
            }
        }
    }
}
fn check(deadline: Instant, cancel: &AtomicBool) -> Result<()> {
    if cancel.load(Ordering::Acquire) {
        Err(Error::Cancelled)
    } else if Instant::now() >= deadline {
        Err(Error::Timeout)
    } else {
        Ok(())
    }
}
fn map(error: ::windows::core::Error) -> Error {
    if [ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION]
        .iter()
        .any(|v| error.code() == HRESULT::from_win32(v.0))
    {
        Error::ResourceInUse
    } else {
        Error::Unavailable
    }
}
