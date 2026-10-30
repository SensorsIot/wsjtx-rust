'use strict';
// This owner stores only the nonextractable signing key and public operation metadata.
window.stationAuthorization = (() => {
  const encoder = new TextEncoder(), database = 'wstx-authorization-v1';
  let epoch = 0, state = 'unavailable', scope = null, recovery = null, retryAt = 0, authorizing = false, lastFailure = null;
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
  const encoded = bytes => btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  function decoded(value, size) {
    if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('Invalid authorization encoding');
    const bytes = Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/')), c => c.charCodeAt(0));
    if (bytes.length !== size || encoded(bytes) !== value) throw new Error('Invalid authorization encoding');
    return bytes;
  }
  function validScope(value) {
    return value && Object.keys(value).sort().join(',') === 'profile_id,radio_id,safety_revision' &&
      uuid(value.profile_id) && uuid(value.radio_id) && Number.isSafeInteger(value.safety_revision) && value.safety_revision > 0;
  }
  const sameRadio = (a, b) => a.profile_id === b.profile_id && a.radio_id === b.radio_id;
  const sameScope = (a, b) => validScope(a) && validScope(b) && sameRadio(a, b) && a.safety_revision === b.safety_revision;
  function publish(next, nextScope = scope) {
    state = next; scope = nextScope;
    const detail = Object.freeze({...snapshot(), authorizationCondition: lastFailure?.condition ?? null, status: lastFailure?.status ?? null});
    window.dispatchEvent(new CustomEvent('station-authorization', {detail}));
  }
  function snapshot() {return Object.freeze({epoch, state, ready: state === 'ready', scope: scope && Object.freeze({...scope})});}
  async function open(create) {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(database, 1); let settled = false;
      const fail = condition => {
        if (settled) return;
        settled = true; const error = new Error('Authorization storage unavailable');
        if (condition) error.authorizationCondition = condition;
        reject(error);
      };
      request.onupgradeneeded = event => {
        if (!create || event.oldVersion > 0 || settled) {
          const absent = !create && event.oldVersion === 0;
          try {request.transaction.abort();} catch {fail(); return;}
          fail(absent ? 'credential-missing' : null); return;
        }
        request.result.createObjectStore('credential');
      };
      request.onerror = () => fail();
      request.onblocked = () => fail();
      request.onsuccess = () => {
        const db = request.result;
        if (settled) {db.close(); return;}
        if (!db.objectStoreNames.contains('credential')) {db.close(); fail(); return;}
        settled = true; resolve(db);
      };
    });
  }
  async function stored(write, create = false, initial = false) {
    const db = await open(create);
    try {
      return await new Promise((resolve, reject) => {
        const transaction = db.transaction('credential', write ? 'readwrite' : 'readonly');
        const store = transaction.objectStore('credential');
        const request = write ? initial ? store.add(write, 'current') : store.put(write, 'current') : store.get('current');
        let value;
        request.onsuccess = () => {value = request.result;};
        transaction.oncomplete = () => resolve(write || value);
        transaction.onabort = transaction.onerror = () => reject(new Error('Authorization storage failed'));
      });
    } finally {db.close();}
  }
  function validateCredential(value) {
    if (!value || value.version !== 1 || value.origin !== location.origin || !validScope(value.scope) ||
        !uuid(value.enrollment_id) || !(value.key instanceof CryptoKey) || value.key.type !== 'private' ||
        value.key.extractable || value.key.algorithm.name !== 'ECDSA' || value.key.algorithm.namedCurve !== 'P-256' ||
        value.key.usages.length !== 1 || value.key.usages[0] !== 'sign' || typeof value.pending_enrollment !== 'boolean') {
      throw new Error('Retained authorization credential missing or invalid');
    }
    decoded(value.grant_id, 32); const publicKey = decoded(value.public_key, 65);
    if (publicKey[0] !== 4) throw new Error('Invalid retained public key');
    return value;
  }
  function payload(credential, currentScope, nonce, operationId) {
    const fields = [location.origin, currentScope.profile_id, currentScope.radio_id,
      String(currentScope.safety_revision), credential.grant_id];
    if (operationId) fields.push(operationId);
    const parts = [encoder.encode(operationId ? 'WSTX-AUTH-RECEIPT' : 'WSTX-AUTH-PROOF'), Uint8Array.of(1)];
    for (const field of [...fields.map(value => encoder.encode(value)), decoded(nonce, 32)]) {
      const size = new Uint8Array(4); new DataView(size.buffer).setUint32(0, field.length);
      parts.push(size, field);
    }
    const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
    let offset = 0; for (const part of parts) {result.set(part, offset); offset += part.length;}
    return result;
  }
  async function raw(path, body, signal) {
    const response = await fetch('/authorization/v1/' + path, {method: 'POST', cache: 'no-store',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body), signal});
    if (!response.ok) {
      const error = new Error(response.status === 429 ? 'Authorization rate limited' : response.status === 503 ?
        'Authorization persistence unavailable' : 'Authorization unavailable');
      error.status = response.status; throw error;
    }
    if (path === 'proof' && response.status !== 204) throw new Error('Invalid proof acknowledgement');
    if (response.status === 204) return null;
    const text = await response.text();
    if (encoder.encode(text).length > 1024) throw new Error('Invalid authorization response');
    return JSON.parse(text);
  }
  async function challenge(credential, signal, operationId) {
    const value = await raw('challenge', operationId ? {version: 1, operation_id: operationId, scope: credential.scope} :
      {version: 1, grant_id: credential.grant_id}, signal);
    if (value.version !== 1 || value.grant_id !== credential.grant_id || value.public_key !== credential.public_key ||
        !validScope(value.scope) || !sameRadio(value.scope, credential.scope) || value.lifetime_seconds !== 60) {
      const error = new Error('Authorization identity changed'); error.authorizationCondition = 'retained-rejected'; throw error;
    }
    decoded(value.nonce, 32);
    return value;
  }
  async function signature(credential, value, operationId) {
    return encoded(new Uint8Array(await crypto.subtle.sign({name: 'ECDSA', hash: 'SHA-256'}, credential.key,
      payload(credential, value.scope, value.nonce, operationId))));
  }
  async function reconcile(credential, operationId, signal) {
    const value = await challenge(credential, signal, operationId);
    const receipt = await raw('receipt', {version: 1, operation_id: operationId, scope: credential.scope,
      grant_id: credential.grant_id, nonce: value.nonce, signature: await signature(credential, value, operationId)}, signal);
    if (receipt.version !== 1 || receipt.operation_id !== operationId || receipt.grant_id !== credential.grant_id ||
        receipt.outcome !== 'committed' || !sameScope(receipt.scope, credential.scope)) throw new Error('Authorization outcome unknown');
    return receipt;
  }
  async function renew(credential, signal, recoveryEpoch = null) {
    const retryEligible = Number.isSafeInteger(recoveryEpoch) && recoveryEpoch > 0 && recoveryEpoch === epoch && credential.pending_enrollment === false;
    const checkRetry = () => {signal.throwIfAborted(); if (recoveryEpoch !== epoch) throw new Error('Authorization recovery changed');};
    if (recoveryEpoch !== null) checkRetry();
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt) checkRetry();
      const value = await challenge(credential, signal);
      if (attempt) checkRetry();
      const signed = await signature(credential, value);
      if (attempt) checkRetry();
      await raw('proof', {version: 1, grant_id: credential.grant_id, nonce: value.nonce, signature: signed}, signal);
      if (credential.pending_enrollment) {
        await reconcile(credential, credential.enrollment_id, signal);
        credential = {...credential, pending_enrollment: false}; await stored(credential);
      }
      if (attempt) checkRetry();
      let status;
      try {status = await raw('status', {version: 1}, signal);}
      catch (error) {
        // An acknowledged proof can lose the shared-cookie race. Re-prove once;
        // never infer current authority from that old acknowledgement or status alone.
        if (attempt === 0 && retryEligible && error?.status === 401 && recoveryEpoch === epoch && !signal.aborted) continue;
        throw error;
      }
      if (status.version !== 1 || !sameScope(status.scope, value.scope)) {const error = new Error('Authorization identity changed'); error.authorizationCondition = 'retained-rejected'; throw error;}
      return value.scope;
    }
  }

  function ensureReady() {
    if (authorizing) {const error = new Error('Explicit authorization in progress'); error.authorizationCondition = 'explicit-in-progress'; return Promise.reject(error);}
    if (state === 'ready') return Promise.resolve(snapshot());
    if (recovery) return recovery;
    if (Date.now() < retryAt) {const error = new Error('Authorization retry pending'); if (lastFailure) {error.authorizationCondition = lastFailure.condition; if (lastFailure.status) error.status = lastFailure.status;} return Promise.reject(error);}
    const current = ++epoch; publish('recovering');
    recovery = (async () => {
      let condition = 'credential-storage-unavailable';
      try {
        const record = await stored(); condition = record === undefined ? 'credential-missing' : 'credential-invalid';
        const credential = validateCredential(record);
        condition = credential.pending_enrollment ? 'enrollment-pending' : 'retained-transient';
        const currentScope = await renew(credential, AbortSignal.timeout(10000), current);
        if (current === epoch) {lastFailure = null; publish('ready', currentScope);}
        return snapshot();
      } catch (error) {
        if (condition === 'credential-storage-unavailable' && error?.authorizationCondition === 'credential-missing') condition = 'credential-missing';
        if (condition === 'retained-transient' && ([401, 403].includes(error?.status) || error?.authorizationCondition === 'retained-rejected')) condition = 'retained-rejected';
        const failure = new Error('Station authorization unavailable'); failure.authorizationCondition = condition;
        if ([401, 403, 429, 503].includes(error?.status)) failure.status = error?.status;
        if (current === epoch) {lastFailure = {condition, status: failure.status}; retryAt = Date.now() + (failure.status === 429 ? 60000 : 4000); publish('unavailable');}
        throw failure;
      } finally {recovery = null;}
    })();
    return recovery;
  }
  function observe(response, capturedEpoch) {
    if (response.status === 401 && capturedEpoch === epoch && state === 'ready') {
      ++epoch; publish('unavailable'); ensureReady().catch(() => {});
    }
    return response;
  }
  async function bootstrap(secret) {
    if (recovery || authorizing) throw new Error('Authorization recovery in progress');
    authorizing = true; lastFailure = null;
    const current = ++epoch; publish('authorizing');
    let condition = null;
    try {
      let response;
      try {response = await fetch('/session', {method: 'POST', body: secret, signal: AbortSignal.timeout(10000)});}
      finally {secret = null;}
      if (response.status !== 204) throw new Error('Could not authorize station');
      const signal = AbortSignal.timeout(10000), discovered = await raw('bootstrap-scope', {version: 1}, signal);
      if (discovered.version !== 1 || !validScope(discovered.current_scope)) throw new Error('Explicit radio setup required');
      condition = 'credential-storage-unavailable';
      const db = await open(true); db.close();
      const existing = await stored();
      if (existing !== undefined) {
        condition = 'credential-invalid';
        const retained = validateCredential(existing);
        condition = retained.pending_enrollment ? 'enrollment-pending' : 'retained-transient';
        throw new Error('Retained credential exists; resolve it before replacing authorization');
      }
      condition = null;
      const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, false, ['sign', 'verify']);
      const credential = {version: 1, origin: location.origin, key: pair.privateKey,
        public_key: encoded(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))),
        grant_id: encoded(crypto.getRandomValues(new Uint8Array(32))), enrollment_id: crypto.randomUUID(),
        scope: discovered.current_scope, pending_enrollment: true};
      condition = 'credential-storage-unavailable';
      await stored(credential, false, true);
      condition = 'enrollment-pending';
      const receipt = await raw('enroll', {version: 1, operation_id: credential.enrollment_id, scope: credential.scope,
        grant_id: credential.grant_id, public_key: credential.public_key}, signal);
      if (receipt.version !== 1 || receipt.operation_id !== credential.enrollment_id || receipt.grant_id !== credential.grant_id ||
          receipt.outcome !== 'committed' || !sameScope(receipt.scope, credential.scope)) throw new Error('Enrollment outcome unknown');
      credential.pending_enrollment = false; await stored(credential);
      condition = 'retained-transient';
      const currentScope = await renew(credential, signal);
      if (current === epoch) {lastFailure = null; publish('ready', currentScope);}
      return snapshot();
    } catch (error) {
      let failure = error;
      if (condition) {
        if (condition === 'retained-transient' && ([401, 403].includes(error?.status) || error?.authorizationCondition === 'retained-rejected')) condition = 'retained-rejected';
        failure = new Error('Station authorization unavailable'); failure.authorizationCondition = condition;
        if ([401, 403, 429, 503].includes(error?.status)) failure.status = error.status;
      }
      if (current === epoch) {lastFailure = condition ? {condition, status: failure.status} : null; publish('unavailable');}
      throw failure;
    }
    finally {authorizing = false; secret = null;}
  }
  // No await lies between this check and fetch: mutations never wait for proof and
  // are never replayed after an ambiguous response. Callers keep their own context fences.
  function protectedFetch(path, options = {}) {
    const captured = snapshot();
    if (!captured.ready) return Promise.reject(new Error('Station authorization unavailable'));
    return fetch(path, options).then(response => {
      observe(response, captured.epoch);
      if (captured.epoch !== epoch) throw new Error('Station authorization changed; response is stale');
      return response;
    });
  }
  return Object.freeze({snapshot, ensureReady, bootstrap, fetch: protectedFetch});
})();
