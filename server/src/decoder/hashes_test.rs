// Proves: CL-024-01; TC-024-001 (#24 S1). The station's call hash table learns the calls
// WSJT-X's packjt77 saves and fills hashed calls in as unpack77 (nrx=1) does; the pure
// unpack is unchanged.
use super::{CallKind, Fields, HashTable, MAX_HASH22, Payload, ihashcall, unpack, unpack_with};
use crate::transmit::pack;

fn bits(values: &[(u128, usize)]) -> [u8; 77] {
    let mut out = [0; 77];
    let mut at = 0;
    for &(v, w) in values {
        for i in (0..w).rev() {
            out[at] = ((v >> i) & 1) as u8;
            at += 1;
        }
    }
    assert_eq!(at, 77);
    out
}
fn h(call: &str, m: u32) -> u128 {
    u128::from(ihashcall(call, m).unwrap())
}
const K1ABC: u128 = 10_214_965;
const W9XYZ: u128 = 12_751_800;
/// 0.1 DXpedition "K1ABC RR73; W9XYZ <hashed> -12".
fn dxpedition(hashed: &str) -> [u8; 77] {
    bits(&[
        (K1ABC, 28),
        (W9XYZ, 28),
        (h(hashed, 10), 10),
        (9, 5),
        (1, 3),
        (0, 3),
    ])
}
/// i3=5 EU VHF "<to> <from> R 570001 JN37VL".
fn vhf(to: &str, from: &str) -> [u8; 77] {
    let grid = ((((9 * 18 + 13) * 10 + 3) * 10 + 7) * 24 + 21) * 24 + 11;
    bits(&[
        (h(to, 12), 12),
        (h(from, 22), 22),
        (1, 1),
        (5, 3),
        (1, 11),
        (grid, 25),
        (5, 3),
    ])
}
fn packed(text: &str) -> [u8; 77] {
    pack(text).unwrap_or_else(|e| panic!("{text}: {e:?}")).bits
}
fn heard(t: &mut HashTable, text: &str) {
    let p = t.resolve(&unpack(&packed(text)));
    t.learn(&p);
}
fn shown(t: &HashTable, b: &[u8; 77]) -> String {
    let p = t.resolve(&unpack(b));
    assert_eq!(p, unpack_with(b, Some(t)));
    p.text.unwrap()
}
fn to_call(p: &Payload) -> serde_json::Value {
    match &p.fields {
        Some(Fields::Standard { to, .. }) => serde_json::to_value(to).unwrap(),
        f => panic!("{f:?}"),
    }
}

#[test]
fn hashed_calls_fill_in_from_heard_calls_and_stay_unknown_otherwise() {
    let m1 = packed("<PJ4/K1ABC> W9XYZ -05");
    let pure = unpack(&m1);
    assert_eq!(pure.text.as_deref(), Some("<...> W9XYZ -05"));
    assert_eq!(
        to_call(&pure),
        serde_json::json!({"kind":"hash","text":null,"hash_bits":22,"hash_value":h("PJ4/K1ABC",22)})
    );
    let mut t = HashTable::new();
    assert_eq!(t.resolve(&pure), pure, "an empty table fills nothing in");

    for text in [
        "CQ PJ4/K1ABC",
        "CQ K1ABC/R FN42",
        "CQ K1ABC FN42",
        "W9XYZ DL1ABC JO62",
        "VK9/K1XX <W9XYZ>",
    ] {
        heard(&mut t, text);
    }
    let filled = t.resolve(&pure);
    assert_eq!(filled.text.as_deref(), Some("<PJ4/K1ABC> W9XYZ -05"));
    assert_eq!(
        to_call(&filled),
        serde_json::json!({"kind":"hash","text":"PJ4/K1ABC","hash_bits":22,"hash_value":h("PJ4/K1ABC",22)})
    );
    assert_eq!(filled.payload77, pure.payload77);
    for (text, expected) in [
        ("<K1ABC/R> W9XYZ", "<K1ABC/R> W9XYZ"),
        ("<DL1ABC> PA/K1XX", "<DL1ABC> PA/K1XX"),
        // A 'to' call teaches nothing, nor the full 'to' call of a hash-'from' message.
        ("<W9XYZ> PA/K1XX", "<...> PA/K1XX"),
        ("<VK9/K1XX> W9XYZ", "<...> W9XYZ"),
        ("PA/K1XX <DL1ABC> RR73", "PA/K1XX <DL1ABC> RR73"),
    ] {
        assert_eq!(shown(&t, &packed(text)), expected);
        assert!(
            unpack(&packed(text)).text.unwrap().contains("<...>"),
            "{text}"
        );
    }
    let dx = dxpedition("KH1/KH7Z");
    assert_eq!(shown(&t, &dx), "K1ABC RR73; W9XYZ <...> -12");
    heard(&mut t, "CQ KH1/KH7Z");
    assert_eq!(shown(&t, &dx), "K1ABC RR73; W9XYZ <KH1/KH7Z> -12");
    assert_eq!(
        unpack(&dx).text.as_deref(),
        Some("K1ABC RR73; W9XYZ <...> -12")
    );
}

