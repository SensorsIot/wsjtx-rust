package WstxOperatingLayout {
    private import ScalarValues::*;
    private import WstxProfiles::HttpProfileRepresentation;
    private import WstxProfiles::HttpProfilePut;
    private import WstxSignalArea::DisplayLevels;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-010';
    private import WstxArchitecture::'FR-019';
    private import WstxArchitecture::'FR-021';
    private import WstxArchitecture::'FR-004';
    private import WstxArchitecture::'FR-007';
    private import WstxStandardQso::'TC-007-003';
    private import WstxArchitecture::'FR-022';
    private import WstxRequirements::AutomationState;
    private import WstxTransmit::'TC-092-005';
    private import WstxContact::'TC-039-046';
    private import WstxContact::'TC-039-006';
    private import WstxContact::'TC-039-007';
    private import WstxStationProtocol::'TC-051-001';
    private import WstxStationProtocol::'TC-051-003';
    private import WstxArchitecture::'FR-008';
    private import WstxContact::'TC-065-004';
    private import WstxContact::'TC-082-005';
    private import WstxContact::'TC-082-006';
    private import WstxArchitecture::'FR-003';
    private import WstxArchitecture::'FR-001';
    private import WstxArchitecture::'FR-009';
    private import WstxStandardQso::'TC-007-004';
    private import WstxStationProtocol::'CL-003-08';
    private import WstxUdp::'CL-040-02';
    private import WstxReceiveStartup::'CL-045-01';
    private import WstxUdp::'CL-112-01';
    private import WstxStationProtocol::'TC-021-006';
    private import WstxModemDecode::'TC-004-001';
    private import WstxModemDecode::'TC-004-002';
    private import WstxModemDecode::'TC-004-003';
    private import WstxRecordingReceive::'TC-009-004';
    private import WstxStationProtocol::'TC-009-005';
    private import WstxStationProtocol::'CL-022-02';
    private import WstxRadioIO::'CL-022-03';
    private import WstxCatLifecycle::'CL-022-04';
    private import WstxStationProtocol::'CL-022-05';
    private import WstxArchitecture::'FR-002';
    private import WstxModemDecode::'TC-057-002';
    private import WstxLiveReceive::'CL-007-05';
    private import WstxModemDecode::'CL-057-02';
    private import WstxContact::'CL-055-02';
    private import WstxTransmit::'TC-111-015';

    doc /* Implementation contract for the profile-mode read-only operating layout.
         Contract: WstxProductScope::ContractIndex4.7.1 and6.6 TC007002. Existing signal and
         profile contracts are reused, not redefined. Full QSO/TX/log behavior is
         outside this slice. No modeled verification verdict is asserted. */

    enum def CapabilityState { enum unsupported; enum unavailable; enum available; }
    enum def LinkState { enum connecting; enum connected; enum stale; }
    enum def SecondaryRegion { enum settings; enum recording; }

    attribute def OperatingPresentation {
        attribute profileMode : Boolean;
        attribute link : LinkState;
        attribute serverIdentity : String;
        attribute profileIdentity : String;
        attribute dialFrequencyAvailable : Boolean = false;
        attribute modeAvailable : Boolean = false;
        attribute audio : CapabilityState = CapabilityState::unavailable;
        attribute cat : CapabilityState = CapabilityState::unavailable;
        attribute decoder : CapabilityState = CapabilityState::unsupported;
        attribute transmit : CapabilityState = CapabilityState::unsupported;
        attribute messageRowCount : Integer = 0;
        attribute liveResultInterfaceAvailable : Boolean = false;
        attribute selectedContactRowCount : Integer = 0;
        attribute transmitEnabled : Boolean = false;
        attribute haltEnabled : Boolean = false;
        attribute autoSequenceEnabled : Boolean = false;
        attribute logEnabled : Boolean = false;
        assert constraint readOnlyUnsupportedCapabilities {
            (liveResultInterfaceAvailable or messageRowCount == 0) and
            messageRowCount >= 0 and messageRowCount <= 2048 and
            (transmit == CapabilityState::available or
             (not transmitEnabled and not haltEnabled and not autoSequenceEnabled))
        }
        doc /* Link transitions follow existing station.status/socket authority.
             A connected link does not imply audio/CAT/decoder/TX availability.
             Unknown frequency/mode are visible unavailable text, never defaults.
             Profile identity uses literal text, never HTML interpretation.
             With liveResultInterfaceAvailable, receive runs from the operating band/mode
             selection (contract 4.7.5); the explicit receive start/stop (12.8 routes,
             saved endpoint/current revision) is an Expert action (OperatingScreen, #37):
             the legacy Start/Stop receive and Next receive mode controls are not shown.
             Device enumeration requires an operator action; viewing settings never
             opens audio. Separate operating mode/band
             behavior is WstxOperatingReceive/contract 4.7.5/12.8.1. Actual12.7 records alone populate
             Band Activity using latest UTC period and relative DT when correlated, nullable SNR and audio frequency;
             no fabricated UTC/DT or message text; a hashed call shows as the station's
             publication gives it (<CALL> or <...>, WstxOfflineDecode::HashResolution). Full source/job/
             generation/sequence binds each row; new identity clears rows (an unknown-loss
             source epoch of the same receive keeps them, CL-061-01), stale
             pages cannot append. At most2048 rows, explicit cursor-expiry history
             warning and partial stop/failure output; unsupported payloads display
             their status. One pending page, Thin limit1/4s and status priority
             follow12.8. RX selection/TX/log remain unsupported. TC009004 exercises
             actual verified native input through converter/manager/modem/HTTP to
             literal browser rows and stale/epoch/stop/cursor/cadence boundaries;
             TC007002 keeps the unsupported/no-input empty-view baseline.
             Without an available transmit capability Enable Tx, Halt and Auto Seq stay
             disabled with the reason, while row selection, contact preparation, the
             Rx Frequency pane and logging remain usable (receive-only station,
             WstxContact). With transmit available the contact controls follow
             ContactWorkspace and WstxContact (CL-010-01..04, -06, -10..-14). */
    }

    enum def ActivitySortField { enum 'value'; enum frequency; enum signalStrength; enum dt; enum 'message'; }
enum def ActivitySortDirection { enum ascending; enum descending; }
attribute def ActivityOrdering {
    attribute field : ActivitySortField = ActivitySortField::'value';
    attribute direction : ActivitySortDirection = ActivitySortDirection::ascending;
    attribute unavailableLast : Boolean = true;
    attribute sequenceTieAscending : Boolean = true;
    attribute appliesOnlyLatestPeriod : Boolean = true;
    attribute sendsServerMutation : Boolean = false;
    attribute newPeriodResetsChoice : Boolean = false;
    attribute newModeResetsChoice : Boolean = false;
    attribute sameProfileReconnectResetsChoice : Boolean = false;
    attribute differentProfileResetsChoice : Boolean = true;
    assert constraint sortingPolicy {
        unavailableLast and sequenceTieAscending and appliesOnlyLatestPeriod and
        not sendsServerMutation and not newPeriodResetsChoice and not newModeResetsChoice and
        not sameProfileReconnectResetsChoice and differentProfileResetsChoice
    }
    doc /* contract 4.7.4/TC007006: numeric frequency/SNR/signedDT, literalASCIIcasefold
         message; EMPTY=unavailable, unknownlastbothdirections, equaltiepublicationsequenceASC. Field
         change defaults signalStrengthDESC, othersASC; explicitdirection retained
         within same field. Re-sort the whole latest view after each arriving page. Reset
         only for a different VALIDATED profile UUID. No newstore/backend/modem
         filtering, station selection, arming or automation. Keyboard/360px/2x.
         #55 (operator 2026-11-03, CL-055-04): the default field is value, chosen again
         by the DXCC column header (one direction only): within each period first by
         BandActivityValue, then by SNR descending (unavailable last), ties by
         publication sequence ascending; with a strategy active the rows with a rank (value 2)
         keep the station's verdict order among themselves (WstxSettings::ValueView). The
         visible "Value" control of the strategy element returns to this field after a
         column click. A different validated
         profile resets to value. */
}
    verification def LatestPeriodAndTimingVerification {
        objective latestPeriodAndTimingObjective { verify WstxOperatingLayout::'CL-010-09'; verify WstxOperatingLayout::'CL-007-02'; }
        doc /* TC007006 cost2 Windows actual Rust manager/API and Chromium scripted
             clocks/results; cost4 controlled HB9BLA receive plus local browser.
             Multiple periods/stations/>16rows/split+Thin pages/empty, complete vs overrun,
             gap/cancel/failure/late+obsolete context/midpage/reconnect/expiry/counters.
             Hand anchor12:00:00Z atframe0:FT8 3600/6000/8400=>-0.2/+0.0/+0.2;
             FT4 3024/5424/7824 same,95424=>+0.0 at12:00:07.5.
             Nonzeroanchor/dayrollover/fractionalUTC/ties/signedzero and unknown quality.
             Actual1440/360/2x text retains all6literalfields without horizontal overflow.
             Native realdecoder/RF proof remains independent, not a fabricated UI fixture.
             Sorting: frequency200/1000/3499.9 numericASC by default; SNR-20/+10/-5
             DESCstrongestfirst; signedDT-0.2/+0.2/unknown ASCearlytolate; literal
             ASCIIcasefoldmessageASC. Bothdirections keepunknown/emptylast, equalkeys
             sequenceASC. Pagesre-sortwholelatestview; no priorperiodrow restored.
             Choicepersistsnewperiod/mode/sameprofilereconnect; differentvalidatedUUID
             resetsfrequencyASC. No servermutation/cadence/authority changes; 360px/2x. */
    }
    attribute def ReceivePresentationFreshness {
        attribute otherwiseValid : Boolean;
        attribute mutationIntervened : Boolean;
        attribute receiveSnapshotIntervened : Boolean;
        attribute mayApplySnapshot : Boolean;
        attribute mayApplyResultPage : Boolean;
        attribute unknownMutationOutcome : Boolean;
        attribute reconciliationRequestedAfterUnknown : Boolean;
        attribute mayClearUnknownOutcome : Boolean;
        attribute matchingLiveOwner : Boolean;
        attribute mayUpdateLiveProgress : Boolean;
        attribute updatesRecordedProgress : Boolean = false;
        assert constraint snapshotFreshness {
            mayApplySnapshot == (otherwiseValid and not mutationIntervened)
        }
        assert constraint resultFreshness {
            mayApplyResultPage == (otherwiseValid and not mutationIntervened and
                                  not receiveSnapshotIntervened)
        }
        assert constraint unknownOutcomeBarrier {
            mayClearUnknownOutcome == (unknownMutationOutcome and
                mayApplySnapshot and reconciliationRequestedAfterUnknown)
        }
        assert constraint independentProgressOwner {
            mayUpdateLiveProgress == (otherwiseValid and matchingLiveOwner) and
            not updatesRecordedProgress
        }
        doc /* contract 4.7.1 and TC009004 explicit receive start/stop (Expert receive
             control and the Receive stopped chip action, #37) only. Coordinated
             selection unknown outcomes use contract 12.8.1 fencing, not this legacy guard.
             Intervening events are relative to request
             initiation. Otherwise-valid includes existing station/source/job/
             generation and wire validation rules. Rejected stale pages change
             neither lifecycle/error state nor cursors. A pre-mutation read is not
             reconciliation for a later unknown outcome; conflicting controls remain
             disabled and the explanation visible until an authoritative later read.
             Live spectrum progress requires no recorded-input job and cannot cause
             a false link failure when that independent snapshot has no job. Existing
             one-page/cadence bounds hold; no mutation is replayed. */
    }

    verification def operatingLayout002 {
        objective {
            verify WstxOperatingLayout::'CL-010-05';
            verify WstxOperatingLayout::'CL-010-07';
            verify WstxOperatingLayout::'CL-010-08';
        }
        doc /* TC-007-002, CL-010-05/07/08: cost2 local real-server Chromium cases at
             desktop/mobile/200% equivalent viewport. Assert ordering, literal
             identity, empty/unavailable views, disabled actions/no new commands,
             disclosure keyboard access, actual pointer/key split geometry and ARIA,
             no horizontal page overflow, stale link after disconnect. Existing
             At360/1440/1600CSSpx computed Band Activity styles meet the stated
             16CSSpx normal/time/numeric/message,14CSSpx labels, rem-scaled at2x,
             and8CSSpx vertical padding. Verify dominant/full-width card placement and
             all-six-labelled responsive rows at360/720/1200/1440/1600 and1x/2x text.
             Captured physical FT4 text plus independent3499.9Hz/signedSNR/DT/longcall/
             fullmessage/large-source-seconds/UTC/status strings are presentation fixtures,
             never decoder truth. All values stay literal/inside cells, numbers unbroken,
             messages wrap at words except emergency token breaks. Capture screenshots;
             retain actual nativeFT4/FT8 positive proofs. Long text wraps.
             TC010005/006/007 independently guard signal semantics. */
    }
    verification def livePresentation004 {
        objective {
            verify WstxOperatingLayout::'CL-010-05';
            verify WstxOperatingLayout::'CL-010-07';
            verify WstxOperatingLayout::'CL-010-08';
        }
        doc /* TC-009-004: actual verified native input through converter, sole
             receive manager, modem and HTTP produces literal browser rows.
             Verify full tuple/cursor, stop/partial presentation, stale-page
             rejection, unknown-epoch reset, cursor expiry and Thin cadence.
             Delayed running page after cancelled snapshot preserves cancellation,
             partial label and cursor; live frame with null recorded job updates only
             live progress without exception/disconnection; pre-Start idle read
             arriving after unknown Start cannot clear its disabled-control/error
             barrier, whereas an explicitly later refresh can. Negative controlled
             HTTP interleavings are response-order evidence, not modem evidence.
             The unsupported/no-input TC-007-002 baseline remains separate. */
    }
    dependency livePresentationCase from livePresentation004 to WstxRecordingReceive::'TC-009-004';
    // #37: Band Activity (with the strategy element above it) and the QSO pane; the
    // Strategy card, Rx Frequency card and separate regions for settings, preferences,
    // recordings, connection and strategies are retired.
    enum def WorkspaceCard { enum bandActivity; enum qsoPane; }
    enum def WorkspaceRegion { enum operate; enum logbook; enum help; }
    attribute def AgreedOperatingDesign {
        attribute designComponent : String = "465528304540209152";
        attribute designRevision : String = "465570890965458944";
        attribute defaultDesktopSignalHeightPx : Integer = 210;
        attribute minimumSignalHeightPx : Integer = 160;
        attribute hasRadioToolbar : Boolean = true;
        attribute hasBandStrip : Boolean = false;
        attribute hasPersistentHalt : Boolean = true;
        attribute usesActualStationState : Boolean = true;
        attribute substitutesPrototypeData : Boolean = false;
        attribute browserExecutesStrategy : Boolean = false;
        attribute unavailableRfActionsEnabled : Boolean = false;
        attribute unavailableStrategyActionsEnabled : Boolean = false;
        attribute settingsDrawerOwnsProfileForm : Boolean = true;
        attribute settingsDrawerOwnsDisplayControls : Boolean = true;
        doc /* Superseded in layout by OperatingScreen (#37, operator design interview
             2026-11-01); the facts below still hold. Desktop order: top bar, actual signal
             canvas with the Rx/Tx strip, keyboard/pointer separator, Band Activity (with the
             strategy element) / QSO pane.
             Narrow cards stack with no page overflow. Reuse native bins0..3000Hz,
             calibrated palette, sensitivity/speed and profile/import guards unchanged.
             Unknown dial/period/level/contact/strategy state stays unknown.
             No new RF, filter/strategy execution, log or QSO service is implemented. */
    }
    action def OpenRegion {
        in region : WorkspaceRegion;
        doc /* Visible keyboard route for each region: Logbook (full page, top-bar
             Logbook button) and Help ("?", F1/F3/F5). Setup and diagnostics are the
             Settings drawer (SettingsDrawer), not a region; it opens with the top-bar
             Settings button or F2 and keeps the waterfall running.
             Persistent Halt stays reachable.
             A secondary region closes with its labelled close control (keyboard
             reachable) or a pointer action outside it, returning to operation and
             restoring opener focus. Escape never closes a region: it is Abort QSO
             (WstxQsoTransmit::AbortQso, #39 2026-11-04; earlier Halt Tx plus contact
             cancellation, CL-010-03, #10 decision 5),
             replacing the earlier Escape-closes-region behaviour; existing TC-007-002
             tests asserting Escape-to-close must be updated with that implementation.
             No radio/QSO/strategy mutation or settings autosave from navigation. */
    }
    verification agreedDesignPresentation {
        subject design : AgreedOperatingDesign;
        objective {
            verify WstxOperatingLayout::'CL-010-05';
            verify WstxOperatingLayout::'CL-010-07';
            verify WstxOperatingLayout::'CL-010-08';
        }
        doc /* TC007002: actual browser/server at360/720/1200/1440/1499/1500/1600;
             desktop two-pane order (#37 OperatingScreen), compact top bar, no overflow,
             typography/breakpoint/native canvas/full-space/splitter assertions,
             pointer/keyboard region routes,F2/close-control/outside-click/focus (Escape
             aborts the QSO, CL-010-03), real profile/recording
             behavior and request recorder refusing invented RF/QSO/strategy work.
             Same1200x800 target/actual screenshots show design correspondence.
             Cost2 Windows isolated real server/Chromium; no radio. */
    }
    dependency agreedDesignCase from agreedDesignPresentation
        to WstxOperatingLayout::'TC-007-002';

    // ---------------------------------------------------------------- #37 operating screen
    // Operator design interview 2026-11-01 (issue #37 comments). Laptop first (minimum
    // 1366x768, mouse and keyboard); tablet adaptation is a later CR; a phone must not break.
    enum def TopBarItem {
        enum band; enum mode; enum dialFrequency; enum utcPeriod;
        enum logbook; enum settings; enum halt;
        // #96 CL-096-01: the full-screen toggle (FullScreenToggle), immediately left of "?".
        enum fullScreen;
    }
    // #37 (operator 2026-11-03): the entries of the ErrorField, which replaced the top-bar
    // exception chips; receiveRestarted (an informational notice) is no entry any more.
    enum def ErrorFieldEntry {
        enum linkStale; enum catLost; enum catSetupUnconfirmed; enum audioUnavailable;
        enum audioLevelLow; enum audioLevelHigh; enum clockOff; enum receiveStopped;
        enum receiveOutcomeUnknown; enum bandModeFailed; enum transmitRefused;
        // #92 CL-043-03: the three clock situations; the station clock is never unknown
        // (no clockUnknown) and the NTP/air disagreement is dropped (no clockDisagree).
        enum pcClockOff; enum ntpUnreachable; enum stationsOff; enum audioClockUncorrelated;
        enum audioClockDrift;
        enum stationUpdated; enum stationDataRejected;
        // #44 CL-044-14: persistent Tx trouble from the meter read of each transmission.
        enum txAlcHigh; enum txPowerLow; enum txSwrHigh; enum txSwrFault;
        // FR-023: the native session is not ready; "No audio input" never applies to it.
        enum nativeRadio;
    }
    enum def SettingsSection { enum general; enum radio; enum loggingReporting; enum expert; }
    enum def ChangeKind { enum operative; enum restart; }
    enum def Theme { enum day; enum dark; enum night; }
    enum def ThemeSwitch { enum manual; enum byTime; enum bySun; }
    attribute def OperatingScreen {
        attribute minimumWidthPx : Integer = 1366;
        attribute minimumHeightPx : Integer = 768;
        attribute pageScrolls : Boolean = false;
        attribute listsScrollInside : Boolean = true;
        attribute hasMonitorControl : Boolean = false;
        attribute hasEnableTxControl : Boolean = false;
        attribute hasLegacyStartStop : Boolean = false;
        attribute hasNextReceiveMode : Boolean = false;
        attribute healthyStatusShown : Boolean = false;
        attribute hasStrategyElement : Boolean = true;
        attribute strategyEngineInScope : Boolean = true;
        attribute hasRxTxStrip : Boolean = true;
        attribute hasQsoPane : Boolean = true;
        attribute haltAlwaysVisible : Boolean = true;
        attribute fixedWidthListsAndFrequencies : Boolean = true;
        assert constraint operatingOnly {
            not pageScrolls and listsScrollInside and not hasMonitorControl and
            not hasEnableTxControl and not hasLegacyStartStop and not hasNextReceiveMode and
            not healthyStatusShown and hasStrategyElement and strategyEngineInScope and
            hasRxTxStrip and hasQsoPane and haltAlwaysVisible and fixedWidthListsAndFrequencies
        }
        doc /* CL-010-16. One fixed full screen at 1366x768 and larger: no page scroll, only
             lists scroll inside. Top to bottom:
             Top bar (TopBarItem, only these): band select and FT8/FT4 select, both marked
             restart (ChangeKind restart: a change restarts receive through the operating
             selection, contract 4.7.5, and asks first while a QSO or transmission is
             active); dial frequency (display, CAT readback or nominal); UTC (#50: the
             period progress is only the QSO pane's NEXT bar); Logbook (full page); Settings (drawer);
             full screen (#96, FullScreenToggle, only where the browser offers it); "?" (shortcut overview); HALT.
             HALT stays reachable by pointer too: a confirmation popup (the only popup kind)
             carries its own HALT with the same action and enabled state as the top-bar one,
             because a modal popup makes the rest of the page inert. One HALT is visible at
             a time (#37, operator 2026-11-03): in the operating view it is the QSO pane's
             HALT and the top-bar HALT is hidden while the QSO pane HALT is fully on screen;
             whenever it is not (a page such as Logbook or "?" or the Settings drawer covers
             the workspace, or the stacked QSO pane at most 75em wide or on a phone is scrolled
             out of view), the top-bar HALT is shown, so a pointer HALT is always on screen; both are the same action and enabled
             state, and Alt+H halts everywhere (Esc is Abort QSO). The exception chips
             that stood in the top bar are the ErrorField below the QSO pane since #37
             (operator 2026-11-03). A link that is connected shows no entry; the accessible
             status stays. There is no
             refresh control: the status refreshes itself (an explicit Refresh status is in
             Settings > Expert).
             Waterfall full width with the Rx/Tx strip (RxTxStrip) directly below it; its corner
             holds Sensitivity, Range (#54) and Waterfall speed (operative, immediate; the speed is a
             per-browser preference).
             Workspace: Band Activity (BandActivityView) on the left with the strategy
             element above it; on the right one vertical column (LowerPanel, #37): the QSO
             pane (QsoPane), the ControlPanel below it and the ErrorField below that, the
             three the same width; at most 75em wide that column goes below Band Activity,
             still the same vertical stack, at most 48em everything stacks (a phone
             scrolls the workspace, never horizontally).
             Strategy element: `Strategy [name] [edit] [Value] [Contest] [Show all]` (#39, WstxStrategy;
             Contest opens WstxContest::ContestPrompt, Show all only with a contest, ContestView): the name
             selects the active strategy, which starts it, None stops it
             (StrategySelector, StrategyRun); edit opens the StrategyEditor popup; Value returns
             Band Activity to the value order (ValueView); beside them the run state. HALT
             is always on screen.
             There is no Monitor and no Enable Tx control on the screen: receive follows
             the band/mode selection; transmission follows SetEnableTx (#37). The legacy
             receive start/stop is an Expert action. Status texts of a healthy station
             (CAT/audio/clock/link) are not shown; their detail is in Settings > Expert.
             Lists, frequencies and messages use a fixed-width font; colours keep the
             WSJT-X meanings (CQ, my call, own transmission, worked before). */
    }
    attribute def ThemeChoice {
        attribute theme : Theme = Theme::dark;
        attribute switchMode : ThemeSwitch = ThemeSwitch::manual;
        doc /* Browser-local view preference (per browser, never a station setting). Day,
             Dark and Night (dim warm/red for dark adaptation). byTime switches Day/Night at
             two local times; bySun at sunrise and sunset computed for the profile locator.
             The continent (General) is a station setting since #39
             (WstxStrategy::StrategyConfiguration continent); its default derives from the
             locator. */
    }
    attribute def UnauthorizedView {
        attribute showsOnlyTokenForm : Boolean = true;
        attribute showsLinkStatus : Boolean = true;
        doc /* While the station token form is shown (no retained authorization), the page
             shows only that form and the link status line: no station data, settings,
             signal or controls. HALT is not shown there because an unauthorized browser
             cannot halt (the station refuses it). A retained authorization that is
             reconnecting keeps the full screen. */
    }
    attribute def FullScreenToggle {
        attribute targetIsWholePage : Boolean = true;
        attribute shownOnlyWhereSupported : Boolean = true;
        attribute escapeLockedWherePossible : Boolean = true;
        attribute escapeAbortsInFullScreen : Boolean = false;
        attribute rememberedAcrossLoads : Boolean = false;
        attribute sendsStationRequest : Boolean = false;
        attribute hasShortcutKey : Boolean = false;
        assert constraint fullScreenRules {
            targetIsWholePage and shownOnlyWhereSupported and escapeLockedWherePossible and
            not escapeAbortsInFullScreen and
            not rememberedAcrossLoads and not sendsStationRequest and not hasShortcutKey
        }
        doc /* CL-096-01 (#96, operator 2026-11-09: "a botton top right where we can enable and
             disable the entire browser headers and only show our app"; place: "halt is already
             available in qso area. switch between normal browser mode and app mode should be
             left of ?"). A top-bar button (TopBarItem fullScreen) immediately left of "?": the
             order is Logbook, Settings, full screen, "?", HALT (OperatingScreen).
             It switches the browser to full screen with the standard Fullscreen API
             (WHATWG Fullscreen Standard: Element.requestFullscreen, Document.exitFullscreen,
             Document.fullscreenElement, Document.fullscreenEnabled, the fullscreenchange
             event) on the whole page (the document element), so the Settings drawer, Logbook,
             "?" overview, popups, menus and tips stay inside it; browser tabs, address bar
             and toolbars are gone. A press while the page is not full screen requests it, a
             press while it is leaves it. No prefixed (webkit) API is used.
             Look: icon only, the same size and style as "?": an inline SVG of four corners
             pointing outwards while not full screen and inwards while full screen (no font
             glyph); aria-label "Full screen" or "Leave full screen", aria-pressed false or
             true, title "Full screen: hide the browser frame" or "Leave full screen", and the
             attribute data-icon "expand" (outward corners) or "collapse" (inward corners). The
             state shown follows Document.fullscreenElement at every fullscreenchange, so it
             is right however full screen was left (the button, Esc held, the browser's own
             control, a page reload). A refused request (the promise rejects: no user
             activation, a permissions policy) leaves the page and the button as they were,
             with no error entry (ErrorField lists station problems only) and no uncaught
             error.
             Where Document.fullscreenEnabled is not true (Safari on iPhone, which offers full
             screen only for video; an embedding frame without allowfullscreen) the button is
             not shown and the top bar has no gap for it (operator 2026-11-09: no button on
             iPhone, nothing more). Android Chrome and desktop Chromium, Firefox and Safari
             show it. Installing the page as a home-screen app (a web app manifest,
             standalone display) is not part of this clause.
             Esc (KeyboardShortcuts; operator 2026-11-09: "lock esc. we do not need esc for
             abort, we have halt button or abort qso"): while the page is full screen Esc
             never aborts the QSO. Where the Keyboard Lock API exists (navigator.keyboard.lock,
             desktop Chromium: Chrome, Edge; a secure context, the station page is HTTPS),
             entering full screen locks the Escape key (navigator.keyboard.lock(["Escape"])):
             a short Esc closes an open dialog or menu as before and otherwise does nothing,
             the page staying full screen, and the browser's "press and hold Esc" leaves full
             screen; leaving releases the lock (navigator.keyboard.unlock). A browser without
             Keyboard Lock leaves full screen on Esc, and that press does not abort either.
             A lock that fails (its promise rejects) leaves full screen working with the
             browser's Esc. HALT, Abort QSO (the QSO pane buttons) and Alt+H act as always.
             Outside full screen a first Esc press stays Abort QSO; a repeated Escape keydown
             (event.repeat, the key held) never aborts, so holding Esc to leave full screen
             cannot abort through the auto-repeat that reaches the page after the exit
             (KeyboardShortcuts).
             Keyboard: an ordinary focusable button (Tab, Enter, Space); no shortcut key (F11 is
             Rx -1 Hz, KeyboardShortcuts, so the browser's own F11 full screen does not reach
             this page). The "?" overview (the Help region): its intro reads "WSJT-X keys where the
             function exists. Letter keys and ? are inactive while a text field has focus;
             Alt+H always halts, Esc aborts the QSO (not in full screen)."; its Esc / Abort QSO
             entry reads "Abort the QSO: the transmission stops now and the contact is
             cancelled (nothing logged); the station stays ready. Not in full screen."; and a
             new entry directly after it, "Full screen button": "Hide the browser frame and
             show only the app; press again to leave. Esc held: leave full screen."
             Per page load only (operator 2026-11-09): the browser requires a user action for
             each request, so a new or reloaded page (also the automatic reload of
             WstxOperatingLayout::PageUpdate) starts in the normal window, and the choice is
             not stored.
             View only: no station request, setting or browser storage; it works over every
             region since it is in the top bar. The UnauthorizedView shows no button (only the
             token form and link status); a full screen entered before stays until left.
             Entering or leaving changes the viewport height; the existing resize rule keeps
             the signal height (SplitGeometry) and the workspace takes the difference, and the
             CL-010-16 rules (no page scroll at 1366x768 and larger, no horizontal overflow at
             360 CSS px) hold in both states. */
    }
    dependency fullScreenToggleClause from FullScreenToggle to WstxOperatingLayout::'CL-096-01';
    action def KeyboardShortcuts {
        doc /* WSJT-X keys 1:1 where the function exists: Alt+H halts (the emergency
             stop, WstxQsoTransmit::HaltTx); Esc aborts the QSO (WstxQsoTransmit::AbortQso, #39
             2026-11-04: transmission stopped now, contact cancelled, no halt); F1/F3/F5 and "?" open the overview;
             F2 Settings; F4 clears the DX call (contact cancel); Alt+1..Alt+6 choose the
             next message Tx1-Tx6 (Now is a fold-out button only); Alt+M receive start/stop; Alt+T Tune;
             Alt+Q Log QSO; F11/F12 Rx -/+1 Hz; Shift+F11/F12 Tx -/+60 Hz FT8 (90 Hz FT4);
             Ctrl+F11/F12 Rx and Tx -/+1 Hz. Letter and "?" keys are inactive while a text
             field has focus; Esc and Alt+H always act (an open dialog or menu takes Esc first). Alt+N (Enable Tx) has no function.
             In full screen (#96, FullScreenToggle) Esc never aborts the QSO: where the
             browser has Keyboard Lock a short Esc only closes an open dialog or menu and
             holding Esc leaves full screen; without Keyboard Lock the browser takes Esc to
             leave full screen. Anywhere, in or out of full screen, an Escape keydown with
             event.repeat true (the key held: Chrome leaves full screen while Esc is still
             down and its auto-repeat keydowns then reach the page) never aborts the QSO; only
             a first press does. */
    }
    verification def operatingScreen009 {
        objective { verify WstxOperatingLayout::'CL-010-16'; }
        doc /* TC-007-009 cost2 isolated real server and Chromium. */
    }
    dependency operatingScreenCase from operatingScreen009 to WstxOperatingLayout::'TC-007-009';
    doc /* contract 4.7.5/12.8.1 coordinated operating selection is modeled by
         WstxOperatingReceive. This companion retains the unchanged legacy strict
         receive/radio/result shapes and owner/cancellation/source contracts.
         New selection uses the same authority, explicit actual release before
         setters/new capture and a fresh context, not a second pipeline or actor. */
    action def PresentStation {
        attribute levels : DisplayLevels;
        doc /* **Crisp canvas geometry.** Render every frequency/time cell using integer device-pixel
             edges with a DPR-sized backing bitmap, image smoothing disabled and pixelated CSS image
             rendering; no blur/filter or interpolation of measured values. The whole fixed[0,3000)Hz span always fits the plot width; frequency mapping is f/3000*W,
             0Hz at left and3000Hz at right. Resize/DPR/zoom changes geometry only, not frequency
             span, FFT dimensions or native data. No horizontal frequency scrolling or minimum1024
             pixel canvas width. Let B be1024 Detailed or128 Thin and W the integer backing width.
             When W>=B, bin k spans[floor(k*W/B),floor((k+1)*W/B)) device pixels. When W<B,
             assign every native bin k to column floor(k*W/B); that column displays the maximum
             original q of its assigned bins, exactly once each, with no interpolation, frequency
             resampling of the retained array or skipped zero-width cells. This display-only maximum
             projection preserves narrow strong signals; it cannot show1024 separate bins in fewer
             than1024 physical columns. The complete original native array remains unchanged.
             Readout names the projected column's native-bin range and its maximum, and separately
             identifies the nearest native bin to the pointer frequency (clamped, ties upward) or the
             exact keyboard-selected bin. Native keyboard stepping never edits/aggregates the data.
             Axis labels/controls stay reachable with no horizontal page or frequency plot overflow.
             A pointer/focusable readout exposes selected
             native bin index, center Hz, original q-120 dBFS and row source interval; keyboard Left/Right moves one
             bin and Up/Down one retained row, clamped to available data. Gaps report no measurement.

             **Waterfall space and Speed.** The canvas fills its entire allotted box. New
             observed rows enter at the top and advance older rows downward at a fixed source-time
             scale; accumulated history is never stretched to fill the canvas. The Speed slider is
             v=0.5..8 in0.5 steps, default2, with numeric output 10*v CSS pixels per source second and
             Slow/Fast ends. Set p=10*v CSSpx/s. Detailed advances 2*v CSSpx per full0.2s row;
             Thin advances10*v CSSpx per full1s row. This changes only local presentation, never
             source replay, decoder, network cadence, sample clock or retained values.
             Round finite speed input to the nearest half-step with floor(2*value+0.5)/2,
             then clamp to[0.5,8]; nonfinite/unparseable input leaves speed unchanged.

             Let C be the actual CSS waterfall height, H=round(C*DPR) its backing height (minimum1),
             and T the newest accepted row's end_frame/12000. A row with source interval[a,b)
             occupies downward integer device-pixel edges
             [floor((T-b)*p*H/C),floor((T-a)*p*H/C)), clipped to[0,H).
             Thus the latest row starts at0; each new accepted source interval shifts existing
             history by its source-time duration times p, independent of retained row count N.
             Older rows leave through the bottom without sticking, stretching, wrapping or repeating.
             A shortened final row uses its actual interval. Paint absent/unobserved history dark
             RGB(0,0,12), including the part below a short recording; it is not a measurement.
             Explicit missing sequence slots remain grey RGB(96,96,96), never noise or repeated data.
             Zero-height rows, if any after integer rounding, contribute to pixel floor((T-b)*p*H/C).
             When several rows contribute to one pixel, use their per-bin maximum and mark the group
             unknown grey if any contributor is a gap. Native arrays remain unchanged.

             The visible source-time capacity is C/p seconds, independent of N. Display this
             capacity and the actual observed source interval separately. Retain the existing
             bounded history so reducing speed can expose earlier observations; never fabricate
             measurements for time outside retained observations. Time advances only on accepted
             source rows. Completed, cancelled, disconnected or stalled input freezes its last
             history; resizing or local controls may repaint but do not advance time. Replay is
             explicit and resets its job/history normally, without automatic looping.

             Pointer selection uses the exact source intervals contributing to its integer pixel.
             For measured pixels, choose the newest contributing native row as initial selection;
             Up/Down steps one visible native row, clamped. The readout separates the selected
             native bin/row value and interval from the projected native-bin/time ranges and maximum.
             For a gap, report unknown; for an unobserved pixel, report no measurement, without
             clamping it to the oldest measured row. Left/Right still steps native frequency bins.
             Speed or geometry changes recompute visible rows/readouts without mutating native data.

                          Keep spectrum above the fixed0..3000Hz ruler and waterfall. #54: the spectrum line is shown
             only with the per-browser option Show spectrum line (default off); hidden, the waterfall
             takes its height. Shown, its vertical scale is [E,0] dBFS, so no level clips at the top.
             The default signal height is 330 CSS px (splitter), at most 560. Allocate the remaining plot
             budget after headings/rulers/legend approximately1:5 to spectrum:waterfall, using explicit
             zero flex bases and min-height0 so intrinsic canvas bitmap heights cannot feed back into
             layout. Each backing bitmap is round(its actual CSS box * DPR), minimum1, and each
             canvas fills its allotted box exactly after drag, resize and zoom. Plot areas therefore
             use approximately17%/83% of their combined height, subject only to integer rounding.
             Headers, rulers and controls remain reachable at the existing pane minima and360px.
             No horizontal page/frequency scrolling or changed frequency span.

             Frequency ruler retains major500Hz/minor100Hz ticks with positions f/3000*W. Time ruler
             labels T at the top and source time t every5s within the viewport,
             at y=floor((T-t)*p*H/C)/DPR, omitting negative source times and colliding labels less
             than16CSSpx apart. The time scale and native/projected readouts use this same mapping;
             labels do not imply observations in unmeasured areas. Label elapsed source seconds, never synthetic UTC/RF frequency/dBm.
             A run of Tx rows (#61 CL-061-05) takes one band of 4 CSSpx instead of its source time; every other row keeps p, and the mapping and labels of times beyond the band stay exact: T-t counts without the run's source time, plus the band.
             Profile changes still clear browser history/old-profile frames; existing bounded history,
             source identities and one pending repaint remain unchanged.

             **Display levels and palette.** The display is a local presentation of calibrated
             levels, independent of source samples, FFT/averaging, wire quantization, Thin bandwidth
             and future decoding (#54, CL-054-02). The waterfall corner holds labelled keyboard-operable
             Sensitivity (WSJT-X Zero), Range (WSJT-X Gain) and Speed range sliders, each with an
             adjacent numeric output, repainting on every input event; Settings > General > Display
             holds Flatten and Show spectrum line. DisplayLevels gives the values and the fixed
             mapping: there is no Black level input, no Auto black and no noise estimate, and a new
             source, job or display profile changes no level. Sensitivity and Range change
             waterfall colours only; the legend shows both effective ends in dBFS. Inputs are rounded
             with floor(value+0.5) and clamped; nonfinite values leave settings unchanged. Clipping
             affects presentation only; the native values remain available. Repaint all retained
             rows when presentation controls change; samples/wire data never change or restart.

             For an original quantized level q, t=clamp(((q-120)-E)/R,0,1). Map t to this project's
             own RGB anchors, interpolating each channel linearly between adjacent anchors and
             rounding with floor(channel+0.5): t=0:(0,0,12), .15:(0,0,80), .35:(0,80,220),
             .50:(0,220,240), .65:(30,230,80), .80:(255,235,0), .95:(255,40,0),1:(255,0,0).
             Saturated/above-range signal is exactly RGB(255,0,0), never white. Below-floor/no-signal
             is RGB(0,0,12); gaps are RGB(96,96,96) and appear only for a real gap (#54: rows the station did not send within its retained window, a source or job change, an unknown-loss source epoch of the same receive as one row between the kept rows (CL-061-01); one or two live Thin rows paced out between two sent rows are drawn with the next row, not as a gap; live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart). This continuous level-to-color
             mapping does not interpolate spatial bins/rows: each rendered cell has one exact RGB
             color, fully opaque. Spectrum trace is RGB(180,245,220). Ruler/grid/text overlays stay
             outside waterfall measured cell interiors. A narrow labeled color legend uses these exact same anchors, positions and linear RGB
             channel interpolation/rounding, ending in the same saturated red; it displays the
             effective waterfall range. Rainbow hue progression does not assert monotonic luminance. Flatten is the optional per-row passband equalisation of DisplayLevels; no palette editor, gain normalization over time or new framework.

             Conventional presentation references, consulted2026-10-25: [WSJT-X User Guide9.2/14.7](https://wsjt.sourceforge.io/wsjtx-main_en.html#_wide_graph) describes spectral averaging,
             bin visibility and display level controls; [FlexRadio SmartSDR User Guide, Waterfall](https://edge.flexradio.com/www/offload/20260423063240/SmartSDR-Software-User-Guide.pdf)
             describes noise-floor black level and display range. These inform the operator's visual
             expectation, not numerical conformance or copied assets/code. The exact formulas,
             geometry and original palette above are authoritative for this implementation. A real
             busy FT8 recording MUST show multiple recognizable narrow time-varying transmissions
             against a dark noise floor with distinguishable brighter signals, reviewed at desktop
             and360px alongside these reference images; analytical tones alone do not meet visual
             acceptance. Readout remains calibrated dBFS rather than implying receiver RF power.

             **Integrated UI.** One browser window/page per station. Spectrum and waterfall
             occupy the upper pane; profile/status/import/replay/controls and future decoded messages
             occupy the lower pane. No placeholder decoded messages or signal data. Horizontal
             separator is focusable with `role=separator`, horizontal orientation, accessible name,
             current/min/max pane sizes and visible focus. Pointer/mouse/touch drag changes upper
             height; Up/Down change it by 16 px, Home/End select min/max. Minimum upper/lower pane
             heights are 160/200 CSS px excluding a 12 px separator. If available height is smaller,
             scroll the page rather than violate minima. Lower controls also scroll independently
             when needed. Initial split is 50% of available height clamped to minima. Recompute/clamp
             on viewport changes; no server persistence of pane size. Verify 1100x850 and 360x640,
             keyboard-only use, touch input, 200% zoom and literal rendering of source/status text.
             No horizontal page overflow; axis labels and primary controls remain reachable. */
    }
    action present : PresentStation;
    dependency browserOwner from present to WstxArchitecture::physicalStation::frontend::browsers;
    attribute def PageUpdate {
        attribute reloadsAtMostOncePerBuild : Boolean = true;
        attribute keepsBrowserSettings : Boolean = true;
        attribute heldByQsoDialogOrUnsavedSettings : Boolean = true;
        attribute rejectedSnapshotSilent : Boolean = false;
        doc /* CL-051-02/03 (#51). On every station.status (each connect and reconnect,
             and Refresh) the page compares StatusData::build with its own ClientBuild.
             Different: the page reloads itself, once per station build (the build it
             reloaded for is kept in this tab's session storage; a later mismatch for
             that same build shows the chip instead of reloading again). Browser storage
             (theme, display and speed preferences) is kept. The operating screen holds
             the reload while a contact or transmission is in progress (contact not idle,
             completed or cancelled; Tx armed; Tune on), a confirmation or editor popup is
             open or the Settings form has unsaved edits; it then shows the
             ErrorFieldEntry stationUpdated (WstxLowerPanel::ErrorField) "Station updated · reload", whose click
             reloads. A held page keeps working with its old client.
             A station snapshot the page rejects by its exact validation (the receive
             snapshot, a result page, the operating selection snapshot, the contact
             snapshot, a waterfall frame of an unknown shape) shows the ErrorFieldEntry stationDataRejected "Station data not
             understood (<which>) · reload" with the same reload action; a later valid
             snapshot of that kind clears it. Neither chip opens the Settings drawer.
             Chosen defaults (#51 implementation, the issue left them open): the build is
             compared on every station.status, that is on each connect and reconnect and
             on Refresh; a held update stays a chip until the operator clicks it, with no
             later automatic reload; unsaved Settings edits hold the reload like a popup.
             CAT status (WstxRadioIO) keeps its own CAT chip and is not part of this chip;
             a page of another build reloads before any of its snapshots matter. */
    }
    attribute def BrowserSnapshotPolicy {
        attribute requiredBeforeConnected : Boolean = true;
        attribute refreshUsesExistingSocket : Boolean = true;
        attribute constantStatusPolling : Boolean = false;
        attribute changingStatusEventDriven : Boolean = true;
        doc /* Initial/reconnected socket requests a complete status snapshot before
             Connected. Profile-mode readiness additionally needs WstxProfiles' valid
             GET. Refresh sends station.get on the existing socket. Last updated
             changes only when a matching snapshot is rendered. No changing station
             properties or subscriptions are implied by the legacy status slice.
             Native receive events have their explicitly declared extension schema.
             UI renders literal text and distinguishes confirmed/pending/stale state. */
    }
    state def BrowserLinkLifecycle {
        in connectionOpened : Boolean;
        in snapshotAccepted : Boolean;
        in connectionClosed : Boolean;
        in silentTooLong : Boolean;
        state connecting; state connected; state stale;
        entry; then connecting;
        transition ready first connecting if connectionOpened and snapshotAccepted then connected;
        transition closed first connected if connectionClosed then stale;
        transition silent first connected if silentTooLong then stale;
        transition retry first stale then connecting;
        doc /* >12s with no message checked each1s permits13s detection. Closed socket
             marks state stale immediately. The page's own deferred client download
             (WstxContact log and contact clients after the first snapshots) shares the one
             station-to-browser bottleneck and can hold queued messages behind it (#8): while
             one is pending the bound is >30s, checked each1s (31s detection); its
             completion or failure counts as a message, so the 12s bound restarts there.
             No other request extends the bound. Reconnect waits1,2,4s then caps4s;
             accepted fresh snapshot resets backoff. A new connection not open within5s
             is abandoned. Watchdog starts reconnect without waiting for old close
             handshake. Ignore replaced-socket callbacks. After restored connectivity
             and loss detection, fresh displayed status<=10s; undetected loss adds its
             separate detection bound. Reconnect never replays old mutable operations. */
    }
    dependency presentationOwner from BrowserSnapshotPolicy to WstxArchitecture::physicalStation::frontend::browsers;
    dependency reconnectPromise from BrowserLinkLifecycle to WstxOperatingLayout::'CL-003-04';
    dependency browserVerification from BrowserSnapshotPolicy to WstxStationProtocol::'TC-021-006';
    dependency reconnectVerification from BrowserLinkLifecycle to WstxOperatingLayout::'TC-021-007';
    dependency pageUpdatePromise from PageUpdate to WstxOperatingLayout::'CL-051-02';
    dependency rejectedSnapshotPromise from PageUpdate to WstxOperatingLayout::'CL-051-03';
    dependency buildPresentationOwner from PageUpdate to WstxArchitecture::physicalStation::frontend::browsers;
    attribute def AutomationIndicator {
        doc /* Browser station bar, read-only, beside the transmit state: while a run is
             waiting or in a contact it shows "Automation waiting" or "Automation in
             contact", the first 8 characters of the run id and "Halt ends it" (#42 a
             pounce run: "Pounce <call> waiting" or "Pounce <call> in QSO" and "HALT ends
             it", WstxStrategy::Pounce; a strategy run: WstxStrategy::StrategySelector); a
             stopped run with a reason other than stopped "Automation stopped · <reason>";
             "Automation idle" otherwise (#74, operator 2026-11-08), also with no strategy
             selected and no run. The station sends automation.state {profile_id, boot_id,
             policy_revision, run_revision} (an optional write paced with contact.state)
             after each change since boot, also once to a peer that subscribes while
             either revision is nonzero; the browser then reads GET /automation, and only
             then: no read once per socket or on connect (#74). No event or request
             while automation is never used. A new boot (#74, CL-074-01,
             WstxStationProtocol::PushedStationState): when the browser learns a boot_id
             other than that of its held automation state, it drops that state at once and
             holds the never-used state (configuration, run, strategy_refusal and
             free_tx_slots null) without a request; an automation.state of the new boot then
             reads GET /automation; a snapshot reply of another boot is discarded. "No event"
             concerns automation.state: free_tx_slots.state (#82, WstxStrategy::FreeTxSlots)
             carries the station's open slots, not automation state, and is pushed every
             period also while automation is never used; the browser reads nothing after
             it. */
    }
    dependency indicatorBootClause from AutomationIndicator to WstxOperatingLayout::'CL-074-01';
    requirement 'CL-010-16' {
        doc /* Present the laptop operating screen of WstxOperatingLayout::OperatingScreen: a top bar with only band, mode, dial, UTC/period, Logbook, Settings, HALT and Abort QSO (Esc); the full-width waterfall with the Rx/Tx strip; Band Activity with the strategy element and the QSO pane with direct buttons and no Enable Tx control; setup and diagnostics in the four-section Settings drawer; themes; WSJT-X keyboard shortcuts; and only the token form for an unauthorized browser. Details: OperatingScreen, RxTxStrip, BandActivityView, QsoPane, SettingsDrawer, ThemeChoice, UnauthorizedView, KeyboardShortcuts, WstxQsoTransmit::SetEnableTx. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css; client/contact.js; client/logbook.js";
    }
    dependency CL_010_16_to_FR_010 from 'CL-010-16' to 'FR-010';
    dependency CL_010_16_to_FR_019 from 'CL-010-16' to 'FR-019';
    dependency CL_010_16_to_FR_021 from 'CL-010-16' to 'FR-021';
    requirement 'CL-010-06' {
        doc /* Present bounded Band Activity and, since #37, the compact QSO pane (WstxQsoPane::QsoPane: the running QSO's last partner message, its QSO dialogue and, below it, at most eight stations calling my call with time and SNR: during a QSO those within +/-50 Hz of my Rx or Tx offset, otherwise every caller, #37) in place of the Rx Frequency pane; local filtering, sorting, highlighting and clearing change no server decoding, contact state or log. Details: WstxQsoPane::QsoPane, QsoPaneCrowding. */
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
        doc /* (#73) Save outcome: the reply to the page's PUT /profile is the save's outcome. A 200 whose body is a valid ProfileRepresentation (the same checks as a GET /profile body) shows "Saved revision N" (N its revision) and is applied as the authoritative snapshot exactly like a GET: SnapshotApplicable, then a reload of the form, the edited revision and the shown profile (no newer same-boot snapshot is overwritten). A received 400, 409 or 503 shows its existing refusal text and state. No follow-up GET /profile is sent for the outcome, and no check of the socket, the authorization epoch or the displayed snapshot after the reply decides it: a control save (mode, endpoint, PTT) advances the CL-022 safety revision, so the server drops this page's transport and socket while the reply is on its way, and the page re-authorizes and reconnects by the existing rules without a token. "Save outcome unknown. Reload saved settings before retrying." with Save disabled until an explicit reload stays only for a save without a readable reply: network failure, the 10 s timeout, abort, an unreadable or invalid body, or a reply the authorization component discards because its headers arrived after a renewal began (accepted rare case). The server, the safety revision rule and every other caller of the authorization component are unchanged. Details: WstxSettings::PresentAndEditProfile, WstxSettings::BrowserSaveLifecycle. */
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
        doc /* The strategy element above Band Activity offers the strategy selector (None and the names, grouped Strategy and Contest), the editor and a Value sort control. While a strategy is active Band Activity marks what it ranks and lists rows by value from the station's verdicts, only after a new publication event; a column click overrides until Value is chosen again; colours stay per #50 (only interesting stations). The editor is a popup with its own HALT that keeps receive running, holds exactly the strategy settings as the nine decisions of CL-097-01 (a new strategy only as a duplicate), previews the unsaved draft against the latest period with the reason per decode, and applies on Save at once without selecting; selecting or saving never restarts receive. Details: WstxSettings::ValueView, StrategySelector, StrategyEditor; WstxOperatingLayout::OperatingScreen. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_039_04_to_FR_010 from 'CL-039-04' to 'FR-010';
    dependency CL_039_04_to_FR_019 from 'CL-039-04' to 'FR-019';
    dependency CL_039_04_verified_by_TC_039_046 from 'CL-039-04' to 'TC-039-046';
    dependency CL_039_04_verified_by_TC_039_006 from 'CL-039-04' to 'TC-039-006';
    dependency CL_039_04_verified_by_TC_039_007 from 'CL-039-04' to 'TC-039-007';
    requirement 'CL-055-04' {
        doc /* Band Activity colours, hover text and order (operator 2026-11-03). Operator decision deviating from WSJT-X, which colours only CQ/QRZ and calling-me lines: the sender of every decoded message (CQ, replies to others, reports, R-reports, RR73, 73; the sender call of WstxCountryFile::DecodedEntity) is coloured by the same new DXCC, continent, zone, grid and call flags (the whole row for a CQ or QRZ, only the sender's call otherwise, #50 CL-050-08); a message to my call keeps the calling-me colour on top; a row without a flag has no colour (there is no CQ slot, #50, and worked before never colours). Every row with a reason carries hover text (title and aria-description, on the row and its colour mark) naming each reason in value order (#50 CL-050-08 replaces this Band Activity hover by its one-line reason tip; the QSO pane callers keep it): calling me, the strategy verdict, each new flag with its entity, zone, grid or band, then the worked-before status, for example "New DXCC: Romania", "New DXCC on 40m", "New CQ zone 20", "New grid KN34", "New call", "Worked before on 40m FT8". Within each period the rows are sorted by value (1 calling me, 2 strategy hits by their rank, 3 new DXCC, 4 new DXCC on this band, 5 new CQ or ITU zone, 6 new grid, 7 new call, 8 no flag), then by SNR strongest first, ties in decode order; the column headers still choose another order and the DXCC header returns to it. Details: WstxBandActivity::BandActivityColours, BandActivityValue, BandActivityHover, ActivityOrdering. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/logbook.js";
    }
    dependency CL_055_04_to_FR_019 from 'CL-055-04' to 'FR-019';
    requirement 'CL-055-05' {
        doc /* Band Activity rows are tighter so more stations fit (operator 2026-11-03): less vertical padding and line height on decode rows and period dividers at the same font size, at most 24 px per row with a mouse; touch (coarse pointer) and the stacked narrow layout keep tappable rows. Details: WstxBandActivity::BandActivityView. */
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
        doc /* A page whose build differs from the build in a station.status reloads itself once for that station build, keeping its browser storage (WstxOperatingLayout::PageUpdate). The operating screen holds the reload while a contact or transmission is in progress, a popup is open or the Settings form has unsaved edits, and shows the "Station updated · reload" chip instead; the chip's click reloads. A second mismatch for a build the tab already reloaded for shows the chip and never loops. */
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
        doc /* Band Activity rows use the WSJT-X 3.3 default highlight colours and priority with its default on/off except as stated here (WstxBandActivity::BandActivityColours), with no text marks other than the a-priori marker aN after an a-priori word's message (#56 slice 5): My call from the message, the New call, New call on band, grid, DXCC, continent and zone slots from the record flags the station supplies (#55; a never-worked call carries both New call flags), for every decoded sender (operator decision, CL-055-04, not only CQ/QRZ lines as in WSJT-X; what a slot colours, whole row or the sender's call only, and the QSO partner's marker: CL-050-08); New call and New call on band are on by default (WSJT-X: off). Only stations of interest are coloured (operator 2026-11-03, deliberately unlike WSJT-X): there is no CQ slot, so a CQ from a station worked before on this band and mode, and every other row that carries no enabled slot, has no colour, while My call still applies. The slots are chosen per browser in Settings > General > Display. The #39 strategy highlight stays an accent and never replaces these colours. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/logbook.js; client/recording.css";
    }
    dependency CL_050_02_to_FR_019 from 'CL-050-02' to 'FR-019';
    requirement 'CL-054-02' {
        doc /* The waterfall colour follows a fixed dBFS mapping (WstxSignalArea::DisplayLevels): reference -85 dBFS, Sensitivity as WSJT-X Zero, a Range slider as WSJT-X Gain (default 50 dB), no automatic level and no reset on a new job, source or profile; optional Flatten across frequency. The spectrum line is a Settings option (default off) with a [E,0] dBFS scale that never clips; the default signal height is 330 px and the default speed 10 px/s, about two FT8 periods. All are per-browser settings that apply at once. Cells keep one native bin per column range, nearest-neighbour, without smoothing. */
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
        doc /* The QSO pane's period bar shows the elapsed part of the current period (15 s FT8, 7.5 s FT4) on the station's clock, the UTC the transmitter keys on including the #43 correction, never the browser's wall clock: the browser takes the largest offset of the station's utc_ms over its own monotonic time among the observations of the last 20 s and redraws at least every 100 ms without animation. An offset more than 500 ms below the estimate is a backward step of the station clock and restarts the estimate at once. The bar is red in a period of my Tx parity while Enable Tx is on and whenever the station reports transmitting, green in every other period. Details: WstxQsoWire::OperatorDisplays StationPeriodClock, WstxQsoPane::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_050_03_to_FR_008 from 'CL-050-03' to 'FR-008';
    dependency CL_050_03_to_FR_019 from 'CL-050-03' to 'FR-019';
    requirement 'CL-050-05' {
        doc /* (#37) While an own CQ runs the QSO pane header reads "Calling CQ" with the Tx period; the message line reads "▶ TX now: <message>" with the seconds left while the station reports transmitting ("▶ TX now: Tune" with the Tune seconds left during Tune) and "▸ next: <message> · Tx in <n> s" otherwise; the Calling me section below the QSO dialogue lists only stations calling my call, one line per station with call, SNR, grid and country: every caller other than the partner on any frequency as soon as decoded, during a QSO ⚠ marking one within +/-50 Hz of my Rx or Tx offset and a double-click switching the contact with Enable Tx kept; an empty list shows the placeholder "Nobody is calling" (#37 2026-11-04, CL-037-04). Details: WstxQsoPane::QsoPane. */
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
        doc /* The waterfall pointer, the Rx and Tx lines and the frequency axis share one mapping of the fixed 0..3000 Hz span onto the waterfall canvas's own box: a click, double-click or marker drag selects the frequency under the pointer, and the confirmed line and the axis tick of that frequency are drawn within 1 px of the pointer position, at every page width, display option (speed, Flatten, spectrum line) and devicePixelRatio. The Rx (green) and Tx (red) lines mark the lowest tone and each carries a WSJT-X bracket (goalpost) at the top of the waterfall over the occupied width to its right, 50 Hz in FT8 and 83.3 Hz in FT4, following the station's operating mode. Details: WstxSignalArea::RxTxStrip, WstxContact::PointerEffect. */
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
        doc /* Band Activity marks each decoded row by what makes it interesting, highest first (WstxBandActivity::BandActivityScheme, BandActivityRowMark): (1) the current QSO partner, from the contact preparation until the contact is logged or cancelled, taken from the contact snapshot the page already holds (no further request): its rows are moved to the top of Band Activity with a red separator stripe below them and carry a red left bar, a "◆ QSO" badge after the message and a bold message, without a slot background; (2) a row to my call from another station (also <MYCALL> and a nonstandard i3=4 'to', #24): the whole row in the My call colour, also when the sender was worked before on this band and mode; (3) a CQ or QRZ from a station with an enabled new_* slot: the whole row in that slot's colour; (4) any other row from a station with an enabled new_* slot (in QSO with another station): only the sender's call is coloured, the rest of the row is plain; (5) everything else has no colour. The Settings slot choice applies to every mark. A row's reason tip is one compact line naming only the reasons of its colour that the row does not show, joined by " · ": per kind (continent, DXCC, zone, grid, call) the strongest enabled one, so an overall flag never also names its on-band form, the on-band call reason with the worked-before status in parentheses, then the strategy verdict, e.g. "New DXCC · New call", "New on 40m (worked on another band or mode)"; no country, continent, distance or "Calls you" (the row shows them); a row without such a reason has no tip. It uses only the #55 record data and the record's worked_status (WstxBandActivity::BandActivityHover). */
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
        doc /* (#60) The QSO pane shows the QSO dialogue as a table with the header row "UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR", and, since #37 CL-037-04 (2026-11-04), the stations calling me in their own Calling me section, no longer rows of this table. UTC is the period start HH:MM:SS with no ◂/▸ mark after it. Direction is the two calls in the Band Activity order, recipient first and sender second, with "◂" between them pointing to the recipient ("HB9BLA ◂ CT1BFP" received from CT1BFP, "CT1BFP ◂ HB9BLA" sent by me; a hashed call as decoded); a CQ is "CQ <call>" or "CQ DX <call>" without an arrow and its grid is the Exchange. Exchange is the message after the two calls; a message that is neither (free text) is all Exchange. Rep is "×N" when the identical message repeated N > 1 times, else empty (operator 2026-11-03: its own column). On every dialogue row, received and sent alike (operator 2026-11-03), Rx SNR is our measured SNR, signed, of the latest received dialogue entry at or before that row, and Tx SNR is the latest report the partner sent us at or before that row ("R-02" gives "−2", a plain report "-05" gives "−5"); each is empty only while no such value exists yet. The table is the QSO section of the fixed-height pane (#37 CL-037-04): its header row and 12 rows without scrolling (6 at most 48em wide), more scrolling inside at its newest row; it does not grow the page (TC-007-009) and the table fits 360 CSS px, the titles abbreviated and the Direction calls wrapping at their spaces there. Details: WstxQsoPane::QsoPane items 7 and 8. */
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
        doc /* (#37) The right column of the workspace is one vertical stack at every width: the QSO pane, below it the Control panel and below that the error field, each with the left and right edges of the QSO pane card. The Control panel is always visible (no fold-out) and holds DX Call and DX Grid with Generate, Report, Auto Seq, Call 1st, Hold Tx and the Tx period Even / 1st or Odd / 2nd, laid out in rows across its width; each control sends the same single contact request as before and shows only the server-confirmed value. Tx1-Tx6 stay in the QSO pane fold-out; Rx/Tx and dial frequency stay under the waterfall and in the top bar; there is no level meter. The stack fits the fixed 1366x768 screen and 360 CSS px without horizontal overflow. Details: WstxLowerPanel::LowerPanel, ControlPanel. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_01_to_FR_007 from 'CL-037-01' to 'FR-007';
    dependency CL_037_01_to_FR_019 from 'CL-037-01' to 'FR-019';
    requirement 'CL-037-02' {
        doc /* (#37) The error field, a small block below the Control panel that replaces the top-bar exception chips, lists only the problems that still apply and need the operator to act (CAT or radio, audio input missing or its level too low or too high, clock unsynchronized or unknown, a transmit refusal the operator must fix, a failed band/mode change, receive stopped, the station connection lost, a station update or rejected data), each with its cause and "since HH:MM" UTC, on one line where it fits. An entry disappears by itself when its condition clears; there is no acknowledge control and no history; transient events (a retried refusal, busy, stale revision, a receive restart) are no entries. With no entry it shows "No problems". A click opens the entry's detail as the chip did. Details: WstxLowerPanel::ErrorField, ErrorFieldEntry. */
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
        doc /* (#65, #82 operator 2026-11-09: "open slots are shown all the time as a part of the waterfall", "we just want to mark open slots, nothing else on screen") Open slot marks: always part of the waterfall, with no setting (#82 removes the Settings > Expert checkbox "Show free Tx slots") and with or without a run, a QSO or Auto: each open range [lo_hz, hi_hz) of the latest held free_tx_slots (CL-065-01) is a bar in the frequency ruler directly above the waterfall over lo to hi on the waterfall's one frequency mapping (CL-050-07), taking no pointer input. The held value is replaced by each free_tx_slots.state in socket order, by a GET /automation reply only with a later at_utc_ms (never by its null or an older value), and dropped at a new boot (#74) and when the page's display is switched to Off; the marks are redrawn on every new value and go when it is null or open is []. No request or poll beyond the snapshot and the event. Look (#76, operator 2026-11-08): each bar 8 CSS px high, shortened by 2 CSS px at each end (from x(lo) + 2 to x(hi) - 2), so touching ranges show a 4 px gap (where a range is narrower than both insets, on a phone, the bar may vanish); no text on the marks (no rank, no rise, no number); one pale green in the base theme, remapped by Day and Night like the page, whose drawn pixel differs in each theme from the drawn Rx line, Tx line and ruler background by at least 40 in the sum of the R, G and B differences. Details: WstxSignalArea::FreeTxSlotMarks. */
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
        doc /* (#37, operator 2026-11-04: "The QSO panel should contain all needed information for the operator. And it should be fixed in size that the things below it do not move all the time up and down. We probably have a section for the QSO and a section for who is calling"; "you can make this section big enough to accommodate also longer QSOs. We have enough space") The QSO pane has a fixed height that depends on the screen only, never on its content, so the Control panel and the error field below it do not move when a QSO starts or ends, dialogue rows or callers are added or a message line appears. It has two sections of fixed height that scroll inside: QSO, below the header (partner call, grid, country, distance, reports) and the message lines (state, NEXT, last partner message), holds the #60 dialogue table with its header row and 12 rows without scrolling on a laptop screen (6 at most 48em wide), more rows scrolling inside with the newest row always visible, and the placeholder "No QSO" while no QSO runs; Calling me lists every station calling my call except the partner, one line per station with call, SNR, grid and country, at least 5 rows high, double-click (or Enter) to work it, with the #10 worked-before marks, and the placeholder "Nobody is calling". At 360 CSS px both sections stack with fixed heights, and Band Activity, with a fixed height, shows compact rows (numbers and distance, then message and country, wrapping only between whole fields, usually two lines) instead of labelled cards, at least six on screen at 360x800. The Calling me hover follows the compact #50 BandActivityHover rule (one line, only the enabled colour reasons, the strongest per kind). No new request or poll: the sections show the contact snapshot and the result rows the page already reads. Details: WstxQsoPane::QsoPane items 3, 7 and 8, BandActivityView. */
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
    requirement 'CL-003-04' {
        doc /* The browser MUST distinguish stale/disconnected state from current station state, detect a silently unresponsive connection, retry at a bounded rate and obtain a full snapshot before showing Connected again. Recovery MUST not wait indefinitely for an old socket to close. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_04_to_FR_019 from 'CL-003-04' to 'FR-019';
    dependency CL_003_04_to_FR_021 from 'CL-003-04' to 'FR-021';
    requirement 'CL-007-02' {
        doc /* The common browser MUST show exact supported payload fields, hash identities (filled in by the station per CL-024-01 or unresolved), UTC period time and relative DT when correlated or explicit unknown timing under4.7.4, lowest-tone audio frequency and calibrated SNR or explicit unavailable SNR, with reliable bounded result delivery. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_02_to_FR_003 from 'CL-007-02' to 'FR-003';
    dependency CL_007_02_to_FR_004 from 'CL-007-02' to 'FR-004';
    dependency CL_007_02_to_FR_019 from 'CL-007-02' to 'FR-019';
    requirement 'CL-010-05' {
        doc /* Present one operating-first profile page with the fixed-band signal display above the message/contact workspace, an accessible adjustable split and secondary in-page settings. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_05_to_FR_010 from 'CL-010-05' to 'FR-010';
    dependency CL_010_05_to_FR_019 from 'CL-010-05' to 'FR-019';
    requirement 'CL-010-07' {
        doc /* Show audio, CAT, decoder and transmit availability independently. Label unavailable values and visibly disable unsupported actions with adjacent reasons; status-link connection alone does not establish a radio capability. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_07_to_FR_001 from 'CL-010-07' to 'FR-001';
    dependency CL_010_07_to_FR_008 from 'CL-010-07' to 'FR-008';
    dependency CL_010_07_to_FR_009 from 'CL-010-07' to 'FR-009';
    dependency CL_010_07_to_FR_019 from 'CL-010-07' to 'FR-019';
    requirement 'CL-010-09' {
        doc /* Band Activity shows only the latest published decode period and signed station timing relative to our clock, selectable presentation sorting and explicit partial/unavailable states. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_09_to_FR_010 from 'CL-010-09' to 'FR-010';
    dependency CL_010_09_to_FR_019 from 'CL-010-09' to 'FR-019';
    requirement 'CL-010-08' {
        doc /* Preserve keyboard and narrow-screen operation, literal field rendering and existing signal/status transport contracts. Secondary in-page regions keep the persistent station bar and disabled Halt Tx accessible. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_08_to_FR_019 from 'CL-010-08' to 'FR-019';
    dependency CL_010_08_to_FR_021 from 'CL-010-08' to 'FR-021';
    dependency CL_010_07_verified_by_TC_007_004 from 'CL-010-07' to 'TC-007-004';
    dependency CL_010_08_verified_by_TC_007_004 from 'CL-010-08' to 'TC-007-004';
    verification 'TC-021-007' {
        doc /* #### TC-021-007 — Disconnect, retry and state resynchronization

             Application payload codecs and negotiated WebSocket compression remain excluded.
             HTTP content coding12.1.1 changes no reconnect, snapshot, event or status deadline.

             **Clauses:** CL-003-04, CL-003-08. **Promise:** FR-021.
             **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, actual candidate server and real browser through a
             controllable disposable local proxy, with WebSocket message and attempt timestamps.

             **Inputs/actions and expected results:**

             1. Connect and observe an unchanged session across a heartbeat interval. Expect an
                initial snapshot request and no periodic station.get polling.
             2. Cut the connection and keep it unavailable. Expect visible stale/disconnected state
                and attempts at the bounded reconnect rate from the
                [liveness contract](../backend/web/StationProtocol.sysml).
             3. Restore connectivity to the actual server. Expect a new station.get exchange and a
                fresh full snapshot before Connected, within the contract's recovery bound. If a
                server restart or version change is exercised, the fresh state MUST replace the old
                display; an unchanged unconfigured state still requires a newly observed exchange.
             4. Drop bytes without closing the established test connection. Expect stale detection
                within the contract's silent-loss bound and scheduler tolerance. Restore byte delivery;
                expect bounded recovery and another snapshot without waiting for the old close handshake.
             5. Hold (delay, not drop) every station-to-browser byte while the page's deferred
                client download is pending; with the page's clock installed before load, drive it
                16s (past the 12s bound and its 1-second tick), then deliver. Expect only the
                connected state, the same socket and no new connection (#8, issue70: driven, no
                real wait). The former real-time 31s check with a download that never completes is
                retired (#80, operator 2026-11-09: a setup case, not normal operation).

             **Oracle:** contract state transitions/time limits and observed request exchange.
             The automation cuts/restores the proxy to the actual server and checks a new snapshot
             exchange; it does not simulate a different application version. **Executable trace:**
             [communication.test.cjs](../../../tests/communication.test.cjs),
             `TC-021-007: dropped connection, bounded retries, fresh snapshot`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-04';
            verify 'CL-003-08';
            verify 'FR-021';
        }
        attribute executable : String = "tests/communication.test.cjs";
    }
    verification 'TC-007-002' {
        doc /* #### TC-007-002 — Read-only operating layout slice

             Proves CL-010-05, CL-010-07, CL-010-08. Cost level 2: offline integration tests on
             the development PC, using the actual server and headless Chromium; no radio or
             external network. Create an isolated saved profile whose display name includes HTML
             metacharacters and connect the browser. At 1440×900 and 360×800 CSS pixels, and a
             desktop 200% zoom-equivalent CSS viewport, verify station identity and truthful status,
             signal above separator above workspace, no document horizontal overflow, empty
             Band Activity/contact tables and explicit unsupported explanations. Verify unsupported
             controls are disabled and produce no requests. With the capability pushed from available
             to unavailable and back (#22): CQ, Tune, Now and Auto Seq disabled, badge Receive only, the
             reason shown, Control panel and pane unmoved, a running Tune can be turned off, Call 1st
             enabled; a double-click or a Calling me line sends select_row and no enable_tx, the
             menu's Reply disabled, "Auto Seq on" not offered; back to Ready without any action. After a real station restart (#22; a new boot's generation below
             the old one) with no receive job yet: whichever of /receive and /recording answers first,
             and while /receive is still pending, Band Activity heading "Latest decode period", no row
             or divider of the previous boot, Decoder unavailable; with a receive job already running
             at a lower generation: the same heading and rows, Listening for FT8.
             Open/close saved settings and recording
             regions with keyboard; verify existing controls remain reachable in the same page.
             Use separator ArrowUp/Down/Home/End and pointer dragging; verify actual height changes,
             ARIA value changes and the signal remains above the workspace. Disconnect the server
             and verify the global state becomes stale without enabling unsupported controls.
             Independent oracles: the specified layout/order/capability rules and existing server
             status contract; a screenshot alone is not an acceptance oracle. Existing TC-010-005,
             TC-010-006 and TC-010-007 remain the waveform/palette/geometry regressions.
             At360,1440 and1600CSSpx, inspect computed Band Activity cell, time and header
             styles against16CSSpx normal/time/numeric/message and14CSSpx label minima, rem-scaled
             at200% text enlargement, and8CSSpx vertical padding.
             All widths retain these minima; long text wraps without page overflow. Existing splitter, keyboard, capability and transport assertions remain.
             These style oracles come from the stated presentation values, not candidate CSS. Verify the dominant/full-width Band Activity proportions and labelled responsive rows at360/720/1200/1440/1600CSSpx and1x/2x text. Use captured physical FT4 message text strictly as a labelled presentation fixture, plus independent edge strings:3499.9Hz, signed SNR/DT, long callsigns/full messages, large source seconds, UTC-formatted text and every result status. All six values remain literal and inside their own cells; numbers never split, message tokens wrap only when needed, and table labels remain accessible. This fixture is not decoder/RF truth. Capture desktop/narrow/2x screenshots; retain the separate actual nativeFT4/FT8 decoder/browser proofs. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-05';
            verify 'CL-010-07';
            verify 'CL-010-08';
        }
        attribute executable : String = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs; tests/contact.test.cjs; tests/receive-page.test.cjs; server/src/receive_http_tests.rs";
    }
    verification 'TC-007-009' {
        doc /* #### TC-007-009 — Laptop operating screen (#37)

             Proves CL-010-16. Cost level 2: actual isolated server and headless Chromium on the
             development PC; no radio, audio device or network service. A Band Activity record
             with a_priori 1 shows the a1 marker after its message, outside the message text
             (#56 slice 5). At 1366x768: no page
             scroll or horizontal overflow; the top bar holds only the TopBarItem set; no Monitor,
             Enable Tx, Start/Stop receive or Next receive mode control exists; no status text or
             error field entry is shown for a healthy station and each injected exception (stale
             link, receive stopped, unknown receive outcome, audio unavailable) shows its entry in
             the error field below the QSO pane (CL-037-02), which opens its detail; the Rx/Tx strip, Band Activity with the strategy element and the QSO pane are
             visible. At 360x800 the page does not overflow horizontally. The Settings drawer has
             exactly General, Radio, Logging & Reporting and Expert and every control that left the
             operating screen is reachable there, with HALT visible and the waterfall running; a
             restart change during an active contact asks before Apply. Rx/Tx strip steps (1/10 Hz),
             Tx=Rx/Rx=Tx and Hold Tx send exactly the expected contact requests. Band Activity shows
             history newest first with period dividers, double-click replies (select then
             enable_tx) and the right-click menu acts. QSO pane CQ sends enable_tx and a fold-out Now (Tx4
             after RR73 chosen, Tx5) sends choose_next then enable_tx, each with the shown safety revision;
             the pane has no Reply, RR73 or 73 button; on a completed contact Now is disabled and a forced
             click sends no enable_tx. In the operating view one HALT is visible, the QSO pane's,
             the top-bar HALT shows on the Logbook page, in the Settings drawer, and at 1024x768
             and 360 px where the stacked pane HALT is below the fold; a HALT is in the viewport
             without scrolling at every size. With the confirmation popup open during an active QSO its HALT
             sends the halt request. Theme switch changes the theme without a request. Keyboard
             shortcuts act as KeyboardShortcuts and letters are inactive while typing. An
             unauthorized browser shows only the token form and its status line, then the full
             screen after authorization. Settings > General shows "Monitor off at startup" as read
             from GET /receive/startup; toggling it sends exactly one POST /receive/startup
             {v 1, profile_id, boot_id, monitor_off_at_startup} and no receive start, stop or
             selection, a refusal restores the previous value, and Expert shows the resume state;
             Logging & Reporting shows the UDP configuration read from GET /udp (no /udp request
             before the drawer opens) and the instance name as text with no input (CL-112-01);
             editing a target, adding one and Save send exactly one PUT
             /udp {v 1, profile_id, boot_id, expected_revision, configuration} whose configuration
             is the edited list, {targets} only, and no receive start, stop or selection; no Accept commands control exists; a refusal
             shows its code and field and keeps the edits; the send-only note and each target's
             status are shown. An IPv6
             group target [ff12::5754:5358]:2237 (#46, CL-040-06) shows the hop-limit/interface-index hint naming the link-local
             need, and saves with the TTL field as hop limit 2 and interface "1"; the same group
             without an interface is refused with targets[0].multicast_interface.
             Compact QSO pane (#37, QsoPane): with a running QSO at 1366x768 the pane shows the
             header, the last partner message "HB9BLA IW9FRA RR73  +17 dB ×3", the QSO
             dialogue as the #60 table (ten entries, oldest first, the newest row inside the
             section) and below it Calling me oldest first (every station calling me but the
             partner, ⚠ on those within +/-50 Hz of Rx 1500 Hz or Tx 2100 Hz, no DT/frequency;
             no ⚠ with Rx and Tx at 2800 Hz), NEXT "▸ next: <message>" while armed, and the
             buttons, all inside the pane (not clipped); item 8 (#37 2026-11-04): the pane at
             the top of its column, its fixed height proved by TC-037-003; at 1920x1080 at
             least 100 px free below the error field (#37 LowerPanel, TC-037-001); there is no LAST row or
             crowding badge; double-clicking a Calling me line during the QSO sends select_row
             with replace true then enable_tx. Idle, every station calling me is a Calling me row
             "<caller> | <SNR> | <grid> | <country>" (no CQ, even near Rx) whose double-click
             sends select_row then enable_tx. When the contact is
             completed (Log QSO or completion) the pane shows "✓ Logged <call>", no NEXT and
             no partner lines, and after loggedNoticeSeconds only the idle pane; a cancelled
             contact is gone at once. At 360x800 nothing overflows horizontally.
             Independent oracles: the design-interview decisions in the
             model, not the candidate markup. Screenshots at 1366x768 and 360x800. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-16';
            verify 'CL-045-01';
            verify 'CL-040-02';
            verify 'CL-037-03';
            verify 'CL-112-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; server/src/contact_tests.rs";
    }
    verification 'TC-007-006' {
        doc /* #### TC-007-006 — Latest decode and signed relative timing

             Proves CL-010-09, CL-007-02. Cost2: offline automated Windows development-PC tests of the actual
             Rust manager/API and real Chromium using independently scripted sample/clock/result
             fixtures. Existing native FT4/FT8-through-real-decoder proofs remain separate; UI
             fixtures are not RF truth. Cost4 live acceptance uses HB9BLA IC-7300 and this PC's
             browser for operator-authorized receive-only FT4/FT8 observation.

             - Publish two periods with multiple stations and more than16 latest-period records;
               retrieve split/Thin pages, then a newly empty period. Expect every available latest
               row, no earlier rows, no page-size truncation and an explicit empty explanation.
             - Exercise complete/overrun attempts, known gaps, cancellation, failure, late results,
               changed descriptor mid-page, old sockets/epochs, reconnect, expired cursors and safe
               counters. Expect atomic monotonic view identity, truthful Partial/incomplete/stale
               labels, no invented completion and no obsolete row/cursor movement. Existing ring,
               page/record sizes and single pending/cadence remain (the 32 kbit/s link budget is
               judged from the link byte log, #80).
             - Hand oracle: anchor2026-10-27T12:00:00Z at frame0. FT8 starts3600/6000/8400 yield
               DT-0.2/+0.0/+0.2 in12:00:00. FT4 starts3024/5424/7824 yield the same, and frame95424
               yields+0.0 in12:00:07.5. Repeat with a nonzero canonical anchor, day rollover,
               sub-millisecond UTC anchor, nearest-slot ties and signed rounded zero. Without
               correlation both timing fields are null; with correlation and external_accuracy
               unknown timing stays relative to our station, not falsely certified external UTC.
             - At1440px/360px and normal/doubled text inspect the actual UTC Time, signed DT,
               callsigns and all six fields: literal values, unbroken numeric text and no horizontal
               page overflow. In live acceptance observe actual decoded calls in both modes and
               record clock quality without claiming independently measured transmitter clock error.

             Sorting checks: use independently scripted frequency200/1000/3499.9, SNR-20/+10/-5,
             signed DT-0.2/+0.2/unknown and case-varied literal messages. Check all fields and both
             directions, unknown-last, stable ties, arrivals spanning pages, empty/next periods,
             mode/reconnect retention and profile reset (to the #55 value order, the default); verify no new server mutations or changed
             result request cadence. Cost2 Windows actual Chromium/candidate server; cost4 actual
             live calls, operator changes both controls and observes only latest-period rows. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-02';
            verify 'CL-010-09';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; server/src/recording_tests.rs";
    }
    dependency CL_003_04_verified_by_TC_021_006 from 'CL-003-04' to 'TC-021-006';
    dependency CL_003_04_verified_by_TC_021_007 from 'CL-003-04' to 'TC-021-007';
    dependency CL_007_02_verified_by_TC_004_001 from 'CL-007-02' to 'TC-004-001';
    dependency CL_007_02_verified_by_TC_004_002 from 'CL-007-02' to 'TC-004-002';
    dependency CL_007_02_verified_by_TC_004_003 from 'CL-007-02' to 'TC-004-003';
    dependency CL_007_02_verified_by_TC_007_006 from 'CL-007-02' to 'TC-007-006';
    dependency CL_010_05_verified_by_TC_007_002 from 'CL-010-05' to 'TC-007-002';
    dependency CL_010_05_verified_by_TC_009_004 from 'CL-010-05' to 'TC-009-004';
    dependency CL_010_05_verified_by_TC_009_005 from 'CL-010-05' to 'TC-009-005';
    dependency CL_010_07_verified_by_TC_007_002 from 'CL-010-07' to 'TC-007-002';
    dependency CL_010_07_verified_by_TC_009_004 from 'CL-010-07' to 'TC-009-004';
    dependency CL_010_07_verified_by_TC_009_005 from 'CL-010-07' to 'TC-009-005';
    dependency CL_010_08_verified_by_TC_007_002 from 'CL-010-08' to 'TC-007-002';
    dependency CL_010_08_verified_by_TC_009_004 from 'CL-010-08' to 'TC-009-004';
    dependency CL_010_08_verified_by_TC_009_005 from 'CL-010-08' to 'TC-009-005';
    dependency CL_010_09_verified_by_TC_007_006 from 'CL-010-09' to 'TC-007-006';
    requirement 'CL-022-01' {
        doc /* Initial bootstrap authorization enrolls one browser proof key for an
             exact station/profile/radio tuple. Grant validity has no time expiry.
             Delivered credential mechanism: browser creates an ECDSA P-256 signing key through WebCrypto;
             private CryptoKey extractable=false, usages=sign only, persisted solely
             in origin-scoped IndexedDB. Public verifier and random grant identifier
             are enrolled over TLS after existing raw-token authorization succeeds.
             Bootstrap token is never put in IndexedDB or other browser stores.
             No export/wrap/postMessage/worker transfer of private key is permitted.
             This deliberately adds one narrowly named browser credential store;
             it does not claim that existing HttpOnly-only policy already permits it.
             localStorage/sessionStorage/URLs/public JSON/logs remain forbidden.
             Non-extractability is an API export barrier, not protection against
             same-origin injected script, browser compromise or disk administrators.
             Existing script/input/Origin/TLS protections remain mandatory.

             Existing 28800-second HttpOnly Secure SameSite=Strict host-only cookie
             becomes a replaceable transport credential, not grant lifetime. Its
             random 256-bit handle refers to the exact active grant; no runtime
             bootstrap token appears in that cookie. On missing/expired transport
             cookie, browser automatically proves its retained key, without token
             entry, before re-establishing HTTP/WS readiness. Thus a closed browser
             needs no background renewal and may return after arbitrary elapsed
             inactivity while its browser profile/key and server grant are retained.
             A finite cookie extension is not the persistence mechanism.
             Credential erasure/eviction, private-mode loss, origin change and lost
             browser profile are reported as lost credentials, never fabricated as
             revocation or recovered by an embedded bootstrap secret. Browser storage
             retention cannot be guaranteed against erasure by the user agent/OS;
             supported acceptance retains the same ordinary persistent profile.

             Renewal uses a fresh cryptographically random 32-byte one-use challenge
             valid for60seconds, bound to exact HTTPS origin, station/profile/radio,
             grant identifier and protocol version. Signed payload is unambiguous
             length-delimited canonical bytes including the challenge; no arbitrary
             signing oracle. Server consumes a valid challenge atomically before
             cookie issuance; replay/wrong tuple/wrong origin/expired challenge fails.
             Exact Origin is required on enrollment/challenge/proof/revocation; no
             credentialed CORS. Preserve existing TLS and10attempts/60seconds per
             process admission ceiling and1024-byte authentication payload cap.
             Decision (issue22 supervisor): that ceiling is the SETUP budget and counts
             only POST /session, bootstrap-scope and enroll. Grant operations
             (challenge, proof, status, receipt, revoke, commission) never spend it, so
             several browsers can enroll and reconnect at once; they stay bounded by
             the64 pending one-use60s challenges (429 on saturation), one transport
             per grant, proof-of-key and the1024-byte cap.
             New strict typed auth payloads/endpoints are explicit canonical API
             additions, not extra keys silently accepted by old POST /session.
             Cookie missing/duplicate/malformed/wrong profile remains401; automatic
             proof recovery is a separate authenticated transition, not a401 bypass.
             At most64 active grants and64 pending challenges per profile process;
             challenge saturation fails closed429, new enrollment beyond grant cap
             fails explicitly and never expires/evicts an existing unrevoked grant.
             Expired/consumed challenges and expired transport handles are removed;
             no background elapsed-time deletion of active grant verifiers.
             Rejected or lost credentials are terminal for automatic recovery: a
             retained-rejected, invalid or missing credential is never retried
             without an operator action, so it cannot spam challenges or drain any
             admission bound; transient failures back off exponentially to60s.
             Opening a page with a retained credential starts its renewal only after the
             page's load event (issue10 TC-007-005): the asset bytes share the link with
             the challenge, whose 10 s attempt bound would otherwise run out behind them
             and add the 4 s back-off to the first status. A browser without a usable
             credential shows the token form without waiting for the load event.
             Slow-link setup retry (operator decision 2026-11-03, issue22): during one
             token login each setup step (POST /session, bootstrap-scope, enroll, and
             the challenge/proof/status renewal) has its own 10 s attempt bound. A step
             whose attempt timed out or failed on the network (no HTTP status) is
             retried automatically, at most 3 attempts per step after 1 s then 2 s,
             and the whole login stops after 45 s, without a second operator press.
             Enroll repeats the same operation ID and verifier (idempotent receipt);
             a renewal attempt starts from a fresh challenge. Any HTTP refusal
             (401/403/409/413/429/503) or invalid/mismatched response is definitive
             and never retried. While retrying the existing authorizing state stays
             and the connection status shows 'Retrying authorization' with the attempt; page
             unload (pagehide) cancels pending attempts and waits. Each retried
             session/bootstrap-scope/enroll attempt spends the setup budget above.
             Browser Log out revokes this grant (revoke all_for_radio=false), then
             deletes the local key after the committed receipt; the server clears
             the transport cookie. A confirmed rejected/invalid retained credential
             offers 'Forget this browser credential and authorize again', which
             deletes only the local key and shows the bootstrap token form. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/authorization.js; client/app.js; server/src/authorization.rs; server/src/authorization_http.rs";
    }
    dependency CL_022_01_to_FR_019 from 'CL-022-01' to 'FR-019';
    dependency CL_022_01_to_FR_021 from 'CL-022-01' to 'FR-021';
    dependency CL_022_01_to_FR_022 from 'CL-022-01' to 'FR-022';
    verification 'TC-022-006' {
        doc /* TC-022-006, CL-022-01/02; cost2 profiles/protocol companions
             using existing TLS/browser helpers. Reopening a page with a retained credential while
             its last asset is held sends no challenge before the load event, then one.
             Fresh-browser initial journey: POST
             session204 then bootstrap-scope200 with strict independently expected tuple;
             no ordinary status/grant, challenge/transport or CAT I/O is created by read.
             Enroll that exact scope, prove key possession, then grant status is usable.
             Missing/expired/duplicate/cross-profile bootstrap401, wrong Origin403, bad
             TLS/type/unknown/duplicate fields/body/rate bounds have zero effects. Race
             a configuration edit after scope read: stale enrollment409 and no verifier.
             Scope wire oracle is exactly profile_id/radio_id/safety_revision, never
             body Origin; reject body-origin/extra/duplicate keys. Independently use
             valid long saved-origin admission fixtures up to the existing6174 escaped
             origin-byte allowance; exact Origin header is still required, signed
             bytes contain that full origin, compact auth bodies do not echo it.
             Hand-count canonical ASCII widths (UUID36/revision16/IDs43/key87/signature86),
             including JSON quotes/punctuation: scope138, enrollment374, receipt-proof426,
             challenge-response396, conservative receipt302 and bootstrap response170.
             Require actual compact serialization
             <= these envelopes and <=1024; no candidate serializer as expected oracle.
             Full status still includes bounded receive/error fields within1024, not
             truncation or a weakened origin/profile domain. Whitespace-padded request
             exactly1024 accepted when otherwise valid,1025 rejected before effects.
             Independently count volatile transport entries: two valid proofs for A
             leave exactly one current handle, old cookie401/new cookie200, B unchanged;
             <=64 entries, no verifier eviction. Verify durable verifier/receipt bytes,
             revocation generation and commissioning unchanged, with zero independently
             counted native open/query/set/PTT/close effects. Invalid/replayed/expired/
             wrong-Origin/wrong-scope proof and failed randomness/response preparation
             retain the prior current handle. Receipt-purpose proof never rotates it.
             At exact monotonic28800 expiry only transport becomes unusable; purge and
             restart retain grants/receipts/commissioning. Use two ACTUAL tabs sharing
             one context to overlap valid proofs and hold/reverse Set-Cookie responses:
             last committed proof owns the sole handle, while late delivery can yield401.
             Include lost204, existing openWS and queued user mutation; after held
             responses quiesce, fresh proof AND protected read-only status restore the
             shared cookie without key deletion/token prompt or automatic mutation
             replay. UI truth remains<=2s; rotation alone does not revoke an existing
             WS grant or disconnect CAT/audio, while actual revoke still fences effects
             and closes affected WS. Same-document readiness sharing is not a claimed
             cross-tab lock; keep rate10/60 and all other caps/budgets unchanged.
             A record with a null scope, which no delivered operation writes, returns null
             and enrolls nothing (no automated case). Authorize A once; preserve ordinary
             browser profile/key, close actual browser process, remove/expire only its
             transport cookie under test control, advance injected times across28800s
             and browser-cookie retention boundary, restart server/browser. A becomes
             usable through signed proof with zero bootstrap submissions; no long real
             wait claimed. Test retained identity/revision vs another scope, other
             profile/origin, malformed/duplicate cookies, stale/replayed/wrong tuple/
             expired signatures, consumed nonce and challenge saturation. Independently
             fixed tuples/challenge bytes and effect counters are oracle, not server
             status. Erase stored key: explicit lost credential, zero silent recreation.
             Block/corrupt IndexedDB, verifier read/write/commit: explicit failure, no
             unauthorized enrollment or CAT I/O. Reject export/wrap/transfer of key by
             application paths. Verify new-browser bootstrap still required.
             Lost-enrollment-response oracle: hold response independently, persist
             enrollment then drop response and restart server/browser with same
             profile/key/operation ID. Independently inspect committed-store fixture
             and native peer: one retained grant, no duplicate enrollment and zero
             queued browser CAT effects while unauthorized/unknown. Read-only receipt
             reconciliation identifies the exact committed tuple/verifier, then scoped
             proof establishes readiness. Contrast pre-commit failure: no retained
             grant after restart and no successful receipt/proof. No assumption that
             server can observe browser receipt of a success response is allowed.
             Slow-link setup retry oracle (independent request counters on the actual
             browser; the page's clock is installed before load and driven, issue70,
             no real wait): hold the first bootstrap-scope response; at 9999 ms no
             retry is shown and one bootstrap-scope was sent, at 10000 ms the status
             shows 'Retrying authorization (attempt 2 of 3)'; the late response is
             then delivered and the page becomes connected after one token press with
             one session, two bootstrap-scope and one enrollment.
             A network-failed enrollment is repeated once with the identical operation
             ID and verifier and connects. Network failure of every /session
             attempt: 1 attempt at +999 ms and 2 at +1000 ms after the first failure,
             2 at +1999 ms and 3 at +2000 ms after the second, then 'Could not
             authenticate', and still exactly 3 after the clock runs past the 45 s
             login bound. A 401 bootstrap-scope is never retried (counts 1/1/0 after
             the clock runs past 45 s). A pagehide event on the live page during a
             held attempt cancels it: no further setup request after the clock runs
             past 45 s (counts 1/1/0).
             Held profile bodies across a renewal (#73): a GET /profile 200 whose body is held
             while the transport cookie is cleared, the authorization renews and a new
             socket connects is never applied ('Could not load saved settings', form
             kept). A PUT /profile 200 held the same way is the save's outcome
             (CL-073-01): on release 'Saved revision 1', Save enabled, the form holds
             the saved value, exactly one PUT and revision 1 on disk.
             Grant revocation and configuration edits (operator 2026-11-06: moved here from
             the retired TC-022-007). Disable/re-enable and endpoint edit preserve UUID;
             endpoint change advances safety revision/invalidates commissioning only.
             Two A browser grants plus B; logout one A leaves otherA/B; revoke-allA
             removes bothA only; restart cannot revive acknowledged revocation. Race
             queued HTTP/WS mutations and selection against revocation with independently
             held dispatch barrier and peer counters: none dispatches after commit;
             pre-dispatched effects follow cancellation/release rather than fabricated
             rollback. Drop ack before/after commit, retry same operation ID, reload
             receipt; no duplicate operation or new credential. Inject durable-write
             failure/restart and verify documented last-committed-state limitation and
             failclosed current process. Cap64 grants without evicting active grants;
             delete verifier and replay old proof/cookie: rejected, no tombstone growth.
             Automated companions: tests/profiles.test.cjs TC-022-006 cases (TC-022-004
             covers browser logout and revoke-all) and server/src/auth_tests.rs, including
             plaintext runtime-token operating access, logout/revoke fencing of every
             operating HTTP route and WS upgrade, foreign grant refusal and commission
             receipts; station-authority unit tests in server/src/authorization_tests.rs.
             Injected-time restart: the store-level cases there use an injected clock (a
             transport usable at 28799 s and refused at exactly 28800 s, a challenge 400 days
             on, a reopen keeping grants and receipts with no transport), and
             tests/profiles.test.cjs "actual browser and server process restart" removes the
             cookie and restarts both processes. Only the slow-link setup retry case
             drives a browser's clock; the cookie-retention and 28800 s combination stays
             unautomated, and TC-022-010 observes controlled cookie expiry live. */
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String = "tests/profiles.test.cjs; server/src/auth_tests.rs; server/src/authorization_tests.rs";
        objective {
            verify 'CL-022-01';
            verify 'CL-022-02';
            verify 'CL-073-01';
        }
    }
    dependency CL_022_01_verified_by_TC_022_006 from 'CL-022-01' to 'TC-022-006';
    verification 'TC-022-010' {
        doc /* TC-022-010 CL-022-01..05 authorized cost4 IC7300 receive-only acceptance. Record the actual deployed SHA/receipt/fresh radio identity and preserve official
             WSJTX noCAT/PTT comparison. Observe explicit initial commissioning once,
             ordinary startup/reconnect with no Connect buttons, unavailable/return/
             cable/server/browser restart, truthful independent health/freshness and
             latest real decode rows. Retained-browser proof after controlled cookie
             expiry is observed; simulated clock boundary labelled simulated. PTT
             remains released; zero transmit acceptance is added. Accepted live
             on 2026-11-08 (6719540079); the freeze is accepted on the trace. Independent source/model review,
             red-on-parent, exact ordinary gates and actual acceptance all required.
             Where: HB9BLA installed exact gated candidate, actual IC-7300 COM3/USB Audio CODEC and authenticated browser. Physical acceptance is planned and consent-bound, not an automated simulator verdict. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-022-01';
            verify 'CL-022-02';
            verify 'CL-022-03';
            verify 'CL-022-04';
            verify 'CL-022-05';
        }
    }
    dependency CL_022_01_verified_by_TC_022_010 from 'CL-022-01' to 'TC-022-010';
    requirement 'CL-044-06' {
        doc /* Settings > Radio "Detect radio" (operating screen of #37): the Detect radio button is enabled only after the operator ticks the confirmation that USB SEND and USB keying (CW/RTTY) are OFF or the radio is on a dummy load, and that opening a port can pulse DTR/RTS also on other CP210x boards; one press sends one POST /radio/detect {v 1, profile_id, boot_id, keying_inhibit_confirmed true} and clears the tick. Nothing is fetched without a press (no polling). The panel shows each port's state and radio, the proposal (port, model, CI-V address, baud, control endpoint, input and output endpoint names as CL-044-07 (the endpoint ID only on hover), or "not matched") and the settings items with value, severity and guidance. "Use this setup" only fills the Radio section (control mode, endpoint, PTT, audio input and output IDs); the operator saves it with Apply ⟳, which restarts receive as any Radio change, and then gives the existing receive-only confirmation (CL-022-03). "Apply recommended radio settings" and "Undo radio settings" are enabled only while CAT is ready with a known connection generation, the transmit state is known (the operating client with its confirmation dialog is loaded) and the transmitter is disarmed and not tuning, each asks its own confirmation and sends one POST /radio/settings/apply or /undo {v 1, profile_id, boot_id, connection_generation}, then shows the written items or the refusal. All server text is shown as text. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js";
    }
    dependency CL_044_06_to_FR_019 from 'CL-044-06' to 'FR-019';
    requirement 'CL-044-08' {
        doc /* Settings > Radio has one Audio section (#settings-audio, a restart setting marked ⟳) holding all audio settings: the Input select with the Rx level meter beside it, the Output select, and the radio's recommendation. Each select offers "None" (null) and the endpoints of its flow from GET /audio/endpoints (read when the Settings drawer opens, at most every 5 s, and after Reload saved settings or a save); an option's text is the label of CL-044-07, its value the endpoint ID, and the ID appears only in the option's hover title and in Settings > Expert ("Audio endpoint IDs": the saved input and output IDs). A saved endpoint that is not present is shown as the selected, disabled option "<last known name> · not present"; while the listing is unavailable the saved value stays selected as "Saved device". There is no free-text endpoint input and no separate input listing. When an endpoint is marked with the radio, the section shows "Recommended: <input label> / <output label>" and the button "Use IC-7300 audio", which selects those endpoints and saves them with the same Apply ⟳ (one PUT /profile, with its usual confirmation); choosing in a select alone saves nothing. The Audio capability line in Expert names the running input by /receive audio.device_name. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/app.js; client/recording.js";
    }
    dependency CL_044_08_to_FR_019 from 'CL-044-08' to 'FR-019';
    dependency CL_044_08_to_FR_002 from 'CL-044-08' to 'FR-002';
    verification 'TC-044-007' {
        doc /* TC-044-007 — Audio section shows names, not endpoint IDs
             CL-044-08
             Setup: actual candidate server on a disposable plaintext profile whose saved input is a fixture capture ID and Chromium; GET /audio/endpoints answered by a route fixture (the CODEC pair marked IC-7300, two same-named headsets, the saved input absent with its last known name), so no device is read.
             Steps: open Settings > Radio; read the Audio section, its options and their hover titles; read Settings > Expert; choose the second headset (no PUT); press Use IC-7300 audio; GET /profile; 360 px width.
             Expected: one Audio section holding #audio-input, the Rx level meter and #audio-output, no #audio-enumerate, no text input for a device; option texts "Microphone (USB Audio CODEC) — IC-7300", "Headset ... #1", "... #2", the saved input selected, disabled and labelled "... · not present"; no visible text of the Radio section contains an endpoint ID ("{0.0."), each option's title is its ID, Expert shows the saved ID; choosing sends no PUT; Use IC-7300 audio sends exactly one PUT /profile and the saved profile holds the two CODEC IDs; no horizontal scroll at 360 px; no page error.
             2 — Isolated automated browser test; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-08';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_08_verified_by_TC_044_007 from 'CL-044-08' to 'TC-044-007';
    verification 'TC-044-005' {
        doc /* TC-044-005 — Detect radio panel
             CL-044-06
             Setup: actual candidate server on a disposable plaintext profile (CAT not authorized, so no CAT owner opens anything) and Chromium; /radio/detect and /radio/settings/* answered by route fixtures with a hand-written IC-7300 proposal on COM250, so no serial port is probed.
             Steps: (separately) hold back the operating client and press Apply recommended radio settings with CAT ready; open Settings > Radio; wait 1.5 s; try Detect radio without the tick; tick and press it; Use this setup; check Apply/Undo with CAT not ready; with CAT ready and the station's connection generation, Apply recommended radio settings, cancel, again with Continue, Undo with Continue; Apply ⟳; GET /profile; 360 px width.
             Expected: with the client held back both buttons disabled and no /radio/settings request; no /radio request before the press; the button disabled without the tick; exactly one detect body {v 1, profile_id, boot_id, keying_inhibit_confirmed true}; port, model, 94h, 19200, endpoint, both friendly names (each endpoint ID only in its hover title, not in the text) and the 0078 DTR blocking item shown; the tick cleared; the five Radio fields filled with no PUT; Apply/Undo disabled until CAT ready; the cancelled apply sends nothing, then exactly apply and undo with {v 1, profile_id, boot_id, connection_generation} of that generation; the saved profile holds the proposed control and the two endpoint IDs; no horizontal scroll at 360 px; no page error.
             2 — Isolated automated browser test; Windows development PC, no radio, serial port or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-06';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_06_verified_by_TC_044_005 from 'CL-044-06' to 'TC-044-005';
    // #68 (operator 2026-11-08: "you could show it somewhere in the UI and mark it red if it is
    // above two"; grill-me 2026-11-09: end of the Rx/Tx strip, the last reading stays, red
    // strictly above 2.0, the error field entries and the Tx stop at 3.0 unchanged).
    requirement 'CL-068-01' {
        doc /* (#68) SWR on the operating screen. The Rx/Tx strip under the waterfall (WstxSignalArea::RxTxStrip) ends, after Rx=Tx, with the text "SWR x.x": the SWR of the latest radio.tx_level push (CL-044-13) of this profile and boot, swr_x10 / 10 with one decimal, shown while that push has managed true and meters with a non-null swr_x10, and hidden otherwise (no push yet, meters null, swr_x10 null, managed false, or a station-ready of another boot). The value is the last reading: it stays after the transmission or Tune that produced it, until a push changes it, and is not cleared by a band change. It is red, in the page's error colour (--op-error, remapped by the Day and Night themes like the page), when swr_x10 is above 20 (2.1 and up; on the IC-7300 raw 0084 and up), and in the strip's normal text colour at 20 (2.0) and below. Nothing is requested or polled for it: it follows the pushed radio.tx_level only. It takes no pointer input and adds no strip line: at 1366x768 and wider the strip keeps its one-line height and the waterfall its place; at 360 px the strip may wrap, with no horizontal scroll. Unchanged by #68: the meter readings and their timing (CL-044-14: one reading per transmission, once per second during Tune, pushed only when they change), the Settings > Radio > Audio meter line (CL-044-13), the error field entries txSwrHigh (SWR at or above 2.0 from the third transmission in a row) and txSwrFault (CL-037-02), and the station's own Tx stop at SWR at or above 3.0 (raw 0120, CL-044-14). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/recording.css";
    }
    dependency CL_068_01_to_FR_019 from 'CL-068-01' to 'FR-019';
    verification 'TC-068-001' {
        doc /* TC-068-001 — SWR at the end of the Rx/Tx strip
             CL-068-01
             Setup: actual candidate server on a disposable plaintext profile and Chromium at 1366x768, 1920x1080 and 360x800; radio.tx_level events injected into the page's station-message stream as the server sends them (as TC-044-015), every request of the page recorded.
             Steps: (a) open the operating screen with no radio.tx_level yet; (b) push managed true, meters null; (c) push meters {alc 0, po_pct 40, swr_x10 null}; (d) push swr_x10 14; (e) push a level change with the same meters (as after the transmission); (f) a band change; (g) push swr_x10 20, then 21, then 30 with warnings [swr_fault]; (h) in the Dark, Day and Night themes read the colour at 14 and at 21; (i) push managed false with swr_x10 14; (j) push managed true with swr_x10 14 and another profile's id, then a station-ready of another boot; (k) at each width measure the strip's height and the waterfall's top and height with and without the value; (l) click the value.
             Expected (oracle: CL-068-01 and the operator's #68 answers): (a) to (c) no SWR text in the strip; (d) the strip's last item, after Rx=Tx, reads exactly "SWR 1.4" in the strip's normal text colour; (e) and (f) still "SWR 1.4"; (g) "SWR 2.0" not red, "SWR 2.1" and "SWR 3.0" in --op-error, and the error field shows its swr_fault entry as before; (h) in each theme the 2.1 colour is the theme's --op-error and the 1.4 colour the strip's text colour; (i) hidden; (j) unchanged by the other profile's push, hidden after the other boot's station-ready; (k) at 1366x768 and 1920x1080 the strip height, waterfall top and height equal those without the value (within 0.5 px); at 360x800 no horizontal scroll; (l) no request, nothing changes; no request at all caused by the pushes and no timer request; no page error. Red on the parent: no SWR text in the strip.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-068-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_068_01_verified_by_TC_068_001 from 'CL-068-01' to 'TC-068-001';
    verification 'TC-068-002' {
        doc /* TC-068-002 — SWR on the operating screen on HB9BLA
             CL-068-01
             Setup: the gated candidate installed on HB9BLA, the IC-7300 on CAT on 40 m FT8 into the station antenna, within the operator's standing transmit consent; the radio.tx_level frames recorded from the station's socket.
             Steps: open the operating screen after a station restart; transmit at least two FT8 transmissions (a CQ suffices); after the last one watch the strip through the following receive period; switch to 20 m without transmitting.
             Expected (oracle: the recorded radio.tx_level frames, not the radio's display, operator decision of 2026-11-08): no SWR text before the first reading; from the first frame with meters the strip's last item reads "SWR " and swr_x10 / 10 of the latest frame, red exactly when that is above 2.0 (on the station antenna normally not red); the value stays through the receive period after the transmission and after the band change; the Settings > Radio > Audio meter line shows the same SWR; the strip stays one line at the operator's screen width. A mismatched antenna is not used (#44 decision of 2026-11-08); red is proven by TC-068-001.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-068-01';
        }
    }
    dependency CL_068_01_verified_by_TC_068_002 from 'CL-068-01' to 'TC-068-002';

    // #57 Decode display speed (operator 2026-11-02; defaults recorded on issue #57).
    requirement 'CL-057-01' {
        doc /* Band Activity on the Detailed display profile shows a published decode view without waiting for a refresh cadence: each new or grown latest_decode publication is announced to every Detailed WebSocket peer at once as a receive.state event (Thin and Off peers keep the 2 s receive tick), and a Detailed browser then fetches the view's records immediately, page after page (limit 16), until its cursor reaches the view's frozen end, instead of at most once per 4 s. A failed result read (which falls back to at most once per 4 s until a page succeeds) and the Thin rules (one pending request, limit 1, at most once per 4 s, page at most 3072 bytes) are unchanged; with no announced or unread view and no failed GET /receive or result read, the idle read on every display profile is only a safety read at most once per 30 s (#10 WstxStationProtocol::PushedStationState), so the two-browser 32 kbit/s budget still holds. On a LAN every row of a published view is painted at most 0.3 s after its publication; "Loading results" shows only while records of the view are still being fetched. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_057_01_to_FR_010 from 'CL-057-01' to 'FR-010';
    dependency CL_057_01_to_FR_019 from 'CL-057-01' to 'FR-019';
    verification 'TC-057-001' {
        doc /* TC-057-001 — Busy live period reaches Band Activity promptly (Detailed)
             CL-057-01
             Setup: actual isolated station Router, Recording owner, native live source, converter, UTC window schedule and modem, fed in real time with the hash-pinned busy recording websdr_test7.wav as 48 kHz native capture whose QPC clock is the system clock, filling an FT8 UTC period and again the periods 30 s and 60 s later, with silence around them; one Chromium page on the Detailed default.
             Steps: start FT8 receive from the Receive stopped chip; record the server's published counters and latest_decode (1 ms sampling), the browser's receive.state frames, /receive and /receive/results requests and every Band Activity change at the next animation frame, all on the system clock; read the first two period views' records through the actual results API; while the third busy period is published, every /receive/results read answers 503 for 9 s, then normally.
             Expected (independent oracle: the published records themselves and the issue's 0.3 s decode-to-row target): for each of the two periods: at least 25 records in the view; the painted rows are exactly the view's records (same message texts); every row is painted at most 300 ms after the view's publication. During the outage the failing reads start at least 3950 ms apart (no faster retry with records pending), and the third period's rows are painted within 5 s after reads recover. The parent client (2 s receive tick, one 16-record page per 4 s) painted them about 5 s after publication.
             2 — Isolated automated functional test; Windows PC, release build, WSTX_SAMPLE_DIR, no radio or audio device. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-01';
        }
        attribute executable : String = "server/src/receive_http_tests.rs; tests/receive-latency.test.cjs";
    }
    dependency CL_057_01_verified_by_TC_057_001 from 'CL-057-01' to 'TC-057-001';
    dependency CL_057_01_verified_by_TC_057_002 from 'CL-057-01' to 'TC-057-002';
    verification 'TC-057-003' {
        doc /* TC-057-003 — Live decode display on HB9BLA
             CL-057-01, CL-057-02, CL-007-05
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 receiving a busy FT8 band, one browser on the LAN on the Detailed profile; no transmission.
             Steps: watch Band Activity over 10 consecutive FT8 periods; read GET /receive audio over the same periods.
             Expected: no "Loading results" visible in normal operation; every row of each period is painted by period start + 15.3 s (CL-007-05 publication by +15.0 s plus CL-057-01's 0.3 s; #72), the observed times being reported; under that decode load no audio_stalled loss (#49): loss_epochs unchanged.
             4 — Live on the station, receive only; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-057-01';
            verify 'CL-057-02';
            verify 'CL-007-05';
        }
    }
    dependency CL_057_01_verified_by_TC_057_003 from 'CL-057-01' to 'TC-057-003';
    verification 'TC-055-006' {
        doc /* TC-055-006 — Band Activity colours, hover text and value order for every sender
             CL-055-04, CL-055-02
             Setup: actual router with a selected profile whose log holds DL1ABC JO62 20m FT8 (TC-055-002); in the browser the operating fixture with routed result records carrying #55 flags and dxcc, selection band 20m and the worked_status of each sender.
             Steps: read /receive/results for a report and an R-report to other stations from new senders (K9XX G4XYZ -10, K9XX YO3ABC R-07) and an RR73 from a sender worked on 20m FT8 (K9XX DL1ABC RR73); in the browser render one period with a report from a new-DXCC sender (YO3ABC K9XX -07), a row to my call, a new CQ zone, a new grid, a new call, two rows of equal value with different SNR and a worked-before CQ without flags; turn Highlight on with a strategy hit.
             Expected: the server gives both non-CQ senders their dxcc and flags (England new call, DXCC and ITU zone; Romania new DXCC) and the worked sender Germany without flags; the YO3ABC report colours only its sender call new DXCC (#50 CL-050-08) and its reason tip is "New DXCC · New call"; the row to my call keeps the my-call colour over the whole row and its tip is "New call"; the new CQ zone CQ is coloured over the whole row; the worked-before CQ has no colour and no reason tip; rows are in value order calling me, strategy hit, new DXCC, new zone, new grid, new call, no flag, equal values strongest first; the DXCC header restores this order after a Freq sort.
             2 — Isolated automated (functional) tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-04';
            verify 'CL-055-02';
        }
        attribute executable : String = "server/src/dxcc_tests.rs; tests/ui-operating.test.cjs";
    }
    requirement 'CL-054-01' {
        doc /* A Detailed waterfall subscriber receives every Detailed row of the current job in order after a processing stall: the station retains the last 25 rows and sends each peer the oldest row it has not sent, 200 ms apart, 170 ms apart while rows wait (WstxStationProtocol::TransferDisplay). Live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart. The browser draws a gap row only for a real gap; one or two live Thin rows paced out between two sent rows are drawn with the next row. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_054_01_to_FR_019 from 'CL-054-01' to 'FR-019';
    dependency CL_054_01_to_FR_021 from 'CL-054-01' to 'FR-021';
    requirement 'CL-111-04' {
        doc /* Display. On a station with transmit capability the operating view shows the transmit state and the cause of its last change at all times, in every region, at 360 px and at 1366x768. It follows only the pushed station state and takes no pointer or keyboard input. Texts. On: "Tx on"; "Tx on · Auto". Off: "Tx off" (startup); "· QSO complete"; "· QSO cancelled"; "· halted"; "· Tx watchdog: same message sent N times"; "· radio lost"; "· radio settings changed"; "· Tx refused · <reason>"; "· <call> works another station"; "· mode changed"; "· band changed"; "· automation ended". Not delivered yet: the display. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_111_04_to_FR_019 from 'CL-111-04' to 'FR-019';
    requirement 'CL-111-09' {
        doc /* The Now button is removed. The Tx lines of the fold-out "Messages Tx1-Tx6" keep their Next choice and their text and have no Now button. Not delivered yet: the Now button is still there. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_111_09_to_FR_019 from 'CL-111-09' to 'FR-019';
    verification 'TC-111-005' {
        doc /* TC-111-005 — The display shows state and cause
             CL-111-04
             Setup: Chromium against the candidate server with a recording hardware double.
             Steps: each text of CL-111-04, at 360x800 and 1366x768, in each region, after a reload and in a second browser; a click and a key on the display.
             Expected (the texts of CL-111-04): each text is shown; the click and the key send no request.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-04';
        }
    }
    dependency CL_111_04_verified_by_TC_111_005 from 'CL-111-04' to 'TC-111-005';
    verification 'TC-111-014' {
        doc /* TC-111-014 — No Now button
             CL-111-09
             Setup: Chromium against the candidate server.
             Steps: the fold-out "Messages Tx1-Tx6"; choosing Next on a Tx line.
             Expected (CL-111-09): no .ct-now element; each Tx line has its Next choice and text; choosing Next sends one choose_next and no start.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-09';
        }
    }
    dependency CL_111_09_verified_by_TC_111_014 from 'CL-111-09' to 'TC-111-014';
    dependency CL_111_04_verified_by_TC_111_015 from 'CL-111-04' to 'TC-111-015';
    verification 'TC-054-001' {
        doc /* TC-054-001 — Detailed rows in order after a stall; gaps only for real gaps
             CL-054-01
             Setup: the station's detail_after/arm_detail functions with a hand-written ring; the browser page with injected live frames.
             Steps: five rows 11..15 retained after the socket sent row 10; a new job's rows; a caught-up socket; Thin sends 100 ms late for 10 periods, after a 5 s pause, 1.5 s and 1 s late; inject live Thin frames 0, 2, 5, 6 and 10; run the Detailed replay cadence.
             Expected: rows 11..15 sent once in order, "behind" true until the last; a new job starts at its oldest row; nothing resent; catch-up spacing 170 ms, steady 200 ms; Thin anchors stay on the 2 s grid, restart after the pause and after a send 1.5 s late, and the next send is at least 1 s later; row 1 drawn with row 2's levels and rows 3..4 with row 5's, rows 7..9 grey gaps; Detailed sends at least 165 ms apart and at most 5.9 per second.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-054-01';
        }
        attribute executable : String = "server/src/protocol_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_054_01_verified_by_TC_054_001 from 'CL-054-01' to 'TC-054-001';
    verification 'TC-054-003' {
        doc /* TC-054-003 — Live waterfall on HB9BLA
             CL-054-01, CL-054-02, CL-050-01, CL-050-02
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 receive, the operator's page.
             Steps: watch 5 min of receive; the operator, who knows the WSJT-X Wide Graph, judges the waterfall against it (coordinator decision on #54: no WSJT-X GUI run).
             Expected: no grey seams during continuous receive; FT8 signals show start and end; strong signals distinguishable; the operator confirms the colours and the pointer mapping.
             3 — Live, read-only on the station; with the operator at acceptance. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-054-01';
            verify 'CL-054-02';
            verify 'CL-050-01';
            verify 'CL-050-02';
        }
    }
    dependency CL_054_01_verified_by_TC_054_003 from 'CL-054-01' to 'TC-054-003';
    requirement 'CL-037-05' {
        doc /* (#37, operator 2026-11-04: the QSO area offered "Change contact to W4WFC DL1FRH JO30", "This makes no sense") While a contact is active, a click on a Band Activity row offers a contact change only for a row that can start a contact for me, a CQ/QRZ complying with the directed-CQ rule (WstxStrategy::DirectedCqRule, also without Highlight or an active strategy) or a row addressed to my call, and the offer names the sender ("Change contact to K1ABC"); a click on a row of a QSO between others or on a CQ directed elsewhere offers nothing and leaves no refusal text. A deliberate double-click on such a row calls its sender and its command line reads "Call <sender>", never the foreign message. Details: WstxBandActivity::BandActivityView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js; server/src/contact_http.rs";
    }
    dependency CL_037_05_to_FR_007 from 'CL-037-05' to 'FR-007';
    verification 'TC-037-004' {
        doc /* TC-037-004 — A contact change is offered only for a row that can start a contact for me
             CL-037-05
             Setup: actual candidate server and Chromium at 1366x768; my continent EU from HB9BLA; routed live rows "CQ K1ABC FN42", "QRZ W1XYZ FN31", "HB9BLA DL1ABC JO31", "W4WFC DL1FRH JO30", "CQ EU G4ABC IO91", "CQ DX K2DX FN42" (NA), "CQ NA K3NA FN42" and "CQ DX DL2DX JO31" (EU); a running contact with IW9FRA; a routed POST /contact/command that refuses select_row without replace as directive_not_answerable for "CQ NA K3NA FN42" and "CQ DX DL2DX JO31" and as contact_active for the other rows, and accepts everything else.
             Steps: click each row and read the change button and the command line; double-click the foreign row and read the commands and the command line.
             Expected (independent oracle: the operator's report of 2026-11-04 on #37): CQ, QRZ, addressed and complying directed rows offer "Change contact to K1ABC", "Change contact to W1XYZ", "Change contact to DL1ABC", "Change contact to G4ABC" and "Change contact to K2DX"; the foreign row and both CQs directed elsewhere each remove the offer, show none and leave the command line empty; its double-click sends select_row with replace true, then enable_tx, and the command line reads "Call DL1FRH: accepted".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_05_verified_by_TC_037_004 from 'CL-037-05' to 'TC-037-004';
    // #74 An open page after a station restart (operator 2026-11-08, one grill-me round).
    requirement 'CL-074-01' {
        doc /* (#74, live acceptance 2026-11-08, #39 comment 6719540492: after a station restart an open page kept "Strategy Farthest new on band · Auto off" until reloaded, while the station had None and Auto off) After a station restart an open page shows the new boot's state without a reload, within the push rule. When the browser learns a boot_id other than the one a view's held station state belongs to, that view drops the state at once and shows the form of a freshly loaded page before its reads; it never shows a value of the previous boot, alone or with values of the new boot; a snapshot reply naming another boot is discarded; once the new boot's reads and first events have arrived the page equals a freshly loaded one. The automation view reads GET /automation only after an automation.state event, never once per socket, and on a new boot holds the never-used state without a request. The strategy element's line is drawn from the current strategy and automation snapshots together at each change of either; with None and no strategy run it shows the automation text, "Automation idle" without a run. No new request kind, no retry timer, no server change. Details: WstxStationProtocol::PushedStationState, WstxOperatingLayout::AutomationIndicator, WstxStrategy::StrategySelector. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/app.js; client/contact.js; client/recording.js";
    }
    dependency CL_074_01_to_FR_019 from 'CL-074-01' to 'FR-019';
    verification 'TC-074-001' {
        doc /* TC-074-001 — Reproduction: a page open across a station restart
             CL-074-01
             Setup: the actual isolated candidate server restarted under the test's control with the page left open (as the #22 restart in tests/receive-page.test.cjs), Chromium at 1366x768, no radio; the page's GET /strategy of the new socket held back 2 s by the test (the order a thin link gives), other requests unchanged; requests recorded.
             Steps: select "Farthest new on band" with Auto off and wait for "Strategy Farthest new on band · Auto off"; restart the server; record the line #station-automation, the selector and the Auto button at each change from the reconnect until 3 s after GET /strategy answered; then open a second page on the same server and read the same three.
             Expected (oracles: the station's state after a restart, active None and Auto off, WstxStrategy D2; the freshly opened second page): the line never shows "Strategy Farthest new on band" after the new boot is learned; at the end the line is "Automation idle", the selector None, and line, selector value and Auto pressed state, disabled state and title equal those of the second page; no GET /automation after the restart (no automation.state while automation is unused); no page error. Red on the parent: the line keeps "Strategy Farthest new on band · Auto off".
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-074-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_074_01_verified_by_TC_074_001 from 'CL-074-01' to 'TC-074-001';
    verification 'TC-074-002' {
        doc /* TC-074-002 — The strategy line with None and no strategy run
             CL-074-01
             Setup: actual browser with hand-written replies for GET and PUT /strategy and GET /automation and pushed strategy.state and automation.state (as TC-039-046); no automation.state before the steps.
             Steps: read the line; select "New calls" with Auto off; select None; push a pounce run (automation.state, configuration strategy false, pounce K1ABC waiting); push its stop with reason no_answer; push run null.
             Expected (oracle: the texts of WstxOperatingLayout::AutomationIndicator and WstxStrategy::StrategySelector): "Automation idle"; "Strategy New calls · Auto off"; "Automation idle" (not the previous text); "Pounce K1ABC waiting · HALT ends it"; "Automation stopped · no answer"; "Automation idle"; no GET /automation before the first automation.state and exactly one after each. Red on the parent: "Strategy New calls · Auto off" stays after None.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-074-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_074_01_verified_by_TC_074_002 from 'CL-074-01' to 'TC-074-002';
    verification 'TC-074-003' {
        doc /* TC-074-003 — Every view on a new boot
             CL-074-01
             Setup: actual browser and isolated server; the test rewrites the server's replies and socket messages to name boot A, then boot B, and holds boot B's reads (GET /contact, /recording, /strategy, /pskr, /receive/startup, /strategy/alerts) and a boot A POST /strategy/ignore reply until it releases them; boot A has replies for GET /profile, /contact, /strategy (Farthest new on band selected, Auto on), /automation (an active strategy run in contact with K1ABC, with hearing and free_tx_slots, announced by automation.state), /pskr (connected), /receive/startup (Monitor off at startup on), /strategy/alerts and the recording and receive reads, and pushed radio.agc, radio.tx_level and transmit.state of boot A; "Show free Tx slots" on; then the socket closed and a new one whose GET /profile names boot B, the replies of boot B (None, Auto off, PSK Reporter off, Monitor off at startup off, no alerts, no automation.state) each held back 2 s; a late reply of boot A to GET /strategy and GET /pskr delivered after boot B is learned; a second case in which boot B's GET /strategy and GET /pskr answer 503.
             Steps: read every view listed in WstxStationProtocol::PushedStationState at each change from the moment boot B is learned until 3 s after the last reply; then open a second page on boot B's replies and read the same views; count the requests.
             Expected (oracles: the boot B replies written in the test and the second page): from the moment boot B is learned no view shows a value of boot A: line not "Pounce", data-active false, no Free Tx slot marks, no PSK hearing lines, Auto not pressed, the selector not on "Farthest new on band", PSK Reporter and Monitor off at startup not shown as on; while the replies are held each faulty view shows the second page's form before its reads; the late boot A replies change nothing; at the end every view equals the second page's; with 503 the strategy and PSK Reporter views stay in their empty form and nothing of boot A returns; no GET /automation on boot B, no request beyond one read per state and socket, no timer request in 5 s; the already conforming views (contact, recording, receive, operating, AGC, Tx level, native, transmit, alerts) show no boot A value as well. Red on the parent: boot A's strategy, automation and PSK Reporter values are shown after boot B is learned.
             #82: there is no "Show free Tx slots" checkbox (the marks are always shown); boot A's open slot marks come from a pushed free_tx_slots.state of boot A, and from the moment boot B is learned no mark of boot A is drawn until boot B's first free_tx_slots.state.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-074-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_074_01_verified_by_TC_074_003 from 'CL-074-01' to 'TC-074-003';
    verification 'TC-074-004' {
        doc /* TC-074-004 — Live: the operator's page across the deploy restart on HB9BLA
             CL-074-01
             Setup: the gated candidate deployed on HB9BLA by the operator's approved deploy, its own station restart; the operator's page (or the live page check, tests/live-page-check.cjs) open before the restart with a strategy selected and Auto off; no transmission.
             Steps: keep the page open across the restart; after it is connected to the new boot read the line, the selector, Auto and the PSK Reporter view, then reload and read them again.
             Expected (oracle: the reload of the same page): without a reload the line is "Automation idle", the selector None, Auto off; the values equal those after the reload; recorded on the issue.
             3 — Live read-only observation on the station during the deploy's own restart; no RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-074-01';
        }
    }
    dependency CL_074_01_verified_by_TC_074_004 from 'CL-074-01' to 'TC-074-004';
}
