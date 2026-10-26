#![forbid(unsafe_code)]
use serde_json::Value;
use wstx_rust::decoder::{Channel, Mode, unpack};
fn bits(s: &str) -> [u8; 77] {
    s.bytes()
        .map(|c| c - b'0')
        .collect::<Vec<_>>()
        .try_into()
        .unwrap()
}
#[test]
fn frozen_payload_channel_tone_vectors() {
    let manifest: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let c = Channel::new();
    let vectors = manifest["vectors"].as_array().unwrap();
    assert_eq!(vectors.len(), 38);
    for v in vectors {
        let id = format!("{} {}", v["id"], v["mode"]);
        let p = bits(v["payload77"].as_str().unwrap());
        let mode = if v["mode"] == "ft4" {
            Mode::Ft4
        } else {
            Mode::Ft8
        };
        let decoded = unpack(&p);
        assert_eq!(
            serde_json::to_value(decoded.fields).unwrap(),
            v["fields"],
            "fields {id}"
        );
        assert_eq!(
            serde_json::to_value(decoded.text).unwrap(),
            v["expected_receive"]["text"],
            "text {id}"
        );
        let word = c.encode(&p, mode);
        let expected = v["codeword174"].as_str().unwrap();
        assert_eq!(
            word.iter().map(|&b| (b + b'0') as char).collect::<String>(),
            expected,
            "codeword {id}"
        );
        assert!(c.valid(&word), "syndrome {id}");
        assert_eq!(
            c.tones(&word, mode)
                .iter()
                .map(|&t| (t + b'0') as char)
                .collect::<String>(),
            v["tones"].as_str().unwrap(),
            "tones {id}"
        );
        let llr = std::array::from_fn(|i| if word[i] == 0 { 6. } else { -6. });
        assert_eq!(c.decode(&llr, &|| false), Some(word), "fec {id}");
    }
}
#[test]
fn canonical_payload_boundaries() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/payload-boundary-cases.json"
    ))
    .unwrap();
    let cases = fixture["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 103);
    for c in cases {
        let p = unpack(&bits(c["payload77"].as_str().unwrap()));
        assert_eq!(
            serde_json::to_value(p.status).unwrap(),
            c["expected_status"],
            "{} {}",
            c["id"],
            c["expected_changed_field"]
        );
    }
}
#[test]
fn fec_repairs_corruption_and_respects_cancellation() {
    let c = Channel::new();
    let mut p = [0; 77];
    p[70] = 1;
    let word = c.encode(&p, Mode::Ft8);
    let mut llr = std::array::from_fn(|i| if word[i] == 0 { 5. } else { -5. });
    for i in [0, 7, 19, 58, 91, 121] {
        llr[i] *= -0.3;
    }
    assert_eq!(c.decode(&llr, &|| false), Some(word));
    assert_eq!(c.decode(&llr, &|| true), None);
    llr[0] = f32::NAN;
    assert_eq!(c.decode(&llr, &|| false), None);
}
