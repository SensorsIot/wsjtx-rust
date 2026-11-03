// Portions adapted from WSJT-X ft8b.f90, ft8apset.f90 and ft4_decode.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
//! The a-priori (AP) hypotheses of WSJT-X 3.3.0-beta5 for ordinary operation (ncontest=0):
//! which known message bits are fixed for a candidate whose unassisted metric families all
//! failed, given the station's QSO context of the window.
use super::{Mode, channel::MASK};

/// WSJT-X nQSOProgress: the Tx message the station sends next (CALLING=Tx6, REPLYING=Tx1,
/// REPORT=Tx2, ROGER_REPORT=Tx3, ROGERS=Tx4, SIGNOFF=Tx5).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum QsoProgress {
    #[default]
    Calling,
    Replying,
    Report,
    RogerReport,
    Rogers,
    Signoff,
}
/// The station's a-priori context of one decode window. The default (no MyCall) leaves only
/// the CQ hypothesis (type 1), as for a file decode.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct APriori {
    /// Payload bits 0..29 (c28 and its /R flag) of MyCall as the first call of a standard
    /// message (ft8apset apsym 1..29); `None` without a usable MyCall (apsym(1)=99).
    pub my_call: Option<[u8; 29]>,
    /// Payload bits 29..58 of DxCall as the second call (apsym 30..58); `None` without a
    /// usable DxCall (apsym(30)=99).
    pub dx_call: Option<[u8; 29]>,
    pub progress: QsoProgress,
    /// Rx and Tx audio frequencies (nfqso, nftx).
    pub rx_hz: f64,
    pub tx_hz: f64,
    /// lapcqonly: no transmission for 300 s; only the CQ hypothesis runs.
    pub cq_only: bool,
}
/// WSJT-X's AP decoding bandwidth (napwid) for the types that name DxCall.
pub(super) const AP_WIDTH_HZ: f64 = 50.;
/// The 19 tail bits (ir, g15, i3=1) of RRR, 73 and RR73 (grid codes 32402, 32404, 32403).
fn tail(code: u32) -> [u8; 19] {
    std::array::from_fn(|i| match i {
        0 => 0,
        1..=15 => ((code >> (15 - i)) & 1) as u8,
        _ => u8::from(i == 18),
    })
}
/// The AP types WSJT-X tries for this window and candidate, in order (ft8b naptypes /
/// ft4_decode naptypes, then its bail-out conditions).
pub(super) fn types(mode: Mode, ap: &APriori, frequency: f64) -> Vec<u8> {
    use QsoProgress::*;
    let table: &[u8] = if ap.cq_only {
        &[1]
    } else {
        match (mode, ap.progress) {
            (_, Calling) => &[1, 2],
            (_, Replying | Report) => &[2, 3],
            (Mode::Ft8, RogerReport | Rogers) => &[3, 4, 5, 6],
            (Mode::Ft4, RogerReport | Rogers) => &[3, 6],
            (_, Signoff) => &[3, 1, 2],
        }
    };
    // FT8 runs the DxCall types near the Rx or the Tx frequency, FT4 near the Rx frequency.
    let near = (frequency - ap.rx_hz).abs() <= AP_WIDTH_HZ
        || mode == Mode::Ft8 && (frequency - ap.tx_hz).abs() <= AP_WIDTH_HZ;
    table
        .iter()
        .copied()
        .filter(|&kind| match kind {
            1 => true,
            2 => ap.my_call.is_some(),
            _ => ap.my_call.is_some() && ap.dx_call.is_some() && near,
        })
        .collect()
}
/// The fixed channel-word bits of one AP type: (index, bit). FT8 types 1..3 also fix i3=1;
/// FT4's do not. FT4 bits are scrambled with the rvec mask like its payload.
pub(super) fn fixed_bits(mode: Mode, kind: u8, ap: &APriori) -> Vec<(usize, u8)> {
    let mut bits = vec![];
    let calls = |bits: &mut Vec<(usize, u8)>, dx: bool| {
        let my = ap.my_call.expect("MyCall checked by types()");
        bits.extend(my.iter().copied().enumerate());
        if dx {
            let dx = ap.dx_call.expect("DxCall checked by types()");
            bits.extend(dx.iter().copied().enumerate().map(|(i, b)| (29 + i, b)));
        }
    };
    match kind {
        // CQ: c28 = 2, ipa = 0.
        1 => bits.extend((0..29).map(|i| (i, u8::from(i == 26)))),
        2 => calls(&mut bits, false),
        3 => calls(&mut bits, true),
        _ => {
            calls(&mut bits, true);
            let code = match kind {
                4 => 32402,
                5 => 32404,
                _ => 32403,
            };
            bits.extend(tail(code).into_iter().enumerate().map(|(i, b)| (58 + i, b)));
        }
    }
    if mode == Mode::Ft8 && kind <= 3 {
        bits.extend([(74, 0), (75, 0), (76, 1)]);
    }
    if mode == Mode::Ft4 {
        for (i, b) in &mut bits {
            *b ^= MASK[*i] - b'0';
        }
    }
    bits
}
/// The AP channel inputs of one candidate, in WSJT-X's pass order: (type, LLRs, fixed mask).
/// FT8 tries each type on the nsym=1 and then the nsym=3 family, each fixed at 1.1 times that
/// family's largest |LLR|; FT4 tries each type once on its 4-symbol family, fixed at 1.1
/// times the 1-symbol family's largest |LLR|. Positive LLR denotes bit zero.
pub(super) fn hypotheses(
    mode: Mode,
    families: &[[f32; 174]],
    ap: &APriori,
    frequency: f64,
) -> Vec<(u8, [f32; 174], [bool; 174])> {
    let complete = match mode {
        Mode::Ft8 => families.len() == 5,
        Mode::Ft4 => families.len() == 3,
    };
    if !complete {
        return vec![];
    }
    let largest = |llr: &[f32; 174]| llr.iter().fold(0f32, |m, x| m.max(x.abs())) * 1.1;
    let mut out = vec![];
    for kind in types(mode, ap, frequency) {
        let bits = fixed_bits(mode, kind, ap);
        let inputs: Vec<(usize, f32)> = match mode {
            Mode::Ft8 => vec![(0, largest(&families[0])), (2, largest(&families[2]))],
            Mode::Ft4 => vec![(2, largest(&families[0]))],
        };
        for (family, magnitude) in inputs {
            let mut llr = families[family];
            let mut fixed = [false; 174];
            for &(i, b) in &bits {
                llr[i] = if b == 1 { -magnitude } else { magnitude };
                fixed[i] = true;
            }
            out.push((kind, llr, fixed));
        }
    }
    out
}
/// WSJT-X's low-confidence mark: qual = 1 - (nharderrors + dmin)/60 < 0.17, where dmin sums
/// |LLR| over the bits the word disagrees with. An assisted word is published only without it.
pub(super) const LOW_CONFIDENCE_QUALITY: f64 = 0.17;
pub(super) fn confident(word: &[u8; 174], llr: &[f32; 174], hard_errors: usize) -> bool {
    let dmin = (0..174)
        .filter(|&i| (word[i] == 1) != (llr[i] < 0.))
        .map(|i| llr[i].abs() as f64)
        .sum::<f64>();
    1. - (hard_errors as f64 + dmin) / 60. >= LOW_CONFIDENCE_QUALITY
}

#[cfg(test)]
#[path = "apriori_test.rs"]
mod tests;
