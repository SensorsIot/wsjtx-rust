//! WebSocket frames the raw peers of the web tests write and read (RFC 6455).

/// A client frame (RFC 6455 5.2): FIN, the opcode, the masked payload under a fixed key.
pub fn client_frame(opcode: u8, payload: &[u8]) -> Vec<u8> {
    let key = [0x37u8, 0xfa, 0x21, 0x3d];
    let mut frame = vec![0x80 | opcode];
    match payload.len() {
        n if n < 126 => frame.push(0x80 | n as u8),
        n if n < 65536 => {
            frame.push(0x80 | 126);
            frame.extend_from_slice(&(n as u16).to_be_bytes());
        }
        n => {
            frame.push(0x80 | 127);
            frame.extend_from_slice(&(n as u64).to_be_bytes());
        }
    }
    frame.extend_from_slice(&key);
    frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ key[i % 4]));
    frame
}

/// One complete frame at the start of `buffer`: (opcode, payload, frame length).
pub fn parse_frame(buffer: &[u8]) -> Option<(u8, Vec<u8>, usize)> {
    let first = *buffer.first()?;
    let second = *buffer.get(1)?;
    let (length, mut at) = match second & 0x7f {
        126 => (
            u16::from_be_bytes(buffer.get(2..4)?.try_into().ok()?) as usize,
            4,
        ),
        127 => (
            u64::from_be_bytes(buffer.get(2..10)?.try_into().ok()?) as usize,
            10,
        ),
        n => (n as usize, 2),
    };
    let key = if second & 0x80 != 0 {
        let key: [u8; 4] = buffer.get(at..at + 4)?.try_into().ok()?;
        at += 4;
        Some(key)
    } else {
        None
    };
    let payload = buffer.get(at..at + length)?;
    let payload = match key {
        Some(key) => payload
            .iter()
            .enumerate()
            .map(|(i, b)| b ^ key[i % 4])
            .collect(),
        None => payload.to_vec(),
    };
    Some((first & 0x0f, payload, at + length))
}
