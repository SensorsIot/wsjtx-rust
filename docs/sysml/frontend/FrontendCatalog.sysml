package WstxRequirementsFrontend {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import WstxStationProtocol::'TC-051-001';
    private import WstxStationProtocol::'TC-051-003';
    private import WstxTransmit::'TC-092-005';
    requirement 'CL-010-16' {
        doc /* Present the laptop operating screen of WstxOperatingLayout::OperatingScreen: a top bar with only band, mode, dial, UTC/period, Logbook, Settings, HALT and Abort QSO (Esc); the full-width waterfall with the Rx/Tx strip; Band Activity with the strategy element and the QSO pane with direct buttons and no Enable Tx control; setup and diagnostics in the four-section Settings drawer; themes; WSJT-X keyboard shortcuts; and only the token form for an unauthorized browser. Details: OperatingScreen, RxTxStrip, BandActivityView, QsoPane, SettingsDrawer, ThemeChoice, UnauthorizedView, KeyboardShortcuts, WstxContact::SetEnableTx. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css; client/contact.js; client/logbook.js";
    }
    dependency CL_010_16_to_FR_010 from 'CL-010-16' to 'FR-010';
    dependency CL_010_16_to_FR_019 from 'CL-010-16' to 'FR-019';
    dependency CL_010_16_to_FR_021 from 'CL-010-16' to 'FR-021';
    requirement 'CL-010-06' {
        doc /* Present bounded Band Activity and, since #37, the compact QSO pane (WstxOperatingLayout::QsoPane: the running QSO's last partner message, its QSO dialogue and, below it, at most eight stations calling my call with time and SNR: during a QSO those within +/-50 Hz of my Rx or Tx offset, otherwise every caller, #37) in place of the Rx Frequency pane; local filtering, sorting, highlighting and clearing change no server decoding, contact state or log. Details: WstxOperatingLayout::QsoPane, QsoPaneCrowding. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js";
    }
    dependency CL_010_06_to_FR_004 from 'CL-010-06' to 'FR-004';
    dependency CL_010_06_to_FR_007 from 'CL-010-06' to 'FR-007';
    dependency CL_010_06_to_FR_021 from 'CL-010-06' to 'FR-021';
    dependency CL_010_06_verified_by_TC_007_003 from 'CL-010-06' to 'TC-007-003';
    dependency CL_010_16_verified_by_TC_007_009 from 'CL-010-16' to 'TC-007-009';
    dependency CL_037_03_verified_by_TC_007_009 from 'CL-037-03' to 'TC-007-009';
    dependency CL_073_01_verified_by_TC_022_006 from 'CL-073-01' to 'TC-022-006';
    // #73 the save reply is the save's outcome (operator 2026-11-08, candidate A).
    requirement 'CL-073-01' {
        doc /* (#73) Save outcome: the reply to the page's PUT /profile is the save's outcome. A 200 whose body is a valid ProfileRepresentation (the same checks as a GET /profile body) shows "Saved revision N" (N its revision) and is applied as the authoritative snapshot exactly like a GET: SnapshotApplicable, then a reload of the form, the edited revision and the shown profile (no newer same-boot snapshot is overwritten). A received 400, 409 or 503 shows its existing refusal text and state. No follow-up GET /profile is sent for the outcome, and no check of the socket, the authorization epoch or the displayed snapshot after the reply decides it: a control save (mode, endpoint, PTT) advances the CL-022 safety revision, so the server drops this page's transport and socket while the reply is on its way, and the page re-authorizes and reconnects by the existing rules without a token. "Save outcome unknown. Reload saved settings before retrying." with Save disabled until an explicit reload stays only for a save without a readable reply: network failure, the 10 s timeout, abort, an unreadable or invalid body, or a reply the authorization component discards because its headers arrived after a renewal began (accepted rare case). The server, the safety revision rule and every other caller of the authorization component are unchanged. Details: WstxOperatingLayout::PresentAndEditProfile, WstxOperatingLayout::BrowserSaveLifecycle. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/app.js";
    }
    dependency CL_073_01_to_FR_019 from 'CL-073-01' to 'FR-019';
    dependency CL_073_01_to_FR_022 from 'CL-073-01' to 'FR-022';
    verification 'TC-073-001' {
        doc /* TC-073-001 — Reproduction: Apply ⟳ of a CAT change reports the committed save
             CL-073-01
             Setup: actual candidate server on a disposable selected HTTPS profile (the TC-022-006 fixture: TLS localhost, token login, enrolled grant) and Chromium; control disabled at revision 0; request recorder for PUT /profile.
             Steps: connect; set CAT mode cat, endpoint fixture-cat-1, PTT disabled; press Apply ⟳; wait until the page is Connected again; read the result line, Save, the form, the shown revision, profile.json and the grant status scope.
             Expected (oracle: the contract above and the fixture's edit, not candidate output): exactly one PUT; the result line "Saved revision 1" and never "Save outcome unknown" at any time; profile.json revision 1 with control cat/fixture-cat-1/disabled; the scope's safety_revision advanced by 1 (the session-dropping path was taken); Connected again within 10 s with no token entry; Save enabled without Reload saved settings; the form shows fixture-cat-1 and the shown revision is 1. Red on the parent: "Save outcome unknown" and Save disabled.
             2 — Isolated automated browser test; Windows development PC, no radio, serial port or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/profiles.test.cjs";
        objective {
            verify 'CL-073-01';
        }
    }
    dependency CL_073_01_verified_by_TC_073_001 from 'CL-073-01' to 'TC-073-001';
    verification 'TC-073-002' {
        doc /* TC-073-002 — Received replies are known, missing replies stay unknown
             CL-073-01
             Setup: as TC-073-001; PUT /profile replies held, replaced or cut by a route fixture after the real server committed or refused them; a second window on the same profile.
             Steps (each from a fresh revision): (a) hold a committed display-name save's 200 reply, close the page's socket and let it reconnect, then release; (b) hold a committed 200 reply, announce the new revision so the page's background GET loads revision 1 first, then release; (c) hold a 409 reply (stale revision) across a socket reconnect, then release; (d) hold window A's committed revision-1 reply while window B saves revision 2 and A loads it, then release; (e) fetch a committed PUT and abort its delivery; (f) fulfil a committed PUT with status 200 and the body cut after 20 bytes; (g) with a body that is JSON but without revision; (h) hold the reply past 10 s.
             Expected (hand-written table): (a) and (b) "Saved revision 1", Save enabled, the form and shown revision 1; (c) the existing 409 text, Save disabled until reload, no "unknown"; (d) "Saved revision 1" while the shown revision stays 2 and the form is not overwritten; (e) to (h) "Save outcome unknown. Reload saved settings before retrying.", Save disabled, Refresh or a reconnect leave it disabled and an explicit reload enables it; exactly one PUT in every case (no replay); no GET /profile is sent for a save outcome in (a) to (d) beyond the socket's own initial read and the announced read. Red on the parent: (a), (b) and (d) unknown.
             2 — Isolated automated browser tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/profiles.test.cjs";
        objective {
            verify 'CL-073-01';
        }
    }
    dependency CL_073_01_verified_by_TC_073_002 from 'CL-073-01' to 'TC-073-002';
    verification 'TC-073-003' {
        doc /* TC-073-003 — Live Apply ⟳ of a CAT change on HB9BLA
             CL-073-01
             Setup: the gated candidate installed on HB9BLA, the operator's browser over HTTPS with its grant, IC-7300 on COM3; no transmission.
             Steps: note the shown revision R; in Settings > Radio change the CAT endpoint from COM3 to icom7300://COM3?baud=9600&radio=94&controller=e0 and press Apply ⟳; after the page is Connected again change it back to COM3 and press Apply ⟳; give the receive-only confirmation; change the display name and back with Apply ⟳.
             Expected (oracle: the shown revision before each save, the operator's look): each Apply ⟳ shows "Saved revision R+1", R+2, ... and never "Save outcome unknown"; after each CAT save the page is Connected again within 10 s with no token entry and Apply ⟳ is enabled without Reload saved settings; CAT shows waiting for the receive-only confirmation, then ready after it; the endpoint ends at the operator's COM3.
             4 — Live on the station, configuration change and back, no RF; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-073-01';
        }
    }
    dependency CL_073_01_verified_by_TC_073_003 from 'CL-073-01' to 'TC-073-003';
    dependency CL_037_02_verified_by_TC_092_005 from 'CL-037-02' to 'TC-092-005';
    requirement 'CL-057-03' {
        doc /* Band Activity shows only the latest even and the latest odd T/R period of the current receive identity (operator 2026-11-02, #37): the latest published period on top and, below a divider with its period UTC, the period it replaced when that one has the other parity; each period sorted by value or by the chosen column (ActivityOrdering, #55 CL-055-04); all decodes of a period; #39 highlight and #50 colours as before. When a new period arrives, the older period of the same parity disappears; a same-parity successor (a skipped period) or an uncorrelated period leaves only the latest. Older periods are neither kept, paged nor fetched: the browser reads only the latest view's records (the replaced period's rows are the ones it already has). The logbook and worked-before status are unaffected. After a page load or reload (for example the #51 reload after a station update) only the latest period is shown until the next period arrives, because the receive snapshot describes only the latest view; the previous period is not fetched back. A period in which this station transmitted is the exception of CL-061-03: it adds no block, and the period kept below it stays until a receive period replaces it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js";
    }
    dependency CL_057_03_to_FR_010 from 'CL-057-03' to 'FR-010';
    dependency CL_057_03_to_FR_019 from 'CL-057-03' to 'FR-019';
    verification 'TC-057-004' {
        doc /* TC-057-004 — Only the latest even and odd periods in Band Activity
             CL-057-03
             Setup: actual station Router and browser client with a scripted correlated FT8 receive snapshot and results route (explicit presentation fixtures, never modem truth).
             Steps: publish three consecutive periods 12:00:00, 12:00:15 and 12:00:30 UTC (3, 2 and 2 records), then 12:01:00 (one record, a skipped period); record every results read with the view current at that moment.
             Expected (independent: the scripted periods): after the second period, its rows on top and the 12:00:00 rows below one divider; after the third, only the 12:00:30 rows on top and the 12:00:15 rows below one divider (never more than two periods, the older same-parity period gone); after 12:01:00 only its row, no divider; no results read below the current view's first sequence; no page error.
             2 — Isolated automated browser test; Windows PC, no radio. Live acceptance: #37 items 1-2 on HB9BLA (FT8 and FT4). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_057_03_verified_by_TC_057_004 from 'CL-057-03' to 'TC-057-004';
    requirement 'CL-039-04' {
        doc /* The strategy element above Band Activity offers the strategy selector (None and the names, grouped Strategy and Contest), the editor and a Value sort control. While a strategy is active Band Activity marks what it ranks and lists rows by value from the station's verdicts, only after a new publication event; a column click overrides until Value is chosen again; colours stay per #50 (only interesting stations). The editor is a popup with its own HALT that keeps receive running, holds exactly the strategy settings as the nine decisions of CL-097-01 (a new strategy only as a duplicate), previews the unsaved draft against the latest period with the reason per decode, and applies on Save at once without selecting; selecting or saving never restarts receive. Details: WstxStrategy::ValueView, StrategySelector, StrategyEditor; WstxOperatingLayout::OperatingScreen. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_039_04_to_FR_010 from 'CL-039-04' to 'FR-010';
    dependency CL_039_04_to_FR_019 from 'CL-039-04' to 'FR-019';
    dependency CL_039_04_verified_by_TC_039_046 from 'CL-039-04' to 'TC-039-046';
    dependency CL_039_04_verified_by_TC_039_006 from 'CL-039-04' to 'TC-039-006';
    dependency CL_039_04_verified_by_TC_039_007 from 'CL-039-04' to 'TC-039-007';
    requirement 'CL-055-04' {
        doc /* Band Activity colours, hover text and order (operator 2026-11-03). Operator decision deviating from WSJT-X, which colours only CQ/QRZ and calling-me lines: the sender of every decoded message (CQ, replies to others, reports, R-reports, RR73, 73; the sender call of WstxContact::DecodedEntity) is coloured by the same new DXCC, continent, zone, grid and call flags (the whole row for a CQ or QRZ, only the sender's call otherwise, #50 CL-050-08); a message to my call keeps the calling-me colour on top; a row without a flag has no colour (there is no CQ slot, #50, and worked before never colours). Every row with a reason carries hover text (title and aria-description, on the row and its colour mark) naming each reason in value order (#50 CL-050-08 replaces this Band Activity hover by its one-line reason tip; the QSO pane callers keep it): calling me, the strategy verdict, each new flag with its entity, zone, grid or band, then the worked-before status, for example "New DXCC: Romania", "New DXCC on 40m", "New CQ zone 20", "New grid KN34", "New call", "Worked before on 40m FT8". Within each period the rows are sorted by value (1 calling me, 2 strategy hits by their rank, 3 new DXCC, 4 new DXCC on this band, 5 new CQ or ITU zone, 6 new grid, 7 new call, 8 no flag), then by SNR strongest first, ties in decode order; the column headers still choose another order and the DXCC header returns to it. Details: WstxOperatingLayout::BandActivityColours, BandActivityValue, BandActivityHover, ActivityOrdering. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/logbook.js";
    }
    dependency CL_055_04_to_FR_019 from 'CL-055-04' to 'FR-019';
    requirement 'CL-055-05' {
        doc /* Band Activity rows are tighter so more stations fit (operator 2026-11-03): less vertical padding and line height on decode rows and period dividers at the same font size, at most 24 px per row with a mouse; touch (coarse pointer) and the stacked narrow layout keep tappable rows. Details: WstxOperatingLayout::BandActivityView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.css";
    }
    dependency CL_055_05_to_FR_019 from 'CL-055-05' to 'FR-019';
    dependency CL_055_04_verified_by_TC_055_006 from 'CL-055-04' to 'TC-055-006';
    verification 'TC-055-007' {
        doc /* TC-055-007 — Dense Band Activity rows
             CL-055-05
             Setup: operating fixture at 1366x768 with a period of 30 routed decodes; Chromium.
             Steps: wait for the rows; measure a row, the font size and the rows fully visible in the table; read the coarse-pointer rule.
             Expected: a row at most 24 px high (41 px before), the font size unchanged (the normal operating font), at least 8 rows visible (5 before), and a pointer:coarse rule keeping at least 8 px cell padding; screenshot band-activity-density-1366.png (before and after on the issue).
             2 — Isolated automated (functional) tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_055_05_verified_by_TC_055_007 from 'CL-055-05' to 'TC-055-007';
    requirement 'CL-051-02' {
        doc /* A page whose build differs from the build in a station.status reloads itself once for that station build, keeping its browser storage (WstxStationProtocol::PageUpdate). The operating screen holds the reload while a contact or transmission is in progress, a popup is open or the Settings form has unsaved edits, and shows the "Station updated · reload" chip instead; the chip's click reloads. A second mismatch for a build the tab already reloaded for shows the chip and never loops. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/app.js; client/recording.js";
    }
    dependency CL_051_02_to_FR_021 from 'CL-051-02' to 'FR-021';
    requirement 'CL-051-03' {
        doc /* A receive snapshot, result page, operating selection snapshot, contact snapshot or waterfall frame of an unknown shape that the page rejects by its validation is never silent: the top bar shows the error chip "Station data not understood (<which>) · reload", whose click reloads the page; a later valid snapshot of that kind clears it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js";
    }
    dependency CL_051_03_to_FR_021 from 'CL-051-03' to 'FR-021';
    dependency CL_051_02_verified_by_TC_051_001 from 'CL-051-02' to 'TC-051-001';
    verification 'TC-051-002' {
        doc /* TC-051-002 — A held update and a rejected snapshot show the reload chip
             CL-051-02, CL-051-03
             Setup: actual candidate server and Chromium at 1366x768; routed contact snapshot with a contact calling CQ; the receive snapshot routed through, optionally with an unknown key dxcc; the proxy of TC-051-001.
             Steps: read receive with the unknown key, then without; the same for a result page, the operating selection snapshot and a contact snapshot; announce a spectrum.detail.frame of the current job with an unknown key; restart the station with build fedcba9876543210 while calling CQ; wait 1.5 s; click the chip; open a confirmation popup and reconnect to a status with another build.
             Expected: the error chip "Station data not understood (receive) · reload" in the error field, hidden again after the valid read; the same with (results), (selection) and (contact); (waterfall) for the frame; while calling CQ the warn chip "Station updated · reload" and no reload; the click reloads once and the reloaded page receives with no chip; with the popup open the chip and no reload; no page error.
             2 — Isolated automated functional tests; Windows development PC, loopback only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-051-02';
            verify 'CL-051-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_051_02_verified_by_TC_051_002 from 'CL-051-02' to 'TC-051-002';
    dependency CL_051_03_verified_by_TC_051_002 from 'CL-051-03' to 'TC-051-002';
    dependency CL_051_02_verified_by_TC_051_003 from 'CL-051-02' to 'TC-051-003';

    // #50 Operating screen operator feedback and #54 continuous WSJT-X-like waterfall (one CR, 2026-11-02).
    requirement 'CL-050-01' {
        doc /* The top bar shows UTC without a period bar; the period progress is the QSO pane's NEXT bar. The waterfall Rx and Tx markers are 3 px green and red lines without text labels, draggable. A waterfall click sets Tx (sent after 250 ms), a double-click sets Rx and Tx with one request; modifiers do not change the effect and a right-click sets nothing (WstxContact::PointerEffect). The help overview states this mapping. A double-click on a decoded Band Activity row selects the station and starts the reply, as Reply. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js; client/recording.css";
    }
    dependency CL_050_01_to_FR_007 from 'CL-050-01' to 'FR-007';
    dependency CL_050_01_to_FR_019 from 'CL-050-01' to 'FR-019';
    requirement 'CL-050-02' {
        doc /* Band Activity rows use the WSJT-X 3.3 default highlight colours and priority with its default on/off except as stated here (WstxOperatingLayout::BandActivityColours), with no text marks other than the a-priori marker aN after an a-priori word's message (#56 slice 5): My call from the message, the New call, New call on band, grid, DXCC, continent and zone slots from the record flags the station supplies (#55; a never-worked call carries both New call flags), for every decoded sender (operator decision, CL-055-04, not only CQ/QRZ lines as in WSJT-X; what a slot colours, whole row or the sender's call only, and the QSO partner's marker: CL-050-08); New call and New call on band are on by default (WSJT-X: off). Only stations of interest are coloured (operator 2026-11-03, deliberately unlike WSJT-X): there is no CQ slot, so a CQ from a station worked before on this band and mode, and every other row that carries no enabled slot, has no colour, while My call still applies. The slots are chosen per browser in Settings > General > Display. The #39 strategy highlight stays an accent and never replaces these colours. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/logbook.js; client/recording.css";
    }
    dependency CL_050_02_to_FR_019 from 'CL-050-02' to 'FR-019';
    requirement 'CL-054-02' {
        doc /* The waterfall colour follows a fixed dBFS mapping (WstxRecordingReceive::DisplayLevels): reference -85 dBFS, Sensitivity as WSJT-X Zero, a Range slider as WSJT-X Gain (default 50 dB), no automatic level and no reset on a new job, source or profile; optional Flatten across frequency. The spectrum line is a Settings option (default off) with a [E,0] dBFS scale that never clips; the default signal height is 330 px and the default speed 10 px/s, about two FT8 periods. All are per-browser settings that apply at once. Cells keep one native bin per column range, nearest-neighbour, without smoothing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    dependency CL_054_02_to_FR_019 from 'CL-054-02' to 'FR-019';
    verification 'TC-050-001' {
        doc /* TC-050-001 — Waterfall pointer, lines, top bar and double-click to call
             CL-050-01
             Setup: actual release candidate with the contact engine (contact_http_tests::contact_browser_operating_flow) and Chromium; the operating screen fixture of ui-operating with routed Band Activity rows.
             Steps: as TC-010-008; read the top bar and the QSO pane; double-click a CQ row and a row to my call.
             Expected: TC-010-008's #50 expectations; the top bar holds UTC only (one child, no period bar) and the QSO pane keeps #qso-progress; a row double-click sends select_row then enable_tx with the shown safety revision, one each; the help names "Waterfall click / double-click: Set Tx / Rx and Tx".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-01';
        }
        attribute executable : String = "tests/contact.test.cjs; tests/ui-operating.test.cjs";
    }
    dependency CL_050_01_verified_by_TC_050_001 from 'CL-050-01' to 'TC-050-001';
    verification 'TC-050-002' {
        doc /* TC-050-002 — WSJT-X Band Activity colours
             CL-050-02
             Setup: (a) actual candidate server; routed live job with CQ K1ABC (worked_this_band_and_mode), CQ W1XYZ, a report K9XX W2AB R-05 (both not_worked) and a free-text row; (b) the same server with routed records carrying the station's #55 flags and worked_status: CQ K1AA (no flag, worked_this_band_and_mode), CQ K2BB (new_call_band, worked_other_band_or_mode), CQ K3CC (new_call and new_call_band, not_worked) and HB9BLA K1AA R-05 to my call; Chromium.
             Steps: wait for the worked-before status of the rows; read row slots and backgrounds; turn New call off in Settings; append synthetic rows with slot sets for the #55 flags.
             Expected: no text marks; no CQ slot in Settings and no row slot cq; (a) the CQ W1XYZ row and the sender call of the non-CQ row K9XX W2AB R-05 (flags new_call, new_call_band; CL-055-04; only the call, CL-050-08) rgba(0,255,255,0.24) by default and rgba(153,255,255,0.2) with New call off; K1ABC (worked on this band and mode, no flag) and the free-text row no slot, background rgba(0,0,0,0); the choice saved in browser storage; priority My call > New continent > New DXCC, New grid and ITU zone off by default; (b) K1AA no slot and rgba(0,0,0,0); K2BB new_call_band, rgba(153,255,255,0.2); K3CC new_call and new_call_band, rgba(0,255,255,0.24); the row to my call from K1AA mycall only, rgba(255,102,102,0.32).
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_02_verified_by_TC_050_002 from 'CL-050-02' to 'TC-050-002';
    // #50/#37 CR 2 (operator 2026-11-02): period bar, QSO pane lines, QSO dialogue.
    requirement 'CL-050-03' {
        doc /* The QSO pane's period bar shows the elapsed part of the current period (15 s FT8, 7.5 s FT4) on the station's clock, the UTC the transmitter keys on including the #43 correction, never the browser's wall clock: the browser takes the largest offset of the station's utc_ms over its own monotonic time among the observations of the last 20 s and redraws at least every 100 ms without animation. An offset more than 500 ms below the estimate is a backward step of the station clock and restarts the estimate at once. The bar is red in a period of my Tx parity while Enable Tx is on and whenever the station reports transmitting, green in every other period. Details: WstxContact::OperatorDisplays StationPeriodClock, WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_050_03_to_FR_008 from 'CL-050-03' to 'FR-008';
    dependency CL_050_03_to_FR_019 from 'CL-050-03' to 'FR-019';
    requirement 'CL-050-05' {
        doc /* (#37) While an own CQ runs the QSO pane header reads "Calling CQ" with the Tx period; the message line reads "▶ TX now: <message>" with the seconds left while the station reports transmitting ("▶ TX now: Tune" with the Tune seconds left during Tune) and "▸ next: <message> · Tx in <n> s" otherwise; the Calling me section below the QSO dialogue lists only stations calling my call, one line per station with call, SNR, grid and country: every caller other than the partner on any frequency as soon as decoded, during a QSO ⚠ marking one within +/-50 Hz of my Rx or Tx offset and a double-click switching the contact with Enable Tx kept; an empty list shows the placeholder "Nobody is calling" (#37 2026-11-04, CL-037-04). Details: WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_050_05_to_FR_007 from 'CL-050-05' to 'FR-007';
    dependency CL_050_05_to_FR_019 from 'CL-050-05' to 'FR-019';
    verification 'TC-050-003' {
        doc /* TC-050-003 — Period bar colour and station clock
             CL-050-03
             Setup: actual candidate server and Chromium; the operating screen with a routed ContactSnapshot (Enable Tx on, own CQ, parity even) whose utc_ms is the browser's time plus a station offset; station.tick events dispatched to the page.
             Steps: read #qso-progress width and colour in an even and an odd station period, with transmitting true in the odd period, and after a 1 s backward step of the station clock; screenshots at 1366x768 and 360 px of a receive (green) and a transmit (red) period.
             Expected: the width is (station time mod period)/period within 4 percentage points, not the browser-clock phase, also right after the backward step; the even period (my Tx parity) and a transmitting period rgb(255, 64, 64), the odd receive period rgb(48, 208, 80); no width transition.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_03_verified_by_TC_050_003 from 'CL-050-03' to 'TC-050-003';
    verification 'TC-050-005' {
        doc /* TC-050-005 — QSO pane while calling CQ and transmitting (#37)
             CL-050-05
             Setup: actual candidate server and Chromium; routed ContactSnapshot of an own CQ with Enable Tx on; station.tick events dispatched to the page; routed live rows.
             Steps: (ui-operating TC-050-005) read the header after a receive refresh, the message line with transmitting true (4 s into my period), with a transmit view whose last_text of this period differs from the next message, during Tune, and with transmitting false at the next odd period start, and Calling me with no row; (ui-operating TC-007-009) Calling me idle and during a QSO with Rx 1500 Hz and Tx 2100 Hz, with callers of my call at 400, 1505 (the partner), 1530, 2130 and 1600 Hz and CQs near Rx, then with Rx and Tx at 2800 Hz; (contact.test TC-007-003) Calling me with a caller and CQs near Rx on the actual server; screenshots of calling CQ, TX now and between periods.
             Expected: header "Calling CQ" with "Tx even (1st)"; "▶ TX now:" "CQ HB9BLA JN47" with "10 s left", then "K1ABC HB9BLA -05" (the text on the air), "▶ TX now:" "Tune" with "80 s left"; "▸ next:" "CQ HB9BLA JN47" with "Tx in 15 s"; "Nobody is calling" for an empty list; idle every caller as a Calling me row "<caller> | <SNR> | <grid> | <country>" oldest first and no CQ; during the QSO every caller but the partner, the 1530 and 2130 Hz callers marked ⚠ ("SV1DZB ⚠"), none marked at 2800 Hz, and a double-click on any caller sends select_row replace true then enable_tx.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; tests/contact.test.cjs";
    }
    dependency CL_050_05_verified_by_TC_050_005 from 'CL-050-05' to 'TC-050-005';
    // #50 waterfall frequency mapping and Rx/Tx brackets (operator 2026-11-03 about 09:45).
    requirement 'CL-050-07' {
        doc /* The waterfall pointer, the Rx and Tx lines and the frequency axis share one mapping of the fixed 0..3000 Hz span onto the waterfall canvas's own box: a click, double-click or marker drag selects the frequency under the pointer, and the confirmed line and the axis tick of that frequency are drawn within 1 px of the pointer position, at every page width, display option (speed, Flatten, spectrum line) and devicePixelRatio. The Rx (green) and Tx (red) lines mark the lowest tone and each carries a WSJT-X bracket (goalpost) at the top of the waterfall over the occupied width to its right, 50 Hz in FT8 and 83.3 Hz in FT4, following the station's operating mode. Details: WstxOperatingLayout::RxTxStrip, WstxContact::PointerEffect. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js; client/recording.css";
    }
    dependency CL_050_07_to_FR_007 from 'CL-050-07' to 'FR-007';
    dependency CL_050_07_to_FR_019 from 'CL-050-07' to 'FR-019';
    verification 'TC-050-007' {
        doc /* TC-050-007 — Waterfall pointer, lines and axis on one frequency mapping; Rx/Tx brackets
             CL-050-07
             Setup: actual release candidate (fixture station) and Chromium with routed contact snapshots and recorded contact commands; station.tick delivered through the page's own listener.
             Steps: at 1366x768 double-click and click at the 500, 1500 and 2500 Hz axis ticks and drag the Tx line to the 2000 Hz tick, confirming each value in the contact snapshot; repeat at 900x700 and at 360x800, with Flatten and the spectrum line on, at speed 4 and with devicePixelRatio 2; read the bracket of each line in FT8 and after an FT4 tick.
             Expected: each request carries the tick's frequency within 2 Hz; each confirmed line's centre and each tick lie within 1 px of the pointer position; the bracket starts within 1 px of its line and is as wide as 50 Hz (FT8) or 83.3 Hz (FT4) on the mapping, within 1 px, green for Rx and red for Tx; a click inside a bracket still reaches the waterfall.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-07';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_07_verified_by_TC_050_007 from 'CL-050-07' to 'TC-050-007';
    // #50 operator design 2026-11-04 (refines the 2026-11-03 colour rule).
    requirement 'CL-050-08' {
        doc /* Band Activity marks each decoded row by what makes it interesting, highest first (WstxOperatingLayout::BandActivityScheme, BandActivityRowMark): (1) the current QSO partner, from the contact preparation until the contact is logged or cancelled, taken from the contact snapshot the page already holds (no further request): its rows are moved to the top of Band Activity with a red separator stripe below them and carry a red left bar, a "◆ QSO" badge after the message and a bold message, without a slot background; (2) a row to my call from another station (also <MYCALL> and a nonstandard i3=4 'to', #24): the whole row in the My call colour, also when the sender was worked before on this band and mode; (3) a CQ or QRZ from a station with an enabled new_* slot: the whole row in that slot's colour; (4) any other row from a station with an enabled new_* slot (in QSO with another station): only the sender's call is coloured, the rest of the row is plain; (5) everything else has no colour. The Settings slot choice applies to every mark. A row's reason tip is one compact line naming only the reasons of its colour that the row does not show, joined by " · ": per kind (continent, DXCC, zone, grid, call) the strongest enabled one, so an overall flag never also names its on-band form, the on-band call reason with the worked-before status in parentheses, then the strategy verdict, e.g. "New DXCC · New call", "New on 40m (worked on another band or mode)"; no country, continent, distance or "Calls you" (the row shows them); a row without such a reason has no tip. It uses only the #55 record data and the record's worked_status (WstxOperatingLayout::BandActivityHover). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/recording.css";
    }
    dependency CL_050_08_to_FR_019 from 'CL-050-08' to 'FR-019';
    verification 'TC-050-008' {
        doc /* TC-050-008 — Band Activity row marks: partner first with the stripe, calls me, CQ of interest, sender-only colour, one-line reason tip
             CL-050-08
             Kept status (#50, live 2026-11-06): a row with the tip "New on 20m (worked on another band or mode)" keeps that tip when the next period of the other parity moves it below the divider, while that period is partial and after it is complete, with no worked-before query.
             Setup: actual release candidate (fixture station) and Chromium at 1440x900; routed receive pages for a kept period 12:00:00 (CQ K1PT FN42 new_call_band; CQ K7OLD FN42; K9XX W1AA R-03) and a latest period 12:00:15 (HB9BLA K1PT FN42 new_call_band; HB9BLA K2CM -05; HB9BLA K3NB R-07 new_call_band; CQ OA4DX FH17 and K9XX YO3ABC -07 with new_dxcc, new_dxcc_band, new_call, new_call_band and dxcc Peru/Romania; CQ K1WB FN42; W9AA W2CD 73; CQ JA1ZZ PM95 new_cq_zone, new_cq_zone_band, CQ zone 25), selection band 40m, the records' worked_status (K2CM, K1WB and W2CD worked on 40m FT8, K3NB on another band or mode, the others not worked) and routed contact snapshots.
             Steps: with no contact read each row's marks, message cell and sender-call backgrounds and reason tip; hover the YO3ABC message, its DXCC cell and an uncoloured row; focus the K3NB row; route a contact with K1PT in replying and reload the snapshot; read the order, stripe and marker; read the stripe at 360x800; sort by Freq and back; turn My call and New call off in Settings; route the contact completed and reload.
             Expected: no contact: no stripe; the three rows to my call whole row rgba(255,102,102,0.32) with tips "New on 40m", none (worked on this band and mode, no flag) and "New on 40m (worked on another band or mode)"; CQ OA4DX whole row rgba(255,0,255,0.26) tip "New DXCC · New call"; K9XX YO3ABC -07 message cell transparent with only the YO3ABC span rgba(255,0,255,0.26) and the same tip; CQ JA1ZZ whole row rgba(255,191,0,0.26) tip "New CQ zone 25"; the rows without a flag uncoloured without a tip; no row has a native title and the aria-description equals the tip; the tip box is one line at the pointer, absent over the DXCC cell and over an uncoloured row, shown for the focused row and gone after focus moves. Prepared K1PT: HB9BLA K1PT FN42 then CQ K1PT FN42 first, then one stripe row (no text, rgb(255,64,64)), then the other rows in the earlier order with the kept divider; the partner rows have no slot background or tip, a 4 px rgb(255,64,64) inset left bar, a bold message and the badge " ◆ QSO"; at 360x800 the stripe is a 3 px full-width rgb(255,64,64) bar; the partner block stays first after the Freq sort. With My call and New call off: K2CM uncoloured, K3NB whole row rgba(153,255,255,0.2), the OA4DX and YO3ABC tips "New DXCC · New on 40m". Completed: no stripe and no partner row; HB9BLA K1PT FN42 is a calls-me row; no worked-before query, none added by the marks, the partner or the tip; no page error.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-08';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; tests/receive-page.test.cjs; server/src/receive_http_tests.rs";
    }
    dependency CL_050_08_verified_by_TC_050_008 from 'CL-050-08' to 'TC-050-008';
    verification 'TC-054-002' {
        doc /* TC-054-002 — Fixed level mapping, Zero/Gain sliders, Flatten and the spectrum line option
             CL-054-02
             Setup: actual candidate and Chromium at 1366x768; injected Detailed rows with known levels (noise q=40, a -40 dBFS carrier, a passband slope).
             Steps: read cells; move Sensitivity to +10 and Range to 30; reload; start a new job; turn Flatten and Show spectrum line on.
             Expected: E=-85 and span 50 by default (q=40 -> t=0.1, -40 dBFS -> t=0.9 by the palette anchors); g=+10 gives E=-95, R=30 the span 30; values survive a reload and a new job (no auto level, no reset); Flatten evens the slope across frequency within one palette step while the native readout is unchanged; the spectrum canvas is hidden by default and shown on request; signal height 330 px, speed 10 px/s.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-054-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_054_02_verified_by_TC_054_002 from 'CL-054-02' to 'TC-054-002';
    dependency CL_054_02_verified_by_TC_054_003 from 'CL-054-02' to 'TC-054-003';
    dependency CL_050_01_verified_by_TC_054_003 from 'CL-050-01' to 'TC-054-003';
    dependency CL_050_02_verified_by_TC_054_003 from 'CL-050-02' to 'TC-054-003';
    // #60 QSO pane dialogue as a table (operator 2026-11-03, final spec).
    requirement 'CL-060-01' {
        doc /* (#60) The QSO pane shows the QSO dialogue as a table with the header row "UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR", and, since #37 CL-037-04 (2026-11-04), the stations calling me in their own Calling me section, no longer rows of this table. UTC is the period start HH:MM:SS with no ◂/▸ mark after it. Direction is the two calls in the Band Activity order, recipient first and sender second, with "◂" between them pointing to the recipient ("HB9BLA ◂ CT1BFP" received from CT1BFP, "CT1BFP ◂ HB9BLA" sent by me; a hashed call as decoded); a CQ is "CQ <call>" or "CQ DX <call>" without an arrow and its grid is the Exchange. Exchange is the message after the two calls; a message that is neither (free text) is all Exchange. Rep is "×N" when the identical message repeated N > 1 times, else empty (operator 2026-11-03: its own column). On every dialogue row, received and sent alike (operator 2026-11-03), Rx SNR is our measured SNR, signed, of the latest received dialogue entry at or before that row, and Tx SNR is the latest report the partner sent us at or before that row ("R-02" gives "−2", a plain report "-05" gives "−5"); each is empty only while no such value exists yet. The table is the QSO section of the fixed-height pane (#37 CL-037-04): its header row and 12 rows without scrolling (6 at most 48em wide), more scrolling inside at its newest row; it does not grow the page (TC-007-009) and the table fits 360 CSS px, the titles abbreviated and the Direction calls wrapping at their spaces there. Details: WstxOperatingLayout::QsoPane items 7 and 8. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js";
    }
    dependency CL_060_01_to_FR_007 from 'CL-060-01' to 'FR-007';
    dependency CL_060_01_to_FR_019 from 'CL-060-01' to 'FR-019';
    verification 'TC-060-001' {
        doc /* TC-060-001 — QSO pane dialogue table
             CL-060-01
             Setup: actual candidate server and Chromium at 1366x768; routed ContactSnapshot of a running QSO of HB9BLA with CT1BFP whose dialogue holds a sent CQ, the operator's #60 example (received IM59 +8, sent +08, received R-02 +7, sent RR73, received 73 +9, here repeated twice with my call hashed and unknown) and a sent free text; routed live rows of callers of my call: DL1ABC JO31, an unknown hashed call with RR73, a known hashed call <PJ4/K1ABC> with the report -05, and EA8BIA IL18 near my Rx.
             Steps: read the header cells and every #qso-dialogue row's cells and the #37 Calling me rows idle and while the QSO runs, the page scroll, the header row and the newest row position, then at 360x800 the table and page widths; screenshots at 1366x768 and 360x800.
             Expected (independent oracle: the literal operator table of #60 and its 2026-11-03 Rep and every-row SNR requests): header UTC, Direction, Exchange, Rep, Rx SNR, Tx SNR; idle no dialogue row ("No QSO") and the callers in Calling me [DL1ABC, −8, JO31, ""], [<...>, −12, JO31, ""], [<PJ4/K1ABC>, −5, JO31, ""], [EA8BIA, 0, JO31, ""]; dialogue [22:51:00, CQ HB9BLA, JN37, "", "", ""], [22:51:15, HB9BLA ◂ CT1BFP, IM59, "", +8, ""], [22:51:30, CT1BFP ◂ HB9BLA, +08, "", +8, ""], [22:51:45, HB9BLA ◂ CT1BFP, R-02, "", +7, −2], [22:52:00, CT1BFP ◂ HB9BLA, RR73, "", +7, −2], [22:52:15, <...> ◂ CT1BFP, 73, ×2, +9, −2], [22:52:30, "", TNX 73 GL, "", +9, −2]; during the QSO the same callers in Calling me, EA8BIA as "EA8BIA ⚠", and none of them a row of the QSO table; no page scroll at 1366x768, the header row and the newest row visible; at 360 px no horizontal overflow and the table within the pane.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-060-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_060_01_verified_by_TC_060_001 from 'CL-060-01' to 'TC-060-001';

    // #61 An audio gap keeps the display (operator 2026-11-03; decision recorded on issue #61).
    requirement 'CL-061-01' {
        doc /* An unknown-loss source epoch inside the same receive does not clear the operator display, as in WSJT-X. The station keeps its contract (RadioIO: fresh source, job and generation, results from sequence 0); the browser recognises the epoch from GET /receive: the same profile and boot, a running job of the same mode on the same audio.device_id, audio.loss_epochs larger than before, no receive start/stop or band/mode change by this page within 15 s and an unchanged operating revision. Then Band Activity keeps the periods already shown (the latest and, of the other parity, the one before it) below a divider, and they stay until the new receive's first view arrives; that view keeps exactly the kept period one T/R period before it (CL-057-03), the others disappear. Results are then read only under the new identity, from its first sequence; a kept row stays bound to its old identity, so a selection of it is refused by the station as before (row_unavailable). The waterfall keeps its rows: they move in front of the new epoch's frame origin, with one gap row (RGB(96,96,96)) marking the epoch, and the new epoch's rows follow. The gap row marks the loss; the error field stays empty, a receive restart being informational and no entry (#37 CL-037-02, decision recorded on #61 and #37). Anything else that changes the receive identity clears both as before: a Stop/Start, a different input or mode, a band/mode change, a station restart (new boot) or a profile change. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js";
    }
    dependency CL_061_01_to_FR_019 from 'CL-061-01' to 'FR-019';
    verification 'TC-061-001' {
        doc /* TC-061-001 — An audio loss epoch keeps the waterfall and Band Activity
             CL-061-01
             Setup: actual station Router and browser client with a scripted correlated FT8 receive snapshot, results route and live Detailed waterfall frames (explicit presentation fixtures, never modem truth).
             Steps: publish the periods 12:00:00 and 12:00:15 (2 and 1 records) and four waterfall rows; then announce a loss epoch: new source, job and generation, loss_epochs 1, results from sequence 0; send two waterfall rows of the new epoch from sequence 0; publish 12:00:30 under the new identity; then a Stop/Start (new identity, loss_epochs 0) with one row.
             Expected (independent: the scripted periods and rows): after the epoch the 12:00:15 and 12:00:00 rows stay below their dividers and the six waterfall rows are the four old ones, one gap row and the two new ones in that order; the error field shows no entry for the epoch; after 12:00:30 its row is on top and the 12:00:15 rows below one divider, read with the new source, job and generation from cursor 0; after the Stop/Start Band Activity and the waterfall hold only the new receive's content. On the parent client the epoch clears both.
             2 — Isolated automated browser test; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_01_verified_by_TC_061_001 from 'CL-061-01' to 'TC-061-001';
    verification 'TC-061-002' {
        doc /* TC-061-002 — Audio gaps on HB9BLA keep the display
             CL-061-01
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 receive, one browser on the LAN; no transmission.
             Steps: watch the waterfall and Band Activity until GET /receive audio.loss_epochs has grown at least once.
             Expected: at each growth the waterfall keeps its history with one grey gap row and Band Activity keeps its periods; the error field shows no entry for it; a mode change still clears both.
             3 — Live, read-only on the station; with the operator at acceptance. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-01';
        }
    }
    dependency CL_061_01_verified_by_TC_061_002 from 'CL-061-01' to 'TC-061-002';
    // #37 lower panel below the compact QSO pane (operator 2026-11-03).
    requirement 'CL-037-01' {
        doc /* (#37) The right column of the workspace is one vertical stack at every width: the QSO pane, below it the Control panel and below that the error field, each with the left and right edges of the QSO pane card. The Control panel is always visible (no fold-out) and holds DX Call and DX Grid with Generate, Report, Auto Seq, Call 1st, Hold Tx and the Tx period Even / 1st or Odd / 2nd, laid out in rows across its width; each control sends the same single contact request as before and shows only the server-confirmed value. Tx1-Tx6 stay in the QSO pane fold-out; Rx/Tx and dial frequency stay under the waterfall and in the top bar; there is no level meter. The stack fits the fixed 1366x768 screen and 360 CSS px without horizontal overflow. Details: WstxOperatingLayout::LowerPanel, ControlPanel. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_01_to_FR_007 from 'CL-037-01' to 'FR-007';
    dependency CL_037_01_to_FR_019 from 'CL-037-01' to 'FR-019';
    requirement 'CL-037-02' {
        doc /* (#37) The error field, a small block below the Control panel that replaces the top-bar exception chips, lists only the problems that still apply and need the operator to act (CAT or radio, audio input missing or its level too low or too high, clock unsynchronized or unknown, a transmit refusal the operator must fix, a failed band/mode change, receive stopped, the station connection lost, a station update or rejected data), each with its cause and "since HH:MM" UTC, on one line where it fits. An entry disappears by itself when its condition clears; there is no acknowledge control and no history; transient events (a retried refusal, busy, stale revision, a receive restart) are no entries. With no entry it shows "No problems". A click opens the entry's detail as the chip did. Details: WstxOperatingLayout::ErrorField, ErrorFieldEntry. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_02_to_FR_019 from 'CL-037-02' to 'FR-019';
    requirement 'CL-037-03' {
        doc /* (#37, operator 2026-11-03 "We have two HALT buttons ...") The operating view shows one HALT, the QSO pane's; the top-bar HALT shows whenever the QSO pane HALT is not fully on screen (a page or the Settings drawer covers the workspace, or the stacked pane is scrolled out of view), so a pointer HALT is always on screen; Alt+H halts everywhere; Esc is Abort QSO. The QSO pane's direct buttons are CQ, Tune, HALT, Abort QSO (Esc) and Log QSO: RR73 and 73 are gone (Auto Seq sends them) and each Tx1-Tx6 line of the fold-out has Next and Now, Now choosing it next and turning Enable Tx on (from the next own period), disabled on a completed or cancelled contact. Reply is gone since the #50 double-click fix is installed: a double-click on a Band Activity or Others row, or the row menu Reply, starts the reply. Details: WstxOperatingLayout::OperatingScreen, QsoPane item 5. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_03_to_FR_008 from 'CL-037-03' to 'FR-008';
    dependency CL_037_03_to_FR_019 from 'CL-037-03' to 'FR-019';
    dependency CL_037_02_to_FR_021 from 'CL-037-02' to 'FR-021';
    verification 'TC-037-001' {
        doc /* TC-037-001 — Control panel below the QSO pane
             CL-037-01
             Setup: actual candidate server and Chromium at 1366x768, 1920x1080 and 360x800; routed ContactSnapshot of a running QSO.
             Steps: without opening the fold-out read the visibility of #dx-call, #dx-grid, #dx-generate, #contact-report, #contact-auto, #contact-call-first, #contact-hold and #contact-parity; read the bounding boxes of the QSO pane, #qso-control and #error-field; change each control and record the contact requests; check the fold-out holds the Tx1-Tx6 rows and no longer the moved controls, and the Rx/Tx strip holds no Hold Tx.
             Expected (oracle: the operator's #37 comments of 2026-11-03): every control visible with the fold-out closed and inside #qso-control; the three blocks stacked top to bottom (pane bottom <= control top, control bottom <= error-field top) with equal left and right edges (within 1 px) at all three sizes; the controls span at least 80% of the panel width at 1366x768 (rows, not a narrow column); Report 7 sends set_report {report 7}, Auto Seq off set_auto_seq false, Call 1st off set_call_first false, Hold Tx on set_hold_tx true, Odd / 2nd set_parity odd, DX Call W1AW with Enter sends enter_dx; no page scroll at 1366x768 and no horizontal overflow at 360 px; screenshots at 1366x768 and 360x800.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_01_verified_by_TC_037_001 from 'CL-037-01' to 'TC-037-001';
    verification 'TC-037-002' {
        doc /* TC-037-002 — Error field lists current problems only
             CL-037-02
             Setup: actual candidate server and Chromium at 1366x768 with a CAT profile; routed CAT status, contact snapshot transmit refusal and connection state.
             Long text (live 2026-11-06): with a CAT status text wrapping to several lines, and one far longer than the block, the block and its last entry can be scrolled fully into view on the 1366x768 screen, with no page scroll and the Control panel top unchanged; one wheel notch moves the block by at most its visible height; at 360x800 no horizontal overflow.
             Steps: healthy station; inject a CAT status not ready; then a transmit refusal radio_lost and a stale_revision-like transient refusal busy; then clear the CAT condition; then clear the refusal; then make the station link stale; read #error-field each time and the top bar.
             Expected (oracle: the operator's #37 correction "NO history"): healthy, the field shows "No problems" and no entry; the CAT entry names the CAT status and "since HH:MM" with the current UTC hour and minute; radio_lost adds "Tx refused · radio lost", busy adds nothing; after the CAT condition clears its entry is gone without any operator action and the refusal entry stays; after the refusal clears the field shows "No problems" again; with the link stale the field shows "Station connection lost · reconnecting"; the field has no acknowledge or dismiss control; the top bar holds no exception chips.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_02_verified_by_TC_037_002 from 'CL-037-02' to 'TC-037-002';
    requirement 'CL-065-02' {
        doc /* (#65, #82 operator 2026-11-09: "open slots are shown all the time as a part of the waterfall", "we just want to mark open slots, nothing else on screen") Open slot marks: always part of the waterfall, with no setting (#82 removes the Settings > Expert checkbox "Show free Tx slots") and with or without a run, a QSO or Auto: each open range [lo_hz, hi_hz) of the latest held free_tx_slots (CL-065-01) is a bar in the frequency ruler directly above the waterfall over lo to hi on the waterfall's one frequency mapping (CL-050-07), taking no pointer input. The held value is replaced by each free_tx_slots.state in socket order, by a GET /automation reply only with a later at_utc_ms (never by its null or an older value), and dropped at a new boot (#74) and when the page's display is switched to Off; the marks are redrawn on every new value and go when it is null or open is []. No request or poll beyond the snapshot and the event. Look (#76, operator 2026-11-08): each bar 8 CSS px high, shortened by 2 CSS px at each end (from x(lo) + 2 to x(hi) - 2), so touching ranges show a 4 px gap (where a range is narrower than both insets, on a phone, the bar may vanish); no text on the marks (no rank, no rise, no number); one pale green in the base theme, remapped by Day and Night like the page, whose drawn pixel differs in each theme from the drawn Rx line, Tx line and ruler background by at least 40 in the sum of the R, G and B differences. Details: WstxOperatingLayout::FreeTxSlotMarks. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/contact.js; client/recording.js; client/recording.css; client/app.js";
    }
    dependency CL_065_02_to_FR_019 from 'CL-065-02' to 'FR-019';
    verification 'TC-065-003' {
        doc /* TC-065-003 — Free Tx slots marks above the waterfall
             CL-065-02
             Setup: actual candidate server and Chromium at 1366x768, 1920x1080 and 360x800, also devicePixelRatio 2; routed automation snapshot with a run, announced by a pushed automation.state (the browser reads GET /automation only after it, #74), and pushed free_tx_slots.state events, FT8 and FT4.
             Steps: open Settings > Expert; with a value pushed and the checkbox off read #frequency-ruler; turn it on; push a value whose slots include FT8 2110 and 2160 Hz (exactly one width apart); in the Dark, Day and Night themes take a screenshot and read the pixel at each bar's centre, at the Rx line's and the Tx line's centre and at the ruler background beside the bars; push a newer value; an FT4 value with slots 90 Hz apart; one of another run_id; one with empty slots; route run null; reload and open a second browser context; click and double-click the waterfall at a mark's frequency and drag the Tx marker across a mark.
             Expected (oracle: CL-050-07 mapping, the operator's #65 and #76 answers): the checkbox "Show free Tx slots" off by default; no mark while off; on at 1366x768 and 1920x1080 (also devicePixelRatio 2): one bar per listed slot, each 8 CSS px high (within 0.5 px) at the bottom of the ruler, with left and right edges within 1 px of x(hz) + 2 and x(hz + width) - 2 (width 50 Hz FT8, 90 Hz FT4); the 2110 and 2160 Hz bars (and the FT4 pair) two bars with a gap of 4 px (within 1 px) between them; no text in the ruler's marks layer (no rank, no rise); in each theme the drawn bar pixel differs from the drawn Rx line, Tx line and ruler background pixel by at least 40 in the sum of the R, G and B differences; the waterfall top and height unchanged; redrawn on the newer value; none for another run_id, for empty slots and with run null; on after reload, off in the other context; the same set_frequency requests as without marks, Rx and Tx lines unchanged; no request after an event and no timer request; at 360x800 no bar is required, no horizontal overflow and no page error. Red on the parent: 4 px bars over the full slot (no gap between 2110 and 2160 Hz), labels in the ruler.
             #82: replaced by TC-082-004. No checkbox (always shown), no run and no run_id match, bars over open ranges [lo, hi) instead of listed slots; its test is rewritten to TC-082-004.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_065_02_verified_by_TC_065_003 from 'CL-065-02' to 'TC-065-003';
    dependency CL_065_02_verified_by_TC_065_004 from 'CL-065-02' to 'TC-065-004';
    verification 'TC-082-004' {
        doc /* TC-082-004 — Open slot marks always on the waterfall
             CL-065-02
             Setup: actual candidate server and Chromium at 1366x768, 1920x1080 and 360x800, also devicePixelRatio 2; pushed free_tx_slots.state events, FT8 and FT4; automation never used unless a step names a GET /automation reply (announced by automation.state, #74); the Dark, Day and Night themes.
             Steps: open Settings > Expert; push FT8 open [[300, 1000], [1050, 2700]]; push [[2110, 2160], [2160, 2210]]; FT4 [[300, 390], [390, 480]]; a newer value; open []; null; while a value is held a GET /automation reply with an older value, one with null, then one with a later value; an event that arrives before the contact client's script has loaded; a new boot; in each theme read the pixel at a bar's centre, at the Rx and Tx lines' centre and at the ruler background; click and double-click the waterfall at a mark and drag the Tx marker across it; an Off page.
             Expected (oracle: CL-050-07 mapping, the operator's #76 and #82 answers): no "Show free Tx slots" checkbox; one bar per range, 8 CSS px high (within 0.5 px) at the bottom of the ruler, edges within 1 px of x(lo) + 2 and x(hi) - 2; the touching ranges two bars with a 4 px gap (within 1 px), also FT4; no text in the marks layer; in each theme the bar pixel differs from the drawn Rx line, Tx line and ruler background by at least 40 in the sum of the R, G and B differences; the waterfall top and height unchanged; redrawn on the newer value; none for [] and for null; the older and the null GET reply leave the marks unchanged, the later one replaces them; the early event's marks drawn once the client has loaded, with no request; from the new boot on no mark of the old boot until the new boot's first event; the same set_frequency requests as without marks, Rx and Tx lines unchanged; no request after an event and no timer request; at 360x800 no horizontal overflow and no page error; the Off page no marks and no event. Red on the parent: no mark without a run, and none with the checkbox off by default.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_065_02_verified_by_TC_082_004 from 'CL-065-02' to 'TC-082-004';
    dependency CL_065_02_verified_by_TC_082_005 from 'CL-065-02' to 'TC-082-005';
    dependency CL_065_02_verified_by_TC_082_006 from 'CL-065-02' to 'TC-082-006';
    // #37 fixed-height QSO pane with a QSO and a Calling me section (operator 2026-11-04).
    requirement 'CL-037-04' {
        doc /* (#37, operator 2026-11-04: "The QSO panel should contain all needed information for the operator. And it should be fixed in size that the things below it do not move all the time up and down. We probably have a section for the QSO and a section for who is calling"; "you can make this section big enough to accommodate also longer QSOs. We have enough space") The QSO pane has a fixed height that depends on the screen only, never on its content, so the Control panel and the error field below it do not move when a QSO starts or ends, dialogue rows or callers are added or a message line appears. It has two sections of fixed height that scroll inside: QSO, below the header (partner call, grid, country, distance, reports) and the message lines (state, NEXT, last partner message), holds the #60 dialogue table with its header row and 12 rows without scrolling on a laptop screen (6 at most 48em wide), more rows scrolling inside with the newest row always visible, and the placeholder "No QSO" while no QSO runs; Calling me lists every station calling my call except the partner, one line per station with call, SNR, grid and country, at least 5 rows high, double-click (or Enter) to work it, with the #10 worked-before marks, and the placeholder "Nobody is calling". At 360 CSS px both sections stack with fixed heights, and Band Activity, with a fixed height, shows compact rows (numbers and distance, then message and country, wrapping only between whole fields, usually two lines) instead of labelled cards, at least six on screen at 360x800. The Calling me hover follows the compact #50 BandActivityHover rule (one line, only the enabled colour reasons, the strongest per kind). No new request or poll: the sections show the contact snapshot and the result rows the page already reads. Details: WstxOperatingLayout::QsoPane items 3, 7 and 8, BandActivityView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_04_to_FR_007 from 'CL-037-04' to 'FR-007';
    dependency CL_037_04_to_FR_019 from 'CL-037-04' to 'FR-019';
    verification 'TC-037-003' {
        doc /* TC-037-003 — Fixed-height QSO pane with QSO and Calling me sections
             CL-037-04
             Setup: actual candidate server and Chromium at 1366x768, then 1920x1080 and 360x800; routed live rows of one period with ten CQs, later joined by three callers of my call (a later publication announced by receive.state, #10) (DL1ABC JO31 Fed. Rep. of Germany at 600 Hz, IW9FRA JM68 Sicily, EA8BIA IL18 Canary Islands at 1520 Hz, near my Rx 1500 Hz); routed ContactSnapshots idle, of a running QSO with IW9FRA with 1, 12 and 15 dialogue entries, armed and disarmed, and completed.
             Steps: at each step read the top and height of the QSO pane, the QSO section, the Calling me section and the top of the Control panel (in the coordinates of the scrolled workspace), the section placeholders, the Calling me cells and whether the dialogue rows lie inside the QSO section; at 360x800 scroll the workspace to the first Band Activity row and count the rows fully on screen and their height; screenshots at each size.
             Expected (independent oracle: the operator's 2026-11-04 #37 design and the live finding 2026-11-04): idle "No QSO" and "Nobody is calling" shown; with the callers the Calling me header Calling me, SNR, Grid, Country and rows [DL1ABC, −8, JO31, Fed. Rep. of Germany], [IW9FRA, +17, JM68, Sicily], [EA8BIA, 0, IL18, Canary Islands]; during the QSO no "No QSO", the partner gone from Calling me and EA8BIA marked ⚠; 12 dialogue rows all inside the section without scrolling and the section on screen at 1366x768 and 1920x1080; 6 dialogue rows all inside the section without scrolling at 360x800 (live 2026-11-06, its header one row high); with 15 rows the section scrolls and the newest row is inside it; after completion "No QSO" again; at each size the Control panel top, the pane height and both section heights are the same at every step; Calling me holds its header and 5 rows; no page scroll at 1366x768 with the Control panel, the error field and the pane HALT on screen; at 360x800 no horizontal overflow, at least six Band Activity rows on screen, each at most 48 px high, and the newest dialogue row visible.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_04_verified_by_TC_037_003 from 'CL-037-04' to 'TC-037-003';
    // Found in the #61 gate (TC-050-004, CQ right after a completed contact refused stale_revision).
    requirement 'CL-061-02' {
        doc /* The QSO pane CQ button is an explicit operator choice like the double-click (CL-050-04): a stale_revision refusal of its enable_tx (the contact revision moves with every transmit step, also when the last period of a just completed contact ends) is retried at most twice with the reloaded snapshot; a third refusal stays shown. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js";
    }
    dependency CL_061_02_to_FR_007 from 'CL-061-02' to 'FR-007';
    verification 'TC-061-003' {
        doc /* TC-061-003 — CQ retries a stale_revision refusal
             CL-061-02
             Setup: actual station Router and browser client with scripted contact snapshots, contact command replies and contact.state events pushed through the station-message handler of the client, each carrying the moved revision, a snapshot_sequence one above the shown snapshot and its transmit, settings, contact, log and watchdog in changed (explicit presentation fixtures); Playwright page clock, paused once CQ is enabled.
             Steps: click CQ while the station refuses one command with stale_revision, moves its revision and sends no contact.state; once the refusal is shown, move the page clock by 2499 ms, then by 1 ms. Click CQ while it refuses three, sending a contact.state with the moved revision after each; after the third refusal, wait for revision 7 in the snapshot, then click Tune.
             Expected (independent: the scripted revisions, the contract wait of 2.5 s and limit of two retries): after 2499 ms no GET /contact and no second command; after 2500 ms one GET /contact and CQ sends enable_tx with revision 4 after revision 3 (accepted); then 4, 5, 6 and the refusal is shown; the next command is tune, with no fourth enable_tx. Every wait is on an event, with a 10 s hang guard (#83). On the parent client CQ sends once (#61).
             2 — Isolated automated browser test; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_02_verified_by_TC_061_003 from 'CL-061-02' to 'TC-061-003';
    // #61 operator report 2026-11-03: after each own transmission Band Activity looked as if reception had stopped.
    // Operator decision 2026-11-04 (#61): "distinguish exactly between TX and RX ... do not listen to audio when you do TX";
    // the station decides the Tx period (CL-061-04) and the browser renders its marker (CL-061-03).
    requirement 'CL-061-03' {
        doc /* Band Activity renders the station's Tx period marker (CL-061-04); the browser no longer infers it from station.tick or the contact snapshot. While the latest view is a Tx period (latest_decode.transmitted true) the header reads "Tx · <MODE> period <UTC> UTC · this station transmitted, no decode", the top row is one marker row (data-period "tx", text "Tx <UTC> · this station transmitted · no decode") and the receive period it replaced follows below its divider "<MODE> period <UTC> UTC" when it has the other parity (CL-057-03); there is no empty-period block ("No stations decoded") for it; the count is the number of rows shown below the marker. When the next period arrives the Tx marker disappears and the receive period kept below it stays below the new one with its divider (it replaces the Tx period, not the receive period before it). A receive period that decodes nothing keeps its note "No stations decoded" as before. The station's receive results and records are unchanged. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    dependency CL_061_03_to_FR_010 from 'CL-061-03' to 'FR-010';
    dependency CL_061_03_to_FR_019 from 'CL-061-03' to 'FR-019';
    verification 'TC-061-004' {
        doc /* TC-061-004 — A Tx period shows the station's Tx marker, no empty block
             CL-061-03
             Setup: actual station Router and browser client with a scripted correlated FT8 receive snapshot and results route (explicit presentation fixtures, never modem truth).
             Steps: publish 12:00:00 UTC with 3 records; publish 12:00:15 as a Tx period (latest_decode transmitted true, no records); publish 12:00:30 with 2 records; publish 12:00:45 (a receive period) with no records. No station.tick says transmitting.
             Expected (independent: the scripted periods and the marker): after 12:00:15 Band Activity shows the marker row "Tx 12:00:15 · this station transmitted · no decode" on top, then the divider "FT8 period 12:00:00 UTC" and the three 12:00:00 rows; no "No stations decoded" and no "No verified stations" text; header "Tx · FT8 period 12:00:15 UTC · this station transmitted, no decode"; count "3 messages"; after 12:00:30 its 2 rows on top and the 12:00:00 rows below the divider "FT8 period 12:00:00 UTC", no marker; after 12:00:45 the note "No stations decoded" with the 12:00:30 rows below their divider; no page error. On the parent client the 12:00:15 view is refused (unknown key) and no marker shows.
             2 — Isolated automated browser test; Windows PC, no radio. Live acceptance: TC-061-007. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_03_verified_by_TC_061_004 from 'CL-061-03' to 'TC-061-004';
    requirement 'CL-061-05' {
        doc /* A Tx period takes only a thin marker band in the waterfall (operator 2026-11-04 and 2026-11-06, #61: "the Tx area in the waterfall can be much shorter", "we still have a white band when the TX runs"). The browser collapses each run of consecutive rows the station marked tx (CL-061-04; it adds no polling and no new station data, #10 client-server rule) to one band of 4 CSS pixels in RGB(90,20,30), whatever the run's source time: while the station transmits the picture holds still once the band stands; receive rows keep the Speed scale. The time ruler stays exact: T at the top, no label inside a band, and a source time t beyond a band at floor((T-t)*p*H/C) less the collapsed source time of the bands above it, plus their height; the readout's projected source range over a band names the whole Tx run. A row the station did not deliver between two Tx rows at most 7.5 s apart is a Tx row of that band, never a grey gap stripe; a longer hole stays a gap. In the Day theme the signal canvases keep their colours: the waterfall's background stays dark and the Tx band dark red, never pale (the canvas counter-filter was overridden by #signal canvas{filter:none}, so the page's inversion turned both nearly white). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    dependency CL_061_05_to_FR_019 from 'CL-061-05' to 'FR-019';
    verification 'TC-061-008' {
        doc /* TC-061-008 — A Tx period is a thin band, the time axis stays exact, nothing pale
             CL-061-05
             Setup: actual station Router and browser client at 1366x1200 (device scale 1; a plot holding 20 s at 10 px/s, which the #37 default split at 1366x768 does not) with a scripted correlated live receive and Detailed frames, Speed 1 (10 CSS px/s) (explicit presentation fixtures).
             Steps: deliver 12 s of receive rows; one Tx row; the rest of a 15 s Tx period with two missing rows; 12 s of receive rows; read the canvas column and the time ruler; hover the band; set the Day theme and read the rendered page pixels; deliver Tx rows after a 7.4 s hole and after a 7.6 s hole.
             Expected (independent: computed from the 0.2 s rows and 10 px/s with y(s)=floor(s*10*H/C)): after the first Tx row the band covers rows 0-3 and the receive rows start at 4; the remaining Tx rows leave that picture unchanged; after the 12 s of receive the band covers rows y(12) to y(12)+3, receive rows above and below it and no grey row; labels 39.0 s at 0, 35.0 s at y(4), 30.0 s at y(9), then 10.0 s at y(14)+4, none of 25, 20, 15 s; the band's readout names the source range 12.0-27.000 s; the Day page pixels of the band are dark red; the 7.4 s hole is part of the band and the 7.6 s hole stays grey. On the parent client the Tx rows take 150 px, the labels ignore the band and the Day pixels are pale.
             2 — Isolated automated browser test; Windows PC, no radio. Live acceptance: TC-061-009. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_05_verified_by_TC_061_008 from 'CL-061-05' to 'TC-061-008';
    verification 'TC-061-009' {
        doc /* TC-061-009 — The Tx band on HB9BLA
             CL-061-05
             Setup: the installed station on HB9BLA, IC-7300, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), the operator's consent, the operator's browser in its usual theme.
             Steps: run a QSO with several Tx periods and look at the waterfall during and after them.
             Expected: each Tx period shows only a thin dark red band; no white or grey band appears while transmitting; the time labels below a band are the source times of those rows.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-05';
        }
    }
    dependency CL_061_05_verified_by_TC_061_009 from 'CL-061-05' to 'TC-061-009';
    // #96 full-screen button in the top bar (operator 2026-11-09).
    requirement 'CL-096-01' {
        doc /* (#96, operator 2026-11-09: "a botton top right where we can enable and disable the entire browser headers and only show our app"; "switch between normal browser mode and app mode should be left of ?") The top bar has a full-screen button immediately left of "?" (Logbook, Settings, full screen, "?", HALT), icon only (four corners outwards, inwards while full screen), labelled "Full screen" or "Leave full screen" with aria-pressed, titled "Full screen: hide the browser frame" or "Leave full screen", data-icon "expand" or "collapse". A press puts the whole page into the browser's full screen with the standard Fullscreen API (no tabs, address bar or toolbars; drawer, pages, popups and menus inside it), a further press leaves it; the button follows the browser's fullscreen state however it is left, and a refused request changes nothing and reports no error. Where the browser does not offer element full screen (Safari on iPhone) the button is not shown. While full screen Esc never aborts the QSO (operator: "lock esc. we do not need esc for abort, we have halt button or abort qso"): where the browser has Keyboard Lock (desktop Chrome and Edge) the Escape key is locked, so a short Esc only closes an open dialog or menu and otherwise does nothing, and holding Esc leaves full screen; elsewhere the browser's Esc leaves full screen; HALT, Abort QSO and Alt+H act as always, and outside full screen a first Esc press stays Abort QSO. Anywhere, an Escape keydown with event.repeat (the key held; Chrome leaves full screen while Esc is still down and the auto-repeat then reaches the page) never aborts. The "?" overview intro reads "... Alt+H always halts, Esc aborts the QSO (not in full screen).", its Esc / Abort QSO entry ends "Not in full screen.", and a "Full screen button" entry follows it ("Hide the browser frame and show only the app; press again to leave. Esc held: leave full screen."). No shortcut key; the button is reachable with Tab, Enter and Space. Each page load starts in the normal window and the choice is not stored. No station request, setting or storage; not shown in the unauthorized view; no page scroll at 1366x768 and no horizontal overflow at 360 CSS px in either state. Details: WstxOperatingLayout::FullScreenToggle, KeyboardShortcuts. */
        attribute implementation : String = "client/recording.js; client/contact.js; client/recording.css";
        attribute coverage : ImplementationState = ImplementationState::implemented;
    }
    dependency CL_096_01_to_FR_010 from 'CL-096-01' to 'FR-010';
    dependency CL_096_01_to_FR_019 from 'CL-096-01' to 'FR-019';
    verification 'TC-096-001' {
        doc /* TC-096-001 — Full-screen button in the browser
             CL-096-01
             Setup: actual candidate server and Chromium at 1366x768 and 360x800 with a retained authorization and a routed ContactSnapshot of a prepared contact (abortable); a request recorder on every station route; per variant an init script that, delegating to the real objects, records each call of navigator.keyboard.lock and unlock with its arguments, or deletes navigator.keyboard, or makes Document.fullscreenEnabled false, or makes Element.requestFullscreen reject.
             Steps: (a) read the top-bar buttons in order and the full-screen button's aria-label, aria-pressed, title and data-icon; click it; read document.fullscreenElement, the button and the lock calls; (b) press Escape (short keydown) while full screen with the prepared contact; read the requests, the contact and document.fullscreenElement; then open the Band Activity row menu and press Escape; read the menu; then leave full screen and press Escape; read the requests; (c) with the contact prepared again, enter full screen, call document.exitFullscreen() from the test (as the browser does on Esc held or its own control); read the button and the unlock call; then dispatch three Escape keydowns with repeat true (the held key's auto-repeat after the exit); read the requests and the contact; (d) Tab to the button, press Enter, then Space; (e) reload while full screen; (f) the variant without navigator.keyboard: click, read; with the prepared contact press Escape while full screen; read the requests; (g) the variant with fullscreenEnabled false; (h) the variant whose request rejects: click, read the page errors; (i) the unauthorized view (no retained authorization); (j) at 360x800 and 1366x768 read the page and top-bar scroll widths and the page scroll height, before and after entering full screen; (k) open "?" and read the Help region's intro text and its key entries (dt and dd) in order.
             Expected (oracle: the operator's request on #96 and the WHATWG Fullscreen Standard): (a) the order Logbook, Settings, full screen, "?", HALT; aria-label "Full screen", aria-pressed false, title "Full screen: hide the browser frame", data-icon "expand"; after the click document.fullscreenElement is document.documentElement, aria-label "Leave full screen", aria-pressed true, title "Leave full screen", data-icon "collapse", one lock call ["Escape"]; (b) in full screen no abort request, the contact still prepared and document.fullscreenElement still set; the menu closed by Escape; after leaving full screen Escape sends one abort request (unchanged Abort QSO); (c) aria-label "Full screen", aria-pressed false, title "Full screen: hide the browser frame", data-icon "expand", one unlock call; after the repeated Escape keydowns no abort request and the contact still prepared; (d) Enter enters and Space leaves full screen; (e) after the reload not full screen and the button off; (f) full screen entered, no lock call, no page error, and the Escape sends no abort request; (k) the intro "WSJT-X keys where the function exists. Letter keys and ? are inactive while a text field has focus; Alt+H always halts, Esc aborts the QSO (not in full screen)."; the entry "Esc / Abort QSO" with "Abort the QSO: the transmission stops now and the contact is cancelled (nothing logged); the station stays ready. Not in full screen." directly followed by "Full screen button" with "Hide the browser frame and show only the app; press again to leave. Esc held: leave full screen."; (g) no full-screen button and Settings directly followed by "?"; (h) not full screen, the button off, no page error and no ErrorField entry; (i) no full-screen button; (j) no horizontal overflow at 360 px and no page scroll at 1366x768 in both states; in (a) to (h) no station request caused by the button. Red on the parent: there is no full-screen button, every Escape keydown aborts (also a repeated one), and the overview lacks the full-screen texts.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-096-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_096_01_verified_by_TC_096_001 from 'CL-096-01' to 'TC-096-001';
    verification 'TC-096-002' {
        doc /* TC-096-002 — Live: full screen on the operator's browsers
             CL-096-01
             Setup: the gated candidate installed on HB9BLA; the operator's laptop with Chrome or Edge over the station link; an Android phone with Chrome; an iPhone with Safari if at hand. Receive only, Enable Tx off: no transmission.
             Steps: on the laptop press the full-screen button; open the Settings drawer, the Logbook and "?", and a Band Activity row menu; select a CQ row (a prepared contact, Enable Tx off) and press Esc briefly; hold Esc; enter again and leave with the button; press F5 while full screen. On the Android phone enter and leave with the button. On the iPhone look at the top bar.
             Expected: on the laptop the button left of "?"; no browser tabs, address bar or toolbars while full screen and the drawer, Logbook, overview and menu inside it; the short Esc leaves the prepared contact as it is and the page stays full screen; holding Esc shows the browser's notice and leaves full screen, the button then off, and the contact is still prepared after holding Esc; the button leaves full screen; after F5 the normal window with the button off; the waterfall keeps running throughout. On Android the browser frame goes and returns with the button. On the iPhone no full-screen button and no gap in the top bar. Screenshots on the issue.
             4 — Live on the station without RF; operator's browsers; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-096-01';
        }
    }
    dependency CL_096_01_verified_by_TC_096_002 from 'CL-096-01' to 'TC-096-002';
}
