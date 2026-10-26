use super::*;
// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn sampled_gram_projection_matches_independent_alias_oracles() {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/fit-metric-cases.json"
    ))
    .unwrap();
    let frames = fixture["support_frames"].as_u64().unwrap() as usize;
    let rows = fixture["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 8);
    for row in rows {
        let frequency = row["frequency_hz"].as_f64().unwrap();
        let mut wave = Vec::with_capacity(frames);
        let mut samples = Vec::with_capacity(frames);
        for k in 0..frames {
            let t = (k + 1) as f64 / 12000.;
            let modulation = 0.4 * (2. * PI * t / 0.048).sin();
            wave.push([modulation.cos() as f32, modulation.sin() as f32]);
            let phase = 2. * PI * frequency * t + modulation;
            samples.push((0.6 * phase.cos() - 0.8 * phase.sin()) as f32);
        }
        let actual = coherent(&samples, 0, &wave, &[(288, frames - 288)], frequency, 4);
        let expected = row["expected_explained_energy"].as_f64().unwrap();
        assert!(
            (actual - expected).abs() <= expected * 5e-7,
            "{frequency}Hz: actual{actual}, independent{expected}"
        );
    }
}
