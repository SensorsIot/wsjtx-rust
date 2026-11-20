#![forbid(unsafe_code)]
#![cfg(not(debug_assertions))]
//! The tests of the decoder resource harness (`wstx_test_tools::resource_harness`), release
//! only as the measured `decoder_signal` binary is.
use serde_json::Value;
use std::process::Command;
use wstx_test_tools::resource_harness::{
    ResourcePeer, resource_bind_monitor, resource_emit, resource_hash, resource_line,
    resource_metrics_source_identity, resource_qualify_round, resource_source,
};

/// The worker of the cleanup test, its own binary started again: it prints the ready line
/// the decoder resource worker prints and waits for its prepare command.
fn cleanup_worker() {
    let text =
        std::env::var("WSTX_RESOURCE_WORKER_CONFIG").expect("parent-owned worker configuration");
    assert!(text.len() <= 2048);
    let config: Value = serde_json::from_str(&text).unwrap();
    resource_emit(
        serde_json::json!({"state":"ready","pid":std::process::id(),"worker_id":config["worker_id"],
        "source_sha":config["source_sha"],"executable_sha256":config["executable_sha256"],
        "provenance_origin":"parent-owned frozen source/executable; worker performs no subprocess probes"}),
    );
    let stdin = std::io::stdin();
    let mut input = stdin.lock();
    let prepare: Value =
        serde_json::from_slice(&resource_line(&mut input).unwrap().expect("prepare command"))
            .unwrap();
    assert_eq!(prepare, serde_json::json!({"op":"prepare"}));
}

#[test]
fn resource_owned_worker_failure_cleanup_uses_process_object_not_pid_reopen() {
    if std::env::var_os("WSTX_RESOURCE_WORKER_CONFIG").is_some() {
        return cleanup_worker();
    }
    assert!(cfg!(windows) && usize::BITS == 64);
    resource_metrics_source_identity();
    let executable = std::env::current_exe().unwrap();
    let config = serde_json::json!({"worker_id":format!("cleanup-control-{}",std::process::id()),
        "source_sha":resource_source(),"executable_sha256":resource_hash(&executable)});
    let mut monitor_and_identity = None;
    let mut cleanup_receipt = None;
    let mut injected = false;
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut command = Command::new(&executable);
        command
            .args([
                "--exact",
                "resource_owned_worker_failure_cleanup_uses_process_object_not_pid_reopen",
                "--nocapture",
                "--test-threads=1",
            ])
            .env("WSTX_RESOURCE_WORKER_CONFIG", config.to_string());
        let worker = ResourcePeer::spawn(&mut command, true);
        cleanup_receipt = Some(worker.cleanup.clone());
        let ready = worker.receive(20);
        assert_eq!(ready["state"], "ready");
        assert_eq!(ready["pid"], worker.child.id());
        let (monitor, creation) = resource_bind_monitor(&worker);
        monitor_and_identity = Some((monitor, creation, worker.child.id()));
        injected = true;
        panic!("controlled owner failure: parent guard must kill and reap its idle worker");
    }));
    assert!(
        outcome.is_err() && injected,
        "the planned cleanup control actually reached the failure point"
    );
    let cleanup = cleanup_receipt.unwrap().lock().unwrap().clone().unwrap();
    assert_eq!(cleanup["kill_attempted"], true);
    assert_eq!(cleanup["kill_error"], Value::Null);
    assert_eq!(cleanup["wait_succeeded"], true);
    assert_eq!(cleanup["reader_joined"], true);
    let (mut monitor, creation, pid) = monitor_and_identity.unwrap();
    monitor.send(serde_json::json!({"op":"sample","id":1}));
    let refusal = monitor.receive(10);
    assert_eq!(
        refusal,
        serde_json::json!({"v":1,"error":"process_not_live","winerror":null})
    );
    assert!(!monitor.wait_status(10).success());
    eprintln!(
        "RESOURCE_CLEANUP_CONTROL {}",
        serde_json::json!({"worker_pid":pid,"creation_filetime":creation,
        "worker_reaped_by_parent_guard":true,"held_process_object_observed_terminated":true,
        "directly_owned_monitor_reaped":true,"worker_cleanup":cleanup,"worker_grandchildren_created":0,"decoded_success_claim":false})
    );
}

#[test]
fn resource_concurrency_qualification_rejects_serial_work_and_clock_faults() {
    let interval = |start: u64, duration: u64| {
        serde_json::json!({"started_unix_ns":start,
        "ended_unix_ns":start+duration,"monotonic_duration_ns":duration,"seconds":duration as f64/1e9})
    };
    let valid = (0..4)
        .map(|index| interval(1_000_000_000 + index * 1_000_000, 200_000_000))
        .collect::<Vec<_>>();
    assert_eq!(
        resource_qualify_round(&[0, 1_000_000, 2_000_000, 3_000_000], &valid)["qualified_common_overlap_ns"],
        187_000_000u64
    );
    let serialized = (0..4)
        .map(|index| interval(1_000_000_000 + index * 10_000_000, 5_000_000))
        .collect::<Vec<_>>();
    assert!(
        std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2, 3], &serialized)).is_err()
    );
    assert!(
        std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2, 50_000_001], &valid))
            .is_err()
    );
    let mut bad_clock = valid.clone();
    bad_clock[0]["ended_unix_ns"] = serde_json::json!(1_210_000_000u64);
    assert!(
        std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2, 3], &bad_clock)).is_err()
    );
    assert!(std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2], &valid[..3])).is_err());
}
