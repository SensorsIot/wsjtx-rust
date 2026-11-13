package WstxLowerPanel {
    private import ScalarValues::*;
    attribute def LowerPanel {
        attribute verticalStack : Boolean = true;
        attribute sameWidthAsQsoPane : Boolean = true;
        attribute hasControlPanel : Boolean = true;
        attribute hasErrorField : Boolean = true;
        attribute hasMessagesPanel : Boolean = false;
        attribute hasFrequencies : Boolean = false;
        attribute hasLevelMeter : Boolean = false;
        assert constraint lowerPanelRules {
            verticalStack and sameWidthAsQsoPane and hasControlPanel and hasErrorField and
            not hasMessagesPanel and not hasFrequencies and not hasLevelMeter
        }
        doc /* CL-037-01 (#37, operator 2026-11-03, "the space freed below the compact QSO pane,
             after the WSJT-X lower panel", narrowed the same morning: "We do not need to see
             Tx1 to Tx6. Just the control stuff and the error field messages."). The right
             column of the workspace is one vertical stack at every width (side by side, at
             most 75em and at most 48em alike): the QsoPane on top, the ControlPanel below it
             and the ErrorField below that. Each block has exactly the left and right edges of
             the QSO pane card (full-width blocks). Tx1-Tx6 stay in the QSO pane fold-out (no
             Messages panel). Rx/Tx frequency and dial frequency stay under the waterfall
             (RxTxStrip) and in the top bar, and the input level is no meter here: it appears
             only as an ErrorField entry when wrong. The whole stack stays within the fixed
             1366x768 screen (TC-007-009, TC-037-003) with the fixed-height QSO pane (QsoPane
             item 8, 12 dialogue rows). To leave room for the stack, the default signal height
             (SplitGeometry, before the operator drags the separator) is 330 px or, when less,
             the available height minus 490 px (#37 2026-11-04, was 400 px; never below the
             signal minimum): unchanged at 1920x1080, the signal minimum (about 200 px) at
             1366x768. */
    }
    attribute def ControlPanel {
        doc /* CL-037-01. Always visible below the QSO pane, no fold-out: DX Call and DX Grid with
             Generate (Enter), Report (dB, -50..+49), Auto Seq, Call 1st, Hold Tx and the Tx
             period Even / 1st or Odd / 2nd. These are the existing controls, moved: each
             sends the same single WstxContact request as before (enter_dx, set_report,
             set_auto_seq, set_call_first, set_hold_tx, set_parity) and shows only the
             server-confirmed value. They are laid out across the full width of the block in
             rows (wrapping at narrow widths), not as one narrow column. */
    }
    attribute def ErrorField {
        attribute hasHistory : Boolean = false;
        attribute hasAcknowledge : Boolean = false;
        attribute showsSince : Boolean = true;
        assert constraint currentOnly { not hasHistory and not hasAcknowledge and showsSince }
        doc /* CL-037-02 (#37, operator 2026-11-03, with the correction "NO history"). A small
             block at the bottom of the right column, below the ControlPanel, that lists only
             problems that still apply and need the operator to act (ErrorFieldEntry), each
             naming the cause and "since HH:MM" (UTC, when this page first saw the condition
             hold), on one line where it fits. An entry appears while its condition holds and disappears by
             itself when it clears; there is no acknowledge control and no list of past
             problems. A click on an entry opens its detail in the Settings drawer;
             receiveStopped offers the explicit receive start; stationUpdated and
             stationDataRejected reload the page (WstxOperatingLayout::PageUpdate, #51).
             Entries and their conditions:
             linkStale "Station connection lost · reconnecting", while the link of a retained
             authorization is not connected (then no other entry is derived, its data being
             stale); catLost / catSetupUnconfirmed, the CAT status not ready or not
             commissioned; audioUnavailable, the audio input unavailable, and "No audio input"
             without a configured input; audioLevelLow / audioLevelHigh, the input level too
             low or overdriven while receive runs; clockOff (Tx blocked), pcClockOff,
             ntpUnreachable, stationsOff, audioClockUncorrelated and audioClockDrift (warn,
             every profile, from clock.state, #92), as CL-043-03; receiveStopped and receiveOutcomeUnknown;
             bandModeFailed, a failed or unknown band/mode change; transmitRefused "Tx refused
             · <reason>", while the contact snapshot's transmit refusal names a reason the
             operator must fix (transmit unsupported or unavailable, radio unavailable or lost,
             clock not synchronized, frequency out of range, the message not packable, PTT or
             audio failures), until the next accepted Enable Tx clears it; txAlcHigh, txPowerLow,
             txSwrHigh and txSwrFault from the radio.tx_level warnings (CL-044-14); stationUpdated and
             stationDataRejected. Informational or transient events (a refused request that is
             retried, busy, a stale revision or period, a receive restart, a completed action)
             are no entries. With no entry the block shows one muted line "No problems".
             The block is small: at most about four entry lines high and never past the screen
             where the page does not scroll, scrolling inside, a wheel notch by at most the
             visible height; the Control panel above it does not move (#37, live 2026-11-06).
             At 1366x768 about one line of it is visible; a longer entry is read by scrolling
             inside it, by its hover text or in its Settings detail. */
    }
}
