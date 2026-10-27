// Adapted from WSJT-X decode174_91.f90 and osd174_91.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see COPYING.
// Source: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
// The CRC bits stay independent of this rank-91 parity search.
use super::{Channel, ChannelWord, DecodeError, search::CpuBudget};

#[derive(Clone, Copy, Default, Debug, PartialEq, Eq)]
struct Bits([u64; 3]);
impl Bits {
    fn bit(self, i: usize) -> bool {
        self.0[i / 64] & (1 << (i % 64)) != 0
    }
    fn set(&mut self, i: usize) {
        self.0[i / 64] |= 1 << (i % 64);
    }
    fn xor(self, other: Self) -> Self {
        Self(std::array::from_fn(|i| self.0[i] ^ other.0[i]))
    }
    fn word(self) -> ChannelWord {
        std::array::from_fn(|i| u8::from(self.bit(i)))
    }
}

pub(super) struct DeepChannel {
    generator: Vec<Bits>,
    checks: Vec<Vec<usize>>,
}
impl DeepChannel {
    pub fn new(channel: &Channel) -> Self {
        let generator = (0..91)
            .map(|i| {
                let mut word = Bits::default();
                word.set(i);
                for (j, row) in channel.generator.iter().enumerate() {
                    if row[i] != 0 {
                        word.set(91 + j);
                    }
                }
                word
            })
            .collect();
        Self {
            generator,
            checks: channel.checks.clone(),
        }
    }

    pub async fn decode(
        &self,
        channel: &Channel,
        llr: &[f32; 174],
        budget: &mut CpuBudget<'_>,
    ) -> Result<Vec<ChannelWord>, DecodeError> {
        budget.checkpoint().await?;
        if llr.iter().any(|x| !x.is_finite()) {
            return Ok(vec![]);
        }
        let mut incoming = self
            .checks
            .iter()
            .map(|row| vec![0f32; row.len()])
            .collect::<Vec<_>>();
        let mut cumulative = [0f32; 174];
        let mut snapshots = Vec::with_capacity(2);
        let (mut previous_unsatisfied, mut nondecreasing) = (0, 0);
        for iteration in 0..=30 {
            budget.checkpoint().await?;
            let mut posterior = *llr;
            for (row, messages) in self.checks.iter().zip(&incoming) {
                for (&j, &message) in row.iter().zip(messages) {
                    posterior[j] += message;
                }
            }
            accumulate(&mut cumulative, &posterior);
            if (1..=2).contains(&iteration) {
                snapshots.push(cumulative);
                #[cfg(test)]
                tests::record(tests::Event::Snapshot(
                    iteration,
                    *snapshots.last().unwrap(),
                ));
            }
            let hard = std::array::from_fn(|i| u8::from(posterior[i] < 0.));
            let unsatisfied = self
                .checks
                .iter()
                .filter(|row| row.iter().fold(0, |p, &j| p ^ hard[j]) != 0)
                .count();
            #[cfg(test)]
            tests::record(tests::Event::Posterior(iteration, unsatisfied));
            if unsatisfied == 0 && nonzero(&hard) && channel.valid(&hard) {
                return Ok(vec![hard]);
            }
            if iteration > 0 {
                if unsatisfied < previous_unsatisfied {
                    nondecreasing = 0;
                } else {
                    nondecreasing += 1;
                }
                if iteration >= 10 && unsatisfied > 15 && nondecreasing >= 5 {
                    break;
                }
            }
            previous_unsatisfied = unsatisfied;
            if iteration == 30 {
                break;
            }
            #[cfg(test)]
            tests::record(tests::Event::Update(iteration));
            for (row, messages) in self.checks.iter().zip(&mut incoming) {
                budget.checkpoint().await?;
                let variables = row
                    .iter()
                    .zip(messages.iter())
                    .map(|(&j, &received)| posterior[j] - received)
                    .collect::<Vec<_>>();
                for (k, message) in messages.iter_mut().enumerate() {
                    *message = check_message(&variables, k);
                }
            }
        }
        let mut out = vec![];
        for snapshot in snapshots {
            budget.checkpoint().await?;
            if let Some(basis) = OrderedBasis::new(&self.generator, &snapshot, budget).await?
                && let Some(word) = basis.nearest(budget).await?
            {
                let word = word.word();
                // Select a parity word FIRST; CRC is never a search-time filter.
                if nonzero(&word) && channel.valid(&word) && !out.contains(&word) {
                    out.push(word);
                }
            }
        }
        Ok(out)
    }
}
fn nonzero(word: &ChannelWord) -> bool {
    word.iter().any(|&b| b != 0)
}
fn accumulate(sum: &mut [f32; 174], posterior: &[f32; 174]) {
    for (sum, &value) in sum.iter_mut().zip(posterior) {
        *sum += value;
    }
}
fn check_message(variables: &[f32], excluded: usize) -> f32 {
    let product = variables
        .iter()
        .enumerate()
        .filter(|&(i, _)| i != excluded)
        .map(|(_, &q)| (q as f64 / 2.).tanh())
        .product::<f64>()
        .clamp(-1. + 1e-12, 1. - 1e-12);
    invert_check_product(product) as f32
}
fn invert_check_product(product: f64) -> f64 {
    2. * product.clamp(-1. + 1e-12, 1. - 1e-12).atanh()
}

