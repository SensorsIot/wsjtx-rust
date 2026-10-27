use super::Mode;
pub type ChannelWord = [u8; 174];
const MASK: &[u8; 77] =
    b"01001010010111101000100110110100101100001000101001111001010101011011111000101";
pub struct Channel {
    pub(super) generator: Vec<[u8; 91]>,
    pub(super) checks: Vec<Vec<usize>>,
    source_generator: Vec<ChannelWord>,
}
impl Default for Channel {
    fn default() -> Self {
        Self::new()
    }
}
impl Channel {
    pub fn new() -> Self {
        let generator = include_str!("../../../fixtures/decoder/protocol-data/generator.dat")
            .lines()
            .filter(|s| s.len() == 91 && s.bytes().all(|c| c == b'0' || c == b'1'))
            .map(|s| std::array::from_fn(|i| s.as_bytes()[i] - b'0'))
            .collect::<Vec<_>>();
        assert_eq!(generator.len(), 83);
        let mut checks = vec![vec![]; 83];
        let mut column = 0;
        for line in include_str!("../../../fixtures/decoder/protocol-data/parity.dat").lines() {
            let numbers = line
                .split_whitespace()
                .map(str::parse::<usize>)
                .collect::<Result<Vec<_>, _>>();
            if let Ok(n) = numbers
                && n.len() == 3
            {
                assert!(column < 174);
                for row in n {
                    checks[row - 1].push(column);
                }
                column += 1;
            }
        }
        assert_eq!(column, 174);
        let mut channel = Self {
            generator,
            checks,
            source_generator: vec![],
        };
        channel.source_generator = (0..77)
            .map(|i| {
                let mut p = [0; 77];
                p[i] = 1;
                channel.encode(&p, Mode::Ft8)
            })
            .collect();
        debug_assert!(
            channel
                .source_generator
                .iter()
                .all(|word| channel.valid(word))
        );
        channel
    }
    pub fn crc(bits: &[u8; 77]) -> u16 {
        let mut r = 0u16;
        for b in bits.iter().copied().chain([0; 5]) {
            let feedback = (r >> 13) ^ (b as u16);
            r = (r << 1) & 0x3fff;
            if feedback != 0 {
                r ^= 0x2757;
            }
        }
        r
    }
    pub fn encode(&self, payload: &[u8; 77], mode: Mode) -> ChannelWord {
        assert!(payload.iter().all(|&b| b < 2));
        let mut out = [0; 174];
        for i in 0..77 {
            out[i] = payload[i] ^ if mode == Mode::Ft4 { MASK[i] - b'0' } else { 0 };
        }
        let p = std::array::from_fn(|i| out[i]);
        let crc = Self::crc(&p);
        for i in 0..14 {
            out[77 + i] = ((crc >> (13 - i)) & 1) as u8;
        }
        for (j, row) in self.generator.iter().enumerate() {
            out[91 + j] = row
                .iter()
                .zip(&out[..91])
                .fold(0, |a, (&x, &b)| a ^ (x & b));
        }
        out
    }
    pub fn valid(&self, word: &ChannelWord) -> bool {
        word.iter().all(|&x| x < 2)
            && self
                .checks
                .iter()
                .all(|row| row.iter().fold(0, |p, &j| p ^ word[j]) == 0)
            && {
                let p = std::array::from_fn(|i| word[i]);
                let c = word[77..91].iter().fold(0u16, |a, &b| (a << 1) | b as u16);
                Self::crc(&p) == c
            }
    }
    pub fn payload(&self, word: &ChannelWord, mode: Mode) -> Option<[u8; 77]> {
        self.valid(word).then(|| {
            std::array::from_fn(|i| word[i] ^ if mode == Mode::Ft4 { MASK[i] - b'0' } else { 0 })
        })
    }
    pub fn tones(&self, word: &ChannelWord, mode: Mode) -> Vec<u8> {
        let mut tones = vec![0; mode.symbol_count()];
        for (i, t) in mode.sync() {
            tones[i] = t;
        }
        let width = mode.bits_per_symbol();
        let gray = mode.gray_map();
        for (i, s) in mode.data_symbols().into_iter().enumerate() {
            let v = word[i * width..(i + 1) * width]
                .iter()
                .fold(0, |a, &b| a * 2 + b as usize);
            tones[s] = gray[v] as u8;
        }
        tones
    }
    /// Normalized min-sum; positive LLR denotes bit zero. Every output passes H and CRC.
    pub fn decode(&self, llr: &[f32; 174], cancel: &impl Fn() -> bool) -> Option<ChannelWord> {
        if llr.iter().any(|x| !x.is_finite()) || cancel() {
            return None;
        }
        let (word, posterior) = self.beliefs(llr, cancel);
        word.or_else(|| self.osd(llr, &posterior, cancel))
    }
    pub(super) fn beliefs(
        &self,
        llr: &[f32; 174],
        cancel: &impl Fn() -> bool,
    ) -> (Option<ChannelWord>, [f32; 174]) {
        if llr.iter().any(|x| !x.is_finite()) || cancel() {
            return (None, *llr);
        }
        let mut messages = self
            .checks
            .iter()
            .map(|row| {
                row.iter()
                    .map(|&j| llr[j].clamp(-12., 12.))
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();
        let mut posterior = *llr;
        for _ in 0..50 {
            if cancel() {
                return (None, *llr);
            }
            let mut sum = *llr;
            let mut outgoing = messages.clone();
            for (c, row) in self.checks.iter().enumerate() {
                for (k, &j) in row.iter().enumerate() {
                    let mut sign = 1.;
                    let mut min = f32::INFINITY;
                    for (m, &q) in messages[c].iter().enumerate() {
                        if m != k {
                            if q < 0. {
                                sign = -sign;
                            }
                            min = min.min(q.abs());
                        }
                    }
                    let r = 0.8 * sign * min;
                    outgoing[c][k] = r;
                    sum[j] += r;
                }
            }
            let hard = std::array::from_fn(|i| u8::from(sum[i] < 0.));
            if self.valid(&hard) {
                return (Some(hard), sum);
            }
            for (c, row) in self.checks.iter().enumerate() {
                for (k, &j) in row.iter().enumerate() {
                    messages[c][k] = (sum[j] - outgoing[c][k]).clamp(-50., 50.);
                }
            }
            posterior = sum;
        }
        (None, posterior)
    }
    fn osd(
        &self,
        llr: &[f32; 174],
        posterior: &[f32; 174],
        cancel: &impl Fn() -> bool,
    ) -> Option<ChannelWord> {
        // Build a reliability-ordered information basis from the systematic generator.
        let mut columns = (0..174).collect::<Vec<_>>();
        columns.sort_by(|&a, &b| {
            posterior[b]
                .abs()
                .total_cmp(&posterior[a].abs())
                .then(a.cmp(&b))
        });
        let mut rows = self.source_generator.clone();
        let mut basis = vec![];
        for c in columns {
            let r = basis.len();
            if let Some(p) = (r..77).find(|&k| rows[k][c] != 0) {
                rows.swap(r, p);
                let pivot = rows[r];
                for (k, row) in rows.iter_mut().enumerate() {
                    if k != r && row[c] != 0 {
                        for (dst, bit) in row.iter_mut().zip(pivot) {
                            *dst ^= bit;
                        }
                    }
                }
                basis.push(c);
                if basis.len() == 77 {
                    break;
                }
            }
        }
        if basis.len() != 77 {
            return None;
        }
        let mut least = (0..77).collect::<Vec<_>>();
        least.sort_by(|&a, &b| {
            posterior[basis[a]]
                .abs()
                .total_cmp(&posterior[basis[b]].abs())
        });
        least.truncate(16);
        let initial = std::array::from_fn::<_, 77, _>(|i| u8::from(posterior[basis[i]] < 0.));
        let mut trials = vec![vec![]];
        for &a in &least {
            trials.push(vec![a]);
        }
        for i in 0..least.len() {
            for j in i + 1..least.len() {
                trials.push(vec![least[i], least[j]]);
            }
        }
        let mut best = None;
        let mut best_cost = f32::INFINITY;
        for flips in trials {
            if cancel() {
                return None;
            }
            let mut bits = initial;
            for i in flips {
                bits[i] ^= 1;
            }
            let mut word = [0; 174];
            for i in 0..77 {
                if bits[i] != 0 {
                    for j in 0..174 {
                        word[j] ^= rows[i][j];
                    }
                }
            }
            if self.valid(&word) {
                let cost = word
                    .iter()
                    .enumerate()
                    .filter(|&(i, &b)| b != u8::from(llr[i] < 0.))
                    .map(|(i, _)| llr[i].abs())
                    .sum();
                if cost < best_cost {
                    best_cost = cost;
                    best = Some(word);
                }
            }
        }
        best
    }
}
