//! The optional native FlexRadio connection (WstxFlexAdapterPart::FlexAdapter).
//! Control and receive samples share one per-station session; audio reaches the station
//! only through the existing sample-source interface, separate from control.
#[path = "../flexAdapter/session.rs"]
pub mod session;
#[path = "../flexAdapter/wire.rs"]
pub mod wire;

pub use session::{Config, Error, Intent, NativeInput, Session, Snapshot, State};
