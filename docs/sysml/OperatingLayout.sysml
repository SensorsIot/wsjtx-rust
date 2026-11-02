package WstxOperatingLayout {
    private import ScalarValues::*;

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
             no fabricated UTC/DT, message text or resolved hash. Full source/job/
             generation/sequence binds each row; new identity clears rows, stale
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

    enum def ActivitySortField { enum frequency; enum signalStrength; enum dt; enum 'message'; }
enum def ActivitySortDirection { enum ascending; enum descending; }
attribute def ActivityOrdering {
    attribute field : ActivitySortField = ActivitySortField::frequency;
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
         filtering, station selection, arming or automation. Keyboard/360px/2x. */
}

    attribute def LatestBandActivity {
        attribute currentDescriptorId : Integer;
        attribute incomingDescriptorId : Integer;
        attribute sameContext : Boolean;
        attribute snapshotFresh : Boolean;
        attribute mayReplace : Boolean;
        attribute inFrozenRange : Boolean;
        attribute sameUtcPeriod : Boolean;
        attribute clockCorrelated : Boolean;
        attribute mayShowRow : Boolean;
        attribute latestEmpty : Boolean;
        attribute cursorAtFrozenEnd : Boolean;
        attribute loadingResults : Boolean;
        attribute displayedRows : Integer;
        attribute complete : Boolean;
        attribute partialLabel : Boolean;
        assert constraint freshPeriod { mayReplace == (sameContext and snapshotFresh and incomingDescriptorId >= currentDescriptorId) }
        assert constraint latestRows { mayShowRow == (sameContext and inFrozenRange and (not clockCorrelated or sameUtcPeriod)) }
        assert constraint deliveryProgress { loadingResults == not cursorAtFrozenEnd }
        assert constraint emptyClears { latestEmpty implies displayedRows == 0 }
        assert constraint truthfulPartial { partialLabel == not complete }
        doc /* CL01009, TC007006, contract 4.7.4. New descriptor clears old rows once and
             seeks its first retained cursor; all pages accumulate <=2048, never page-only.
             Loading results until cursor reaches frozen end; attempt completion does
             not assert delivery completeness. New periods supersede pending old views,
             including Thin cadence unable to load every station before the next period.
             Old identity/socket/snapshot/page cannot restore obsolete view or cursor.
             Next attempt retains prior published view; gap/epoch invalidates it.
             Empty published period => explicit no-stations explanation. Partial overrun
             stays visibly Partial; cancellation/failure/stale lifecycle stay truthful.
             Time UTC HH:mm:ss FT8/HH:mm:ss.s FT4; DT signed one decimal seconds,
             rounded zero +0.0; Unknown when uncorrelated. All six fields remain readable.
             Existing single pending, Thin limit1/4s, caps/control priority unchanged. */
    }
    verification def LatestPeriodAndTimingVerification {
        objective latestPeriodAndTimingObjective { verify WstxRequirements::'CL-010-09'; verify WstxRequirements::'CL-007-02'; }
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

    attribute def BandActivityReadability {
        attribute viewportCssPixels : Integer;
        attribute textScale : Real = 1.0;
        attribute messageNumericFontCssPixels : Real;
        attribute timestampFontCssPixels : Real;
        attribute headerFontCssPixels : Real;
        attribute verticalCellPaddingCssPixels : Real;
        attribute longMessagesWrap : Boolean = true;
        attribute horizontalPageOverflow : Boolean = false;
        attribute numericCellsNoWrap : Boolean = true;
        attribute allSixValuesVisible : Boolean = true;
        attribute valuesInsideCells : Boolean = true;
        attribute workspaceWidthEm : Real;
        attribute bandWidthEm : Real;
        attribute bandWidthFraction : Real;
        attribute labelledRowDetails : Boolean;
        assert constraint readableCells {
            messageNumericFontCssPixels >= 16.0 * textScale and
            timestampFontCssPixels >= 16.0 * textScale and headerFontCssPixels >= 14.0 * textScale and
            verticalCellPaddingCssPixels >= 8.0 and longMessagesWrap and
            not horizontalPageOverflow and numericCellsNoWrap and allSixValuesVisible and
            valuesInsideCells and
            (workspaceWidthEm <= 75.0 or (bandWidthFraction >= 0.55 and bandWidthFraction <= 0.60)) and
            (bandWidthEm > 44.0 or labelledRowDetails)
        }
        doc /* contract 4.7.1 and TC007002: 360CSSpx retains the same minima and wraps
             long messages without horizontal page scrolling. Desktop cards use2.2:1:0.8; bandWidthFraction measures allocated card widths excluding gaps/padding;
             workspace<=75em gives Band Activity full width above secondary cards,
             <=48em stacks all cards. Band table<=44em uses all-six-labelled row details,
             <=23em single column, otherwise two columns with Message spanning the row.
             Numeric/time/status cells use ch minimum widths and nowrap; Message uses
             remaining width and word wrapping with emergency token breaks only as needed.
             Time is UTC period and signed relative DT under4.7.4; uncorrelated timing is Unknown.
             Normal text16px, labels14px, rem scaled; frequency3499.9 stays unbroken.
             Preserve accessible table headers and all values; no hiding/clipping/overlap.
             Presentation changes
             no result fields, ordering/filtering, requests, capabilities or state. */
    }

    attribute def SplitGeometry {
        attribute signalAboveWorkspace : Boolean = true;
        attribute lowerWorkspaceScrollable : Boolean = true;
        attribute horizontalPageOverflow : Boolean = false;
        attribute minimumSignalPixels : Integer = 160;
        attribute minimumWorkspacePixels : Integer = 200;
        doc /* Signal then keyboard/mouse separator then operating workspace, within
             the same page under the station bar. ArrowUp/Down change height16CSSpx;
             Home chooses the minimum, End maximum with workspace retained.
             ARIA min/max/current follow the clamped actual signal height.
             360CSSpx and 200% zoom stack lower panes; text remains reachable.
             Existing 0..3000Hz, palette, optional 1:5 curve/waterfall (#54) and native bin contracts
             are unchanged. Secondary in-page disclosures reuse existing forms,
             preserve login and never obscure the station bar or disabled Halt Tx. */
    }

    verification def operatingLayout002 {
        objective {
            verify WstxRequirements::'CL-010-05';
            verify WstxRequirements::'CL-010-07';
            verify WstxRequirements::'CL-010-08';
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
            verify WstxRequirements::'CL-010-05';
            verify WstxRequirements::'CL-010-07';
            verify WstxRequirements::'CL-010-08';
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
    dependency livePresentationCase from livePresentation004 to WstxRequirements::'TC-009-004';
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
             restoring opener focus. Escape never closes a region: it is Halt Tx plus
             contact cancellation (WstxContact::HaltTx, CL-010-03, #10 decision 5),
             replacing the earlier Escape-closes-region behaviour; existing TC-007-002
             tests asserting Escape-to-close must be updated with that implementation.
             No radio/QSO/strategy mutation or settings autosave from navigation. */
    }
    verification agreedDesignPresentation {
        subject design : AgreedOperatingDesign;
        objective {
            verify WstxRequirements::'CL-010-05';
            verify WstxRequirements::'CL-010-07';
            verify WstxRequirements::'CL-010-08';
        }
        doc /* TC007002: actual browser/server at360/720/1200/1440/1499/1500/1600;
             desktop two-pane order (#37 OperatingScreen), compact top bar, no overflow,
             typography/breakpoint/native canvas/full-space/splitter assertions,
             pointer/keyboard region routes,F2/close-control/outside-click/focus (Escape
             halts, CL-010-03), real profile/recording
             behavior and request recorder refusing invented RF/QSO/strategy work.
             Same1200x800 target/actual screenshots show design correspondence.
             Cost2 Windows isolated real server/Chromium; no radio. */
    }
    dependency agreedDesignCase from agreedDesignPresentation
        to WstxRequirements::'TC-007-002';
    attribute def ContactWorkspace {
        attribute hasStationBarHalt : Boolean = true;
        attribute hasEnableTx : Boolean = false;
        attribute hasAutoSequence : Boolean = true;
        attribute hasTune : Boolean = true;
        attribute hasDxCallGridEntry : Boolean = true;
        attribute hasStandardMessageRows : Integer = 6;
        attribute hasReportOverride : Boolean = true;
        attribute hasTx1Skip : Boolean = true;
        attribute hasTx4Toggle : Boolean = true;
        attribute hasRxTxInputs : Boolean = true;
        attribute hasHoldTx : Boolean = true;
        attribute hasPeriodChoice : Boolean = true;
        attribute hasRxFrequencyPane : Boolean = false;
        attribute hasQsoPane : Boolean = true;
        attribute hasDirectButtons : Boolean = true;
        attribute hasLogQso : Boolean = true;
        attribute hasNowButtons : Boolean = false;
        attribute hasFrequencyStepKeys : Boolean = false;
        attribute escapeClosesRegion : Boolean = false;
        attribute workspaceCardsChangeSignalArea : Boolean = false;
        assert constraint adoptedControls {
            hasStationBarHalt and not hasEnableTx and hasDirectButtons and hasAutoSequence and hasDxCallGridEntry and
            hasStandardMessageRows == 6 and hasReportOverride and hasTx1Skip and hasTx4Toggle and
            hasRxTxInputs and hasHoldTx and hasPeriodChoice and hasQsoPane and not hasRxFrequencyPane and hasLogQso and
            not hasNowButtons and not hasFrequencyStepKeys and not escapeClosesRegion and
            not workspaceCardsChangeSignalArea
        }
        doc /* #37 (operator design interview 2026-11-01) replaces the Enable Tx control,
             the Current QSO card and the Rx Frequency pane by the QSO pane (QsoPane) with
             direct buttons, and moves the Rx/Tx inputs and Hold Tx to the Rx/Tx strip
             (RxTxStrip); where the text below names those controls, QsoPane, RxTxStrip and
             WstxContact::SetEnableTx apply. Earlier text: Browser regions for WstxContact, inside the existing AgreedOperatingDesign
             order (station bar, toolbar, signal canvas, separator, band strip, cards);
             the signal area, its 0..3000 Hz span, palette, Speed/Sensitivity and split
             (CL-010-05, SplitGeometry) are unchanged.
             Station bar: Halt Tx (always visible, Alt+H, Esc; disabled with reason on a
             receive-only station, where Esc only cancels the contact) and a compact
             transmit state with the last transmitted text, Tx watchdog remaining WD:nm
             or "Tx watchdog expired", visible in every region. Radio toolbar (its period
             and level slots): UTC clock, Tx progress v/15 with Transmitting label, Rx
             level meter 0..90 dB with high/low text labels
             (WstxContact::OperatorDisplays); they are not in the station bar because the
             360 px / 200 % station bar cannot hold them without overflow (#10 review
             decision 2026-10-31).
             Waterfall: green Rx and red Tx markers labelled Rx/Tx with their Hz, pointer
             actions per WstxContact::PointerEffect; the context menu is suppressed only
             over the canvas.
             Band Activity card: existing latest-period table plus a worked-before
             label/icon column (WstxContact::WorkedBeforeQuery); row selection by click,
             Enter or double-click is SelectDecodedRow.
             Current QSO card: DX Call and DX Grid inputs with Generate (Enter); contact
             state text and partner; six message rows Tx1..Tx6, each with a Next radio and
             editable validated text, a Tx1 skip toggle on Tx1 and an RRR/RR73 toggle on
             Tx4; report input -50..+49; Rx Hz and Tx Hz inputs, Hold Tx and Tx even/odd
             choice with requested versus confirmed values; Enable Tx (Alt+N), Auto Seq,
             Tune with remaining seconds, Cancel contact, Log QSO (Alt+Q); the Rx
             Frequency pane (WstxContact::RoutesToRxFrequencyPane) with Tx-labelled own
             messages, unread count and Erase. At 360 CSS px it stacks below Band Activity
             or is a labelled tab, with no horizontal page overflow.
             Logbook region: history and ADI import/export (since #41 there is no log
             review form: WstxContact::DirectLog stores each completed contact and Log
             QSO, and an open Logbook page lists a new record when the contact snapshot
             reports it saved); opening it never hides Halt Tx.
             Alt+letter bindings apply only where the browser delivers the key; every
             action is also a focusable labelled control. Ctrl+R, Ctrl+1..6, F11/F12 and
             Now buttons are not adopted (browser reload/tab keys; #10 decision 7).
             Every control is a server request; state shows only server-confirmed
             values, pending and unknown outcomes explicitly. */
    }
    dependency contactWorkspaceClauses from ContactWorkspace to WstxRequirements::'CL-010-03';

    // ---------------------------------------------------------------- #37 operating screen
    // Operator design interview 2026-11-01 (issue #37 comments). Laptop first (minimum
    // 1366x768, mouse and keyboard); tablet adaptation is a later CR; a phone must not break.
    enum def TopBarItem {
        enum band; enum mode; enum dialFrequency; enum utcPeriod; enum exceptionChips;
        enum logbook; enum settings; enum halt;
    }
    enum def ExceptionChip {
        enum linkStale; enum catLost; enum catSetupUnconfirmed; enum audioUnavailable;
        enum audioLevelLow; enum audioLevelHigh; enum clockOff; enum receiveStopped;
        enum receiveRestarted; enum receiveOutcomeUnknown;
        enum stationUpdated; enum stationDataRejected;
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
             period progress is only the QSO pane's NEXT bar); exception chips (ExceptionChip, shown only while the
             condition holds, nothing when all is well; each names its cause, opens its
             detail in the Settings drawer, and receiveStopped offers the explicit receive
             start; stationUpdated and stationDataRejected reload the page instead,
             WstxStationProtocol::PageUpdate, #51); Logbook (full page); Settings (drawer); "?" (shortcut overview); HALT.
             HALT stays reachable by pointer too: a confirmation popup (the only popup kind)
             carries its own HALT with the same action and enabled state as the top-bar one,
             because a modal popup makes the rest of the page inert. A
             link that is connected shows no chip; the accessible status stays. There is no
             refresh control: the status refreshes itself (an explicit Refresh status is in
             Settings > Expert).
             Waterfall full width with the Rx/Tx strip (RxTxStrip) directly below it; its corner
             holds Sensitivity, Range (#54) and Waterfall speed (operative, immediate; the speed is a
             per-browser preference).
             Workspace: Band Activity (BandActivityView) on the left with the strategy
             element above it, the QSO pane (QsoPane) on the right; at most 75em wide the
             QSO pane goes below Band Activity, at most 48em everything stacks (a phone
             scrolls the workspace, never horizontally).
             Strategy element: `Strategy [name] [edit] [Highlight | Auto]` (#39,
             WstxStrategy): the name chooses the active strategy (None: none), edit opens
             the StrategyEditor popup, Highlight marks matches in Band Activity
             (HighlightView) and Auto starts or stops an Auto strategy run
             (AutoStrategyRun); beside them the WstxMcp automation run state.
             There is no Monitor and no Enable Tx control on the screen: receive follows
             the band/mode selection; transmission follows SetEnableTx (#37). The legacy
             receive start/stop is an Expert action. Status texts of a healthy station
             (CAT/audio/clock/link) are not shown; their detail is in Settings > Expert.
             Lists, frequencies and messages use a fixed-width font; colours keep the
             WSJT-X meanings (CQ, my call, own transmission, worked before). */
    }
    attribute def RxTxStrip {
        attribute stepHz : Integer = 1;
        attribute shiftStepHz : Integer = 10;
        attribute hasHoldTx : Boolean = true;
        attribute hasTxFromRx : Boolean = true;
        attribute hasRxFromTx : Boolean = true;
        attribute markersDraggable : Boolean = true;
        doc /* `Rx [Hz] [-][+]  Tx [Hz] [-][+]  Hold Tx  [Tx=Rx] [Rx=Tx]` under the waterfall.
             Exact Hz can be typed; the buttons, the mouse wheel and the arrow keys step
             1 Hz, with Shift 10 Hz. Each change is one WstxContact set_frequency or
             set_hold_tx request; the fields show only server-confirmed values (a typed
             value is not shown as applied until confirmed). Waterfall pointer (#50): click Tx,
             double-click Rx and Tx (WstxContact::PointerEffect). The Rx and Tx markers are 3 px
             green (Rx) and red (Tx) lines over the full waterfall height, without text, and can be
             dragged; the release sends one set_frequency. No strip or
             pointer action enables transmission. */
    }
    enum def BandActivitySlot {
        enum mycall; enum new_continent; enum new_continent_band; enum new_cq_zone; enum new_cq_zone_band;
        enum new_itu_zone; enum new_itu_zone_band; enum new_dxcc; enum new_dxcc_band; enum new_grid;
        enum new_grid_band; enum new_call; enum new_call_band; enum lotw; enum cq;
    }
    attribute def BandActivityColours {
        attribute slots : Integer = 15;
        doc /* CL-050-02 (#50). The WSJT-X 3.3 DecodeHighlightingModel slots in its priority order
             (BandActivitySlot order, highest first) with its default on/off and colours (row
             background; dark theme as the same colour at 0.2-0.35 alpha; the Day and Night themes
             transform the whole page): mycall #ff6666 on; new_continent #ff0063 on;
             new_continent_band #ff99c2 on; new_cq_zone #ffbf00 on; new_cq_zone_band #ffe499 on;
             new_itu_zone #a6ff00 off; new_itu_zone_band #ddff99 off; new_dxcc #ff00ff on;
             new_dxcc_band #ffaaff on; new_grid #ff8000 off; new_grid_band #ffcc99 off; new_call
             #00ffff off; new_call_band #99ffff off; lotw off (no source); cq #66ff66 on. A row takes
             the highest-priority enabled slot it matches. Matches: mycall, a decoded message to the
             profile callsign; cq, a decoded message starting CQ; new_call, the worked-before status
             not_worked of the sending call; new_call_band, not_worked or worked_other_band_or_mode; every new_*
             slot also when the record carries flags.<slot> true (#55 supplies DXCC, continent and
             zone flags from cty.dat; a slot without data stays inactive). As in WSJT-X, every
             new_* slot applies only to CQ/QRZ lines, and a never-worked call matches new_call and
             new_call_band. Worked before on this band and mode has no colour. Settings > General > Display lists the slots with their
             colours; the choice is per browser (browser storage). The #39 strategy Highlight is an
             accent (a left bar and the message text), never a row background. */
    }
    attribute def BandActivityView {
        attribute newestFirst : Boolean = true;
        attribute periodDividers : Boolean = true;
        attribute columns : Integer = 7;
        attribute retainedPeriods : Integer = 2;
        attribute maximumRows : Integer = 2048;
        doc /* CL-010-09/CL-010-16. Columns UTC, dB, DT, Freq, Message, DXCC, Distance.
             The latest published period (LatestBandActivity rules unchanged) is shown
             first; only the latest even and the latest odd T/R period are shown (#37/#57,
             CL-057-03): the period it replaced follows below a divider with its period UTC
             when it has the other parity, and no older period is kept, paged or fetched; a
             same-parity successor (a skipped period) or an uncorrelated period leaves only
             the latest; a new receive identity (band/mode change, restart) clears it. Within a period the ActivityOrdering applies (column
             header click). DXCC needs the cty.dat prefix table, which the station does not
             yet provide: the column shows an explicit unavailable mark. Distance is the
             great-circle distance from the profile locator to a grid carried in the
             message, unavailable otherwise. Colours (#50, BandActivityColours) are the WSJT-X
             row backgrounds; there are no text marks; worked before (WstxContact::
             WorkedBeforeQuery) feeds only the New call slots; with Highlight on the strategy accent of
             WstxStrategy::HighlightView (matches first in their period, greyed directed
             CQs not for my continent). Pointer: click selects (SelectDecodedRow, prepares, never
             transmits); double-click replies (select, then SetEnableTx on); right-click
             opens a menu: Reply, Select, Set Rx here. Enter selects; the menu is also
             reachable with the keyboard (context-menu key / Shift+F10). */
    }
    calc def QsoPaneCrowding {
        in rowFrequencyHz : Real;
        in rxOffsetHz : Integer;
        in fromPartner : Boolean;
        return crowding : Boolean = not fromPartner and
            rowFrequencyHz >= rxOffsetHz - 50.0 and rowFrequencyHz <= rxOffsetHz + 50.0;
        doc /* Another station within +/-50 Hz of my Rx frequency in the latest period:
             shown in the QSO pane marked with a warning sign and counted in its header
             badge. Presentation only. */
    }
    attribute def QsoPane {
        attribute crowdingWindowHz : Integer = 50;
        attribute hasPartnerHeader : Boolean = true;
        attribute hasDialogue : Boolean = true;
        attribute hasNextWithCountdown : Boolean = true;
        attribute hasEnableTx : Boolean = false;
        attribute hasNowButtons : Boolean = false;
        doc /* Right pane, replacing the Rx Frequency pane and the Current QSO card. Header:
             partner call, grid, last SNR and distance; a badge counts
             crowding stations (QsoPaneCrowding). Dialogue: the station's transmitted
             messages (sent) and the rows routed by WstxContact::RoutesToRxFrequencyPane
             (received), newest last; crowding rows marked; a call to my callsign from
             another station during a QSO highlighted. "Next" shows the next message with
             a progress bar and countdown to the next period of the contact's parity.
             Direct buttons: CQ, Reply, RR73, 73, Tune, HALT, Log QSO (SetEnableTx (#37);
             Log QSO logs the contact now, WstxContact::DirectLog (#41), and the pane
             shows the latest log outcome: logged, or not logged with its error).
             Always visible: partner header, dialogue, Next/Last with progress, direct buttons.
             A fold-out shows the DX Call/Grid entry with Generate, Erase (dialogue), Tx1-Tx6
             with their Next choice and editable text, Skip Tx1, RRR/RR73, report, Tx period
             and Auto Seq in place. On a station without
             transmit capability the transmit buttons are disabled with the reason. */
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
             General: station (display name, callsign, locator, continent), clock/NTP
             state, display (theme Day/Dark/Night and its switch, waterfall display
             preferences), access and grants (log out, forget credential), MCP/automation,
             and "Monitor off at startup" (#45 CL-045-01: read with GET /receive/startup,
             saved on change with POST /receive/startup; it acts at the next station start
             and restarts nothing, so it carries no restart mark).
             Radio (restart): CAT (control, endpoint, PTT, receive-only confirmation),
             audio (input, output, input listing, Rx level meter), transmit (Tx watchdog
             minutes and Tune seconds as WSJT-X, power is set on the transceiver).
             Logging & Reporting: the existing log (Logbook page, ADIF), the WSJT-X UDP
             interface (WstxUdp, CL-040-02): instance name and up to 16 targets, each
             address:port, enabled, multicast TTL (the hop limit of an IPv6 group) and
             interface (an interface index for an IPv6 group, with a hint that an
             interface- or link-local group needs one; WstxUdp D6), the outbound message
             selection and accept_commands (not offered for an IPv4 or IPv6 multicast
             address), with each
             target's status (active, schema, last send, error, last inbound command) and a
             standing warning that accept_commands lets that program select a QSO and edit
             Tx5 but never key the transmitter. GET /udp is read when the drawer opens (at
             most every 30 s, so routine drawer use stays inside the Thin budget), on the
             Logging tab and on Reload; Save sends one PUT /udp with expected_revision; it
             is a setting that restarts nothing (no restart mark). PSK Reporter remains a
             placeholder (later CR).
             Expert: raw CAT readback, receive job/generation, timing, the explicit receive
             start/stop, the startup resume state of #45 (resume state and last receive
             choice from GET /receive/startup), the decode window diagnostics of #52 (Save
             FT8 decode windows and the latest window's counters, CL-052-01), selection
             refresh, connection details,
             recordings/replay and the
             raw transmit test panel (WstxTransmit, #9).
             Operative changes (display, theme, watchdogs) apply immediately and never
             interrupt decoding. Restart changes (the saved profile: station, CAT, audio,
             PTT) take effect only on Apply (the existing revision-aware profile save) and,
             while a QSO is active or the station transmits, only after a confirmation. */
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
    action def KeyboardShortcuts {
        doc /* WSJT-X keys 1:1 where the function exists: Esc and Alt+H halt (Esc also
             cancels the contact, WstxContact::HaltTx); F1/F3/F5 and "?" open the overview;
             F2 Settings; F4 clears the DX call (contact cancel); Alt+1..Alt+6 choose the
             next message Tx1-Tx6 (no Now buttons); Alt+M receive start/stop; Alt+T Tune;
             Alt+Q Log QSO; F11/F12 Rx -/+1 Hz; Shift+F11/F12 Tx -/+60 Hz FT8 (90 Hz FT4);
             Ctrl+F11/F12 Rx and Tx -/+1 Hz. Letter and "?" keys are inactive while a text
             field has focus; Esc and Alt+H always act. Alt+N (Enable Tx) has no function. */
    }
    verification def operatingScreen009 {
        objective { verify WstxRequirements::'CL-010-16'; }
        doc /* TC-007-009 cost2 isolated real server and Chromium. */
    }
    dependency operatingScreenCase from operatingScreen009 to WstxRequirements::'TC-007-009';
    doc /* contract 4.7.5/12.8.1 coordinated operating selection is modeled by
         WstxOperatingReceive. This companion retains the unchanged legacy strict
         receive/radio/result shapes and owner/cancellation/source contracts.
         New selection uses the same authority, explicit actual release before
         setters/new capture and a fresh context, not a second pipeline or actor. */
}
