//! Private selected-radio authorization owner. HTTP and native dispatch remain callers.
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ring::{agreement, rand::SystemRandom, signature};
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;

use crate::profile;

#[cfg(test)]
#[path = "authorization_tests.rs"]
pub(crate) mod authorization_tests;

const CAP: usize = 64;
const CHALLENGE_LIFE: Duration = Duration::from_secs(60);
const TRANSPORT_LIFE: Duration = Duration::from_secs(28_800);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Invalid,
    Unauthorized,
    Conflict,
    Saturated,
    PersistenceFailed,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnrollmentRequest {
    pub version: u8,
    pub operation_id: String,
    pub scope: WireScope,
    pub grant_id: String,
    pub public_key: String,
}

impl EnrollmentRequest {
    pub fn verifier(self, validated_origin: &str) -> Result<Verifier, Error> {
        if self.version != 1 {
            return Err(Error::Invalid);
        }
        let verifier = Verifier {
            grant_id: self.grant_id,
            enrollment_operation_id: self.operation_id,
            public_key: self.public_key,
            scope: self.scope.in_validated_origin(validated_origin)?,
        };
        validate_verifier(&verifier)?;
        Ok(verifier)
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProofRequest {
    pub version: u8,
    pub grant_id: String,
    pub nonce: String,
    pub signature: String,
}
impl ProofRequest {
    fn validate(&self) -> Result<(), Error> {
        if self.version != 1 {
            return Err(Error::Invalid);
        }
        decode::<32>(&self.grant_id)?;
        decode::<32>(&self.nonce)?;
        decode::<64>(&self.signature)?;
        Ok(())
    }
}

pub fn parse_request<T: serde::de::DeserializeOwned>(bytes: &[u8]) -> Result<T, Error> {
    if bytes.len() > 1024 {
        return Err(Error::Invalid);
    }
    serde_json::from_slice(bytes).map_err(|_| Error::Invalid)
}

/// A single process-level instance is shared by all auth endpoints/profile contexts.
pub struct AttemptBudget {
    attempts: VecDeque<Instant>,
}
impl AttemptBudget {
    pub fn new() -> Self {
        Self {
            attempts: VecDeque::new(),
        }
    }
    pub fn admit(&mut self, now: Instant) -> Result<(), Error> {
        while self
            .attempts
            .front()
            .is_some_and(|t| now.saturating_duration_since(*t) >= Duration::from_secs(60))
        {
            self.attempts.pop_front();
        }
        if self.attempts.len() == 10 {
            return Err(Error::Saturated);
        }
        self.attempts.push_back(now);
        Ok(())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct WireScope {
    pub profile_id: String,
    pub radio_id: String,
    pub safety_revision: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Scope {
    pub wire: WireScope,
    pub https_origin: String,
}

impl WireScope {
    pub fn validate(&self) -> Result<(), Error> {
        if !profile::valid_uuid(&self.profile_id)
            || !profile::valid_uuid(&self.radio_id)
            || !(1..=profile::MAX_REVISION).contains(&self.safety_revision)
        {
            return Err(Error::Invalid);
        }
        Ok(())
    }
    /// The caller must first validate TLS and the exact HTTP Origin against Endpoint.
    pub fn in_validated_origin(self, origin: &str) -> Result<Scope, Error> {
        self.validate()?;
        if !origin.starts_with("https://") || profile::parse_origin(origin).is_none() {
            return Err(Error::Invalid);
        }
        Ok(Scope {
            wire: self,
            https_origin: origin.to_owned(),
        })
    }
}

impl Scope {
    fn validate(&self) -> Result<(), Error> {
        self.wire
            .clone()
            .in_validated_origin(&self.https_origin)
            .map(|_| ())
    }
    fn same_radio(&self, other: &Self) -> bool {
        self.wire.profile_id == other.wire.profile_id
            && self.wire.radio_id == other.wire.radio_id
            && self.https_origin == other.https_origin
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Verifier {
    pub grant_id: String,
    pub enrollment_operation_id: String,
    pub public_key: String,
    pub scope: Scope,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Commissioning {
    pub scope: Scope,
    pub receive_only_confirmed: bool,
    pub control: profile::Control,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum OperationKind {
    Enroll,
    Logout,
    RevokeAll,
    Commission,
}

fn required_nullable<'de, D, T>(d: D) -> Result<Option<T>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(d)
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct JournalEntry {
    pub operation_id: String,
    pub scope: Scope,
    pub kind: OperationKind,
    #[serde(deserialize_with = "required_nullable")]
    pub grant_id: Option<String>,
    #[serde(deserialize_with = "required_nullable")]
    pub owner_verifier: Option<Verifier>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Record {
    pub schema_version: u8,
    // Durable reconciliation watermark, not another current configuration owner.
    pub checked_control: profile::Control,
    #[serde(deserialize_with = "required_nullable")]
    pub current_scope: Option<Scope>,
    #[serde(deserialize_with = "required_nullable")]
    pub commissioning: Option<Commissioning>,
    pub grants: Vec<Verifier>,
    pub revocation_generation: u64,
    pub operation_receipts: VecDeque<JournalEntry>,
}

impl Record {
    pub fn initial(scope: Scope) -> Result<Self, Error> {
        scope.validate()?;
        Ok(Self {
            schema_version: 1,
            checked_control: profile::Control {
                mode: "disabled".into(),
                endpoint: None,
                ptt: "disabled".into(),
            },
            current_scope: Some(scope),
            commissioning: None,
            grants: Vec::new(),
            revocation_generation: 0,
            operation_receipts: VecDeque::new(),
        })
    }
    pub fn validate(&self, profile_id: &str) -> Result<(), Error> {
        self.checked_control
            .validate()
            .map_err(|_| Error::Invalid)?;
        if self.schema_version != 1
            || self.grants.len() > CAP
            || self.operation_receipts.len() > CAP
            || self.revocation_generation > profile::MAX_REVISION
        {
            return Err(Error::Invalid);
        }
        let check_scope = |scope: &Scope| {
            scope.validate()?;
            if scope.wire.profile_id != profile_id {
                return Err(Error::Invalid);
            }
            Ok(())
        };
        if let Some(scope) = &self.current_scope {
            check_scope(scope)?;
        }
        if self.current_scope.is_none() && (!self.grants.is_empty() || self.commissioning.is_some())
        {
            return Err(Error::Invalid);
        }
        for (i, grant) in self.grants.iter().enumerate() {
            validate_verifier(grant)?;
            check_scope(&grant.scope)?;
            if self
                .current_scope
                .as_ref()
                .is_none_or(|s| !s.same_radio(&grant.scope))
                || self.grants[..i].iter().any(|g| {
                    g.grant_id == grant.grant_id
                        || g.enrollment_operation_id == grant.enrollment_operation_id
                })
            {
                return Err(Error::Invalid);
            }
        }
        if let Some(c) = &self.commissioning {
            if !c.receive_only_confirmed
                || self.current_scope.as_ref() != Some(&c.scope)
                || c.control != self.checked_control
            {
                return Err(Error::Invalid);
            }
            check_scope(&c.scope)?;
            c.control.validate().map_err(|_| Error::Invalid)?;
        }
        for (i, entry) in self.operation_receipts.iter().enumerate() {
            check_scope(&entry.scope)?;
            if !profile::valid_uuid(&entry.operation_id)
                || self
                    .operation_receipts
                    .iter()
                    .take(i)
                    .any(|e| e.operation_id == entry.operation_id)
            {
                return Err(Error::Invalid);
            }
            match &entry.owner_verifier {
                Some(v) => {
                    validate_verifier(v)?;
                    check_scope(&v.scope)?;
                    if !v.scope.same_radio(&entry.scope)
                        || entry.grant_id.as_ref() != Some(&v.grant_id)
                    {
                        return Err(Error::Invalid);
                    }
                    if self
                        .grants
                        .iter()
                        .any(|g| g.grant_id == v.grant_id && g != v)
                        || self
                            .operation_receipts
                            .iter()
                            .take(i)
                            .filter_map(|e| e.owner_verifier.as_ref())
                            .any(|g| g.grant_id == v.grant_id && g != v)
                    {
                        return Err(Error::Invalid);
                    }
                    if entry.kind == OperationKind::Enroll
                        && (entry.operation_id != v.enrollment_operation_id
                            || entry.scope != v.scope)
                    {
                        return Err(Error::Invalid);
                    }
                }
                None => return Err(Error::Invalid),
            }
        }
        Ok(())
    }
    fn receipt(&mut self, entry: JournalEntry) {
        if self.operation_receipts.len() == CAP {
            self.operation_receipts.pop_front();
        }
        self.operation_receipts.push_back(entry);
    }
}

pub fn decode<const N: usize>(value: &str) -> Result<[u8; N], Error> {
    let bytes = URL_SAFE_NO_PAD.decode(value).map_err(|_| Error::Invalid)?;
    if URL_SAFE_NO_PAD.encode(&bytes) != value {
        return Err(Error::Invalid);
    }
    bytes.try_into().map_err(|_| Error::Invalid)
}

fn validate_verifier(verifier: &Verifier) -> Result<(), Error> {
    decode::<32>(&verifier.grant_id)?;
    if !profile::valid_uuid(&verifier.enrollment_operation_id) {
        return Err(Error::Invalid);
    }
    verifier.scope.validate()?;
    let key = decode::<65>(&verifier.public_key)?;
    if key[0] != 4 {
        return Err(Error::Invalid);
    }
    // ring validates the supplied SEC1 point during ECDH; no custom curve arithmetic.
    let ephemeral =
        agreement::EphemeralPrivateKey::generate(&agreement::ECDH_P256, &SystemRandom::new())
            .map_err(|_| Error::Invalid)?;
    agreement::agree_ephemeral(
        ephemeral,
        &agreement::UnparsedPublicKey::new(&agreement::ECDH_P256, key),
        |_| (),
    )
    .map_err(|_| Error::Invalid)
}

/// Receipt-purpose proofs insert operation ID before the raw nonce and use a separate domain.
pub fn signed_payload(
    scope: &Scope,
    grant_id: &str,
    nonce: &[u8; 32],
    operation_id: Option<&str>,
) -> Result<Vec<u8>, Error> {
    scope.validate()?;
    decode::<32>(grant_id)?;
    let domain: &[u8] = if operation_id.is_some() {
        b"WSTX-AUTH-RECEIPT"
    } else {
        b"WSTX-AUTH-PROOF"
    };
    let revision = scope.wire.safety_revision.to_string();
    let mut payload = domain.to_vec();
    payload.push(1);
    let mut fields = vec![
        scope.https_origin.as_bytes(),
        scope.wire.profile_id.as_bytes(),
        scope.wire.radio_id.as_bytes(),
        revision.as_bytes(),
        grant_id.as_bytes(),
    ];
    if let Some(id) = operation_id {
        if !profile::valid_uuid(id) {
            return Err(Error::Invalid);
        }
        fields.push(id.as_bytes());
    }
    fields.push(nonce);
    for field in fields {
        payload.extend_from_slice(
            &u32::try_from(field.len())
                .map_err(|_| Error::Invalid)?
                .to_be_bytes(),
        );
        payload.extend_from_slice(field);
    }
    Ok(payload)
}

#[derive(Clone)]
struct Challenge {
    nonce: String,
    scope: Scope,
    verifier: Verifier,
    operation_id: Option<String>,
    deadline: Instant,
}
#[derive(Debug, PartialEq, Eq)]
pub enum VerifiedProof {
    Control {
        scope: Scope,
        grant_id: String,
        generation: u64,
    },
    Receipt {
        operation_id: String,
    },
}
struct Transport {
    token: String,
    scope: Scope,
    grant_id: String,
    deadline: Instant,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Access {
    pub scope: Scope,
    pub grant_id: String,
    pub generation: u64,
}

/// Caller serializes this owner with the existing profile Store before dispatch.
pub struct Authority {
    record: Record,
    quarantined: bool,
    challenges: Vec<Challenge>,
    transports: Vec<Transport>,
}

impl Authority {
    pub fn record(&self) -> &Record {
        &self.record
    }
    /// CL-022-03 automatic read-only CAT precondition: a usable (non-quarantined)
    /// store, at least one unrevoked grant for the current radio and durable
    /// commissioning of exactly the current scope and saved control settings.
    /// Returns None when no grant authorizes it, Some(false) when commissioning is
    /// missing or invalidated, Some(true) when the lifecycle may run.
    pub fn automatic_cat(&self, control: &profile::Control) -> Option<bool> {
        let scope = self.record.current_scope.as_ref()?;
        if self.available().is_err()
            || !self.record.grants.iter().any(|g| g.scope.same_radio(scope))
        {
            return None;
        }
        Some(self.record.commissioning.as_ref().is_some_and(|c| {
            c.receive_only_confirmed && &c.scope == scope && &c.control == control
        }))
    }
    pub fn load(store: &mut profile::Store, initial: Scope) -> Result<Self, Error> {
        let record = store
            .load_authorization(initial)
            .map_err(|_| Error::PersistenceFailed)?;
        let mut owner = Self {
            record,
            quarantined: false,
            challenges: Vec::new(),
            transports: Vec::new(),
        };
        owner.reconcile_control(store)?;
        Ok(owner)
    }
    pub fn reconcile_control(&mut self, store: &mut profile::Store) -> Result<(), Error> {
        self.available()?;
        if self.record.checked_control == store.document.control {
            return Ok(());
        }
        let mut next = self.record.clone();
        next.checked_control = store.document.control.clone();
        if let Some(scope) = &mut next.current_scope {
            scope.wire.safety_revision = scope
                .wire
                .safety_revision
                .checked_add(1)
                .filter(|n| *n <= profile::MAX_REVISION)
                .ok_or(Error::Conflict)?;
        }
        next.commissioning = None;
        self.persist(store, next)?;
        self.challenges.clear();
        self.transports.clear();
        Ok(())
    }
    pub fn challenge_details(&self, nonce: &str) -> Option<(&Scope, &Verifier)> {
        self.challenges
            .iter()
            .find(|c| c.nonce == nonce)
            .map(|c| (&c.scope, &c.verifier))
    }
    /// A WS retains its grant context, not its rotated/expired HTTP transport handle.
    pub fn current_grant(&self, prior: &Access) -> Result<Access, Error> {
        self.available()?;
        if self.record.current_scope.as_ref() != Some(&prior.scope)
            || !self
                .record
                .grants
                .iter()
                .any(|g| g.grant_id == prior.grant_id && g.scope.same_radio(&prior.scope))
        {
            return Err(Error::Unauthorized);
        }
        Ok(Access {
            generation: self.record.revocation_generation,
            ..prior.clone()
        })
    }
    fn available(&self) -> Result<(), Error> {
        if self.quarantined {
            Err(Error::PersistenceFailed)
        } else {
            Ok(())
        }
    }
    fn persist(&mut self, store: &mut profile::Store, next: Record) -> Result<(), Error> {
        self.available()?;
        next.validate(&store.document.profile_id)?;
        if store.save_authorization(&next).is_err() {
            self.quarantined = true;
            self.challenges.clear();
            self.transports.clear();
            return Err(Error::PersistenceFailed);
        }
        self.record = next;
        Ok(())
    }
    pub fn enroll(
        &mut self,
        store: &mut profile::Store,
        verifier: Verifier,
    ) -> Result<JournalEntry, Error> {
        self.available()?;
        validate_verifier(&verifier)?;
        if let Some(existing) = self
            .record
            .operation_receipts
            .iter()
            .find(|e| e.operation_id == verifier.enrollment_operation_id)
        {
            return if existing.kind == OperationKind::Enroll
                && existing.owner_verifier.as_ref() == Some(&verifier)
            {
                Ok(existing.clone())
            } else {
                Err(Error::Conflict)
            };
        }
        if self.record.current_scope.as_ref() != Some(&verifier.scope) {
            return Err(Error::Conflict);
        }
        if self
            .record
            .grants
            .iter()
            .any(|g| g.grant_id == verifier.grant_id)
            || self
                .record
                .operation_receipts
                .iter()
                .filter_map(|e| e.owner_verifier.as_ref())
                .any(|g| g.grant_id == verifier.grant_id)
        {
            return Err(Error::Conflict);
        }
        if self.record.grants.len() == CAP {
            return Err(Error::Saturated);
        }
        let receipt = JournalEntry {
            operation_id: verifier.enrollment_operation_id.clone(),
            scope: verifier.scope.clone(),
            kind: OperationKind::Enroll,
            grant_id: Some(verifier.grant_id.clone()),
            owner_verifier: Some(verifier.clone()),
        };
        let mut next = self.record.clone();
        next.grants.push(verifier);
        next.receipt(receipt.clone());
        self.persist(store, next)?;
        Ok(receipt)
    }
    pub fn challenge(
        &mut self,
        grant_id: &str,
        origin: &str,
        operation_id: Option<&str>,
        now: Instant,
    ) -> Result<String, Error> {
        self.available()?;
        let (verifier, scope) = if let Some(id) = operation_id {
            let entry = self
                .record
                .operation_receipts
                .iter()
                .find(|e| e.operation_id == id)
                .ok_or(Error::Conflict)?;
            let verifier = entry
                .owner_verifier
                .as_ref()
                .filter(|v| v.grant_id == grant_id)
                .ok_or(Error::Unauthorized)?;
            (verifier.clone(), entry.scope.clone())
        } else {
            let scope = self
                .record
                .current_scope
                .as_ref()
                .ok_or(Error::Unauthorized)?;
            let verifier = self
                .record
                .grants
                .iter()
                .find(|v| v.grant_id == grant_id && v.scope.same_radio(scope))
                .ok_or(Error::Unauthorized)?;
            (verifier.clone(), scope.clone())
        };
        if scope.https_origin != origin {
            return Err(Error::Unauthorized);
        }
        self.challenges.retain(|c| now < c.deadline);
        if self.challenges.len() == CAP {
            return Err(Error::Saturated);
        }
        let nonce = random_token()?;
        self.challenges.push(Challenge {
            nonce: nonce.clone(),
            scope,
            verifier,
            operation_id: operation_id.map(str::to_owned),
            deadline: now + CHALLENGE_LIFE,
        });
        Ok(nonce)
    }
    /// Consumes a valid challenge; only ordinary proof can subsequently mint transport.
    fn verify_proof(
        &mut self,
        grant_id: &str,
        nonce: &str,
        signature: &str,
        origin: &str,
        operation_id: Option<&str>,
        now: Instant,
    ) -> Result<VerifiedProof, Error> {
        self.available()?;
        let raw_nonce = decode::<32>(nonce)?;
        let signature = decode::<64>(signature)?;
        let index = self
            .challenges
            .iter()
            .position(|c| {
                c.nonce == nonce
                    && c.verifier.grant_id == grant_id
                    && c.operation_id.as_deref() == operation_id
            })
            .ok_or(Error::Unauthorized)?;
        let c = &self.challenges[index];
        if now >= c.deadline || c.scope.https_origin != origin {
            return Err(Error::Unauthorized);
        }
        if operation_id.is_none()
            && (self.record.current_scope.as_ref() != Some(&c.scope)
                || !self.record.grants.iter().any(|g| g == &c.verifier))
        {
            return Err(Error::Unauthorized);
        }
        let payload = signed_payload(&c.scope, grant_id, &raw_nonce, operation_id)?;
        let key = decode::<65>(&c.verifier.public_key)?;
        signature::UnparsedPublicKey::new(&signature::ECDSA_P256_SHA256_FIXED, key)
            .verify(&payload, &signature)
            .map_err(|_| Error::Unauthorized)?;
        let accepted = if let Some(id) = operation_id {
            VerifiedProof::Receipt {
                operation_id: id.into(),
            }
        } else {
            VerifiedProof::Control {
                scope: c.scope.clone(),
                grant_id: grant_id.into(),
                generation: self.record.revocation_generation,
            }
        };
        self.challenges.remove(index);
        Ok(accepted)
    }
    /// Prepare the bounded HTTP response/cookie before installing a replacement.
    /// This synchronous call runs within the caller's station authority transaction.
    pub fn prove_transport(
        &mut self,
        request: &ProofRequest,
        origin: &str,
        now: Instant,
        prepare_response: impl FnOnce(&str) -> Result<(), Error>,
    ) -> Result<String, Error> {
        request.validate()?;
        self.verify_proof(
            &request.grant_id,
            &request.nonce,
            &request.signature,
            origin,
            None,
            now,
        )?;
        let token = random_token()?;
        prepare_response(&token)?;
        let scope = self
            .record
            .current_scope
            .clone()
            .ok_or(Error::Unauthorized)?;
        self.transports.retain(|t| {
            t.grant_id != request.grant_id
                && now < t.deadline
                && self.record.current_scope.as_ref() == Some(&t.scope)
                && self.record.grants.iter().any(|g| g.grant_id == t.grant_id)
        });
        self.transports.push(Transport {
            token: token.clone(),
            scope,
            grant_id: request.grant_id.clone(),
            deadline: now + TRANSPORT_LIFE,
        });
        Ok(token)
    }
    pub fn prove_receipt(
        &mut self,
        request: &ProofRequest,
        operation_id: &str,
        origin: &str,
        now: Instant,
    ) -> Result<JournalEntry, Error> {
        request.validate()?;
        self.verify_proof(
            &request.grant_id,
            &request.nonce,
            &request.signature,
            origin,
            Some(operation_id),
            now,
        )?;
        self.record
            .operation_receipts
            .iter()
            .find(|e| e.operation_id == operation_id)
            .cloned()
            .ok_or(Error::Conflict)
    }
    pub fn access(&self, token: &str, origin: &str, now: Instant) -> Result<Access, Error> {
        self.available()?;
        decode::<32>(token).map_err(|_| Error::Unauthorized)?;
        let t = self
            .transports
            .iter()
            .find(|t| bool::from(t.token.as_bytes().ct_eq(token.as_bytes())))
            .ok_or(Error::Unauthorized)?;
        if now >= t.deadline
            || t.scope.https_origin != origin
            || self.record.current_scope.as_ref() != Some(&t.scope)
            || !self
                .record
                .grants
                .iter()
                .any(|g| g.grant_id == t.grant_id && g.scope.same_radio(&t.scope))
        {
            return Err(Error::Unauthorized);
        }
        Ok(Access {
            scope: t.scope.clone(),
            grant_id: t.grant_id.clone(),
            generation: self.record.revocation_generation,
        })
    }
    /// Recheck at dispatch under the same authority transaction, never after queueing.
    pub fn recheck_dispatch(&self, access: &Access) -> Result<(), Error> {
        self.available()?;
        if self.record.current_scope.as_ref() != Some(&access.scope)
            || access.generation != self.record.revocation_generation
            || !self
                .record
                .grants
                .iter()
                .any(|g| g.grant_id == access.grant_id && g.scope.same_radio(&access.scope))
        {
            return Err(Error::Unauthorized);
        }
        Ok(())
    }
    /// Explicit receive-only acknowledgement; never opens or controls a device.
    pub fn commission(
        &mut self,
        store: &mut profile::Store,
        access: &Access,
        operation_id: &str,
    ) -> Result<JournalEntry, Error> {
        if !profile::valid_uuid(operation_id) {
            return Err(Error::Invalid);
        }
        // Commissioning always requires CURRENT
        // authority before any retained-operation lookup.
        self.recheck_dispatch(access)?;
        let control = store.document.control.clone();
        control.validate().map_err(|_| Error::Invalid)?;
        if self.record.checked_control != control {
            return Err(Error::Conflict);
        }
        let verifier = self
            .record
            .grants
            .iter()
            .find(|v| v.grant_id == access.grant_id && v.scope.same_radio(&access.scope))
            .ok_or(Error::Unauthorized)?
            .clone();
        if let Some(entry) = self
            .record
            .operation_receipts
            .iter()
            .find(|e| e.operation_id == operation_id)
        {
            return if entry.kind == OperationKind::Commission
                && entry.scope == access.scope
                && entry.grant_id.as_ref() == Some(&access.grant_id)
                && entry.owner_verifier.as_ref() == Some(&verifier)
            {
                Ok(entry.clone())
            } else {
                Err(Error::Conflict)
            };
        }
        let entry = JournalEntry {
            operation_id: operation_id.into(),
            scope: access.scope.clone(),
            kind: OperationKind::Commission,
            grant_id: Some(access.grant_id.clone()),
            owner_verifier: Some(verifier),
        };
        let mut next = self.record.clone();
        next.commissioning = Some(Commissioning {
            scope: access.scope.clone(),
            receive_only_confirmed: true,
            control,
        });
        next.receipt(entry.clone());
        self.persist(store, next)?;
        Ok(entry)
    }
    pub fn revoke(
        &mut self,
        store: &mut profile::Store,
        grant_id: &str,
        operation_id: &str,
        all: bool,
    ) -> Result<JournalEntry, Error> {
        self.available()?;
        if !profile::valid_uuid(operation_id) {
            return Err(Error::Invalid);
        }
        if self
            .record
            .operation_receipts
            .iter()
            .any(|e| e.operation_id == operation_id)
        {
            return Err(Error::Conflict);
        }
        let verifier = self
            .record
            .grants
            .iter()
            .find(|v| v.grant_id == grant_id)
            .ok_or(Error::Unauthorized)?
            .clone();
        let scope = self
            .record
            .current_scope
            .clone()
            .ok_or(Error::Unauthorized)?;
        let receipt = JournalEntry {
            operation_id: operation_id.into(),
            scope,
            kind: if all {
                OperationKind::RevokeAll
            } else {
                OperationKind::Logout
            },
            grant_id: Some(grant_id.into()),
            owner_verifier: Some(verifier),
        };
        let mut next = self.record.clone();
        next.revocation_generation = next
            .revocation_generation
            .checked_add(1)
            .filter(|n| *n <= profile::MAX_REVISION)
            .ok_or(Error::Conflict)?;
        if all {
            next.grants.clear();
        } else {
            next.grants.retain(|v| v.grant_id != grant_id);
        }
        next.receipt(receipt.clone());
        self.persist(store, next)?;
        self.challenges.clear();
        self.transports
            .retain(|t| self.record.grants.iter().any(|g| g.grant_id == t.grant_id));
        Ok(receipt)
    }
}

fn random_token() -> Result<String, Error> {
    use ring::rand::SecureRandom;
    let mut bytes = [0; 32];
    SystemRandom::new()
        .fill(&mut bytes)
        .map_err(|_| Error::Invalid)?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}
