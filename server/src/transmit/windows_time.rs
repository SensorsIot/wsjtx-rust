//! #92 situation 1: reads the Windows Time (W32Time) service state through the service
//! control manager with query rights only (no administrator rights). Never starts, stops
//! or configures the service.
use super::clock::WindowsTime;
use windows::Win32::System::Services::{
    CloseServiceHandle, OpenSCManagerW, OpenServiceW, QUERY_SERVICE_CONFIGW, QueryServiceConfigW,
    QueryServiceStatus, SC_HANDLE, SC_MANAGER_CONNECT, SERVICE_DISABLED, SERVICE_QUERY_CONFIG,
    SERVICE_QUERY_STATUS, SERVICE_RUNNING, SERVICE_STATUS,
};
use windows::core::{PCWSTR, w};

/// Closes a service control handle when dropped.
struct Handle(SC_HANDLE);
impl Drop for Handle {
    fn drop(&mut self) {
        // SAFETY: the handle was opened by OpenSCManagerW/OpenServiceW and is closed once.
        let _ = unsafe { CloseServiceHandle(self.0) };
    }
}

pub(super) fn query() -> WindowsTime {
    read().unwrap_or(WindowsTime::Unknown)
}

fn read() -> Option<WindowsTime> {
    // SAFETY: null machine and database names select the local active database.
    let manager =
        Handle(unsafe { OpenSCManagerW(PCWSTR::null(), PCWSTR::null(), SC_MANAGER_CONNECT) }.ok()?);
    // SAFETY: a valid manager handle and a static, null-terminated service name.
    let service = Handle(
        unsafe {
            OpenServiceW(
                manager.0,
                w!("W32Time"),
                SERVICE_QUERY_STATUS | SERVICE_QUERY_CONFIG,
            )
        }
        .ok()?,
    );
    let mut status = SERVICE_STATUS::default();
    // SAFETY: a valid service handle opened with SERVICE_QUERY_STATUS and a local struct.
    unsafe { QueryServiceStatus(service.0, &mut status) }.ok()?;
    if status.dwCurrentState == SERVICE_RUNNING {
        return Some(WindowsTime::Running);
    }
    // The configuration and its strings fit 8 KiB (the documented maximum); u64 storage
    // keeps the buffer aligned for QUERY_SERVICE_CONFIGW.
    let mut buffer = vec![0u64; 1024];
    let mut needed = 0u32;
    // SAFETY: the buffer is 8192 bytes, aligned, and outlives the call; the result is
    // read only after success.
    unsafe {
        QueryServiceConfigW(
            service.0,
            Some(buffer.as_mut_ptr().cast::<QUERY_SERVICE_CONFIGW>()),
            8192,
            &mut needed,
        )
    }
    .ok()?;
    // SAFETY: the call succeeded and wrote a QUERY_SERVICE_CONFIGW at the buffer start.
    let config = unsafe { &*buffer.as_ptr().cast::<QUERY_SERVICE_CONFIGW>() };
    Some(if config.dwStartType == SERVICE_DISABLED {
        WindowsTime::Disabled
    } else {
        WindowsTime::Stopped
    })
}