struct OrderedBasis {
    rows: Vec<Bits>,
    parity_columns: Vec<usize>,
    order: Vec<usize>,
    hard: Bits,
    zero: Bits,
    weights: [f64; 174],
}
impl OrderedBasis {
    async fn new(
        generator: &[Bits],
        reliability: &[f32; 174],
        budget: &mut CpuBudget<'_>,
    ) -> Result<Option<Self>, DecodeError> {
        if reliability.iter().any(|x| !x.is_finite()) {
            return Ok(None);
        }
        #[cfg(test)]
        tests::record(tests::Event::BasisInput(*reliability));
        let mut columns = (0..174).collect::<Vec<_>>();
        columns.sort_by(|&a, &b| {
            reliability[b]
                .abs()
                .total_cmp(&reliability[a].abs())
                .then(a.cmp(&b))
        });
        let mut rows = generator.to_vec();
        let mut basis = vec![];
        for &column in &columns {
            budget.checkpoint().await?;
            let rank = basis.len();
            let Some(pivot) = (rank..rows.len()).find(|&i| rows[i].bit(column)) else {
                continue;
            };
            rows.swap(rank, pivot);
            let row = rows[rank];
            for (i, other) in rows.iter_mut().enumerate() {
                if i != rank && other.bit(column) {
                    *other = other.xor(row);
                }
            }
            basis.push(column);
            if basis.len() == rows.len() {
                break;
            }
        }
        if basis.len() != rows.len() {
            return Ok(None);
        }
        let mut hard = Bits::default();
        for (i, &value) in reliability.iter().enumerate() {
            if value < 0. {
                hard.set(i);
            }
        }
        let mut zero = Bits::default();
        for (&column, &row) in basis.iter().zip(&rows) {
            if hard.bit(column) {
                zero = zero.xor(row);
            }
        }
        let mut order = (0..basis.len()).collect::<Vec<_>>();
        order.sort_by(|&a, &b| {
            reliability[basis[a]]
                .abs()
                .total_cmp(&reliability[basis[b]].abs())
                .then(basis[a].cmp(&basis[b]))
        });
        Ok(Some(Self {
            rows,
            parity_columns: columns.into_iter().filter(|i| !basis.contains(i)).collect(),
            order,
            hard,
            zero,
            weights: std::array::from_fn(|i| reliability[i].abs() as f64),
        }))
    }
    fn cost(&self, word: Bits) -> f64 {
        let differences = word.xor(self.hard);
        self.weights
            .iter()
            .enumerate()
            .filter(|&(i, _)| differences.bit(i))
            .map(|(_, &weight)| weight)
            .sum()
    }
    fn admissible(&self, word: Bits, weight: usize) -> bool {
        self.parity_columns
            .iter()
            .take(40)
            .filter(|&&i| word.bit(i) != self.hard.bit(i))
            .count()
            + weight
            <= 10
    }
    async fn nearest(&self, budget: &mut CpuBudget<'_>) -> Result<Option<Bits>, DecodeError> {
        let (mut best, mut cost) = (self.zero, self.cost(self.zero));
        #[cfg(test)]
        tests::record(tests::Event::Pattern(0, true));
        for (position, &i) in self.order.iter().enumerate() {
            budget.checkpoint().await?;
            let single = self.zero.xor(self.rows[i]);
            let admitted = self.admissible(single, 1);
            #[cfg(test)]
            tests::record(tests::Event::Pattern(1, admitted));
            if admitted {
                let value = self.cost(single);
                if value < cost {
                    (best, cost) = (single, value);
                }
            }
            for &j in &self.order[position + 1..] {
                budget.checkpoint().await?;
                let pair = single.xor(self.rows[j]);
                let admitted = self.admissible(pair, 2);
                #[cfg(test)]
                tests::record(tests::Event::Pattern(2, admitted));
                if admitted {
                    let value = self.cost(pair);
                    if value < cost {
                        (best, cost) = (pair, value);
                    }
                }
            }
        }
        Ok(Some(best))
    }
}

#[cfg(test)]
#[path = "deep_channel_test.rs"]
mod tests;
