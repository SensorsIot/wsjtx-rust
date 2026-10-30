use super::*;
use std::{fs, path::PathBuf};

const PUBLIC: &str =
    "BM3n23Sz_r60-bM-ntSNyhCBIRfFOThu4-DIgnUH3kCuLFq27hJeQOTpHIEIkczfRmkzgVOZZpWBUjCC0ihYrmM";
const GRANT: &str = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc";
const NONCE: &str = "CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk";
const SIGNATURE: &str =
    "fmV2J0aHAwHZpBE5zij_qnWcMNV3RDcuYbMJaVRHCy6n01zzMK_9ak8SO2uj0Nh3W312Clk3qRNN1_QR0QiZxA";
const OP: &str = "00000000-0000-4000-8000-000000000003";
const ORIGIN: &str = "https://station.example:18081";

pub(crate) fn peer_key() -> signature::EcdsaKeyPair {
    let rng = SystemRandom::new();
    let pkcs8 =
        signature::EcdsaKeyPair::generate_pkcs8(&signature::ECDSA_P256_SHA256_FIXED_SIGNING, &rng)
            .unwrap();
    signature::EcdsaKeyPair::from_pkcs8(
        &signature::ECDSA_P256_SHA256_FIXED_SIGNING,
        pkcs8.as_ref(),
        &rng,
    )
    .unwrap()
}
fn peer_verifier(scope: Scope, key: &signature::EcdsaKeyPair) -> Verifier {
    use signature::KeyPair;
    Verifier {
        grant_id: URL_SAFE_NO_PAD.encode([11; 32]),
        enrollment_operation_id: profile::new_uuid().unwrap(),
        public_key: URL_SAFE_NO_PAD.encode(key.public_key().as_ref()),
        scope,
    }
}
fn peer_request(
    a: &mut Authority,
    key: &signature::EcdsaKeyPair,
    grant_id: &str,
    operation: Option<&str>,
    now: Instant,
) -> ProofRequest {
    let nonce = a.challenge(grant_id, ORIGIN, operation, now).unwrap();
    let c = a.challenges.iter().find(|c| c.nonce == nonce).unwrap();
    ProofRequest {
        version: 1,
        grant_id: grant_id.into(),
        nonce: nonce.clone(),
        signature: peer_sign(key, &c.scope, grant_id, &nonce, operation),
    }
}
pub(crate) fn peer_sign(
    key: &signature::EcdsaKeyPair,
    scope: &Scope,
    grant_id: &str,
    nonce: &str,
    operation: Option<&str>,
) -> String {
    // Test peer independently frames the protocol; never calls candidate signed_payload.
    let mut bytes = if operation.is_some() {
        b"WSTX-AUTH-RECEIPT".to_vec()
    } else {
        b"WSTX-AUTH-PROOF".to_vec()
    };
    bytes.push(1);
    let mut fields = vec![
        scope.https_origin.clone().into_bytes(),
        scope.wire.profile_id.clone().into_bytes(),
        scope.wire.radio_id.clone().into_bytes(),
        scope.wire.safety_revision.to_string().into_bytes(),
        grant_id.as_bytes().to_vec(),
    ];
    if let Some(id) = operation {
        fields.push(id.as_bytes().to_vec());
    }
    fields.push(URL_SAFE_NO_PAD.decode(nonce).unwrap());
    for field in fields {
        bytes.extend_from_slice(&(field.len() as u32).to_be_bytes());
        bytes.extend_from_slice(&field);
    }
    URL_SAFE_NO_PAD.encode(key.sign(&SystemRandom::new(), &bytes).unwrap().as_ref())
}

fn scope(profile_id: &str) -> Scope {
    WireScope {
        profile_id: profile_id.into(),
        radio_id: "00000000-0000-4000-8000-000000000002".into(),
        safety_revision: 1,
    }
    .in_validated_origin(ORIGIN)
    .unwrap()
}
fn verifier(scope: Scope) -> Verifier {
    Verifier {
        grant_id: GRANT.into(),
        enrollment_operation_id: OP.into(),
        public_key: PUBLIC.into(),
        scope,
    }
}

