use super::super::Channel;
use super::*;

fn calls() -> APriori {
    APriori {
        my_call: Some([0; 29]),
        dx_call: Some([1; 29]),
        rx_hz: 1500.,
        tx_hz: 2000.,
        ..APriori::default()
    }
}

// Proves: FR-003, CL-007-03 (#56 slice 5). WSJT-X's naptypes per QSO state, lapcqonly, the
// MyCall/DxCall availability rules and the 50 Hz napwid (FT8: Rx or Tx, FT4: Rx only).
#[test]
fn a_priori_types_follow_the_wsjtx_state_table() {
    use QsoProgress::*;
    let mut ap = calls();
    for (progress, ft8, ft4) in [
        (Calling, vec![1, 2], vec![1, 2]),
        (Replying, vec![2, 3], vec![2, 3]),
        (Report, vec![2, 3], vec![2, 3]),
        (RogerReport, vec![3, 4, 5, 6], vec![3, 6]),
        (Rogers, vec![3, 4, 5, 6], vec![3, 6]),
        (Signoff, vec![3, 1, 2], vec![3, 1, 2]),
    ] {
        ap.progress = progress;
        assert_eq!(types(Mode::Ft8, &ap, 1500.), ft8, "{progress:?}");
        assert_eq!(types(Mode::Ft4, &ap, 1500.), ft4, "{progress:?}");
    }
    ap.progress = Rogers;
    assert_eq!(
        types(Mode::Ft8, &ap, 1551.),
        Vec::<u8>::new(),
        "beyond napwid"
    );
    assert_eq!(types(Mode::Ft8, &ap, 2049.), vec![3, 4, 5, 6], "near Tx");
    assert_eq!(
        types(Mode::Ft4, &ap, 2049.),
        Vec::<u8>::new(),
        "FT4: Rx only"
    );
    ap.dx_call = None;
    assert_eq!(types(Mode::Ft8, &ap, 1500.), Vec::<u8>::new(), "no DxCall");
    ap.progress = Calling;
    assert_eq!(types(Mode::Ft8, &ap, 1500.), vec![1, 2]);
    ap.my_call = None;
    assert_eq!(types(Mode::Ft8, &ap, 1500.), vec![1], "no MyCall");
    let mut ap = calls();
    ap.progress = Rogers;
    ap.cq_only = true;
    assert_eq!(types(Mode::Ft8, &ap, 1500.), vec![1], "lapcqonly");
    assert_eq!(types(Mode::Ft8, &APriori::default(), 1500.), vec![1]);
}

// Detail test of WstxModemDecode (#56 slice 5). The fixed bits are the packed message bits: CQ token and i3
// for FT8 type 1, MyCall/DxCall from the packed calls, RRR/73/RR73 tails, FT4 scrambled and
// without i3 for types 1..3.
#[test]
fn a_priori_bits_are_the_packed_message_bits() {
    let channel = Channel::new();
    let message = |text: &str| crate::transmit::pack(text).unwrap().bits;
    let my: [u8; 29] = message("HB9BLA K1ABC RRR")[..29].try_into().unwrap();
    let dx: [u8; 29] = message("HB9BLA K1ABC RRR")[29..58].try_into().unwrap();
    let ap = APriori {
        my_call: Some(my),
        dx_call: Some(dx),
        ..APriori::default()
    };
    for (kind, text, count) in [
        (1, "CQ K1ABC FN42", 32),
        (2, "HB9BLA W9XYZ FN42", 32),
        (3, "HB9BLA K1ABC FN42", 61),
        (4, "HB9BLA K1ABC RRR", 77),
        (5, "HB9BLA K1ABC 73", 77),
        (6, "HB9BLA K1ABC RR73", 77),
    ] {
        let bits = message(text);
        let fixed = fixed_bits(Mode::Ft8, kind, &ap);
        assert_eq!(fixed.len(), count, "type {kind}");
        assert!(
            fixed.iter().all(|&(i, b)| bits[i] == b),
            "type {kind} {text}"
        );
        let ft4 = fixed_bits(Mode::Ft4, kind, &ap);
        let word = channel.encode(&bits, Mode::Ft4);
        assert_eq!(ft4.len(), if kind <= 3 { count - 3 } else { 77 });
        assert!(
            ft4.iter().all(|&(i, b)| word[i] == b),
            "FT4 type {kind} {text}"
        );
    }
}

// Proves: CL-007-03 (#56 slice 5). WSJT-X's qual = 1 - (nharderrors + dmin)/60 >= 0.17.
#[test]
fn low_confidence_boundary() {
    let word = [0u8; 174];
    let mut llr = [1f32; 174];
    assert!(confident(&word, &llr, 0));
    for l in llr.iter_mut().take(24) {
        *l = -1.;
    }
    // 24 errors + dmin 24 = 48 <= 49.8.
    assert!(confident(&word, &llr, 24));
    for l in llr.iter_mut().take(25) {
        *l = -1.;
    }
    // 25 + 25 = 50 > 49.8.
    assert!(!confident(&word, &llr, 25));
}
