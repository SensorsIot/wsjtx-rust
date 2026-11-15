#[derive(Clone, Copy, Default)]
struct Gram {
    cc: f64,
    ss: f64,
    cs: f64,
    xc: f64,
    xs: f64,
}
impl Gram {
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
pub(super) fn fit_coefficients(
    cc: f64,
    ss: f64,
    cs: f64,
    xc: f64,
    xs: f64,
) -> Option<(f64, f64, f64)> {
    Gram { cc, ss, cs, xc, xs }.solve()
}
