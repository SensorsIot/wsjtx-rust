use super::Mode;
use std::f64::consts::PI;
pub(super) fn erf(x: f64) -> f64 {
    let a = x.abs();
    if a >= 6. {
        return x.signum();
    }
    let mut t = 1.;
    let mut s = 1.;
    for n in 1..150 {
        t *= 2. * a * a / (2 * n + 1) as f64;
        s += t;
        if t <= s * 1e-17 {
            break;
        }
    }
    x.signum() * (2. * a / PI.sqrt() * (-a * a).exp() * s).min(1.)
}
/// Gaussian-smoothed continuous-phase unit quadratures, including pulse and amplitude ramps.
/// The origin is the start of the first symbol; phase advances before the first sample.
pub fn quadratures(mode: Mode, tones: &[u8], frequency: f64) -> Option<Vec<[f32; 2]>> {
    if tones.len() != mode.symbol_count()
        || tones.iter().any(|&t| t as usize >= mode.tone_count())
        || !frequency.is_finite()
    {
        return None;
    }
    let n = mode.symbol_frames();
    let len = n * tones.len();
    let bt = if mode == Mode::Ft8 { 2. } else { 1. };
    let k = PI * (2. / 2f64.ln()).sqrt();
    let mut frequency_offset = vec![0.; len];
    for (j, &tone) in tones.iter().enumerate() {
        if tone == 0 {
            continue;
        }
        let center = j as isize * n as isize + n as isize / 2;
        let lo = (center - 2 * n as isize).max(0) as usize;
        let hi = (center + 2 * n as isize).min(len as isize) as usize;
        for (s, f) in frequency_offset.iter_mut().enumerate().take(hi).skip(lo) {
            let t = (s as f64 + 0.5 - center as f64) / n as f64;
            *f +=
                tone as f64 * mode.spacing() * (erf(k * bt * (t + 0.5)) - erf(k * bt * (t - 0.5)))
                    / 2.;
        }
    }
    let ramp = if mode == Mode::Ft8 { n / 8 } else { n };
    let mut phase = 0.;
    let mut out = Vec::with_capacity(len);
    for (i, off) in frequency_offset.into_iter().enumerate() {
        phase = (phase + 2. * PI * (frequency + off) / 12000.) % (2. * PI);
        let amp = if i < ramp {
            (1. - (PI * i as f64 / ramp as f64).cos()) / 2.
        } else if i >= len - ramp {
            (1. - (PI * (len - 1 - i) as f64 / ramp as f64).cos()) / 2.
        } else {
            1.
        };
        out.push([(amp * phase.cos()) as f32, (amp * phase.sin()) as f32]);
    }
    Some(out)
}
