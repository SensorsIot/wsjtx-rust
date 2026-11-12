package WstxProfiles {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-001';
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::'FR-022';
    private import WstxRequirements::'FR-023';
    private import WstxRequirements::'CL-005-02';
    private import WstxRequirements::'CL-005-03';
    private import WstxRequirements::'TC-022-001';
    private import WstxRequirements::'TC-022-004';
    private import WstxStationProtocol::RuntimeInputs;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::Conflict;
    doc /* The profile part (WstxArchitecture::PersistedProfile, deployed as
         physicalStation::backend::stations::profile): the saved profile of one station, its
         creation, its launch with ownership, its save through GET and PUT /profile, its stop
         and its recovery. Its directory is the outside thing
         WstxArchitecture::OutsideThing::profileFiles. The recordings function of the part is
         WstxProfileRecordings; authentication is the web part's (WstxStationProtocol), the
         profile form the browser's (WstxOperatingLayout). */
    doc /* The content coding of a GET /profile body is
         WstxOperatingReceive::HttpContentCodingBoundary's; the checks of this package come
         before it, and it adds no owner, wire JSON or WebSocket codec. */
    @ImplementedIn { module = "server/src/profile.rs; server/src/main.rs"; }

    enum def ConnectionType { enum 'standard'; enum native_flex; }
    enum def ControlMode { enum disabled; enum cat; }
    enum def PttMode { enum disabled; enum cat; }
    enum def StartupOutcome {
        doc /* The outcome of a launch or a creation, written as the process output and the
             exit: ready and created end with exit 0, every other member with a nonzero
             exit. */
        enum ready; enum created; enum invalid_runtime_configuration;
        enum resource_unavailable; enum invalid_profile; enum unsupported_schema;
        enum unsupported_connection_type; enum profile_in_use; enum endpoint_in_use;
    }
    enum def HttpOutcome {
        doc /* The outcome of GET or PUT /profile; HttpStatus gives its status and
             HttpProfileError its body. */
        enum ok; enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_settings; enum wrong_profile;
        enum revision_conflict; enum revision_exhausted; enum storage_unavailable;
    }

    attribute maxRevision : Integer = (900719925 * 10000000 + 4740991) {
        doc /* The largest revision: 2^53 - 1, the largest integer a JSON number carries
             exactly. */
        @FollowsSource { reference = "RFC 7493 section 2.2"; }
    }
    attribute profileFileMaxBytes : Integer = 16384 {
        doc /* The largest profile.json, in UTF-8 bytes. */
    }
    attribute profileHttpMaxBytes : Integer = 8192 {
        doc /* The largest PUT /profile body and the largest GET or PUT /profile response, in
             UTF-8 bytes. */
    }
    attribute readinessDeadlineSeconds : Integer = 10 {
        doc /* A launch reports readiness or exits within this time. */
    }

    attribute def AudioSelection {
        doc /* Exactly the keys input_device and output_device, both required and nullable:
             null is a JSON null, never an omitted key. A value is opaque nonempty UTF-8 of at
             most 256 bytes without U+0000..001F or U+007F..009F. The two are saved
             independently; saving them enumerates and opens no device. The browser offers
             them by endpoint name (CL-044-08). */
        attribute input_device : String[0..1] = null;
        attribute output_device : String[0..1] = null;
    }
    attribute def ControlSelection {
        doc /* Exactly the keys mode, endpoint and ptt. The endpoint is null exactly when mode
             is disabled; with mode cat it is opaque nonempty UTF-8 of at most 256 bytes
             without control characters. PTT cat requires mode cat. The selection is intent:
             no driver and no evidence that the device is available. */
        attribute mode : ControlMode = ControlMode::disabled;
        attribute endpoint : String[0..1] = null;
        attribute ptt : PttMode = PttMode::disabled;
        assert constraint noCatPttWithoutCat {
            ptt == PttMode::cat implies mode == ControlMode::cat
        }
    }
    enum def AgcSetting { enum FAST; enum MID; enum SLOW; }
    attribute def RadioSettings {
        doc /* The radio settings the station manages over CAT (CL-044-10): present exactly
             while control is CAT on an IC-7300 CI-V endpoint. agc is FAST, MID or SLOW,
             SLOW for FT8 and FT4 on the IC-7300. RadioSettings is separate from
             ControlSelection, which identifies the receive-only confirmation. */
        doc /* power_limit_pct (CL-044-12), optional 1..100, is the profile power: the Po in
             percent of the radio's full scale that the Tx level never drives above; without
             it only the radio's own RF power setting limits it. The Tx level is not in the
             profile document: it is tx-level.json in the profile directory, and storing it
             does not advance the revision. */
        attribute agc : AgcSetting = AgcSetting::SLOW;
        attribute power_limit_pct : Integer[0..1];
    }
    attribute def Settings {
        doc /* The five editable fields and the optional radio (CL-044-10). display_name is
             1..64 UTF-8 bytes without leading or trailing whitespace or control characters
             (U+0000..001F, U+007F..009F). callsign is empty or 3..12 ASCII uppercase letters,
             digits or slash with at least one letter and one digit. locator is empty or a
             4, 6 or 8 character Maidenhead locator, [A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?. No
             value is normalized and no national callsign rule is claimed. An invalid value is
             refused, never replaced by a default. */
        doc /* radio is present exactly for a managed radio; an edit without it keeps the
             saved value. The browser renders every string of the profile literally, also in
             the title and in errors, never as markup. */
        attribute display_name : String = "New station";
        attribute callsign : String = "";
        attribute locator : String = "";
        attribute audio : AudioSelection;
        attribute control : ControlSelection;
        attribute radio : RadioSettings[0..1];
    }
    attribute def Endpoint {
        doc /* Exactly the keys bind and origin. bind is a numeric socket address, IP and port
             1..65535; port 0 is refused in profile mode. origin is required and nullable: null
             only for a loopback bind, whose origin is then the scheme, the bound IP and the
             port; otherwise scheme://host:port without credentials, path, query, fragment or
             trailing slash, whose scheme matches the runtime TLS and whose port is the bind
             port. The host may be localhost or a DNS alias of the listener. A non-loopback
             bind needs an explicit HTTPS origin and runtime TLS and token. The station is
             reached directly: no proxy remaps it. */
        doc /* The effective browser origin, the one readiness, GET /profile, the page and the
             Origin checks use, keeps an explicit alias rather than the numeric bind. */
        attribute 'bind' : String = "127.0.0.1:8080";
        attribute origin : String[0..1] = null;
    }
    attribute def ProfileDocument {
        doc /* profile.json: a UTF-8 JSON object of at most profileFileMaxBytes with exactly the
             keys schema_version, profile_id, revision, display_name, callsign, locator,
             endpoint, connection_type, audio, control and, for a managed radio, radio. The
             Settings fields stand flat in the object, not in a nested settings key. Malformed
             UTF-8 or JSON, a duplicate, unknown or missing key, a wrong type or a value outside
             its domain is refused. The document holds no TLS path, token, contact or
             recording. */
        doc /* profile_id is a lowercase hyphenated UUID v4 chosen at creation; neither the
             station nor the browser changes it, and an edit of it in the file is
             unsupported. */
        @FollowsSource { reference = "RFC 9562 section 5.4 (UUID version 4)"; }
        attribute schema_version : Integer = 1;
        attribute profile_id : String;
        attribute revision : Integer = 0;
        attribute settings : Settings;
        attribute endpoint : Endpoint;
        attribute connection_type : ConnectionType = ConnectionType::'standard';
        assert constraint supportedSchema { schema_version == 1 }
        assert constraint supportedBackend { connection_type == ConnectionType::'standard' }
        assert constraint safeRevision { revision >= 0 and revision <= maxRevision }
    }
    attribute def NativeProfileDocument {
        doc /* The profile of a native FlexRadio station (FR-023), chosen at creation: the keys
             of ProfileDocument with schema_version 2, connection_type native_flex and the
             required key native. Its audio selections are null, its control and PTT disabled,
             and it has no radio settings. Radio serial, slice index or letter, DAX channel,
             stream ID, client handle and tuning are never persisted. GET and PUT /profile
             keep their shapes, and the connection type is not editable. A binary that knows
             only schema 1 refuses it as unsupported_schema. */
        attribute schema_version : Integer = 2;
        attribute profile_id : String;
        attribute revision : Integer = 0;
        attribute settings : Settings;
        attribute endpoint : Endpoint;
        attribute connection_type : ConnectionType = ConnectionType::native_flex;
        attribute native : NativeIntent;
    }
    attribute def NativeIntent {
        doc /* The key native: client_id is a lowercase UUID v4 generated at creation, this
             station's GUI-client identity and not a radio identity; rx_antenna is 1..16
             uppercase letters, digits or underscore; radio_address, optional, is an IPv4
             address:port, a locator for a radio that discovery cannot reach, never an
             identity and never compared. */
        attribute client_id : String;
        attribute rx_antenna : String;
        attribute radio_address : String[0..1];
    }
    dependency nativePersistence from NativeProfileDocument to 'FR-023';

    item def HttpProfileGet :> WstxArchitecture::StationRequest {
        doc /* GET /profile. Over TLS it needs the selected profile's cookie
             (WstxStationProtocol::AuthenticateProfile). A supplied Origin is exact; an absent
             Origin is permitted for an ordinary same-origin GET. No CORS permission is
             given. */
    }
    item def HttpProfilePut :> WstxArchitecture::StationRequest {
        doc /* PUT /profile: a JSON body of at most profileHttpMaxBytes UTF-8 bytes with exactly
             these keys, Content-Type application/json with an optional UTF-8 charset. */
        attribute profile_id : String;
        attribute revision : Integer;
        attribute settings : Settings;
    }
    item def SaveProfile :> WstxArchitecture::ProfileRequest {
        doc /* The station forwards validated settings and revision to its own selected
             profile; a request never selects a directory. */
        attribute profile_id : String;
        attribute expectedRevision : Integer;
        attribute settings : Settings;
    }
    item def ProfileSnapshot :> WstxArchitecture::ProfileOutcome {
        doc /* The selected profile inside the station; the runtime inputs stay private. */
        attribute document : ProfileDocument;
    }
    item def HttpProfileRepresentation :> WstxArchitecture::StationOutcome {
        doc /* The 200 body of GET and PUT /profile with exactly these keys: application/json,
             Cache-Control no-store, at most profileHttpMaxBytes. endpoint is the effective
             browser origin, not the bind object. No path, secret, schema_version or internal
             object is exported. */
        attribute profile_id : String;
        attribute boot_id : String;
        attribute revision : Integer;
        attribute endpoint : String;
        attribute connection_type : ConnectionType;
        attribute settings : Settings;
    }
    item def HttpProfileError :> WstxArchitecture::StationOutcome {
        doc /* The error body {"error":{"code":<outcome>,"field":<field>}}; field is a dotted
             field name for invalid_settings where one applies, null otherwise. No value, path
             or exception is echoed. */
        attribute outcome : HttpOutcome;
        attribute field : String[0..1];
    }

    calc def PutDecision {
        doc /* The checks of a PUT in this order. authValid holds for trusted plaintext loopback
             or for exactly one expected cookie whose UUID and token verify. settingsValid
             judges the whole Settings object against every domain above; there is no partial
             edit. A transport body limit may answer 413 before this order. Every outcome
             but ok keeps the saved bytes, the revision and the settings. */
        @FollowsSource { reference = "RFC 9110 (status codes and Origin handling)"; }
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
            if bodyBytes > profileHttpMaxBytes ? HttpOutcome::request_too_large else
            if not settingsValid ? HttpOutcome::invalid_settings else
            if not profileMatches ? HttpOutcome::wrong_profile else
            if expectedRevision != currentRevision ? HttpOutcome::revision_conflict else
            if currentRevision == maxRevision ? HttpOutcome::revision_exhausted else
            if not durableReplaceSucceeded ? HttpOutcome::storage_unavailable else
            HttpOutcome::ok;
    }
    calc def ResponseBudgetAdmission {
        doc /* Before readiness, the launch encodes the complete HttpProfileRepresentation with
             the effective origin and the largest valid later settings and revision, not only
             the values in the file, and admits the profile only if it fits
             profileHttpMaxBytes. A refused profile gives invalid_profile; an admitted one
             keeps room for every valid later edit. The endpoint identity is never truncated
             or replaced. */
        doc /* The worst case with an empty origin is 2,018 bytes of compact UTF-8: 36-byte
             profile and boot UUIDs, revision maxRevision, standard, a display name of 64
             backslashes, callsign A12345678901, locator RR99XX99, both audio identifiers and
             the CAT endpoint of 256 backslashes each, CAT mode and PTT disabled. The escaped
             origin may therefore take 6,174 bytes. */
        in completeWorstCaseUtf8Bytes : Integer;
        return admitted : Boolean =
            completeWorstCaseUtf8Bytes >= 0 and completeWorstCaseUtf8Bytes <= profileHttpMaxBytes;
    }
    calc def GetDecision {
        in originAbsentOrExact : Boolean;
        in authValid : Boolean;
        return outcome : HttpOutcome = if not originAbsentOrExact ?
            HttpOutcome::forbidden_origin else if not authValid ?
            HttpOutcome::unauthorized else HttpOutcome::ok;
    }
    calc def HttpStatus {
        @FollowsSource { reference = "RFC 9110 section 15"; }
        in outcome : HttpOutcome;
        return status : Integer =
            if outcome == HttpOutcome::ok ? 200 else
            if outcome == HttpOutcome::forbidden_origin
                or outcome == HttpOutcome::wrong_profile ? 403 else
            if outcome == HttpOutcome::unauthorized ? 401 else
            if outcome == HttpOutcome::unsupported_media_type ? 415 else
            if outcome == HttpOutcome::request_too_large ? 413 else
            if outcome == HttpOutcome::invalid_settings ? 400 else
            if outcome == HttpOutcome::storage_unavailable ? 503 else 409;
    }
    metadata audioEndpointConflict : Conflict about HttpOutcome, HttpStatus {
        what = "CL-044-05 states 400 audio_device_not_endpoint for PUT /profile; HttpOutcome "
            + "does not list it and HttpStatus maps an unlisted outcome to 409";
    }
    calc def NextRevision {
        in beforeRevision : Integer;
        in saveOutcome : HttpOutcome;
        return afterRevision : Integer = if saveOutcome == HttpOutcome::ok ?
            beforeRevision + 1 else beforeRevision;
    }

    action def CreateProfile {
        in directoryArgument : String;
        out createdDocument : ProfileDocument[0..1];
        out outcome : StartupOutcome;
        doc /* --create-profile <directory> is the sole command; a relative directory resolves
             from the working directory. The parent must exist and the target must not, also
             when it would be empty; the target is never overwritten. */
        doc /* Creation writes profile.json with the defaults of ProfileDocument, Settings,
             Endpoint, AudioSelection and ControlSelection, a fresh UUID v4 and revision 0, and
             exits created without a listener or a browser. */
        doc /* An unknown, duplicate or combined argument gives invalid_runtime_configuration;
             an existing target, an absent parent or a storage failure gives
             resource_unavailable. A launch never falls back to creation. */
    }
    action def LaunchSelectedProfile {
        in directoryArgument : String;
        in runtime : RuntimeInputs;
        out selected : ProfileDocument[0..1];
        out bootIdentity : String[0..1];
        out effectiveBrowserOrigin : String[0..1];
        out outcome : StartupOutcome;
        doc /* --profile <directory> resolves and canonicalizes the directory from the working
             directory. An unknown or duplicate argument, --create-profile beside it, or a
             present WSTX_BIND or WSTX_ORIGIN gives invalid_runtime_configuration. */
        doc /* A missing or unreadable directory or profile.json gives resource_unavailable. */
        doc /* Malformed UTF-8 or JSON, a duplicate, extra or missing key, a wrong type or
             domain, a file over profileFileMaxBytes, an invalid UUID, bind port 0 or 65536, a
             malformed origin or an origin port other than the bind port gives
             invalid_profile; so does a NativeProfileDocument with an explicit null or an
             unknown key. */
        doc /* A schema_version other than 1 and 2, or schema 2 without the key native, gives
             unsupported_schema; a schema 1 document naming native_flex gives
             unsupported_connection_type. */
        doc /* The profile is validated before any request is accepted. */
        doc /* The launch takes exclusive ownership of the directory and of the profile UUID for
             the account, held by the operating system for its lifetime: the same directory
             through any alias, or a copy of an owned UUID, gives profile_in_use; a denied lock
             gives resource_unavailable. */
        doc /* An incomplete TLS pair, TLS without token, a token without TLS, a token that is
             not 32..128 ASCII letters and digits, insecure or incomplete remote inputs, or a
             saved origin whose scheme differs from the runtime TLS gives
             invalid_runtime_configuration; an absent, unreadable or invalid certificate or key
             gives resource_unavailable. */
        doc /* ResponseBudgetAdmission runs for the effective origin before readiness. */
        doc /* An occupied port gives endpoint_in_use; another failure of an operating-system
             resource gives resource_unavailable. Each single fault gives exactly its
             outcome. */
        doc /* A refused launch exits nonzero without readiness, browser, attachment, file
             rewrite or disruption of another process. */
        doc /* Ready, the launch takes a fresh UUID v4 boot ID that is not persisted and reports
             the effective browser origin and the selected UUID and name, no secret; it opens
             no browser. Readiness comes within readinessDeadlineSeconds, and the number of
             profiles running at once has no fixed bound. */
        doc /* Without arguments the station keeps the environment mode of WstxStationProtocol
             and wstx.v1: GET and PUT /profile answer 404, and no profile is created, migrated
             or searched. */
    }
    action def SaveSelectedProfile {
        in request : SaveProfile;
        in beforeDocument : ProfileDocument;
        out afterDocument : ProfileDocument;
        out outcome : HttpOutcome;
        assert constraint identityStable { afterDocument.profile_id == beforeDocument.profile_id }
        assert constraint revisionEffect {
            afterDocument.revision == (if outcome == HttpOutcome::ok ?
                beforeDocument.revision + 1 else beforeDocument.revision)
        }
        assert constraint failedSettingsUnchanged {
            outcome != HttpOutcome::ok implies afterDocument.settings == beforeDocument.settings
        }
        doc /* The web adapter authenticates, checks the Origin and decodes the request; the
             station calls only its selected profile. */
        doc /* Saves are serialized: the expected revision is checked again with the
             whole-settings validation and the write. A competing stale writer neither merges
             nor overwrites. */
        doc /* The API edits no identity, endpoint or connection type. */
        doc /* The commit point is the replacement of profile.json. Before it the old bytes and
             revision stay authoritative, and a failure gives storage_unavailable with the old
             file, the old state in memory and the server available. After it the complete new
             document is authoritative with revision + 1, and only then is the save
             acknowledged with 200. */
        doc /* A GET during a save sees the complete old or the complete new revision. A lost
             response is resolved by a GET, never by an automatic replay. */
        doc /* A save never acknowledges a partial write, selects a path, activates a driver or
             merges silently. */
        doc /* A PUT to a native profile naming an audio device, CAT or PTT, or radio settings,
             gives invalid_settings with that field. */
    }
    action def RecoverOrStopProfile {
        in selected : ProfileDocument;
        out outcome : StartupOutcome;
        doc /* Stop releases the listener and the locks; a crash releases the operating-system
             ownership too. A marker file alone owns no directory and no UUID, so a killed
             process can start again. */
        doc /* A restart reads only profile.json: a leftover temporary file is ignored and never
             promoted. A missing, corrupt or future file fails without reset, rewrite or copy
             from another profile. */
        doc /* The operator restores a known complete copy while the profile is stopped, or
             creates a new profile. A write to the file by another program while it is owned is
             unsupported. An endpoint edited while stopped is validated at the next launch; an
             edit of the UUID is unsupported. */
        doc /* An acknowledged save survives a process restart and an ordered restart of the
             operating system; after a reboot the operator starts the profile. There is no
             automatic backup selection, migration, autostart or device discovery, and no
             guarantee against a hostile user or against arbitrary power or storage failure. */
        doc /* The other profiles' processes, settings and sessions stay usable: profiles share
             no lifecycle. */
    }

    state def ProfileLifecycle {
        doc /* The lifecycle of one selected profile process. starting runs
             LaunchSelectedProfile and saving runs SaveSelectedProfile; a save returns to
             running with the new or the old revision. Stop or crash releases ownership and
             listener; a refused launch never becomes ready. A crash during the replacement
             leaves the complete old or the complete new document. */
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
        transition started first starting
            if launchFinished and launchOutcome == StartupOutcome::ready then running;
        transition refused first starting
            if launchFinished and launchOutcome != StartupOutcome::ready then rejected;
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
    dependency launchOwner from launchProfile
        to WstxArchitecture::physicalStation::backend::stations::profile;
    dependency saveOwner from saveProfile
        to WstxArchitecture::physicalStation::backend::stations::profile;
    dependency stationValidationOwner from saveProfile
        to WstxArchitecture::physicalStation::backend::stations::station;
    dependency createOwner from createProfile to WstxArchitecture::PersistedProfile;
    dependency lifecycleOwner from stopOrRecover
        to WstxArchitecture::physicalStation::backend::stations;
    dependency internalRequestRefinement from SaveProfile to WstxArchitecture::ProfileRequest;
    dependency externalRequestRefinement from HttpProfilePut
        to WstxArchitecture::StationRequest;
    satisfy 'CL-005-01' by launchProfile;
    satisfy 'CL-005-02' by saveProfile;
    satisfy 'CL-005-04' by launchProfile;

    requirement 'CL-005-01' {
        doc /* Each selected profile MUST own exactly one station process and listener, and the
             number of profiles running at once MUST have no fixed limit. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_005_01_to_FR_022 from 'CL-005-01' to 'FR-022';
    requirement 'CL-005-04' {
        doc /* Launch and save MUST end with an explicit StartupOutcome or HttpOutcome on
             contested ownership, invalid storage, an occupied endpoint or an unavailable
             resource, without replacing the saved configuration or disrupting a running
             profile. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_005_04_to_FR_016 from 'CL-005-04' to 'FR-016';
    dependency CL_005_04_to_FR_021 from 'CL-005-04' to 'FR-021';
    dependency CL_005_04_to_FR_022 from 'CL-005-04' to 'FR-022';
    requirement 'CL-005-05' {
        doc /* The profile MUST persist its audio and control selections independently of each
             other, with standard audio and CAT and PTT disabled by default and without
             claiming that a device is available; a native FlexRadio profile MUST be a
             NativeProfileDocument chosen at creation. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/profile.rs; client/app.js"; }
    }
    dependency CL_005_05_to_FR_001 from 'CL-005-05' to 'FR-001';
    dependency CL_005_05_to_FR_022 from 'CL-005-05' to 'FR-022';

    verification 'TC-022-002' {
        doc /* TC-022-002 — Persistence and independent restart
             Setup: four profiles from the fixture table, each in its own directory: UUID
             00000000-0000-4000-8000-00000000000i, Station i, TESTi, JN47AA, revision 0,
             standard, fixture-input-i and fixture-output-i, control disabled, null, disabled
             (i = 1..4). The operational windows are HTTPS with selected grants, with
             plaintext numeric loopback for compatibility. Test-build checkpoints sit on the
             real save path.
             (a) --create-profile writes exactly the defaults of ProfileDocument, Settings,
                 Endpoint, AudioSelection and ControlSelection, with a fresh UUID v4 and
                 revision 0, and opens no listener. An existing target, empty or not, or an
                 absent parent gives resource_unavailable.
             (b) Four acknowledged saves survive restart and kill, each with a fresh boot ID.
                 A leftover temporary file and a leftover marker are ignored. No restart of
                 the operating system is claimed.
             (c) A file of exactly profileFileMaxBytes loads; one byte more gives
                 invalid_profile. Malformed UTF-8 or JSON, a duplicate, unknown or missing
                 key, a bad UUID, or port 0 or 65536 gives invalid_profile; a missing file
                 gives resource_unavailable; schema 0, or schema 2 without native, gives
                 unsupported_schema; schema 1 naming native_flex gives
                 unsupported_connection_type. The file bytes stay unchanged in every case, and
                 the restored bytes launch again.
             (d) A denied write gives 503 storage_unavailable and keeps the old state. A crash
                 before or after the replacement leaves the complete old or the complete new
                 document.
             (e) A lost 200 reply: only one PUT is sent, a later GET returns the committed
                 revision, and Save stays disabled until an explicit reload; a failed reload
                 keeps it disabled. This browser condition is kept for the interaction it
                 proves.
             (f) The response budget, over numeric loopback with the saved origin as the
                 Origin header and no external DNS: the empty-origin worst case is 2,018
                 bytes; an origin sized to exactly profileHttpMaxBytes launches and the bodies
                 fit, including a save from maxRevision - 1 to maxRevision; one more origin
                 byte, or a 9,000-character hostname, gives invalid_profile before readiness
                 without a file rewrite.
             (g) A relative path from another working directory, aliases, invalid arguments,
                 and WSTX_BIND or WSTX_ORIGIN each give their mapped outcome.
             Oracle: independent expected fields and hashes, never the candidate's helpers.
             No power-loss durability or migration from WSJT-X is claimed.
             2 — Isolated automated tests; Windows PC, disposable storage, N real processes
             and windows. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-005-02';
            verify 'CL-005-04';
            verify 'CL-005-05';
            verify 'FR-001';
            verify 'FR-016';
            verify 'FR-022';
        }
        @TestedBy { test = "tests/profiles.test.cjs; server/src/profile_tests.rs"; }
    }
    verification 'TC-022-003' {
        doc /* TC-022-003 — Lifecycle, ownership and isolation
             Setup: four running profiles with valid inputs; each fault is applied alone, with
             otherwise valid TLS and token inputs.
             (a) Profile 1 stops and restarts while the other three refresh within
                 WstxOperatingLayout::loopbackRefreshDeadlineSeconds and stay unchanged.
                 Profile 1 returns with its UUID and revision and a new boot ID.
             (b) The same path, an alias or a copied UUID gives profile_in_use until the
                 owner exits, whatever the directory's name. An occupied port gives
                 endpoint_in_use.
             (c) Denied storage and an absent, unreadable or invalid TLS file give
                 resource_unavailable; incomplete TLS, an absent or malformed token, a remote
                 plaintext bind, an environment override or a runtime scheme mismatch gives
                 invalid_runtime_configuration; a malformed stored origin or a port mismatch
                 gives invalid_profile.
             (d) Each refusal exits non-zero within readinessDeadlineSeconds, with no
                 readiness, no file rewrite and no interruption of the other profiles. After
                 the fault is cleared, launch succeeds.
             (e) Killing the owner releases its lock. A marker alone holds nothing.
             Oracle: the mapped faults and independent hashes.
             2 — Isolated automated tests; Windows PC, N real processes and windows, port
             reservations and controlled resource faults, never exhaustion of the PC. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-005-03';
            verify 'CL-005-04';
            verify 'FR-021';
            verify 'FR-022';
        }
        @TestedBy { test = "tests/profiles.test.cjs; server/src/profile_tests.rs"; }
    }
    dependency CL_005_01_verified_by_TC_022_001 from 'CL-005-01' to 'TC-022-001';
    dependency CL_005_04_verified_by_TC_022_002 from 'CL-005-04' to 'TC-022-002';
    dependency CL_005_04_verified_by_TC_022_003 from 'CL-005-04' to 'TC-022-003';
    dependency CL_005_04_verified_by_TC_022_004 from 'CL-005-04' to 'TC-022-004';
    dependency CL_005_05_verified_by_TC_022_001 from 'CL-005-05' to 'TC-022-001';
    dependency CL_005_05_verified_by_TC_022_002 from 'CL-005-05' to 'TC-022-002';
}