struct Fixture {
    directory: PathBuf,
    store: Option<profile::Store>,
    authority: Option<Authority>,
}
impl Fixture {
    fn new() -> Self {
        let directory =
            std::env::temp_dir().join(format!("wstx-auth-core-{}", profile::new_uuid().unwrap()));
        profile::Store::create(&directory).unwrap();
        let (mut store, _) = profile::Store::open(&directory).unwrap();
        let initial = scope(&store.document.profile_id);
        let authority = Authority::load(&mut store, initial).unwrap();
        Self {
            directory,
            store: Some(store),
            authority: Some(authority),
        }
    }
    fn parts(&mut self) -> (&mut profile::Store, &mut Authority) {
        (
            self.store.as_mut().unwrap(),
            self.authority.as_mut().unwrap(),
        )
    }
    fn reopen(&mut self) -> Result<(), Error> {
        self.authority.take();
        self.store.take();
        let (mut store, _) =
            profile::Store::open(&self.directory).map_err(|_| Error::PersistenceFailed)?;
        let initial = scope(&store.document.profile_id);
        let result = Authority::load(&mut store, initial);
        self.store = Some(store);
        match result {
            Ok(authority) => {
                self.authority = Some(authority);
                Ok(())
            }
            Err(e) => Err(e),
        }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.authority.take();
        self.store.take();
        // Only this fixture-created, UUID-named directory is owned by this test.
        fs::remove_dir_all(&self.directory).unwrap();
    }
}

