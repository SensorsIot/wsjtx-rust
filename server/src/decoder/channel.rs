// Channel decoding adapted from WSJT-X lib/ft8/decode174_91.f90, osd174_91.f90 and
// platanh.f90 (WSJT-X 3.3.0-beta5; unchanged in WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9).
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
use super::Mode;
pub type ChannelWord = [u8; 174];
const MASK: &[u8; 77] =
    b"01001010010111101000100110110100101100001000101001111001010101011011111000101";
/// Information bits of the (174,91) code: 77 payload bits and the 14-bit CRC.
const K: usize = 91;
/// decode174_91 max_iterations.
const ITERATIONS: usize = 30;
/// maxosd: ordered-statistics passes over the cumulative sums of BP iterations 1..=2.
const RECOVERY_SUMS: usize = 2;
/// osd174_91 ndeep=2 (FT8 and FT4 deep decoding): nt=40, ntheta=10.
const SCREEN_BITS: u32 = 40;
const SCREEN_LIMIT: u32 = 10;
pub struct Channel {
    generator: Vec<[u8; 91]>,
    checks: Vec<Vec<usize>>,
    /// Edge indices (into the check-major edge list) of the three checks of each bit.
    bit_edges: Vec<[usize; 3]>,
    /// Columns of the systematic (174,91) generator as 91-bit row masks; CRC bits free.
    generator_columns: Vec<u128>,
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
            .collect::<Vec<[u8; 91]>>();
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
        let mut bit_edges = vec![[usize::MAX; 3]; 174];
        let mut filled = [0; 174];
        for (edge, &bit) in checks.iter().flatten().enumerate() {
            bit_edges[bit][filled[bit]] = edge;
            filled[bit] += 1;
        }
        assert!(filled.iter().all(|&n| n == 3));
        let generator_columns = (0..174)
            .map(|col| {
                if col < K {
                    1u128 << col
                } else {
                    (0..K)
                        .filter(|&row| generator[col - K][row] != 0)
                        .fold(0, |mask, row| mask | 1 << row)
                }
            })
            .collect();
        Self {
            generator,
            checks,
            bit_edges,
            generator_columns,
        }
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
    fn crc_valid(word: &ChannelWord) -> bool {
        let p = std::array::from_fn(|i| word[i]);
        let c = word[77..91].iter().fold(0u16, |a, &b| (a << 1) | b as u16);
        Self::crc(&p) == c
    }
    pub fn valid(&self, word: &ChannelWord) -> bool {
        word.iter().all(|&x| x < 2)
            && self
                .checks
                .iter()
                .all(|row| row.iter().fold(0, |p, &j| p ^ word[j]) == 0)
            && Self::crc_valid(word)
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
    /// Positive LLR denotes bit zero. Every output passes H and CRC.
    pub fn decode(&self, llr: &[f32; 174], cancel: &impl Fn() -> bool) -> Option<ChannelWord> {
        self.decode_counted(llr, cancel).map(|(word, _)| word)
    }
    /// Hybrid decode174_91 (maxosd=2, norder=2): belief propagation, then ordered statistics
    /// on the cumulative sums of BP iterations 1 and 2. Returns the word and its hard
    /// disagreements (nharderrors): against the channel LLRs for a BP word, against the
    /// hard decisions of the recovered sum for an ordered-statistics word.
    pub(super) fn decode_counted(
        &self,
        llr: &[f32; 174],
        cancel: &impl Fn() -> bool,
    ) -> Option<(ChannelWord, usize)> {
        if llr.iter().any(|x| !x.is_finite()) || cancel() {
            return None;
        }
        let (word, sums) = self.beliefs(llr, cancel);
        if word.is_some() {
            return word;
        }
        sums.iter().find_map(|sum| self.osd(sum, cancel))
    }
    /// Sum-product belief propagation (flooding schedule) with WSJT-X's early stop. Returns a
    /// valid word, or the cumulative bit sums of iterations 1..=RECOVERY_SUMS.
    pub(super) fn beliefs(
        &self,
        llr: &[f32; 174],
        cancel: &impl Fn() -> bool,
    ) -> (Option<(ChannelWord, usize)>, Vec<[f32; 174]>) {
        let mut to_bit = vec![0f32; self.bit_edges.len() * 3];
        let mut sum = [0f32; 174];
        let mut sums = vec![];
        let mut half = [0f32; 7];
        let (mut stalled, mut last) = (0, 0);
        for iteration in 0..=ITERATIONS {
            #[cfg(test)]
            super::resource_observer::hit(super::resource_observer::Phase::FecCheck);
            if cancel() {
                return (None, vec![]);
            }
            let zn: [f32; 174] = std::array::from_fn(|i| {
                llr[i] + self.bit_edges[i].iter().map(|&e| to_bit[e]).sum::<f32>()
            });
            for (s, z) in sum.iter_mut().zip(&zn) {
                *s += z;
            }
            if (1..=RECOVERY_SUMS).contains(&iteration) {
                sums.push(sum);
            }
            let hard: ChannelWord = std::array::from_fn(|i| u8::from(zn[i] < 0.));
            #[cfg(test)]
            super::resource_observer::fec_word(hard);
            let unsatisfied = self
                .checks
                .iter()
                .filter(|row| row.iter().fold(0, |p, &j| p ^ hard[j]) != 0)
                .count();
            if unsatisfied == 0 && Self::crc_valid(&hard) {
                let errors = (0..174)
                    .filter(|&i| {
                        if hard[i] == 1 {
                            llr[i] > 0.
                        } else {
                            llr[i] < 0.
                        }
                    })
                    .count();
                return (Some((hard, errors)), sums);
            }
            if iteration > 0 {
                stalled = if unsatisfied < last { 0 } else { stalled + 1 };
                if stalled >= 5 && iteration >= 10 && unsatisfied > 15 {
                    break;
                }
            }
            last = unsatisfied;
            let mut edge = 0;
            for row in &self.checks {
                for (k, &j) in row.iter().enumerate() {
                    half[k] = tanh((zn[j] - to_bit[edge + k]) / 2.);
                }
                for k in 0..row.len() {
                    let others = (0..row.len())
                        .filter(|&m| m != k)
                        .fold(1f32, |p, m| p * half[m]);
                    to_bit[edge + k] = 2. * platanh(others);
                }
                edge += row.len();
                #[cfg(test)]
                super::resource_observer::hit(super::resource_observer::Phase::FecRow);
            }
        }
        (None, sums)
    }
    /// osd174_91 with Keff=91 and ndeep=2: order-1 patterns plus the first preprocessing
    /// rule (pairs screened on the 40 most reliable parity bits, at most 10 disagreements).
    pub(super) fn osd(
        &self,
        sum: &[f32; 174],
        cancel: &impl Fn() -> bool,
    ) -> Option<(ChannelWord, usize)> {
        // Most reliable first; ties in reverse index order (reversed ascending sort).
        let mut order = (0..174).collect::<Vec<_>>();
        order.sort_by(|&a, &b| sum[a].abs().total_cmp(&sum[b].abs()));
        order.reverse();
        let mut columns = order
            .iter()
            .map(|&c| self.generator_columns[c])
            .collect::<Vec<_>>();
        for id in 0..K {
            let Some(pivot) = (id..(K + 20).min(174)).find(|&c| columns[c] >> id & 1 != 0) else {
                continue;
            };
            columns.swap(id, pivot);
            order.swap(id, pivot);
            let rows = columns[id] & !(1 << id);
            let (low, high) = (rows as u64, (rows >> 64) as u64);
            let (word, shift) = (id / 64, id % 64);
            // Earlier pivot columns are unit vectors without bit id. Branch-free halves.
            for column in &mut columns[id..] {
                let halves = [*column as u64, (*column >> 64) as u64];
                let mask = 0u64.wrapping_sub(halves[word] >> shift & 1);
                *column =
                    ((halves[1] ^ high & mask) as u128) << 64 | (halves[0] ^ low & mask) as u128;
            }
        }
        #[cfg(test)]
        super::resource_observer::hit(super::resource_observer::Phase::RecoveryRank);
        // Rows restricted to the information columns (identity after full elimination) and
        // to the 83 parity columns, as bit masks in reliability order.
        let mut information = [0u128; K];
        let mut parity = [0u128; K];
        for (i, &column) in columns.iter().enumerate() {
            let mut rows = column;
            while rows != 0 {
                let r = rows.trailing_zeros() as usize;
                if i < K {
                    information[r] |= 1 << i;
                } else {
                    parity[r] |= 1 << (i - K);
                }
                rows &= rows - 1;
            }
        }
        let reliability: [f32; 174] = std::array::from_fn(|i| sum[order[i]].abs());
        let one = |i: usize| sum[order[i]] <= 0.;
        let message = (0..K).filter(|&i| one(i)).fold(0u128, |m, i| m | 1 << i);
        let received = (K..174)
            .filter(|&i| one(i))
            .fold(0u128, |m, i| m | 1 << (i - K));
        let weight = |mut bits: u128| {
            let mut w = 0f32;
            while bits != 0 {
                w += reliability[K + bits.trailing_zeros() as usize];
                bits &= bits - 1;
            }
            w
        };
        // The screened parity bits of every row, as u64 (SCREEN_BITS <= 64).
        let screen = |bits: u128| (bits & ((1 << SCREEN_BITS) - 1)) as u64;
        let screened = parity.map(screen);
        let base = (0..K)
            .filter(|&r| message >> r & 1 != 0)
            .fold(0u128, |p, r| p ^ parity[r]);
        let base_errors = base ^ received;
        let mut best = (0u128, weight(base_errors));
        for first in (0..K).rev() {
            #[cfg(test)]
            super::resource_observer::hit(super::resource_observer::Phase::RecoveryCheck);
            if cancel() {
                return None;
            }
            let single = base_errors ^ parity[first];
            let single_screened = screen(single);
            let d1 = reliability[first];
            if single_screened.count_ones() < SCREEN_LIMIT {
                let distance = d1 + weight(single);
                if distance < best.1 {
                    best = (1 << first, distance);
                }
            }
            for second in (0..first).rev() {
                if (single_screened ^ screened[second]).count_ones() + 2 <= SCREEN_LIMIT {
                    let pair = single ^ parity[second];
                    let distance = d1 + reliability[second] + weight(pair);
                    if distance < best.1 {
                        best = (1 << first | 1 << second, distance);
                    }
                }
            }
            #[cfg(test)]
            super::resource_observer::hit(super::resource_observer::Phase::RecoveryTrial);
        }
        let selected = message ^ best.0;
        let (info, check) = (0..K)
            .filter(|&r| selected >> r & 1 != 0)
            .fold((0u128, 0u128), |(i, p), r| {
                (i ^ information[r], p ^ parity[r])
            });
        let mut word = [0u8; 174];
        for (i, &c) in order.iter().enumerate() {
            let bit = if i < K { info >> i } else { check >> (i - K) };
            word[c] = (bit & 1) as u8;
        }
        let errors = ((info ^ message).count_ones() + (check ^ received).count_ones()) as usize;
        self.valid(&word).then_some((word, errors))
    }
}
/// tanh by its [7/6] Lambert continued-fraction approximant clamped to [-1, 1]: relative error
/// below 5e-6 for |x| <= 3.5 and below 1e-4 elsewhere; libm tanhf dominated the BP cost.
fn tanh(x: f32) -> f32 {
    let x = x.clamp(-9., 9.);
    let x2 = x * x;
    let p = x * (135135. + x2 * (17325. + x2 * (378. + x2)));
    let q = 135135. + x2 * (62370. + x2 * (3150. + 28. * x2));
    (p / q).clamp(-1., 1.)
}
/// WSJT-X platanh: piecewise-linear inverse hyperbolic tangent, saturating at 7.
fn platanh(x: f32) -> f32 {
    let z = x.abs();
    if z <= 0.664 {
        return x / 0.83;
    }
    let y = if z <= 0.9217 {
        (z - 0.4064) / 0.322
    } else if z <= 0.9951 {
        (z - 0.8378) / 0.0524
    } else if z <= 0.9998 {
        (z - 0.9914) / 0.0012
    } else {
        7.
    };
    y.copysign(x)
}

#[cfg(test)]
#[path = "channel_resource_test.rs"]
mod resource_tests;
