package WstxProfiles {
    private import ScalarValues::*;

    doc /* contract 12.1.1 H1 adds only bounded negotiated HTTP GET JSON content coding.
         Existing handler/auth/errors/caps precede negotiation, exactly one dispatch.
         WstxOperatingReceive::HttpContentCodingBoundary formalizes eligibility,
         selected gzip and406 exclusion; no new owner, actor, wire JSON or WS codec. */
    doc /* Implementation contract for the delivered CR #5 profile functionality. Review,
         validation and acceptance evidence remains on issue #5; no modeled verification verdict is asserted. The canonical contract is this package and WstxRequirements:
         WstxProductScope::ContractIndex 4.2 (selection/schema/ownership), 6.2 (independent cases),
         12.5 (HTTP/session); existing 12.1..12.4 remain the legacy/status contract.
         UUID: RFC 9562 section 5.4, https://www.rfc-editor.org/rfc/rfc9562.html#section-5.4.
         HTTP: RFC 9110, https://www.rfc-editor.org/rfc/rfc9110.html.
         Cookies: RFC 6265 section 8.5, https://www.rfc-editor.org/rfc/rfc6265.html#section-8.5.
         This file supplies behavior/data/state/error/ownership semantics absent from
         the stable Requirements declarations. Pinned validation checks names/types,
         not execution, equivalence, real OS atomicity or successful test results.
         Readiness requires independent comparison with approved requirements, source and independent verification expectations before implementation. */

    enum def ConnectionType { enum 'standard'; enum native_flex; }
    enum def ControlMode { enum disabled; enum cat; }
    enum def PttMode { enum disabled; enum cat; }
    enum def StartupOutcome {
        enum ready; enum created; enum invalid_runtime_configuration;
        enum resource_unavailable; enum invalid_profile; enum unsupported_schema;
        enum unsupported_connection_type; enum profile_in_use; enum endpoint_in_use;
    }
    enum def HttpOutcome {
        enum ok; enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_settings; enum wrong_profile;
        enum revision_conflict; enum revision_exhausted; enum storage_unavailable;
    }

    attribute maxRevision : Integer = (900719925 * 10000000 + 4740991);
    attribute profileFileMaxBytes : Integer = 16384;
    attribute profileHttpMaxBytes : Integer = 8192;
    attribute loginBodyMaxBytes : Integer = 1024;
    attribute referenceAcceptanceCount : Integer = 4;
    attribute hasFixedPopulationLimit : Boolean = false;
    attribute readinessDeadlineSeconds : Integer = 10;
    attribute loopbackRefreshDeadlineSeconds : Integer = 2;
    attribute reconnectAfterDetectionDeadlineSeconds : Integer = 10;
    attribute silentLossDetectionSeconds : Integer = 13;
    attribute cookieMaxAgeSeconds : Integer = 28800;

    attribute def AudioSelection {
        doc /* JSON object has exactly input_device/output_device, both required and
             nullable. Multiplicity zero means JSON null, NOT an omitted key. A present
             value is opaque nonempty UTF-8, <=256 bytes, no U+0000..001F or 007F..009F.
             Defaults null/null. Save independently; do not enumerate/open devices. */
        attribute input_device : String[0..1];
        attribute output_device : String[0..1];
    }
    attribute def ControlSelection {
        doc /* Exactly mode/endpoint/ptt; mode and ptt disabled|cat. Defaults disabled,
             null, disabled. Endpoint is null iff disabled; CAT requires an opaque
             nonempty UTF-8 endpoint <=256 bytes without control characters. PTT cat
             requires mode cat. Intent only, not a driver or evidence of availability. */
        attribute mode : ControlMode = ControlMode::disabled;
        attribute endpoint : String[0..1];
        attribute ptt : PttMode = PttMode::disabled;
        assert constraint noCatPttWithoutCat {
            ptt == PttMode::cat implies mode == ControlMode::cat
        }
    }
    attribute def Settings {
        doc /* Exactly these five required fields. display_name: 1..64 UTF-8 bytes,
             no leading/trailing whitespace or control characters (U+0000..001F,
             U+007F..009F). callsign empty or 3..12 ASCII uppercase letters/digits/slash,
             with >=1 letter and >=1 digit. locator empty or 4/6/8 Maidenhead:
             [A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?. No normalization or national
             callsign eligibility claim. Invalid values are refused, never defaulted.
             Defaults New station, empty callsign/locator, independent audio/control.
             All user strings render literally, including title/errors; never markup. */
        attribute display_name : String = "New station";
        attribute callsign : String = "";
        attribute locator : String = "";
        attribute audio : AudioSelection;
        attribute control : ControlSelection;
    }
    attribute def Endpoint {
        doc /* Exactly bind/origin. bind numeric socket IP+port 1..65535; default
             127.0.0.1:8080, never port zero in profile mode. origin required nullable:
             null only for loopback, derive scheme+bound IP+port; otherwise exact 12.1
             origin without credentials/path/query/fragment/trailing slash. Scheme
             matches runtime TLS and port equals bind port; hostname may be localhost
             or DNS alias resolving to listener. Non-loopback needs explicit HTTPS
             origin and runtime TLS/token. Direct deployment only: no proxy remapping.
             The effective browser origin is shared by readiness/GET/UI/Origin checks,
             retaining an explicit alias rather than replacing it with numeric bind. */
        attribute 'bind' : String = "127.0.0.1:8080";
        attribute origin : String[0..1];
    }
    attribute def ProfileDocument {
        doc /* Exact JSON keys: schema_version, profile_id, revision, display_name,
             callsign, locator, endpoint, connection_type, audio, control. Settings
             below groups five flat JSON fields semantically, NOT a nested settings
             field in profile.json. UTF-8 JSON object <=16384 bytes; reject malformed
             UTF-8/JSON, duplicate/unknown/missing keys, wrong types and domains.
             Fresh lowercase hyphenated UUID v4 at create; application/browser cannot
             alter it; offline UUID edits unsupported. No TLS path, token, native
             association, contact or recording schema is introduced by CR #5. */
        attribute schema_version : Integer = 1;
        attribute profile_id : String;
        attribute revision : Integer = 0;
        attribute settings : Settings;
        attribute endpoint : Endpoint;
        attribute connection_type : ConnectionType = ConnectionType::'standard';
        assert constraint supportedSchema { schema_version == 1 }
        assert constraint supportedBackend { connection_type == ConnectionType::'standard' }
        assert constraint safeRevision { revision >= 0 and revision <= (900719925 * 10000000 + 4740991) }
    }
    attribute def RuntimeInputs {
        doc /* WSTX_TLS_CERT/KEY/TOKEN only; relative TLS paths resolve process CWD
             in BOTH modes. They are never serialized into settings/profile responses.
             Profile mode rejects present WSTX_BIND/WSTX_ORIGIN, including empty values.
             TLS pair complete, token 32..128 ASCII letters/digits with TLS only;
             non-loopback requires TLS/token plus saved explicit HTTPS origin.
             Independent random tokens per profile are an operator prerequisite:
             deliberately sharing the same login secret authorizes both logins. */
        attribute tlsCertificatePath : String[0..1];
        attribute tlsKeyPath : String[0..1];
        attribute token : String[0..1];
        attribute forbiddenBindPresent : Boolean;
        attribute forbiddenOriginPresent : Boolean;
    }

    item def HttpProfileGet :> WstxArchitecture::StationRequest {
        doc /* GET /profile; TLS requires selected-profile cookie; supplied Origin
             exact, absent Origin permitted for ordinary same-origin GET. No CORS. */
    }
    item def HttpProfilePut :> WstxArchitecture::StationRequest {
        doc /* PUT /profile exact JSON body keys below, <=8192 UTF-8 bytes;
             Content-Type application/json with optional UTF-8 charset. */
        attribute profile_id : String;
        attribute revision : Integer;
        attribute settings : Settings;
    }
    item def SaveProfile :> WstxArchitecture::ProfileRequest {
        doc /* Station service forwards validated settings/revision to its existing
             selected profile, never selects a directory from a request. */
        attribute profile_id : String;
        attribute expectedRevision : Integer;
        attribute settings : Settings;
    }
    item def ProfileSnapshot :> WstxArchitecture::ProfileOutcome {
        doc /* Internal selected-profile response; runtime inputs remain private. */
        attribute document : ProfileDocument;
    }
    item def HttpProfileRepresentation :> WstxArchitecture::StationOutcome {
        doc /* GET/PUT 200 exactly these keys. endpoint is effective browser origin,
             not the bind object. application/json, Cache-Control no-store, <=8192
             bytes. No paths/secrets/schema_version or internal objects are exported. */
        attribute profile_id : String;
        attribute boot_id : String;
        attribute revision : Integer;
        attribute endpoint : String;
        attribute connection_type : ConnectionType;
        attribute settings : Settings;
    }
    item def HttpProfileError :> WstxArchitecture::StationOutcome {
        doc /* JSON {error:{code:<outcome spelling>,field:null}}; invalid_settings may
             identify a dotted field name, otherwise null. No values/paths/exceptions
             echoed. Error status mapping is HttpStatus below. */
        attribute outcome : HttpOutcome;
        attribute field : String[0..1];
    }

    calc def PutDecision {
        doc /* Ordered application checks. AuthValid includes trusted plaintext
             loopback or exactly one expected cookie with UUID+token verification.
             Lexical/body validators enforce all explicit schema domains above;
             settingsValid covers whole object, no partial edit. A transport body
             limit may return 413 earlier than this application ordering. All other
             failures preserve saved bytes/revision/authoritative settings. */
        in originValid : Boolean;
        in authValid : Boolean;
        in mediaTypeValid : Boolean;
        in bodyBytes : Integer;
        in settingsValid : Boolean;
        in profileMatches : Boolean;
        in expectedRevision : Integer;
        in currentRevision : Integer;
        in durableReplaceSucceeded : Boolean;
        return outcome : HttpOutcome =
            if not originValid ? HttpOutcome::forbidden_origin else
            if not authValid ? HttpOutcome::unauthorized else
            if not mediaTypeValid ? HttpOutcome::unsupported_media_type else
            if bodyBytes > 8192 ? HttpOutcome::request_too_large else
            if not settingsValid ? HttpOutcome::invalid_settings else
            if not profileMatches ? HttpOutcome::wrong_profile else
            if expectedRevision != currentRevision ? HttpOutcome::revision_conflict else
            if currentRevision == (900719925 * 10000000 + 4740991) ? HttpOutcome::revision_exhausted else
            if not durableReplaceSucceeded ? HttpOutcome::storage_unavailable else
            HttpOutcome::ok;
    }
    calc def ResponseBudgetAdmission {
        doc /* contract 12.5 cross-field bound, checked BEFORE readiness. Encode the complete
             HttpProfileRepresentation using the selected effective origin and worst
             valid later settings/revision, not merely the initial file values.
             Independent schema-1 compact UTF-8 oracle: 36-byte profile/boot UUIDs,
             revision9007199254740991, standard, display64 backslashes, callsign
             A12345678901, locatorRR99XX99, both audio identifiers256 backslashes,
             CAT endpoint256 backslashes, CAT mode, disabled PTT. Empty-origin full
             representation2018 bytes, so escaped origin contents may use6174 bytes.
             This is a derived complete-response constraint, not an arbitrary host
             limit. Actual response encoding supplies the byte count. Reject failure
             as invalid_profile; stable origin/identity/backend then reserve capacity
             for every valid later edit. Never truncate/substitute endpoint identity. */
        in completeWorstCaseUtf8Bytes : Integer;
        return admitted : Boolean = completeWorstCaseUtf8Bytes >= 0 and completeWorstCaseUtf8Bytes <= 8192;
    }
    calc def SaveSubmissionAllowed {
        in saving : Boolean;
        in conflict : Boolean;
        in unknownOutcome : Boolean;
        return allowed : Boolean = not saving and not conflict and not unknownOutcome;
        doc /* contract 12.5: background Refresh/profile snapshots cannot clear a pending,
             conflict or unknown-outcome save guard; explicit validated reload is required
             for conflict/unknown outcome. This guard covers programmatic submission too. */
    }
    calc def SnapshotApplicable {
        in sameBoot : Boolean;
        in candidateRevision : Integer;
        in displayedRevision : Integer;
        return applicable : Boolean = not sameBoot or candidateRevision >= displayedRevision;
    }
    calc def GetDecision {
        in originAbsentOrExact : Boolean;
        in authValid : Boolean;
        return outcome : HttpOutcome = if not originAbsentOrExact ?
            HttpOutcome::forbidden_origin else if not authValid ?
            HttpOutcome::unauthorized else HttpOutcome::ok;
    }
    calc def HttpStatus {
        in outcome : HttpOutcome;
        return status : Integer =
            if outcome == HttpOutcome::ok ? 200 else
            if outcome == HttpOutcome::forbidden_origin or outcome == HttpOutcome::wrong_profile ? 403 else
            if outcome == HttpOutcome::unauthorized ? 401 else
            if outcome == HttpOutcome::unsupported_media_type ? 415 else
            if outcome == HttpOutcome::request_too_large ? 413 else
            if outcome == HttpOutcome::invalid_settings ? 400 else
            if outcome == HttpOutcome::storage_unavailable ? 503 else 409;
    }
    calc def NextRevision {
        in beforeRevision : Integer;
        in saveOutcome : HttpOutcome;
        return afterRevision : Integer = if saveOutcome == HttpOutcome::ok ?
            beforeRevision + 1 else beforeRevision;
    }

    action def CreateProfile {
        doc /* Input --create-profile <directory>, sole command. Resolve relative path
             from CWD. Parent must exist and target must not, even if target would be
             empty. Create profile.json with the specified defaults and fresh UUID v4,
             revision 0; exit created without listener/browser. Never overwrite target.
             Unknown/duplicate/composed CLI arguments -> invalid_runtime_configuration.
             Existing target/absent parent/storage failure -> resource_unavailable.
             Creation is explicit; profile startup never falls back to creation. */
        in directoryArgument : String;
        out createdDocument : ProfileDocument[0..1];
        out outcome : StartupOutcome;
    }
    action def LaunchSelectedProfile {
        doc /* Input --profile <directory>. Resolve/canonicalize CWD-relative directory.
             Reject unknown/duplicate CLI flags, create/start combination or present
             WSTX_BIND/ORIGIN -> invalid_runtime_configuration. Load exact profile.json:
             missing/unreadable directory/file -> resource_unavailable; malformed JSON/
             UTF-8, duplicates/extra/missing keys/types/domains, >16384 bytes, invalid
             UUID, bind port 0/65536, malformed origin or port mismatch -> invalid_profile;
             integer schema !=1 -> unsupported_schema; native_flex ->
             unsupported_connection_type. Validate before accepting requests.
             Acquire OS-backed exclusive directory AND account-local UUID ownership;
             canonical aliases and copies of a currently owned UUID -> profile_in_use;
             denied lock acquisition -> resource_unavailable. Hold through lifetime.
             Validate runtime: incomplete TLS pair, TLS without token, token without
             TLS, invalid 32..128 ASCII alphanumeric token, insecure/incomplete remote
             inputs or saved origin/runtime scheme mismatch -> invalid_runtime_configuration;
             absent/unreadable/invalid cert/key -> resource_unavailable.
             Apply ResponseBudgetAdmission for the effective origin BEFORE readiness;
             a complete worst-case response over8192 bytes ->invalid_profile even when
             the file itself fits16384. Valid later settings must retain this guarantee.
             Bind port:
             occupied -> endpoint_in_use, other OS resource failure -> resource_unavailable.
             Single-fault fixtures have exactly these outcomes. All failed launches
             nonzero, no readiness/browser/attach/file rewrite/other process disruption.
             On ready assign fresh nonpersisted UUID v4 boot ID; report the effective
             browser origin, selected UUID/name, no secrets. No auto-opening browser.
             Readiness fixture deadline 10 seconds, no fixed N bound.
             No-argument startup preserves 12.1..12.4 environment mode and wstx.v1;
             GET/PUT /profile are 404 there; do not create/migrate/search a profile. */
        in directoryArgument : String;
        in runtime : RuntimeInputs;
        out selected : ProfileDocument[0..1];
        out bootIdentity : String[0..1];
        out effectiveBrowserOrigin : String[0..1];
        out outcome : StartupOutcome;
    }
    action def SaveSelectedProfile {
        doc /* Existing web adapter authenticates/validates Origin/decodes HTTP and
             calls station service, which calls only its selected profile owner.
             Serialize check+whole-settings validation+write with other saves; recheck
             expected revision at this serialized boundary. Wrong selected UUID 403,
             stale revision 409, exhausted 409. No identity/endpoint/connection-type
             edit through API. A competing stale writer cannot merge or overwrite.
             Write complete new JSON to same-directory temp, flush it, atomic replace;
             publish memory/revision and acknowledge only after replacement succeeds.
             Before replacement old bytes/revision remain authoritative; failure 503
             leaves both old disk and memory plus server available. After successful
             replace new complete document is authoritative, revision+1, response 200.
             GET overlapping save sees complete old or complete new revision.
             Lost response is resolved by GET, never automatic replay. No partial write
             acknowledgment, filesystem-path selection, driver activation or silent merge. */
        in request : SaveProfile;
        in beforeDocument : ProfileDocument;
        out afterDocument : ProfileDocument;
        out outcome : HttpOutcome;
        assert constraint identityStable { afterDocument.profile_id == beforeDocument.profile_id }
        assert constraint revisionEffect {
            afterDocument.revision == (if outcome == HttpOutcome::ok ? beforeDocument.revision + 1 else beforeDocument.revision)
        }
        assert constraint failedSettingsUnchanged {
            outcome != HttpOutcome::ok implies afterDocument.settings == beforeDocument.settings
        }
    }
    action def RecoverOrStopProfile {
        doc /* Stop releases listener/OS locks; crash releases OS-backed ownership too.
             File marker alone never owns directory/UUID; killed process can restart.
             Restart reads only profile.json; ignores leftover temps, never promotes.
             Missing/corrupt/future file fails without reset/rewrite/cross-profile copy.
             Operator restores a known complete copy while stopped, or explicitly
             creates a NEW directory/profile. External file writes while owned are
             unsupported. Endpoint edits while stopped must validate on next launch;
             UUID edits unsupported. Acknowledged save survives process/ordered OS
             restart; operator starts selected profile explicitly after OS reboot.
             No automatic backup selection, migration, autostart, device discovery,
             hostile-user guarantees or arbitrary power/storage-failure durability.
             Other N-1 processes/settings/sessions stay usable; no shared lifecycle. */
        in selected : ProfileDocument;
        out outcome : StartupOutcome;
    }
    action def AuthenticateProfile {
        doc /* Target issue22 authentication for selected persisted profiles. CL-022-01/02
             supersede the old UUID.runtime-token transport cookie, restart revocation
             and HttpOnly-only persistence rule. Existing runtime is not claimed to
             implement this amendment. Preserve POST /session raw-token body<=1024,
             exact Origin403 before authentication, invalid token401, oversized413,
             rate10attempts/60seconds per process429, TLS only and successful204.
             Successful bootstrap creates only a random256-bit ephemeral bootstrap
             context (60seconds), never a runtime-token cookie or ordinary-control grant.
             Host-only wstx_bootstrap_<UUID>, Path=/, Secure, HttpOnly, SameSite=Strict;
             its only uses are strict enrollment and the explicit bootstrap scope/identity
             setup operations below; it never authorizes ordinary control.
             Normal wstx_session_<UUID> contains a random256-bit opaque transport handle
             bound to one unrevoked scoped grant, Max-Age=28800. Verify exactly one
             expected cookie; malformed/duplicate/missing/cross-profile cookies401.
             Wrong/legacy token-valued cookies are not migrated into grants. Other
             names ignored. Expiry only removes transport readiness; retained key proof
             restores it automatically without another bootstrap submission.
             Transport handles follow RotateScopedTransport below; at most one current
             handle per grant and64 overall, elapsed monotonic lifetime28800seconds.
             Grant persistence is independent of transport rotation or expiry.
             One narrow new credential exception permits only a nonextractable P256
             signing CryptoKey in origin-scoped IndexedDB; no bootstrap token, private
             key export or token persistence in localStorage/sessionStorage/public
             profileJSON/URLs/logs/reports/retained submitted form state. Same-origin
             injected script/browser/OS compromise remains outside nonextractability.
             Environment-only legacy launch without a persisted selected profile retains
             its transient legacy auth contract and does not claim this durable grant.
             Existing WS exact Origin/wstx.v1/frame/rate/liveness protections remain;
             grant revocation closes affected WS and rejects later protected effects.
             Same-host processes remain trusted; distinct ports are not hostile-service
             isolation. No transmit role or permission is created. */
        in selectedUuid : String;
        in runtime : RuntimeInputs;
        out cookieName : String;
    }
    calc def StatusReady {
        in currentOpen : Boolean;
        in correlatedValidStatus : Boolean;
        in initializedOnThisSocket : Boolean;
        in validatedProfile : Boolean;
        return ready : Boolean = currentOpen and correlatedValidStatus and
            (initializedOnThisSocket or validatedProfile);
    }
    attribute statusProfileGetsInFlightMax : Integer = 1;
    attribute statusProfileFollowupsMax : Integer = 1;
    action def PresentAndEditProfile {
        doc /* Existing browser on embedded profile-mode flag, never error-based mode
             guessing. One real window per endpoint; operator opens readiness origin.
             Display full UUID/name/effective endpoint/boot UUID/revision with legacy
             radio/link/version; title contains display name and port. Before Connected
             require correlated status snapshot AND successful validated authenticated GET
             /profile on EACH new socket, before station-ready or optional display.
             After every await captured socket must remain current and OPEN before
             applying HTTP results. Established same-socket correlated status updates
             version/radio/Connected/updated and enables Refresh immediately, independent
             of settings HTTP. Still refresh saved settings asynchronously: at most one
             status-triggered GET in flight and one pending follow-up per socket.
             A repeated Refresh eventually fetches newest settings; no mutation replay.
             Failed background GET visibly fails and marks socket stale. Old/disconnected
             results cannot restore Connected or mutate newer snapshots/forms.
             GET body exactly ProfileRepresentation, no-store JSON <=8192 bytes.
             GET absent Origin is valid; supplied wrong Origin 403, no CORS permission.
             Form edits whole Settings only, expected revision and selected profile_id.
             UUID/schema/endpoint/connection type/revision read-only. Standard selected;
             Native FlexRadio reserved/disabled. All selections Saved; not activated;
             radio stays unconfigured; audio/control selection availability independent.
             PUT validates exact body shape/JSON/UTF8, media type/size before applying.
             Disable form controls while saving, preserving their read-only state;
             SaveSubmissionAllowed is the per-form submission guard. Refresh/profile
             GET completion must retain saving, conflict OR unknown outcome in Save's disabled state;
             a second submission during saving sends no second PUT. Restore editable
             controls after completion, while permanent read-only controls stay disabled.
             SnapshotApplicable rejects a lower revision from the same boot so a held
             Refresh cannot overwrite an acknowledged newer save/form. A changed boot
             permits authoritative restart/recovery resynchronization, including an
             independently restored lower revision.
             Invalid field preserves typed input with error, never Saved. Successful save
             updates revision only on durable 200. On 409 prompt reload before another
             save. An unknown outcome also requires explicit reload before another save,
             without automatic PUT replay or an assumed rollback. Refresh/reconnect reload authoritative settings; preserve in-progress
             edits until explicit reload or successful save. No settings polling/replay.
             Refresh fixture <=2 seconds unshaped loopback. Existing watchdog 12-second
             silence checked each second =>13-second detection; reconnect 1/2/4 seconds,
             snapshot+profile within 10 seconds after loss detection/restored link.
             Keep 12.3/12.4 existing bounds; no N-station thin-link guarantee is invented.
             Literal-text output, keyboard access/readability at desktop and 360px.
             HTTP error mappings are PutDecision/GetDecision/HttpStatus; unsupported
             methods 405 no mutation; environment-only GET/PUT return 404. */
        in authoritative : HttpProfileRepresentation;
        out edited : HttpProfilePut;
    }

    state def ProfileLifecycle {
        doc /* Lifecycle of the selected process/profile, not a second runtime part.
             Flags denote corresponding events/completed actions, not free policy.
             Starting runs LaunchSelectedProfile; saving runs SaveSelectedProfile.
             Successful/failed save returns running with new/old authoritative revision.
             Stop/crash releases ownership/listener; launch rejection never becomes
             ready. Crash during replacement yields complete old/new document per the
             save commit point, never a partially acknowledged document. */
        attribute startRequested : Boolean;
        attribute stopOrCrash : Boolean;
        attribute launchFinished : Boolean;
        attribute launchOutcome : StartupOutcome;
        attribute saveRequested : Boolean;
        attribute saveFinished : Boolean;
        entry; then stopped;
        state stopped;
        state starting;
        state running;
        state saving;
        state rejected;
        transition startProfile first stopped if startRequested then starting;
        transition started first starting if launchFinished and launchOutcome == StartupOutcome::ready then running;
        transition refused first starting if launchFinished and launchOutcome != StartupOutcome::ready then rejected;
        transition requestSave first running if saveRequested then saving;
        transition completeSave first saving if saveFinished then running;
        transition stopRunning first running if stopOrCrash then stopped;
        transition stopSaving first saving if stopOrCrash then stopped;
        transition stopStarting first starting if stopOrCrash then stopped;
        transition exitRejected first rejected then stopped;
    }

    enum def SaveBrowserEvent {
        enum submit; enum success; enum rejected; enum conflict;
        enum outcome_unknown; enum explicit_reload_validated;
    }
    state def BrowserSaveLifecycle {
        attribute acceptedEvent : SaveBrowserEvent;
        entry; then editable;
        state editable; state saving; state conflict; state unknownOutcome;
        transition submit first editable if acceptedEvent == SaveBrowserEvent::submit then saving;
        transition saved first saving if acceptedEvent == SaveBrowserEvent::success then editable;
        transition rejected first saving if acceptedEvent == SaveBrowserEvent::rejected then editable;
        transition conflicted first saving if acceptedEvent == SaveBrowserEvent::conflict then conflict;
        transition responseUnknown first saving if acceptedEvent == SaveBrowserEvent::outcome_unknown then unknownOutcome;
        transition reloadConflict first conflict if acceptedEvent == SaveBrowserEvent::explicit_reload_validated then editable;
        transition reloadUnknown first unknownOutcome if acceptedEvent == SaveBrowserEvent::explicit_reload_validated then editable;
        doc /* contract 12.5: browser form state, separate from the server process lifecycle.
             While saving, disable editable controls and allow no second PUT; completion
             restores editable fields without changing permanently read-only fields.
             Conflict and unknownOutcome keep Save disabled until explicit reload returns
             a validated authoritative profile on the current OPEN socket. Background GET,
             Refresh or reconnect alone cannot clear the reload requirement; failed reload
             leaves it set. No mutation replay. Known rejection shows error, not Saved. */
    }
    action createProfile : CreateProfile;
    action launchProfile : LaunchSelectedProfile;
    action saveProfile : SaveSelectedProfile;
    action stopOrRecover : RecoverOrStopProfile;
    action authenticate : AuthenticateProfile;
    action presentAndEdit : PresentAndEditProfile;

    attribute serverSource : String = "server/src/main.rs; server/src/profile.rs";
    attribute browserSource : String = "client/index.html; client/app.js; client/style.css";
    // Allocation references EXISTING actual deployment usages, never a duplicate part.
    dependency launchOwner from launchProfile to WstxArchitecture::physicalStation::backend::stations::profile;
    dependency saveOwner from saveProfile to WstxArchitecture::physicalStation::backend::stations::profile;
    dependency stationValidationOwner from saveProfile to WstxArchitecture::physicalStation::backend::stations::station;
    dependency authenticationOwner from authenticate to WstxArchitecture::physicalStation::backend::stations::web;
    dependency presentationOwner from presentAndEdit to WstxArchitecture::physicalStation::frontend::browsers;
    dependency createOwner from createProfile to WstxArchitecture::PersistedProfile;
    dependency lifecycleOwner from stopOrRecover to WstxArchitecture::physicalStation::backend::stations;
    dependency internalRequestRefinement from SaveProfile to WstxArchitecture::ProfileRequest;
    dependency externalRequestRefinement from HttpProfilePut to WstxArchitecture::StationRequest;
    satisfy WstxRequirements::'CL-005-01' by launchProfile;
    satisfy WstxRequirements::'CL-005-02' by saveProfile;
    satisfy WstxRequirements::'CL-005-03' by authenticate;
    satisfy WstxRequirements::'CL-005-04' by launchProfile;
    satisfy WstxRequirements::'CL-005-05' by presentAndEdit;

    package IndependentVerification {
        doc /* Case identities remain WstxRequirements::TC-022-001..004, projected
             from WstxRequirements and this package. No cases/verdicts are regenerated from
             action calculations. These declarations refine their subjects/oracles.
             Delivered source/test companions, level 2 isolated automated Windows PC tests;
             FOUR real candidate processes, distinct saved ports/profiles, four real
             Chromium windows sharing ONE context/cookie store; no radio/device/live
             account/external-service/duplicate hosted run. Rust profile tests in
             server/src/profile_tests.rs and server/src/auth_tests.rs; communication browser/
             process cases in tests/profiles.test.cjs, registered beside the legacy suite.
             Case names are TC-022-001..004; run node --test --test-concurrency=1
             tests/profiles.test.cjs after cargo build --locked. Rust companions run with
             cargo test --workspace --locked --all-targets. Execution evidence remains
             on issue #5; model declarations are not run results.
             Fixture expects UUID 00000000-0000-4000-8000-00000000000i for i=1..4,
             Station i, TESTi, JN47AA, revision0, standard, fixture-input-i/output-i,
             disabled/null/disabled control. Ports reserved+recorded independently.
             Bind127.0.0.1, saved TLS origin https://localhost:<port>; plaintext origin
             null =>http://127.0.0.1:<port>. Tokens independently generated, never logged.
             Hand-authored expected edit table and independently parsed JSON/file
             hashes are the oracle, NOT new code/model-produced golden outputs.
             Readiness <=10s, Refresh <=2s, recovery <=10s after detection/restored link.
             No fewer-than-four/zero-check pass; missing prerequisites fail. Variable-N
             implementation is reviewed to reject fixed four-entry arrays/assumptions;
             additional mandatory 1/6-server runtime repeats are not required. */
        verification variableServers {
            subject operation : PresentAndEditProfile;
            objective { verify WstxRequirements::'CL-005-01'; verify WstxRequirements::'CL-005-02'; verify WstxRequirements::'CL-005-03'; verify WstxRequirements::'CL-005-05'; }
            doc /* TC-022-001: four PID/listener/boot-ID/visible-UUID endpoints, Refresh
                 all. Edit only profile1: Edited station 1, changed-input-1, CAT endpoint
                 fixture-cat-1, CAT/disabled; retain output. Second window on same
                 station reloads acknowledged revision; other three settings/bytes stable.
                 Repeat audio-only/control-only/null-audio/CAT-disabled edits. Radio
                 stays unconfigured; no device opens; native disabled. Validate every
                 4.2 domain empty/max/one-beyond, types/duplicates/extra/missing keys,
                 malformed JSON/UTF8/enum/CAT/PTT, wrong UUID, stale/exhausted revision,
                 exact8192/8193 HTTP-byte bodies padded with whitespace and media type.
                 Valid boundaries persist; invalid leaves memory/disk/revision intact.
                 Two stale competing windows: one winner/one409, no merge.
                 Hold Refresh GET, start/hold PUT, then release GET: Save stays disabled,
                 repeated submit sends no second PUT. Release PUT, require one revision
                 increment and usable editable controls/Save, preserving read-only controls.
                 Inverse order on revision0 station: hold old Refresh, complete PUT and
                 its revision1 GET, then release old GET. Visible revision/form/name and
                 Saved1 feedback remain1; same-boot ordering does not reject changed boots.
                 Render <img src=x onerror=alert(1)> display name and
                 <script>alert(1)</script> audio ID literally, no element/dialog/script.
                 Desktop/360px identity/errors/Save readable and keyboard reachable.
                 Oracle: independent canonical domain table and independent fixture edits. */
        }
        verification persistence {
            subject operation : SaveSelectedProfile;
            objective { verify WstxRequirements::'CL-005-02'; verify WstxRequirements::'CL-005-04'; verify WstxRequirements::'CL-005-05'; }
            doc /* TC-022-002: create extra default profile, verify exact defaults/UUID,
                 no listener. Four browser saves; record independently expected fields,
                 UUIDs/revisions. Fresh processes after clearing inherited WSTX inputs
                 restore same settings/fixed endpoint/UUID/revision and fresh boot ID.
                 Restart/kill one after ack; stale marker/orphan temp ignored. No actual
                 OS reboot claimed (optional isolated VM only). Test missing file,
                 truncation/UTF8/unknown/duplicate/missing/type/UUID/schema0/2/port0/65536,
                 16384-byte valid whitespace padding versus16385, reserved native.
                 Exact startup categories per LaunchSelectedProfile and canonical domain table;
                 independent pre/post hashes unchanged. Restore bytes and restart.
                 Deny write/replace deterministically:503/no revision advance/old state.
                 Crash before/after replacement:complete old/new, never partial. Test-build-only
                 checkpoints execute the real save/write/sync/replace path with write,
                 flush and replace errors and interruptions before/after replacement;
                 reopen independently checks old/new JSON and retained revision. No
                 runtime fault knobs. Browser route fetches a real successful PUT then
                 aborts delivery; one PUT only and subsequent GET recovers commit. After
                 a lost response, Refresh/background GET/reconnect keeps Save disabled;
                 failed explicit reload keeps the guard and successful current-socket
                 validated explicit reload recovers the committed revision without another PUT. Lost
                 response GET, no replay. Relative path from different CWD, aliases,
                 absent parent/existing empty/nonempty create target, invalid CLI and
                 forbidden env all have mapped errors. Independent ResponseBudgetAdmission
                 fixture: the full worst-case representation with empty origin is2018
                 UTF-8 bytes; size the ASCII origin contents to6174 bytes. Startup and
                 actual GET/PUT bodies must fit exactly8192, including a save from
                 maxRevision-1 to maxRevision. One extra origin byte or a9000-character
                 hostname must fail invalid_profile BEFORE readiness without rewriting
                 any profile. Numeric loopback transports fixture requests with exact
                 saved Origin header; no external DNS/service. Expected bytes come from
                 independent case expectations, not the candidate helper. No migration/power-loss claim. */
        }
        verification lifecycleIsolation {
            subject operation : LaunchSelectedProfile;
            objective { verify WstxRequirements::'CL-005-03'; verify WstxRequirements::'CL-005-04'; }
            doc /* TC-022-003: stop/restart profile1 while other three Refresh<=2s and
                 UUID/settings unchanged. Original UUID/revision returns,new boot ID.
                 Running same path/alias/copied UUID ->profile_in_use; occupied port
                 ->endpoint_in_use. Denied storage and absent/unreadable/invalid TLS file
                 ->resource_unavailable; incomplete TLS/token absent/malformed/remote
                 plaintext/env overrides/runtime scheme mismatch ->invalid_runtime_configuration;
                 malformed stored origin/port mismatch ->invalid_profile.
                 Single fault each, nonzero within10s/no readiness/attach/file rewrite/
                 existing session interruption. Controlled resources, no PC exhaustion.
                 Release fault then launch. Killing owner releases lock; marker alone
                 cannot hold it. Oracle: original mapped faults and independent hashes. */
        }
        verification sharedBrowserSessions {
            subject operation : AuthenticateProfile;
            objective { verify WstxRequirements::'CL-005-03'; verify WstxRequirements::'CL-005-04'; }
            doc /* TC-022-004: four TLS localhost ports/tokens, ONE Chromium cookie
                 context. Before login GET/PUT/WS401; login all then reverse order204.
                 Ordinary same-origin browser GET without manual Origin200; cookie
                 names/attributes only reported. All four Refresh/reconnect independently.
                 Station1 token to station2 login401; copied name/value or value under
                 station2's expected name401; legacy cookie or duplicate expected name401.
                 Missing/wrong Origin login/PUT/WS403, including other station port and
                 unrelated origin. Transport-cookie expiry/proof recovery does not clear other cookies; ordinary restart retains grants.
                 Explicitly revoke station1 grants and rotate bootstrap+restart:old grants/token401,new enrollment succeeds,
                 other three usable. Exact UUID in PUT matches selected profile; wrong
                 UUID403, WS numeric correlation IDs retain existing local meaning.
                 Check 12.1 login body/rate independently per process, cookie attributes,
                 only HttpOnly handles and the CL-022-01 nonextractable IndexedDB key persist; no
                 local/sessionStorage/profileJSON/retained form/URL/log/report leakage. Failed
                 network login also clears DOM token immediately on submission.
                 Repeated Cookie headers are checked in the
                 separate auth_tests.rs vector, not only a single cookie string.
                 Oracle: original cookie/error/identity table and independent inputs;
                 trusted same-host processes only, not hostile-host isolation proof. */
        }
        verification statusReadiness {
            subject operation : PresentAndEditProfile;
            objective { verify WstxRequirements::'CL-005-02'; verify WstxRequirements::'CL-005-03'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-022-005, tests/profiles.test.cjs, level2 Windows real Chromium/server.
                 Established socket: hold GET/profile; actual correlated WS response and
                 changed updated/enabled Refresh <=2s BEFORE HTTP release. Repeated
                 Refresh: one in-flight GET plus one follow-up gets independently saved
                 newer revision and retains dirty input. Fresh socket: held initial GET
                 withholds Connected/station-ready/optional display until validated.
                 Close old socket with GET held, establish replacement, release old:
                 no reconnection or newer snapshot/form overwrite. Initial/background
                 GET failure visibly fails/stales, never successful configuration.
                 Oracle: WstxRequirements and this package, real WS and prepared revisions. */
        }
        dependency identity005 from statusReadiness to WstxRequirements::'TC-022-005';
        dependency identity001 from variableServers to WstxRequirements::'TC-022-001';
        dependency identity002 from persistence to WstxRequirements::'TC-022-002';
        dependency identity003 from lifecycleIsolation to WstxRequirements::'TC-022-003';
        dependency identity004 from sharedBrowserSessions to WstxRequirements::'TC-022-004';
    }

    doc /* Declared implementation freedoms: Rust file/module names and internal type
         layout, existing-library/std OS lock and atomic-write mechanisms, UUID/random
         implementation, JSON parser/validation routines implementing the exact domains,
         browser layout/accessibility details and deterministic disposable fault-injection
         technique. These choices may not alter wire/storage shape, identity/ownership,
         errors/order, trust scope, persistence commit point, required bounds or oracles.
         No additional dependencies, drivers, native Flex schemas, legacy migration or
         product behaviors are implicitly authorized by this list. */

    doc /* Issue22 target data/actions below implement CL-022-01/02 only after exact
         independent meaning review, supported-browser primitive qualification and
         source-scope admission. They reuse selected profile/station authority; no new
         physical component or public-profile schema field is introduced. */
    enum def GrantCondition { enum unauthorized; enum authorized; enum revoked; enum unknown; }
    enum def AuthOperationKind { enum enroll; enum challenge; enum prove; enum logout; enum revokeAll; enum receipt; enum commission; enum bootstrapScope; enum radioIdentity; enum status; }
    enum def AuthOperationOutcome { enum committed; enum proofRequired; enum unauthorized; enum wrongOrigin; enum invalid; enum saturated; enum persistenceFailed; enum unknown; }
    enum def RadioIdentityChange { enum add; enum replace; enum remove; }
    attribute maxActiveBrowserGrants : Integer = 64;
    attribute maxPendingProofChallenges : Integer = 64;
    attribute proofChallengeLifetimeSeconds : Integer = 60;
    attribute maxActiveTransportHandles : Integer = 64;
    attribute maxTransportHandlesPerGrant : Integer = 1;
    attribute transportLifetimeSeconds : Integer = 28800;
    action def RotateScopedTransport {
        doc /* Issue22 target behavior, not an implementation declaration. The volatile
             transport table is owned by the same selected-station authorization
             authority, not another credential store or lifecycle owner. It contains
             at most one current handle per existing unrevoked verifier grant and at
             most64 entries overall; no disk transport persistence or verifier eviction.
             Successful ordinary grant proof serializes current scope/grant/revocation
             validation, one-use challenge consumption and installation of a new
             CSPRNG256bit opaque handle. Installation atomically replaces the previous
             current handle for that SAME grant only. It does not replace a verifier,
             advance revocation generation, revoke another grant, change commissioning
             or disconnect CAT/audio. Other grants/profile processes remain unchanged.
             Replay or invalid/expired/wrong-Origin/wrong-scope proof never replaces a
             current handle. Random-generation or response-preparation failure fails
             closed without installing a handle or invalidating the prior current one;
             an already consumed nonce requires a new challenge, never proof replay.
             Installed handles expire after28800 elapsed monotonic seconds, never
             extended by use; cookie Max-Age remains28800. Expired/replaced/revoked/
             wrong-scope handles return401 for new protected HTTP requests/WS upgrades.
             Purge, rotation, expiry and ordinary restart do not delete or age-evict a
             verifier, operation receipt or commissioning. Restart drops only volatile
             transport; retained-key proof recovers without another bootstrap token.
             Receipt-purpose proof NEVER installs or replaces transport. Revocation or
             radio removal still invalidates dependent handles and existing effects/WS
             according to the existing authority/cancellation rules.
             Rotation is distinct from revocation: an already authenticated WS retains
             only its existing grant/scope/revocation authority and existing dispatch
             checks; rotation alone neither grants a new effect nor revokes its grant.
             An open socket never establishes current browser authorization readiness.
             Concurrent same-key proofs serialize; last committed proof determines the
             sole current handle. HTTP delivery can be reordered or lost, so204 alone
             does not prove the last-delivered cookie is current. The client shares its
             existing readiness promise within a document and checks protected read-only
             status after renewal. A401 or lost renewal response leaves readiness
             unavailable/unknown and recovers through fresh challenge/proof/status using
             the retained key, without bootstrap resubmission or user-mutation replay.
             Same-origin tabs share cookie storage; once overlapping responses quiesce,
             any tab can recover through fresh proof/status. Rotation by another tab
             never deletes the retained key or claims revocation. No cross-tab framework
             or additional credential store is introduced. Existing<=2s truthfulness,
             rate10/60, TLS/Origin/profile checks and1024byte auth bounds all remain. */
    }
    attribute def SelectedRadioAuthorizationScope {
        doc /* ProfileId is the persisted logical station identity in this phase;
             HTTPS origin is exact effective Endpoint.origin including port. UUIDs are
             lowercase RFC9562v4; safetyRevision is positive safe integer<=maxRevision.
             RadioId is authority-assigned, not COM endpoint/boot/browser identity.
             Migration assigns identity only, no grant or commissioning. Replacement
             creates a new UUID; endpoint/model/PTT change increments revision and
             invalidates commissioning. Unchanged USB return preserves both. */
        attribute profileId : String;
        attribute radioId : String;
        attribute safetyRevision : Integer;
        attribute httpsOrigin : String;
    }
    attribute def AuthWireScope {
        doc /* Every auth-v1 JSON scope/current_scope/expected_scope, including
             bootstrap/status/challenge/receipt/identity projections, is EXACTLY
             {profile_id,radio_id,safety_revision}; no https_origin/origin/extra keys.
             This is an ephemeral wire projection of SelectedRadioAuthorizationScope,
             not another selected-radio identity/current-value owner. Copy UUID/revision
             unchanged. In a request, first validate TLS and exact HTTP Origin against
             the selected Endpoint; reconstruct httpsOrigin only from that validated
             effective origin, never a body field. In responses browser already knows
             its exact location.origin. Reconstruction is lossless within this required
             endpoint context; the projection alone is not globally authoritative.
             Internal scope, persistence and both signed proof-purpose payloads KEEP
             the full exact origin and its length-prefixed signed bytes unchanged.
             For a new operation compare reconstructed profile/radio/revision with the
             current authority snapshot; stale tuple409/no effect. Explicit receipt
             reconciliation instead compares its stored operation tuple and never
             grants current control. Wrong transport Origin remains403 before auth;
             public profile origin domains/ResponseBudgetAdmission remain unchanged.
             Fixed UUID36/revision<=9007199254740991 give scope138UTF8bytes including
             all JSON punctuation/quotes. Compact-output independent width bounds:
             enrollment374, ordinary proof225, receipt proof426, identity request242,
             commissioning244, revoke236, challenge response396, receipt response<=302
             (conservative18ASCII outcome/43grantId), bootstrap receipt query67.
             Bootstrap response including current scope AND identity-receipt scope is
             440bytes (two138 scopes +164fixed fields/UUID/outcome/nullgrant); absent
             scope/receipt only shortens it. All below unchanged1024 logical-byte cap.
             These bounds are for compact server JSON; input whitespace may consume
             the remaining request allowance but total>1024 still413. All bounded
             strings here are canonical ASCII, so no hidden UTF8/escape growth.
             Status scope is likewise138, not an origin echo; its existing complete
             response<=1024 admission still includes condition/error/receive summary.
             No unbounded native text or copied numerical/result state is permitted. */
        attribute profileId : String;
        attribute radioId : String;
        attribute safetyRevision : Integer;
    }
    attribute def BrowserPublicVerifier {
        doc /* Public, not a secret. GrantId is fresh CSPRNG256bits encoded unpadded
             base64url43characters; never recycled. P256 SEC1 uncompressed public key
             is65bytes beginning04, canonical base64url87characters, on-curve validated.
             Enrollment operationId persists with this verifier for restart reconciliation.
             Exactly ECDSA_P256_SHA256_FIXED-compatible r||s; no algorithm negotiation.
             Grant lifetime keys only origin/profileId/radioId; recorded safetyRevision
             is not grant lifetime. A same-radio safety edit preserves the verifier,
             but proof binds the new current revision and CAT remains uncommissioned.
             This permits re-confirmation without bootstrap token re-entry. */
        attribute grantId : String;
        attribute enrollmentOperationId : String;
        attribute uncompressedPublicKeyBase64url : String;
        attribute scope : SelectedRadioAuthorizationScope;
    }
    attribute def RadioCommissioningRecord {
        doc /* Single current observable acknowledgement for exact scope and effective
             endpoint/model/PTT configuration. Owner persists it only after explicit
             Confirm receive-only setup. Never a CAT open/query or transmit action.
             Changed safety configuration invalidates it and exposes explicit recovery. */
        attribute scope : SelectedRadioAuthorizationScope;
        attribute receiveOnlyConfirmed : Boolean;
    }
    attribute def PrivateAuthorizationRecord {
        doc /* Version1 private per-profile atomic record under existing OS-protected
             service data, one selected-profile writer. Contains public verifiers and
             authority metadata, never browser private key/bootstrap token. Reuse
             acknowledged atomic replacement, not another database/storage writer.
             Corrupt/missing expected record or failed commit fails closed. Only a new
             never-enrolled profile may create an empty record; no reset-on-read-error.
             Unrevoked verifiers have no timed deletion. Removing a radio removes its
             grants; grant-cap failure never evicts active grants. Existing trusted-OS
             persistence boundary remains; no universal power-loss durability claim. */
        attribute schemaVersion : Integer = 1;
        attribute currentScope : SelectedRadioAuthorizationScope[0..1];
        attribute commissioning : RadioCommissioningRecord[0..1];
        attribute grants : BrowserPublicVerifier[0..64];
        attribute revocationGeneration : Integer;
        attribute operationReceipts : AuthOperationReceipt[0..64];
    }
    attribute def BootstrapScopeRequest {
        doc /* Exact POST /authorization/v1/bootstrap-scope request is {version:1};
             read-only identity-receipt reconciliation additionally has operation_id
             (UUIDv4). No other optional/unknown/duplicate fields. */
        attribute version : Integer = 1;
        attribute operationId : String[0..1];
    }
    attribute def BootstrapScopeResponse {
        doc /* Strict200 {version,current_scope,identity_receipt}; optional model
             features serialize as explicit JSON null. Scope is the station-authority
             snapshot, never a browser-supplied tuple; receipt is null on initial read.
             Reconciliation returns only the matching radioIdentity-kind receipt;
             absent/evicted/wrong-kind operation409 unknown, not fabricated success.
             Receipt.scope identifies that operation, not necessarily current scope.
             No grant/verifier enumeration, cookies, keys or credentials in response. */
        attribute version : Integer = 1;
        attribute currentScope : AuthWireScope[0..1];
        attribute identityReceipt : AuthOperationReceipt[0..1];
    }
    attribute def RadioIdentityRequest {
        doc /* Exact POST /authorization/v1/radio-identity JSON fields:
             version,operation_id,expected_scope,change. expected_scope is explicit
             null or the full last-authoritative scope; change is add/replace/remove.
             operation_id is browser-generated UUIDv4 retained through unknown outcome.
             This is explicit Add/Replace/Remove radio setup intent, not disable,
             reconnect, endpoint edit, commissioning or automatic browser recovery. */
        attribute version : Integer = 1;
        attribute operationId : String;
        attribute expectedScope : AuthWireScope[0..1];
        attribute change : RadioIdentityChange;
    }
    action def ReadBootstrapScope {
        doc /* Valid unexpired ephemeral bootstrap cookie for this selected profile
             required (missing/duplicate/wrong-profile401), exact Origin/TLS and all
             strict auth-v1 request/response/rate bounds apply. Cache-Control:no-store.
             POST is read-only: no identity/grant/receipt/challenge mutation, transport
             issuance, CAT/native I/O or implicit enrollment. After POST/session204,
             a fresh browser reads this response, then enrolls its exact non-null scope.
             Removed radio yields null; Add is explicit before enrollment, never inferred.
             Scope may race configuration: enrollment still compares authoritative
             scope and bootstrap binding at dispatch; stale tuple409, no effect.
             A read never rebinds a bootstrap context or broadens its enrollment scope. */
        in request : BootstrapScopeRequest;
        out response : BootstrapScopeResponse;
    }
    action def ChangeSelectedRadioIdentity {
        doc /* Same-profile unexpired bootstrap cookie and explicit setup intent are
             required; an ordinary grant/transport cookie alone is insufficient401.
             Strict auth-v1 bounds/errors apply. Before current-scope comparison,
             a committed same operation ID/equal parsed request returns its receipt
             without effects; different fields409. For a new operation compare
             expected_scope under existing station authority; add requires no current scope, replace/remove require
             exact current scope. Wrong presence/tuple or reused operation ID with
             different parsed fields409, no change. Initial selected-profile migration
             may assign its first logical UUID without a grant; Add is used after
             explicit removal, never repeated for an already selected identity.
             Fence access/automatic retry, use existing acknowledged close/cancellation
             before identity commit, without scan/query/set/PTT. No parallel native owner.
             Failed close retains quarantine and returns409 resource_quarantined, no
             identity commit. After confirmed release, recheck scope/configuration and
             atomically commit under the existing single profile writer: delete old
             grants/commissioning, advance revocation generation, and retain operation
             receipt/request in the existing bounded64-entry FIFO journal. Add/replace
             allocate fresh radio UUID, safetyRevision1 and exact current effective
             safety configuration; remove leaves no current scope/commissioning/grant.
             Public profile JSON/configuration is unchanged. With no selected scope,
             CAT stays disabled regardless of saved control settings; settings edits
             cannot silently Add. Ordinary disable/re-enable/USB return preserve UUID;
             endpoint/model/PTT edit only advances its safety revision as CL-022-02.
             Commit success rebinds only this explicit operation's bootstrap context
             to its resulting scope (null on removal), without extending its60s life;
             this is not a grant. New radio needs fresh enrollment and explicit current
             commissioning; no old proof/cookie/acknowledgement transfers. Return200
             AuthOperationReceipt: scope is resulting scope for add/replace, old scope
             for remove; grant_id null. Failed write503 keeps last committed identity
             and current-process access quarantined, never claims durable completion.
             Retain parsed request for same-operation equality; the browser never
             automatically resubmits this mutation. Lost response uses read-only
             bootstrap-scope(operation_id); after bootstrap expiry/restart, explicit
             bootstrap reauthorization permits reconciliation, not mutation replay.
             Missing/evicted receipt409 leaves operation outcome unknown. */
        in request : RadioIdentityRequest;
        out receipt : AuthOperationReceipt;
    }
    attribute def AuthChallenge {
        doc /* Server CSPRNG32byte nonce, canonical unpadded base64url43characters,
             one-use and60second monotonic validity; no wall-clock-expiry extension.
             Challenge binds currentScope,grantId,protocol1 and intended prove operation;
             currentScope is authority-selected current safety revision, not copied
             from an old verifier enrollment. Radio/profile/origin must still match.
             Signature payload is UTF8("WSTX-AUTH-PROOF") then byte01 then six fields:
             exact origin,profileId,radioId,decimal safetyRevision,grantId,nonce raw32.
             Each field is preceded by unsigned32-bit big-endian byte length; UUID and
             decimal fields ASCII, no padding/leadingzero, no Unicode normalization.
             Exactly this payload is signed with ECDSA SHA256; signature is64byte r||s
             (32byte unsigned big-endian coordinates), canonical base64url86characters.
             Reject noncanonical encoding, DER/ASN1, other length/curve/version/tuple,
             wrong origin, consumed/expired nonce. Valid proof atomically consumes nonce
             before transport issuance. Replays never mint another session. */
        attribute verifier : BrowserPublicVerifier;
        attribute currentScope : SelectedRadioAuthorizationScope;
        attribute nonceBase64url : String;
        attribute lifetimeSeconds : Integer = 60;
    }
    attribute def AuthEnrollmentRequest {
        doc /* Strict JSON version1,operation_id,scope,grant_id,public_key only. GrantId
             is browser-CSPRNG256bits generated and retained BEFORE submission;
             collision with a different verifier/operation is409, never replacement.
             This permits restart proof even when the enrollment response is lost.
             OperationId is
             fresh UUIDv4 retained by browser through unknown outcome. Bootstrap context
             authorizes this one exact scope; never grants another radio implicitly. */
        attribute version : Integer = 1;
        attribute operationId : String;
        attribute scope : AuthWireScope;
        attribute grantId : String;
        attribute publicKeyBase64url : String;
    }
    attribute def AuthProofRequest {
        doc /* Strict JSON version1,grant_id,nonce,signature only. Fields carry exact
             encodings above; server obtains scope from its challenge, never trusts a
             client-selected replacement. Request cap remains1024 logical UTF8bytes. */
        attribute version : Integer = 1;
        attribute grantId : String;
        attribute nonceBase64url : String;
        attribute signatureBase64url : String;
    }
    attribute def AuthOperationReceipt {
        doc /* Public strict response version1,operation_id,scope,outcome,grant_id;
             grant_id nullable; scope uses AuthWireScope on the wire, while journal
             scope below retains full internal context. No token,cookie,signature,nonce
             or private material.
             Receipt reconciliation identifies a committed operation, not authorization
             itself. Lost enrollment ACK retains a committed verifier; browser remains
             unknown/unauthorized until same operation receipt and scoped proof recover.
             Uncommitted enrollment is unusable after restart. Revocation commit fences
             queued effects; already-dispatched I/O follows acknowledged cancellation.
             Verifier-owned entries require ownerVerifier and no identityRequest;
             radioIdentity entries require identityRequest, no ownerVerifier and null
             grant_id. Only bootstrap-scope may reconcile the latter; proof/receipt
             paths reject them and cannot turn setup receipts into control authority.
             A failed revocation write quarantines current-process access but discloses
             NOT durably revoked; restart may restore last committed grant. */
        attribute version : Integer = 1;
        attribute operationId : String;
        attribute scope : SelectedRadioAuthorizationScope;
        attribute outcome : AuthOperationOutcome;
        attribute grantId : String[0..1];
        // Internal journal discriminator/owner; not additional public response keys.
        attribute operationKind : AuthOperationKind;
        attribute ownerVerifier : BrowserPublicVerifier[0..1];
        attribute identityRequest : RadioIdentityRequest[0..1];
    }
    action def HandleScopedAuthorization {
        doc /* Target strict auth API v1. Exact paths POST /authorization/v1/bootstrap-scope,
             /radio-identity,/status,/enroll,/challenge,/proof,/revoke,/commission,/receipt; no credentialed CORS.
             Existing POST /session stays raw-token, never accepts JSON extension keys.
             Every new request exactly version1 plus its listed fields; unknown,
             missing,duplicate keys/wrongtype/noncanonicalencoding400, contenttype
             application/json else415, body>1024bytes413, wrongOrigin403 first, TLS
             required before accepting credentials. At most10authattempts/60s/process;
             grant/challenge caps64, saturation429. All responses<=1024UTF8bytes,
             uncompressed, no auth material in errors/logs. No endpoint opens CAT.
             bootstrap-scope: BootstrapScopeRequest/Response via ReadBootstrapScope;
             radio-identity: RadioIdentityRequest via ChangeSelectedRadioIdentity;
             status: WstxOperatingReceive::AuthStatusRequest, read-only active-grant
             snapshot per AutomaticCatStatus, no effects and no GET fallback;
             enroll: AuthEnrollmentRequest, ephemeral bootstrap cookie required;
             non-null current scope and exact bootstrap-scope binding required, stale
             tuple409, no grant. A removed scope cannot enroll or prove readiness;
             challenge: {version,grant_id}, exact Origin and known verifier required;
             proof: AuthProofRequest; successful204 issues only new opaque transport;
             revoke: {version,operation_id,scope,all_for_radio}, matching active grant
             required; false logs out that grant, true revokes matching radio grants;
             commission: {version,operation_id,scope,receive_only_confirmed:true}, active
             matching grant required, commits exact displayed safety configuration;
             receipt: {version,operation_id,scope,grant_id,nonce,signature}; one-use
             receipt-purpose proof validates the operation owner, not ordinary-control
             authorization. Retain a bounded64-entry FIFO public receipt journal with
             original verifier for verifier-owned entries and committed outcome; it
             cannot authorize control or revive a revoked grant. Evicted/absent receipt returns409 unknown and
             browser remains unknown, never fabricates durable success. Journal entries
             persist atomically with their mutation and carry only bounded public
             verifier/scope/operation/outcome metadata or the parsed identityRequest;
             no bootstrap secret or unbounded tombstones. A separate challenge request
             {version,operation_id,scope} addresses a known receipt. Its payload uses
             UTF8 WSTX-AUTH-RECEIPT then byte01, followed by the same six length-prefixed
             proof fields plus operationId before nonce. Only receipt consumes this
             nonce; it never issues transport/control readiness. Ordinary grant proof
             uses WSTX-AUTH-PROOF and cannot substitute for receipt-purpose proof.
             Lost enrollment browser knows its pre-generated grantId, can prove its
             retained committed key then reconcile receipt while local readiness stays
             unknown; it dispatches no queued browser CAT effect before both succeed.
             Committed mutations return200 AuthOperationReceipt; unknown/failed commit
             never reports success (503persistence failure,409identity/unknown conflict).
             Missing/unknown/revoked/mismatched grant or cookie401. New challenge returns
             200 strict {version,grant_id,scope,public_key,nonce,lifetime_seconds},
             projecting AuthChallenge.currentScope through AuthWireScope and public
             verifier metadata; no origin is echoed or removed from signed bytes.
             Receipt uses same operationId only and is read-only even though POST.
             Bootstraprotation is explicit revoke-allprofile; process restart is not.
             Before protected HTTP/WS/native dispatch, station authority serializes
             current grant/scope/revocation generation with selection. No blanket
             session readiness from an open WS. Disconnect/401 is truthful<=2s and
             automatic retained-key proof does not replay a user mutation. */
        in kind : AuthOperationKind;
        in selected : SelectedRadioAuthorizationScope[0..1];
        out receipt : AuthOperationReceipt;
    }

}
