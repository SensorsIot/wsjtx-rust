#![deny(unsafe_code)]
#![cfg(windows)]
#[path = "../../src/radioControl/mod.rs"]
pub mod radio_control;
use radio_control::{
    Error,
    executor::Transport,
    windows::{SerialTransport, claim_identity, resolve_endpoint},
};
use std::io::{Read, Write};
use std::sync::{Arc, atomic::AtomicU64};
use std::{
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
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
fn identity_lease_child_probe() {
    if let Some(path) = std::env::var_os("WSTX_TEST_CAT_LOCK_ROOT") {
        assert!(matches!(
            claim_identity("usb\\vid_10c4&pid_ea60\\fixture", Path::new(&path)),
            Err(Error::ResourceInUse)
        ));
    }
}
// Proves: TC-009-003
#[test]
fn physical_identity_lease_conflicts_across_processes_and_case_aliases() {
    if std::env::var_os("WSTX_TEST_CAT_LOCK_ROOT").is_some() {
        return identity_lease_child_probe();
    }
    let root = std::env::temp_dir().join(format!(
        "wstx-cat-lock-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let lease = claim_identity("USB\\VID_10C4&PID_EA60\\FIXTURE", &root).unwrap();
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "physical_identity_lease_conflicts_across_processes_and_case_aliases",
        ])
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
#[allow(unsafe_code)]
mod windows_fixture {
    use ::windows::{
        Win32::{Storage::FileSystem::*, System::Pipes::*},
        core::PCWSTR,
    };
    use std::os::windows::io::{FromRawHandle, OwnedHandle};

    /// The server end of a unique local-only named pipe (synchronous I/O, the test's own).
    pub fn server(name: &[u16]) -> ::windows::core::Result<std::fs::File> {
        // SAFETY: NUL-terminated unique pipe name, no shared memory or external radio endpoints.
        let server = unsafe {
            CreateNamedPipeW(
                PCWSTR(name.as_ptr()),
                PIPE_ACCESS_DUPLEX,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_REJECT_REMOTE_CLIENTS,
                1,
                256,
                256,
                0,
                None,
            )
        };
        if server.is_invalid() {
            return Err(::windows::core::Error::from_thread());
        }
        // SAFETY: successful CreateNamedPipe returned sole ownership to this fixture.
        Ok(unsafe { OwnedHandle::from_raw_handle(server.0) }.into())
    }
}
/// A pipe whose client end the transport opens through `open_interface`, leased in a
/// temporary lock root of its own; the server end is the test's peer.
fn pair() -> (PathBuf, SerialTransport, std::fs::File) {
    let id = format!(
        "{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    );
    let name: Vec<u16> = format!("\\\\.\\pipe\\wstx-cat-{id}\0")
        .encode_utf16()
        .collect();
    let peer = windows_fixture::server(&name).expect("unique local-only pipe opens");
    let root = std::env::temp_dir().join(format!("wstx-cat-pipe-{id}"));
    let identity = format!("pipe-fixture-{id}");
    let lease = claim_identity(&identity, &root).unwrap();
    let transport = SerialTransport::open_interface(&name, identity, lease).unwrap();
    // The client end is already connected; the server needs no pending connect.
    (root, transport, peer)
}
#[test]
fn native_overlapped_pipe_io_uses_actual_owned_buffers_and_close() {
    let (root, mut transport, mut peer) = pair();
    let cancel = AtomicBool::new(false);
    let end = Instant::now() + Duration::from_secs(2);
    assert_eq!(transport.write(&[0xfe, 0xfe, 0xe0], end, &cancel), Ok(3));
    let mut heard = [0; 3];
    peer.read_exact(&mut heard).unwrap();
    assert_eq!(heard, [0xfe, 0xfe, 0xe0]);
    peer.write_all(&[0xfe, 0xfe, 0x94]).unwrap();
    let mut bytes = [0; 256];
    assert_eq!(transport.read(&mut bytes, end, &cancel), Ok(3));
    assert_eq!(&bytes[..3], &[0xfe, 0xfe, 0x94]);
    transport.close().unwrap();
    transport.close().unwrap();
    drop(peer);
    std::fs::remove_dir_all(root).unwrap();
}
/// A deadline `after` from now, handed to the transport.
fn deadline_in(after: Duration) -> Instant {
    Instant::now() + after
}
/// Sets `cancel` from another thread after `ms` milliseconds, while a read is pending: the
/// transport signals no event for a pending read, so this is a fixed pause.
fn cancel_after(cancel: &Arc<AtomicBool>, ms: u64) -> std::thread::JoinHandle<()> {
    let signal = cancel.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(ms));
        signal.store(true, Ordering::Release)
    })
}
#[test]
fn native_pending_read_deadline_and_cross_thread_cancel_are_acknowledged() {
    let (root, mut receiver, _peer) = pair();
    let mut bytes = [0; 256];
    let no_cancel = AtomicBool::new(false);
    assert_eq!(
        receiver.read(
            &mut bytes,
            deadline_in(Duration::from_millis(40)),
            &no_cancel
        ),
        Err(Error::Timeout)
    );
    let cancel = Arc::new(AtomicBool::new(false));
    let cancel_thread = cancel_after(&cancel, 25);
    assert_eq!(
        receiver.read(&mut bytes, deadline_in(Duration::from_secs(2)), &cancel),
        Err(Error::Cancelled)
    );
    cancel_thread.join().unwrap();
    receiver.close().unwrap();
    assert_eq!(
        receiver.read(&mut bytes, deadline_in(Duration::from_secs(1)), &no_cancel),
        Err(Error::Unavailable)
    );
    std::fs::remove_dir_all(root).unwrap();
}
// Timing: radio
#[test]
fn realtime_bound_native_pending_read_deadline_and_cross_thread_cancel_are_acknowledged() {
    let (root, mut receiver, _peer) = pair();
    let mut bytes = [0; 256];
    let no_cancel = AtomicBool::new(false);
    let start = Instant::now();
    assert_eq!(
        receiver.read(&mut bytes, start + Duration::from_millis(40), &no_cancel),
        Err(Error::Timeout)
    );
    assert!(start.elapsed() < Duration::from_millis(250));
    let cancel = Arc::new(AtomicBool::new(false));
    let cancel_thread = cancel_after(&cancel, 25);
    let start = Instant::now();
    assert_eq!(
        receiver.read(&mut bytes, start + Duration::from_secs(2), &cancel),
        Err(Error::Cancelled)
    );
    cancel_thread.join().unwrap();
    assert!(start.elapsed() < Duration::from_millis(250));
    receiver.close().unwrap();
    std::fs::remove_dir_all(root).unwrap();
}
