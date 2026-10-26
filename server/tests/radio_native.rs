#![cfg(windows)]
#[path = "../src/radio_control/mod.rs"]
pub mod radio_control;
use ::windows::Win32::System::Pipes::*;
use radio_control::{
    Error,
    executor::Transport,
    windows::{SerialTransport, claim_identity, resolve_endpoint},
};
use std::sync::{Arc, atomic::AtomicU64};
use std::{
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};
use windows::{
    Win32::{Foundation::*, Storage::FileSystem::*},
    core::{HRESULT, PCWSTR},
};
static NEXT: AtomicU64 = AtomicU64::new(1);
#[test]
fn exact_registry_portname_fallback_never_uses_friendly_names_or_disagreement() {
    use radio_control::windows::exact_port_name;
    assert_eq!(
        exact_port_name("COM3", Ok(None), Ok(Some("COM3".into()))),
        Ok(true)
    );
    assert_eq!(
        exact_port_name("COM3", Ok(Some("COM3".into())), Ok(Some("COM7".into()))),
        Err(Error::Protocol)
    );
    assert_eq!(
        exact_port_name("COM3", Err(Error::Unavailable), Ok(Some("COM3".into()))),
        Err(Error::Unavailable)
    );
    assert_eq!(
        exact_port_name("COM3", Ok(Some("COM3".into())), Err(Error::Unavailable)),
        Err(Error::Unavailable)
    );
    assert_eq!(
        exact_port_name("COM3", Ok(None), Ok(Some("Silicon Labs (COM3)".into()))),
        Err(Error::Protocol)
    );
    assert_eq!(
        exact_port_name("COM3", Ok(None), Ok(Some("COM7".into()))),
        Ok(false)
    );
    assert_eq!(
        exact_port_name("COM3", Ok(None), Ok(Some("com3".into()))),
        Ok(true)
    );
}
#[test]
fn identity_lease_child_probe() {
    if let Some(path) = std::env::var_os("WSTX_TEST_CAT_LOCK_ROOT") {
        assert!(matches!(
            claim_identity("usb\\vid_10c4&pid_ea60\\fixture", Path::new(&path)),
            Err(Error::ResourceInUse)
        ));
    }
}
#[test]
fn physical_identity_lease_conflicts_across_processes_and_case_aliases() {
    let root = std::env::temp_dir().join(format!(
        "wstx-cat-lock-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let lease = claim_identity("USB\\VID_10C4&PID_EA60\\FIXTURE", &root).unwrap();
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "identity_lease_child_probe"])
        .env("WSTX_TEST_CAT_LOCK_ROOT", &root)
        .status()
        .unwrap();
    assert!(status.success());
    drop(lease);
    drop(claim_identity("usb\\vid_10c4&pid_ea60\\fixture", &root).unwrap());
    std::fs::remove_dir_all(root).unwrap();
    assert!(matches!(
        resolve_endpoint(0),
        Err(Error::InvalidConfiguration)
    ));
}
#[test]
#[ignore = "Read-only OS discovery acceptance: explicitly select the test PC and port"]
fn read_only_selected_endpoint_discovery() {
    let port = std::env::var("WSTX_TEST_SERIAL_PORT")
        .unwrap()
        .parse::<u16>()
        .unwrap();
    let endpoint = resolve_endpoint(port).unwrap();
    println!("COM{} PNP {}", endpoint.port, endpoint.instance_id);
    if let Ok(expected) = std::env::var("WSTX_TEST_SERIAL_PNP") {
        assert_eq!(
            endpoint.instance_id.to_ascii_uppercase(),
            expected.to_ascii_uppercase()
        )
    }
}
fn pair() -> (SerialTransport, SerialTransport) {
    let name: Vec<u16> = format!(
        "\\\\.\\pipe\\wstx-cat-{}-{}\0",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    )
    .encode_utf16()
    .collect();
    // SAFETY: unique local-only named pipe, no shared memory or external radio endpoints.
    let server = unsafe {
        CreateNamedPipeW(
            PCWSTR(name.as_ptr()),
            PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_REJECT_REMOTE_CLIENTS,
            1,
            256,
            256,
            0,
            None,
        )
    };
    assert!(!server.is_invalid());
    // SAFETY: successful CreateNamedPipe returned sole ownership to this fixture.
    let server = unsafe { OwnedHandle::from_raw_handle(server.0) };
    // SAFETY: unique pipe created above; asynchronous owned client handle.
    let client = unsafe {
        CreateFileW(
            PCWSTR(name.as_ptr()),
            GENERIC_READ.0 | GENERIC_WRITE.0,
            FILE_SHARE_MODE(0),
            None,
            OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED,
            None,
        )
    }
    .unwrap();
    // The client is already connected; do not leave a pending ConnectNamedPipe operation.
    // SAFETY: server handle remains owned and live, no pending connect is requested.
    let connected = unsafe { ConnectNamedPipe(HANDLE(server.as_raw_handle()), None) };
    assert!(
        connected.is_ok()
            || connected.unwrap_err().code() == HRESULT::from_win32(ERROR_PIPE_CONNECTED.0)
    );
    // SAFETY: CreateFile returned this fixture's sole client handle ownership.
    let client = unsafe { OwnedHandle::from_raw_handle(client.0) };
    (
        SerialTransport::from_owned_test_handle(server),
        SerialTransport::from_owned_test_handle(client),
    )
}
#[test]
fn native_overlapped_pipe_io_uses_actual_owned_buffers_and_close() {
    let (mut receiver, mut sender) = pair();
    let cancel = AtomicBool::new(false);
    let end = Instant::now() + Duration::from_secs(2);
    assert_eq!(sender.write(&[0xfe, 0xfe, 0xe0], end, &cancel), Ok(3));
    let mut bytes = [0; 256];
    assert_eq!(receiver.read(&mut bytes, end, &cancel), Ok(3));
    assert_eq!(&bytes[..3], &[0xfe, 0xfe, 0xe0]);
    receiver.close().unwrap();
    receiver.close().unwrap();
    sender.close().unwrap();
}
#[test]
fn native_pending_read_deadline_and_cross_thread_cancel_are_acknowledged() {
    let (mut receiver, _sender) = pair();
    let mut bytes = [0; 256];
    let no_cancel = AtomicBool::new(false);
    let start = Instant::now();
    assert_eq!(
        receiver.read(&mut bytes, start + Duration::from_millis(40), &no_cancel),
        Err(Error::Timeout)
    );
    assert!(start.elapsed() < Duration::from_millis(250));
    let cancel = Arc::new(AtomicBool::new(false));
    let signal = cancel.clone();
    let cancel_thread = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(25));
        signal.store(true, Ordering::Release)
    });
    let start = Instant::now();
    assert_eq!(
        receiver.read(&mut bytes, start + Duration::from_secs(2), &cancel),
        Err(Error::Cancelled)
    );
    cancel_thread.join().unwrap();
    assert!(start.elapsed() < Duration::from_millis(250));
    receiver.close().unwrap();
    assert_eq!(
        receiver.read(
            &mut bytes,
            Instant::now() + Duration::from_secs(1),
            &no_cancel
        ),
        Err(Error::Unavailable)
    );
}