#[test]
fn my_call_fills_the_to_slot_even_after_the_list_has_dropped_it() {
    let mut t = HashTable::new();
    heard(&mut t, "CQ PJ4/K1ABC");
    heard(&mut t, "CQ K1ABC FN42");
    let mine = packed("<HB9BLA> K1ABC -05");
    assert_eq!(shown(&t, &mine), "<...> K1ABC -05");
    t.set_my_call(Some("hb9bla"));
    assert_eq!(t.my_call(), Some("HB9BLA"));
    assert_eq!(
        shown(&t, &packed("<HB9BLA> PJ4/K1ABC")),
        "<HB9BLA> PJ4/K1ABC"
    );
    assert_eq!(shown(&t, &mine), "<HB9BLA> K1ABC -05");
    // unpack77 nrx=1 fills my call into the nonstandard hash only in the 'to' slot.
    assert_eq!(
        shown(&t, &packed("PJ4/K1ABC <HB9BLA> RR73")),
        "PJ4/K1ABC <...> RR73"
    );
    assert_eq!(
        shown(&t, &vhf("HB9BLA", "K1ABC")),
        "<HB9BLA> <K1ABC> R 570001 JN37VL"
    );
    assert_eq!(
        unpack(&vhf("HB9BLA", "K1ABC")).text.as_deref(),
        Some("<...> <...> R 570001 JN37VL")
    );
    let old = packed("<PJ4/K1ABC> W9XYZ -05");
    assert_eq!(shown(&t, &old), "<PJ4/K1ABC> W9XYZ -05");
    for i in 0..MAX_HASH22 {
        t.save(&format!("Q{i:04}ZZ"));
    }
    assert_eq!(
        shown(&t, &old),
        "<...> W9XYZ -05",
        "the oldest call fell out"
    );
    assert_eq!(shown(&t, &packed("W9XYZ <HB9BLA>")), "W9XYZ <...>");
    assert_eq!(
        shown(&t, &mine),
        "<HB9BLA> K1ABC -05",
        "my call stays known"
    );
    t.set_my_call(None);
    assert_eq!(shown(&t, &mine), "<...> K1ABC -05");
}

#[test]
fn the_later_of_two_calls_with_one_hash_wins() {
    let mut seen = std::collections::HashMap::new();
    let (a, b) = (0..)
        .map(|i| format!("C{i}X"))
        .find_map(|c| {
            let k = ihashcall(&c, 12).unwrap();
            seen.insert(k, c.clone()).map(|a| (a, c))
        })
        .unwrap();
    let mut t = HashTable::new();
    t.save(&a);
    t.save(&b);
    assert_eq!(
        shown(&t, &packed(&format!("<{a}> PA/K1XX"))),
        format!("<{b}> PA/K1XX")
    );
    t.save(&a);
    assert_eq!(
        shown(&t, &packed(&format!("<{b}> PA/K1XX"))),
        format!("<{a}> PA/K1XX")
    );
}

#[test]
fn sent_messages_teach_their_calls() {
    let mut t = HashTable::new();
    for text in [
        "<VP2X/K1JT> HB9BLA",
        "CQ YW18FIFA",
        "K1ABC W9XYZ R-07",
        "DL1ABC/P HB9BLA -05",
    ] {
        let p = pack(text).unwrap();
        t.learn_sent(&unpack(&p.bits), &p.text);
    }
    for (text, expected) in [
        ("<VP2X/K1JT> W9XYZ", "<VP2X/K1JT> W9XYZ"),
        ("<YW18FIFA> PA/K1XX", "<YW18FIFA> PA/K1XX"),
        ("<K1ABC> PA/K1XX", "<K1ABC> PA/K1XX"),
        ("<W9XYZ> PA/K1XX", "<W9XYZ> PA/K1XX"),
        ("<HB9BLA> PA/K1XX", "<HB9BLA> PA/K1XX"),
        // A sent /P call teaches its base call (pack28 stages the base).
        ("<DL1ABC> PA/K1XX", "<DL1ABC> PA/K1XX"),
        ("<DL1ABC/P> W9XYZ", "<...> W9XYZ"),
    ] {
        assert_eq!(shown(&t, &packed(text)), expected);
    }
    let free = pack("TNX 73 GL").unwrap();
    let mut empty = HashTable::new();
    empty.learn_sent(&unpack(&free.bits), &free.text);
    assert_eq!(shown(&empty, &packed("<TNX> PA/K1XX")), "<...> PA/K1XX");
    assert!(matches!(
        unpack(&packed("<VP2X/K1JT> W9XYZ")).fields,
        Some(Fields::Standard { ref to, .. }) if to.kind == CallKind::Hash && to.text.is_none()
    ));
}

