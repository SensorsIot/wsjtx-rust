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
pub(super) fn fit_coefficients(
    cc: f64,
    ss: f64,
    cs: f64,
    xc: f64,
    xs: f64,
) -> Option<(f64, f64, f64)> {
    Gram { cc, ss, cs, xc, xs }.solve()
}
