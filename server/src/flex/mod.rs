//! FR-023 optional native FlexRadio connection (WstxProductScope::NativeFlexBoundary).
//! Control and receive samples share one per-station session; audio reaches the station
//! only through the existing sample-source interface, separate from control.
pub mod session;
pub mod wire;

pub use session::{Config, Error, Intent, NativeInput, Session, Snapshot, State};