#[test]
fn strict_wire_scope_and_enrollment_reject_duplicate_unknown_omission_and_noncanonical_bytes() {
    let text = format!(
        r#"{{"version":1,"operation_id":"{OP}","scope":{{"profile_id":"00000000-0000-4000-8000-000000000001","radio_id":"00000000-0000-4000-8000-000000000002","safety_revision":1}},"grant_id":"{GRANT}","public_key":"{PUBLIC}"}}"#
    );
    let request: EnrollmentRequest = parse_request(text.as_bytes()).unwrap();
    assert!(request.verifier(ORIGIN).is_ok());
    for bad in [
        text.replace("\"version\":1", "\"version\":1,\"version\":1"),
        text.replace("\"version\":1", "\"version\":1,\"extra\":0"),
        text.replace(
            "\"safety_revision\":1",
            "\"safety_revision\":1,\"https_origin\":\"https://evil.example\"",
        ),
        text.replace("\"version\":1,", ""),
        format!("{}{}", " ".repeat(1024), text),
    ] {
        assert!(parse_request::<EnrollmentRequest>(bad.as_bytes()).is_err());
    }
    let wrong_version = text.replace("\"version\":1", "\"version\":2");
    assert_eq!(
        parse_request::<EnrollmentRequest>(wrong_version.as_bytes())
            .unwrap()
            .verifier(ORIGIN),
        Err(Error::Invalid)
    );
    assert!(decode::<32>(&format!("{GRANT}=")).is_err());
    assert!(decode::<64>(SIGNATURE).is_ok());
    assert!(decode::<65>(SIGNATURE).is_err());
    let raw =
        format!(r#"{{"version":1,"operation_id":"{OP}","expected_scope":null,"change":"add"}}"#);
    assert!(parse_request::<IdentityRequest>(raw.as_bytes()).is_ok());
    assert!(
        parse_request::<IdentityRequest>(raw.replace("\"expected_scope\":null,", "").as_bytes())
            .is_err()
    );
}

#[test]
fn independent_node_openssl_fixed_vector_binds_exact_bytes_purpose_origin_and_revision() {
    let s = scope("00000000-0000-4000-8000-000000000001");
    let nonce = decode::<32>(NONCE).unwrap();
    let bytes = signed_payload(&s, GRANT, &nonce, None).unwrap();
    // Independently constructed and signed using Node24/OpenSSL's IEEE-P1363 ECDSA.
    let expected_hex = "575354582d415554482d50524f4f46010000001d68747470733a2f2f73746174696f6e2e6578616d706c653a31383038310000002430303030303030302d303030302d343030302d383030302d3030303030303030303030310000002430303030303030302d303030302d343030302d383030302d30303030303030303030303200000001310000002b42776348427763484277634842776348427763484277634842776348427763484277634842776348427763000000200909090909090909090909090909090909090909090909090909090909090909";
    assert_eq!(
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>(),
        expected_hex
    );
    let key = decode::<65>(PUBLIC).unwrap();
    let signature = decode::<64>(SIGNATURE).unwrap();
    let public = signature::UnparsedPublicKey::new(&signature::ECDSA_P256_SHA256_FIXED, key);
    assert!(public.verify(&bytes, &signature).is_ok());
    let mut changed = s.clone();
    changed.https_origin.push('0');
    assert!(
        public
            .verify(
                &signed_payload(&changed, GRANT, &nonce, None).unwrap(),
                &signature
            )
            .is_err()
    );
    changed = s.clone();
    changed.wire.safety_revision = 2;
    assert!(
        public
            .verify(
                &signed_payload(&changed, GRANT, &nonce, None).unwrap(),
                &signature
            )
            .is_err()
    );
    assert!(
        public
            .verify(
                &signed_payload(&s, GRANT, &nonce, Some(OP)).unwrap(),
                &signature
            )
            .is_err()
    );
    let mut invalid = verifier(s);
    invalid.public_key = URL_SAFE_NO_PAD.encode([0u8; 65]);
    assert_eq!(validate_verifier(&invalid), Err(Error::Invalid));
}

#[test]
fn valid_proof_is_one_use_and_expiry_wrong_origin_and_wrong_purpose_do_not_consume_it() {
    let now = Instant::now();
    let selected = scope("00000000-0000-4000-8000-000000000001");
    let v = verifier(selected.clone());
    let mut record = Record::initial(selected.clone()).unwrap();
    record.grants.push(v.clone());
    let mut a = Authority {
        record,
        quarantined: false,
        transports: Vec::new(),
        challenges: vec![Challenge {
            nonce: NONCE.into(),
            scope: selected.clone(),
            verifier: v.clone(),
            operation_id: None,
            deadline: now + Duration::from_secs(60),
        }],
    };
    let request: ProofRequest = parse_request(
        format!(
            r#"{{"version":1,"grant_id":"{GRANT}","nonce":"{NONCE}","signature":"{SIGNATURE}"}}"#
        )
        .as_bytes(),
    )
    .unwrap();
    assert_eq!(request.version, 1);
    assert_eq!(
        a.verify_proof(
            &request.grant_id,
            &request.nonce,
            &request.signature,
            "https://wrong.example",
            None,
            now
        ),
        Err(Error::Unauthorized)
    );
    assert_eq!(
        a.verify_proof(GRANT, NONCE, SIGNATURE, ORIGIN, Some(OP), now),
        Err(Error::Unauthorized)
    );
    assert_eq!(
        a.verify_proof(
            GRANT,
            NONCE,
            SIGNATURE,
            ORIGIN,
            None,
            now + Duration::from_secs(60)
        ),
        Err(Error::Unauthorized)
    );
    assert_eq!(a.challenges.len(), 1);
    assert_eq!(
        a.verify_proof(
            GRANT,
            NONCE,
            SIGNATURE,
            ORIGIN,
            None,
            now + Duration::from_secs(59)
        ),
        Ok(VerifiedProof::Control {
            scope: selected,
            grant_id: GRANT.into(),
            generation: 0
        })
    );
    assert!(a.challenges.is_empty());
    assert_eq!(
        a.verify_proof(GRANT, NONCE, SIGNATURE, ORIGIN, None, now),
        Err(Error::Unauthorized)
    );
    assert_eq!(a.record().grants, vec![v]);
}

#[test]
fn committed_verifier_survives_lock_release_reopen_and_has_no_clock_expiry() {
    let mut f = Fixture::new();
    let original_profile = fs::read(f.directory.join("profile.json")).unwrap();
    let (store, a) = f.parts();
    let grant = verifier(a.record.current_scope.clone().unwrap());
    let receipt = a.enroll(store, grant.clone()).unwrap();
    assert_eq!(a.enroll(store, grant.clone()).unwrap(), receipt);
    let committed = fs::read(f.directory.join("authorization.json")).unwrap();
    f.reopen().unwrap();
    let (_, a) = f.parts();
    assert_eq!(a.record.grants, vec![grant]);
    assert!(
        a.challenge(
            GRANT,
            ORIGIN,
            None,
            Instant::now() + Duration::from_secs(400 * 86400)
        )
        .is_ok()
    );
    assert_eq!(
        fs::read(f.directory.join("authorization.json")).unwrap(),
        committed
    );
    assert_eq!(
        fs::read(f.directory.join("profile.json")).unwrap(),
        original_profile
    );
}

#[test]
fn expected_missing_corrupt_and_cross_profile_records_never_reset_grants() {
    for corrupt in [false, true] {
        let mut f = Fixture::new();
        let (store, a) = f.parts();
        a.enroll(store, verifier(a.record.current_scope.clone().unwrap()))
            .unwrap();
        if corrupt {
            fs::write(f.directory.join("authorization.json"), b"{corrupt").unwrap();
        } else {
            fs::remove_file(f.directory.join("authorization.json")).unwrap();
        }
        assert_eq!(f.reopen(), Err(Error::PersistenceFailed));
        assert!(
            !fs::read(f.directory.join(".authorization-initialized.json"))
                .unwrap()
                .is_empty()
        );
    }
    let mut f = Fixture::new();
    let mut record: Record =
        serde_json::from_slice(&fs::read(f.directory.join("authorization.json")).unwrap()).unwrap();
    record.current_scope.as_mut().unwrap().wire.profile_id =
        "00000000-0000-4000-8000-000000000009".into();
    fs::write(
        f.directory.join("authorization.json"),
        serde_json::to_vec(&record).unwrap(),
    )
    .unwrap();
    assert_eq!(f.reopen(), Err(Error::PersistenceFailed));
}

#[test]
fn failed_revocation_keeps_committed_bytes_but_quarantines_current_process() {
    for stage in ["write", "flush", "replace"] {
        let mut f = Fixture::new();
        let (store, a) = f.parts();
        a.enroll(store, verifier(a.record.current_scope.clone().unwrap()))
            .unwrap();
        let old = fs::read(f.directory.join("authorization.json")).unwrap();
        let (store, a) = f.parts();
        let result = profile::tests::with_fault(stage, || {
            a.revoke(store, GRANT, "00000000-0000-4000-8000-000000000004", false)
        });
        assert_eq!(result, Err(Error::PersistenceFailed));
        assert_eq!(
            a.challenge(GRANT, ORIGIN, None, Instant::now()),
            Err(Error::PersistenceFailed)
        );
        assert_eq!(
            fs::read(f.directory.join("authorization.json")).unwrap(),
            old
        );
        f.reopen().unwrap();
        assert_eq!(
            f.authority.as_ref().unwrap().record.grants.len(),
            1,
            "failed write must not claim durable revocation"
        );
    }
}

#[test]
fn committed_revocation_retains_receipt_verifier_without_control_authority() {
    let mut f = Fixture::new();
    let (store, a) = f.parts();
    a.enroll(store, verifier(a.record.current_scope.clone().unwrap()))
        .unwrap();
    a.revoke(store, GRANT, "00000000-0000-4000-8000-000000000004", false)
        .unwrap();
    f.reopen().unwrap();
    let (_, a) = f.parts();
    assert!(a.record.grants.is_empty());
    assert_eq!(a.record.revocation_generation, 1);
    assert_eq!(
        a.challenge(GRANT, ORIGIN, None, Instant::now()),
        Err(Error::Unauthorized)
    );
    assert!(
        a.challenge(
            GRANT,
            ORIGIN,
            Some("00000000-0000-4000-8000-000000000004"),
            Instant::now()
        )
        .is_ok()
    );
    assert_eq!(
        a.record.operation_receipts.back().unwrap().kind,
        OperationKind::Logout
    );
}

#[test]
fn transport_rotation_changes_only_same_grant_slot_and_retains_durable_state() {
    let mut f = Fixture::new();
    let key = peer_key();
    let now = Instant::now();
    let (store, a) = f.parts();
    let va = peer_verifier(a.record.current_scope.clone().unwrap(), &key);
    let mut vb = va.clone();
    vb.grant_id = URL_SAFE_NO_PAD.encode([12; 32]);
    vb.enrollment_operation_id = profile::new_uuid().unwrap();
    a.enroll(store, va.clone()).unwrap();
    a.enroll(store, vb.clone()).unwrap();
    let durable = serde_json::to_vec(a.record()).unwrap();
    let request_a = peer_request(a, &key, &va.grant_id, None, now);
    let old = a
        .prove_transport(&request_a, ORIGIN, now, |_| Ok(()))
        .unwrap();
    let request_b = peer_request(a, &key, &vb.grant_id, None, now);
    let b = a
        .prove_transport(&request_b, ORIGIN, now, |_| Ok(()))
        .unwrap();
    let request = peer_request(a, &key, &va.grant_id, None, now);
    let current = a
        .prove_transport(&request, ORIGIN, now, |_| Ok(()))
        .unwrap();
    assert_eq!(a.transports.len(), 2);
    assert_eq!(a.access(&old, ORIGIN, now), Err(Error::Unauthorized));
    let access = a.access(&current, ORIGIN, now).unwrap();
    a.recheck_dispatch(&access).unwrap();
    a.access(&b, ORIGIN, now).unwrap();
    assert_eq!(serde_json::to_vec(a.record()).unwrap(), durable);
    assert_eq!(
        a.prove_transport(&request, ORIGIN, now, |_| Ok(())),
        Err(Error::Unauthorized)
    );
    assert!(a.access(&current, ORIGIN, now).is_ok());
    let receipt_request = peer_request(
        a,
        &key,
        &va.grant_id,
        Some(&va.enrollment_operation_id),
        now,
    );
    let receipt = a
        .prove_receipt(&receipt_request, &va.enrollment_operation_id, ORIGIN, now)
        .unwrap();
    assert_eq!(receipt.operation_id, va.enrollment_operation_id);
    assert_eq!(a.transports.len(), 2);
    assert!(a.access(&current, ORIGIN, now).is_ok());
    // A dispatch admitted before committed revocation cannot pass its generation fence.
    a.revoke(store, &va.grant_id, &profile::new_uuid().unwrap(), false)
        .unwrap();
    assert_eq!(a.recheck_dispatch(&access), Err(Error::Unauthorized));
    assert_eq!(a.access(&current, ORIGIN, now), Err(Error::Unauthorized));
    assert!(
        a.access(&b, ORIGIN, now).is_ok(),
        "logout must not expire another verifier's handle"
    );
}

#[test]
fn failed_proof_or_response_preparation_preserves_prior_handle_and_consumed_nonce_cannot_replay() {
    let mut f = Fixture::new();
    let key = peer_key();
    let now = Instant::now();
    let (store, a) = f.parts();
    let v = peer_verifier(a.record.current_scope.clone().unwrap(), &key);
    a.enroll(store, v.clone()).unwrap();
    let request = peer_request(a, &key, &v.grant_id, None, now);
    let old = a
        .prove_transport(&request, ORIGIN, now, |_| Ok(()))
        .unwrap();
    let request = peer_request(a, &key, &v.grant_id, None, now);
    assert_eq!(
        a.prove_transport(&request, "https://other.example", now, |_| Ok(())),
        Err(Error::Unauthorized)
    );
    assert!(a.access(&old, ORIGIN, now).is_ok());
    let mut bad = request.clone();
    bad.signature = URL_SAFE_NO_PAD.encode([0; 64]);
    assert_eq!(
        a.prove_transport(&bad, ORIGIN, now, |_| Ok(())),
        Err(Error::Unauthorized)
    );
    assert!(a.access(&old, ORIGIN, now).is_ok());
    assert_eq!(
        a.prove_transport(&request, ORIGIN, now, |_| Err(Error::Invalid)),
        Err(Error::Invalid)
    );
    assert_eq!(
        a.prove_transport(&request, ORIGIN, now, |_| Ok(())),
        Err(Error::Unauthorized)
    );
    assert!(a.access(&old, ORIGIN, now).is_ok());
    assert_eq!(a.transports.len(), 1);
    let request = peer_request(a, &key, &v.grant_id, None, now);
    assert_eq!(
        a.prove_transport(&request, ORIGIN, now + Duration::from_secs(60), |_| Ok(())),
        Err(Error::Unauthorized)
    );
    assert!(
        a.access(&old, ORIGIN, now + Duration::from_secs(60))
            .is_ok()
    );
}

#[test]
fn monotonic_boundary_and_actual_store_reopen_expire_only_volatile_transport() {
    let mut f = Fixture::new();
    let key = peer_key();
    let now = Instant::now();
    let (store, a) = f.parts();
    let v = peer_verifier(a.record.current_scope.clone().unwrap(), &key);
    a.enroll(store, v.clone()).unwrap();
    let request = peer_request(a, &key, &v.grant_id, None, now);
    let token = a
        .prove_transport(&request, ORIGIN, now, |_| Ok(()))
        .unwrap();
    assert!(
        a.access(&token, ORIGIN, now + Duration::from_secs(28799))
            .is_ok()
    );
    assert_eq!(
        a.access(&token, ORIGIN, now + Duration::from_secs(28800)),
        Err(Error::Unauthorized)
    );
    let committed = fs::read(f.directory.join("authorization.json")).unwrap();
    f.reopen().unwrap();
    let (_, a) = f.parts();
    assert!(a.transports.is_empty());
    assert_eq!(a.record.grants.len(), 1);
    assert_eq!(a.record.operation_receipts.len(), 1);
    let request = peer_request(
        a,
        &key,
        &v.grant_id,
        None,
        now + Duration::from_secs(400 * 86400),
    );
    let new = a
        .prove_transport(
            &request,
            ORIGIN,
            now + Duration::from_secs(400 * 86400),
            |_| Ok(()),
        )
        .unwrap();
    assert!(
        a.access(&new, ORIGIN, now + Duration::from_secs(400 * 86400))
            .is_ok()
    );
    assert_eq!(
        fs::read(f.directory.join("authorization.json")).unwrap(),
        committed
    );
}

#[test]
fn caps_do_not_evict_active_grants_and_monotonic_attempt_window_is_bounded() {
    let mut f = Fixture::new();
    let key = peer_key();
    let now = Instant::now();
    let (store, a) = f.parts();
    for i in 0..64u8 {
        let mut v = peer_verifier(a.record.current_scope.clone().unwrap(), &key);
        v.grant_id = URL_SAFE_NO_PAD.encode([i; 32]);
        v.enrollment_operation_id = format!("00000000-0000-4000-8000-{i:012x}");
        let id = v.grant_id.clone();
        a.enroll(store, v).unwrap();
        let request = peer_request(a, &key, &id, None, now);
        a.prove_transport(&request, ORIGIN, now, |_| Ok(()))
            .unwrap();
    }
    assert_eq!(
        a.enroll(store, verifier(a.record.current_scope.clone().unwrap())),
        Err(Error::Conflict)
    ); // ID7 already belongs to another operation.
    let mut v = verifier(a.record.current_scope.clone().unwrap());
    v.grant_id = URL_SAFE_NO_PAD.encode([99; 32]);
    v.enrollment_operation_id = "00000000-0000-4000-8000-000000000099".into();
    assert_eq!(a.enroll(store, v), Err(Error::Saturated));
    assert_eq!(a.record.grants.len(), 64);
    assert_eq!(a.transports.len(), 64);
    assert_eq!(a.record.operation_receipts.len(), 64);
    let now = Instant::now();
    let mut budget = AttemptBudget::new();
    for _ in 0..10 {
        budget.admit(now).unwrap();
    }
    assert_eq!(
        budget.admit(now + Duration::from_secs(59)),
        Err(Error::Saturated)
    );
    assert!(budget.admit(now + Duration::from_secs(60)).is_ok());
}

#[test]
fn repair_retained_revoked_grant_id_cannot_bind_different_key_or_operation_after_reopen() {
    let mut f = Fixture::new();
    let first_key = peer_key();
    let second_key = peer_key();
    let (store, a) = f.parts();
    let first = peer_verifier(a.record.current_scope.clone().unwrap(), &first_key);
    let original_receipt = a.enroll(store, first.clone()).unwrap();
    a.revoke(store, &first.grant_id, &profile::new_uuid().unwrap(), false)
        .unwrap();
    f.reopen().unwrap();
    let before = fs::read(f.directory.join("authorization.json")).unwrap();
    let before_hash = ring::digest::digest(&ring::digest::SHA256, &before);
    let (store, a) = f.parts();
    assert_eq!(
        a.enroll(store, first.clone()).unwrap(),
        original_receipt,
        "exact operation reconciles without reviving control"
    );
    let replacement = peer_verifier(first.scope.clone(), &second_key);
    assert_ne!(replacement.public_key, first.public_key);
    assert_ne!(
        replacement.enrollment_operation_id,
        first.enrollment_operation_id
    );
    assert_eq!(replacement.grant_id, first.grant_id);
    assert_eq!(a.enroll(store, replacement), Err(Error::Conflict));
    assert!(a.record.grants.is_empty());
    assert_eq!(
        ring::digest::digest(
            &ring::digest::SHA256,
            &fs::read(f.directory.join("authorization.json")).unwrap()
        )
        .as_ref(),
        before_hash.as_ref()
    );
    f.reopen().unwrap();
    assert!(f.authority.as_ref().unwrap().record.grants.is_empty());
    assert_eq!(
        fs::read(f.directory.join("authorization.json")).unwrap(),
        before
    );
}

#[test]
fn repair_semantically_corrupt_commissioning_and_identity_journal_fail_closed_without_rewrite() {
    let changes = [
        ("commission", "mode", serde_json::json!("bogus")),
        ("commission", "endpoint", serde_json::Value::Null),
        ("commission", "ptt", serde_json::json!("rts")),
        (
            "commission",
            "disabled_with_endpoint",
            serde_json::Value::Null,
        ),
        ("identity", "add_present", serde_json::Value::Null),
        ("identity", "replace_null", serde_json::Value::Null),
        ("identity", "remove_null", serde_json::Value::Null),
        ("identity", "wrong_profile", serde_json::Value::Null),
        ("identity", "remove_wrong_receipt", serde_json::Value::Null),
        ("identity", "replace_same_radio", serde_json::Value::Null),
        ("identity", "add_revision_two", serde_json::Value::Null),
    ];
    for (kind, field, value) in changes {
        let mut f = Fixture::new();
        let (_, a) = f.parts();
        let mut record = a.record.clone();
        let selected = record.current_scope.clone().unwrap();
        record.commissioning = Some(Commissioning {
            scope: selected.clone(),
            receive_only_confirmed: true,
            control: profile::Control {
                mode: "cat".into(),
                endpoint: Some("fixture-cat".into()),
                ptt: "disabled".into(),
            },
        });
        record.checked_control = record.commissioning.as_ref().unwrap().control.clone();
        let operation_id = profile::new_uuid().unwrap();
        record.operation_receipts.push_back(JournalEntry {
            operation_id: operation_id.clone(),
            scope: selected.clone(),
            kind: OperationKind::RadioIdentity,
            grant_id: None,
            owner_verifier: None,
            identity_request: Some(IdentityRequest {
                version: 1,
                operation_id,
                expected_scope: None,
                change: IdentityChange::Add,
            }),
        });
        // Independent JSON edits exercise semantic read/write validation, not just Rust construction.
        let mut json = serde_json::to_value(&record).unwrap();
        if kind == "commission" {
            if field == "disabled_with_endpoint" {
                json["commissioning"]["control"]["mode"] = serde_json::json!("disabled");
            } else {
                json["commissioning"]["control"][field] = value;
            }
        } else {
            let request = &mut json["operation_receipts"][0]["identity_request"];
            match field {
                "add_present" => {
                    request["expected_scope"] = serde_json::to_value(&selected.wire).unwrap()
                }
                "replace_null" => request["change"] = serde_json::json!("replace"),
                "remove_null" => request["change"] = serde_json::json!("remove"),
                "wrong_profile" => {
                    request["change"] = serde_json::json!("remove");
                    request["expected_scope"] = serde_json::to_value(&selected.wire).unwrap();
                    request["expected_scope"]["profile_id"] =
                        serde_json::json!("00000000-0000-4000-8000-000000000099");
                }
                "remove_wrong_receipt" => {
                    request["change"] = serde_json::json!("remove");
                    request["expected_scope"] = serde_json::to_value(&selected.wire).unwrap();
                    request["expected_scope"]["safety_revision"] = serde_json::json!(2);
                }
                "replace_same_radio" => {
                    request["change"] = serde_json::json!("replace");
                    request["expected_scope"] = serde_json::to_value(&selected.wire).unwrap();
                }
                "add_revision_two" => (),
                _ => unreachable!(),
            }
            if field == "add_revision_two" {
                json["operation_receipts"][0]["scope"]["wire"]["safety_revision"] =
                    serde_json::json!(2);
            }
        }
        let invalid: Record = serde_json::from_value(json.clone()).unwrap();
        let committed = fs::read(f.directory.join("authorization.json")).unwrap();
        let (store, _) = f.parts();
        assert!(
            store.save_authorization(&invalid).is_err(),
            "accepted semantic corruption {field}"
        );
        assert_eq!(
            fs::read(f.directory.join("authorization.json")).unwrap(),
            committed
        );
        let corrupt_bytes = serde_json::to_vec(&json).unwrap();
        fs::write(f.directory.join("authorization.json"), &corrupt_bytes).unwrap();
        assert_eq!(
            f.reopen(),
            Err(Error::PersistenceFailed),
            "reopen accepted {field}"
        );
        assert_eq!(
            fs::read(f.directory.join("authorization.json")).unwrap(),
            corrupt_bytes
        );
    }
}

#[test]
fn repair_valid_same_radio_older_verifier_and_receipt_remain_valid() {
    let mut f = Fixture::new();
    let (store, a) = f.parts();
    let v = verifier(a.record.current_scope.clone().unwrap());
    a.enroll(store, v).unwrap();
    let mut record = a.record.clone();
    record.current_scope.as_mut().unwrap().wire.safety_revision = 2;
    record.commissioning = Some(Commissioning {
        scope: record.current_scope.clone().unwrap(),
        receive_only_confirmed: true,
        control: record.checked_control.clone(),
    });
    store.save_authorization(&record).unwrap();
    f.reopen().unwrap();
    assert_eq!(
        f.authority.as_ref().unwrap().record.grants[0]
            .scope
            .wire
            .safety_revision,
        1
    );
    assert_eq!(
        f.authority.as_ref().unwrap().record.operation_receipts[0]
            .scope
            .wire
            .safety_revision,
        1
    );
    assert_eq!(
        f.authority
            .as_ref()
            .unwrap()
            .record
            .current_scope
            .as_ref()
            .unwrap()
            .wire
            .safety_revision,
        2
    );
}

#[test]
fn repair_valid_add_replace_remove_identity_receipts_survive_reopen() {
    for change in [
        IdentityChange::Add,
        IdentityChange::Replace,
        IdentityChange::Remove,
    ] {
        let mut f = Fixture::new();
        let (store, a) = f.parts();
        let mut record = a.record.clone();
        let old = record.current_scope.clone().unwrap();
        let mut result = old.clone();
        if change == IdentityChange::Replace {
            result.wire.radio_id = profile::new_uuid().unwrap();
        }
        record.current_scope = if change == IdentityChange::Remove {
            None
        } else {
            Some(result.clone())
        };
        let operation_id = profile::new_uuid().unwrap();
        record.operation_receipts.push_back(JournalEntry {
            operation_id: operation_id.clone(),
            scope: result,
            kind: OperationKind::RadioIdentity,
            grant_id: None,
            owner_verifier: None,
            identity_request: Some(IdentityRequest {
                version: 1,
                operation_id,
                expected_scope: if change == IdentityChange::Add {
                    None
                } else {
                    Some(old.wire)
                },
                change,
            }),
        });
        store.save_authorization(&record).unwrap();
        f.reopen().unwrap();
        assert_eq!(f.authority.as_ref().unwrap().record, record);
    }
}

#[test]
fn safety_watermark_reconciles_public_private_commit_gap_once_after_failed_private_write() {
    let mut f = Fixture::new();
    let (store, a) = f.parts();
    let grant = verifier(a.record.current_scope.clone().unwrap());
    a.enroll(store, grant.clone()).unwrap();
    let old = a.record.clone();
    let mut settings = store.document.settings();
    settings.control = profile::Control {
        mode: "cat".into(),
        endpoint: Some("fixture-cat".into()),
        ptt: "disabled".into(),
    };
    store.save(settings).unwrap();
    let result = profile::tests::with_fault("write", || a.reconcile_control(store));
    assert_eq!(result, Err(Error::PersistenceFailed));
    assert_eq!(
        a.challenge(&grant.grant_id, ORIGIN, None, Instant::now()),
        Err(Error::PersistenceFailed)
    );
    let saved: Record =
        serde_json::from_slice(&fs::read(f.directory.join("authorization.json")).unwrap()).unwrap();
    assert_eq!(
        saved, old,
        "a failed second-file write must not claim cross-file atomicity"
    );
    f.reopen().unwrap();
    let current = f.authority.as_ref().unwrap().record.clone();
    assert_eq!(
        current.current_scope.as_ref().unwrap().wire.radio_id,
        grant.scope.wire.radio_id
    );
    assert_eq!(
        current.current_scope.as_ref().unwrap().wire.safety_revision,
        2
    );
    assert_eq!(current.grants, vec![grant]);
    assert!(current.commissioning.is_none());
    assert_eq!(
        current.checked_control,
        f.store.as_ref().unwrap().document.control
    );
    f.reopen().unwrap();
    assert_eq!(
        f.authority.as_ref().unwrap().record,
        current,
        "reopen cannot increment twice for one committed control configuration"
    );
}
