package WstxContact {
    private import ScalarValues::*;
    private import ModelBindings::RetiredCase;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::'FR-020';
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-011';
    private import WstxRequirements::'FR-024';
    private import WstxRequirements::'FR-006';
    private import WstxRequirements::'FR-019';
    private import WstxMessageEncode::'TC-006-002';
    private import WstxLogbook::'TC-007-008';
    private import WstxRequirements::'FR-010';
    private import WstxStandardQso::'TC-007-001';
    private import WstxStandardQso::'TC-007-004';
    private import WstxStandardQso::'TC-007-007';
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-012';
    private import WstxOperatingLayout::'CL-039-04';
    private import WstxTransmit::'CL-039-06';
    private import WstxOperatingLayout::'TC-055-006';
    private import WstxLogbook::'TC-110-004';
    private import WstxOperatingLayout::'CL-065-02';
    private import WstxOperatingChain::TxSlot;
    private import WstxOperatingChain::BusyPartner;
    private import WstxValueOrder::'CL-039-02';
    private import WstxValueOrder::'CL-039-03';
    private import WstxMostWanted::'CL-039-10';
    private import WstxValueOrder::'CL-042-01';
    private import WstxIgnoreLists::'CL-042-02';
    private import WstxAlert::'CL-042-04';
    private import WstxContestRanking::'CL-063-02';
    private import WstxContestRanking::'CL-063-04';
    private import WstxValueOrder::'CL-097-02';
    private import WstxValueOrder::'CL-097-03';
    doc /* Canonical contract of the standard FT8 contact (issue #10, CL-010-01..04, -06,
         -10..-14 in WstxRequirements): standard messages Tx1-Tx6, the server-owned
         auto-sequencing state machine, manual DX Call/Grid entry, Rx/Tx audio frequency
         selection including waterfall pointer actions, Rx Frequency pane routing,
         worked-before determination, the contact log and operator display items.
         Declared coverage is target; nothing here is an execution result.

         Ownership. WstxQsoPart::QsoAndLogging owns contact identity, the sequence
         state, next-message choice, completion and the per-profile log. It never keys
         PTT, opens audio or touches a radio. It consumes the TARGET #9 slice B consumer
         contract in WstxTransmit (TransmitArming, TransmitRequest, TransmitOutcome,
         HaltTransmit, SetTune) over the qso.transmit -> transmit.contacts connection of
         WstxArchitecture::StationProcess. #9 slice B owns the armed state, halt, PTT
         and pending-request replacement; TransmitService alone holds the station's
         explicit transmit authority (WstxRadioControlPart::RadioAuthority) and plans starts
         with WstxTransmitSchedule::PlanTransmitStart. #9 slice B is delivered (WstxTransmit
         transmit owner); the engine consumes it in-process, so a station with transmit
         capability and a current CL-022 grant can arm through Enable Tx.
         A receive-only station (no transmit capability) can still select rows, prepare
         contacts and log; every transmit action is then refused with
         transmit_unavailable. Wire contract: ContactWire below. The browser
         renders server-confirmed state and sends requests; it runs no sequence timer,
         modem or QSO state machine (#10 functional description).

         Behaviour reference: WSJT-X 3.3.0-beta5 source (C:/WSJT/wsjtx-3.3.0-beta5-src;
         WstxRequirements::BehaviorBaseline v3.3.0-beta4 is unchanged for these
         functions). Cited as MW = widgets/mainwindow.cpp, DMR =
         DecodedMessageReaction.cpp, DOP = DecodeOutputPlan.cpp, PL = widgets/plotter.cpp,
         CFG = Configuration.cpp, LQ = widgets/logqso.cpp, ADQ = logbook/AdifQso.cpp,
         WB = logbook/WorkedBefore.cpp, HT = HelpText.cpp. Operator decisions: issue #10
         comment 6539901776 (2026-10-31), items D1..D11. Deliberate differences are
         marked DIFFERENT with their reason.

         FT4 (#11 CL-011-02..04) reuses this contract unchanged except the rules marked
         FT4-NOTE: 7.5 s periods (WstxTransmitSchedule::Ft4Schedule), Tx4 always RR73 (MW
         ~11227 forces m_send_RR73 in FT4), ADIF MODE MFSK with SUBMODE FT4 (ADQ
         to_adif), Tx offset upper bound 2916 Hz (Ft4WaveformContract). Which mode a
         contact uses and what a mode change does: StationOperatingMode, ContactMode
         and ModeChange below (#11 slice B). */
    enum def Tx4Form { enum rrr; enum rr73; }
    attribute def ReportRange {
        attribute minimumDb : Integer = -50;
        attribute maximumDb : Integer = 49;
        attribute manualDefaultDb : Integer = -15;
        doc /* Report value domain -50..+49 dB: DecodedText::report() clamps the decoded SNR
             (Decoder/decodedtext.cpp ~271) and widgets/mainwindow.ui rptSpinBox has
             min -50, max 49, value -15. Rendering is sign plus at least two digits,
             asprintf("%+2.2d") (MW genStdMsgs ~9738): -05, +03, +00, -15, +49.
             The value after selecting a decoded row is round-half-away-from-zero of its
             snr_db, clamped to this range; a row with null SNR, and manual DX entry,
             use the current report value, initially manualDefaultDb. Once the current Tx2
             or Tx3 text of the active contact was sent, selecting its partner again keeps
             the report (WstxQsoControl::TxWatchdog). */
    }
    action def OverrideReport {
        in requestedReportDb : Integer;
        doc /* D7 adopted (rptSpinBox, MW genStdMsgs): the operator sets the report sent
             in Tx2/Tx3; -50..+49 accepted, other values refused with the range. The
             override applies to the next transmission. A later row selection for a
             new partner sets the report from that row again (DMR appendReactedTail
             ~388-400). RST_SENT logs the report actually transmitted last. */
    }

    // ---------------------------------------------------------------- contact
    enum def ContactOrigin { enum decodedRow; enum manualEntry; enum ownCq; }
    enum def SequenceStateName {
        enum idle; enum calling; enum replying; enum report; enum rogerReport;
        enum rogers; enum signoff; enum completed; enum cancelled;
    }
    attribute def Contact {
        attribute contactId : String;
        attribute origin : ContactOrigin;
        attribute dxCall : String[0..1];
        attribute dxGrid : String[0..1];
        attribute reportSentDb : Integer[0..1];
        attribute reportReceivedDb : Integer[0..1];
        attribute rxOffsetHz : Integer;
        attribute txOffsetHz : Integer;
        attribute holdTx : Boolean;
        attribute txParity : WstxPeriodTiming::PeriodParity;
        attribute nextSlot : TxSlot;
        attribute lastTransmittedText : String[0..1];
        attribute sequenceState : SequenceStateName;
        attribute armState : WstxTransmitControl::ArmState;
        attribute mode : WstxModeProcessing::Mode;
        attribute autoSequence : Boolean;
        attribute callFirst : Boolean;
        attribute startUtc : String[0..1];
        attribute endUtc : String[0..1];
        attribute saved : Boolean;
        doc /* Server-owned. contactId is a fresh lowercase UUID v4 created when a
             partner is prepared (row selection or manual entry) and kept through
             retries, reconnect, restart recovery and the log record
             (APP_WSTXRUST_CONTACT_ID). One active contact per station profile.
             A different partner while a contact is active (state replying..signoff)
             requires the explicit ChangeContact operation; a late row or stale request
             cannot change the transmitting partner. dxGrid is 4 or 6 Maidenhead
             characters or absent. nextSlot and lastTransmittedText are distinct and
             both shown. Reconnect loads this snapshot; it replays no arm, tune,
             next-message or transmit request. Another profile never inherits it.
             autoSequence is on at a profile's first start and afterwards as saved
             (CL-110-01, QsoSettingsFile); the operator can switch it off, and off means
             received messages never change nextSlot. callFirst (WSJT-X Call 1st /
             "CQ: First") is on at a profile's first start and afterwards as saved
             (CL-110-01, QsoSettingsFile), see CallFirst. Relation to WSJT-X 3.3.0-beta
             (widgets/mainwindow_settings.cpp). Followed: both settings are kept across
             starts, as WSJT-X keeps AutoSeq (group Common) and RespondCQ (group
             MainWindow) with its configuration. Deliberate difference: both are on when
             nothing is saved, where WSJT-X starts with AutoSeq false and RespondCQ None.
             Own choice: the value is saved with each accepted change, where WSJT-X
             writes its settings in writeSettings (at exit and at configuration changes),
             so that a change can be lost there when the program ends abnormally.
             armState is the
             read view of #9's TransmitArming, never armed by selection, entry, reconnect or startup (#10 CL-010-01,
             TransmitSafetyPolicy armedOnStartup=false). mode: ContactMode. */
    }
    attribute def ContactMode {
        doc /* #11 CL-011-03. A contact's mode is fixed when it is prepared: the selected
             row's mode (the live job that decoded it) or StationOperatingMode for
             manual entry and own CQ. All of its rules use that mode: messages
             (FT4-NOTE Tx4), TransmitSubmission requests (mode carried in every
             WstxOperatingChain::TransmitRequest, so #9 plans Ft4Schedule or Ft8Schedule and
             renders that waveform), period parity, TIME_ON/TIME_OFF period lengths, log
             MODE/SUBMODE and worked-before mode. Only decoded rows of the contact's
             mode count as received messages or for the 50 Hz rule; a row of the other
             mode never changes the sequence (cross-mode isolation). Re-preparing the
             same DX call in the other mode is a different contact (new contactId,
             ChangeContact rules). Each station process owns its own engine, transmit
             owner and contacts.adi, so simultaneous FT4 and FT8 stations share no
             contact, arm or log state. */
    }
    calc def FirstSlotOnSelection {
        in toIsMyCall : Boolean;
        in exchangeKind : String;
        in tx1Skipped : Boolean;
        return slot : TxSlot;
        doc /* DMR ~528-704. Row not addressed to me (CQ, or to another station): tx1
             (state replying), or tx2 (state report) when Tx1 is skipped. Row
             addressed to me: grid -> tx2/report; report -> tx3/rogerReport;
             R+report -> tx4/rogers; RRR or RR73 -> tx5/signoff; 73 -> tx5/signoff
             (logged once tx5 is sent, DirectLog). Responding to a station that answered
             my CQ is this case; CQ response mode (automatic choice of the responder)
             was #12 (D6): a reply to my CQ needs this explicit selection unless CallFirst
             answers it (#10, operator 2026-11-02, Call 1st on by default). */
    }

    // ---------------------------------------------------------------- sequencing
    enum def ReceivedKind {
        enum grid; enum signalReport; enum rogerReport; enum rogers; enum seventyThree;
        enum otherFromPartner; enum partnerToOtherStation;
    }
    enum def SequenceEvent {
        enum prepareReply; enum startCq; enum receivedFromPartner; enum transmittedSignoff;
        enum cancel; enum halt; enum watchdogExpired; enum partnerWorksOther; enum none;
    }

    // ---------------------------------------------------------------- frequencies
    enum def PointerAction {
        enum click; enum shiftClick; enum rightClick; enum ctrlClick;
        enum leftDoubleClick; enum rightDoubleClick;
    }
    calc def PointerEffect {
        in pointerAction : PointerAction;
        in pointerHz : Integer;
        doc /* D3 adopted (PL mouseReleaseEvent ~976, mouseDoubleClickEvent ~1012; MW
             setFreq4 ~12816). pointerAction and pointerHz: pointerHz is the waterfall/spectrum frequency under the
             pointer from the fixed 0..3000 Hz axis, rounded to integer Hz, by the waterfall's one
             frequency mapping (WstxSignalArea::RxTxStrip, CL-050-07) (the native/
             projected readout of WstxRecordingReceive is unchanged). #50 (CL-050-01, operator
             2026-11-02, replacing the #37 mapping): click -> Tx, sent after 250 ms so that a
             leftDoubleClick -> Rx and Tx sends only its one request; shiftClick and ctrlClick
             act as click; rightClick and rightDoubleClick set nothing (no context menu).
             No decode-at-point: the fixed full-band decoder always runs and the browser sends
             no redecode. Dragging the Rx or Tx marker sets that offset on release
             (WstxSignalArea::RxTxStrip). Explicit Tx pointer actions move Tx even with Hold Tx on, as
             WSJT-X setFreq4 (Hold Tx only stops implicit moves on selection).
             A Tx outside its domain is refused with the domain; Rx accepts 0..3000.
             Each is a server request; markers move only after confirmation, the
             pointer readout is local. Touch: tap = click; Tx/both use the labelled
             numeric inputs. No pointer action enables Tx. */
    }
    attribute def FrequencyControls {
        attribute rxOffsetHz : Integer;
        attribute txOffsetHz : Integer;
        attribute holdTx : Boolean;
        assert constraint rxDomain { rxOffsetHz >= 0 and rxOffsetHz <= 3000 }
        assert constraint txDomain { txOffsetHz >= 200 and txOffsetHz <= 2950 }
        doc /* Labelled numeric Rx Hz and Tx Hz inputs (MW RxFreqSpinBox/TxFreqSpinBox),
             Hold Tx (requested vs confirmed shown separately; on by default, CL-039-08). Tx<-Rx/Rx<-Tx copy
             buttons are not adopted (agent choice 2026-10-31: ctrl-click and the
             numeric inputs cover them); F11/F12 steps are not adopted (D7). FT4-NOTE Tx max 2916. */
    }

    // ---------------------------------------------------------------- Rx pane
    calc def RoutesToRxFrequencyPane {
        in rowFrequencyHz : Real;
        in rxOffsetHz : Integer;
        in firstCallIsMyCall : Boolean;
        in containsMyCallAndDxCall : Boolean;
        return routed : Boolean = firstCallIsMyCall or containsMyCallAndDxCall or
            (rowFrequencyHz >= rxOffsetHz - 10.0 and rowFrequencyHz <= rxOffsetHz + 10.0);
        doc /* #37 (2026-11-02): no browser pane shows the routed rows any more; the
             compact QSO pane (WstxQsoPane::QsoPane) shows the last partner message
             and at most two other stations instead. The completion and log rules below
             are unchanged. Earlier text:
             D2 adopted (DOP decideRouting ~391-441): a decoded row is shown in the Rx
             Frequency pane when its audio frequency is within +/-10 Hz inclusive of the
             confirmed Rx offset (FT8 and FT4 alike), or its first ('to') call equals
             the profile callsign exactly, or it contains my call followed by the DX
             call. It also stays in Band Activity. The station's own transmitted
             messages appear in the pane labelled Tx with their period UTC (CFG
             Tx2QSO default true; MW displayTransmittedText ~8151). The pane
             accumulates rows across periods in the browser from results it already
             receives (no extra request), newest last, at most 500 rows (own bound),
             with the same unread/resume-follow behaviour as Band Activity; it clears
             on profile change, mode/band change and Erase (local only). An Rx change
             affects only later routing. Selecting a pane row is SelectDecodedRow. */
    }

    // ---------------------------------------------------------------- wire contract
    enum def ContactRefusal {
        enum invalid_request; enum unsupported_version; enum unauthorized; enum forbidden_origin;
        enum wrong_profile; enum not_found; enum request_too_large; enum unsupported_media_type;
        enum state_conflict; enum stale_revision; enum busy; enum counter_exhausted;
        enum contact_active; enum no_contact; enum row_unavailable; enum row_not_standard;
        enum directive_not_answerable;
        enum invalid_call; enum invalid_grid; enum invalid_report; enum invalid_message;
        enum out_of_range; enum profile_incomplete; enum transmit_unavailable;
        enum redecode_unavailable; enum log_invalid_field; enum log_conflict;
        enum import_failed; enum storage_unavailable; enum snapshot_limit;
        enum tx_watchdog; enum operator_required; enum clock_not_synchronized;
    }

    dependency contactOwner from Contact to WstxQsoPart::QsoAndLogging;
    dependency busyPartnerClause from BusyPartner to WstxContact::'CL-097-06';
    requirement CompletedContactIdentity {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        doc /* QSO/logging owns stable completion identity, agreed fields and explicit
             persisted-versus-unsaved outcome. Replayed completion cannot silently
             create a second contact. Each profile owns contact storage; the browser,
             MCP and reconnect path cannot bypass station/transmit authority or another
             profile's storage. Exact fields/format/compatibility and duplicate/recovery
             behaviour are settled before this capability is implemented. */
    }
    dependency contactBoundary from CompletedContactIdentity to WstxRequirements::'FR-011';
    requirement 'CL-039-21' {
        doc /* A strategy or contest run never stops its own contact for the Tx watchdog; the leave rule bounds it instead (CL-039-23, CL-097-04), and while the target has not answered Tx moves by the Tx move rule per PSK case (CL-097-05); a target that has answered keeps its slot for the whole exchange. WD:n is the Tx watchdog only: the run's own contact shows the leave label instead (CL-097-04). Manual operation, a pounce and an MCP policy run keep the stop at N, and so does a run's CQ; unattended or past the run limit the stop at N is back at once. Details: WstxStrategy::StrategyWatchdog, TxMoveRule, HearingFeed, FreeTxSlot, LeaveCountLabel; WstxQsoControl::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/freeslot.rs; server/src/pskr.rs";
    }
    dependency CL_039_21_to_FR_007 from 'CL-039-21' to 'FR-007';
    dependency CL_039_21_to_FR_008 from 'CL-039-21' to 'FR-008';
    requirement 'CL-039-23' {
        doc /* Exit (operator grill 2026-11-07, Q6, Q7, Q13-Q16, Q19-Q28). A repetition is a fresh complete publication of the target's parity after an own transmission without progress; any message of the target to my call is progress, also a repeated one, except a selected caller repeating the message it was selected on. Both situations count alike: he repeats, because he does not hear us (decoded, a CQ again or another station), and we repeat, because we do not hear him (not decoded). The run leaves a station by the strategy's leave mode and gives it the retry pause (CL-097-04); a busy target's calls are paused (CL-097-06). Nothing changes before an exit criterion, even for a more valuable station; a caller of my call (in a contest only a non-dupe caller) is answered at once while the target has not answered, with Calling stations are answered on. A contest dupe caller never ends a stay. Details: WstxStrategy::LeaveRule, QuietTime, StrategyRun; WstxAutoControl::ContestRun. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; server/src/contest.rs; server/src/pskr.rs";
    }
    dependency CL_039_23_to_FR_007 from 'CL-039-23' to 'FR-007';
    dependency CL_039_23_to_FR_020 from 'CL-039-23' to 'FR-020';
    verification 'TC-039-022' {
        doc /* TC-039-022 — Tx moves at the repetitions of a target that does not hear us, and the run's own contact past the Tx watchdog
             CL-039-21
             Setup: the actual station router, contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz; Tx watchdog 2; a strategy run with Auto on, on 20 m, leave {calls 4, calls_heard 8} and tx_move_every {heard 0, not_heard 1, no_reports 1}, calling K1ABC (CQ at 1800 Hz) from Tx 1500; hand-authored waterfall rows whose quietest slot changes between periods.
             Steps: 4 repetitions with: no spot; a spot of my call to K1ABC 60 s old, 590 s old, 601 s old, on 40 m; the spot with Use PSK Reporter off; the spot with the feed off. The quietest slot moving 1400, 1300 between repetitions, and staying tied with the current one. The partner's report after the 2nd repetition, then silent periods. The engine alone: the run's own contact past the watchdog limit, then another contact; a run's CQ at the limit. Unattended (no client 60 s) and past the run limit with the spot: N 2 back at once, also without a publication. A refused move.
             Expected (hand-worked from WstxStrategy::FreeTxSlot): every repetition keyed while the run is attended, tx_expired false. The run's own contact shows no WD (tx_remaining_calls null) and the leave label counts the calls left, 4, 3, 2, 1, then the leaving; with the spot from 8 down to 1 (TC-097-013). No spot, 601 s, 40 m, Use off, feed off: Tx and Rx 1400 after the 1st, 1300 after the 2nd; a move never keeps the current slot, so a slot tied with it gives the next quietest (TC-097-010); slot_check hears_us false. Heard (60 s, 590 s): Tx stays 1500, hears_us true. After the partner's report Tx never moves again in that exchange. Engine: the run's own contact sends past N; another contact and the run's CQ stop at N (cause tx_watchdog). Unattended: the stop at N back, no further key, stopped no_client or run_limit. A refused move: unchanged, checked again at the next repetition. Manual stop at N: TC-008-001; a pounce stops at N: TC-039-005.
             #39 holdtx: these steps run with Hold Tx explicitly off (Tx and Rx move together); with Hold Tx on only Tx moves and Rx stays on 1800: TC-039-049.             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-21';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/contact_tests.rs; server/src/freeslot_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_039_21_verified_by_TC_039_022 from 'CL-039-21' to 'TC-039-022';
    dependency CL_039_23_verified_by_TC_039_043 from 'CL-039-23' to 'TC-039-043';
    dependency CL_039_23_verified_by_TC_039_044 from 'CL-039-23' to 'TC-039-044';
    dependency CL_039_21_verified_by_TC_039_047 from 'CL-039-21' to 'TC-039-047';
    dependency CL_039_23_verified_by_TC_039_047 from 'CL-039-23' to 'TC-039-047';
    dependency CL_039_23_verified_by_TC_039_048 from 'CL-039-23' to 'TC-039-048';
    dependency CL_039_21_verified_by_TC_039_049 from 'CL-039-21' to 'TC-039-049';
    dependency CL_039_21_verified_by_TC_039_051 from 'CL-039-21' to 'TC-039-051';
    // ---------------------------------------------------------------- #55 DXCC from cty.dat
    requirement 'CL-055-01' {
        doc /* The station resolves each call to its DXCC entity from AD1C's cty.dat exactly as WSJT-X does: exact =CALL entries, the longest matching prefix, operating suffixes (/P, /QRP, /M, a digit and the other WSJT-X suffixes), compound calls by their shorter side, /MM and /AM without entity, the KG4 rule, and the zone, position and continent overrides of the matching entry; names are shown in the WSJT-X short form with WAE entities shown as their DXCC. The cty.dat WSJT-X 3.3.0-beta5 ships (VER20250115) is bundled with its source and permission notice. Details: WstxCountryFile::CountryFile, EntityOfCall. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/dxcc.rs";
    }
    dependency CL_055_01_to_FR_011 from 'CL-055-01' to 'FR-011';
    verification 'TC-055-001' {
        doc /* TC-055-001 — Entity resolution known answers
             CL-055-01
             Setup: the bundled cty.dat; a hand-written file with every override kind; malformed files.
             Steps: effective prefix of WSJT-X's own test_radio_callsign vectors with "", /P, /QRP, /P/QRP; resolve HB9BLA, K1ABC, DL1XYZ, EA8ABC, HB9BLA/P, HB9BLA/QRP, W1AW/4, DL/HB9BLA, HB9BLA/DL, EA8/K1ABC, K1ABC/EA8, HB9BLA/MM, K1ABC/AM, KG4AB, KG4ABC, KG4AB/P, 3D2CR, 3D2CR/P, 3D2AG/P, W1AW/KG4, RA0DAA, RA0ABC, KG4IJS/0, IT9ABC, 4U1VIC, 2M0BDR, GB3LER, FO5ABC, UA3ABC, Q1ABC, a non-ASCII text; parse the override file and each malformed file (also CQ zone 41, ITU zone 91, an empty, a 41-character and a non-ASCII name).
             Expected (from the cited cty.dat lines and AD1CCty.cpp): Switzerland, U.S.A., Germany, Canary Is. with their zones; compound and suffixed calls by their effective prefix; /MM and /AM none; KG4 5 characters Guantanamo Bay, else U.S.A.; exact entries only for the whole call (3D2CR Conway Reef, 3D2CR/P Fiji, 3D2AG/P Rotuma Is.); zone overrides RA0 19/33, RA0A 18/32, KG4IJS/0 4/7; Sicily, Vienna Intl Ctr and Shetland shown as Italy, Austria, Scotland; the first entry of a duplicate key (GB3LER Scotland); version VER20250115, 346 entities; overrides applied; malformed files refused with their line.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-01';
        }
        attribute executable : String = "server/src/dxcc_tests.rs";
    }
    dependency CL_055_01_verified_by_TC_055_001 from 'CL-055-01' to 'TC-055-001';
    requirement 'CL-063-01' {
        doc /* The station holds one profile per contest from the official rules: WW Digi, ARRL Digi, ARRL Field Day, ARRL January, June and September VHF, IARU R1 50 MHz and 70 MHz MGM and FT8 Activity, usable everywhere in the world; a limit that depends on the location or the entry class is a note, not a refusal. Each profile holds the schedule rule, bands, modes, exchange, dupe, points and multiplier rules, the automation clause as the rules word it, notes and the source, as data, so that a new contest is one more entry. Its period is pre-computed from the schedule rule for the current or next occurrence; ARRL January VHF is not computed. GET /strategy/contests reads them. Details: WstxStrategies::ContestProfile, ScheduleRule, AutomationClause, ProfileTable, ContestHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/main.rs";
    }
    dependency CL_063_01_to_FR_024 from 'CL-063-01' to 'FR-024';
    verification 'TC-063-001' {
        doc /* TC-063-001 — The profile table
             CL-063-01
             Setup: the profile table as compiled; an expected table written by hand from the rule sources listed on #63.
             Steps: read id, activity, dupes, points, multipliers, automation clause, bands, Cabrillo mark and the notes of each profile.
             Expected: the nine ids in selector order; WW Digi bands 160 to 10 m, dupes per band, 1 + 1 per 3000 km, grid field per band, forbidden; ARRL Digi with 6 m, 1 + 1 per 500 km rounded up, no multiplier, forbidden; Field Day per band and mode class, forbidden, check-log note, Cabrillo unconfirmed; the three VHF per band and grid, grid per band, forbidden, W/VE note; Field Day and VHF with every ADIF band from 50 MHz (6 m, 5 m, 4 m, 2 m up to submm); IARU 6 m and 4 m, kilometres, grid per band, silent, 6 hours note; FT8 Activity 2 m, 70 cm, 23 cm, one per call, silent; no RTTY Roundup; no id twice.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_001_the_profile_table_holds_the_rule_facts";
    }
    dependency CL_063_01_verified_by_TC_063_001 from 'CL-063-01' to 'TC-063-001';
    verification 'TC-063-002' {
        doc /* TC-063-002 — The period from the schedule rule
             CL-063-01
             Setup: instants chosen by a calendar, not by the code.
             Steps: the current or next occurrence of each profile at 2026-01-01; WW Digi during and at the end of its period; WW Digi 2024 and ARRL Digi 2025 for the full-weekend edge; FT8 Activity at the start and between its rounds and across the year end.
             Expected: WW Digi 2026-08-29 12:00 to 08-30 12:00, ARRL Digi 2026-06-06 18:00 to 06-08 00:00, Field Day 2026-06-27 18:00 to 06-28 21:00, June VHF 2026-06-13 18:00 to 06-15 03:00, September VHF 2026-09-12 18:00 to 09-14 03:00, IARU 2026-04-18 and 2026-05-16 14:00 to 14:00, end exclusive; January VHF none; at the end the next year's 2027-08-28; 2024-08-24 and 2025-06-07; FT8 Activity 2026-11-04 2 m, 11-11 70 cm, 11-18 23 cm, 2027-01-06 2 m, 17:00 to 21:00.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_002_the_period_comes_from_the_rule";
    }
    dependency CL_063_01_verified_by_TC_063_002 from 'CL-063-01' to 'TC-063-002';
    verification 'TC-063-003' {
        doc /* TC-063-003 — GET /strategy/contests
             CL-063-01
             Setup: the pure list at 2026-08-01; the actual station router on a disposable selected HTTPS profile with one grant.
             Steps: the list; GET with the browser cookie, without credentials and with a query; POST.
             Expected: the nine ids in order, WW Digi with period {2026-08-29T12:00Z, 2026-08-30T12:00Z, band null}, its activity and rule names; January VHF period null; the route returns v 1, the profile id and the list with a period that has not ended; 401 unauthorized; 400 invalid_request; 405.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_003_the_list_names_each_profile_with_its_period; server/src/strategy_tests.rs::tc_063_003_the_contests_route";
    }
    dependency CL_063_01_verified_by_TC_063_003 from 'CL-063-01' to 'TC-063-003';
    verification 'TC-063-004' {
        doc /* TC-063-004 — The directive rule in a contest activity
             CL-063-02
             Setup: a hand table of activity, directive and answerable; the actual router with an injected FT8 live job for the selection.
             Steps: the table with EU and NA continents and with my continent unknown; the verdict of CQ WW K1ABC with and without the activity; the browser's select_row of that row in none and in ww_digi.
             Expected: TEST answerable in na_vhf and arrl_digi only, WW in ww_digi, FD in field_day, RU in rtty, not in another activity or hound; NA stays not answerable and EU answerable in an activity; greyed without the activity, rank 0 with it; 409 directive_not_answerable in none, accepted in ww_digi without directive_confirmed.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_004_the_directive_table_in_a_contest_activity; server/src/strategy_tests.rs::tc_063_004_a_selection_of_the_activitys_cq_needs_no_confirmation";
    }
    requirement 'CL-063-06' {
        doc /* The safety of a contest run stays on the server and is that of a strategy run: HALT from any source ends it and turns Auto off (the contest stays), Abort QSO (Esc) ends the QSO only, the Tx watchdog stops its CQ, with no client for 60 s or after 8 hours it starts nothing new, finishes the QSO in progress and its own CQ ends at once, only the browser's Auto on starts it, and a double-click is a manual intervention it resumes after. Details: WstxAutoControl::ContestRun, WstxAutoControl::StrategyRun, AutoToggle, ManualIntervention, WatchdogFromOperator. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs";
    }
    dependency CL_063_06_to_FR_024 from 'CL-063-06' to 'FR-024';
    dependency CL_063_06_to_FR_020 from 'CL-063-06' to 'FR-020';
    verification 'TC-063-011' {
        doc /* TC-063-011 — The safety of a contest run
             CL-063-06
             Setup: as TC-063-010, the run calling CQ with Auto on.
             Steps: an MCP configure with strategy true; a browser's replace selection of a CQ; Abort; HALT by route; Auto on, the clock past 8 hours; Auto on, every session gone and the clock past 60 s; Auto on, then Auto off, then Auto on; a watchdog limit of 2 with two CQs sent, the third period and a caller; Auto on, Enable Tx off, Auto off, Auto on.
             Expected: operator_required; manual with the operator's contact; after Abort calling_cq; halted, Auto off, the contest and its strategy kept, disarmed; run_limit and no_client, disarmed, Auto off, the contest selected with its strategy; stopped and disarmed at Auto off, calling_cq again with no CQ left behind; tx_watchdog, not keyed again, still disarmed with the caller, Auto off, the contest selected with its strategy; transmit_stopped, then calling_cq again.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-06';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_011_the_safety_of_a_contest_run_stays_on_the_server; server/src/strategy_tests.rs::tc_063_011_the_tx_watchdog_stops_a_run_on_a_silent_band";
    }
    dependency CL_063_06_verified_by_TC_063_011 from 'CL-063-06' to 'TC-063-011';
    requirement 'CL-097-05' {
        doc /* (#97 decision 6, operator #94 and #90) Tx frequency while a run calls a target that has not answered, per PSK Reporter case (he reports and hears us; he reports and does not hear us; he does not report or it is unknown): stay, move every call, or move every n-th call (a busy-paused call not counted). A move goes to another quiet slot (never the current one), never within 50 Hz of a frequency he reports decoding in my Tx parity (no fallback: with none left Tx stays and it is tried at the next call), never below 500 Hz; Hold Tx on moves Tx alone, off Rx and Tx together; after his answer Tx never moves in that exchange. Auto never chooses a slot below 500 Hz; the upper edge (a signal reaching above 2400 Hz) is allowed but loses every tie. The open-slot marks still mark from 300 Hz. Details: WstxStrategy::TxMoveRule, FreeTxSlot, HearingFeed, PskrUse. */
        attribute implementation : String = "server/src/automation.rs; server/src/freeslot.rs; server/src/pskr.rs";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_05_to_FR_007 from 'CL-097-05' to 'FR-007';
    dependency CL_097_05_to_FR_020 from 'CL-097-05' to 'FR-020';
    verification 'TC-097-006' {
        doc /* TC-097-006 — Country, US state and CQ target lists
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture; a hand log with STATE fields (W6ABC: a confirmed record STATE CA and a newer unconfirmed STATE NV); rows CQ POTA K1ABC FN42, CQ SOTA W7XYZ DN31, CQ DX JA1XYZ PM95, CQ EU DL1XYZ JO62, plain CQ W6ABC CM87, CQ VE3ABC FN03, an RTTY Roundup exchange of K1RU carrying MA, CQ K9NOR EN52 with no log record; a VK9 call and a call of Lord Howe Island; the station band 20m then 40m.
             Steps: countries include [prefix VK9]; include [country "Lord Howe Island"]; include [prefix DL, bands [40m]] on 20m and on 40m; exclude [country "United States"]; include [prefix W] with exclude [prefix W6]; a PUT with country "Atlantis"; states include [CA]; include [MA]; exclude [CA]; cq_targets include [POTA]; exclude [DX]; the built-in POTA/SOTA on the same rows with K1ABC also logged on 20m yesterday and W7XYZ logged on 20m today; the Band Activity rows and the alert history under POTA/SOTA and under another strategy (browser case with routed verdicts). The run's own select_row of CQ POTA and the directive refusals are TC-097-018's.
             Expected (hand-worked from WstxRankingControl::CountryList, UsStateFilter, UsStateOf, CqTargetList): prefix by the start of the call, country by the entity; the DL entry only on 40m; exclude wins over include; "Atlantis" refused 400 at its field path; CA for W6ABC (confirmed before newer unconfirmed), MA for K1RU from the exchange; K9NOR (unknown) and VE3ABC fail include and pass exclude; with include [POTA] only CQ POTA is ranked (answerable for the strategy although DirectedCqRule greys it), the plain CQ and CQ DX fail with why "CQ target"; exclude [DX] fails CQ DX only; POTA/SOTA ranks K1ABC (worked yesterday, new today; grey false) and not W7XYZ (worked today, "not new"), and nothing else of the rows; in Band Activity the CQ POTA row marked and not struck through under POTA/SOTA, struck through under the other strategy; one alert for K1ABC under POTA/SOTA. Red on the parent: the lists are refused.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-02';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    verification 'TC-097-010' {
        doc /* TC-097-010 — Tx moves per PSK case and Auto's slot choice
             CL-097-05
             Setup: as TC-039-022 (the actual router, contact engine and #9 owner on the recording hardware double, virtual UTC, a dial of 14074000 Hz, hand-authored waterfall rows on a flat floor of 20 with raised bands), a feed without a connection fed hand-authored spots (of my call at K1ABC; of other senders received by K1ABC at given offsets and parities); Hold Tx on and off; FT8 and FT4; the run calling K1ABC (CQ at 1800 Hz) from Tx 1500; the slot tables written in the test.
             Steps: case heard (a spot of my call 60 s old); case not_heard (K1ABC reports another sender 120 s ago, and 600 s ago, no spot of my call); K1ABC's only report 601 s old (no_reports); case no_reports (no spot; PskrUse off; the feed off; a call with a slash); each with tx_move_every {0, 0, 0}, {1, 1, 1}, {2, 2, 2} and {0, 1, 2} over 6 calls; a move whose quietest slot is the current one; a move whose quiet candidates all lie within 50 Hz of his reported frequencies of my Tx parity; his reported frequency in the other parity; free slots at 400, 480 and 520 Hz only; free slots at 1700 and 2420 Hz of equal value; 2420 strictly quieter than 1700; FT8 free slots only at 2350 (signal to 2400 Hz) and 2360 (to 2410 Hz) of equal value, the current Tx 2400; a held Tx at 400 (Hold Tx on) at the selection and at a move; the case changing from no_reports to heard after the 1st call; K1ABC answering after the 2nd call; a busy-paused call between two calls.
             Expected (hand-worked from WstxStrategy::TxMoveRule and FreeTxSlot): slot_check.case not_heard for the reports 120 s and 600 s old, no_reports for the one 601 s old; k 0 never moves; k 1 moves at every call and k 2 at every second, each move to another slot than the current (never overlapping it), never within 50 Hz of his frequency of my Tx parity; all candidates near his frequencies: Tx stays, slot_check moved false, tried again at the next call; the other parity's frequency does not exclude; 520 chosen, never 400 or 480; 1700 over 2420 on the tie, 2420 when strictly quieter; 2350 (not the upper edge) over the nearer 2360 (upper edge); the held 400 kept at the selection and moved into 500..2650 at a move; after the case change to heard no move; no move after the answer; the paused call not counted toward k; Hold Tx on moves Tx alone with Rx on K1ABC, off both; slot_check carries case, hears_us, moved and hz; the open-slot marks (FreeTxSlots) still list an open range below 500 Hz. Red on the parent: moves at every call regardless of the case, 400 chosen, 2420 on the tie.
             2 — Isolated automated tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-05';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/freeslot_tests.rs; server/src/pskr_tests.rs";
    }
    dependency CL_097_05_verified_by_TC_097_010 from 'CL-097-05' to 'TC-097-010';
    dependency CL_097_05_verified_by_TC_097_016 from 'CL-097-05' to 'TC-097-016';
    // #11 slice B (CL-011-02..04): FT4 in the operating workflow through the shared
    // contact engine; detailed contract in WstxContact (StationOperatingMode,
    // ContactMode, ModeChange, FT4-NOTE rules). The issue's planned TC-007-002 collided
    // with the #10 operating-layout case of that number; the FT4 contact case is
    // TC-007-008 (agent decision, 2026-10-31). Physical FT4 RF acceptance belongs to a
    // separately approved level-5 case and is not part of this slice.
    requirement 'CL-011-02' {
        doc /* Make FT4 selectable per station through the existing operating selection
             and receive start, without a second browser, rig-control, logging or
             transmit-authority path: the station's operating mode (the running live
             decoding job's mode, else the operating selection's mode) sets the mode of
             manual entries and own CQs, the Tx offset domain and the period shown; the
             mode persists across a receive stop and a band change; an operating mode
             selection is refused busy while #9 reports PTT keyed, a transmission or
             Tune; the #9 panel's mode is a read-only display of it. Details:
             WstxQsoTransmit::StationOperatingMode, ModeChange. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/selection_http.rs; server/src/receive_http.rs; server/src/contact_http.rs; server/src/contact.rs; client/contact.js; client/recording.js";
    }
    dependency CL_011_02_to_FR_006 from 'CL-011-02' to 'FR-006';
    dependency CL_011_02_to_FR_007 from 'CL-011-02' to 'FR-007';
    dependency CL_011_02_to_FR_019 from 'CL-011-02' to 'FR-019';
    requirement 'CL-011-04' {
        doc /* Keep FT8 behaviour unchanged and isolate the modes: a change of the
             station's operating mode disarms #9 and cancels a calling or active
             contact of the other mode (a completed contact keeps its review and mode),
             clamps the Tx offset into the new domain, the #9 owner never keys or plays
             a request of another station mode, and simultaneous FT4 and FT8 stations
             share no contact, arm or log state. Details: WstxQsoTransmit::ModeChange,
             ContactMode, WstxTransmit::StationModeGate. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/transmit/service.rs; server/src/recording.rs; server/src/receive_http.rs";
    }
    dependency CL_011_04_to_FR_006 from 'CL-011-04' to 'FR-006';
    dependency CL_011_04_to_FR_007 from 'CL-011-04' to 'FR-007';
    dependency CL_011_04_to_FR_008 from 'CL-011-04' to 'FR-008';
    dependency CL_011_02_verified_by_TC_006_002 from 'CL-011-02' to 'TC-006-002';
    dependency CL_011_04_verified_by_TC_007_008 from 'CL-011-04' to 'TC-007-008';
    requirement 'CL-010-03' {
        doc /* Offer explicit Enable Tx, disarm, contact cancellation, Abort QSO (Esc and a button beside HALT: the transmission stops now and the contact is cancelled without a halt, closing no panel; #39 2026-11-04) and the immediate Halt Tx emergency stop (buttons and Alt+H; the station and its automation never halt in normal flow); every transmission is a TransmitRequest through the #9 transmit service and its transmit authority, never direct PTT; loss, reconnect, retry or duplicates replay no transmit request and create no second contact. The live transmit path consumes the delivered #9 slice B owner (WstxTransmit::TransmitArming, TransmitRequest, TransmitOutcome, HaltTransmit) in-process. Details: WstxQsoTransmit::SetEnableTx, HaltTx, AbortQso, CancelContact, TransmitSubmission, ContactCommand; WstxTransmit::AbortTransmission, TransmitHaltUse. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_03_to_FR_007 from 'CL-010-03' to 'FR-007';
    dependency CL_010_03_to_FR_008 from 'CL-010-03' to 'FR-008';
    requirement 'CL-010-10' {
        doc /* Bound unattended transmission with a server-owned Tx watchdog (#39, 2026-11-06: default 6, 1..99 repetitions of one message, the Rep of the contact dialogue; only a different message, a new contact or an operator Enable Tx restarts it, never a partner message, a browser click or a setting; a send that would exceed the limit is not keyed and Enable Tx goes off without a halt) and an always-on Tune watchdog (default 90 s, 1..300 s). Details: WstxQsoControl::TxWatchdog, TuneWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_10_to_FR_008 from 'CL-010-10' to 'FR-008';
    requirement 'CL-010-11' {
        doc /* Set Rx and Tx audio offsets through labelled numeric inputs and waterfall pointer actions (#50: click Tx; double-click Rx and Tx; dragging the 3 px Rx/Tx lines and the Rx/Tx strip fields with 1 Hz/10 Hz steps), Hold Tx protecting only against implicit moves, each confirmed by the server and none enabling transmission. Details: WstxContact::PointerEffect, FrequencyControls. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_010_11_to_FR_007 from 'CL-010-11' to 'FR-007';
    dependency CL_010_11_to_FR_010 from 'CL-010-11' to 'FR-010';
    requirement 'CL-010-13' {
        doc /* Indicate worked-before status of decoded calls in Band Activity and the Rx Frequency pane (this band and mode, other band or mode, not worked, unknown) determined by the server from the profile log, by text or icon as well as colour, carried on each decoded record with no query. Details: WstxLogbook::WorkedBeforeQuery. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; client/logbook.js; client/contact.js; server/src/dxcc.rs";
    }
    dependency CL_010_13_to_FR_010 from 'CL-010-13' to 'FR-010';
    dependency CL_010_13_to_FR_011 from 'CL-010-13' to 'FR-011';
    requirement 'CL-010-14' {
        doc /* Show a UTC clock, a Tx period progress indicator and an Rx audio level meter (0..90 dB, high above 85, low below 15) from server observations, display-only and marked stale with the status link. Details: WstxQsoWire::OperatorDisplays. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/recording.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_14_to_FR_006 from 'CL-010-14' to 'FR-006';
    dependency CL_010_14_to_FR_010 from 'CL-010-14' to 'FR-010';
    verification 'TC-008-001' {
        doc /* TC-008-001 — Tx and Tune watchdogs
             CL-010-10
             Setup: actual server with virtual clock and the #9 transmit-service double; browser and MCP clients.
             Steps: refuse limits 0 and 100, accept 6 (default) and 1..99; with limit 2 call CQ with no answer for three periods; with limit 2 select a CQ, send Tx1 twice and let the partner answer with a report, then repeat the reply; with limit 3 let the partner repeat the same report every period while I repeat (R+report), with unrelated browser requests between the transmissions (hold, frequency, settings), and after the stop Enable Tx again; with limit 2 send Enable Tx while armed after the first reply and select the partner's row, at the same and at another SNR and after an edited Tx3, after the second; lower the limit to 2 with a third reply pending; at the limit with RR73 received and 73 pending choose Tx3; with limit 2 repeat the reply twice and let the partner advance with RR73 at +14.2 s, after the start window's lead for the third; with limit 2 call CQ, send one CQ and let a station answer with Call 1st off, then with Call 1st on; disarm and re-enable; Tune with 90 s default, 1 and 300 s, refuse 0 and 301; Halt during Tune.
             Expected (hand-counted): the third CQ is never keyed: Enable Tx goes off before keying with cause tx_watchdog, tx_expired true, halt_state unchanged (no halt), PTT released; remaining calls 2, 1, 0 while armed; the partner's report makes the next message a different one, which starts at the limit again (two repetitions before the stop); the partner's repeats and the browser requests change nothing: exactly three R+report go out, the fourth is never keyed, cause tx_watchdog without a halt, the dialogue shows the report and R+report each with their Rep; Enable Tx after the stop sends the same message again, a new tx entry with Rep 1; Enable Tx while armed and the partner's row change neither the remaining calls nor the dialogue, and the third reply is never sent, the lowered limit and the Tx button stop at once with nothing keyed; the RR73 makes 73 go out and the contact complete; with Call 1st off a caller leaves the CQ count unchanged, with Call 1st on the reply to the caller starts at the limit; a message from another station to someone else changes nothing; the counter is 0 while disarmed; the contact state is kept and "Tx watchdog: same message sent 2 times" is shown; Tune ends at its limit through #9; startup default 6 calls and 90 s.
             2 — Isolated automated functional tests; Windows development PC, virtual clock and independent transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-10';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/tests/transmit_service.rs";
    }
    verification 'TC-010-008' {
        doc /* TC-010-008 — Waterfall pointer actions and frequency inputs
             CL-010-11
             Setup: actual Chromium/server with injected spectrum rows at 1440x1000, DPR 1; request recorder. The pointer mapping at 1366x768 (DPR 1 and 2), 900x700 and 360x800 is checked by TC-050-007.
             Steps: at independently computed pixel positions for 700, 1000, 1500 and 2950 Hz perform click, double-click, shift-click with Hold Tx on and right-click; numeric Rx/Tx inputs with 199/200/2950/2951 Tx.
             Expected (#50): requested offsets equal the independently computed axis frequency rounded to integer Hz; click Tx only; a double-click exactly one request for Rx and Tx and no re-decode request; shift-click as click and with Hold Tx on; right-click nothing; the markers are 3 px lines (Rx rgb(48,208,80), Tx rgb(255,64,64)) without text at the confirmed values; out-of-domain refused; no Enable Tx request; the browser context menu does not open on the waterfall.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-11';
        }
        attribute executable : String = "tests/contact.test.cjs";
    }
    verification 'TC-010-009' {
        doc /* TC-010-009 — UTC clock, Tx progress and Rx level meter
             CL-010-14
             Setup: actual server/browser, virtual server UTC, independently synthesized canonical samples: silence, full-scale sine, sine at -40 dBFS and noise of known power; transmit double.
             Steps: observe across period boundaries, during a transmission, after link loss, with audio stopped.
             Expected: clock shows the server UTC HH:MM:SS (independent of a skewed browser clock) and is marked stale with the link; progress shows v/15 with v = whole elapsed seconds and a Transmitting label while transmitting; level = round(10 log10(mean(s^2))) with s scaled to 32768 (full-scale sine 87, -40 dBFS sine 47, silence clamped 0), labelled high above 85 and low below 15, unavailable with audio stopped, at most one value per second.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-14';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-011-003' {
        doc /* TC-011-003 — Worked-before indication
             CL-010-13
             Setup: profile log fixture with K1ABC on 20m FT8, W1XYZ on 40m FT8, DL1ABC on 20m MFSK/FT4; dial 20m FT8; rows from K1ABC, W1XYZ, DL1ABC, k1abc case variant, N0NEW and a hashed call; 65 distinct calls in one period.
             Steps: publish periods, save a new contact with N0NEW, publish again.
             Expected: K1ABC this band and mode; W1XYZ and DL1ABC other band or mode; N0NEW not worked then this band and mode after the save; hashed unknown; the status is text (hover text and aria-description, BandActivityHover) in Band Activity and the QSO pane's stations calling me, colour only from the enabled new_* slots of the record flags, so worked before on this band and mode has no colour; each record carries its status (worked_status, WstxLogControl::DecodedEntity) and the browser sends no query; no change to decoding, sequence or log.
             QSO pane subset (#10 2026-11-04, WstxQsoPane::QsoPane item 3). Setup: selection 20m FT8; routed records of one period with callers to my call HB9BLA K1ABC FN42 (no flags, worked_this_band_and_mode), HB9BLA W1XYZ FN31 (new_call, new_call_band, not_worked) and HB9BLA DL1ABC -10 (new_call_band, worked_other_band_or_mode). Steps: wait for the worked-before status of the rows; read the callers; turn New call off in Settings; refresh status. Expected (#50 BandActivityHover compact rule, #37 2026-11-04): K1ABC no colour and no hover text; W1XYZ the New call colour and the one-line hover "New call"; DL1ABC the New call on band colour and "New on 20m (worked on another band or mode)"; no My call colour; with New call off W1XYZ takes New call on band and the hover "New on 20m"; no worked-before query.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-13';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/dxcc_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_010_03_verified_by_TC_007_001 from 'CL-010-03' to 'TC-007-001';
    dependency CL_010_03_verified_by_TC_007_004 from 'CL-010-03' to 'TC-007-004';
    dependency CL_010_03_verified_by_TC_007_007 from 'CL-010-03' to 'TC-007-007';
    dependency CL_010_10_verified_by_TC_008_001 from 'CL-010-10' to 'TC-008-001';
    dependency CL_010_10_verified_by_TC_007_007 from 'CL-010-10' to 'TC-007-007';
    dependency CL_010_11_verified_by_TC_010_008 from 'CL-010-11' to 'TC-010-008';
    dependency CL_010_13_verified_by_TC_011_003 from 'CL-010-13' to 'TC-011-003';
    dependency CL_010_14_verified_by_TC_010_009 from 'CL-010-14' to 'TC-010-009';

    // #39 Strategy engine: selection, value order, editor popup, directed-CQ rule (decisions
    // on #37/#39/#42, 2026-11-01); detailed contract in WstxStrategy.
    requirement 'CL-039-01' {
        doc /* Named strategies are a station setting of the selected profile: strategy.json (schema 4) beside profile.json holds {continent, strategies, ignore lists} with up to 16 strategies, each with the keys of CL-097-01 (classes and contest strategies: CL-097-01, CL-097-07). Exactly one strategy is active, or None; active never survives a station restart. Files of schema 1, 2 and 3 are read by the upgrade of WstxStrategies::StrategyConfiguration and written as schema 4 by the next PUT. GET /strategy and PUT /strategy (revision-checked, exact keys) read and save it; my continent is configurable there (Settings > General) and otherwise the cty.dat continent of my callsign (#55). Details: WstxStrategies::StrategyConfiguration, Strategy, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_039_01_to_FR_007 from 'CL-039-01' to 'FR-007';
    dependency CL_039_01_to_FR_016 from 'CL-039-01' to 'FR-016';
    requirement 'CL-039-05' {
        doc /* Selecting a strategy marks its candidates; it transmits only while Auto is on (CL-039-22), through the existing station automation and contact engine (no second engine), with no confirmation and no client decision: the browser sends only the selection and the toggle, and HALT is always on screen. A strategy run calls CQ only with CQ when idle (CL-039-22) and goes on after each QSO without a contact limit, waiting for the next opportunity, for at most 8 hours from its start, also with a browser open (operator decision 2026-11-06: a new start gives a new 8 hours); it answers callers of my call (only with Calling stations are answered on, first), then the best candidate; it leaves a station by the leave rule (CL-039-23) and may call it again after its retry pause; it never selects a station the operator cancelled or aborted again in that run, nor one completed in that run on this band and mode. It follows its grant, not the transport of the starting request: a page reload or a second tab does not stop it, a revoked grant does. Unattended (operator decision, #39 comment 6685226511) and at the run limit ("Finish the QSO first", operator 2026-11-07): with no authenticated client (a status WebSocket session, or an authenticated MCP request) for 60 s, or past 8 hours, it selects no new station and answers no caller, its own CQ ends at once, a QSO the partner is answering is completed, otherwise the contact ends at x repetitions, and it stops with the reason no_client or run_limit; only an Auto on restarts it, never an AutomationCommand start. A band or mode change by the operator and HALT end the contact at once; Auto off, None, another selection, a contest deselected and the end of a contest period end at once a contact that is no started QSO and let a started QSO finish (#81, CL-081-01). It waits instead of stopping across a receive restart; a refused start or a stop turns Auto off with the reason shown and leaves the strategy selected. HALT from any source stops the run and turns Auto off, pushed to the browser; the selection stays. Esc does not. A double-click is always possible and is a manual intervention: the run waits for that QSO to end and resumes. An MCP principal cannot select a strategy nor switch Auto. Every Auto decision is taken at the earliest moment the information it needs is available, never later (#89, operator 2026-11-09: "decision always fastest when needed info is available. this is a general rule for the auto mode"). Details: WstxAutoControl::StrategyRun (Decision timing), AutoToggle, StrategySelector, ManualIntervention, SaneCall; WstxMcp::OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_05_to_FR_020 from 'CL-039-05' to 'FR-020';
    dependency CL_039_05_to_FR_007 from 'CL-039-05' to 'FR-007';
    requirement 'CL-039-07' {
        doc /* Outstanding, issue #39/#42 later slices: filtered-out view toggle; freeze Band Activity on hover; per-mode watchdog values; late-duplicate guard and false-decode heuristic; CQ-target prefer; stacked DXpedition replies. Delivered: the free Tx slot finder (CL-039-09), contests (#63), the busy pause (CL-097-06) for a busy partner, and the CQ target filter (CL-097-02). The outstanding slices are not offered. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_039_07_to_FR_007 from 'CL-039-07' to 'FR-007';
    verification 'TC-039-008' {
        doc /* TC-039-008 — Later strategy slices (outstanding: the CL-039-07 slices)
             CL-039-07
             Setup: actual candidate router with a pinned cty.dat fixture and hand-authored rows.
             Steps: the scenarios of each outstanding slice.
             Expected: defined when the slice is prepared.
             2 — Isolated automated functional tests; Windows development PC; not implemented. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-07';
        }
    }
    dependency CL_039_07_verified_by_TC_039_008 from 'CL-039-07' to 'TC-039-008';
    requirement 'CL-039-22' {
        doc /* Mode (operator grill 2026-11-07, Q5, Q11, Q12, Q17, Q29, Q35, Q40). Auto is a toggle above the QSO pane next to CQ, green on and grey off, not part of a strategy, one toggle for strategies and contests; the station owns it in memory: off after a station restart, after HALT from any source and after every run end, and only the browser switches it (POST /strategy/auto; an MCP principal is refused). With Auto off a selected strategy or contest only marks its candidates; switching it on needs a selection and starts the run, and a contest whose rules forbid automatic operation asks the existing warning and needs its confirmation; switching it off ends the run at once, and a QSO the run has started is finished as an ordinary contact (#81, CL-081-01: Auto only decides whether new QSOs start); selecting None turns it off, another selection with Auto on starts that one. CQ when idle is a strategy setting with its CQ wait (CL-097-01, CL-097-08; on in Casual and the contest built-ins): with it on the run calls CQ after cq_wait_periods publications with nothing callable, answers callers (with Calling stations are answered on) and calls a candidate that appears; the Tx watchdog stops its CQ. With Hold Tx on (#39 holdtx round 1 Q3) the CQ goes out on the held Tx without a slot decision; with Hold Tx off it takes the slot quiet in my Rx parity (CL-039-09, #66). Details: WstxAutoControl::AutoToggle, CqWhenNoTarget, StrategyRun, PskrUse; WstxQsoPane::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_039_22_to_FR_007 from 'CL-039-22' to 'FR-007';
    dependency CL_039_22_to_FR_020 from 'CL-039-22' to 'FR-020';
    requirement 'CL-039-20' {
        doc /* A read-only PSK Reporter MQTT feed tells the station whether the current target hears my call (with the SNR it reported) and which frequencies it decodes, with their parity: two exact subscriptions (my call as sender; the strategy or contest target as receiver while Use PSK Reporter is on, replaced when the target changes), never a wildcard from a decoded call, TLS against compiled-in roots, an identifiable client id, bounded reconnect backoff, bounded memory, spots expiring after 600 s, a spot of another band or mode ignored. Settings shows the master switch (on by default) and the status, pushed; the Use PSK Reporter toggle next to Auto (on by default, kept across restarts) decides whether runs use the feed, and while it is on the QSO pane shows "hears us" (spot age and reported SNR, or no, or unknown) and "open at his end" with the chosen slot. It sends nothing but the handshake, keep-alive and subscriptions; everything works without it: no connection is unknown, never an operator error, and receive and the 50 ms station step never wait on it. Details: WstxHearingFeed::HearingFeed, PskrUse. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/pskr.rs; server/src/main.rs; server/src/contact_http.rs; server/src/recording.rs; client/contact.js";
    }
    dependency CL_039_20_to_FR_007 from 'CL-039-20' to 'FR-007';
    dependency CL_039_20_to_FR_012 from 'CL-039-20' to 'FR-012';
    verification 'TC-039-020' {
        doc /* TC-039-020 — The PSK Reporter feed against a local peer
             CL-039-20
             Setup: no network. A local TCP peer whose packets are written from the OASIS MQTT 3.1.1 tables; hand-authored payloads in the form of the broker's published schema; the certificate chain the broker presented on 2026-11-06, captured once as a fixture; shortened session timings; the actual station router for the routes.
             Steps: parse a full spot, one without t_tx, and malformed ones; build filters from my call, a target and hostile calls (wildcards, slash, space, lower case, control and non-ASCII characters, overlong); record spots past the window, on another band or mode, past each bound, repeated and ahead of the clock; read the decoded offsets of a 7074000 Hz dial; encode each packet and parse whole, split and hostile input; step the backoff; run a session and change the target, send a non-spot and spots with another sender and receiver than the topic says, wait for a ping, switch off; a peer that drops five connections and then accepts; peers that refuse CONNECT, refuse SUBSCRIBE, send a reserved packet; the setting by default, after a save, from another profile and broken; WSTX_PSKR values; verify the captured chain against the compiled-in roots, with another name and after it expired; a peer without TLS; GET and POST /pskr with and without a feed, an extra key, a query.
             Expected: exactly pskr/filter/v2/+/+/HB9BLA/+/# and pskr/filter/v2/+/+/+/K1ABC/#, no filter for any hostile call; hears us exactly up to 600 s, on that band and mode; offsets [1200, 800] for 7075200 and 7074800 Hz, none from another band, mode, receiver or from my own spot, none outside the range; at most 256 and 128 entries, 32 offsets, newest kept; packets equal the hand table; hostile input is protocol_error; delays 5, 10, 20, 40, 80, 160, 300, 300 s, 5 s after a reset; on the wire only CONNECT, SUBSCRIBE, UNSUBSCRIBE, PINGREQ, DISCONNECT; the old target unsubscribed, the hostile one not subscribed; the spot counts by its payload; off forgets everything; attempts at least 40, 80, 160, 160, 160 ms apart with the shortened timing, the status naming the error, recovery without any action; connection_refused, subscribe_refused, protocol_error; on by default, the save kept, invalid_pskr for the other two; only a loopback tcp: value replaces the broker; the chain valid on capture, refused otherwise; tls_failed with TLS spoken first; 404 without a feed, the exact view with one, other requests refused.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-20';
        }
        attribute executable : String = "server/src/pskr_tests.rs";
    }
    dependency CL_039_20_verified_by_TC_039_020 from 'CL-039-20' to 'TC-039-020';
    verification 'TC-039-021' {
        doc /* TC-039-021 — Settings shows the PSK Reporter status, pushed
             CL-039-20
             Setup: the actual isolated station with WSTX_PSKR pointing at a local MQTT peer in the test, Chromium at 1366 x 768.
             Steps: open Settings > Logging; wait for the connection; publish a spot of my call 180 s old; uncheck the switch; drop the peer and check the switch again.
             Expected: the switch is in view and on by default; "Connected · no spot yet", then "Connected · last spot 3 min ago", with exactly one GET /pskr; "Off" and Saved after the switch, the station stores it and the peer sees DISCONNECT and no packet other than CONNECT, SUBSCRIBE, PINGREQ, DISCONNECT; "Not connected · <code> · retrying" with the broker gone; no page error.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-20';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_039_20_verified_by_TC_039_021 from 'CL-039-20' to 'TC-039-021';
    requirement 'CL-039-08' {
        doc /* Hold Tx is on by default (operator decision 2026-11-04, #39; consistent with the split-frequency rule): a station starts with settings.hold_tx true, in manual operation and for a strategy alike, so selecting or answering a station moves Rx and never Tx; Tx stays on the operator's chosen slot until an explicit Tx action (the Tx input, a waterfall Tx pointer action, MCP set_frequency, the Hound's own rule). Automation (#39 holdtx, operator 2026-11-07: "Hold Tx on: the automation never moves Tx", corrected to "if the other station does not hear us we are allowed to change the frequency to a quiet place, but never to the Rx frequency"; this replaces "a run's free slot" as an explicit Tx action): with Hold Tx on a strategy or contest run or a pounce keeps Tx at a selection, before its CQ and when answering a caller from it, and moves Tx in exactly two cases: the station selected or answered is within 50 Hz of Tx (then Tx goes to the nearest slot 50 Hz away from it, round 1 Q2), and a Tx move of the Tx move rule (CL-097-05); Rx stays on the station. The operator may switch it off with set_hold_tx; the choice lasts for the station's running session, since Hold Tx is not saved (CL-110-01 point 8); the run reads it at each decision. Details: WstxStrategy::FreeTxSlot. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js; server/src/automation.rs; server/src/freeslot.rs";
    }
    dependency CL_039_08_to_FR_007 from 'CL-039-08' to 'FR-007';
    verification 'TC-039-009' {
        doc /* TC-039-009 — Hold Tx is on by default
             CL-039-08
             Setup: actual contact engine and actual station Router with a fresh profile (no explicit choice), hand-authored decode rows.
             Steps: read the first contact snapshot; select a CQ at another frequency; answer through a strategy pick; switch Hold Tx off and select again.
             Expected (oracle: the operator's decision on #39): settings.hold_tx true in a fresh snapshot and #contact-hold checked; after the selection Rx follows the row and Tx stays 1500; after the strategy pick Tx stays; with Hold Tx explicitly off a selection moves Tx to the row (the WSJT-X rule of FirstSlotOnSelection). On the parent the fresh snapshot says false and the selection moves Tx.
             2 — Isolated automated tests; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-08';
        }
        attribute executable : String = "server/src/contact_tests.rs::hold_tx_is_on_by_default_and_a_selection_keeps_tx; server/src/strategy_tests.rs::tc_039_004_selecting_starts_a_run_that_calls_by_value_and_never_calls_cq; tests/contact.test.cjs";
    }
    dependency CL_039_08_verified_by_TC_039_009 from 'CL-039-08' to 'TC-039-009';
    requirement 'CL-039-09' {
        doc /* A strategy or contest run or a pounce calls from the quietest Tx slot: the slot where the target can answer us, a free slot on my side, judged in every decision (a selection, a slot check, a CQ) in my Rx periods only (his Tx parity; #66 operator 2026-11-08 "judge the parity I will receive in"), and only in recent ones: the counted periods among the last 4 periods of my Rx parity that are due: ended on the clock, or earlier, while in progress, once their complete decodes are published, never before they start (#66 "Only if recent"; #89 operator 2026-11-09 "Count once decoded": a decision on the publication of my newest Rx period counts it; every contest Run CQ decided in waiting without a fresh publication, at Auto on, when a reason ends, when a manual contact ends or Esc gives a caller up, after a completion or a leaving, waits for that publication and decides at once when it arrives, at the latest when the period in progress ends, CL-039-05 decision timing), periods I transmitted in never counted. Slots are compared with each other across the whole passband (#66, operator 2026-11-08 "We want to have the quiet slots overall. Across the entire bandwidth of FT8."), not by their own usual level: in each counted period a slot's rise is its level minus the WSJT-X passband floor fitted to that period (so the receive filter's roll-off does not favour the edges), and its value is its largest rise over the counted periods clamped at 0 (#66, operator 2026-11-08 "At or under floor = free": a slot at or below the floor is free, so a sharp filter knee the floor cannot follow never makes the edges win); compared in whole dB, the lowest value winning; a tie keeps the current Tx when it is among the quietest, else goes nearer the current Tx, then lower; there is no threshold. A slot whose signal overlaps a station decoded in a counted period (less than one signal width from his decoded frequency) is left out while any other is free. Where known it is free at his end: at least 50 Hz from every frequency his PSK Reporter spots show him decoding, counting only spots from my Tx parity (ignored when that leaves no slot). Hold Tx off: Rx = Tx, the slot sets both, decided at each selection, before a CQ and at each move of the Tx move rule (CL-097-05). Hold Tx on (CL-039-08): Rx stays on the station and the slot sets Tx alone, only at a move of the Tx move rule, or as the nearest slot 50 Hz away when the station is within 50 Hz of Tx; a CQ goes out on the held Tx. Every slot the run chooses lies from 500 Hz inside the Tx range (FT8 500..2650, FT4 500..2610), a slot reaching above 2400 Hz losing every tie, and at least 50 Hz from the called station's signal and from Rx; without power data the current Tx is kept. Details: WstxStrategy::FreeTxSlot. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/freeslot.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_039_09_to_FR_007 from 'CL-039-09' to 'FR-007';
    dependency CL_039_09_to_FR_020 from 'CL-039-09' to 'FR-020';
    verification 'TC-039-010' {
        doc /* TC-039-010 — The quietest Tx slot
             CL-039-09
             Setup: the pure slot function with hand-authored power tables (levels in dB per 10 Hz candidate, written in the test) and hand-authored spot frequencies; the actual station Router with the contact engine and #9 owner on the hardware double, an injected FT8 live job whose detailed waterfall rows are hand-authored (a flat floor of 20 with raised bands), a selected strategy with Auto on, a pounce, a plain MCP run; virtual UTC.
             Steps: choose on tables: one lowest slot; the current Tx tying the lowest; two lowest without the current Tx, at different distances from it and at equal distances; levels 40.4 and 40.0 (one whole dB, a tie) against 40.6 and 40.0 (no tie); the range edges for FT8 (500..2650) and FT4 (500..2610, width 90), the upper edge losing ties (TC-097-010), every slot at 500 Hz or above; the called station on the quietest slot; his decoded frequencies of my Tx parity and of the other parity near the quietest; his frequencies excluding every candidate; listening only, with one parity quiet and the other loud; no power yet, with the called station on and away from the current Tx. Router: periods of both parities with a quiet band at 1800 Hz only in my Rx parity; the 5th oldest period of the parity quiet at 600 Hz; a period I transmitted in; then a candidate CQ on 1500 Hz; a QSO to its end; a station band change within the job; Hold Tx off; a caller on my slot; a pounce; a plain MCP run.
             Expected (oracle: the operator's rule, hand-computed in the test): that slot; the current Tx kept; the nearer one, then the lower; 40.4 and 40.0 tie and keep the current Tx, 40.6 does not; never outside the range; never within 50 Hz of the called station; his frequency of my Tx parity excludes the slot within 50 Hz and the other parity does not; all excluded: his end ignored, his_end no; listening only (#66): judged on my Rx parity alone, the parity loud only in my Tx periods not avoided; no power: the current Tx kept, or the nearest away from the called station, power_db null. Router: Tx and Rx 1800 before the first call (the 5th period and the transmitted period ignored), tx_slot {hz 1800, power_db 20, his_end unknown}; Tx stays 1800 through the whole QSO; after the band change only the new band's periods count; with Hold Tx off Tx back on its slot; the caller answered from the quietest slot away from it; the pounce calls from the quietest slot; the plain run has tx_slot null and keeps its Tx.             #39 holdtx: the Router steps run with Hold Tx explicitly off (the Rx = Tx rule); with Hold Tx on they are TC-039-049. The tables give the compared value instead of the absolute power, and power_db is that value. #66: the compared value is the largest rise above the passband floor clamped at 0 (TC-039-050), so the Router's tx_slot reads power_db 0 on the flat floor of 20 (floor 20.65, rise -0.65 clamped); the decoded-station rule is TC-066-002.
             2 — Isolated automated tests; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs; server/src/automation_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_039_010 from 'CL-039-09' to 'TC-039-010';
    verification 'TC-039-030' {
        doc /* TC-039-030 — Goals, windows, value order, callers and the WPX prefix
             CL-039-01, CL-039-02, CL-039-05
             Setup: hand-authored rows and a log of hand-written contacts (worked, confirmed, per band and mode, with and without a grid, with dates) for HB9BLA on 40m FT8, EU, and for a non-EU profile; the expected verdicts are written in the tests.
             Steps: each what of the schema 3 goals as the upgrade maps it (new [dxcc] per ever, band and band_mode, [cq_zone] per ever, [prefix] per ever, [grid] per ever, [call] per ever and per band; TC-097-002, TC-097-005) with worked and confirmed fixtures in both needed settings; grid with no message grid and with a logged QSO without a grid; region all, dx and selected for an EU and a non-EU profile; window all, today and from-to with an undated record; the worked set for the station step after a log write; min_snr_db; a caller against a Most Wanted station with a what, region and SNR that exclude it; value order with and without a list; the WPX prefix table; class contest; the old file upgrade.
             Expected: the tables of the tests; the caller that fails the filters has no rank (TC-097-007); without a list strongest first; with one the listed first by rank, the others after them strongest first; unknown grid is never needed; the step gets the last set at once and the new one follows on its own thread; class contest is accepted only with a contest (TC-097-001).
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-02';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/dxcc_tests.rs; server/src/logbook_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_030 from 'CL-039-01' to 'TC-039-030';
    dependency CL_039_05_verified_by_TC_039_030 from 'CL-039-05' to 'TC-039-030';
    requirement 'CL-039-11' {
        doc /* Read-only built-in strategies are offered beside the user's: the five of class strategy and one contest built-in per contest, with their values (CL-097-01, CL-097-07). They come from one server table, are listed with builtin true in the snapshot, can be selected like any strategy, cannot be edited through PUT /strategy (a user strategy with such a name is refused) and can be duplicated to a user strategy in the editor. Details: WstxStrategies::BuiltinStrategies, StrategyEditor, StrategySelector. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_11_to_FR_007 from 'CL-039-11' to 'FR-007';
    verification 'TC-039-032' {
        doc /* TC-039-032 — Built-in strategies: selection, refusal and copy
             CL-039-11
             Setup: the actual station router on a disposable HTTPS profile with the contact engine and #9 transmit owner on the recording hardware double; a browser case on the actual isolated station. The table of the built-ins is TC-097-003's.
             Steps: GET /strategy; parse a configuration with active "Casual", with "casual", with a user strategy "New DXCC" and "new dxcc", with the key builtin; PUT active "Casual", Auto on, and publish CQ DL1XYZ JO62 (+9 dB) and CQ K1ABC FN42 (-15 dB); read strategy.json; open a new owner; a PUT with a user strategy "Casual"; HALT; a saved file with a strategy named "New calls" (no built-in) and one named "Casual". Browser: the selector; open the editor with no user strategy; Save; open a built-in; try to change it; Duplicate; Save; rename the copy to a built-in's name and Save.
             Expected: every built-in with builtin true, none in configuration.strategies; active accepted exact only, "casual" refused active; strategies[0].name refused; strategies[0] refused for the key builtin; the run calls DL1XYZ (SNR bucket above 0 dB first); the file holds no built-in and active null; the new owner reads None; the PUT refused strategies[0].name; HALT turns Auto off and keeps "Casual"; the saved "New calls" reads as it is and the saved "Casual" reads renamed "Casual copy". Browser: None and the built-in names; the editor shows the first built-in, Save sends no strategy and active null; the built-in's fields disabled, Delete disabled, no PUT of a built-in; the copy "New DXCC copy" the only user strategy saved; the colliding rename refused with its field shown.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-11';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_039_11_verified_by_TC_039_032 from 'CL-039-11' to 'TC-039-032';
    verification 'TC-039-033' {
        doc /* TC-039-033 — A strategy without a client and its run limit
             CL-039-05
             Setup: as TC-039-004 (Auto on after each selection); the automation clock of the test moved by the seam; no status WebSocket unless a session is held or, in one case, a real upgrade over the served router; reads through the browser routes, which are not clients here.
             Steps: select and Auto on; at 59 s publish CQ K1ABC; at 60 s run the exchange to its end; publish a CQ and a call to my call; an MCP start; Auto on again; at 60 s without a contact publish a CQ; a session held from 0 s and released at 120 s, ticks at 179 s and 180 s; an MCP request at 59 s, a tick, ticks at 118 s and 119 s; a client back at 59 s of a contact past 60 s; at 60 s with K1ABC silent and a spot of my call at K1ABC; a CQ of a strategy with CQ when idle at 60 s; an actual status WebSocket upgrade with the browser cookie, past 60 s, then closed. Run limit, a client connected throughout: a CQ just before 8 h; at 8 h the exchange to its end; a CQ; Auto on again; again just before and at 8 h after that start.
             Expected: K1ABC selected and armed at 59 s; the contact goes on at 60 s to completed, then stopped no_client, Auto off, the strategy still selected, neither the CQ nor the caller called; the MCP start refused operator_required; Auto on waits and answers; stopped no_client at 60 s with nothing selected; waiting at 179 s and stopped at 180 s; waiting at 118 s and stopped at 119 s; no stop when the client came back before the contact ended; the silent K1ABC left at 4 repetitions, not 8, then stopped no_client; the CQ disarmed and cancelled at once and stopped no_client; waiting while the real WebSocket is open and stopped no_client after it closes. Run limit: selected and armed just before 8 h; the contact goes on at 8 h to completed, then stopped run_limit, Auto off, still selected, the CQ not called; the new start waits, answers and stops run_limit 8 h after it.
             2 — Isolated automated functional tests; Windows development PC, transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_05_verified_by_TC_039_033 from 'CL-039-05' to 'TC-039-033';
    // TC-039-041 retired: its schema 2 and schema 3 store cases are TC-097-002's and its built-ins
    // TC-097-003's. The identity is not reused.
    @RetiredCase { identity = "TC-039-041"; supersededBy = "TC-097-002; TC-097-003"; }
    verification 'TC-039-042' {
        doc /* TC-039-042 — The Auto toggle
             CL-039-22, CL-039-05
             Setup: the actual station router (HB9BLA JN47AA) with the contact engine and #9 transmit owner on the recording hardware double, virtual UTC, 20 m; a status session held open; the browser cookie grant; an MCP token; a saved strategy "New calls" of class strategy (new [call] per ever, not worked, order [most_wanted]).
             Steps: GET /strategy; select "New calls" and publish CQ K1ABC FN42 for two periods; POST /strategy/auto true; another selection with Auto on; Auto false; Auto true without a selection (None); select None with Auto on; HALT by route and by MCP; a station restart; Auto true from the MCP principal; extra key, wrong profile, stale boot; a contest WW Digi (forbidden) with Auto true without and with automation_confirmed; FT8 Activity (silent) without it; with Auto on for FT8 Activity, a selection change to WW Digi; a run stopped tx_watchdog by a manual contact, then a browser Auto on; with Auto off a pounce armed on K1ABC, then a PUT selecting "Test calls", then Auto on; a strategy.state subscriber across each change.
             Expected: auto false by default; with Auto off the verdicts mark K1ABC and nothing is armed or keyed; Auto true starts the run, K1ABC selected and armed; another selection ends the run and starts the new one, Auto still on; Auto false disarms and cancels at once, the run stopped, the strategy selected (K1ABC has sent nothing to my call, so no QSO has started: #81, CL-081-01; a started QSO is TC-081-001); 409 not_configured strategy and Auto off; None turns Auto off; HALT turns Auto off, the run stopped halted, active kept; after the restart auto false and active None; the MCP principal refused 401, nothing changed; 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id; WW Digi refused field automation_confirmed and accepted with it, FT8 Activity accepted; the change to WW Digi while Auto is on ends the run, starts none and turns Auto off; the Auto on ends the watchdog stop and arms; the PUT with Auto off leaves the pounce running and armed, and Auto on ends it; one strategy.state per change, none on subscription. No PTT exchange.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-22';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_22_verified_by_TC_039_042 from 'CL-039-22' to 'TC-039-042';
    dependency CL_039_05_verified_by_TC_039_042 from 'CL-039-05' to 'TC-039-042';
    verification 'TC-039-043' {
        doc /* TC-039-043 — Leaving in a strategy run
             CL-039-23, CL-039-05
             Setup: as TC-039-042 with Auto on, strategy "Test" of class strategy (new [call] per ever, order [snr], leave {calls 4, calls_heard 8}, retry_minutes 10, Calling stations are answered on, busy_pause off), the feed without a connection fed hand-authored spots, a dial of 14074000 Hz; the run calling K1ABC (CQ FN42). The callers JA1XYZ and W1AW pass the filters (new calls). The other leave modes are TC-097-009.
             Steps: (a) K1ABC silent (not decoded) for 5 partner periods. (b) K1ABC calling CQ again each period. (c) As (a) with a spot of my call at K1ABC 60 s old; the same with Use PSK Reporter off. (d) K1ABC answers with -05 after the 2nd repetition and repeats -05 for 6 periods (the #63 fix). (e) A caller W1AW selected, repeating its first call 5 times. (f) A stronger new CQ DL1XYZ from the 2nd repetition on. (g) A caller JA1XYZ at the 2nd repetition; the same with Calling stations are answered off; with JA1XYZ in its retry pause; after K1ABC has answered. (h) After (a): K1ABC's CQ alone at 9 min 59 s and at 10 min, and its call to my call at 5 min. (i) leave {calls 1, calls_heard 2}. (j) The band changed to 40 m in a stay; a new live identity (FT4); Auto off; HALT.
             Expected (hand-worked from the operator's rule): (a) and (b) armed after 3, disarmed and cancelled at the 4th, left {K1ABC, repetitions}, quiet K1ABC 600 s, waiting; (c) armed after 7, left at the 8th; with Use off left at the 4th; (d) never left during the 6 repeats, unanswered back to 0 at each (red on the parent, which leaves at the calls); (e) left at the 4th; (f) K1ABC kept, DL1XYZ never selected before the 4th, selected at the next step after it; (g) left {K1ABC, caller} at once and JA1XYZ selected from the same publication; callers off, in its retry pause or after an answer: K1ABC kept; (h) not selected at 9 min 59 s nor answered at 5 min, selected at 10 min; (i) left at the 1st; (j) disarmed and cancelled at the next step, no quiet entry, left null, the run waiting (band, mode) and selecting from the next publication, stopped (Auto off, HALT); in a stay K1ABC has not answered, so no QSO has started and Auto off disarms at once (#81, CL-081-01).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-23';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_05_verified_by_TC_039_043 from 'CL-039-05' to 'TC-039-043';
    verification 'TC-039-044' {
        doc /* TC-039-044 — Leaving in a contest run
             CL-039-23, CL-063-05
             Setup: as TC-063-009 (WW Digi, 20 m, the period in force, W1DUP a dupe in the log) with Auto on and automation_confirmed; a copy of the contest built-in "WW Digi" with cq_when_idle false, leave {calls 2, calls_heard 4} for (a) and (b), leave {contest, tx_changes 1} with tx_move_every {heard 0, not_heard 1, no_reports 1} for (c), (d) and (e) (a move at the 1st call, the leaving at the 2nd), retry_minutes 10; for (f) the built-in with cq_when_idle true; the feed fed hand-authored spots; the run calling K1ABC FN42 (new multiplier).
             Steps: (a) K1ABC silent, no spot. (b) K1ABC silent with a spot of my call at K1ABC. (c) K1ABC calling CQ again for 10 periods with the spot; then CQ JA1XYZ PM95 (new multiplier, more points) from the 6th; again with JA1XYZ from the 1st repetition. (d) W1DUP (dupe) calling my call for 8 periods during (c) (the #63 fix). (e) A non-dupe caller K2NEW FN31 at the 1st repetition. (f) The CQ when idle: CQ, caller K2NEW answered, then silent; K2NEW calling again during its retry pause. (g) leave {calls 3, calls_heard 6} and retry_minutes 1 in the strategy. (h) The station clock past the period end in a contact; the contest deselected (None) in a contact.
             Expected (hand-worked): (a) left at the 2nd; (b) left at the 4th; (c) stays all 10 with the spot and nothing more valuable; with JA1XYZ listed from the 6th a stay has no count, so the 6th call is a change point and K1ABC is left at the 7th with reason tx_changes, then JA1XYZ is selected; JA1XYZ from the 1st: K1ABC kept until the 2nd, then left and JA1XYZ selected; (d) the stay holds, W1DUP never selected or answered (red on the parent, where the dupe ends the stay); (e) left {K1ABC, caller} at once, K2NEW selected; (f) K2NEW answered from the CQ's slot (Tx and Rx stay on 900, the CQ quiet in my Rx parity, #66), left at the 2nd, calling_cq again, K2NEW not answered while quiet; (g) left at the 3rd, called again after 1 minute; (h) disarmed and cancelled at once, waiting outside_period; stopped, Auto off (K1ABC has not answered the call in (h), so no QSO has started; a started contest QSO at the period end or deselection finishes: #81, TC-081-003).
             #39 holdtx: these steps run with Hold Tx explicitly off (they test the run logic; Rx = Tx on the slot); with Hold Tx on the CQ of (f) stays on the held Tx: TC-039-049 (j).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-23';
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_063_05_verified_by_TC_039_044 from 'CL-063-05' to 'TC-039-044';
    verification 'TC-039-045' {
        doc /* TC-039-045 — CQ when idle
             CL-039-22
             Setup: as TC-039-042 with Auto on and the saved strategy "Casual 20 m" of class strategy (new [call] per band, worked_since today, order [snr], cq_when_idle true, cq_wait_periods 2); the log holds W1AW on 20 m today; Tx watchdog 6.
             Steps: two publications with nothing callable; a third; W1AW (worked today) calls my call, then N1NEW FN31 (not in the log); N1NEW's QSO to the end; two empty publications; CQ DL1XYZ JO62 while calling CQ; callers at 1200 Hz and at 920 Hz with the CQ on 900; the same strategy with cq_when_idle false for 6 empty publications; Tx watchdog 2 with an unanswered CQ; no client for 60 s while calling CQ; the slot of the CQ with one parity loud.
             Expected: waiting after the first, calling_cq after the second, armed, Tx6 "CQ HB9BLA JN47"; a caller is answered from the CQ's slot: with the CQ on 900 (quiet in my Rx parity, #66) a caller at 1200 Hz keeps Tx and Rx on 900, a caller at 920 Hz moves them to 820, the nearest candidate 50 Hz away from it; W1AW not answered (it fails the filters, TC-097-007); N1NEW answered with select_row {replace false} and Enable Tx kept; completed, then calling_cq again after two empty publications; DL1XYZ selected and called, the CQ ended; off: never a CQ, nothing armed; watchdog 2: stopped tx_watchdog, Auto off, not keyed again; unattended: the CQ disarmed and cancelled at once, stopped no_client; the CQ's slot the quietest in my Rx parity, the loud parity ignored when it is my Tx parity (#66: the CQ judges only my Rx periods).
             #39 holdtx: these steps run with Hold Tx explicitly off; with Hold Tx on the CQ goes out on the held Tx and the callers are TC-039-049 (h).
             #66: the step "the slot of the CQ with one parity loud" is run twice, the loud parity my Tx parity (ignored) and my Rx parity (avoided); a caller's nearest candidate 50 Hz away also skips a station decoded in my Rx periods (TC-066-002 (h)).             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-22';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_22_verified_by_TC_039_045 from 'CL-039-22' to 'TC-039-045';
    verification 'TC-039-047' {
        doc /* TC-039-047 — Live strategydef on HB9BLA at 30 W, 20 m FT8
             CL-039-02, CL-039-09, CL-039-20, CL-039-21, CL-039-22, CL-039-23
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 on 20 m FT8 (14.074 MHz), RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), operator consent; Tx watchdog 6; PSK Reporter on in Settings and Use PSK Reporter on; the saved strategies of class strategy "Strongest new on band" (new [call] per band, order [snr]), "Farthest new on band" (order [distance]) and "Casual 20 m" (as TC-039-045), each with leave {calls 4, calls_heard 8} and retry_minutes 10. The built-ins live are TC-097-016's.
             Steps: select "Strongest new on band" with Auto off for two periods; switch Auto on and let it work stations to two logged QSOs; watch a station that does not answer; watch the PSK Reporter lines and the Tx slot at each repetition; HALT; Auto on again; select "Farthest new on band" and let it work one QSO; select "Casual 20 m" and let it call CQ and answer a caller; Auto off during a CQ; select None.
             Expected: with Auto off the candidates are marked by SNR and nothing is transmitted; with Auto on the strongest new call on band is called first, to a logged QSO, and it goes on; a station that does not answer is left after 4 repetitions (8 while the QSO pane shows "Hears us" with a spot) and not called again for 10 minutes; while there is no spot Tx (with Hold Tx on; Tx and Rx together with Hold Tx off) moves to the quietest slot at a repetition or stays on a tie, and with a spot Tx stays; the QSO pane shows "Hears us" and "open at his end" with the slot; HALT stops at once, Auto grey, the selection kept; Farthest calls the farthest new call on band first; Casual calls CQ after 2 periods without a candidate and answers a caller to a logged QSO; Auto off ends the CQ at once; None leaves Auto off. Not live: the contest rules (no contest in progress; TC-039-044 at cost 2), the 8 h limit and the 60 s without a client (TC-039-033 at cost 2): named on #39 for the operator.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-02';
            verify 'CL-039-09';
            verify 'CL-039-20';
            verify 'CL-039-21';
            verify 'CL-039-22';
            verify 'CL-039-23';
        }
    }
    dependency CL_039_09_verified_by_TC_039_047 from 'CL-039-09' to 'TC-039-047';
    dependency CL_039_20_verified_by_TC_039_047 from 'CL-039-20' to 'TC-039-047';
    dependency CL_039_22_verified_by_TC_039_047 from 'CL-039-22' to 'TC-039-047';
    verification 'TC-039-048' {
        doc /* TC-039-048 — PSK Reporter use, reported SNR, his decodes by parity and the hearing state
             CL-039-20, CL-039-23, CL-039-09
             Setup: as TC-039-020 (no network, a local MQTT peer, hand-authored payloads, the actual station router) with the contact engine and #9 owner on the recording hardware double, virtual UTC, a dial of 14074000 Hz; a strategy run with Auto on calling K1ABC from Tx 1500; a contest run (the WW Digi built-in) for the subscription; hand-authored waterfall rows.
             Steps: parse spots with rp -5, -99, 99, absent, 100, "x" and 2.5; spots to K1ABC from other senders at 14075200 Hz with t_tx in an even and in an odd period, twice the same offset in both parities; pskr.json of schema 1, schema 2 with use false, broken; POST /pskr/use {use false} and true, with an extra key, another profile, a stale boot, from the MCP principal; GET /pskr; a pskr.state subscriber; Use off and on during the run, and the subscription of a contest run's target; hearing with the feed connected and no spot, a spot 60 s old with rp -12, 601 s old, the feed not connected, a target call with a slash; the slot with his decoded offset of my Tx parity at the quietest slot, of the other parity there, and none.
             Expected: rp -5, -99 and 99 kept; absent, 100, "x" and 2.5 read as unknown and the spot still counts; offsets [1200] with their parities, the same offset kept once per parity; schema 1 reads use true and is written as schema 2 at the next change, use false read, the broken file reads enabled true and use true with invalid_pskr; use saved and returned by GET /pskr and pskr.state, the refusals 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id, 401 for MCP; with Use off no target subscription (UNSUBSCRIBE seen) and the run's hearing state unknown, with Use on SUBSCRIBE pskr/filter/v2/+/+/+/K1ABC/# again, also for the contest target; hearing {no, null, null}, {heard, t, -12}, {no}, {unknown}, {unknown}; when the only slot left lies within 50 Hz of his offset of my Tx parity Tx stays on 1650 with slot_check.moved false (no fallback, WstxStrategy::TxMoveRule), else the next quietest slot with his_end yes, the other parity's offset not excluding, his_end unknown without spots. Red on the parent: rp, use and the parity do not exist.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-20';
            verify 'CL-039-23';
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/pskr_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_039_20_verified_by_TC_039_048 from 'CL-039-20' to 'TC-039-048';
    dependency CL_039_09_verified_by_TC_039_048 from 'CL-039-09' to 'TC-039-048';
    verification 'TC-039-049' {
        doc /* TC-039-049 — Hold Tx on in a run: Tx stays, Rx on the station, Tx alone moves when he does not hear us
             CL-039-08, CL-039-09, CL-039-21, CL-039-22
             Setup: as TC-039-022 (the actual station router, contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz, hand-authored waterfall rows), Hold Tx on (the default), Tx 1500, FT8 and FT4; a strategy run with Auto on (leave {calls 4, calls_heard 8}, tx_move_every {heard 0, not_heard 1, no_reports 1}), a copy of the contest built-in WW Digi with cq_when_idle false, the built-in itself (cq_when_idle true), a pounce, a plain MCP run; the saved strategy "Casual 20 m" (class strategy, cq_when_idle true) for the CQ.
             Steps: (a) select K1ABC (CQ at 1800 Hz). (b) 2 repetitions with no spot, the quietest slot 1400, then 1300. (c) A repetition whose quietest slot lies within 50 Hz of Rx (1800 signal). (d) A spot of my call at K1ABC 60 s old. (e) His report after the 1st repetition, then silent periods. (f) Select a station at 1520 Hz (within 50 Hz of the held Tx), and a caller at 1530 Hz. (g) The held Tx at 2700 (FT4), a station at 1000; then an unanswered repetition with no spot. (h) The CQ when idle from the held Tx 900, one parity loud; callers at 1200 and at 920. (i) Hold Tx switched off during the contact, then the next repetition. (j) The contest copy: (a) and (b); the contest built-in: (h) (its CQ from the held Tx 900, callers at 1200 and at 920). (k) Pounce on K1ABC. (l) Plain MCP run.
             Expected (hand-worked from the operator's rule, #39 holdtx round 1): (a) Tx 1500, Rx 1800, no set_frequency of Tx, tx_slot.hz 1500; (b) Tx 1400 then 1300, Rx 1800 both times, slot_check {repetitions, hears_us false, hz}; (c) that slot excluded, the next quietest chosen; (d) Tx stays, hears_us true; (e) Tx never moves after the report; (f) Tx to the nearest slot 50 Hz clear of the station's signal (the lower on a tie), Rx on the station; (g) Tx 2700 kept at the selection, Rx 1000; at the repetition Tx moves to the quietest slot inside 500..2610 (2700 is no candidate, round 3 Q6), Rx stays 1000; (h) the CQ keyed on 900 with no slot decision; the caller at 1200 answered from 900, Rx 1200; the caller at 920 moves Tx to the nearest slot 50 Hz clear of it, Rx 920; (i) Tx and Rx together on the slot (Hold Tx off rule); (j) the copy as (a) and (b), the built-in as (h); (k) Tx stays 1500, Rx on K1ABC, never moved; (l) tx_slot null, Tx kept. Red on the parent: (a), (b), the selection of (g), (h), the built-in of (j) and (k) set Rx = Tx on the slot (the repetition of (g) is green on the parent, which also moves Tx into the range).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-08';
            verify 'CL-039-09';
            verify 'CL-039-21';
            verify 'CL-039-22';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/automation_tests.rs::tc_039_010_a_plain_policy_run_keeps_its_tx_on_the_called_station";
    }
    dependency CL_039_08_verified_by_TC_039_049 from 'CL-039-08' to 'TC-039-049';
    dependency CL_039_09_verified_by_TC_039_049 from 'CL-039-09' to 'TC-039-049';
    dependency CL_039_22_verified_by_TC_039_049 from 'CL-039-22' to 'TC-039-049';
    verification 'TC-039-050' {
        doc /* TC-039-050 — Quietness above the passband floor (#66 replaces the usual level)
             CL-039-09
             Setup: the slot function and the per-period waterfall power with hand-authored detailed rows (levels in dB per bin, written in the test), FT4 and FT8, no decoded station unless a step names one; the actual station router for the status. Floor oracle: a flat floor F gives the floor F + 0.65 exactly (the lowest tenth of every segment is F); a sloped table's floor is a reference vector from an independent least-squares fourth-order fit (numpy.polynomial, version recorded with the vector) through the lowest-tenth points of its ten segments, plus 0.65 dB, stored next to the test with its source.
             Steps: (a) the FT4 roll-off table: a floor of 30 dB flat to 2400 Hz and falling linearly to 15 dB at 2700 Hz (5 dB per 100 Hz, a sharp knee the fourth-order floor cannot follow: the roll-off slots read about 2 dB below it) in all 4 counted Rx periods, and AA3B 12 dB above the floor at 2621 Hz (width 90), not decoded, the reproduction of 2026-11-07 (tx_slot 2610 power_db 29); twice: the current Tx 1500 on the flat floor, and the current Tx 1500 on an undecoded station 18 dB above the floor at 1500.5..1590.5 Hz (an FT4 signal; level and position chosen so that the parent's rule makes the same choice). The fixture is authored so that every candidate deciding the choice (those no farther from the current Tx than the chosen slot) has its compared value, its largest rise clamped at 0, at least 0.1 dB from a half dB (the vector's margin_db), so the whole-dB rounding of the choice is unambiguous. (b) FT8 flat floor 30, the current Tx 1500 on a slot 5 dB above the floor in all 4 periods, every other slot on the floor. (c) Busiest period: slot A on the floor in 3 periods and 6 dB above it in one, slot B 3 dB above it in all 4, every other candidate covered 10 dB above the floor. (d) The floor 30 in the two older periods and 32 in the two later, everywhere. (e) One counted period only, the current Tx on a slot 4 dB above the floor. (f) A period I transmitted in; a 5th older Rx period quiet at another slot; after the Tx parity changed, my last counted Rx periods 3 minutes old. (g) A station band change. (h) Values 0.4 against 0.0 (a tie) and 0.6 against 0.0. (i) Coverage: one period whose levels end at bin 921 (2698.2 Hz) and one whose levels end at bin 920 (2695.3 Hz), the other periods unchanged; a flat-floor period with one segment where only its 8 lowest bins sit at the floor (the minimum of 8 points from that segment). (j) No counted period. (k) The status of each.
             Expected (hand computation recorded in the test, the floor from the reference vector): (a) the roll-off slots below the floor read 0 (clamped), the same as the free mid-band slots, never lower; the slots on AA3B stay positive; with Tx 1500 on the flat floor Tx stays 1500 (value 0, the current Tx kept); with Tx 1500 on the station Tx goes to 1410 (value 0), the free slot nearest 1500, the lower on equal distance; never a slot in 2400..2610 and never 2530 (raw level alone would choose 2530 at 21 dB on the roll-off; the unclamped floor rule chose 2530 at about -2); (b) Tx leaves 1500 for the nearest floor slot, value 0 (rise -0.65 clamped), the slot at 1500 value 4; (c) B wins, values 2 against 5 (the mean would choose A); (d) a floor slot reads 0 in every period (rise -0.65), not raised by the floor change; (e) one period compares: Tx leaves for the nearest floor slot; (f) the transmitted period, the 5th older period and the 3-minute-old periods never count: no power, Tx kept, power_db null; (g) after the band change only later periods count; (h) 0.4 ties and keeps the current Tx, 0.6 does not; (i) the period ending at bin 921 counts and the one ending at bin 920 does not (its slot values and decodes absent from the result, periods now one less); the 8-point segment fits the floor of the hand computation (the cutoff is its 8th lowest level); (j) the current Tx kept, power_db null; (k) tx_slot.power_db is the whole-dB value of the chosen slot, never negative; free_tx_slots rise_db the same value while level_db and floor_db are the busiest period's as measured (level_db 30 and floor_db 31 on the flat floor of 30). Red on the parent: (b) and (e) keep the current Tx (every rise 0 over its own usual level); (a) is a regression guard, green on the parent and red on the unclamped floor rule.
             #82: (k) free_tx_slots carries no per-slot numbers; only tx_slot.power_db is checked, and the chosen floor slot lies in an open range of the same build when it overlaps no decode.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_039_050 from 'CL-039-09' to 'TC-039-050';
    verification 'TC-039-051' {
        doc /* TC-039-051 — Live Hold Tx in Auto on HB9BLA
             CL-039-08, CL-039-09, CL-039-21, CL-039-22
             Setup: the gated candidate installed on HB9BLA, IC-7300, FT4 or FT8 within the operator's standing transmit consent, Hold Tx on, PSK Reporter on, Auto off at start; contact and run snapshots read from GET /contact and GET /automation at each step.
             Steps: select the saved strategy "Farthest new on band" (as TC-039-047), Auto on, let it call stations to one logged QSO and through a station that does not answer; note tx_hz and rx_hz before and after each selection and at each repetition; select "Casual 20 m" and let it call CQ; switch Hold Tx off and let it call one station; HALT.
             Expected: with Hold Tx on tx_hz unchanged by a selection unless the station is within 50 Hz of it, rx_hz the station's decoded frequency; at a repetition with slot_check.hears_us false only tx_hz changes and its signal stays at least 50 Hz from the Rx signal; after an answer or with a spot tx_hz unchanged; the CQ keyed on the held tx_hz; no chosen slot overlapping a station decoded in my Rx periods when a slot with a lower rise and none exists (power_db the rise); with Hold Tx off rx_hz equals tx_hz on the slot.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-08';
            verify 'CL-039-09';
            verify 'CL-039-21';
            verify 'CL-039-22';
        }
    }
    dependency CL_039_08_verified_by_TC_039_051 from 'CL-039-08' to 'TC-039-051';
    dependency CL_039_09_verified_by_TC_039_051 from 'CL-039-09' to 'TC-039-051';
    dependency CL_039_22_verified_by_TC_039_051 from 'CL-039-22' to 'TC-039-051';
    verification 'TC-042-001' {
        doc /* TC-042-001 — New DXCC and CQ zone against a hand log
             CL-042-01
             Setup: the bundled cty.dat; a worked set from a hand log: DL1ABC 40m FT8 unconfirmed (Fed. Rep. of Germany, EU, CQ 14, ITU 28), JA1XYZ 20m FT8 confirmed (Japan, AS, 25, 45), F1ABC 40m FT4 confirmed (France, EU, 14, 27), K2ABC with no band (United States, NA, 5, 8), Q1ABC 40m FT8 (no entity); station HB9BLA JN47AA on 40m FT8; rows CQ DL2XYZ, CQ F5ABC, CQ JA2ABC, CQ VK2ABC (Australia, OC, 30, 59), CQ K1ABC, CQ XX1ABC (no entity), CQ DL1ABC. A browser case: the editor offers what must be new and the station keeps it.
             Steps: evaluate strategies of new [dxcc] per ever, per band and per band_mode, and new [cq_zone] per ever, new means not_worked; the same with the station band unknown and with the log unreadable.
             Expected (entity columns of the cited cty.dat lines; the log of the test): [dxcc] ever VK2ABC only; [dxcc] band JA2ABC VK2ABC K1ABC; [dxcc] band_mode also F5ABC; [cq_zone] ever VK2ABC only; XX1ABC never; band unknown: band and band_mode never new, ever unchanged; log unreadable: nothing new.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/ui-operating.test.cjs";
    }
    verification 'TC-042-002' {
        doc /* TC-042-002 — Ignore lists in the evaluator, the store, the routes and strategy runs
             CL-042-02
             Setup: hand-authored rows CQ K1ABC FN42, CQ DL1XYZ JO62, CQ NA W1AW FN31, HB9BLA VK2ABC QF56; the station HB9BLA JN47AA on 40m; the actual station router, contact engine and #9 transmit owner on the recording hardware double (virtual UTC; no audio, PTT or radio); synthetic monotonic instants for the session expiry.
             Steps: parse the configuration with ignore_calls and session_ignore_minutes and refuse a duplicate, a lower-case or a 14-character call, 101 calls, minutes 0 and 721; read a saved pre-#42 file without both keys and with only one of them; evaluate a new_call strategy with K1ABC on the permanent list, on the session list and on both, and with W1AW (greyed) ignored; the session list: add, renew, remove, expiry at the minute boundary, 65 adds, a band change and a band unknown; POST /strategy/ignore accepted and refused (extra key, bad call, wrong profile, stale boot), GET /strategy session_ignore; the station tick on another band; a strategy run with the strongest candidate ignored, and with an ignored caller.
             Expected: the round trip keeps both keys; the refusals name ignore_calls[i], ignore_calls and session_ignore_minutes; the pre-#42 file reads with [] and 30, the one-key file is invalid_configuration; K1ABC rank null, grey false, why "K1ABC is ignored (permanent list)", "(session list)", session first when on both; W1AW also not greyed when ignored; an entry ends exactly at added + minutes and reports remaining_s rounded up; renewal moves it last with a new expiry; the 65th add drops the oldest; a band change (also to unknown) empties the list; the route returns the snapshot at an unchanged revision with the refusal codes and fields of PUT /strategy; a run selects the next candidate, never the ignored one, and the other caller, never the ignored one; no transmit key in any evaluation.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    verification 'TC-042-003' {
        doc /* TC-042-003 — Band Activity Ignore and the Settings ignore lists
             CL-042-02
             Setup: the browser fixture of the operating screen with the actual isolated station and its fixture live decodes; a strategy active.
             Steps: right-click a decoded row with a resolved sender; choose Ignore; open the menu again on that row; open Settings > General; enter two calls in the permanent list; change the session minutes; remove the session entry.
             Expected: the menu offers Reply, Select, Set Rx here, "Pounce <call>" (#42 CL-042-03) and "Ignore <call>", Ignore sends POST /strategy/ignore {call, ignore true} and does not set the Rx frequency; the row loses its strategy mark after the station's new verdicts; the menu then offers "Stop ignoring <call>"; Settings lists the call with its remaining minutes; the permanent list saves with PUT /strategy as ignore_calls in upper case, the minutes as session_ignore_minutes; remove sends ignore false and the list is empty; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    requirement 'CL-042-03' {
        doc /* Pounce waits for one chosen call and answers it: an operator action (Band Activity right-click "Pounce <call>") starts a station automation run with pounce <call> on the current band and mode (one run at a time, so never beside a strategy run, and needing a known band); when that call is decoded sending a CQ that the directed-CQ rule leaves to me, or an RR73/73 ending another QSO (then my Tx frequency is held), and it is on no ignore list, the station answers it as a double-click does (select_row, enable_tx; the contact engine calls in the next own period and Auto Seq runs the QSO). The pounce ends when that contact completes, on a station band change (band_changed), on HALT, the Tx watchdog or the operator's Stop pounce; a contact without an answer for max_unanswered_periods partner periods is cancelled and the pounce waits again. While it runs the QSO pane and the strategy element show it. Details: WstxStrategy::Pounce, WstxMcp::AutomationConfiguration, OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/mcp.rs; client/contact.js";
    }
    dependency CL_042_03_to_FR_007 from 'CL-042-03' to 'FR-007';
    dependency CL_042_03_to_FR_020 from 'CL-042-03' to 'FR-020';
    verification 'TC-042-004' {
        doc /* TC-042-004 — Pounce at the station: configuration, answer, ignore, band change and end
             CL-042-03
             Setup: hand-authored rows; the station HB9BLA JN47AA on 40m; the actual station router, contact engine and #9 transmit owner on the recording hardware double (virtual UTC; no audio, PTT or radio); FT8 live job; the browser's grant.
             Steps: parse configurations with pounce absent, null, K1ABC, lower case, 2 characters, K1ABC/R and with K1ABC in blocked_calls; start a pounce with the station band unknown; start a pounce on K1ABC on 40m; publish CQ W1AW FN31 and CQ DL1XYZ JO62; publish CQ K1ABC FN42; run the own period; the partner's report, RR73 and the own 73 period; start again and configure or start a second run while it waits; publish W1AW K1ABC RR73; a pounce on K1ABC with K1ABC on the session ignore list and a CQ K1ABC; a pounce with CQ NA K1ABC (not for EU); a pounce waiting when the station band changes to 20m; a pounce in its contact with max_unanswered_periods 2 and two partner periods without an answer.
             Expected: absent and null read as no pounce, K1ABC accepted, the others invalid_request pounce; not_ready band; the run waits with pounce {K1ABC, 40m} and selects nothing for the other calls (candidates 0); CQ K1ABC is selected (replying, Tx1 "K1ABC HB9BLA JN47", armed) and the own period keys "K1ABC HB9BLA JN47"; the completed contact stops the run completed; a second configure or start is state_conflict run; after the RR73 to W1AW K1ABC is selected with my Tx frequency kept; an ignored K1ABC and the CQ NA are never selected (the run keeps waiting); the band change stops band_changed; two unanswered partner periods disarm and cancel the contact and the run waits again for K1ABC.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-03';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_042_03_verified_by_TC_042_004 from 'CL-042-03' to 'TC-042-004';
    verification 'TC-042-005' {
        doc /* TC-042-005 — Band Activity Pounce and the pounce line in the QSO pane
             CL-042-03
             Setup: the browser fixture of the operating screen with the actual isolated station and its fixture live decodes; the automation routes are hand-written fixtures.
             Steps: right-click a decoded row with a resolved sender; choose Pounce; confirm; announce the started run; open the menu again; choose Stop pounce in the QSO pane.
             Expected: the menu offers "Pounce K1ABC"; it asks once per page session; configure sends exactly {modes [ft8], ranking first_seen, min_snr_db null, allowed_calls [], blocked_calls [], max_contacts 1, max_unanswered_periods 5, completion_action stop, max_run_minutes 480, strategy false, pounce K1ABC}, then start with the shown safety revision; no contact command (no enable_tx) is sent by the browser; the QSO pane reads "Pouncing on K1ABC (40m) · waiting for CQ or 73", the status "Pounce K1ABC waiting · HALT ends it"; the menu then offers "Stop pouncing K1ABC"; Stop pounce sends stop with the run id; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_042_03_verified_by_TC_042_005 from 'CL-042-03' to 'TC-042-005';
    verification 'TC-042-006' {
        doc /* TC-042-006 — Alert at the station: candidates, dedupe, ignore and directed-CQ rule, history and routes
             CL-042-04
             Setup: hand-authored rows and strategies; the station HB9BLA JN47AA on 40m; the actual station router and contact engine on the recording hardware double (virtual UTC; no audio, PTT or radio); FT8 live job; no grant in the selection path, so no run transmits.
             Steps: publish CQ JA1XYZ PM95 before any strategy is active, then select the strategy "Alerts" (goal new_call); publish in one period CQ K1ABC FN42 (-12 dB), CQ DL1XYZ JO62 (-3 dB), CQ NA W1AW FN31, CQ G4ABC IO91 with G4ABC on the session ignore list and HB9BLA VK2ABC QF56; publish CQ K1ABC FN42 30 s later and 10 minutes after the first; change the band to 20m and publish CQ K1ABC again; read GET /strategy/alerts and wstx_read alerts; clear with an extra key, a wrong profile, a wrong boot and correctly; read GET /strategy/alerts with the MCP principal's cookie and POST the clear with it; publish 101 CQs from different calls in one period.
             Expected: no alert for JA1XYZ; alerts exactly K1ABC {utc of the period, message "CQ K1ABC FN42", rule "Alerts", band 40m, mode ft8, snr_db -12, dxcc United States} and DL1XYZ (Fed. Rep. of Germany), ids 1 and 2, revision 2, none for W1AW, G4ABC or the message to me; nothing 30 s later; a third K1ABC alert 10 minutes later and a fourth on 20m; wstx_read alerts equals the browser's GET; the refusals 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id leave the history; the clear empties it with revision + 1; the MCP cookie may GET and is refused 401 on the clear; after 101 alerts the history holds the last 100; no contact, no selection and no keying throughout.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-04';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    verification 'TC-042-007' {
        doc /* TC-042-007 — The Settings alert history, sound and browser notification
             CL-042-04
             Setup: the browser fixture of the operating screen with the actual isolated station; the strategy and alert routes are hand-written fixtures; the page's Notification and AudioContext are recording test doubles (no sound device).
             Steps: open Settings > General with one alert in the history; announce alert.state with a second alert; tick Sound and announce a third; tick Browser notification (the double grants) and announce a fourth; make the page hidden and announce a fifth; reload; Clear.
             Expected: the editor offers no alert setting; Sound and Browser notification are unchecked by default and the history line reads "12:00:00 K1ABC CQ K1ABC FN42 · CQ · 40m FT8 · -12 dB · United States"; the second alert is listed first with no tone, no notification and no permission request; the third plays one tone and no notification; the permission is asked exactly once, on the click; the fourth plays one tone and shows one notification "Alert JA1XYZ" with body "CQ JA1XYZ PM95 · CQ"; the hidden page's fifth plays no tone and shows one notification; after the reload both checkboxes stay as chosen and nothing is announced; Clear sends exactly {v, profile_id, boot_id} to POST /strategy/alerts/clear and the list is empty; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    verification 'TC-039-001' {
        doc /* TC-039-001 — Strategy configuration is exact
             CL-039-01
             Setup: hand-written configuration JSON with a schema 4 strategy, the parser only.
             Steps: parse the valid configuration and serialize it; parse variants each with one refused value: an extra key of the configuration (highlight), two strategy names equal ignoring case, 17 strategies. The refusals of the strategy's own fields are TC-097-001's.
             Expected: the valid one round-trips to the same JSON; each refusal names exactly its field path (configuration, strategies[1].name, strategies).
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_001 from 'CL-039-01' to 'TC-039-001';
    verification 'TC-039-002' {
        doc /* TC-039-002 — Continent, directed-CQ tables and verdicts
             CL-039-02, CL-039-03
             Setup: hand-authored codec-packed rows for HB9BLA JN47AA (continent EU) on 40m: CQ K1ABC FN42 -12, CQ DL1XYZ JO62 -3, CQ NA W1AW FN31 -5, CQ EU G4ABC IO91 -8, CQ DX OH1AA KP20 -1, CQ DX JA1XYZ PM95 -15, W1AW K1ABC RR73 -6, HB9BLA VK2ABC QF56 -20, CQ TEST N1MM FN31 -2; continents from the cty.dat entities of the senders.
             Steps: continent (cty.dat entity) of HB9BLA K1ABC OH1AA JA1XYZ VK2ABC PY1AA ZS6AA CE9AA UA9ABC Q1ABC K1ABC/MM; DirectedCqRule for plain/EU/NA/DX/JA/TEST/POTA with known and unknown continents, an EU profile and a non-EU (K1ABC, NA) profile; MyContinent from a configured value, a callsign, and a locator with a call without entity; a new_call strategy with and without Treat 73 as CQ; my continent unknown; the reasons; an operator's selection of a CQ that is not answerable.
             Expected (hand table, continent column of the cited cty.dat lines): EU NA EU AS OC SA AF SA AS, none, none; for K1ABC: CQ NA and CQ DX from JA answerable, CQ EU and CQ DX from NA not; a call without entity: JN37 EU, FN42 NA, PM95 AS, QF56 OC, GG87 SA; none without call and locator; verdict order: VK2ABC (caller), then the candidates strongest first, rows 2, 4 and 8 greyed; with Treat 73 as CQ the RR73 of K1ABC has a rank and a call to me is never cq-like; unknown continent greys rows 2,3,4,5,8; reasons "calls my call", "needed: new_call", "CQ NA — not for EU"; the callsign guard refuses K1, ABCDE and W1AW/R; the selection warning as written in the test.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-02';
            verify 'CL-039-03';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-039-003' {
        doc /* TC-039-003 — Strategy store, routes and evaluation
             CL-039-01, CL-039-02, CL-039-03
             Setup: actual station router on a disposable selected HTTPS profile (HB9BLA, JN47AA) with one grant, the browser cookie and Origin; injected FT8 live job with rows CQ K1ABC FN42, CQ NA W1AW FN31, HB9BLA G4ABC IO91, CQ DL1XYZ JO62.
             Steps: GET /strategy; PUT a configuration; read strategy.json; open a new owner; PUT with a stale revision, another profile, another boot, v 2, an extra key, a foreign Origin; GET without credentials; PUT continent AS; evaluate the saved strategy, a draft with explain, another job id, a 2049-record range; an old schema 1 strategy.json; a strategy.state event after a change.
             Expected: default {null,null,[]} revision 0 with my_continent EU; revision 1 and the file {schema_version 3, profile_id, revision 1, configuration with active null}; the new owner reads it with active None; 409 stale_revision, 403 wrong_profile, 409 state_conflict boot_id, 400 unsupported_version, 400 invalid_request, 403, 401; my_continent AS; verdicts {caller 2 rank 0, candidates 3 and 0 by SNR, 1 grey} in display order; the draft lists all four with reasons; 409 stale_request; 400 next_sequence; the old file reads with strategies dropped, active None, continent and ignore lists kept; no PTT exchange.
             2 — Isolated automated functional tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-02';
            verify 'CL-039-03';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_003 from 'CL-039-01' to 'TC-039-003';
    verification 'TC-039-004' {
        doc /* TC-039-004 — Strategy runs
             CL-039-03, CL-039-05
             Setup: as TC-039-003 with the contact engine and #9 transmit owner on the recording hardware double (virtual UTC set 1 s after an even FT8 period E; own periods odd); the strategy selected from the browser path (cookie grant) with "Test calls" (class strategy: new [call] per ever, Treat 73 as CQ, order [snr], leave {calls 2, calls_heard 4}, retry_minutes 1, Calling stations are answered on) and Auto switched on from the browser (POST /strategy/auto).
             Steps: (a) PUT with active and Auto on: the run starts, no CQ; publish CQ NA W1AW (strongest), CQ JA JA1XYZ, CQ 290 N1MM, CQ DL1XYZ, CQ K1ABC; two empty partner periods; CQ K1ABC and W1AW DL1XYZ RR73 at 1700 Hz; CQ K1ABC alone afterwards, before and after its quiet minute; PUT None; PUT active again and Auto on; HALT; Esc. (b) A QSO to its end, then the next station, repeatedly past the former limits; the deadline seam moved past 480 minutes. (c) A caller against a candidate; a browser select_row and enable_tx during the run's contact and while it waits; the partner's RR73; a new CQ; a run contact cancelled by the browser followed by the same station's CQ and its call to me; a browser selection racing the run's select_row and enable_tx; stop and Halt while manual. (d) Selecting with no receive; receive starts; the live identity changes during a contact; Auto on without a grant transport; an MCP configure with strategy true; an MCP stop then start; a station restart. (e) A station completed on 40m, as a caller on 40m and as a CQ and a caller on 20m; a retune with a station in its quiet time and with a station the operator gave up. (f) A new proof of the grant during a contact; past the transport's 8 h; the grant revoked.
             Expected: (a) no CQ is ever armed; DL1XYZ or K1ABC selected by value (W1AW, JA1XYZ and N1MM never); after two unanswered periods disarmed, waiting, left {DL1XYZ or K1ABC, repetitions}, no stop reason; the next publication goes to the other station with Rx and Tx on its slot; the left station is not called while in its quiet time, also alone, and is called again after it; None stops the run, disarms and turns Auto off; HALT stops halted, turns Auto off with a new revision and keeps active; Esc leaves active, Auto and the run. (b) The run stays waiting after each completion, no limit_reached, no time_limit. (c) the caller first (it passes the filters, TC-097-007); a double-click during the run: the run is manual, the strategy stays active, the run neither disarms nor cancels; the manual QSO completed: the run waits and answers the next match; the operator's cancel of the run's contact: that station is not selected again, also not as a caller; the race leaves the operator's contact and the state manual, no stop; Halt while manual stops halted. (d) waiting with reason no_receive and no contact; waiting without a reason after receive starts and it answers; the contact disarmed and cancelled at once and the run waiting on the new identity; strategy_refusal transmit_unavailable, Auto off, the strategy still selected; operator_required strategy, also for the start, nothing armed, an MCP policy of its own starts as ever; active None and Auto off after the restart. (e) not answered again on 40m, called and answered on 20m; the station in its quiet time on 40m is called on 20m, the given-up one is not. (f) the run and its contact go on through the proof and the deadline; the revocation stops authority_lost, disarms and turns Auto off. No PTT exchange.
             #39 holdtx: these steps run with Hold Tx explicitly off (they test the run logic; Rx = Tx on the slot); with Hold Tx on a selection keeps Tx and puts Rx on the station: TC-039-049.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-03';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_05_verified_by_TC_039_004 from 'CL-039-05' to 'TC-039-004';
    verification 'TC-039-006' {
        doc /* TC-039-006 — Strategy selector, value marks, editor popup and Most Wanted in the browser
             CL-039-01, CL-039-04, CL-039-05, CL-039-10
             Setup: actual isolated server and Chromium at 1366x768 (and 360x740 for the popup); routed fixtures: an FT8 live job with CQ K1ABC FN42, CQ NA W1AW FN31, CQ DL1XYZ JO62, a strategy view (revision 4, "DX first", none active), station verdicts [2 rank 0, 0 rank 1, 1 grey] (with reasons when explain), the automation owner. A second case uses the real station store.
             Steps: wait; select "DX first"; click the Freq column; click Value; open the editor; read the preview; resize to 360 px; change a goal; Save; Close; announce automation.state with a waiting run; strategy.state with active null (a HALT); select None. Second case: choose continent AS in Settings > General; the Most Wanted section: a failed Update Most Wanted (routed, no network), a successful one. Third case: a new row published while an evaluation is held.
             Expected: no evaluation request and no mark while none is active; selecting sends one PUT {expected_revision 4, active "DX first"} and asks nothing; no POST /automation/command and no enable_tx from the browser; one evaluation {the live identity, 0..3, strategy null, explain false}, none on a timer; rows DL1XYZ, K1ABC marked in that order, W1AW greyed; a column click sorts by the column with the marks kept, Value returns to the station's order; the editor holds exactly the settings of Strategy; the popup HALT has the top-bar state; preview rows with their reasons from a draft evaluation with explain; no horizontal overflow at 360 px; an edit re-runs the preview; Save sends exactly the edited strategy and does not select; the run state reads "Strategy DX first waiting" after the event, GET /automation only on the event; strategy.state re-reads GET /strategy and the selector shows None. Second case: PUT saved continent AS (my_continent AS) and no browser storage key; the button reads Update Most Wanted and the status "No list; strategies call the strongest first"; no upload control; the failure shows its reason in one line and the status stays; after a success the status reads "List from <date> · 2 entries · 1 not mapped to an entity". Third case: a second evaluation with the larger next_sequence when the first ends and the new row marked.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-04';
            verify 'CL-039-05';
            verify 'CL-039-10';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_039_01_verified_by_TC_039_006 from 'CL-039-01' to 'TC-039-006';
    dependency CL_039_05_verified_by_TC_039_006 from 'CL-039-05' to 'TC-039-006';
    verification 'TC-039-007' {
        doc /* TC-039-007 — Live strategy on HB9BLA
             CL-039-03, CL-039-04, CL-039-05, CL-039-06
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 on 40 m FT8, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), operator consent; Tx watchdog 6 repetitions (the profile default).
             Steps: duplicate a built-in to a strategy of class strategy (new [call] per ever, region dx, Treat 73 as CQ); select it with Auto off for two periods; switch Auto on; let it work two stations; HALT; switch Auto on again; Esc during a QSO; select None; in Settings > General click Update Most Wanted once.
             Expected: the stations it would call are marked and on top by value, CQ NA/AS and same-continent CQ DX greyed; nothing is transmitted with Auto off; no CQ is transmitted; it answers callers first, then the best candidate, to a logged QSO, and goes on; HALT stops at once, Auto turns grey and the selector keeps the strategy; Esc aborts the QSO, gives the station up and the strategy goes on; None stops it and Auto turns grey; a station restart leaves None and Auto off; Update Most Wanted fetches the list once and the status shows its date, its entries and how many are not mapped.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-03';
            verify 'CL-039-04';
            verify 'CL-039-05';
            verify 'CL-039-06';
        }
    }
    dependency CL_039_05_verified_by_TC_039_007 from 'CL-039-05' to 'TC-039-007';
    requirement 'CL-055-02' {
        doc /* Each decoded record of a resolved sender carries its entity (shown name, continent, CQ and ITU zone, entity distance) and the WSJT-X new-* flags that hold against the internal log (new call, grid, DXCC, continent, CQ zone and ITU zone, each ever and on this band), only the true ones, for the #50 row colours. Band Activity's DXCC column shows the shown name; Distance uses the message grid and otherwise the entity distance marked approximate; the QSO pane header shows the partner's country and continent. The strategy's continent condition and the directed-CQ rule use the sender's entity (WstxValueOrder::ContinentOfCall). Details: WstxLogControl::DecodedEntity; WstxOperatingLayout BandActivity. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/dxcc.rs; server/src/receive_http.rs; server/src/strategy.rs; server/src/decoder/payload.rs; client/recording.js; client/contact.js";
    }
    dependency CL_055_02_to_FR_010 from 'CL-055-02' to 'FR-010';
    dependency CL_055_02_to_FR_019 from 'CL-055-02' to 'FR-019';
    requirement 'CL-055-03' {
        doc /* Settings > General shows the cty.dat in use (its date, bundled or uploaded, entity count) and replaces it by a file upload that the station validates first, or returns to the bundled file; there is no automatic download. A refused upload changes nothing; an unreadable stored upload leaves the bundled file in use and is reported. Details: WstxCountryFile::CountryFile, CountryFileHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/main.rs; client/logbook.js";
    }
    dependency CL_055_03_to_FR_016 from 'CL-055-03' to 'FR-016';
    verification 'TC-055-002' {
        doc /* TC-055-002 — Decoded records carry entity and new-* flags
             CL-055-02
             Setup: actual router with a selected profile (HB9BLA JN47AA) whose log holds DL1ABC JO62 20m FT8, K1ABC FN42 40m FT8 and W1AW FN31 20m FT4; a live FT8 job with CQ K1ABC FN42, CQ DL2XYZ JO62, CQ JA1XYZ PM95, HB9BLA G4ABC IO91, a free text and CQ W1AW FN31; a hand log for the worked categories.
             Steps: read /receive/results without a band, then with the selection band 20m; log DL2XYZ on 20m and read again; worked categories from the hand log.
             Expected: K1ABC dxcc {U.S.A., NA, 5, 8, 7706 km} without flags (no band), then only new_call_band and new_grid_band (the US is worked on 20m); W1AW worked on 20m in FT4 has no flag (band, not mode); DL2XYZ Germany 465 km with only new_call and new_call_band, none after it is logged; JA1XYZ all twelve flags; G4ABC new call, grid, DXCC and ITU zone (EU and CQ 14 worked); free text unchanged; calls compare case-insensitively, grids by square; Sicily counts as its own name. Every decoded sender call resolves (#55, live 2026-11-06): CQ HF6FIRAC Poland with new-* flags and no grid flag, a filled-in hash such as OH2DKQ <CT9/DL7VXX> -02 its entity, a nonstandard full call and a filled-in second hash likewise, a DXpedition hashed call the entity only; R330S <...> 73, OH2DKQ <...> -02 and the free text CQ SA7BKX JO6 no entity.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-02';
        }
        attribute executable : String = "server/src/dxcc_tests.rs";
    }
    dependency CL_055_02_verified_by_TC_055_002 from 'CL-055-02' to 'TC-055-002';
    verification 'TC-055-003' {
        doc /* TC-055-003 — Country file upload
             CL-055-03
             Setup: actual isolated router and profile directory; Chromium at 1366x768 on the isolated server.
             Steps: GET /dxcc; GET /dxcc?call= with DL/HB9BLA, K1ABC/MM and refused queries (empty, encoded slash, other key, 14 characters); PUT a one-entity file; PUT a file with an invalid continent, an empty file, a number and a file over 1 MiB; stale boot; wrong Origin; restart; PUT null; store an unreadable file and restart; revoked HTTPS grant; environment-only mode. In the browser: open Settings > General, upload an invalid then a valid file, then Use bundled file.
             Expected: bundled VER20250115 346; the upload is the file on disk and resolves HB9BLA to it and survives the restart; refusals 400 invalid_cty line 1 / invalid_request text, 409, 403 without change; null removes the file; an unreadable file stays and is reported with the bundled table; 401 and 404. The page shows "cty.dat 2025-01-15 · bundled with this station · 346 entities", the refusal with its line, "cty.dat 2099-12-31 · uploaded · 1 entities", then bundled again.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-03';
        }
        attribute executable : String = "server/src/logbook_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_055_03_verified_by_TC_055_003 from 'CL-055-03' to 'TC-055-003';
    verification 'TC-055-004' {
        doc /* TC-055-004 — DXCC column, approximate distance and QSO header in the browser
             CL-055-02
             Setup: actual candidate router with the contact engine (HB9BLA JN47AA); hand-authored rows published through the test control peer, including HB9BLA W1XYZ -10 without a grid; later the live K1WY rows KW8CW K1WY RR73 (exchange packed as the grid square RR73, 32373), CQ K1WY FN31 and SP6E K1WY +00 in one period and reversed in the next.
             Steps: wait for the rows; select CQ K1ABC FN42; publish the K1WY periods.
             Expected: W1XYZ row DXCC U.S.A. with title "U.S.A. · NA · CQ zone 5 · ITU zone 8 (cty.dat)" and distance "~7706 km"; DL1ABC Germany; K1ABC's distance from its grid without "~"; the QSO header "K1ABC · FN42" with its detail line starting "U.S.A. (NA) · <n> km · sent" (the exact distance, no "~"). In both K1WY orders: the RR73 and +00 rows "~7706 km", the CQ row "6188 km"; the unpacked RR73 square is the roger RR73 with unchanged text.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-02';
        }
        attribute executable : String = "tests/contact.test.cjs; server/tests/decoder_vectors.rs";
    }
    dependency CL_055_02_verified_by_TC_055_004 from 'CL-055-02' to 'TC-055-004';
    dependency CL_055_02_verified_by_TC_055_006 from 'CL-055-02' to 'TC-055-006';
    verification 'TC-055-005' {
        doc /* TC-055-005 — Live DXCC on HB9BLA
             CL-055-02, CL-055-03
             Setup: the gated candidate installed on HB9BLA, receive only (no transmission), the operator's contacts.adi.
             Steps: watch Band Activity for several periods on a busy band; compare rows against the log; open Settings > General.
             Expected: the DXCC column is filled for decoded calls; new-DXCC flags only for entities absent from the log and on-band flags only for entities not worked on this band; the country file date is shown.
             3 — Live, read-only on the station; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-055-02';
            verify 'CL-055-03';
        }
    }
    dependency CL_055_02_verified_by_TC_055_005 from 'CL-055-02' to 'TC-055-005';
    dependency CL_055_03_verified_by_TC_055_005 from 'CL-055-03' to 'TC-055-005';
    // #50/#10 operator feedback 2026-11-02 evening (US5WFL/YO3GNF, TC2TR, the 22:48 CQ run on 40 m).
    requirement 'CL-050-04' {
        doc /* Replacing an active contact (ChangeContact, select_row or enter_dx with replace true) keeps Enable Tx as it is: with Enable Tx on, the next period of the new contact's parity carries the new contact's next message, and after a transmission already on the air nothing more goes to the old partner. A double-click (or Reply) on another station's Band Activity row, idle, after a completed contact, during a contact or during my CQ, also when the rows are redrawn between its two clicks or during its second press, is that selection without a confirmation, followed by Enable Tx on (WSJT-X double-click with "Double-click on call sets Tx enable"), each request retried at most twice after a stale_revision refusal; Auto Seq then runs the QSO to its completion and log. During a station automation run an operator replacement of the run's contact ends the run, which disarms (WstxMcp, TC-020-003). A single click only offers "Change contact to <call>" during a contact and never turns Enable Tx on. Details: WstxStandardQso::ChangeContact, SelectDecodedRow, WstxOperatingLayout::BandActivity. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js";
    }
    dependency CL_050_04_to_FR_007 from 'CL-050-04' to 'FR-007';
    dependency CL_050_04_to_FR_008 from 'CL-050-04' to 'FR-008';
    requirement 'CL-010-17' {
        doc /* (#10) Call 1st (WSJT-X "CQ: First"), an operator setting next to Auto Seq, on at a profile's first start, then as saved (CL-110-01): while my own CQ runs with Enable Tx and Auto Seq on, the first decoded message to my call of a step, in decode order, whose exchange is a grid or a report is answered at once as a selection of that row with Enable Tx kept, so the next own period answers that caller. Off, a CQ moves only on an operator selection. Details: WstxStandardQso::CallFirst. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_010_17_to_FR_007 from 'CL-010-17' to 'FR-007';
    verification 'TC-050-004' {
        doc /* TC-050-004 — A double-click switches to another station with Enable Tx kept
             CL-050-04
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); the actual candidate Router, contact engine and #9 transmit owner on a recording hardware double with Chromium on the real clock (contact_http_tests::contact_browser_operating_flow, tests/contact.test.cjs).
             Steps: (a) engine: select "CQ K1ABC FN42", Enable Tx, send Tx1 in the odd period, then select "CQ DL1ABC JO62" (even period) with replace true and run two periods; then enter_dx W1AW with replace true; again switching 100 ms after my period start (PTT keyed, audio not started), also to "CQ DL1ABC JO62" decoded in an odd period; (b) browser: double-click "CQ K1ABC FN42"; after its Tx1 double-click "CQ DL1ABC JO62"; publish DL1ABC's report and RR73; then CQ right after that completed contact (armed, calling); on a second station and browser run at the same time: CQ and, while calling, double-click "CQ EA8BIA IL18" and run that QSO the same way; (c) browser, after the completed EA8BIA contact (disarmed, contact_completed): double-click "CQ G8KHF IO92" with the Band Activity rows redrawn during the second press (#50, operator 2026-11-03).
             Expected: (a) still armed, last_disarm_cause unchanged, the next odd period sends "DL1ABC HB9BLA JN47", no later period sends to K1ABC, the manual replacement keeps Enable Tx; the switch in the keyed window sends the new contact's Tx1 in that same period, still armed; a switch in the keyed window to "CQ DL1ABC JO62" decoded in an odd period (my own parity) still sends K1ABC's Tx1 in that period and DL1ABC's Tx1 in the next even period, still armed, never refused busy (#10); (b) each double-click sends select_row with replace true then enable_tx and shows no "Change contact" button; still armed, last_disarm_cause not contact_cancelled; the next own period sends "DL1ABC HB9BLA JN47", then "DL1ABC HB9BLA R-03" and "DL1ABC HB9BLA 73"; the contact completes and contacts.adi holds exactly one record for it; the same for EA8BIA from the CQ ("R+00"); (c) select_row with replace true then enable_tx, armed, and the next own period sends "G8KHF HB9BLA JN47".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-04';
        }
        attribute executable : String = "server/src/contact_tests.rs; tests/contact.test.cjs";
    }
    dependency CL_050_04_verified_by_TC_050_004 from 'CL-050-04' to 'TC-050-004';
    requirement 'CL-050-06' {
        doc /* (#37) The contact snapshot carries the QSO dialogue of the current contact, at most 16 entries: each partner message the engine counted (with SNR) and each of our transmissions of that contact as sent, with its period start and a repeat count; the QSO pane shows it while the QSO runs, oldest first and newest at the bottom, scrolling inside the card without growing the page, and drops it with the QSO. Details: WstxQsoControl::ContactSnapshot dialogue, WstxQsoPane::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js; client/recording.css";
    }
    dependency CL_050_06_to_FR_007 from 'CL-050-06' to 'FR-007';
    dependency CL_050_06_to_FR_019 from 'CL-050-06' to 'FR-019';
    verification 'TC-050-006' {
        doc /* TC-050-006 — QSO dialogue in the contact snapshot and the pane (#37)
             CL-050-06
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); the snapshot shape bound (contact_http_tests); the operating screen with a routed ContactSnapshot in Chromium.
             Steps: (a) engine: replay a QSO with K1ABC (select their CQ, Tx1 twice, their report, Tx3, their RR73, 73) and read the dialogue after each step; cancel a second contact; push 20 distinct entries; (b) the maximum snapshot shape with 16 maximal entries; (c) browser: a running QSO with a 10-entry dialogue at 1366x768 and 360 px, then the completed contact.
             Expected: (a) entries in order tx "K1ABC HB9BLA JN47" count 2, rx "HB9BLA K1ABC -05" with SNR, tx "K1ABC HB9BLA R-12", rx "HB9BLA K1ABC RR73", tx "K1ABC HB9BLA 73", periods the period starts; a new contact starts empty, cancel empties it, at most 16 entries (the oldest dropped); a received message repeated at SNR −12, −3 and null is one entry with count 3, its first period and SNR −3 (#60); (b) at most 4096 bytes; (c) rows of the #60 QSO table "HH:MM:SS | <recipient> ◂ <sender> | <exchange> | <Rep> | <Rx SNR> | <Tx SNR>" (my first sent "JN47" with Rep "×2" and no SNR yet, a received "-05" with Rx SNR "−5" and Tx SNR "−5", the last received "RR73" with Rep "×3", Rx SNR "+17" and the carried Tx SNR "−5") oldest first, the header row kept and the newest row visible, no page scroll, gone once completed.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-06';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_050_06_verified_by_TC_050_006 from 'CL-050-06' to 'TC-050-006';
    verification 'TC-010-010' {
        doc /* TC-010-010 — Call 1st answers the first caller of my CQ
             CL-010-17
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); hand-authored rows of the 2026-11-02 22:48 CQ run; the snapshot wire (contact_http_tests) on a fresh profile directory.
             Steps: Enable Tx with no partner (calling, odd parity), Hold Tx on; after my CQ deliver in one even period, decode order "HB9BLA EA4HTI IM69" (1678 Hz, -8) then "HB9BLA F1PBZ -13" (2144 Hz, -10), in reverse slice order; later "HB9BLA EA8BIA -11" and "HB9BLA SV1DZB KM18"; repeat with Call 1st off, with Auto Seq off, and with only "HB9BLA DL1ABC RR73", "HB9BLA DL2ABC 73", "HB9BLA DL3ABC RRR", "HB9BLA DL4ABC R-10".
             Also: the same callers after Enable Tx off (disarmed, still calling).
             Expected: Call 1st on: the contact is EA4HTI (grid IM69) in report with next Tx2 "EA4HTI HB9BLA -08" at once, still armed, Tx offset 1500 Hz kept, the next odd period sends it; the later callers change nothing; Call 1st off, Auto Seq off, Enable Tx off or only continuing exchanges: still calling (with Enable Tx off nothing is sent) and the next odd period sends "CQ HB9BLA JN47"; on a profile with nothing saved the snapshot settings carry call_first true.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-17';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_010_17_verified_by_TC_010_010 from 'CL-010-17' to 'TC-010-010';
    dependency CL_010_17_verified_by_TC_110_004 from 'CL-010-17' to 'TC-110-004';
    requirement 'CL-111-07' {
        doc /* A start that cannot transmit. When a reply or call_dx is admitted but transmission is not possible (no transmit capability, radio or authorization not ready, clock not synchronized, Tune on), the command is accepted, the QSO is prepared, the transmit state stays off with its cause unchanged, and the transmit view's refusal names the reason (busy while Tune is on). The operating view shows that reason beside the state. Nothing starts by itself when the reason goes away. call_cq, send_next and reset_repetitions in the same situation are refused with that reason and change nothing. Not delivered yet: the operating view does not show the reason beside the state. Details: WstxQsoTransmit::StartActions. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/transmit/service.rs";
    }
    dependency CL_111_07_to_FR_007 from 'CL-111-07' to 'FR-007';
    dependency CL_111_07_to_FR_008 from 'CL-111-07' to 'FR-008';
    verification 'TC-111-011' {
        doc /* TC-111-011 — A start that cannot transmit
             CL-111-07
             Setup: as TC-111-001; for the view Chromium against the candidate server.
             Steps: reply and call_dx with no capability, radio unavailable and clock not synchronized; the reason removed, 3 periods; a new reply. call_cq and send_next in the same situations. With the transmit owner refusing to arm (a PTT release that failed, an owner fault): call_cq from idle and on an own CQ that is off, send_next on a kept QSO; with the failed PTT release, reset_repetitions after a repetition-limit stop. reset_repetitions while the state is on, with Tune on and with the PTT switch indeterminate.
             Expected (CL-111-07): accepted, QSO prepared, state off, cause unchanged, refusal names the reason, the view shows it. Nothing sent in the 3 periods; the new reply transmits. call_cq and send_next: refused, nothing changed. With the owner refusing: transmit_unavailable, nothing changed, no contact prepared, nothing sent. An owner fault itself stops with cause failed, so after it Reset is state_conflict by the outcome table. Reset while on: busy with Tune on, transmit_unavailable with the PTT switch indeterminate; the count stays.
             Not automated yet: the view shows the reason.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-07';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_07_verified_by_TC_111_011 from 'CL-111-07' to 'TC-111-011';
    // #65 Free Tx slots (operator 2026-11-08, three grill-me rounds).
    requirement 'CL-065-01' {
        doc /* (#65, replaced by #82, operator 2026-11-09: "open slots are shown all the time as a part of the waterfall"; "we want to signal the other station a free frequency on our side when he will be transmitting"; "we just want to mark open slots, nothing else on screen. auto mode could use a quality ranking for its decision which of them to select") Open Tx slots: the station builds, with or without an automation run, a QSO or Auto, the open slots of my Rx parity, the periods the other station transmits in: in a QSO (Enable Tx on, my own CQ included, or a contact in progress; by a run or by hand) the contact's Rx parity; otherwise, while only listening, the parity of the period in progress, the Rx parity for transmitting in the next period, so it alternates every period. Counted periods, floor and value are #66's (WstxStrategy::FreeTxSlot: the last 4 periods of that parity that are due, ended or in progress with their complete decodes published (#89),the largest rise above the WSJT-X passband floor clamped at 0 in whole dB), of the station's live job and operating mode, from the last station band change on. A Tx frequency of the 10 Hz candidate grid inside the Tx range (FT8 300..2650, FT4 300..2610) is open when its value is 0 and its signal (FT8 50 Hz, FT4 90 Hz wide) overlaps no station decoded in a counted period; no other filter, no fallback, no ranking, no limit. The open signals join into open ranges [lo_hz, hi_hz) (overlapping ones join, touching ones stay separate). It is built at each period start, again when the decodes of a counted period are published (operator 2026-11-09, "Rebuild on decodes": the build at a period start counts the period just ended before its decodes exist), also the complete publication of the period in progress of the judged parity (#89), and at once when a QSO starts or ends or the live job, mode or band changes. The value null (no live receive) or {at_utc_ms, mode, rx_parity, qso, periods (the counted number), open [[lo_hz, hi_hz], ...]} is the top-level free_tx_slots of GET /automation and the MCP automation view, and is pushed at each build as free_tx_slots.state to every Detailed and Thin peer (at most 1024 bytes; once as null when it becomes null; once to a peer that subscribes while a value exists; never to Off), also while automation is never used, within the Thin link envelope. Auto's choice and tx_slot are unchanged (its own ranking, not shown); #65's five best of each run decision, its run_id and "no list without a run" go. Details: WstxAutoControl::FreeTxSlots (D18), WstxMcp::AutomationWire, WstxStationLink::PushedStationState. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/freeslot.rs; server/src/automation.rs; server/src/main.rs; server/src/contact_http.rs";
    }
    dependency CL_065_01_to_FR_020 from 'CL-065-01' to 'FR-020';
    dependency CL_065_01_to_FR_007 from 'CL-065-01' to 'FR-007';
    verification 'TC-065-001' {
        doc /* TC-065-001 — The five best non-overlapping candidates
             CL-065-01
             Setup: the list function with hand-authored power tables (dB per candidate, written in the test), FT8 and FT4.
             Steps: seven separate quiet places; three candidates only; no power; rises 0.4 against 0.0 and 0.6 against 0.0; equal rises either side of the current Tx; FT8 a candidate 40 Hz and one 50 Hz from a listed one, FT4 80 Hz and 90 Hz; a candidate within 50 Hz of the called station; one within 50 Hz of my Rx with Hold Tx on and off; his frequencies of my Tx parity near some candidates, and everywhere; a rise of -1.4; listening with one parity higher.
             Expected (hand computation recorded in the test): 5 of seven in rank order; 3; empty; 0.4 ties and the current Tx is first, 0.6 does not; the nearer first, at equal distance the lower; 40 Hz skipped and 50 Hz listed, 80 Hz skipped and 90 Hz listed; the called station's neighbour never listed; my Rx's neighbour not listed with Hold Tx on, listed with it off; candidates near his frequencies excluded, his frequencies everywhere leave all; -1.4 listed as -1; level_db the larger parity's; the first listed equals quietest_clear's chosen hz for every table. Red on the parent: no list.
             #66: the tables give the largest rise above the passband floor, and the compared value is that rise clamped at 0: the rise of -1.4 is listed with rise_db 0 (not -1), tying with a rise of 0.0 by the tie rule, and its level_db and floor_db stay as measured; "listening with one parity higher" becomes my Tx parity higher, which changes nothing (only my Rx parity is judged), and level_db and floor_db are those of the busiest Rx period; a candidate overlapping a decoded station is not listed while a free one exists (TC-066-002).
             #82: the five-best list is gone (WstxStrategy D18); this case is replaced by TC-082-001 (the open ranges), and its test is rewritten to it. The choice parts ("the first listed equals quietest_clear's chosen hz") go with the list; the choice stays covered by TC-039-050 and TC-066-002.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/freeslot_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_065_001 from 'CL-065-01' to 'TC-065-001';
    verification 'TC-065-002' {
        doc /* TC-065-002 — free_tx_slots in the snapshot and on the socket
             CL-065-01
             Setup: the actual station router with hand-authored detailed waterfall rows (as TC-039-050); a strategy run and a CQ run, Hold Tx off and on; socket peers subscribed Detailed, Thin and Off; GET /automation and the MCP automation view.
             Steps: read before any run; a selection with Hold Tx off; the same with only my Rx-parity periods counted since the band change; a CQ decision; a selection with Hold Tx on; a second decision with the same list; the run ends; a fourth peer subscribes Thin while a value exists; a separate session with no run at all.
             Expected: null before any run; the value with exactly {run_id, at_utc_ms, mode, rx_parity, listening, periods, slots}, the run's id, at_utc_ms the station clock of the decision, the hand-computed slots and period counts; one free_tx_slots.state each to the Detailed and Thin peer, data.free_tx_slots equal to the GET value, none to Off, at most 1024 bytes also with 5 slots at their longest numbers; tx_slot exactly as on the parent; the MCP view carries the same value; with only Rx-parity periods the Tx-parity usual count is 0; the CQ listening true with both now counts; Hold Tx on the list filled and Tx unchanged; a new event with a later at_utc_ms; after the end null and no free_tx_slots.state; the fourth peer gets the value once; without a run zero free_tx_slots.state and zero automation.state. Red on the parent: no key, no event.
             #66: periods carries {now} only, the count for my Rx parity and null for my Tx parity, in every decision (also the CQ, listening true); slots carry {hz, rise_db, level_db, floor_db} with no usual_db; "with only Rx-parity periods the Tx-parity usual count is 0" becomes "the Tx parity null"; at most 1024 bytes with 5 slots at their longest numbers (floor_db -999 and the like); rise_db is never negative (clamped at 0), while level_db and floor_db stay as measured.
             #82: replaced by TC-082-003. The value has no run_id, listening or slots ({at_utc_ms, mode, rx_parity, qso, periods, open}); it exists without a run, and free_tx_slots.state is sent every period also without a run (zero automation.state stays). "Null before any run", "after the end null and no free_tx_slots.state" and "without a run zero free_tx_slots.state" go; its test is rewritten to TC-082-003.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_065_002 from 'CL-065-01' to 'TC-065-002';
    verification 'TC-065-004' {
        doc /* TC-065-004 — Live Free Tx slots on HB9BLA
             CL-065-01, CL-065-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 40 m FT8 within the operator's standing transmit consent, PSK Reporter on, Hold Tx on, "Show free Tx slots" on in the operator's browser.
             Steps: Auto on with a strategy; let it select and call through at least one QSO and one slot check; at each decision look at the marks against the traces of my recent Rx periods; where a mark lies on a visible station read free_tx_slots from GET /automation and record it on the issue; place Tx by hand between marks with a click; HALT, Auto off.
             Expected (oracle: the operator's look): 5 marks at each decision, staying until the next; each mark a separate pale green bar visible at a glance, also two adjacent slots, with no text (#76); their places comparable with the waterfall at a glance; the recorded numbers name why that slot ranked as it did; the click sets Tx as before; no marks after the run ends.
             #82: replaced by TC-082-005 and TC-082-006 (marks all the time, no checkbox, no five, kept after the run ends).
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-065-01';
            verify 'CL-065-02';
        }
    }
    dependency CL_065_01_verified_by_TC_065_004 from 'CL-065-01' to 'TC-065-004';
    verification 'TC-066-001' {
        doc /* TC-066-001 — The 10:28:58 capture: free Tx slots off the busy 800-1330 Hz region
             CL-039-09, CL-065-01
             Setup: the slot decision and list functions with hand-authored per-period bin levels modelled on the HB9BLA capture of 2026-11-08 10:28:58 UTC (10 m FT8, D:/wstx-tmp/live-20261108c/slots-102901.json and its waterfall): a run's CQ decision (listening), my Tx parity odd and Rx parity even, Hold Tx on, Tx 1930, Rx 906. Counted even periods 10:27:30, 10:28:00, 10:28:30 and odd periods 10:28:15, 10:28:45, each a flat floor of 30 dB (32 dB in the latest period of each parity), every station the capture decoded in that period as its decode (audio frequency, period) and as a band [hz, hz + 50) 12 dB above 30 dB (live, occupied slots read 4-12 dB above clear ones, #66 comment 6720568259); RK3AW's band at 1198.5 Hz also in both odd periods, undecoded there (the capture's 1180 Hz slot: level 50 against usual 48, busy in the odd periods too).
             Steps: the decision with Hold Tx on (no choice, the list only); the same with Hold Tx off (the choice).
             Expected (hand computation recorded in the test): the even decodes leave the candidates 300..400, 720..800, 1010..1050, 1250..1310, 1450..1680, 1890..1960, 2120..2130 and 2240..2650 (810..1000 within 50 Hz of Rx 906 with Hold Tx on); each reads 0 (floor 30.65 or 32.65, rise -0.65 clamped at 0, #66 "At or under floor = free"); the list is 1930, 2120, 1680, 1630, 2240 (the current Tx kept as free, then the free slots by distance), each {rise_db 0, level_db 32, floor_db 33} (level and floor of the latest, busiest period as measured); no listed slot overlaps a station decoded in my even periods and none lies in 800-1330 Hz; the odd stations (DL5XU at 1976, A61DD at 765) do not count; periods {even {now 3}, odd {now null}}; Hold Tx off: the CQ's slot is 1930, tx_slot power_db 0, the first listed. Red on the parent: its list holds slots on RK3AW (rise 0 there against 1 on the free slots, the live failure's ranks 2 and 3).
             #82: the list parts become the open ranges of the same tables (TC-082-001's rule: value 0 and no even decode overlapped, no clearance of Rx or the called station), hand-computed in the test; no open range overlaps a station decoded in my even periods, and the odd stations close nothing. The choice parts (Hold Tx off: the CQ's slot 1930, tx_slot power_db 0) stand.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_066_001 from 'CL-039-09' to 'TC-066-001';
    dependency CL_065_01_verified_by_TC_066_001 from 'CL-065-01' to 'TC-066-001';
    verification 'TC-066-002' {
        doc /* TC-066-002 — Decoded stations, my Rx parity only, recent periods
             CL-039-09, CL-065-01, CL-039-22
             Setup: the slot decision and list functions with hand-authored per-period bin levels and decodes (audio frequency and period), FT8 and FT4; the actual station router with the contact engine on the hardware double for (g) and (h), virtual UTC.
             Steps: (a) the 07:29 reproduction (HB9BLA 2026-11-08, 20 m): Tx 1550, my Rx parity even, a flat floor 30 in the two older and 32 in the two later of 4 counted periods of each parity; a station decoded at 659.5 Hz at 38 dB in all 4 even periods, stations at 659.7 and 691.8 Hz at 38 dB in all 4 odd periods. (b) A decode at 1000.0 Hz: FT8 candidates 950, 960, 1040, 1050; FT4 910, 920, 1080, 1090; a decode at 1000.4 Hz and the candidate 1050. (c) A decode overlapping every candidate. (d) A station decoded only in my Tx parity, 20 dB above the floor, on the otherwise quietest slot. (e) A CQ decision: a slot loud only in the CQ's Tx parity, quietest in my Rx parity; and the reverse. (f) Decodes from a period that does not count: the 5th older Rx period, one before a band change, one older than the last 4 Rx periods on the clock. (g) Hold Tx on, a selection of a station within 50 Hz of Tx whose nearest candidate 50 Hz clear overlaps a decoded station; the same with every candidate overlapped. (h) Hold Tx off, the CQ on 900 answered for a caller at 920, with a station decoded at 800 Hz. (i) His frequencies of my Tx parity together with decodes. (j) The list at each step.
             Expected (hand computation recorded in the test): (a) Tx stays 1550 (value 0, every free slot 0 with rise -0.65 clamped, the current Tx kept); 610..700 never chosen or listed; (b) FT8 960 and 1040 left out, 950 and 1050 kept; FT4 920 and 1080 left out, 910 and 1090 kept; 1050 left out at 1000.4; (c) all candidates back, ranked by value; (d) that slot chosen, neither left out nor raised; (e) the slot quietest in my Rx parity chosen in both; (f) those decodes leave nothing out; (g) Tx to the next nearest candidate clear of the station and of the decoded station; with all overlapped the nearest 50 Hz clear; (h) Tx and Rx to the nearest candidate 50 Hz clear of 920 that does not overlap 800 (not 820); (i) his end applies among the candidates left by the decoded stations, his_end no when it leaves none; (j) the first listed equals the choice, no listed slot overlaps a counted decode while a free one exists. Red on the parent: (a) moves Tx to 680 (rise 0 on the station, 1 on the free slots), as live; (b), (g) and (h) choose the overlapped candidates.
             Added after the live run of 2026-11-08 (#66): a strategy run with Hold Tx on calls in my Tx periods through the actual router and the actual live worker; the last 2 rows of each received Rx period complete while keyed. Expected: each received Rx period counts (periods.<rx>.now 1, 2, 3 at the selection and the two slot checks); only periods I transmitted in are not counted, by the period, not by the on-air state of single rows.
             #82: (j) becomes: the open ranges at each step contain no signal overlapping a counted decode, also in (c), where every candidate is overlapped and open is [] (no fallback for the marks, while the choice still uses all candidates). The choice parts stand.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
            verify 'CL-039-22';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_066_002 from 'CL-039-09' to 'TC-066-002';
    dependency CL_065_01_verified_by_TC_066_002 from 'CL-065-01' to 'TC-066-002';
    dependency CL_039_22_verified_by_TC_066_002 from 'CL-039-22' to 'TC-066-002';
    verification 'TC-066-003' {
        doc /* TC-066-003 — Live quiet slots on HB9BLA
             CL-039-09, CL-065-01
             Setup: the gated candidate installed on HB9BLA, IC-7300 FT8 on a busy band (20 m or 10 m) within the operator's standing transmit consent, PSK Reporter on, Hold Tx on, "Show free Tx slots" on; decodes and free_tx_slots read from GET /automation and the decode list at each decision.
             Steps: Auto on with a strategy with CQ when idle; let it call CQ, answer or call through at least one QSO and one Tx move; switch Hold Tx off for one call; at each decision record free_tx_slots and the decodes of my last 4 Rx periods on the issue; HALT, Auto off.
             Baseline before #66 (HB9BLA 2026-11-08, #66 comment 6720568259): in 14 decisions 52 of 70 listed slots, and rank 1 in 7 of 14, had a decoded station within 50 Hz while 23-67 decode-free 10 Hz points existed each time; occupied slots read 48-52 dB, clear ones 36-44 dB.
             Expected (oracle: the decodes and the operator's look at the waterfall): no listed slot and no chosen slot overlaps a station decoded in my last 4 Rx periods while the list has a free one (0 of the listed slots where the baseline had 52 of 70); the marks lie in stretches the waterfall shows empty in my Rx periods and are not all at the passband edges; rise_db of a slot free of decodes 0, 1 or 2 (never negative); with Hold Tx on Tx moves only at a slot check or by the 50 Hz rule, never onto Rx.
             #82: there is no checkbox and no listed slot: the marks (open ranges, recorded from GET /automation free_tx_slots at each decision) overlap no station decoded in my last 4 Rx periods; rise_db is read from tx_slot.power_db of the chosen slot only.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
    }
    dependency CL_039_09_verified_by_TC_066_003 from 'CL-039-09' to 'TC-066-003';
    dependency CL_065_01_verified_by_TC_066_003 from 'CL-065-01' to 'TC-066-003';
    // #82 open slots all the time (operator 2026-11-09, two grill-me rounds and the simplification).
    verification 'TC-082-001' {
        doc /* TC-082-001 — Open slots and open ranges
             CL-065-01
             Setup: the open-slot function and the range join with hand-authored per-period bin levels and decodes (audio frequency, period), FT8 and FT4, 4 counted periods of the judged parity unless a step names fewer; the join also fed open frequency sets directly.
             Steps: (a) FT8 a flat floor of 30 dB everywhere (floor 30.65, every rise -0.65) and an undecoded station band 12 dB above it over 1000..1050 Hz in all 4 periods. (b) FT8 the flat floor and a decode at 1000.0 Hz; FT4 the same. (c) The join: FT8 open sets {2110, 2160}, {2100, 2110, 2130}, {2650}, every 5th grid point {300, 350, ..., 2650}; FT4 {300}, {300, 390}. (d) Values: a slot window whose largest rise is 0.4 dB and one whose is 0.6 dB. (e) A station decoded and 20 dB above the floor only in periods of the other parity. (f) Decodes in periods that do not count: the 5th older period, one before a band change, one older than the last 4 of the parity on the clock. (g) Decodes overlapping every grid point. (h) No counted period. (i) A slot on the floor in 3 periods and 3 dB above it in one.
             Expected (hand computation recorded in the test; oracle: the open rule of CL-065-01 and FreeTxSlot's floor and value, the flat-floor floor F + 0.65 of TC-039-050): (a) 950 and 1050 open, 960..1040 closed: open [[300, 1000], [1050, 2700]]; (b) FT8 the same; FT4 920..1080 closed, 910 and 1090 open: [[300, 1000], [1090, 2700]]; (c) [[2110, 2160], [2160, 2210]] (touching, not joined); [[2100, 2180]]; [[2650, 2700]]; 48 ranges [[300, 350], ..., [2650, 2700]]; FT4 [[300, 390]]; [[300, 390], [390, 480]]; (d) 0.4 open (value 0), 0.6 closed (value 1); (e) nothing closed by it; (f) those decodes close nothing; (g) open [] (no fallback); (h) open [], periods 0; (i) closed (its busiest period counts). Red on the parent: no open-slot function (the five-best list).
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/freeslot_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_001 from 'CL-065-01' to 'TC-082-001';
    verification 'TC-082-002' {
        doc /* TC-082-002 — The judged parity and when the value is built
             CL-065-01
             Setup: the actual station router with hand-authored detailed waterfall rows of both parities (as TC-039-050), the contact engine on the hardware double, virtual UTC, FT8 and FT4; no automation run unless a step names one.
             Steps: (a) Listening without a run: read GET /automation free_tx_slots right after 4 consecutive period starts (FT8 at :00, :15, :30, :45; FT4 7.5 s apart), with one slot loud only in the even periods and one loud only in the period in progress. (b) Enable Tx on for my own CQ with Tx even in the middle of a period, then 4 period starts, then Enable Tx off with no contact. (c) A manual contact with a caller decoded in the odd periods (Tx even) through two periods. (d) A strategy run waiting, then its CQ decision and its contact; the same tables as for the run's choice on the parent. (e) A station band change; the live job stopped; restarted. (f) In a QSO with Tx even, a station decoded at 1200 Hz only in the odd period just ended, below the level that closes a slot by its waterfall rise; the build at the next even period start, then the publication of that period's decodes.
             Expected (hand computation recorded in the test; oracle: CL-065-01's parity rule and the operator's round 1 Q3 and round 2 Q1 answers): (a) rx_parity even, odd, even, odd at :00, :15, :30, :45 (the parity of the period in progress), qso false, at_utc_ms the period start; the even-loud slot closed in the even builds, open in the odd ones; the slot loud only in the period in progress not closed at that period's start; periods the counted periods of that parity before the period in progress (at most 4). (b) At Enable Tx at once a build with qso true and rx_parity odd; rx_parity odd at every following start, open changing only at builds at even period starts (when an odd period has ended); at Enable Tx off at once a build with qso false and the parity of the period in progress. (c) qso true, rx_parity odd, the caller's slot closed. (d) The waiting run as (a); in its CQ and contact as (b); the run's choice and tx_slot equal the parent's for the same tables, and the value has no run_id. (e) After the band change only later periods count (the first build periods 0, open []); a stopped live job: null; restarted: a value from its first period. (f) The period-start build has the 1200 Hz slot open (its decodes not yet published); at the publication at once a build with the same qso and rx_parity, a later at_utc_ms, and the slot overlapping 1200 Hz closed. Red on the parent: no value without a run, no alternation.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_002 from 'CL-065-01' to 'TC-082-002';
    verification 'TC-082-003' {
        doc /* TC-082-003 — free_tx_slots on the socket and in the snapshot without a run
             CL-065-01
             Setup: the actual station router with hand-authored detailed rows, virtual UTC; socket peers subscribed Detailed, Thin and Off; the MCP automation view; automation never used (no configuration, no run).
             Steps: 60 s of FT8 listening; 30 s of FT4 listening; Enable Tx on and off in the middle of a period; a fourth peer subscribes Thin; the live receive stops; a value with 48 ranges at 4-digit numbers.
             Expected (oracle: CL-065-01 and WstxStationLink::PushedStationState): GET /automation free_tx_slots with exactly {at_utc_ms, mode, rx_parity, qso, periods, open}, equal to the MCP view's; each Detailed and Thin peer one free_tx_slots.state per build (FT8 4 in 60 s, FT4 4 in 30 s, plus one at each QSO start and end), data.free_tx_slots equal to the GET value of that build; none to Off; zero automation.state throughout; the fourth peer exactly one with the current value; after the receive stops one event with free_tx_slots null, GET null, no further event; at most 1024 bytes also for the 48-range value with two UUIDs and a 13-digit at_utc_ms; no run_id, slots, rise_db, level_db or floor_db anywhere in it. Red on the parent: no event and null without a run.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_003 from 'CL-065-01' to 'TC-082-003';
    verification 'TC-082-005' {
        doc /* TC-082-005 — Live open slots while listening on HB9BLA
             CL-065-01, CL-065-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 40 m (or 10, 15 or 20 m) FT8, Monitor on, Auto off, no run and no transmission; the operator's browser.
             Steps: for 2 minutes read GET /automation free_tx_slots after each period start (8 builds) together with the decodes of those periods, and look at the marks against the waterfall; then FT4 for 1 minute.
             Expected (oracle: the recorded decodes and the operator's look): rx_parity alternates build by build, qso false; no open range overlaps a station decoded in the counted periods of its parity; the marks change every period with the parity and lie on stretches the waterfall shows empty in that parity's periods; no text, no checkbox; the same in FT4 every 7.5 s.
             3 — Live read-only on the station (receive only, no transmission); not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-065-01';
            verify 'CL-065-02';
        }
    }
    dependency CL_065_01_verified_by_TC_082_005 from 'CL-065-01' to 'TC-082-005';
    verification 'TC-082-006' {
        doc /* TC-082-006 — Live open slots in a QSO on HB9BLA
             CL-065-01, CL-065-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 1 W on 40 m (or 10, 15 or 20 m) FT8 within the operator's standing transmit consent; the operator's browser.
             Steps: a manual QSO (own CQ or answering a CQ) to its end; then Auto on with a strategy through one QSO; HALT not needed, Auto off. At each period start read GET /automation free_tx_slots and the run's tx_slot, and record them with the decodes on the issue.
             Expected (oracle: the recorded decodes and the operator's look): from Enable Tx on to the QSO's end qso true and rx_parity constant, the marks on my Rx parity only; no open range overlaps the partner or another station decoded in my counted Rx periods; after the QSO the marks alternate again; in the run its tx_slot is its own choice (power_db as before), and the marks are the same as without the run.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-065-01';
            verify 'CL-065-02';
        }
    }
    dependency CL_065_01_verified_by_TC_082_006 from 'CL-065-01' to 'TC-082-006';
    // #89 the newest Rx period counts once its decodes are published (operator 2026-11-09, "Count once decoded").
    verification 'TC-089-001' {
        doc /* TC-089-001 — Due periods at a decision
             CL-039-09, CL-065-01
             Setup: the slot decision and open-slot functions with hand-authored per-period bin levels (flat floor 30 dB) and decodes (audio frequency, period), FT8 my Rx parity odd, P the newest odd period; FT4 for (f).
             Steps: (a) a decision at P + 14.1 s with P's complete publication; (b) the same instant without it; (c) only a partial publication of P; (d) undecoded, in every period a flat 30 dB in every bin (floor 30.65, TC-039-050), except in P the 18 bins k = 512..529 of [1500, 1550) Hz at 42 dB in P's rows 3..64 (62 rows of 0.2 s, 0.6..12.8 s) and 30 dB in its other rows; the test feeds P's rows 0..69 (the 70 rows complete at P + 14.1 s) for the decision at (a), then rows 70..74 and a decision at P + 15.2 s; (e) a decision at P + 15.2 s, P ended without its publication, then after it; (f) FT4 a decision at P + 6.9 s with P's complete publication; (g) a complete publication naming the next odd period P + 2, published while P + 1 is in progress (a period not yet begun).
             Expected (hand computation recorded in the test; oracle: WstxStrategy::FreeTxSlot Due): (a) counted P and the 3 odd periods before it, the 4th older not; a decode at 2340 Hz in P closes the candidates 2300..2380 (|f - d| below 50); (b) P not counted, the 4 before it counted, 2340 closes nothing; (c) as (b); (d) at P + 14.1 s slot 1500 level (62 x 42 + 8 x 30) / 70 = 40.63, floor 30.65 (the band's 18 bins lie above each segment's 8th lowest level, so the flat-floor fit stands), rise 9.98, value 10 (every other period and every slot outside the band 0); at P + 15.2 s with all 75 rows level (62 x 42 + 13 x 30) / 75 = 39.92, rise 9.27, value 9; (e) P counted by its levels, 2340 closes nothing until the publication, then closes; (f) P counted; (g) P + 2 not due and not counted, its decodes close nothing. Red on the parent: (a) P not counted and 2340 open; (d) value 0.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/newest_rx_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_089_001 from 'CL-039-09' to 'TC-089-001';
    dependency CL_065_01_verified_by_TC_089_001 from 'CL-065-01' to 'TC-089-001';
    verification 'TC-089-002' {
        doc /* TC-089-002 — Decisions on the newest Rx period (the 12:24:29 reproduction)
             CL-039-09
             Setup: the actual station router with the contact engine on the hardware double, virtual UTC; detailed rows and decodes modelled on HB9BLA 2026-11-09 12:24:15-12:24:29 (#66 comment 6740465378): Tx 2340 free in the 4 older odd periods, in the odd period P M7HNI decoded at 2340 Hz.
             Steps: a strategy run with Hold Tx off selects HA7NB (1001 Hz) on P's complete publication at P + 14.1 s; Hold Tx on, a slot check of a target that does not hear us with a station decoded on Tx only in P; the same selection by a pounce; a station decoded only in the 5th older odd period.
             Expected (hand computation recorded in the test; oracle: FreeTxSlot Due and Choice): Tx and Rx to the hand-computed nearest free slot clear of 2340 and 1001, tx_slot.hz not 2340; at the slot check Tx alone moves off the station; the pounce as the selection; the 5th older station closes nothing. Red on the parent: Tx stays on 2340.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/newest_rx_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_089_002 from 'CL-039-09' to 'TC-089-002';
    verification 'TC-089-003' {
        doc /* TC-089-003 — Open slots rebuilt on the publication of the period in progress
             CL-065-01
             Setup: the actual station router with hand-authored detailed rows of both parities and decodes, the contact engine on the hardware double, virtual UTC (as TC-082-002).
             Steps: (a) in a QSO with Tx even, the complete publication of the odd period P at P + 14.1 s with a station decoded at 1200 Hz in P; (b) listening without a run, P's complete publication, then the next period start; (c) only a partial publication of P; (d) a publication of the other parity.
             Expected (hand computation recorded in the test; oracle: CL-065-01): (a) one build at once with periods counting P, the slot overlapping 1200 Hz closed, at_utc_ms the publication time; (b) a build with P's parity counting P, at the next period start the parity flips as before; (c) no build counting P; (d) the judged periods unchanged. Red on the parent: no build at P's publication, the 1200 Hz slot open until the next period start.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/newest_rx_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_089_003 from 'CL-065-01' to 'TC-089-003';
    verification 'TC-089-004' {
        doc /* TC-089-004 — A contest strategy's CQ waits for the newest Rx period
             CL-039-09, CL-039-05
             Setup: the actual station router, the WW Digi contest built-in strategy (cq_when_idle on, cq_wait_periods 2: CQ only after two empty publications, CqWhenNoTarget), Hold Tx off, Tx 1500, Rx parity even, P = e, the contact engine on the hardware double, virtual UTC.
             Steps: (a) Auto on at P + 5 s, P's complete publication at P + 14.1 s (a station at 1500 calling another); (b) no publication at P + 15.0 and P + 29, then e + 15 published empty at e + 29.1; (c) Hold Tx on; (d) Auto off, and separately Halt, at P + 20 s; (e) P published before Auto on, Auto on at P + 20 s; (f) Auto on sent again at P + 20 s; (g) the operator's manual contact ended by Esc at P + 5 s, and separately completed (logged about e + 28).
             Expected (oracle: WstxStrategy::FreeTxSlot Waiting for the newest period and CqWhenNoTarget, hand-worked): (a) waiting, no decision and no enable_tx at P + 8 and P + 14; P's publication is the first empty one, still waiting; (b) no decision without a publication; at e + 29.1 (the second empty) the CQ slot taken with P counted, 1460..1540 closed, giving 1450, armed; (c) no CQ at Auto on or the first publication, CQ on the held 1500 at the second, no slot decision; (d) stopped, no decision at the second; (e) P not fresh, still waiting after the empty e + 15, CQ from 1450 after the empty e + 30; (f) one decision (1450) at the second; (g) Esc: no set_frequency at P + 14 or at P's publication, CQ at 1750 on e + 15's publication; completed: no CQ at e + 29.9, e + 30 or the first empty publication after (e + 30, published e + 44.1), CQ at the second (e + 45, published e + 59.1), Tx 1500 kept. Red on the parent: build only.
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/newest_rx_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_089_004 from 'CL-039-09' to 'TC-089-004';
    dependency CL_039_05_verified_by_TC_089_004 from 'CL-039-05' to 'TC-089-004';
    verification 'TC-089-005' {
        doc /* TC-089-005 — Live decisions on the newest Rx period on HB9BLA
             CL-039-09, CL-065-01
             Setup: the gated candidate installed on HB9BLA, IC-7300 1 W FT8 on 20 m or 10 m within the operator's standing transmit consent, PSK Reporter on.
             Steps: Auto on with a strategy through at least 20 decisions, Hold Tx on and off; at each decision record tx_slot, free_tx_slots and the decodes of the newest Rx period (as D:/wstx-tmp/live/20261109/tc66-decisions.txt) on the issue; HALT, Auto off.
             Baseline before #89 (#66 comment 6740465378): 16 of 98 listed slots in 10 of 23 decisions sat on stations of the newest Rx period, the kept Tx 2340 on M7HNI.
             Expected (oracle: the recorded decodes and the operator's look): no chosen slot overlaps a station decoded in the newest Rx period while a free one exists; no open range overlaps one from that period's publication on.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
    }
    dependency CL_039_09_verified_by_TC_089_005 from 'CL-039-09' to 'TC-089-005';
    dependency CL_065_01_verified_by_TC_089_005 from 'CL-065-01' to 'TC-089-005';

    requirement 'CL-063-03' {
        doc /* The operator selects a contest with its period and a contest strategy of that contest (CL-097-07) through a prompt pre-filled from the schedule rule (empty for ARRL January VHF, which the prompt asks), shown with the strategy and editable; with Auto off it only colours (CL-039-22). It is exclusive with a strategy of class strategy, is held in station memory only, and None ends it. The log is evaluated only inside that period: dupes by the profile's rule, multipliers, points and the score. Choosing an activity sets no strategy and selecting a contest sets no activity. Details: WstxStrategies::ContestSelection, ContestLog, ContestPrompt. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_063_03_to_FR_024 from 'CL-063-03' to 'FR-024';
    dependency CL_063_03_to_FR_019 from 'CL-063-03' to 'FR-019';
    verification 'TC-063-005' {
        doc /* TC-063-005 \— The points and multiplier rules
             CL-063-03
             Setup: distances computed apart from this code (haversine, R 6371 km; IARU 111.2 km per degree): JN37-FN42 5894.6 km, JN37-JO62 701.6, JN37-JN38 111.2, JN37-PM95 9624.3.
             Steps: each points rule for those pairs, a six-character locator, the same square, no grid; the VHF band tables; Field Day per mode; the multiplier keys.
             Expected: WW 2, 1, 1, 4; ARRL 13, 3, 2, 21; IARU 5895, 702, 112, 9625; the same large square 50; ARRL same square 2 (the minimum distance value); no grid none; 1 per call; January 1,1,2,2,4,4,8,8 and June/September 1,1,2,2,3,3,4,4 for 6 m, 2 m, 1.25 m, 70 cm, 33 cm, 23 cm, 13 cm, 3 cm; Field Day digital 2, CW 2, phone 1; keys FN|20m and FN42|6m, none without a rule or a grid.
             2 \— Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_005_the_points_rules_by_hand";
    }
    dependency CL_063_03_verified_by_TC_063_005 from 'CL-063-03' to 'TC-063-005';
    verification 'TC-063-006' {
        doc /* TC-063-006 \— The log inside the period, the dupe rules and the verdicts
             CL-063-03, CL-063-04
             Setup: hand-written QSO lists and decoded records for HB9BLA JN37 in EU on 20 m with activity ww_digi.
             Steps: a WW Digi log with a QSO before the period, one at its exclusive end, a repeat in FT4, another band, SSB and 30 m; ARRL VHF with a rover and without a grid; Field Day SSB; FT8 Activity on another band; ARRL Digi with RTTY. Verdicts for a known field, a new far field, a new near field, a dupe, CQ NA, no CQ, another station's RR73, a weak caller, a dupe caller; on 30 m; without a log; a /R CQ in ARRL VHF and IARU.
             Expected: 2 QSOs, 2 multipliers, 4 points, score 8, nothing outside the period counted; VHF dupe on the same grid only, every grid without a logged grid; Field Day digital no dupe of SSB; a Field Day exchange to my call a caller with 2 points or a dupe, to another call not a CQ; FT8 Activity a dupe on another band; ARRL Digi 1 QSO, 13 points, score 13. Rank order caller, far new multiplier, near new multiplier, the known field, the RR73; the dupes rank null with dupe true, also the caller; greyed CQ NA; nothing ranked on 30 m or without a log; the wire form of a verdict; the rover ranked in ARRL VHF, refused callsign guard in IARU.
             2 \— Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
            verify 'CL-063-04';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_006_only_the_period_counts_and_each_dupe_rule; server/src/contest_tests.rs::tc_063_006_verdicts_callable_by_value; server/src/contest_tests.rs::tc_063_006_a_field_day_exchange_to_my_call_is_a_caller";
    }
    dependency CL_063_03_verified_by_TC_063_006 from 'CL-063-03' to 'TC-063-006';
    verification 'TC-063-007' {
        doc /* TC-063-007 \— The contest selection on the store and the evaluate route
             CL-063-03, CL-063-04
             Setup: exact-parse table; the actual station router on a disposable selected HTTPS profile (HB9BLA, JN47AA) on 40 m with an imported log (one QSO inside the period, one before), an injected FT8 live job with CQ WW W1DUP, K1OLD and JA1XYZ, activity ww_digi.
             Steps: each refused selection form, also with each key that WstxStrategies::ContestSelection refuses as an extra key; PUT with a contest {profile, start, end} and active the WW Digi built-in; read strategy.json; a new owner; the automation snapshot; PUT with a strategy of class strategy and a contest; a period with end not after start; evaluate; PUT without contest; evaluate.
             Expected: each field named, those keys refused as extra keys; the configuration echoes the contest, the file holds none, a new owner has none, no run; 400 field contest (a strategy plus a contest is accepted only when the strategy is a contest strategy of that profile, TC-097-015) and contest.end; verdicts JA1XYZ rank 0 new multiplier 4 points, K1OLD rank 1, W1DUP dupe with rank null; tally 1 QSO, 1 multiplier, 3 points, score 3 (JN47-EM12 8469.4 km); strategy WW Digi; after None the key is gone and evaluate says not_configured.
             2 \— Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
            verify 'CL-063-04';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_007_a_selection_is_parsed_exactly; server/src/strategy_tests.rs::tc_063_007_a_contest_selection_store_and_evaluation";
    }
    dependency CL_063_03_verified_by_TC_063_007 from 'CL-063-03' to 'TC-063-007';
    verification 'TC-063-008' {
        doc /* TC-063-008 \— The contest prompt, the callable list and Show all in the browser
             CL-063-03, CL-063-04
             Setup: actual browser with hand-written station replies for the receive results, GET and PUT /strategy, GET /strategy/contests and POST /strategy/evaluate.
             Steps: no contest; the prompt on WW Digi; a page reload with the contest in force; ARRL January VHF without a date; Start, with a row to my call that is a dupe, rows carrying all-time flags (new call, new DXCC) and a row of the partner; the partner's contact prepared and ended; Show all on and off; 1.5 s of silence; reopen; None; the prompt at 360 px.
             Expected: the toggle hidden, the selector unchanged, nothing evaluated and no read of /strategy/contests without a contest; one read at the prompt, and one after the reload, which names the contest in the selector; the rule's period pre-filled, the clause, the activity line, the contest strategies offered with no operation choice (TC-097-015); January empty and refused with no request; one PUT with active the contest built-in and the contest; one evaluation; the row to my call stays beside JA1XYZ with the multiplier colour and K1ABC, the status with period and tally; no all-time slot colour and no new-call or new-DXCC reason on any row; a partner row is listed first while its contact stands, and hidden after; Show all adds the dupe and the directed CQ dimmed, without a slot colour, with no new request; no request during the silence; the period in force on reopening; None sends no contest, shows every row and brings the slot colour back; no sideways overflow on the phone.
             2 \— Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
            verify 'CL-063-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_063_03_verified_by_TC_063_008 from 'CL-063-03' to 'TC-063-008';
    requirement 'CL-063-05' {
        doc /* With Auto on the run applies the contest strategy (CL-097-04, CL-097-07): it calls the most valuable callable station by the contest's rules, and with its CQ when idle calls CQ with the contest's message and answers the most valuable non-dupe caller (with Calling stations are answered on; new multiplier, QSO points, SNR), not the first decoded; a dupe caller is never answered and never ends a stay. Leaving follows CL-039-23 with the strategy's leave and retry pause. Where the rules forbid automatic operation the browser shows the clause as a warning when Auto is switched on and transmits only after the operator's confirmation, and the station refuses Auto on without it; where they are silent a short note. It waits while the activity, the band or the period do not fit the contest; a contest can still be operated by hand. Details: WstxAutoControl::ContestRun, AutomationClause, ContestSelection; WstxAutoControl::AutoToggle, LeaveRule. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contest.rs; server/src/strategy.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_063_05_to_FR_024 from 'CL-063-05' to 'FR-024';
    dependency CL_063_05_to_FR_020 from 'CL-063-05' to 'FR-020';
    verification 'TC-063-009' {
        doc /* TC-063-009 — Search and pounce, and the automation clause
             CL-063-05
             Setup: the selection form table; the actual station router (HB9BLA JN47AA) with the contact engine and #9 transmit owner on the recording hardware double, virtual UTC, on 20 m, an imported QSO with W1DUP inside the period; a status session held open; for the manual QSO, the CAT owner on a scripted IC-7300 whose dial reads 14.074 MHz, confirmed, and an empty log.
             Steps: each forbidding and silent profile with its contest built-in and with a copy (cq_when_idle false), then Auto on with and without the confirmation; a selection with operation colouring or with automation_confirmed; set_activity alone; the copy with Auto on and activity none, on 30 m, then fitting; CQ WW W1DUP (strongest), K1ABC and JA1XYZ (weakest); empty partner periods; W1DUP alone; a selection whose period starts in an hour; a run with a manual replacing QSO with W9XYZ to its end, nothing imported, the log rebuilt, then W9XYZ's CQ alone.
             Expected: Auto on refused field automation_confirmed where forbidden, accepted where silent; colouring and automation_confirmed refused on PUT with their field; no run with Auto off, after the refused Auto on and after set_activity; reasons activity, band, none; never a CQ; JA1XYZ selected and armed, Tx2 with the grid; after 2 partner periods without progress waiting, disarmed, JA1XYZ in its retry pause; nothing armed for the dupe alone; outside_period and nothing armed; the log holds exactly W9XYZ EN52 20m FT8, written by the completed QSO itself; the manual QSO's station a dupe, nothing armed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_009_a_selection_asks_nothing_and_refuses_colouring_and_the_confirmation; server/src/strategy_tests.rs::tc_063_009_search_and_pounce_calls_the_most_valuable_and_waits_for_what_it_needs; server/src/strategy_tests.rs::tc_063_009_a_manual_qso_of_the_period_is_a_dupe_for_the_next_evaluation; server/src/strategy_tests.rs::tc_039_042_a_silent_contest_switches_auto_on_without_a_confirmation";
    }
    dependency CL_063_05_verified_by_TC_063_009 from 'CL-063-05' to 'TC-063-009';
    verification 'TC-063-010' {
        doc /* TC-063-010 — CQ when idle in a contest and the most valuable caller
             CL-063-05
             Setup: as TC-063-009 with the scripted IC-7300 on 14.074 MHz, activity ww_digi, the contest built-in WW Digi selected (cq_when_idle true, cq_wait_periods 2); no callable station in the published periods (only callers).
             Steps: two empty publications; callers W1DUP (dupe, strongest), K1ABC (first non-dupe decoded), JA1XYZ (weakest, new multiplier, most points); its R and 73; steps; nothing imported; JA1XYZ again; once the log is rebuilt, callers JA2ABC PM85 (more points) and K1NEW FN42; Abort of that QSO; an empty period; Abort of the run's own CQ; the band leaves the contest and returns (the dial to 10.136 MHz and back); the station clock past the period's end.
             Expected: calling_cq, armed, Tx6 "CQ WW HB9BLA JN47"; JA1XYZ answered with 2 candidates, not the first, not the strongest, not the dupe; completed, then calling_cq again with 1 completed; the log holds W1DUP EM12 and JA1XYZ PM95 20m FT8, the latter written by the completed QSO itself; not answered again; K1NEW selected, PM being no new multiplier any more; after that Abort calling_cq; the CQ goes on; after Abort of the CQ calling_cq, armed, with a new contact id; waiting band and disarmed, then calling_cq and armed again; waiting outside_period and disarmed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_010_run_calls_cq_and_answers_the_most_valuable_caller";
    }
    dependency CL_063_05_verified_by_TC_063_010 from 'CL-063-05' to 'TC-063-010';
    verification 'TC-063-012' {
        doc /* TC-063-012 — Fully automatic in the browser
             CL-063-05
             Setup: actual browser with hand-written replies for GET and PUT /strategy, POST /strategy/auto, GET /strategy/contests and GET /automation.
             Steps: the contest built-in WW Digi chosen in the prompt (TC-097-015), Start; Auto on, decline; Auto on, confirm; 1.5 s of silence; automation.state pushes for calling_cq, waiting outside_period and stopped run_limit; reopen and Start the same selection; reopen; FT8 Activity with its built-in and Auto on.
             Expected: Start sends one PUT with active the built-in and the contest {profile, start, end}, no automation_confirmed; the warning with the clause on Auto on, nothing sent when declined; one POST /strategy/auto with automation_confirmed true when confirmed; no read of /automation during the silence; the status names each; Start of the same selection sends nothing new to the run (Auto stays as pushed); the strategy in force on reopening, the built-in of another contest chosen first, the note; no warning and no automation_confirmed for FT8 Activity.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_063_05_verified_by_TC_063_012 from 'CL-063-05' to 'TC-063-012';
    // #81 A started QSO is finished whatever ends the run (operator 2026-11-08, two grill-me rounds).
    requirement 'CL-081-01' {
        doc /* (#81, operator 2026-11-08: "If Auto is deselected during a QSO, this QSO is finished, has to be finished as normal. Auto only starts."; "A started QSO should always be finished out of courtesy. If we did not answer, then this does not count as a QSO") Auto, and every run, decides only whether new QSOs start. A started QSO is a contact of a run whose dialogue holds a decoded message of the partner to my call and an own transmission to the partner that has started (keyed, also one still on the air); a station that called my call before our transmission to it started, and a station we called that has sent nothing to my call, are no started QSO. When Auto off, None, another strategy or contest selection, an Auto on that ends a pounce or MCP run, an AutomationCommand stop or a policy run's time limit ends the run, or a contest period ends during it, the run ends (or waits) at once with its reason as before, and a started QSO stays armed and is finished as an ordinary contact: sequenced to its end and logged once, bounded by the Tx watchdog's stop at N with no leave rule, slot check or exemption; Tx and Rx stay; nothing new is selected, called or answered for it, and a run started meanwhile waits for it as for the operator's contact. A contact that is no started QSO ends at once at these ends as before; a transmission already on the air finishes its period and nothing after it is keyed. Still at once: HALT, Abort QSO, the operator's selection of another station, the Tx watchdog's stop, the grant revoked or a safety edit, a band or mode change by the operator, a station restart, and the run's own leaving while it runs. Details: WstxStrategy::StartedQso, StrategyRun, AutoToggle; WstxMcp::OperatingAutomation; WstxQsoControl::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contact_http.rs; server/src/contact.rs; client/contact.js";
    }
    dependency CL_081_01_to_FR_007 from 'CL-081-01' to 'FR-007';
    dependency CL_081_01_to_FR_020 from 'CL-081-01' to 'FR-020';
    verification 'TC-081-001' {
        doc /* TC-081-001 — Reproduction: Auto off in a started QSO
             CL-081-01
             Setup: as TC-039-042 (the actual station router, HB9BLA JN47AA, with the contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, 20 m FT8, a status session held open, the browser cookie grant); the saved strategy "New calls" of class strategy (new [call] per ever, order [most_wanted]) selected, Auto on; Tx watchdog 6; an empty log.
             Steps: publish CQ K1ABC FN42; let the run select and call K1ABC (Tx1 keyed); publish K1ABC's answer HB9BLA K1ABC -05 in his period; at the next station step POST /strategy/auto {auto false}; then publish HB9BLA K1ABC RR73 after our next transmission; afterwards publish CQ DL1XYZ JO62 and W1AW calling my call for three periods.
             Expected (oracle: the operator's rule of 2026-11-08 on #81 and the standard sequence of WstxContact::QsoAndLogging): Auto off at once (GET /strategy auto false, one strategy.state) and the run stopped with reason stopped; Enable Tx stays on: the R-report K1ABC HB9BLA R-.. is keyed in the next own period, then 73 after his RR73; the contact completed with Enable Tx off; exactly one log entry K1ABC FN42 20m FT8, written by the completed contact itself; after the completion nothing is armed, selected or keyed: DL1XYZ and W1AW never get a transmission. Red on the parent: Enable Tx off and the contact cancelled at the Auto off, no R-report keyed, nothing logged.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_001 from 'CL-081-01' to 'TC-081-001';
    verification 'TC-081-002' {
        doc /* TC-081-002 — What is a started QSO
             CL-081-01
             Setup: as TC-081-001; for (a), (b) and (d) the saved strategy "Casual 20 m" of class strategy (new [call] per band, cq_when_idle true, cq_wait_periods 2) calling CQ after two empty publications, Hold Tx off; each case from a new run.
             Steps: (a) W1AW FN31 calls my call during the CQ; the run answers; POST /strategy/auto {auto false} 2 s into the period in which our reply to W1AW is keyed; W1AW then sends R-.. and RR73 in turn. (b) The same, with Auto false after W1AW is selected and our reply armed, before its period starts; W1AW calls my call again for three periods. (c) The saved strategy "New calls" (new [call] per ever, order [most_wanted]) calling CQ K1ABC FN42, K1ABC silent; Auto false 2 s into the period of our second Tx1; then K1ABC answers HB9BLA K1ABC -05. (d) Auto false 2 s into a period in which the run's CQ is keyed, no caller.
             Expected (oracle: the definition of a started QSO in CL-081-01): (a) started: the reply's period ends normally (no abort, no halt), the exchange goes on to completed and one log entry of W1AW; (b) not started: Enable Tx off and the contact cancelled at once, no transmission to W1AW, his further calls not answered, nothing logged; (c) not started: the Tx1 on the air finishes its period (no abort, PTT released at its normal end), then nothing is keyed, the contact cancelled, K1ABC's answer not replied to, nothing logged; (d) the CQ on the air finishes its period, nothing keyed after it, no CQ contact left behind. Red on the parent: (a) Enable Tx off and cancelled at the Auto off; (b), (c) and (d) are regression guards, green on the parent.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_002 from 'CL-081-01' to 'TC-081-002';
    verification 'TC-081-003' {
        doc /* TC-081-003 — Every run end that lets a started QSO finish
             CL-081-01
             Setup: as TC-081-001; for (c) and (d) the contest WW Digi in force with a copy of its built-in (cq_when_idle false) and automation_confirmed (as TC-063-009); for (e) a pounce on K1ABC started by MCP with Auto off (as TC-039-042); for (f) and (g) an MCP policy run (as TC-020-003) with max_run_minutes 1 for (g) and the automation clock moved by the seam. Each case runs into the same started QSO: K1ABC FN42 called by the run, his answer HB9BLA K1ABC -05 decoded, then the end below, then his RR73 after our R-report.
             Steps: (a) PUT /strategy with active None; (b) PUT /strategy with the saved strategy "Farthest new on band" (order [distance]) while Auto is on, and CQ JA1XYZ PM95 published during the QSO and after its completion; (c) PUT /strategy without the contest; (d) the station clock past the contest period's end; (e) POST /strategy/auto {auto true} with the saved strategy "New calls" selected; (f) AutomationCommand stop of the run; (g) the run deadline passed; (h) POST /strategy/auto {auto false} sent twice, 1 s apart.
             Expected (oracle: the list of run ends in CL-081-01): every case completes K1ABC with exactly one log entry and keys nothing for another station until it has completed; the run's state and reason at the end: (a) stopped, Auto off; (b) the old run stopped, Auto on, the new run manual until the completion, then waiting, and JA1XYZ selected only from a publication after the completion; (c) stopped, Auto off; (d) waiting outside_period after manual, disarmed after the completion; (e) the pounce stopped, the strategy run manual until the completion; (f) stopped; (g) time_limit; (h) stopped once, the second request changes no revision and no contact. Red on the parent: each case disarms and cancels K1ABC at the end, nothing logged.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_003 from 'CL-081-01' to 'TC-081-003';
    verification 'TC-081-004' {
        doc /* TC-081-004 — The finishing QSO is bounded by the Tx watchdog, not by the run
             CL-081-01
             Setup: as TC-081-001 with the Tx watchdog set to 2 by the browser, the strategy's leave {calls 4, calls_heard 8}, a spot of my call at K1ABC 60 s old (he hears us: the leave rule would allow 8 calls), K1ABC called from Tx 1500 with the quietest slot elsewhere; the started QSO of TC-081-001.
             Steps: (a) Auto false after our 1st R-report; K1ABC sends RR73 after our 2nd R-report. (b) Auto false after our 1st R-report; K1ABC repeats HB9BLA K1ABC -05 every period. (c) Auto stays on while K1ABC repeats -05 until our R-report has been keyed 3 times (past the limit under the run's exemption, StrategyWatchdog); then Auto false.
             Expected (oracle: WstxQsoControl::TxWatchdog, limit 2, and CL-081-01): (a) the 2nd R-report keyed, then 73, completed, one log entry (the limit not passed); (b) the R-report keyed a 2nd time, never a 3rd: 1.2 s into that period Enable Tx goes off with cause txWatchdog, no halt, nothing logged; (c) the R-report not keyed again after the Auto off, Enable Tx off with cause txWatchdog at 1.2 s into the next due period; in every case after the Auto off no leaving (left null, no quiet entry), no Tx move (tx_hz stays 1500, slot_check unchanged), the hearing subscription of K1ABC dropped, and the contact snapshot's tx_remaining_calls that of the Tx watchdog. Red on the parent: (a) disarmed at the Auto off, never completed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_004 from 'CL-081-01' to 'TC-081-004';
    verification 'TC-081-005' {
        doc /* TC-081-005 — What still ends a finishing QSO at once
             CL-081-01
             Setup: as TC-081-001, Auto false sent in the started QSO and the R-report keyed once after it (the QSO finishing); a second run of (h) with Auto on.
             Steps: (a) HALT by route; (b) Abort QSO (ContactCommand abort); (c) a double-click of W1AW's call to my call (select_row replace true, then enable_tx); (d) the radio's dial to 7.074 MHz (band change); (e) the operating mode to FT4; (f) the browser grant revoked; (g) a safety edit; (h) with Auto on and the run still on, K1ABC silent after his report for 4 repetitions (no spot).
             Expected (oracle: the immediate stops of CL-081-01): (a) halted, the transmission stopped, nothing keyed after, nothing logged; (b) the transmission stopped now, the contact cancelled, nothing logged, no halt; (c) W1AW's contact replaces K1ABC's and is called, K1ABC never logged; (d), (e), (f) Enable Tx off and the contact cancelled at the next station step, nothing keyed after and nothing logged; (g) Enable Tx off with cause authorityChanged, nothing logged; (h) left {K1ABC, repetitions} at the 4th, disarmed and cancelled, waiting. Red on the parent: the precondition fails, the QSO is already ended at the Auto off ((h) is a regression guard, green on the parent).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_005 from 'CL-081-01' to 'TC-081-005';
    verification 'TC-081-006' {
        doc /* TC-081-006 — The Auto button says what Auto off does
             CL-081-01
             Setup: actual browser with hand-written replies for GET /strategy (a strategy selected, auto true, then false) and GET /contact (transmit capability available, a contact in progress with K1ABC), and pushed strategy.state and automation.state (as TC-039-046).
             Steps: read the Auto button's title with Auto on; push Auto off with the run stopped and the contact still in progress; read the button, the strategy line and the QSO pane.
             Expected (oracle: the texts of WstxAutoControl::AutoToggle and StrategySelector): with Auto on the title "Auto on: the selection transmits. Click to switch Auto off; a QSO already started is finished"; after the push the button grey with the title "Auto off: the selection only marks. Click to let it transmit", the line "Strategy New calls · Auto off" and the QSO pane still showing the contact with K1ABC. Red on the parent: the on title lacks the sentence on the started QSO.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_081_01_verified_by_TC_081_006 from 'CL-081-01' to 'TC-081-006';
    verification 'TC-081-007' {
        doc /* TC-081-007 — Live: Auto off in a QSO on HB9BLA
             CL-081-01
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 20 m or 40 m FT8 within the operator's standing transmit consent (1 W on 40 m), Tx watchdog 6; contact and run snapshots read from GET /contact and GET /automation at each step; the station log read before and after.
             Steps: Auto on with the saved strategy "Strongest new on band" (as TC-039-047); when a station has answered our call (his report decoded) switch Auto off in the browser; watch to the end of the QSO and two more periods; Auto on with the saved strategy "Casual 20 m" (as TC-039-045) until it calls CQ; switch Auto off while the CQ is keyed.
             Expected: after the first Auto off the Auto button grey and the line "Strategy Strongest new on band · Auto off" at once, the QSO goes on to RR73/73 and is logged once (one new log entry of that call), then nothing is keyed; after the second Auto off the CQ period ends normally and nothing is keyed after it; recorded on the issue.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-081-01';
        }
    }
    dependency CL_081_01_verified_by_TC_081_007 from 'CL-081-01' to 'TC-081-007';
    // #97 Strategy settings and ranking: one set of settings for every strategy (operator grill
    // 2026-11-09, re-scope 2026-11-12; takes over #84, #90, #91, #93, #94). Detailed contract in
    // WstxStrategy D19.
    requirement 'CL-097-01' {
        doc /* (#97, operator grill 2026-11-09 and 2026-11-12) There are two classes (operator grill Q12): strategy (Filters and Order from the filter questions) and contest (from a contest, CL-097-07); a strategy's class is never switched. strategy.json schema 4 holds, per strategy and in this order: name, class, bands, filters, order, contest, callers_first, leave, tx_move_every {heard, not_heard, no_reports}, busy_pause, cq_when_idle, cq_wait_periods, retry_minutes; each refusal names its field path. A strategy is new only as a duplicate (built-in or saved), keeping its class and contest. The editor shows the settings as the nine numbered decisions: 1 band, 2 filters, 3 order, 4 "Calling stations are answered", 5 leaving a station, 6 Tx frequency, 7 busy pause, 8 "CQ when idle, after <n> periods with nothing callable", 9 retry pause. Saved files of schema 1, 2 and 3 are upgraded at their revision as WstxStrategies::StrategyConfiguration maps them (a schema 3 strategy key by key, with cq_wait_periods 2), and a saved strategy whose name collides with a built-in is renamed, never dropped, with the rename shown once. Built-ins: the five of the table of 2026-11-09, DXCC all, New DXCC on band, New DXCC (until logged, gone 10 min, most wanted then SNR, CQ when idle off), Casual (new call per band, SNR bucket then distance, after 4 calls or 8 if he hears us, CQ when idle on) and POTA/SOTA (only CQ POTA and CQ SOTA, new call per band since today, SNR bucket then distance, after 4 calls or 8 if he hears us, CQ when idle off), all of class strategy, all bands, region all, Calling stations are answered on, Tx stay/every call/every 2nd call, busy pause on, retry 10 min; plus one contest built-in per contest (CL-097-07); each with cq_wait_periods 2. "DXCC all" is first in the list; no built-in is called the default, and active is None at a station start. A strategy defines values only: it never selects, calls, answers, arms or transmits. The settings of decisions 5 to 9 take effect only through the part that starts QSOs: the run (CL-097-04) until #119, then Auto. Details: WstxStrategies::Strategy, StrategyClass, BuiltinStrategies, StrategyConfiguration, StrategyEditor, StrategySelector, StrategyHttp. */
        attribute implementation : String = "server/src/strategy.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_01_to_FR_007 from 'CL-097-01' to 'FR-007';
    dependency CL_097_01_to_FR_016 from 'CL-097-01' to 'FR-016';
    dependency CL_097_01_to_FR_019 from 'CL-097-01' to 'FR-019';
    requirement 'CL-097-04' {
        doc /* (#97 decisions 5, 8 and 9, #91; the run that applies a strategy's settings, the stopgap until #119 replaces it with Auto) Leaving a station, one of three modes per strategy: after n calls without an answer, m while he hears us; until logged, leaving when he has not been decoded for n minutes; contest style, staying while he hears us and is still the most valuable, else leaving after n Tx changes. Progress (his message to my call) resets the count; a caller of my call with a rank (CL-097-03: it passes the filters and Calling stations are answered is on) is answered at once; unattended or past the run limit there is no m, no contest stay and no busy pause, and the Tx watchdog's stop at N is back. After every leaving the retry pause (minutes) passes before the station is called or answered again. WD:n shows only the Tx watchdog: in a run's own contact, which the Tx watchdog does not stop while attended, no WD is shown and the leave count has its own label ("Leave in n calls", "Until logged", "Leave in n Tx changes", "Stay · most valuable", with "busy, not counted" while the target is busy); GET /transmit watchdog.tx_remaining_calls is null for such a contact (never the leave count) and the receive page leaves its WD part out. Contest style counts change points; with "stay" for the case Tx never moves at them. Off the strategy's bands the run waits with reason band. The run's own select_row of a CQ whose directive word is on the active strategy's CQ target include list passes the directed-CQ check; every other automatic select_row of a non-answerable directive stays refused directive_not_answerable (an MCP or UDP command, a pounce, a run of a strategy without the word). With CQ when idle on the run calls CQ after the CQ wait (CL-097-08). Details: WstxStrategy::LeaveRule, QuietTime, LeaveCountLabel, StrategyWatchdog, StrategyRun, DirectedCqRule, CqWhenNoTarget; WstxQsoControl::ContactSnapshot, TxWatchdog. */
        attribute implementation : String = "server/src/automation.rs; server/src/contact_http.rs; client/contact.js; client/recording.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_04_to_FR_007 from 'CL-097-04' to 'FR-007';
    dependency CL_097_04_to_FR_008 from 'CL-097-04' to 'FR-008';
    requirement 'CL-097-06' {
        doc /* (#97 decision 7, operator #93 "we pause counting ... till the called station finishes its other qso") Busy pause: the called station is busy from his message to another call carrying a grid, report or R-report (a hashed call not filled with my call is another call) until he ends that QSO with RR73, RRR or 73 to another call, a CQ, free text or a message to my call, however long he is not decoded. The station keeps calling, on a split frequency: when he sends to another call and my signal is not 50 Hz clear of his (FT8 100 Hz, FT4 140 Hz between the lower edges), Tx moves to the nearest clear candidate from 500 Hz (also clear of decoded stations and of his PSK Reporter frequencies while one is free), Rx stays on him, also with Hold Tx on; a refused move stops as the WSJT-X rule does; an operator's own Tx wins until his next message to another call. This replaces the WSJT-X stop for every contact that pauses (a manual contact; a run's own contact with busy pause on), also while it is not pausing. A call is paused when he is busy at its stop point (1.2 s into the period) and is not counted: in a run with busy pause on, not toward leaving or Tx moves; in a manual contact, not toward the Tx watchdog. At most N paused calls per message (N the Tx watchdog limit), so nothing the partner does extends the bound; a pounce, an MCP policy run and a run with busy pause off never pause and keep the WSJT-X stop; unattended there is no pause. The contact snapshot carries busy_with and paused_calls within GET /contact's 4096 bytes, and the QSO pane shows "<call> busy with <other>, not counted (k/N)". Details: WstxOperatingChain::BusyPartner, TxWatchdog, AutoSequence; WstxStrategy::BusyPause, FreeTxSlot. */
        attribute implementation : String = "server/src/contact.rs; server/src/freeslot.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_06_to_FR_007 from 'CL-097-06' to 'FR-007';
    dependency CL_097_06_to_FR_008 from 'CL-097-06' to 'FR-008';
    requirement 'CL-097-07' {
        doc /* (#97, interface to #98) A strategy of class contest names a contest id of the contest table, has order [], and has filters {countries, states, cq_targets}: the contest supplies its rules (dupes, points, multipliers, ranking) and the strategy its other settings. Each contest has a read-only contest built-in with leave contest style after 2 Tx changes, tx_move_every {0, 2, 2}, busy_pause off, cq_when_idle on, cq_wait_periods 2 and retry_minutes 10. The contest prompt offers the built-in and the saved contest strategies of that contest; the prompt's choice and period select it. There is no operation choice and no per-contest repetitions or retry pause: with cq_when_idle on the strategy's CQ when idle applies. Details: WstxContest D11, ContestSelection, ContestPrompt, ContestRun, ContestValueOrder; WstxStrategies::StrategyClass, BuiltinStrategies. */
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/automation.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_07_to_FR_007 from 'CL-097-07' to 'FR-007';
    dependency CL_097_07_to_FR_020 from 'CL-097-07' to 'FR-020';
    requirement 'CL-097-08' {
        doc /* (#97 decision 8, operator 2026-11-12) The CQ wait: cq_wait_periods is an integer 1..20, default 2, in every strategy of both classes; anything else, also a missing key, is refused at strategies[i].cq_wait_periods. With cq_when_idle on, the part that starts QSOs calls CQ only after this many consecutive fresh complete publications with nothing callable. Every period counts, in both parities: 2 is 30 s in FT8 and 15 s in FT4. The count starts at 0 at Auto on, after a QSO ends and after a leaving. With cq_when_idle off the value has no effect and is kept. Details: WstxStrategies::Strategy, CqWhenNoTarget, StrategyConfiguration, StrategyEditor. */
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_08_to_FR_007 from 'CL-097-08' to 'FR-007';
    dependency CL_097_08_to_FR_020 from 'CL-097-08' to 'FR-020';
    verification 'TC-097-001' {
        doc /* TC-097-001 — Strategy schema 4 on the wire
             CL-097-01, CL-097-08
             Setup: the actual station store and router on a disposable HTTPS profile; hand-written configurations; the expected acceptances and refusals written in the test from WstxStrategies::Strategy.
             Steps: PUT one strategy of each class with every key at its bounds (bands null and 32 bands; new with 1 and 7 whats; countries with 64 entries in each list, each {kind "prefix", value of 3 characters, bands null} except one entry with a 13-character prefix and one with 32 bands, states 51, cq_targets 32 of 8 characters; the test asserts the encoded body is below 32768 bytes; order with 16 criteria; each leave mode at its lower and upper bounds; tx_move_every 0 and 20; cq_wait_periods 1 and 20; retry_minutes 1 and 120); then one refusal each: cq_wait_periods 0, 21, "2", null and missing; band "11m", a repeated band, 33 bands; new [] and a repeated what; new_per "slot"; a country entry of kind "call", prefix "VK-9", a prefix of 14 characters, an entry with 33 bands, a country name not in the table, 65 entries; state "XX" and "PR", 52 states; a CQ target of 9 characters and "PO-TA", 33 CQ targets; an order with a repeat and with 17; leave calls 0 and 21, calls_heard below calls and 41, gone_minutes 0 and 61, tx_changes 0 and 21, mode "never"; tx_move_every -1, 21 and a missing case; retry_minutes 0 and 121; a contest strategy with order [most_wanted], with filters.new, with contest null and "unknown"; a class strategy with contest "ww_digi"; class "award" and "casual" (refused values); names "DXCC all" and "casual"; each schema 3 key (goals, needed, value, window, repetitions, quiet_minutes, cq_when_no_target) and builtin; a configuration whose body exceeds 32768 bytes.
             Expected: the first PUT accepted with revision + 1 and read back key for key; each refusal 400 invalid_request naming exactly its field path (strategies[0].bands[0], strategies[0].filters.countries.include[0].value, strategies[0].leave.calls_heard, strategies[0].cq_wait_periods for each CQ wait refusal, strategies[0].class, strategies[1].order, strategies[1].contest, strategies[0].name ...; strategy 0 of class strategy, 1 of class contest), nothing stored; the oversized body refused as every oversized body. Red on the parent: cq_wait_periods is refused as an extra key.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_01_verified_by_TC_097_001 from 'CL-097-01' to 'TC-097-001';
    dependency CL_097_08_verified_by_TC_097_001 from 'CL-097-08' to 'TC-097-001';
    verification 'TC-097-002' {
        doc /* TC-097-002 — Upgrade of saved strategy.json files to schema 4
             CL-097-01, CL-097-08
             Setup: the actual station store on a disposable profile; hand-written strategy.json files of schema 1, 2, 3 and 4; the expected schema 4 strategies written in the test from the mapping table of WstxStrategies::StrategyConfiguration.
             Steps: a schema 3 file at revision 7 with "Mine" (goals [dxcc_band, new_call], needed not_confirmed, value [new_dxcc_slot, snr], repetitions 5, quiet_minutes 15, cq_when_no_target true, treat_73_as_cq false, window today, region dx), "Grid" (goals [grid]), "DXCC all", "dxcc all copy" and "Casual"; GET /strategy; PUT one change; read the file; a schema 3 file with an otherwise malformed strategy. The schema 2 store cases: a schema 2 file at revision 7 with "Mine" (goals [new_call], calls_per_station 5); GET /strategy; PUT a change; read the file; schema 2 strategies with calls_per_station 0, 21, missing, a bad region and a value key; a schema 3 file holding a schema 2 strategy. A schema 4 file with one strategy without cq_wait_periods and one with cq_wait_periods 5. Then the TC-039-030 goal fixtures evaluated through their mapped schema 4 strategies.
             Expected: revision 7; "Mine" class strategy, new [dxcc, call], new_per band (the most specific of band and ever), new_means not_confirmed, worked_since today, region dx, treat_73_as_cq false, the three lists empty, order [new_dxcc_band_mode, snr], contest null, leave {calls, 5, 10}, tx_move_every {0, 1, 2}, busy_pause true, cq_when_idle true, cq_wait_periods 2, retry_minutes 15; "Grid" new [grid] per ever; "DXCC all" renamed "DXCC all copy 2" ("dxcc all copy" is taken, ignoring case) and "Casual" renamed "Casual copy", configuration_note listing both; the malformed file configuration null with invalid_configuration; after the PUT the file is schema 4 at revision 8 and configuration_note []. Schema 2: revision 7 with "Mine" as schema 3 with value [most_wanted], callers_first true, cq_when_no_target false, repetitions 4 and quiet_minutes 10 reads it, mapped to schema 4 (new [call] per ever, leave {calls 4, calls_heard 8}, retry_minutes 10, cq_wait_periods 2); the PUT writes schema 4 at revision 8; each malformed one configuration null with invalid_configuration. Schema 4: the strategy without the key reads cq_wait_periods 2, the other 5. Each mapped goal gives the verdicts TC-039-030 expects of its goal (property: the same ranked set). Red on the parent: the strategies read without cq_wait_periods.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_01_verified_by_TC_097_002 from 'CL-097-01' to 'TC-097-002';
    dependency CL_097_08_verified_by_TC_097_002 from 'CL-097-08' to 'TC-097-002';
    verification 'TC-097-003' {
        doc /* TC-097-003 — The built-in strategies and the contest built-ins
             CL-097-01, CL-097-07, CL-097-08
             Setup: the expected table written in the test from the operator's table on #97 and the contest defaults; the actual station router on a disposable HTTPS profile with today's contest profile table; the contact engine and #9 owner on the recording hardware double.
             Steps: GET /strategy; PUT active "DXCC all", "casual", "New calls"; PUT active "WW Digi" without a contest selection and with {ww_digi, start, end}; a station restart; GET /strategy.
             Expected: builtin_strategies exactly DXCC all, New DXCC on band, New DXCC, Casual, POTA/SOTA in this order, all five class strategy, with every key of the table (POTA/SOTA: worked_since today, cq_targets include [POTA, SOTA], cq_when_idle false), then one contest built-in per profile (class contest, contest its id, order [], leave {contest, 2}, tx_move_every {0, 2, 2}, busy_pause false, cq_when_idle true, retry_minutes 10), every built-in with cq_wait_periods 2, "DXCC all" first, no built-in named a default, none in configuration.strategies; "DXCC all" accepted; "casual" and "New calls" refused field active; "WW Digi" refused field contest without the selection and accepted with it; after the restart active None and auto false (DXCC all first in the list, not selected). Red on the parent: the built-ins carry no cq_wait_periods.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-07';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_01_verified_by_TC_097_003 from 'CL-097-01' to 'TC-097-003';
    dependency CL_097_07_verified_by_TC_097_003 from 'CL-097-07' to 'TC-097-003';
    dependency CL_097_08_verified_by_TC_097_003 from 'CL-097-08' to 'TC-097-003';
    verification 'TC-097-009' {
        doc /* TC-097-009 — The three leave modes and the retry pause
             CL-097-04
             Setup: as TC-039-043 (the actual router, contact engine and #9 owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz, Hold Tx off), Tx watchdog 6; the run calling K1ABC (CQ FN42); one strategy per mode.
             Steps: (a) leave {calls 4, calls_heard 8}: K1ABC silent; the same with a spot of my call 60 s old; the spot ageing past 600 s after the 5th call. (b) leave {until_logged, gone_minutes 10}: K1ABC calling CQ every period for 30 minutes; K1ABC last decoded at t0 then silent, publications at t0 + 9 min 45 s and t0 + 10 min; K1ABC answers -05, then silent. (c) leave {contest, tx_changes 2} with tx_move_every {0, 2, 2}: K1ABC silent with no spot; K1ABC calling CQ with a spot and nothing more valuable for 20 periods; the same with a more valuable callable station listed from the 3rd period, with tx_move_every heard 0 (the contest built-in's) and with heard 1; tx_move_every no_reports 0. (d) An answer after the 3rd call, then silence. (e) retry_minutes 10: K1ABC's CQ after the leaving at 9 min 59 s and 10 min, its call to my call at 5 min. (f) No client for 60 s in each mode. (g) A caller of my call that passes the filters at the 2nd call in each mode.
             Expected (hand-worked from WstxStrategy::LeaveRule): (a) left at the 4th call {K1ABC, repetitions}; with the spot at the 8th; back to 4 once the spot is older than 600 s (left at the 5th); (b) never left while decoded (30 minutes); left {K1ABC, gone} at t0 + 10 min, not at t0 + 9 min 45 s; after the answer left 10 minutes after his last decode; (c) Tx moved after the 2nd and the 4th call and left {K1ABC, tx_changes} at the 6th (three slots); staying all 20 periods; counting from the 3rd: with heard 0 Tx never moves and K1ABC is left {tx_changes} at the 5th call (change points at the 3rd and 4th, leaving at the 5th), with heard 1 Tx moves at the 3rd and 4th and he is left at the 5th; with no_reports 0 Tx never moves and he is left at the 3rd call; (d) the counts back to 0; (e) not selected at 9 min 59 s nor answered at 5 min, selected at 10 min; (f) calls: left at 4 also with the spot; until_logged and contest: no stay, ended by the Tx watchdog's stop at 6; (g) left {K1ABC, caller} and the caller selected from the same publication. Red on the parent: the modes are refused.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-04';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_097_04_verified_by_TC_097_009 from 'CL-097-04' to 'TC-097-009';
    verification 'TC-097-011' {
        doc /* TC-097-011 — A busy partner in a strategy run
             CL-097-06
             Setup: as TC-039-043 (the actual router, contact engine and #9 owner on the recording hardware double, virtual UTC, 20m FT8, Hold Tx on, waterfall rows on a flat floor so every candidate is free), a strategy with leave {calls 4, calls_heard 8}, busy_pause on (and off), Tx watchdog 3; the run calling KE1J from Tx 1500, KE1J's CQ at 1800 Hz; hand-authored decodes of KE1J to other calls.
             Steps: (a) KE1J sends W9XYZ KE1J -07 at 1200 Hz for two of his periods, then W9XYZ KE1J RR73, then CQ; (b) KE1J sends W9XYZ KE1J R-09 at 1510 Hz; (c) after (a)'s report, three periods without a decode of KE1J, then W9XYZ KE1J RR73; (d) KE1J busy for 5 periods; (e) KE1J sends HB9BLA KE1J -10 after being busy; (f) (a) and (b) with busy_pause off; (g) KE1J busy at 1510 Hz while the run is unattended; (h) KE1J sends W9XYZ KE1J FN42 and later W9XYZ KE1J 73; (i) KE1J goes on from W9XYZ to K2ABC with a report, then sends free text.
             Expected (hand-worked from WstxOperatingChain::BusyPartner and WstxStrategy::BusyPause): (a) our call keyed in every period, leave.busy true, paused 1 and 2, remaining stays 4; the RR73 ends it and the next call counts (remaining 3); (b) Tx moves before our next period to 1410 (the nearest candidate at least 100 Hz from 1510, FT8), Rx stays 1800, Enable Tx stays on, the call goes on; (c) the three calls without his decode stay paused (busy holds), the call after the RR73 counts; (d) 3 paused calls, the 4th and 5th count (N = 3); (e) progress resets every count; (f) the calls count and KE1J is left at the 4th; (b) disarms as partnerWorksOther does; (g) the calls count (no pause unattended) and Tx still moves to 1410, Enable Tx on, until the stop at N; (h) the grid to another starts busy, the 73 ends it; (i) busy holds across K2ABC and ends with the free text; no TxMoveRule move while busy. Red on the parent: the busy calls count and (b) disarms.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-06';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_06_verified_by_TC_097_011 from 'CL-097-06' to 'TC-097-011';
    verification 'TC-097-012' {
        doc /* TC-097-012 — Reproduction: a manual call to a busy station (KE1J, #93)
             CL-097-06
             Setup: the actual contact engine and router on the recording hardware double, virtual UTC, 10m FT4, Tx watchdog 6 set by the browser, Hold Tx on, no run; the operator double-clicks CQ KE1J at 1800 Hz with Tx 1500 (KE1J HB9BLA JN37 due).
             Steps: (a) the reproduction of 2026-11-09 14:39 UTC: KE1J works W9XYZ for 8 of his periods (reports at 1200 Hz), then W9XYZ KE1J RR73, then silent; (b) KE1J works a station at 1520 Hz; (c) KE1J busy for 10 periods; (d) after the stop, the operator's Enable Tx; (e) the limit set to 2 and (c) again.
             Expected (oracle: operator #93 "Keep calling, don't count" and the bound of WstxQsoControl::TxWatchdog): (a) our Tx1 keyed in each of the 8 periods, the first 6 paused (WD:6 with " · KE1J busy with W9XYZ, not counted (k/6)", tx_expired false), the 7th and 8th counted (WD:5, WD:4), then counted after the RR73, stopped at the 12th send with "Tx watchdog: same message sent 6 times"; (b) Tx moves to 1380 (the nearest candidate at least 140 Hz from 1520, FT4), Rx stays 1800, Enable Tx stays on, Hold Tx still on; (c) stopped at the 12th send; (d) the counts restart; (e) 2 paused, stopped at the 4th send. Red on the parent: stopped at the 6th send in (a), (b) disarms.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-06';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_097_06_verified_by_TC_097_012 from 'CL-097-06' to 'TC-097-012';
    verification 'TC-097-013' {
        doc /* TC-097-013 — Reproduction: WD:n is the Tx watchdog only, the leave count has its own label (#91)
             CL-097-04
             Setup: the actual router (contact and run snapshots) and Chromium with routed replies and pushed events as TC-039-046; Tx watchdog 6.
             Steps: (a) the #91 run of 2026-11-09: a run calling M7HNI with M7HNI HB9BLA +15, M7HNI repeating his message so that the leave count resets; (b) a run's own contact with leave {calls 4, calls_heard 8}, attended, then unattended; (c) a contest stay; (d) until_logged; (e) a manual contact; (f) a busy partner in the run and in the manual contact; (g) GET /transmit and the receive page's transmit line during (b) attended, (b) unattended and (e).
             Expected (oracle: WstxStrategy::LeaveCountLabel and WstxQsoControl::ContactSnapshot): (a) no WD text in the run's own contact, tx_remaining_calls null, the label "Leave in <n> calls" going back up on his message; (b) "Leave in 4 calls" .. "Leave in 1 calls"; unattended WD:n with the Tx watchdog's count; (c) "Stay · most valuable", never "WD:∞"; (d) "Until logged", then "Until logged · leave if gone <n> min"; (e) WD:6 down to WD:1; (f) the busy suffixes; (g) watchdog.tx_remaining_calls null while armed in (b) attended and the transmit line without a WD part, an integer (the Tx watchdog's) unattended and in (e) with "WD <n> calls". Red on the parent: WD:2 then WD:6 in (a); GET /transmit reports the leave countdown.
             2 — Isolated automated tests and browser test; Windows development PC; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-04';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/strategy_tests.rs; server/src/contact_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_097_04_verified_by_TC_097_013 from 'CL-097-04' to 'TC-097-013';
    verification 'TC-097-014' {
        doc /* TC-097-014 — The editor and the selector in the browser
             CL-097-01
             Setup: the actual isolated server and Chromium at 1366x768 and 360x740; routed replies for GET and PUT /strategy and POST /strategy/evaluate; a snapshot with the built-ins, two saved strategies of class strategy (an award-like and a casual-like one) and one of class contest, and configuration_note [{from "Casual", to "Casual copy"}].
             Steps: open the editor; read the decisions of "DXCC all", decision 4's label, decision 8 and every text of the editor; Duplicate "DXCC all"; set every control of the nine decisions (the CQ wait 5); look for a class control; open the contest strategy; enter a country name that the station refuses; Save; close; open the selector; choose the saved contest strategy (contest ww_digi) with no contest in force, then with ww_digi in force, then with another contest in force (FT8 Activity in the test), and Cancel and Start in the prompt it opens.
             Expected (oracle: WstxSettings::StrategyEditor and StrategySelector): the list grouped Strategy, Contest, no Add; the headings 1 Band .. 9 Retry pause with decision 4 "Calling stations are answered" (its checkbox labelled the same) and decision 8 reading "CQ when idle, after <n> periods with nothing callable" with n 2 for the built-in; no "default" in the editor's text or options; "DXCC all copy" of class strategy with the nine decisions in order and their labels; Save sends exactly one PUT whose strategy is the schema 4 object written in the test, key for key, with cq_wait_periods 5; the class shown and never switchable; the contest strategy shows its contest read-only, only the three lists and "Ranked by the contest's rules"; the refusal shown at the country control; "Renamed Casual to Casual copy" shown once; the selector grouped with "DXCC all" first and no contest built-ins; one evaluate request 400 ms after an edit; no horizontal overflow at 360 px; choosing the contest strategy with no contest or with another contest in force (FT8 Activity in the test) sends nothing and opens the prompt on WW Digi with that strategy chosen and the period pre-filled, Cancel sends nothing and the selector returns to the earlier selection, Start sends one PUT {active the strategy, contest {ww_digi, start, end}}; with ww_digi in force it sends one PUT with that active and the same contest key. Red on the parent: decision 4 is headed "Callers first" and decision 8 has no CQ wait.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-08';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_097_01_verified_by_TC_097_014 from 'CL-097-01' to 'TC-097-014';
    dependency CL_097_08_verified_by_TC_097_014 from 'CL-097-08' to 'TC-097-014';
    verification 'TC-097-015' {
        doc /* TC-097-015 — Contest strategies: the prompt and the selection
             CL-097-07
             Setup: as TC-039-044 (WW Digi, 20m, the period in force, Auto on with automation_confirmed); the contest built-in "WW Digi" and a saved copy "WW Digi fast"; the prompt in Chromium with routed replies. The contest strategy's run is TC-097-018's.
             Steps: open the prompt, choose WW Digi, Start with the built-in; PUT a contest selection with operation "run"; active a strategy of class strategy with the contest.
             Expected (oracle: WstxContest D11 and WstxStrategies::BuiltinStrategies): the prompt offers "WW Digi" first and "WW Digi fast", with no operation choice and no repetitions or retry pause; Start sends one PUT {active "WW Digi", contest {ww_digi, start, end}}; the PUTs refused 400 field contest.operation and contest. Status "Contest WW Digi · <period> UTC · WW Digi · Auto on". Red on the parent: the prompt offers an operation choice.
             2 — Isolated automated functional and browser tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-07';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_097_07_verified_by_TC_097_015 from 'CL-097-07' to 'TC-097-015';
    verification 'TC-097-016' {
        doc /* TC-097-016 — Live: DXCC all and Casual on HB9BLA
             CL-097-01, CL-097-02, CL-097-03, CL-097-04, CL-097-05, CL-097-06, CL-097-07, CL-097-08
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 20m or 40m FT8 within the operator's standing transmit consent (1 W on 40m), Tx watchdog 6, PSK Reporter on and Use PSK Reporter on, Hold Tx on; contact and run snapshots read from GET /contact and GET /automation at each step.
             Steps: select "DXCC all" with Auto off for two periods; Auto on until a QSO is logged or a target is left gone; when a called station works another station, watch it; select "Casual", let it call CQ with nothing callable, answer a caller to a logged QSO and leave a silent station; a duplicate of Casual with Calling stations are answered off while a station calls my call; open the editor; note tx_hz, slot_check and the leave label at each repetition.
             Expected: with Auto off only stations of a DXCC entity not confirmed on this band and mode are marked; Casual calls CQ after 2 empty periods, and again 2 periods after the QSO; with callers off a station calling my call has no mark and is not answered; the editor shows the nine decisions with the CQ wait; a target stays until logged or not decoded for 10 minutes; no slot below 500 Hz is chosen; Tx stays when he hears us, moves every call when he reports and does not hear us, every 2nd call when he does not report; while a target is busy the calls go on, are not counted, and Tx is never within 50 Hz of his signal; the QSO pane shows the leave label and no WD in the run's own contact; Casual leaves after 4 calls (8 while heard) and does not answer a caller worked on the band; recorded on the issue.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-02';
            verify 'CL-097-03';
            verify 'CL-097-04';
            verify 'CL-097-05';
            verify 'CL-097-06';
            verify 'CL-097-07';
            verify 'CL-097-08';
        }
    }
    dependency CL_097_01_verified_by_TC_097_016 from 'CL-097-01' to 'TC-097-016';
    dependency CL_097_04_verified_by_TC_097_016 from 'CL-097-04' to 'TC-097-016';
    dependency CL_097_06_verified_by_TC_097_016 from 'CL-097-06' to 'TC-097-016';
    dependency CL_097_07_verified_by_TC_097_016 from 'CL-097-07' to 'TC-097-016';
    dependency CL_097_08_verified_by_TC_097_016 from 'CL-097-08' to 'TC-097-016';
    verification 'TC-097-017' {
        doc /* TC-097-017 — Busy start and end, the split-frequency table and the busy marker (cases carried over from the #93 draft fca9822fe)
             CL-097-06
             Setup: the actual contact engine and router on the recording hardware double, virtual UTC, FT8 and FT4, Tx watchdog 6 set by the browser, Hold Tx on; a manual contact calling KE1J (CQ at 1800 Hz) from Tx 1500, KE1J HB9BLA JN37 due; hand-authored codec-packed decodes of KE1J published at set offsets into my period; waterfall rows on a flat floor except where a step names a decoded station; a feed without a connection fed hand-authored spots; Chromium with routed replies for the screen steps.
             Steps: (a) start and end: KE1J to W9XYZ with a grid, a report, an R-report; KE1J to "<...>" whose hash is not my call's, and one whose hash is my call's; then each end in turn: RR73, RRR, 73 to W9XYZ, CQ KE1J, free text "TNX QSO", HB9BLA KE1J -10. (b) timing: the publication that starts busy arriving 1.1 s into my period, and in another run 1.3 s (the stop point 1.2 s), with the message at its limit. (c) split table, FT8: KE1J to W9XYZ with |Tx - his frequency| 0, 50, 51, 99, 100 Hz; FT4: 139 and 140 Hz; the only candidates clear of him below 500 Hz and at 500 Hz; a decoded station on the nearest clear candidate; a PSK spot of KE1J decoding another sender within 50 Hz of the nearest clear candidate in my Tx parity, and in the other parity; his decode arriving before the audio start of my next send, and after it; set_frequency refused for the move; the operator clicking Tx onto his signal while he is still busy, then his next message to W9XYZ. (d) marker: GET /contact while busy with W9XYZ, with a 13-character other call and the maximum snapshot shape of TC-007-004; the QSO pane and the station bar.
             Expected (hand-worked from WstxOperatingChain::BusyPartner and TxWatchdog): (a) the grid, report and R-report start busy_with W9XYZ; the unresolved hash starts busy_with "<...>", the hash of my call is a message to me (progress, no busy); each end clears busy_with and the next send counts; (b) at 1.1 s the send at the limit is paused and keyed; at 1.3 s it is stopped by the Tx watchdog (Enable Tx off, txWatchdog) and the busy counts from the next send; (c) FT8 0, 50, 51 and 99 Hz move Tx, 100 Hz does not; FT4 139 moves, 140 does not; never below 500 Hz (500 chosen when it is the nearest clear); the decoded station's slot skipped while another is clear; the slot near his PSK frequency of my Tx parity skipped (the other parity does not skip); before the audio start the pending request carries the new offset, after it that send finishes at the old offset and the next is moved; the refused move turns the transmit state off with cause partnerWorksOther (the partnerWorksOther stop), nothing keyed on his signal; the operator's Tx kept until his next message to W9XYZ, then moved again; (d) watchdog.busy_with "W9XYZ" and paused_calls k, GET /contact at most 4096 bytes in the maximum shape with the 13-character call; " · KE1J busy with W9XYZ, not counted (k/6)" after WD:n in the QSO pane and the station bar, gone with busy_with null. Red on the parent: (c) disarms at 0 and 50 Hz, no busy_with key.
             2 — Isolated automated functional and browser tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-06';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy97_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_097_06_verified_by_TC_097_017 from 'CL-097-06' to 'TC-097-017';
    verification 'TC-097-018' {
        doc /* TC-097-018 — The run applies the strategy's settings, and the CQ wait
             CL-097-04, CL-097-08
             Setup: the actual station router, contact engine and #9 owner on the recording hardware double, virtual UTC, 20m FT8, Auto on. For the CQ wait the saved strategy "Casual 20 m" of TC-039-045 (W1AW worked on 20m today) with cq_when_idle and cq_wait_periods set per step, and "Test calls" of TC-039-043 with leave {calls 1, calls_heard 2}, cq_when_idle true and cq_wait_periods 3. For the run: "Test calls" with bands ["20m", "40m"]; the built-in POTA/SOTA; a duplicate of Casual with min SNR -10 (W1AW worked on 20m); the WW Digi built-in and its copy "WW Digi fast" (leave {contest, 1}, cq_when_idle false, countries exclude [country "Japan"]) of TC-097-015 with W1DUP a dupe in the log.
             Steps: (a) cq_when_idle on with cq_wait_periods 1, 2 and 5: empty publications of alternating parity (every 15 s) until the CQ. (b) cq_when_idle off with cq_wait_periods 1: eight empty publications. (c) cq_wait_periods 3: one empty publication, Auto off and on, then empty publications. (d) cq_wait_periods 3: one empty publication, N1NEW FN31 calling my call (a callable station before the CQ is due), his R-05 and 73, then empty publications. (e) "Test calls": one empty publication, then CQ K1ABC FN42 selected, K1ABC silent at the next publication, then empty publications. (f) Bands: the run on 15m with CQ K1ABC FN42 published; the dial to 20m; on 20m in a contact with K1ABC, the dial to 17m. (g) POTA/SOTA with CQ POTA K1ABC FN42; the operator's double-click of it with POTA/SOTA active and Auto off; an MCP select_row of the CQ POTA row; a run of "Test calls" (no POTA on its include list) with CQ POTA K1ABC. (h) The Casual duplicate: W1AW calls my call, then W1AW and N1NEW FN31; a QSO with K1ABC whose answer -05 is decoded at -15 dB; the operator's double-click of W1AW's call. (i) WW Digi: one and two empty publications; CQ JA1XYZ PM95, CQ K1ABC FN42 and the dupe W1DUP calling my call; a JA caller of my call; then "WW Digi fast" with six empty publications, the same stations, K1ABC silent without spots.
             Expected (hand-worked from WstxStrategy::CqWhenNoTarget, StrategyRun, LeaveRule, DirectedCqRule and CL-097-08): (a) waiting after one fewer empty publication than the CQ wait, then calling_cq at exactly that many (state calling, Tx6 "CQ HB9BLA JN47", armed), both parities counted; (b) never a CQ, nothing armed; (c) still waiting after the 2nd empty publication after Auto on, calling_cq at the 3rd; (d) N1NEW answered (report), the QSO completed; then waiting at 2 empty publications and calling_cq at the 3rd; (e) left {K1ABC, repetitions}; then waiting at 2 empty publications and calling_cq at the 3rd; (f) the run waits with reason band and arms nothing on 15m; after the retune it selects K1ABC from the next publication; the retune to 17m disarms and cancels the contact at the next step (no retry entry) and the run waits band; (g) K1ABC selected (the run's own select_row accepted), armed and its Tx1 "K1ABC HB9BLA JN47" keyed in the next own period; the double-click refused 409 directive_not_answerable (the warning); the MCP select_row refused directive_not_answerable; "Test calls" never selects it; (h) W1AW never answered by the run, N1NEW answered; K1ABC's answer is progress (roger report due, not left); the double-click starts a manual QSO with W1AW (state manual); (i) no CQ after one empty publication, the CQ after the second; JA1XYZ selected (first by ContestValueOrder) and the CQ ended, W1DUP never answered, the JA caller answered at once; under "WW Digi fast" no CQ, JA1XYZ and the JA caller without rank, K1ABC selected, moved after the 2nd call (no_reports, every 2nd call) and left {K1ABC, tx_changes} at the 4th. Red on the parent: the CQ after 2 publications for 1 and for 5, and at the 2nd in (c), (d) and (e).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-04';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_04_verified_by_TC_097_018 from 'CL-097-04' to 'TC-097-018';
    dependency CL_097_08_verified_by_TC_097_018 from 'CL-097-08' to 'TC-097-018';
    verification 'TC-097-019' {
        doc /* TC-097-019 — The model carries no superseded wording
             CL-097-01, CL-097-02, CL-097-03, CL-097-07
             Setup: the files docs/sysml/*.sysml as read by the test; the patterns and scopes written in the test from lists A and B of #97.
             Steps: (1) the doc bodies rewritten into settings or ranking text: WstxStrategy package doc lines D1, D2, D3, D15, D19 and the docs of StrategyClass, NewWhat, NewPer, ValueCriterion, Needed, LeaveMode, PskCase, Strategy, StrategyBands, CountryList, UsStateFilter, UsStateOf, CqTargetList, BuiltinStrategies, StrategyConfiguration, NewNeeded, CallerOfMyCall, Candidate, ValueOrder, Verdict, StrategyEditor; the WstxContest package doc before D1 and its lines D1 and D11, and the docs of ContestSelection, ContestPrompt, ContestValueOrder, ContestView; the docs of CL-039-01, CL-039-02, CL-039-04, CL-039-11, CL-042-01, CL-063-03; each searched for P1 (the run vocabulary: run, runs, StrategyRun, ManualIntervention, the search-and-pounce operation, pounce, policy run, select_row, enable_tx), P2 (a strategy or contest strategy that selects, calls, answers, leaves, arms, transmits or starts) and P3 (a replacement or target note, ignoring case), with the patterns of #97's TC-097-019 written in the test. (2) every file searched for the old setting vocabulary of #97's check 2 (the operation choice, the per-contest repetitions and quiet time, the CQ option and the goals of schema 3, the callers rule of D5 and the old callers label, the award class), except the refused-keys sentences of WstxStrategies::Strategy and WstxStrategies::ContestSelection, the upgrade text of WstxStrategies::StrategyConfiguration, TC-097-001 and TC-097-002. (3) every file searched for a #97 note or label (the issue number followed by a colon, with or without a parenthesis between).
             Expected: no match in any of the three searches; a failure names each hit as file:line and the matched text. Red on the parent: the hits of lists A and B (search 1 in WstxStrategy D1, D2, D19, CallerOfMyCall, CqTargetList, UsStateOf, Verdict, StrategyEditor, the WstxContest package doc and D11, ContestSelection, ContestPrompt, ContestView, CL-039-01, 02, 04, 11, CL-042-01, CL-063-03; search 2 in Strategy, Contest, Contact, ProductScope and Requirements; search 3 the #97 notes and labels).
             2 — Isolated automated test; Windows development PC; no browser, radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-02';
            verify 'CL-097-03';
            verify 'CL-097-07';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_097_01_verified_by_TC_097_019 from 'CL-097-01' to 'TC-097-019';
    dependency CL_097_07_verified_by_TC_097_019 from 'CL-097-07' to 'TC-097-019';
}
