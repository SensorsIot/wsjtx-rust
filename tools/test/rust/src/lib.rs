#![forbid(unsafe_code)]
//! The test tools of the Rust tests
//! (harness/project/docs/specifics/windows-build-and-packaging.md, "Test tools"): code only tests run,
//! never product. The crate depends on no product package; each tool takes plain values.
//! Product code names a tool only in a test file.
pub mod capture_evidence;
pub mod link_estimate;
pub mod listening;
pub mod lock_holder;
pub mod model_values;
pub mod native_ft8_fixture;
pub mod ports;
pub mod receive_authority;
pub mod resource_harness;
pub mod resource_observer;
pub mod ws_frame;
