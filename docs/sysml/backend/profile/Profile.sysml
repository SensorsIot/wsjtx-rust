package WstxProfiles {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-001';
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::'FR-022';
    private import WstxRequirements::'CL-005-02';
    private import WstxRequirements::'CL-005-03';
    private import WstxRequirements::'TC-022-001';
    private import WstxRequirements::'TC-022-004';
    private import WstxStationProtocol::RuntimeInputs;

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
    attribute referenceAcceptanceCount : Integer = 4;
    attribute hasFixedPopulationLimit : Boolean = false;
    attribute readinessDeadlineSeconds : Integer = 10;

    attribute def AudioSelection {
        doc /* JSON object has exactly input_device/output_device, both required and
             nullable. Multiplicity zero means JSON null, NOT an omitted key. A present
             value is opaque nonempty UTF-8, <=256 bytes, no U+0000..001F or 007F..009F.
             Defaults null/null. Save independently; do not enumerate/open devices.
             The UI chooses them by endpoint name (#44 CL-044-08). */
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
    enum def AgcSetting { enum FAST; enum MID; enum SLOW; }
    attribute def RadioSettings {
        doc /* #44 CL-044-10: the radio settings the station manages over CAT, exactly
             agc (FAST|MID|SLOW, default SLOW for FT8/FT4 on the IC-7300). Present only
             while control is CAT on an IC-7300 CI-V endpoint, absent otherwise; separate
             from ControlSelection, which is the receive-only confirmation's identity.
             power_limit_pct (CL-044-12, optional 1..100): the profile power, the Po in
             percent of the radio's full scale the Tx level never drives above; absent,
             only the radio's own RF power setting limits it. The Tx level itself is not
             part of the profile document: it lives in tx-level.json of the profile
             directory, so that storing it does not advance the revision. */
        attribute agc : AgcSetting = AgcSetting::SLOW;
        attribute power_limit_pct : Integer[0..1];
    }
    attribute def Settings {
        doc /* Exactly these five required fields and the optional radio (CL-044-10). display_name: 1..64 UTF-8 bytes,
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
        /* #44 CL-044-10: optional sixth key radio, present exactly for a managed radio;
           an edit without it keeps the saved value. */
        attribute radio : RadioSettings[0..1];
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
             callsign, locator, endpoint, connection_type, audio, control (and radio for a managed radio, CL-044-10). Settings
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
             any other integer schema than 1 or a schema 2 NativeProfileDocument ->
             unsupported_schema; schema 1 naming native_flex -> unsupported_connection_type. Validate before accepting requests.
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

    attribute serverSource : String = "server/src/main.rs; server/src/profile.rs";
    // Allocation references EXISTING actual deployment usages, never a duplicate part.
    dependency launchOwner from launchProfile to WstxArchitecture::physicalStation::backend::stations::profile;
    dependency saveOwner from saveProfile to WstxArchitecture::physicalStation::backend::stations::profile;
    dependency stationValidationOwner from saveProfile to WstxArchitecture::physicalStation::backend::stations::station;
    dependency createOwner from createProfile to WstxArchitecture::PersistedProfile;
    dependency lifecycleOwner from stopOrRecover to WstxArchitecture::physicalStation::backend::stations;
    dependency internalRequestRefinement from SaveProfile to WstxArchitecture::ProfileRequest;
    dependency externalRequestRefinement from HttpProfilePut to WstxArchitecture::StationRequest;
    satisfy WstxProfiles::'CL-005-01' by launchProfile;
    satisfy WstxRequirements::'CL-005-02' by saveProfile;
    satisfy WstxProfiles::'CL-005-04' by launchProfile;

    package IndependentVerification {
        verification persistence {
            subject operation : SaveSelectedProfile;
            objective { verify WstxRequirements::'CL-005-02'; verify WstxProfiles::'CL-005-04'; verify WstxProfiles::'CL-005-05'; }
            doc /* TC-022-002: operational browser saves/recovery use the common HTTPS/
                 grant partition; HTTP/startup compatibility remains independently tested.
                 Create extra default profile, verify exact defaults/UUID,
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
                 a lost response, Refresh, an announced GET or a reconnect keeps Save disabled;
                 failed explicit reload keeps the guard and successful current-socket
                 validated explicit reload recovers the committed revision without another PUT. Lost
                 response GET, no replay. Relative path from different CWD, aliases,
                 absent parent/existing empty/nonempty create target, invalid CLI and
                 forbidden env all have mapped errors. Independent ResponseBudgetAdmission
                 fixture remains plaintext numeric loopback with the independently sized
                 saved Origin, no protected browser/WS claim or TLS/DNS requirement:
                 the full worst-case representation with empty origin is2018
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
            objective { verify WstxRequirements::'CL-005-03'; verify WstxProfiles::'CL-005-04'; }
            doc /* TC-022-003: operational windows use the common HTTPS/grant partition;
                 retain separate plaintext startup/configuration variants. Each fault
                 starts with otherwise valid transport-specific TLS/token inputs, so a
                 missing prerequisite cannot replace the intended single fault.
                 Stop/restart profile1 while other three Refresh<=2s and
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
        dependency identity002 from persistence to WstxProfiles::'TC-022-002';
        dependency identity003 from lifecycleIsolation to WstxProfiles::'TC-022-003';
    }

    doc /* Declared implementation freedoms: Rust file/module names and internal type
         layout, existing-library/std OS lock and atomic-write mechanisms, UUID/random
         implementation, JSON parser/validation routines implementing the exact domains,
         browser layout/accessibility details and deterministic disposable fault-injection
         technique. These choices may not alter wire/storage shape, identity/ownership,
         errors/order, trust scope, persistence commit point, required bounds or oracles.
         No additional dependencies, drivers, native Flex schemas, legacy migration or
         product behaviors are implicitly authorized by this list. */

    requirement NativeProfileDocument {
        doc /* FR-023 native profile persistence. A standard profile remains the exact
             schema-1 document; a schema-1 document naming native_flex stays refused with
             unsupported_connection_type. A native profile is a schema-2 document with the
             same keys plus connection_type native_flex and required native object
             {client_id: lowercase v4 UUID generated at creation (this station's GUI-client
             identity, not a radio identity), rx_antenna: 1..16 uppercase
             letters/digits/underscore, optional radio_address: IPv4 address:port, a locator for a
             radio discovery cannot reach (operator decision on #13, 2026-11-06), never an identity
             and never compared}; an explicit null or unknown key is invalid_profile, a
             schema-2 document without the native object stays unsupported_schema, and older
             binaries refuse it as unsupported_schema. Its audio selections stay null, control
             and PTT disabled and it has no managed radio settings; a PUT naming them is
             invalid_settings with that field. Radio serial, slice index/letter, DAX
             channel, stream ID, client handle and tuning are never persisted. GET/PUT /profile
             shapes are unchanged; connection type is not editable. */
    }
    dependency nativeProfileDocument from NativeProfileDocument to WstxRequirements::'FR-023';
    requirement 'CL-005-01' {
        doc /* A selected profile owns one process/listener; N is variable and storage, process and browser collections MUST NOT assume four entries. Four concurrent servers are sufficient for CR #5 acceptance; the implementation has no four-instance ceiling. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_01_to_FR_022 from 'CL-005-01' to 'FR-022';
    requirement 'CL-005-04' {
        doc /* Ownership, invalid storage, occupied endpoints and unavailable startup resources MUST fail explicitly without replacing saved configuration or disrupting a running instance. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_04_to_FR_016 from 'CL-005-04' to 'FR-016';
    dependency CL_005_04_to_FR_021 from 'CL-005-04' to 'FR-021';
    dependency CL_005_04_to_FR_022 from 'CL-005-04' to 'FR-022';
    requirement 'CL-005-05' {
        doc /* Standard audio with optional CAT/PTT remains the default. Audio and control selections MUST persist independently without claiming hardware availability. A schema-1 document naming native_flex stays refused; a native profile is a separate schema-2 document chosen at profile creation (FR-023, WstxProfiles::NativeProfileDocument). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_05_to_FR_001 from 'CL-005-05' to 'FR-001';
    dependency CL_005_05_to_FR_022 from 'CL-005-05' to 'FR-022';
    verification 'TC-022-002' {
        doc /* #### TC-022-002 — Persistence and independent restart

             **Promises:** FR-001, FR-016, FR-022; CL-005-02, CL-005-04, CL-005-05.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, disposable storage,
             N real processes/windows. No full OS reboot is required or claimed by this case.

             **Setup partition:** Browser saves, recovery and restart observations use the
             common operational HTTPS/grant fixture; trusted plaintext loopback HTTP/startup
             compatibility remains independently mandatory, including the complete validation,
             error/storage/file invariants and exact8192 response-budget fixture. An ordinary
             unchanged-bootstrap restart retains unrevoked grants, without enrollment replay.

             **Steps:** Create an additional profile with `--create-profile`, independently check
             all creation defaults and UUID v4, and verify creation exits without listening. Save
             different editable values through each table profile's browser, record acknowledged
             revisions/UUIDs, stop all processes, clear inherited WSTX variables and restart using
             only the same paths plus explicit required TLS/token inputs. Reopen/refresh windows.
             Stop/restart only profile 1 again; then kill it after an acknowledged save and restart.

             **Oracle/outcome:** Saved fields, fixed endpoints, profile UUIDs and revisions exactly
             match the independent input/edit table; boot IDs change. Other profiles remain unchanged.
             A stale lock marker does not block restart and an orphan temporary file is never loaded.
             The fresh-process restart is evidence for process-independent storage; actual OS reboot
             is unexecuted unless separately reported from a disposable Windows VM.

             **Recovery/error variants:** Preserve independent byte hashes of all profile files.
             With the target stopped, test missing file, truncated JSON, malformed UTF-8, duplicate/
             unknown/missing fields, invalid UUID, schema 0/2, port 0/65536 and a 16,385-byte file;
             an otherwise valid 16,384-byte file padded with whitespace is accepted. Also try
             a schema-1 document naming `native_flex` and require `unsupported_connection_type`, without an attempted radio
             connection or a change to the standard profile's stored settings.
             Each invalid launch fails nonzero with the defined category and no listener or file rewrite;
             others remain usable. Restore the original bytes and restart successfully. During a
             save inject a deterministic denied-write/atomic-replace failure in disposable storage:
             no acknowledgement, no revision advance, previous complete JSON and current settings
             remain authoritative. At crash-before/after-replacement fault points require either
             complete old or complete new JSON, never a partial file; a lost response is reconciled
             by GET without replay. After a lost save response, ordinary Refresh, an announced GET or
             reconnect MUST NOT permit a second save: Save remains disabled until an explicit reload
             successfully validates the current authoritative profile. A failed explicit reload keeps
             that guard; a successful one recovers the committed revision without a second PUT.
             Test a relative profile argument from another working directory,
             a directory alias, absent parent on creation, existing empty/nonempty creation target,
             unknown/duplicate CLI flags and forbidden WSTX_BIND/WSTX_ORIGIN overrides. No fallback
             or mutation is permitted. This does not certify power-loss durability or WSJT-X migration.
             The cross-field response-budget fixture remains plaintext numeric loopback with
             an independently long saved Origin, not a protected browser/TLS/DNS/grant fixture.
             For the cross-field response budget, independently build the maximum-encoded-settings
             vector in 12.5. With the selected origin sized so its complete representation is exactly
             8,192 UTF-8 bytes, startup and GET succeed; save from revision 9,007,199,254,740,990 to
             9,007,199,254,740,991 and require a successful response of exactly 8,192 bytes. Increase
             that origin by one unescaped ASCII byte, then separately use a 9,000-character hostname:
             both launches fail `invalid_profile` before readiness without changing stored bytes.
             Use the numeric loopback address to transport the fixture requests and the saved origin
             as the exact Origin header; no external DNS or service is contacted. Other instances
             remain usable. These expectations come from the independent byte calculation, not the
             candidate's admission helper. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-02';
            verify 'CL-005-04';
            verify 'CL-005-05';
            verify 'FR-001';
            verify 'FR-016';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
    }
    verification 'TC-022-003' {
        doc /* #### TC-022-003 — Stop isolation and collision refusal

             **Promises:** FR-021, FR-022; CL-005-03, CL-005-04.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, N real server/browser
             instances, OS port reservations, ownership aliases/copies and disposable resource fixtures.

             **Setup partition:** Operational windows use the common four-process HTTPS/
             grant fixture; retain separate plaintext launch/configuration variants. Each
             negative launch has otherwise valid transport-specific TLS/token inputs, so the
             intended single fault is not replaced by a missing prerequisite or scheme mismatch.

             **Steps:** Stop profile 1 and query the other N-1 before, during and after its restart.
             While the original is running attempt: the same profile path, an alias to that directory,
             a copied directory retaining its UUID, and a new UUID/profile requesting an occupied
             port. For separate stopped copies test denied directory access, missing/unreadable TLS
             certificate/key, incomplete TLS pair, absent/invalid token and insecure remote binding.
             Test saved-origin port mismatch separately from a runtime scheme mismatch; the 4.2
             table supplies their distinct expected categories.
             Use a controlled startup resource failure for any exhaustion branch; never exhaust the
             operator PC. After failed launch remove the failing condition and launch successfully.

             **Oracle/outcome:** Only the stopped window becomes stale. N-1 Refresh requests continue
             to match their table identities within two seconds. Restart returns profile 1's UUID and
             saved revision with a fresh boot ID. Every conflicting launch fails within the ten-second
             fixture deadline, nonzero, with exactly the category mapped to its single injected
             fault by 4.2's startup-error table; no readiness, browser attachment, settings rewrite
             or existing-session interruption occurs. Pre/post byte hashes of saved files agree.
             Killing a process releases its ownership claim; a stale marker alone does not own it.
             A copied UUID is rejected until the owning process exits, irrespective of directory name.

             **Automation coverage:** Existing companions retain delivered profile launch,
             fault and lifecycle-isolation subsets. The operational HTTPS/grant browser
             fixture conversion and complete transport-partition companions remain pending;
             the expanded case is partial, with every existing launch/error oracle retained. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-03';
            verify 'CL-005-04';
            verify 'FR-021';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
    }
    dependency CL_005_01_verified_by_TC_022_001 from 'CL-005-01' to 'TC-022-001';
    dependency CL_005_04_verified_by_TC_022_002 from 'CL-005-04' to 'TC-022-002';
    dependency CL_005_04_verified_by_TC_022_003 from 'CL-005-04' to 'TC-022-003';
    dependency CL_005_04_verified_by_TC_022_004 from 'CL-005-04' to 'TC-022-004';
    dependency CL_005_05_verified_by_TC_022_001 from 'CL-005-05' to 'TC-022-001';
    dependency CL_005_05_verified_by_TC_022_002 from 'CL-005-05' to 'TC-022-002';
}