// Proves: CL-024-01; TC-024-003 (f). unpack77's nonstandard DX-call rule: a 'to' hash equal
// to my 12-bit hash is my call when the full call is the contact's DX call, even when
// calls12 holds another call with that hash.
#[test]
fn the_dx_call_rule_prefers_my_call_over_a_colliding_call() {
    let mine = ihashcall("HB9BLA", 12).unwrap();
    let x = (0..)
        .map(|i| format!("C{i}X"))
        .find(|c| ihashcall(c, 12) == Some(mine))
        .unwrap();
    let mut t = HashTable::new();
    t.set_my_call(Some("HB9BLA"));
    t.save(&x);
    let to_me = packed("<HB9BLA> PJ4/K1ABC");
    assert_eq!(shown(&t, &to_me), format!("<{x}> PJ4/K1ABC"));
    t.set_dx_call(Some("PJ4/K1ABC"));
    assert_eq!(t.dx_call(), Some("PJ4/K1ABC"));
    assert_eq!(shown(&t, &to_me), "<HB9BLA> PJ4/K1ABC");
    assert_eq!(
        shown(&t, &packed("<HB9BLA> PA/K1XX")),
        format!("<{x}> PA/K1XX"),
        "only from the DX call"
    );
    t.set_dx_call(None);
    assert_eq!(shown(&t, &to_me), format!("<{x}> PJ4/K1ABC"));
}

// Proves: CL-024-01; TC-024-010 (#24 S4a). unpack77 n3=1, nrx=1: a 0.1 hash equal to the
// 10-bit hash of the current DX call shows the DX call, also over a colliding calls10
// entry; another or a too-short DX call leaves the table entry; my call is not filled in.
#[test]
fn a_dxpedition_hash_of_the_dx_call_shows_the_dx_call() {
    let dx = dxpedition("KH1/KH7Z");
    let mut t = HashTable::new();
    assert_eq!(shown(&t, &dx), "K1ABC RR73; W9XYZ <...> -12");
    t.set_dx_call(Some("kh1/kh7z"));
    assert_eq!(shown(&t, &dx), "K1ABC RR73; W9XYZ <KH1/KH7Z> -12");
    // A heard call with the same 10-bit hash: the DX call still wins.
    let target = ihashcall("KH1/KH7Z", 10).unwrap();
    let other = (0..100_000)
        .map(|n| format!("K{}ABC", n))
        .find(|c| ihashcall(c, 10) == Some(target) && c.len() <= 11)
        .expect("a 10-bit collision");
    let mut t = HashTable::new();
    heard(&mut t, &format!("CQ {other}"));
    assert_eq!(shown(&t, &dx), format!("K1ABC RR73; W9XYZ <{other}> -12"));
    t.set_dx_call(Some("KH1/KH7Z"));
    assert_eq!(shown(&t, &dx), "K1ABC RR73; W9XYZ <KH1/KH7Z> -12");
    t.set_dx_call(Some("K1ABC"));
    assert_eq!(shown(&t, &dx), format!("K1ABC RR73; W9XYZ <{other}> -12"));
    // A 2-character DX call is refused although the payload carries exactly its hash.
    let mut t = HashTable::new();
    t.set_dx_call(Some("KH"));
    assert_eq!(t.dx_call(), None);
    assert_eq!(shown(&t, &dxpedition("KH")), "K1ABC RR73; W9XYZ <...> -12");
    // My call is filled into a 0.1 only when rendering my own transmission (nrx=0).
    let mut t = HashTable::new();
    t.set_my_call(Some("HB9BLA"));
    assert_eq!(
        shown(&t, &dxpedition("HB9BLA")),
        "K1ABC RR73; W9XYZ <...> -12"
    );
    assert_eq!(
        unpack(&dx).text.as_deref(),
        Some("K1ABC RR73; W9XYZ <...> -12")
    );
}
