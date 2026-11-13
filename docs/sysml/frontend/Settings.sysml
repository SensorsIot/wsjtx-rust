package WstxSettings {
    private import ScalarValues::*;
    private import WstxStationLink::DisplayProfile;
    private import WstxProfileAccess::HttpProfilePut;
    private import WstxProfileAccess::HttpProfileRepresentation;
    attribute def BrowserDisplayPreference {
        attribute effectiveOrigin : String;
        attribute profileUuid : String;
        attribute savedChoice : DisplayProfile[0..1];
        attribute effectiveChoice : DisplayProfile;
        attribute storageAvailable : Boolean;
        doc /* Browser-owned preference for one effective origin and validated saved-profile UUID.
             The browser storage boundary isolates origins; a versioned UUID key stores only
             off/thin/detail, never credentials, device identifiers, station settings or decoded traffic.
             Boot ID and revision do not alter identity. Environment-only/no-profile use is nonpersistent. */
    }
    action def RestoreDisplayChoice {
        in preference : BrowserDisplayPreference;
        out effectiveChoice : DisplayProfile;
        doc /* Use a valid saved choice if available. Otherwise Detailed on every origin,
             including remote HTTPS, using existing1024 native bins at2.9296875Hz. Invalid/missing values or
             unavailable storage use that normal default without disabling in-memory selection.
             Explicit choices survive reload/browser restart for this origin/profile only. */
    }
    action def SelectDisplayChoice {
        in explicitChoice : DisplayProfile;
        in preference : BrowserDisplayPreference;
        out updatedPreference : BrowserDisplayPreference;
        doc /* An explicit user selection changes effective and saved choice for this viewer only.
             If storage is unavailable, retain effective choice in memory without a persistence claim.
             Subscribe with existing off/thin/detail commands; do not change decoder/radio mode,
             source measurements, station settings or other viewers. Automatic server fallback changes
             effective choice only, never overwrites the explicit saved choice, and retains existing
             single Thin fallback/no retry loop. Detailed keeps fast-link/up-to10KiB/s notice and
             no32kbit/s promise; Thin retains all bandwidth limits. */
    }
    enum def ImportBrowserEvent {
        enum start; enum accepted; enum reservation_rejected; enum abort; enum response_lost;
        enum reconciled; enum terminal;
    }
    state def BrowserImportLifecycle {
        attribute acceptedEvent : ImportBrowserEvent;
        entry; then idle;
        state idle; state pending; state pendingCancel; state cleanupRequested; state uploading; state reconciling;
        transition begin first idle if acceptedEvent == ImportBrowserEvent::start then pending;
        transition reserved first pending if acceptedEvent == ImportBrowserEvent::accepted then uploading;
        transition cancelPending first pending if acceptedEvent == ImportBrowserEvent::abort then pendingCancel;
        transition cancelAcceptedReservation first pendingCancel if acceptedEvent == ImportBrowserEvent::accepted then cleanupRequested;
        transition cancelledReservationRejected first pendingCancel if acceptedEvent == ImportBrowserEvent::reservation_rejected then idle;
        transition cancelledReservationUnknown first pendingCancel if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition cleanupObserved first cleanupRequested if acceptedEvent == ImportBrowserEvent::terminal then reconciling;
        transition cleanupUnknown first cleanupRequested if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition reservationRejected first pending if acceptedEvent == ImportBrowserEvent::reservation_rejected then idle;
        transition reservationUnknown first pending if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition abortUpload first uploading if acceptedEvent == ImportBrowserEvent::abort then reconciling;
        transition uploadUnknown first uploading if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition observed first reconciling if acceptedEvent == ImportBrowserEvent::reconciled then idle;
        transition finished first uploading if acceptedEvent == ImportBrowserEvent::terminal then idle;
        doc /* contract 12.6: pendingCancel retains local cancellation intent while awaiting
             the reservation response. It never starts PUT. An accepted response gives
             the exact import ID: cleanupRequested sends DELETE for that returned ID,
             with zero PUT requests, then reconciles GET. Rejected responses end pending
             cancellation without PUT/DELETE. Lost reservation/cleanup responses enter
             reconciling; no cancellation success or cleanup is inferred. An unknown
             reservation ID is observed through GET, never guessed or automatically retried.
             UI abort during upload stops PUT and sends DELETE independently, then uses GET
             to reconcile uncertain outcome. A lost reservation response is reconciled from
             GET /recording, which exposes any accepted import ID. Never retry a mutation,
             resume upload, replay, or infer rollback from a missing response. reconciling
             persists on unavailable transport; no fabricated successful snapshot.
             A known reservation rejection ends local pending, visibly reports the returned
             error and starts no PUT/DELETE/retry; authoritative busy/degraded/identity state
             remains unchanged until an independently validated snapshot changes it.
             idle means no local upload, not permission to ignore authoritative busy state. */
    }
    attribute def SettingsDrawer {
        attribute sections : Integer = 4;
        attribute waterfallKeepsRunning : Boolean = true;
        attribute restartChangesApplyOnly : Boolean = true;
        attribute confirmRestartDuringQso : Boolean = true;
        assert constraint drawerRules { sections == 4 and waterfallKeepsRunning and restartChangesApplyOnly and confirmRestartDuringQso }
        doc /* Side drawer over the workspace (the waterfall keeps running; HALT stays
             reachable), opened by the top-bar Settings button or F2, closed by its close
             control or a pointer action outside it. Exactly four sections
             (SettingsSection):
             General: station (display name, callsign, locator, continent, #42 the
             ignore lists of WstxRankingControl::IgnoreLists: permanent calls, session expiry
             minutes, the session list with remove controls; #42 the Alerts section of
             WstxRankingControl::Alert: Sound and Browser notification checkboxes, both off by
             default, and the alert history newest first with Clear; #39 the Most Wanted
             section of WstxRankingControl::MostWantedList: status with the date and source attribution, and one button Update Most Wanted), clock
             (#43/#92 CL-043-01 a status line only, no source setting: the SNTP state,
             the Windows Time service state, the correction and the stations heard
             (median DT, how many above +0.1 s and below -0.1 s), the warning and its remedy, read with GET /clock when the drawer
             opens),
             display (theme Day/Dark/Night and its switch, waterfall display
             preferences), access and grants (log out, forget credential), MCP/automation,
             and "Monitor off at startup" (#45 CL-045-01: read with GET /receive/startup,
             saved on change with POST /receive/startup; it acts at the next station start
             and restarts nothing, so it carries no restart mark).
             Radio (restart): CAT (control, endpoint, PTT, receive-only confirmation),
             audio (one Audio section, #44 CL-044-08: input select with the Rx level meter,
             output select, both by endpoint name, and the radio's recommendation with
             Use IC-7300 audio), transmit (Tx watchdog
             minutes and Tune seconds as WSJT-X, power is set on the transceiver).
             Logging & Reporting: the existing log (Logbook page, ADIF), #10 "Update
             logbook from ADIF" (WstxLogbook::UpdateLogbook: an ADIF file input, the Update
             logbook button and the summary line), the WSJT-X UDP
             interface (WstxUdp, CL-040-02): the instance name as read-only text with no
             input (CL-112-01; "not fixed yet" while GET /udp shows null) and up to 16
             targets, each
             address:port, enabled, multicast TTL (the hop limit of an IPv6 group) and
             interface (an interface index for an IPv6 group, with a hint that an
             interface- or link-local group needs one; WstxUdp D6), the outbound message
             selection, with each target's status (active, schema, last send, error) and a
             note that the interface is send-only: programs listen and the station takes no
             command over UDP (operator 2026-11-06). GET /udp is read when the drawer opens (at
             most every 30 s, so routine drawer use stays inside the Thin budget), on the
             Logging tab and on Reload; Save sends one PUT /udp with expected_revision; it
             is a setting that restarts nothing (no restart mark). PSK Reporter: the read-only
             feed's switch and status (off; connecting; connected with the age of the last
             spot, or no spot yet; not connected with the error and retrying) from
             WstxStrategy::HearingFeed; plain setting, saved at once, never an error
             elsewhere on the screen.
             Expert: raw CAT readback, receive job/generation, timing, the explicit receive
             start/stop, the startup resume state of #45 (resume state and last receive
             choice from GET /receive/startup), the decode window diagnostics of #52 (Save
             FT8 decode windows and the latest window's counters, CL-052-01), selection
             refresh, connection details, the saved audio endpoint IDs (CL-044-08),
             recordings/replay and the
             raw transmit test panel (WstxTransmit, #9). (#82 removes #65's "Show free Tx
             slots": the open slots are always part of the waterfall, FreeTxSlotMarks.)
             Operative changes (display, theme, watchdogs) apply immediately and never
             interrupt decoding. Restart changes (the saved profile: station, CAT, audio,
             PTT) take effect only on Apply (the existing revision-aware profile save) and,
             while a QSO is active or the station transmits, only after a confirmation. */
    }

    attribute loopbackRefreshDeadlineSeconds : Integer = 2;
    attribute reconnectAfterDetectionDeadlineSeconds : Integer = 10;
    attribute silentLossDetectionSeconds : Integer = 13;
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
             For a selected persisted profile this operational browser flow uses the
             effective HTTPS origin and a current scoped grant/transport established by
             AuthenticateProfile/HandleScopedAuthorization. Trusted plaintext loopback
             GET/PUT compatibility remains the HttpProfileGet/PutDecision API contract;
             a plaintext selected profile reaches Connected only through the
             runtime-token operating contract of AuthenticateProfile, never a grant.
             Display full UUID/name/effective endpoint/boot UUID/revision with legacy
             radio/link/version; title contains display name and port. Before Connected
             require correlated status snapshot AND successful validated authenticated GET
             /profile on EACH new socket, before station-ready or optional display.
             After every await captured socket must remain current and OPEN before
             applying HTTP results; the one exception is the save reply below (CL-073-01).
             Established same-socket correlated status updates
             version/radio/Connected/updated and enables Refresh immediately, independent
             of settings HTTP. A status on an established socket reads no settings; a newer
             announced revision (WstxStationProtocol profile.state) reads them asynchronously:
             at most one GET in flight and one pending follow-up per socket; no mutation replay.
             Failed background GET visibly fails and marks socket stale. Old/disconnected
             results cannot restore Connected or mutate newer snapshots/forms.
             GET body exactly ProfileRepresentation, no-store JSON <=8192 bytes.
             GET absent Origin is valid; supplied wrong Origin 403, no CORS permission.
             Form edits whole Settings only, expected revision and selected profile_id.
             UUID/schema/endpoint/connection type/revision read-only. Standard selected;
             Native FlexRadio is shown as the saved read-only type of a native profile
             (NativeProfileDocument). All selections Saved; not activated;
             radio stays unconfigured; audio/control selection availability independent.
             PUT validates exact body shape/JSON/UTF8, media type/size before applying.
             Disable form controls while saving, preserving their read-only state;
             SaveSubmissionAllowed is the per-form submission guard. Refresh/profile
             GET completion must retain saving, conflict OR unknown outcome in Save's disabled state;
             a second submission during saving sends no second PUT. Restore editable
             controls after completion, while permanent read-only controls stay disabled.
             SnapshotApplicable rejects a lower revision from the same boot so a held
             GET cannot overwrite an acknowledged newer save/form. A changed boot
             permits authoritative restart/recovery resynchronization, including an
             independently restored lower revision.
             Invalid field preserves typed input with error, never Saved. Successful save
             updates revision only on durable 200. The PUT reply is the save's outcome
             (CL-073-01): a 200 whose body is a valid ProfileRepresentation shows Saved
             revision N and is applied as the authoritative snapshot exactly as a GET
             (SnapshotApplicable; a reload of the form and edited revision), with no
             follow-up GET and no socket, authorization or form-context check after
             the reply; a received 400/409/503 shows its refusal. The outcome is unknown
             only when no readable reply arrives (network failure, timeout, abort,
             unreadable or invalid body, or a reply the authorization component discards).
             On 409 prompt reload before another
             save. An unknown outcome also requires explicit reload before another save,
             without automatic PUT replay or an assumed rollback. A newer announced revision or a reconnect reloads authoritative settings; preserve in-progress
             edits until explicit reload or successful save. No settings polling/replay.
             Refresh fixture <=2 seconds unshaped loopback. Existing watchdog 12-second
             silence checked each second =>13-second detection (31 seconds while a deferred
             client download is pending, WstxOperatingLayout::BrowserLinkLifecycle); reconnect 1/2/4 seconds,
             snapshot+profile within 10 seconds after loss detection/restored link.
             Keep 12.3/12.4 existing bounds; no N-station thin-link guarantee is invented.
             Literal-text output, keyboard access/readability at desktop and 360px.
             HTTP error mappings are PutDecision/GetDecision/HttpStatus; unsupported
             methods 405 no mutation; environment-only GET/PUT return 404. */
        in authoritative : HttpProfileRepresentation;
        out edited : HttpProfilePut;
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
             leaves it set. No mutation replay. Known rejection shows error, not Saved.
             CL-073-01: success is a received 200 with a valid ProfileRepresentation body,
             also when the socket, the authorization or the displayed snapshot changed
             while it was in flight (a control save renews the authorization itself);
             a received 400 is rejected and a received 409 is conflict likewise.
             outcome_unknown is only a save without a readable reply. */
    }
    action presentAndEdit : PresentAndEditProfile;
    attribute browserSource : String = "client/index.html; client/app.js; client/style.css";
    dependency presentationOwner from presentAndEdit to WstxArchitecture::physicalStation::frontend::browsers;
    satisfy WstxProfiles::'CL-005-05' by presentAndEdit;
    satisfy WstxOperatingLayout::'CL-073-01' by presentAndEdit;

    package IndependentVerification {
        doc /* Case identities remain WstxRequirements::TC-022-001..005, projected
             from WstxRequirements and this package. No cases/verdicts are regenerated from
             action calculations. These declarations refine their subjects/oracles.
             Source/test companions retain delivered scoped profile/API/legacy-socket
             subsets, level 2 isolated automated Windows PC tests. The operational HTTPS/
             grant fixture conversion and complete dual-transport companions below remain
             pending; existing source is not complete automation of the expanded cases.
             The independently sized plaintext8192 response-budget companion remains
             implemented and mandatory; no existing companion or scoped evidence is discarded.
             FOUR real candidate processes, distinct saved ports/profiles, four real
             Chromium windows sharing ONE context/cookie store; no radio/device/live
             account/external-service/duplicate hosted run. Rust profile tests in
             server/src/profile_tests.rs and server/src/auth_tests.rs; communication browser/
             process cases in tests/profiles.test.cjs, registered beside the legacy suite.
             Case names are TC-022-001..005; run node --test --test-concurrency=1
             tests/profiles.test.cjs after cargo build --locked. Rust companions run with
             cargo test --workspace --locked --all-targets. Execution evidence remains
             on issue #5; model declarations are not run results.
             Fixture expects UUID 00000000-0000-4000-8000-00000000000i for i=1..4,
             Station i, TESTi, JN47AA, revision0, standard, fixture-input-i/output-i,
             disabled/null/disabled control. Ports reserved+recorded independently.
             Operational browser windows in TC-022-001/002/003/005 and their save/readiness
             regressions bind127.0.0.1 with saved HTTPS origins https://localhost:<port>
             and legitimate selected grants in the shared browser context. Initial
             selected-configuration identity migration creates no grant or commissioning;
             fresh setup follows AuthenticateProfile/HandleScopedAuthorization, and
             retained setup proves its existing grant without token/enrollment replay.
             Plaintext origin null =>http://127.0.0.1:<port> remains a separate HTTP/launch
             compatibility variant, never a claim of Connected or protected WS readiness.
             Preserve every API field/size/error/storage/startup variant: the full trusted
             numeric-loopback no-cookie GET/PUT matrix and current-grant HTTPS protected
             ordered checks are independently mandatory. The exact8192 response-budget
             fixture remains plaintext. Tokens independently generated, never logged.
             Auth setup cannot commission/open/query/set/close CAT/audio or key PTT.
             Hand-authored expected edit table and independently parsed JSON/file
             hashes are the oracle, NOT new code/model-produced golden outputs.
             Readiness <=10s, Refresh <=2s, recovery <=10s after detection/restored link.
             No fewer-than-four/zero-check pass; missing prerequisites fail. Variable-N
             implementation is reviewed to reject fixed four-entry arrays/assumptions;
             additional mandatory 1/6-server runtime repeats are not required. */
        verification variableServers {
            subject operation : PresentAndEditProfile;
            objective { verify WstxProfiles::'CL-005-01'; verify WstxProfiles::'CL-005-02'; verify WstxStationProtocol::'CL-005-03'; verify WstxProfiles::'CL-005-05'; }
            doc /* TC-022-001: operational HTTPS/grant setup and separate plaintext API
                 compatibility use the common partition above. Four PID/listener/boot-ID/
                 visible-UUID endpoints, Refresh all. Edit only profile1: Edited station 1,
                 changed-input-1, CAT endpoint
                 fixture-cat-1, CAT/disabled; retain output. Second window on same
                 station reloads acknowledged revision; other three settings/bytes stable.
                 Repeat audio-only/control-only/null-audio/CAT-disabled edits. Radio
                 stays unconfigured; no device opens; native disabled. Validate every
                 4.2 domain empty/max/one-beyond, types/duplicates/extra/missing keys,
                 malformed JSON/UTF8/enum/CAT/PTT, wrong UUID, stale/exhausted revision,
                 exact8192/8193 HTTP-byte bodies padded with whitespace and media type.
                 Valid boundaries persist; invalid leaves memory/disk/revision intact.
                 Two stale competing windows: one winner/one409, no merge.
                 Hold an announced revision's GET, start/hold PUT, then release GET: Save stays disabled,
                 repeated submit sends no second PUT. Release PUT, require one revision
                 increment and usable editable controls/Save, preserving read-only controls.
                 Inverse order on revision0 station: hold an old announced GET, complete PUT,
                 whose 200 reply is the revision1 snapshot (CL-073-01), then release old GET. Visible revision/form/name and
                 Saved1 feedback remain1; same-boot ordering does not reject changed boots.
                 Render <img src=x onerror=alert(1)> display name and
                 <script>alert(1)</script> audio ID literally, no element/dialog/script.
                 Desktop/360px identity/errors/Save readable and keyboard reachable.
                 Oracle: independent canonical domain table and independent fixture edits. */
        }
        verification statusReadiness {
            subject operation : PresentAndEditProfile;
            objective { verify WstxProfiles::'CL-005-02'; verify WstxStationProtocol::'CL-005-03'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-022-005, tests/profiles.test.cjs, level2 Windows real Chromium/server.
                 Use the common operational HTTPS/grant partition before each relevant
                 protected socket; count profile GETs separately from auth setup, never
                 substitute auth status for the correlated WS observation.
                 Established socket: Refresh reads no profile; an independent save announces the
                 revision and the browser reads once. Hold that GET; actual correlated WS response and
                 changed updated/enabled Refresh <=2s BEFORE HTTP release. Repeated
                 Refresh adds no GET; a second save while held starts no parallel read, and
                 one follow-up gets that newer revision and retains dirty input. Fresh socket: held initial GET
                 withholds Connected/station-ready/optional display until validated.
                 Close old socket with GET held, establish replacement, release old:
                 no reconnection or newer snapshot/form overwrite. Initial/background
                 GET failure visibly fails/stales, never successful configuration.
                 Oracle: WstxRequirements and this package, real WS and prepared revisions. */
        }
        dependency identity005 from statusReadiness to WstxProfiles::'TC-022-005';
        dependency identity001 from variableServers to WstxProfiles::'TC-022-001';
    }
    attribute def ValueView {
        doc /* While a strategy is active the browser renders the station's verdicts in Band
             Activity: after a new publication event (never on a timer) it asks POST
             /strategy/evaluate once for the shown sequences of the current live identity; rows
             arriving during an evaluation are asked for when it ends.
             A row with a rank has the existing strategy mark (colour stays per
             WstxBandActivity::BandActivityColours: only interesting stations); greyed rows
             are dimmed and struck through; other rows have no mark. With the sort on value (the
             default, the visible "Value" control in the strategy element) rows are ordered in
             their period block by ValueOrder: the partner rows stay on top (#50), rows to my
             call next, then rows with a rank by rank, then the rest in ActivityOrdering.
             Clicking a column header sorts by that column until the operator returns to Value
             (ActivityOrdering; the marks stay). No active strategy: no evaluation request and
             no mark. After an Ignore or Stop ignoring the shown rows are evaluated again.
             Selecting a strategy never restarts receive. */
    }
    attribute def StrategyEditor {
        doc /* The edit (pencil) popup (a modal dialog carrying its own HALT with the top-bar HALT's
             action and enabled state; receive keeps running): choose, duplicate and delete
             strategies (a new strategy is only a duplicate, "<name> copy", of a built-in or
             user strategy, keeping its class and contest; there is no blank "Add"); the list
             grouped Strategy, Contest (the two classes). Exactly the settings of Strategy, as the nine
             numbered decisions in order (D19, mockups of 2026-11-09):
             name and class (strategy or contest, shown, never switchable: a duplicate keeps it);
             1 Band: "All bands" or band checkboxes;
             2 Filters, as questions with answers: "What must be new?" (DXCC entity, Call, Grid,
             CQ zone (WAZ), ITU zone, Continent (WAC), Prefix (WPX) checkboxes); "New per" (Ever,
             Band, Band and mode); "New means" (Not worked, Not confirmed (QSL/LoTW)); "Region"
             (All, Other continents than mine, Selected continents with checkboxes); "Minimum SNR"
             (empty: none); "Worked since" (Any time, Today UTC, From/to UTC dates); "Treat 73 as
             CQ"; "Prefix/country" include and exclude lists (an entry: a prefix or a country name
             typed as free text, checked by the station on Save with a refusal shown at the entry;
             no picker, optional bands); "US state" include and exclude
             (state codes); "CQ target" include and exclude (words); the line "Callers of my call
             must pass these filters too". A contest strategy shows its contest (read-only) and
             only the three lists, under "Contest rules first, then:".
             3 Order: dropdown rows, one criterion each (add a row from the ValueCriterion names
             not yet listed, remove one, move one up or down; "the first decides, the next breaks
             a tie"; the line "then SNR" under the rows, not removable); a contest strategy shows
             "Ranked by the contest's rules" instead.
             4 "Calling stations are answered" (a checkbox, callers_first).
             5 "Leaving a station": After <n> calls without answer, <m> if he hears us | Until
             logged, leave when not decoded for <n> min | Contest style: while he hears us stay as
             long as he is the most valuable, else leave after <n> Tx changes.
             6 "Tx frequency": for each PSK case (He reports and hears us · He reports, does not
             hear us · He does not report) Stay | Move every call | Move every <n>-th call; the line
             "a move goes to a quiet slot, never onto a frequency he reports busy, never below 500
             Hz".
             7 "Busy pause: while he is in a QSO with another station keep calling on a split
             frequency and do not count".
             8 "CQ when idle, after <n> periods with nothing callable" (a checkbox, cq_when_idle,
             and a number 1..20, cq_wait_periods).
             9 "Retry pause (minutes)" before a left station is called again.
             Labels of the criteria: Most wanted (Club Log rank), New DXCC, New DXCC on band, New
             DXCC on band and mode, New call, New call on band, New grid, New grid on band, New CQ
             zone, New ITU zone, New continent, New prefix, SNR bucket (above 0, -10..0, below
             -10), SNR (stronger first), Distance (farthest first), Hears us first (PSK
             Reporter). A refused field is shown at its control with the station's reason. The
             live preview evaluates the
             unsaved draft against the latest period (POST /strategy/evaluate with explain,
             400 ms after an edit, one request per edit, no timer otherwise) and shows each
             decode's rank and why. Save sends one PUT /strategy, applies at once (also to the
             active strategy) and never selects a strategy. A built-in strategy is listed read-only with
             its settings shown and its preview; only Duplicate acts on it. With no user strategy the
             popup opens on the first built-in and Save stores none. My continent is set in
             Settings > General (StrategyConfiguration continent, saved by PUT /strategy). */
    }
    dependency editorRedesignClause from StrategyEditor to WstxContact::'CL-097-01';
    dependency valueViewClause from ValueView to WstxOperatingLayout::'CL-039-04';
    dependency editorClause from StrategyEditor to WstxOperatingLayout::'CL-039-04';
    attribute def ContestView {
        doc /* With a contest in force the browser renders the verdicts as WstxSettings::ValueView
             does, on the same events (a new publication, a save; never a timer). Band Activity lists
             only the rows with a rank, in rank order under the value sort; rows to my call and the
             partner rows stay (#50); every other row is hidden. Show all (a toggle in the strategy
             element, visible only with a contest, off at each page load, kept in the page only)
             shows them all again without a new request: a dupe and a greyed row dimmed, no colour; a
             row with a new multiplier has its own colour beside the strategy mark
             (WstxBandActivity::BandActivityColours: only interesting stations). The colour slots of the
             all-time log (new call, DXCC, zone, grid and LotW) are off while a contest is in force,
             their reasons leave the hover too, and they come back with its end: QSOs outside the
             period do not count (the My call slot stays; the Settings choice is unchanged). The hover names "#n",
             new multiplier and points, or the dupe. The status beside it: "Contest <name> \· <MM-DD
             HH:MM> to <MM-DD HH:MM> UTC \· <strategy name> \· Auto <on or off>" (Auto off is
             colouring only) and, once evaluated, " \· <n> QSOs \· <m>
             mult \· score <s>". Manual operation stays as it is: every row selects as ever, the
             double-click and the directive warning unchanged. */
    }
    dependency viewClause from ContestView to WstxContact::'CL-063-04';
}
