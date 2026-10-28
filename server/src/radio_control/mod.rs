#![deny(unsafe_code)]
//! Typed receive-only radio control. Catalogue facts never grant raw-byte execution.
pub mod actor;
pub mod catalogue;
pub mod codec;
pub mod executor;
#[cfg(windows)]
#[allow(unsafe_code)]
pub mod windows;

use serde::{Deserialize, Serialize};
use std::{
    sync::{Arc, atomic::AtomicBool},
    time::Instant,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidConfiguration,
    InvalidRequest,
    Unsupported,
    StaleContext,
    Busy,
    Unavailable,
    ResourceInUse,
    Cancelled,
    Timeout,
    Protocol,
    Limit,
    Rejected,
    PartialWrite,
    ReadbackMismatch,
    Indeterminate,
    FailedClose,
}
pub type Result<T> = std::result::Result<T, Error>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Baud {
    Auto,
    Fixed(u32),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Configuration {
    pub port: u16,
    pub baud: Baud,
    pub radio_address: u8,
    pub controller_address: u8,
}
impl Configuration {
    pub fn validate(&self) -> Result<()> {
        if !(1..=256).contains(&self.port)
            || !(1..=0xef).contains(&self.radio_address)
            || !(1..=0xef).contains(&self.controller_address)
            || self.radio_address == self.controller_address
            || matches!(self.baud,Baud::Fixed(rate) if ![4800,9600,19200,38400,57600,115200].contains(&rate))
        {
            Err(Error::InvalidConfiguration)
        } else {
            Ok(())
        }
    }
    pub fn parse(value: &str) -> Result<Self> {
        if value.len() > 256 || !value.is_ascii() || value.bytes().any(|b| b.is_ascii_control()) {
            return Err(Error::InvalidConfiguration);
        }
        let (port, baud, radio_address, controller_address) = if let Some(rest) =
            value.strip_prefix("icom7300://")
        {
            let (port, query) = rest.split_once('?').ok_or(Error::InvalidConfiguration)?;
            let mut fields = query.split('&');
            let baud = fields
                .next()
                .and_then(|s| s.strip_prefix("baud="))
                .ok_or(Error::InvalidConfiguration)?;
            let radio = fields
                .next()
                .and_then(|s| s.strip_prefix("radio="))
                .ok_or(Error::InvalidConfiguration)?;
            let controller = fields
                .next()
                .and_then(|s| s.strip_prefix("controller="))
                .ok_or(Error::InvalidConfiguration)?;
            if fields.next().is_some() {
                return Err(Error::InvalidConfiguration);
            }
            let parse_address = |s: &str| -> Result<u8> {
                if s.len() != 2 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Err(Error::InvalidConfiguration);
                }
                let n = u8::from_str_radix(s, 16).map_err(|_| Error::InvalidConfiguration)?;
                if !(1..=0xef).contains(&n) {
                    return Err(Error::InvalidConfiguration);
                }
                Ok(n)
            };
            let baud = if baud == "auto" {
                Baud::Auto
            } else {
                let n = baud
                    .parse::<u32>()
                    .map_err(|_| Error::InvalidConfiguration)?;
                if ![4800, 9600, 19200, 38400, 57600, 115200].contains(&n) || n.to_string() != baud
                {
                    return Err(Error::InvalidConfiguration);
                }
                Baud::Fixed(n)
            };
            (
                port,
                baud,
                parse_address(radio)?,
                parse_address(controller)?,
            )
        } else {
            (value, Baud::Auto, 0x94, 0xe0)
        };
        let port = port.to_ascii_uppercase();
        let number = port
            .strip_prefix("COM")
            .ok_or(Error::InvalidConfiguration)?;
        let n = number
            .parse::<u16>()
            .map_err(|_| Error::InvalidConfiguration)?;
        if !(1..=256).contains(&n) || n.to_string() != number || radio_address == controller_address
        {
            return Err(Error::InvalidConfiguration);
        }
        Ok(Self {
            port: n,
            baud,
            radio_address,
            controller_address,
        })
    }
    pub fn port_name(&self) -> String {
        format!("COM{}", self.port)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Sideband {
    #[serde(rename = "LSB")]
    Lsb,
    #[serde(rename = "USB")]
    Usb,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum Operation {
    ReadFrequency,
    ReadMode,
    ReadData,
    ReadRxTx,
    ReadSplit,
    SetFrequency {
        frequency_hz: u64,
    },
    SetMode {
        mode: Sideband,
        filter: u8,
    },
    SetData {
        data: bool,
        filter: u8,
    },
    ReceiveSetup {
        frequency_hz: u64,
        mode: Sideband,
        filter: u8,
        data: bool,
        data_filter: u8,
    },
}
// Empty struct variants retain strict unknown-field checks for parameter-free queries.
#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum WireOperation {
    ReadFrequency {},
    ReadMode {},
    ReadData {},
    ReadRxTx {},
    ReadSplit {},
    SetFrequency {
        frequency_hz: u64,
    },
    SetMode {
        mode: Sideband,
        filter: u8,
    },
    SetData {
        data: bool,
        filter: u8,
    },
    ReceiveSetup {
        frequency_hz: u64,
        mode: Sideband,
        filter: u8,
        data: bool,
        data_filter: u8,
    },
}
impl<'de> Deserialize<'de> for Operation {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        Ok(match WireOperation::deserialize(deserializer)? {
            WireOperation::ReadFrequency {} => Self::ReadFrequency,
            WireOperation::ReadMode {} => Self::ReadMode,
            WireOperation::ReadData {} => Self::ReadData,
            WireOperation::ReadRxTx {} => Self::ReadRxTx,
            WireOperation::ReadSplit {} => Self::ReadSplit,
            WireOperation::SetFrequency { frequency_hz } => Self::SetFrequency { frequency_hz },
            WireOperation::SetMode { mode, filter } => Self::SetMode { mode, filter },
            WireOperation::SetData { data, filter } => Self::SetData { data, filter },
            WireOperation::ReceiveSetup {
                frequency_hz,
                mode,
                filter,
                data,
                data_filter,
            } => Self::ReceiveSetup {
                frequency_hz,
                mode,
                filter,
                data,
                data_filter,
            },
        })
    }
}
impl Operation {
    pub fn key(&self) -> &'static str {
        match self {
            Self::ReadFrequency => "read_frequency",
            Self::ReadMode => "read_mode",
            Self::ReadData => "read_data",
            Self::ReadRxTx => "read_rx_tx",
            Self::ReadSplit => "read_split",
            Self::SetFrequency { .. } => "set_frequency",
            Self::SetMode { .. } => "set_mode",
            Self::SetData { .. } => "set_data",
            Self::ReceiveSetup { .. } => "receive_setup",
        }
    }
    pub fn validate(&self) -> Result<()> {
        let frequency = |f: &u64| (30000..=74800000).contains(f);
        let filter = |f: &u8| (1..=3).contains(f);
        let valid = match self {
            Self::SetFrequency { frequency_hz } => frequency(frequency_hz),
            Self::SetMode { filter: f, .. } => filter(f),
            Self::SetData { data, filter: f } => {
                if *data {
                    filter(f)
                } else {
                    *f == 0
                }
            }
            Self::ReceiveSetup {
                frequency_hz,
                filter: f,
                data,
                data_filter,
                ..
            } => {
                frequency(frequency_hz)
                    && filter(f)
                    && if *data {
                        filter(data_filter)
                    } else {
                        *data_filter == 0
                    }
            }
            _ => true,
        };
        if valid {
            Ok(())
        } else {
            Err(Error::InvalidRequest)
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Authority {
    pub profile_id: String,
    pub boot_id: String,
    pub profile_revision: u64,
    pub resource_id: String,
    pub connection_generation: u64,
}
impl Authority {
    pub fn validate(&self) -> Result<()> {
        if self.profile_id.is_empty()
            || self.boot_id.is_empty()
            || self.resource_id.is_empty()
            || self.connection_generation == 0
            || self.connection_generation > 9_007_199_254_740_991
            || self.profile_revision > 9_007_199_254_740_991
        {
            Err(Error::InvalidRequest)
        } else {
            Ok(())
        }
    }
}
pub struct Request {
    pub authority: Authority,
    pub request_id: String,
    pub operation: Operation,
    pub deadline: Instant,
    pub cancelled: Arc<AtomicBool>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ModeValue {
    pub code: u8,
    pub filter: u8,
}
impl ModeValue {
    pub fn sideband(self) -> Option<Sideband> {
        match self.code {
            0 => Some(Sideband::Lsb),
            1 => Some(Sideband::Usb),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DataValue {
    pub enabled: bool,
    pub filter: u8,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Observation {
    pub frequency_hz: Option<u64>,
    pub mode: Option<ModeValue>,
    pub data: Option<DataValue>,
    pub transmitting: Option<bool>,
    pub split: Option<bool>,
    pub observed_at: Option<Instant>,
}
/// Provenance belongs to the particular addressed query that consumed its reply.
/// The legacy aggregate Observation timestamp deliberately retains its old meaning.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Fact<T> {
    pub value: Option<T>,
    pub query_sequence: Option<u64>,
    pub observed_at: Option<Instant>,
    pub confirmed: bool,
}
impl<T> Default for Fact<T> {
    fn default() -> Self {
        Self {
            value: None,
            query_sequence: None,
            observed_at: None,
            confirmed: false,
        }
    }
}
impl<T> Fact<T> {
    pub(super) fn observed(value: T, sequence: u64, at: Instant) -> Self {
        Self {
            value: Some(value),
            query_sequence: Some(sequence),
            observed_at: Some(at),
            confirmed: true,
        }
    }
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Facts {
    pub sequence: u64,
    pub frequency: Fact<u64>,
    pub mode: Fact<ModeValue>,
    pub data: Fact<DataValue>,
    pub rx_tx: Fact<bool>,
    pub split: Fact<bool>,
}
impl Facts {
    pub(super) fn invalidate(&mut self, operation: &Operation) {
        match operation {
            Operation::SetFrequency { .. } => self.frequency.confirmed = false,
            Operation::SetMode { .. } => self.mode.confirmed = false,
            Operation::SetData { .. } => self.data.confirmed = false,
            Operation::ReceiveSetup { .. } => {
                self.frequency.confirmed = false;
                self.mode.confirmed = false;
                self.data.confirmed = false;
            }
            _ => {}
        }
    }
    pub(super) fn stale(&mut self) {
        self.frequency.confirmed = false;
        self.mode.confirmed = false;
        self.data.confirmed = false;
        self.rx_tx.confirmed = false;
        self.split.confirmed = false;
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Closed,
    Connecting,
    Ready,
    Closing,
    Unavailable,
}
#[derive(Clone, Debug)]
pub struct Snapshot {
    pub(super) publication: u64,
    pub(super) closing_requested: bool,
    pub state: State,
    pub authority: Authority,
    pub effective_baud: Option<u32>,
    pub observation: Observation,
    pub facts: Facts,
    pub last_error: Option<Error>,
}

impl Snapshot {
    /// Private publication order, separate from per-query wire provenance.
    pub fn publication(&self) -> u64 {
        self.publication
    }
    pub(super) fn publish(&mut self) -> Result<()> {
        self.publication = self.publication.checked_add(1).ok_or(Error::Limit)?;
        Ok(())
    }
    pub(super) fn invalidate(&mut self, operation: &Operation) -> Result<()> {
        let before = self.facts.clone();
        self.facts.invalidate(operation);
        if self.facts != before {
            self.publish()?;
        }
        Ok(())
    }
}
