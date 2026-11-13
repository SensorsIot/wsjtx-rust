package WstxSignalArea {
    private import ScalarValues::*;
    attribute def DisplayLevels {
        attribute blackDbfs : Integer = -85;
        attribute rangeDb : Integer = 50;
        attribute sensitivityDb : Integer = 0;
        attribute speedMultiplier : Real = 1;
        attribute flatten : Boolean = false;
        attribute spectrumLine : Boolean = false;
        assert constraint localSliders { sensitivityDb >= -30 and sensitivityDb <= 30 and speedMultiplier >= 0.5 and speedMultiplier <= 8 }
        assert constraint displayRange { rangeDb >= 10 and rangeDb <= 80 and blackDbfs == -85 }
        doc /* #54 (CL-054-02), as WSJT-X's Wide Graph: a fixed dBFS-to-colour mapping; no level
             follows the signal over time and nothing resets it on a new job, source or profile.
             B is the fixed reference -85 dBFS. Sensitivity g (WSJT-X Zero, -30..+30, default 0)
             moves the scale: effective black E=clamp(B-g,-120,-R). Range R (WSJT-X Gain, a slider
             10..80 dB, default 50) is the span [E,E+R]. Speed sets 10*speedMultiplier CSS px per
             source second (default 1: about two FT8 periods in the default height); fixed source
             intervals move down independent of history length, clip at bottom; unobserved pixels
             dark/no-measurement. Sensitivity, Range, Speed, Flatten and the spectrum line are
             per-browser settings that apply at once and persist in browser storage. Flatten
             (default off, WSJT-X flat4 equivalent) subtracts per row the lower envelope across
             frequency (20th percentile of 32 blocks, linearly interpolated) and adds back its
             median: it evens out the passband shape, never a level change over time; the readout
             keeps the original native levels. Original calibrated levels unchanged.
             Rounding, exact RGB palette, ruler/readout/geometry and all actions
             remain normative in PresentStation/CalculateSpectrum source contract. */
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
    attribute def RxTxStrip {
        attribute stepHz : Integer = 1;
        attribute shiftStepHz : Integer = 10;
        attribute hasHoldTx : Boolean = true;
        attribute hasTxFromRx : Boolean = true;
        attribute hasRxFromTx : Boolean = true;
        attribute markersDraggable : Boolean = true;
        attribute hasSwrValue : Boolean = true;
        attribute swrRedAboveX10 : Integer = 20;
        doc /* `Rx [Hz] [-][+]  Tx [Hz] [-][+]  [Tx=Rx] [Rx=Tx]  SWR x.x` under the waterfall
             (SWR x.x since #68, CL-068-01: the last pushed radio.tx_level SWR, hidden without
             one, red above swrRedAboveX10 = 20, i.e. 2.1 and up, display only); Hold Tx
             (hasHoldTx) is in the ControlPanel below the QSO pane since #37 (operator
             2026-11-03); the frequencies themselves stay here.
             Exact Hz can be typed; the buttons, the mouse wheel and the arrow keys step
             1 Hz, with Shift 10 Hz. Each change is one WstxContact set_frequency or
             set_hold_tx request; the fields show only server-confirmed values (a typed
             value is not shown as applied until confirmed). Waterfall pointer (#50): click Tx,
             double-click Rx and Tx (WstxContact::PointerEffect). The Rx and Tx markers are 3 px
             green (Rx) and red (Tx) lines over the full waterfall height, without text, and can be
             dragged; the release sends one set_frequency. No strip or
             pointer action enables transmission.
             Frequency mapping (#50, CL-050-07): the waterfall canvas's own box carries the fixed
             0..3000 Hz span, 0 Hz at its left edge and 3000 Hz at its right edge (the time ruler
             beside it is outside the span). The pointer frequency, the Rx and Tx lines, their
             brackets and the frequency axis ticks all use this one mapping, so a line and an
             axis tick of a frequency lie within 1 px of the pointer position that selects it, at
             every width, display option and devicePixelRatio. Each line marks the signal's
             lowest tone and carries a WSJT-X bracket (goalpost) of the line's colour at the top
             of the waterfall over the occupied width to its right: FT8 8 x 6.25 = 50 Hz, FT4
             4 x 20.833 = 83.3 Hz, following the station's operating mode (station.tick period,
             15 s FT8, 7.5 s FT4). The bracket takes no pointer input. */
    }
    attribute def FreeTxSlotMarks {
        attribute marksTakePointer : Boolean = false;
        attribute alwaysShown : Boolean = true;
        attribute hasLabels : Boolean = false;
        attribute barHeightPx : Integer = 8;
        attribute endInsetPx : Integer = 2;
        attribute minColourDifference : Integer = 40;
        assert constraint marksRules { not marksTakePointer and alwaysShown and not hasLabels }
        doc /* CL-065-02 (#65, operator 2026-11-08: "show it above the waterfall as
             visually that I can place the TX frequency according to that"; #82, operator
             2026-11-09: "open slots are shown all the time as a part of the waterfall", "we
             just want to mark open slots, nothing else on screen"; WstxStrategy D18). Part of
             the waterfall, with no setting (#82 removes the Settings > Expert checkbox "Show
             free Tx slots"; its browser storage key is no longer read): on every page with
             the waterfall, each open range [lo_hz, hi_hz) of the latest held free_tx_slots
             (WstxStrategy::FreeTxSlots) is a bar in the frequency ruler directly above the
             waterfall over lo to hi, on the waterfall's one frequency mapping (RxTxStrip,
             CL-050-07), with or without a run, a QSO or Auto (no run_id match). The held
             value: each free_tx_slots.state replaces it in socket order; a GET /automation
             reply (read only after automation.state, #74) replaces it only with a value whose
             at_utc_ms is later than the held one's (its null or an older value never does); a
             new boot and switching the page's display to Off drop it (#74, #82). No other request or poll; an Off peer has no waterfall
             and receives no value.
             Look (#76, operator 2026-11-08: "shorten the mark a bit so that it has a space
             in between two adjacent ones", "in green and a little bit thicker", "We do not
             need any text on the open slots, just the sign"): each bar is barHeightPx (8)
             CSS px high at the bottom of the ruler and is shortened by endInsetPx (2) CSS px
             at each end, from x(lo) + 2 to x(hi) - 2 (edges within 1 px), so two touching
             ranges (FT8 [2110, 2160) and [2160, 2210)) show a gap of 4 px; where a range is
             narrower than both insets (a phone) the bar may vanish. The marks
             carry no text (hasLabels false: no rank, no rise, no number). The colour is one pale green in
             the base (dark) theme that the Day and Night themes remap like the rest of the
             page; as drawn, in each theme a bar's pixel differs from the drawn Rx line's,
             the Tx line's and the ruler background's by at least minColourDifference (40)
             in the sum of the R, G and B differences. Bars take no pointer input (click,
             double-click and marker drag act as without them); the Rx and Tx lines are
             unchanged; the marks fit inside the ruler and never move the waterfall.
             They are redrawn on every new held value (every period) and go when the value is
             null, when open is [] and at a new boot. No horizontal overflow at 360 px. Auto's
             ranking and the chosen slot are not drawn (the Tx line shows where Tx is). */
    }
    dependency freeTxSlotMarksClause from FreeTxSlotMarks to WstxOperatingLayout::'CL-065-02';
    dependency freeTxSlotMarksMapping from FreeTxSlotMarks to RxTxStrip;
    dependency rxTxStripSwrClause from RxTxStrip to WstxOperatingLayout::'CL-068-01';
    enum def ReceiveMode { enum spectrum; enum ft4; enum ft8; }
    enum def ReceiveState { enum stopped; enum running; enum cancelling; enum failed; }
    enum def MutationState { enum idle; enum pending; enum outcomeUnknown; }
    enum def ReceiveIntent { enum monitor; enum stop; enum chooseNextMode; }
    enum def ExistingOperation { enum none; enum start; enum stop; }
    calc def MapToolbarIntent {
        in intent : ReceiveIntent;
        in current : ReceiveState;
        in mutation : MutationState;
        in receiveCapability : Boolean;
        in currentContextValidated : Boolean;
        in previousOwnershipReleased : Boolean;
        return operation : ExistingOperation =
            if not receiveCapability or not currentContextValidated or mutation != MutationState::idle ? ExistingOperation::none else
            if intent == ReceiveIntent::chooseNextMode ? ExistingOperation::none else
            if intent == ReceiveIntent::stop and current == ReceiveState::running ? ExistingOperation::stop else
            if intent == ReceiveIntent::monitor and current == ReceiveState::running ? ExistingOperation::stop else
            if intent == ReceiveIntent::monitor and previousOwnershipReleased and (current == ReceiveState::stopped or current == ReceiveState::failed) ? ExistingOperation::start else
            ExistingOperation::none;
        doc /* contract 4.7.51/2/3/4/6. Existing server guards still decide admission; none does
             not claim success. Observed Monitor-off and Stop share receive-only stopped indications
             and retained texts; Receiving may remain green transitionally. Hidden
             loop/wait/TX effects and native release are unobserved. Abstract stopped
             maps absent/completed/cancelled job. Failed job does not prove ownership
             released. previousOwnershipReleased is confirmed prior-owner release;
             currentContextValidated includes validated current station/profile/boot
             snapshot even if job absent. No first/stale snapshot request permitted. No PTT, disarm, QSO cancellation or CAT. */
    }
    attribute def ReceivePresentation {
        attribute activeMode : ReceiveMode;
        attribute nextMode : ReceiveMode;
        attribute receive : ReceiveState;
        attribute mutation : MutationState;
        attribute currentTupleValidated : Boolean;
        attribute canMutate : Boolean;
        assert constraint mutationAuthority {
            canMutate implies (currentTupleValidated and mutation == MutationState::idle and receive != ReceiveState::cancelling)
        }
        doc /* Existing profile/boot/source/job/generation and revision are retained,
             not replaced with a new ownership scheme. Next selection starts no device
             and never changes activeMode. Active mode and running/released state come
             from authoritative receive snapshot. Partial results remain explicit. */
    }
    enum def MutationEvent {
        enum submitted; enum confirmed; enum rejected; enum responseLost;
        enum laterAuthoritativeReconciliation;
    }
    state def ExistingMutationBarrier {
        attribute acceptedEvent : MutationEvent;
        entry; then idle;
        state idle; state pending; state outcomeUnknown;
        transition submit first idle if acceptedEvent == MutationEvent::submitted then pending;
        transition complete first pending if acceptedEvent == MutationEvent::confirmed or acceptedEvent == MutationEvent::rejected then idle;
        transition uncertain first pending if acceptedEvent == MutationEvent::responseLost then outcomeUnknown;
        transition reconcile first outcomeUnknown if acceptedEvent == MutationEvent::laterAuthoritativeReconciliation then idle;
        doc /* contract 4.7.54. Old/pre-intent reads never emit laterAuthoritativeReconciliation.
             This names the legacy Start/Stop browser barrier only; coordinated selection
             uses MayClearUnknown and explicit12.8.1 fencing; it adds no mutation queue/retry.
             Reconciliation determines real state, not automatic desired success. */
    }
    action def StartWithExistingReceiveAPI {
        in nextMode : ReceiveMode;
        doc /* contract 4.7.51/3: POST /receive/start with unchanged contract 12.8 exact shape,
             saved input/current revision/current context. One receive owner and
             actual decoder; no audio selection fallback or radio command. */
    }
    action def StopWithExistingReceiveAPI {
        doc /* contract 4.7.52/5: exact current-job Stop, publication invalid before ACK;
             existing cancellation/release bounds and failure ownership preserved.
             Verified partial results remain; stale callbacks cannot publish. */
    }
}
