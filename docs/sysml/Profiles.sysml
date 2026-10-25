// Canonical profile contract SHA256: 8bbbb297e06fedde8e6d23fdea2322019ffb249da2823fcc15695bebb726ff4b
package WstxProfiles {
    private import ScalarValues::*;

    doc /* Implementation contract for the delivered CR #5 profile functionality. Review,
         validation and acceptance evidence remains on issue #5; no modeled verification verdict is asserted. Markdown remains authoritative:
         docs/WSTX Rust FSD.md 4.2 (selection/schema/ownership), 6.2 (independent cases),
         12.5 (HTTP/session); existing 12.1..12.4 remain the legacy/status contract.
         UUID: RFC 9562 section 5.4, https://www.rfc-editor.org/rfc/rfc9562.html#section-5.4.
         HTTP: RFC 9110, https://www.rfc-editor.org/rfc/rfc9110.html.
         Cookies: RFC 6265 section 8.5, https://www.rfc-editor.org/rfc/rfc6265.html#section-8.5.
         This file supplies behavior/data/state/error/ownership semantics absent from
         the generated Requirements projection. Pinned validation checks names/types,
         not execution, equivalence, real OS atomicity or successful test results.
         Readiness requires independent comparison with the original Markdown first. */

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
        doc /* FSD12.5 cross-field bound, checked BEFORE readiness. Encode the complete
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
        return allowed : Boolean = not saving and not conflict;
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
        doc /* Preserve 12.1 POST /session raw-token body <=1024 bytes, exact Origin,
             10 attempts/60 seconds PER PROCESS, TLS only for tokens. Wrong Origin
             403 before auth; invalid token 401; oversized 413; over rate 429; valid 204.
             Profile cookie name wstx_session_<full-lowercase-hyphenated-UUID>, value
             <UUID>.<runtime-token>; verify both UUID and token, accept exactly one
             expected-name cookie. Other names ignored including legacy wstx_session.
             Duplicate expected-name/missing/wrong/cross-profile value ->401 for WS,
             GET and PUT. Host-only (no Domain), Path=/, Secure, HttpOnly,
             SameSite=Strict, Max-Age=28800. Expiry is browser lifetime, not a new
             server-enforced session expiry. Token rotation plus this process restart
             invalidates only this profile's old credential; never delete others' cookies.
             TLS WS still exact Origin, wstx.v1, 1024-byte incoming/control frames,
             opt-in outbound Detailed exception in12.6, existing rate/liveness/
             connection rules. No account roles or transmit authority are created.
             HttpOnly cookie is permitted credential persistence; forbid localStorage,
             sessionStorage, profile JSON, retained form/page state after submission,
             URLs/logs/reports. Runtime secret values never reported.
             Same-host station processes are trusted by the same operator: namespacing
             fixes accidental cookie collisions, NOT hostile same-host services.
             Mutually distrusting services need separate host/origin boundaries. */
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
             GET completion must retain saving OR conflict in Save's disabled state;
             a second submission during saving sends no second PUT. Restore editable
             controls after completion, while permanent read-only controls stay disabled.
             SnapshotApplicable rejects a lower revision from the same boot so a held
             Refresh cannot overwrite an acknowledged newer save/form. A changed boot
             permits authoritative restart/recovery resynchronization, including an
             independently restored lower revision.
             edits typed after submission cannot be clobbered by its acknowledgement.
             Invalid field preserves typed input with error, never Saved. Successful save
             updates revision only on durable 200. On 409 prompt reload before another
             save. Refresh/reconnect reload authoritative settings; preserve in-progress
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

    action createProfile : CreateProfile;
    action launchProfile : LaunchSelectedProfile;
    action saveProfile : SaveSelectedProfile;
    action stopOrRecover : RecoverOrStopProfile;
    action authenticate : AuthenticateProfile;
    action presentAndEdit : PresentAndEditProfile;

    attribute serverSource : String = "server/src/main.rs; server/src/profile.rs";
    attribute browserSource : String = "client/index.html; client/app.js; client/style.css";
    // Allocation references EXISTING actual deployment usages, never a duplicate part.
    dependency launchOwner from launchProfile to WstxArchitecture::physicalStation::controller::stations::profile;
    dependency saveOwner from saveProfile to WstxArchitecture::physicalStation::controller::stations::profile;
    dependency stationValidationOwner from saveProfile to WstxArchitecture::physicalStation::controller::stations::station;
    dependency authenticationOwner from authenticate to WstxArchitecture::physicalStation::controller::stations::web;
    dependency presentationOwner from presentAndEdit to WstxArchitecture::physicalStation::viewer::browsers;
    dependency createOwner from createProfile to WstxArchitecture::PersistedProfile;
    dependency lifecycleOwner from stopOrRecover to WstxArchitecture::physicalStation::controller::stations;
    dependency internalRequestRefinement from SaveProfile to WstxArchitecture::ProfileRequest;
    dependency externalRequestRefinement from HttpProfilePut to WstxArchitecture::StationRequest;
    satisfy WstxRequirements::'CL-005-01' by launchProfile;
    satisfy WstxRequirements::'CL-005-02' by saveProfile;
    satisfy WstxRequirements::'CL-005-03' by authenticate;
    satisfy WstxRequirements::'CL-005-04' by launchProfile;
    satisfy WstxRequirements::'CL-005-05' by presentAndEdit;

    package IndependentVerification {
        doc /* Case identities remain WstxRequirements::TC-022-001..004, projected
             from authoritative Markdown 6.2. No cases/verdicts are regenerated from
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
                 Oracle: original Markdown/domain table and independent fixture edits. */
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
                 Exact startup categories per LaunchSelectedProfile and Markdown table;
                 independent pre/post hashes unchanged. Restore bytes and restart.
                 Deny write/replace deterministically:503/no revision advance/old state.
                 Crash before/after replacement:complete old/new, never partial. Test-build-only
                 checkpoints execute the real save/write/sync/replace path with write,
                 flush and replace errors and interruptions before/after replacement;
                 reopen independently checks old/new JSON and retained revision. No
                 runtime fault knobs. Browser route fetches a real successful PUT then
                 aborts delivery; one PUT only and subsequent GET recovers commit. Lost
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
                 original Markdown, not the candidate helper. No migration/power-loss claim. */
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
                 unrelated origin. Cookie expiry/re-login does not clear other cookies.
                 Rotate only station1 token+restart:old token/session401,new login succeeds,
                 other three usable. Exact UUID in PUT matches selected profile; wrong
                 UUID403, WS numeric correlation IDs retain existing local meaning.
                 Check 12.1 login body/rate independently per process, cookie attributes,
                 no secrets except required HttpOnly cookie in permitted store; no
                 local/sessionStorage/profileJSON/retained form/URL/log/report leakage. Failed
                 network login also clears DOM token immediately on submission; password
                 autocomplete is disabled. Repeated Cookie headers are checked in the
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
                 Oracle: original Markdown6.2/12.5, real WS and prepared revisions. */
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
}
