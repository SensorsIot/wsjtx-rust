use super::Mode;
#[derive(Clone, Copy, Default)]
struct Gram {
    cc: f64,
    ss: f64,
    cs: f64,
    xc: f64,
    xs: f64,
}
impl Gram {
    fn from(samples: &[f32], wave: &[[f32; 2]]) -> Self {
        let mut g = Self::default();
        for (&x, q) in samples.iter().zip(wave) {
            let (c, s) = (q[0] as f64, q[1] as f64);
            g.cc += c * c;
            g.ss += s * s;
            g.cs += c * s;
            g.xc += x as f64 * c;
            g.xs += x as f64 * s;
        }
        g
    }
    fn add(&mut self, other: Self) {
        self.cc += other.cc;
        self.ss += other.ss;
        self.cs += other.cs;
        self.xc += other.xc;
        self.xs += other.xs;
    }
    fn solve(self) -> Option<(f64, f64, f64)> {
        let det = self.cc * self.ss - self.cs * self.cs;
        if !det.is_finite() || det <= 1e-12 * self.cc * self.ss {
            return None;
        }
        let a = (self.xc * self.ss - self.xs * self.cs) / det;
        let b = (self.xs * self.cc - self.xc * self.cs) / det;
        let explained = a * self.xc + b * self.xs;
        if !a.is_finite() || !b.is_finite() || !explained.is_finite() {
            return None;
        }
        Some((a, b, explained.max(0.)))
    }
}
pub(super) fn fit_signal(
    samples: &[f32],
    start: usize,
    wave: &[[f32; 2]],
) -> Option<(f64, f64, f64)> {
    let end = start.checked_add(wave.len())?;
    Gram::from(samples.get(start..end)?, wave).solve()
}
/// Both projections use exactly the same current-pass samples and refined full support.
pub(super) fn phase_agreement(
    samples: &[f32],
    start: usize,
    wave: &[[f32; 2]],
    mode: Mode,
) -> Option<f64> {
    let n = mode.symbol_frames();
    if wave.len() != n * mode.symbol_count() {
        return None;
    }
    let x = samples.get(start..start.checked_add(wave.len())?)?;
    let group_size = if mode == Mode::Ft8 { 7 } else { 4 };
    let (mut individual, mut coherent) = (0., 0.);
    let mut group = Gram::default();
    for (symbol, (x, q)) in x.chunks_exact(n).zip(wave.chunks_exact(n)).enumerate() {
        let gram = Gram::from(x, q);
        individual += gram.solve()?.2;
        group.add(gram);
        if (symbol + 1) % group_size == 0 || symbol + 1 == mode.symbol_count() {
            coherent += group.solve()?.2;
            group = Gram::default();
        }
    }
    if individual <= 0. || !individual.is_finite() {
        return None;
    }
    let ratio = coherent / individual;
    ratio.is_finite().then_some(ratio)
}
