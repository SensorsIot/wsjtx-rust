// Canonical FSD slices SHA256: 6f00349a9d4ba0194aa7e0d95c3dfa4995aecc799ef5dc11ae269fa82568783e
package WstxOperatingLayout {
    private import ScalarValues::*;

    doc /* Implementation contract for the profile-mode read-only operating layout.
         Markdown authority: docs/WSTX Rust FSD.md4.7.1 and6.6 TC007002. Existing signal and
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
            selectedContactRowCount == 0 and
            not transmitEnabled and not haltEnabled and
            not autoSequenceEnabled and not logEnabled
        }
        doc /* Link transitions follow existing station.status/socket authority.
             A connected link does not imply audio/CAT/decoder/TX availability.
             Unknown frequency/mode are visible unavailable text, never defaults.
             Profile identity uses literal text, never HTML interpretation.
             With liveResultInterfaceAvailable,12.8 explicit Start/Stop and next-job
             spectrum/FT4/FT8 selection use the saved endpoint/current revision.
             Device enumeration requires an operator action; viewing settings or
             choosing a mode never opens audio. Actual12.7 records alone populate
             Band Activity using source seconds, nullable SNR and audio frequency;
             no fabricated UTC/DT, message text or resolved hash. Full source/job/
             generation/sequence binds each row; new identity clears rows, stale
             pages cannot append. At most2048 rows, explicit cursor-expiry history
             warning and partial stop/failure output; unsupported payloads display
             their status. One pending page, Thin limit1/4s and status priority
             follow12.8. RX selection/TX/log remain unsupported. TC009004 exercises
             actual verified native input through converter/manager/modem/HTTP to
             literal browser rows and stale/epoch/stop/cursor/cadence boundaries;
             TC007002 keeps the unsupported/no-input empty-view baseline. */
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
        doc /* FSD4.7.1 and TC009004. Intervening events are relative to request
             initiation. Otherwise-valid includes existing station/source/job/
             generation and wire validation rules. Rejected stale pages change
             neither lifecycle/error state nor cursors. A pre-mutation read is not
             reconciliation for a later unknown outcome; conflicting controls remain
             disabled and the explanation visible until an authoritative later read.
             Live spectrum progress requires no recorded-input job and cannot cause
             a false link failure when that independent snapshot has no job. Existing
             one-page/cadence bounds hold; no mutation is replayed. */
    }

    attribute def ReadableOperatingTypography {
        attribute normalTextRem : Real = 1.0;
        attribute secondaryTextMinimumRem : Real = 0.875;
        attribute technicalRulerMinimumRem : Real = 0.75;
        attribute dialMinimumRem : Real = 1.5;
        attribute dialMaximumRem : Real = 1.75;
        attribute textEnlargementFactor : Real = 2.0;
        attribute shrinksAtNarrowWidth : Boolean = false;
        attribute usesSharedRemTokens : Boolean = true;
        attribute reflowsVertically : Boolean = true;
        attribute horizontalPageOverflow : Boolean = false;
        attribute hidesNavigationLabels : Boolean = false;
        attribute persistentHaltReachable : Boolean = true;
        attribute changesStationAuthority : Boolean = false;
        doc /* Normal body/messages/inputs/selects/action buttons use>=1rem;
             secondary descriptions/labels/status/table/card headings use>=0.875rem.
             Only technical frequency/time/level ticks may use>=0.75rem;
             their accessible descriptions remain normal text. Dial1.5..1.75rem.
             Rem values follow browser text preference;16/14/12 are defaultCSSpx,
             product choices, not a WCAG mandated pixel minimum.
             All in-page regions retain unclipped, nonoverlapping text/controls
             at360/1200/1600and200percent text enlargement. Vertical scroll/reflow
             preserves keyboard navigation, unsaved forms and Halt position.
             Agreed shell, native0..3000Hz waterfall/colors/sliders/split remain;
             signal/control space adapts to text. No RF/config mutation. */
    }
    attribute def BandActivityReadability {
        attribute messageNumericFontRem : Real;
        attribute timestampFontRem : Real;
        attribute headerFontRem : Real;
        attribute verticalCellPaddingCssPixels : Real;
        attribute longMessagesWrap : Boolean = true;
        attribute numericValuesWrap : Boolean = true;
        attribute textStaysWithinCell : Boolean = true;
        attribute horizontalPageOverflow : Boolean = false;
        assert constraint readableCells {
            messageNumericFontRem >= 1.0 and timestampFontRem >= 1.0 and
            headerFontRem >= 0.875 and verticalCellPaddingCssPixels >= 8.0 and
            longMessagesWrap and numericValuesWrap and textStaysWithinCell and
            not horizontalPageOverflow
        }
        doc /* FSD4.7.1/4.7.3 and TC007002 use shared rem typography; timestamps
             are decoded-row data, not technical ruler ticks. No narrow-size reduction
             or wide-screen font threshold. At360CSSpx/2xtext long messages and
             numeric values wrap within their cells without clipping or overlap.
             Presentation changes no result fields, ordering/filtering, requests,
             capabilities or state. ReadableOperatingTypography covers all regions. */
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
             Existing 0..3000Hz, palette, 1:5 curve/waterfall and native bin contracts
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
             At360/1200/1600CSSpx and1x/2xtext computed styles throughout all
             eight regions meet shared1rem normal/0.875rem secondary minima.
             Technical ticks alone may use0.75rem; dial1.5..1.75rem. The2xcase
             sets rootfont32CSSpx, not DPR. Decoded cells/time use1rem, headers
             0.875rem and padding8CSSpx. Long message/numeric text stays inside
             its own cell without clipping/overlap; no viewport font reduction.
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
    enum def WorkspaceCard { enum bandActivity; enum currentQso; enum strategy; }
    enum def WorkspaceRegion { enum operate; enum recordings; enum logbook; enum strategies; enum serverSettings; enum clientPreferences; enum help; }
    attribute def AgreedOperatingDesign {
        attribute designComponent : String = "465528304540209152";
        attribute designRevision : String = "465570890965458944";
        attribute defaultDesktopSignalHeightPx : Integer = 210;
        attribute minimumSignalHeightPx : Integer = 160;
        attribute hasRadioToolbar : Boolean = true;
        attribute hasBandStrip : Boolean = true;
        attribute hasPersistentHalt : Boolean = true;
        attribute usesActualStationState : Boolean = true;
        attribute substitutesPrototypeData : Boolean = false;
        attribute browserExecutesStrategy : Boolean = false;
        attribute unavailableRfActionsEnabled : Boolean = false;
        attribute unavailableStrategyActionsEnabled : Boolean = false;
        attribute serverSettingsOwnsProfileForm : Boolean = true;
        attribute clientPreferencesOwnsDisplayControls : Boolean = true;
        doc /* Desktop order: station/nav header, radio toolbar, actual signal canvas,
             keyboard/pointer separator, band strip, Band Activity / Current QSO / Strategy.
             Narrow cards stack with no page overflow. Reuse native bins0..3000Hz,
             calibrated palette, sensitivity/speed and profile/import guards unchanged.
             Unknown dial/period/level/contact/strategy state stays unknown.
             No new RF, filter/strategy execution, log or QSO service is implemented. */
    }
    action def OpenRegion {
        in region : WorkspaceRegion;
        doc /* Visible keyboard route for each region. Server settings uses actual
             revision-aware profile/connection; Client preferences uses existing
             browser display controls; Recordings uses real import/replay/cancel.
             Persistent Halt stays reachable; F2 opens server settings;
             Escape returns to operation and restores opener focus.
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
             desktop three-card order, compact header/toolbars/bands, no overflow,
             typography/reflow/native canvas/full-space/splitter assertions,
             pointer/keyboard region routes,F2/Escape/focus, real profile/recording
             behavior and request recorder refusing invented RF/QSO/strategy work.
             Same1200x800 target/actual screenshots show design correspondence.
             Cost2 Windows isolated real server/Chromium; no radio. */
    }
    dependency agreedDesignCase from agreedDesignPresentation
        to WstxRequirements::'TC-007-002';
    verification readableOperatingWorkspace {
        subject typography : ReadableOperatingTypography;
        objective {
            verify WstxRequirements::'CL-010-05';
            verify WstxRequirements::'CL-010-07';
            verify WstxRequirements::'CL-010-08';
        }
        doc /* TC007002, cost2 actual Windows server/Chromium, no radio:
             48cases: eight regions x360/1200/1600CSSpx x1x/2xroot text.
             Check normal>=1rem/secondary>=0.875rem throughout operate and every
             secondary region, including real profile/recording/display controls.
             Only technical ruler ticks may use>=0.75rem; dial1.5..1.75rem.
             At2x use32CSSpx root text and assert actual text/control bounds,
             no clipping/overlap/pageoverflow, keyboard routes/Halt reachability,
             retained unsaved state, fixed0..3000Hz waterfall and adjustable split.
             Independently supplied long-message/numeric CSS fixtures must remain
             explicitly separate from actual native source/modem row evidence.
             Capture1200default/2xtext. No invented backend results or actions. */
    }
    dependency readableOperatingCase from readableOperatingWorkspace
        to WstxRequirements::'TC-007-002';
}
