//! Bounded nuisance-tone likelihood, evaluated without subtracting large common logs.
use super::DecodeError;
#[derive(Clone, Copy, Debug)]
pub(super) struct PeerNoise {
    pub energy: f64,
    pub offset: i32,
}
#[derive(Clone, Copy, Debug)]
pub(super) struct LikelihoodContext {
    pub variance: f64,
    pub signal: f64,
    pub peer: Option<PeerNoise>,
}
#[derive(Clone, Copy)]
struct AccurateSum {
    hi: f64,
    lo: f64,
}
impl AccurateSum {
    fn of(values: impl Iterator<Item = f64>) -> Self {
        let (mut s, mut c) = (0f64, 0f64);
        for x in values {
            let t = s + x;
            c += if s.abs() >= x.abs() {
                (s - t) + x
            } else {
                (x - t) + s
            };
            s = t;
        }
        let hi = s + c;
        Self {
            hi,
            lo: (s - hi) + c,
        }
    }
    fn cmp(self, other: Self) -> std::cmp::Ordering {
        self.hi
            .total_cmp(&other.hi)
            .then(self.lo.total_cmp(&other.lo))
    }
    fn difference(self, other: Self) -> f64 {
        (self.hi - other.hi) + (self.lo - other.lo)
    }
}
pub(super) fn logsum(a: &[f64]) -> f64 {
    let m = a.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    if !m.is_finite() {
        return m;
    }
    m + a.iter().map(|&x| (x - m).exp()).sum::<f64>().ln()
}
/// Rows are neighbor contexts, columns are physical tone indices; unused columns stay zero.
pub(super) fn scores(
    energies: &[[f64; 8]],
    q: usize,
    context: LikelihoodContext,
) -> Result<Vec<[f64; 8]>, DecodeError> {
    let LikelihoodContext {
        variance: v,
        signal: s,
        peer,
    } = context;
    if !matches!(q, 4 | 8)
        || energies.is_empty()
        || energies.len() > 16
        || !v.is_finite()
        || v < 1e-20
        || !s.is_finite()
        || s < 0.
        || energies
            .iter()
            .any(|row| row[..q].iter().any(|e| !e.is_finite() || *e < 0.))
    {
        return Err(DecodeError::InvalidSamples);
    }
    let Some(PeerNoise {
        energy: i,
        offset: d,
    }) = peer
    else {
        let out = energies
            .iter()
            .map(|row| std::array::from_fn(|k| if k < q { row[k] / v } else { 0. }))
            .collect::<Vec<_>>();
        if out
            .iter()
            .any(|row: &[f64; 8]| row[..q].iter().any(|x| !x.is_finite()))
        {
            return Err(DecodeError::InvalidSamples);
        }
        return Ok(out);
    };
    if !i.is_finite() || i < 0. || !(v + s + i).is_finite() {
        return Err(DecodeError::InvalidSamples);
    }
    if s == 0. {
        return Ok(vec![[0.; 8]; energies.len()]);
    }
    let uncovered = |e: &[f64; 8], t: usize, u: i64| {
        AccurateSum::of(
            e[..q]
                .iter()
                .enumerate()
                .filter(|&(k, _)| k != t && k as i64 != u)
                .map(|(_, e)| *e),
        )
    };
    let mut reference = AccurateSum {
        hi: f64::INFINITY,
        lo: 0.,
    };
    for row in energies {
        for t in 0..q {
            for j in 0..q {
                let value = uncovered(row, t, i64::from(d) + j as i64);
                if value.cmp(reference).is_lt() {
                    reference = value;
                }
            }
        }
    }
    if !reference.hi.is_finite() || !reference.lo.is_finite() {
        return Err(DecodeError::InvalidSamples);
    }
    let ls = (s / v).ln_1p();
    let li = (i / v).ln_1p();
    let lsi = ((s + i) / v).ln_1p();
    let mut result = Vec::with_capacity(energies.len());
    for row in energies {
        let mut output = [0.; 8];
        for t in 0..q {
            let mut components = [0.; 8];
            for (j, component) in components[..q].iter_mut().enumerate() {
                let u = i64::from(d) + j as i64;
                let missing = uncovered(row, t, u).difference(reference) / v;
                *component = if u == t as i64 {
                    -missing - row[t] / (v + s + i) - lsi
                } else if (0..q as i64).contains(&u) {
                    -missing - row[t] / (v + s) - row[u as usize] / (v + i) - ls - li
                } else {
                    -missing - row[t] / (v + s) - ls
                };
                if !component.is_finite() {
                    return Err(DecodeError::InvalidSamples);
                }
            }
            output[t] = logsum(&components[..q]) - (q as f64).ln();
        }
        result.push(output);
    }
    Ok(result)
}
