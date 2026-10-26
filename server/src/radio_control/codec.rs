use super::{Configuration, DataValue, Error, ModeValue, Operation, Result, Sideband};

pub const MAX_FRAME: usize = 32;
pub const MAX_READ: usize = 256;
pub const MAX_BYTES: usize = 4096;
pub const MAX_FRAMES: usize = 64;

pub fn encode_frequency(mut value: u64) -> Result<[u8; 5]> {
    if !(30000..=74800000).contains(&value) {
        return Err(Error::InvalidRequest);
    }
    let mut bytes = [0; 5];
    for byte in &mut bytes {
        let pair = (value % 100) as u8;
        *byte = ((pair / 10) << 4) | (pair % 10);
        value /= 100;
    }
    Ok(bytes)
}
pub fn decode_frequency(bytes: &[u8]) -> Result<u64> {
    if bytes.len() != 5 {
        return Err(Error::Protocol);
    }
    let (mut value, mut factor) = (0, 1);
    for &byte in bytes {
        let hi = byte >> 4;
        let lo = byte & 15;
        if hi > 9 || lo > 9 {
            return Err(Error::Protocol);
        }
        value += u64::from(hi * 10 + lo) * factor;
        factor *= 100;
    }
    if !(30000..=74800000).contains(&value) {
        return Err(Error::Protocol);
    }
    Ok(value)
}
pub fn request(config: &Configuration, operation: &Operation) -> Result<Vec<u8>> {
    config.validate()?;
    operation.validate()?;
    let mut bytes = vec![0xfe, 0xfe, config.radio_address, config.controller_address];
    match operation {
        Operation::ReadFrequency => bytes.push(3),
        Operation::ReadMode => bytes.push(4),
        Operation::ReadData => bytes.extend([0x1a, 6]),
        Operation::ReadRxTx => bytes.extend([0x1c, 0]),
        Operation::ReadSplit => bytes.push(0x0f),
        Operation::SetFrequency { frequency_hz } => {
            bytes.push(5);
            bytes.extend(encode_frequency(*frequency_hz)?);
        }
        Operation::SetMode { mode, filter } => bytes.extend([
            6,
            match mode {
                Sideband::Lsb => 0,
                Sideband::Usb => 1,
            },
            *filter,
        ]),
        Operation::SetData { data, filter } => bytes.extend([0x1a, 6, u8::from(*data), *filter]),
        Operation::ReceiveSetup { .. } => return Err(Error::InvalidRequest),
    }
    bytes.push(0xfd);
    Ok(bytes)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reply {
    Ack,
    Rejected,
    Frequency(u64),
    Mode(ModeValue),
    Data(DataValue),
    Transmitting(bool),
    Split(bool),
}
pub fn reply(config: &Configuration, frame: &[u8], operation: &Operation) -> Result<Option<Reply>> {
    if frame.len() < 6
        || frame.len() > MAX_FRAME
        || frame[..2] != [0xfe, 0xfe]
        || frame.last() != Some(&0xfd)
    {
        return Err(Error::Protocol);
    }
    if frame[2] != config.controller_address || frame[3] != config.radio_address {
        return Ok(None);
    }
    let body = &frame[4..frame.len() - 1];
    if body == [0xfa] {
        return Ok(Some(Reply::Rejected));
    }
    let setter = matches!(
        operation,
        Operation::SetFrequency { .. } | Operation::SetMode { .. } | Operation::SetData { .. }
    );
    if setter && body == [0xfb] {
        return Ok(Some(Reply::Ack));
    }
    let starts = match operation {
        Operation::ReadFrequency => &[3][..],
        Operation::ReadMode => &[4],
        Operation::ReadData => &[0x1a, 6],
        Operation::ReadRxTx => &[0x1c, 0],
        Operation::ReadSplit => &[0x0f],
        _ => return Ok(None),
    };
    if !body.starts_with(starts) {
        return Ok(None);
    }
    let data = &body[starts.len()..];
    let value = match operation {
        Operation::ReadFrequency => Reply::Frequency(decode_frequency(data)?),
        Operation::ReadMode if data.len() == 2 && (1..=3).contains(&data[1]) => {
            Reply::Mode(ModeValue {
                code: data[0],
                filter: data[1],
            })
        }
        Operation::ReadData
            if data.len() == 2
                && ((data[0] == 0 && data[1] == 0)
                    || (data[0] == 1 && (1..=3).contains(&data[1]))) =>
        {
            Reply::Data(DataValue {
                enabled: data[0] == 1,
                filter: data[1],
            })
        }
        Operation::ReadRxTx if data.len() == 1 && data[0] <= 1 => Reply::Transmitting(data[0] == 1),
        Operation::ReadSplit if data.len() == 1 && data[0] <= 1 => Reply::Split(data[0] == 1),
        _ => return Err(Error::Protocol),
    };
    Ok(Some(value))
}

#[derive(Default)]
pub struct Framer {
    frame: Vec<u8>,
    preamble: bool,
    bytes: usize,
    frames: usize,
}
impl Framer {
    pub fn feed(&mut self, chunk: &[u8]) -> Result<Vec<Vec<u8>>> {
        if chunk.len() > MAX_READ {
            return Err(Error::Limit);
        }
        self.bytes = self.bytes.checked_add(chunk.len()).ok_or(Error::Limit)?;
        if self.bytes > MAX_BYTES {
            return Err(Error::Limit);
        }
        let mut complete = Vec::new();
        for &byte in chunk {
            if self.frame.is_empty() {
                if byte == 0xfe {
                    if self.preamble {
                        self.frame.extend([0xfe, 0xfe]);
                        self.preamble = false;
                    } else {
                        self.preamble = true;
                    }
                } else {
                    self.preamble = false;
                }
                continue;
            }
            if self.frame.len() == 2 && byte == 0xfe {
                continue;
            }
            if self.frame.len() >= MAX_FRAME {
                return Err(Error::Limit);
            }
            self.frame.push(byte);
            if byte == 0xfd {
                self.frames += 1;
                if self.frames > MAX_FRAMES {
                    return Err(Error::Limit);
                }
                complete.push(std::mem::take(&mut self.frame));
                self.preamble = false;
            }
        }
        Ok(complete)
    }
}
