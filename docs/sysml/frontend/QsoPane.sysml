package WstxQsoPane {
    private import ScalarValues::*;
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
             WstxQsoTransmit::SetEnableTx apply. Earlier text: Browser regions for WstxContact, inside the existing AgreedOperatingDesign
             order (station bar, toolbar, signal canvas, separator, band strip, cards);
             the signal area, its 0..3000 Hz span, palette, Speed/Sensitivity and split
             (CL-010-05, SplitGeometry) are unchanged.
             Station bar: Halt Tx (always visible, Alt+H; disabled with reason on a
             receive-only station), beside it Abort QSO (Esc, WstxQsoTransmit::AbortQso,
             enabled while a contact is in progress, armed or transmitting) and a compact
             transmit state with the last transmitted text, Tx watchdog remaining calls WD:n
             (#97, #91: the Tx watchdog only; in a strategy run's own contact the run's leave label
             instead, WstxStrategy::LeaveCountLabel; a busy partner appended,
             WstxOperatingChain::BusyPartner)
             or "Tx watchdog: same message sent N times", visible in every region. Radio toolbar (its period
             and level slots): UTC clock, Tx progress v/15 with Transmitting label, Rx
             level meter 0..90 dB with high/low text labels
             (WstxQsoWire::OperatorDisplays); they are not in the station bar because the
             360 px / 200 % station bar cannot hold them without overflow (#10 review
             decision 2026-10-31).
             Waterfall: green Rx and red Tx markers labelled Rx/Tx with their Hz, pointer
             actions per WstxContact::PointerEffect; the context menu is suppressed only
             over the canvas.
             Band Activity card: existing latest-period table plus a worked-before
             label/icon column (the record's worked_status, WstxLogbook::WorkedBeforeQuery); row selection by click,
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
             Logbook region: history and ADI export (since #41 there is no log
             review form: WstxLogbook::DirectLog stores each completed contact and Log
             QSO, and an open Logbook page lists a new record when the contact snapshot
             reports it saved); opening it never hides Halt Tx.
             Alt+letter bindings apply only where the browser delivers the key; every
             action is also a focusable labelled control. Ctrl+R, Ctrl+1..6 and F11/F12
             are not adopted (browser reload/tab keys; #10 decision 7); since #37
             (operator 2026-11-03) each fold-out Tx line has Next and Now (QsoPane).
             Every control is a server request; state shows only server-confirmed
             values, pending and unknown outcomes explicitly. */
    }
    dependency contactWorkspaceClauses from ContactWorkspace to WstxContact::'CL-010-03';
    calc def QsoPaneCrowding {
        in rowFrequencyHz : Real;
        in rxOffsetHz : Integer;
        in txOffsetHz : Integer;
        in fromPartner : Boolean;
        in toMyCall : Boolean;
        return crowding : Boolean = not fromPartner and toMyCall and
            ((rowFrequencyHz >= rxOffsetHz - 50.0 and rowFrequencyHz <= rxOffsetHz + 50.0) or
             (rowFrequencyHz >= txOffsetHz - 50.0 and rowFrequencyHz <= txOffsetHz + 50.0));
        doc /* #37 (operator 2026-11-02, replacing the near-Rx rule): another station
             calling my call within +/-50 Hz of my Rx or Tx offset in the latest two
             published periods (the latest and the one before it): a ⚠ QsoPane Calling me line
             while a QSO runs. A station near my Rx that does not call me is not a QsoPane
             line (Band Activity shows it). Presentation only. */
    }
    attribute def QsoPane {
        attribute crowdingWindowHz : Integer = 50;
        attribute hasPartnerHeader : Boolean = true;
        attribute hasLastPartnerMessage : Boolean = true;
        attribute maximumOtherLines : Integer = 8;
        attribute qsoAreaRows : Integer = 12;
        attribute narrowQsoAreaRows : Integer = 6;
        attribute callingMeRows : Integer = 5;
        attribute fixedHeight : Boolean = true;
        attribute hasNextWithCountdown : Boolean = true;
        attribute hasDialogue : Boolean = true;
        attribute hasLastSentRow : Boolean = false;
        attribute hasCrowdingBadge : Boolean = false;
        attribute loggedNoticeSeconds : Integer = 8;
        attribute hasEnableTx : Boolean = false;
        attribute hasNowButtons : Boolean = true;
        attribute hasFinalMessageButtons : Boolean = false;
        assert constraint compact {
            hasPartnerHeader and hasLastPartnerMessage and maximumOtherLines == 8 and
            fixedHeight and qsoAreaRows >= 12 and callingMeRows >= 5 and
            hasNextWithCountdown and hasDialogue and not hasLastSentRow and
            not hasCrowdingBadge and not hasEnableTx and hasNowButtons and
            not hasFinalMessageButtons
        }
        doc /* Right pane, replacing the Rx Frequency pane and the Current QSO card. #37
             compact QSO pane (operator decisions 2026-11-02): it shows only the running QSO
             and nothing else, and its content takes about half the height the earlier pane
             needed. Item 8 (operator 2026-11-03 on #37, "The QSO part is way too long. It
             should be much smaller. Then we can add a lot of different things below it.",
             replacing the earlier option C where the card filled its column), revised on
             2026-11-04 (CL-037-04, live finding: at 1366x768 the dialogue rows sat in a 46 px
             area): "The QSO panel should contain all needed information for the operator. And
             it should be fixed in size that the things below it do not move all the time up
             and down. We probably have a section for the QSO and a section for who is
             calling", and "you can make this section big enough to accommodate also longer
             QSOs. We have enough space". The pane is at the top of its column and has a fixed
             height (fixedHeight): its height depends on the screen width only, never on its
             content, so the ControlPanel and the ErrorField below it (LowerPanel) never move
             when a QSO starts or ends, dialogue rows or callers are added or a line such as
             NEXT appears. From top to bottom: the header (item 1: the partner line, which
             wraps and scrolls in its own fixed line when longer, with the badge beside it; then
             the last partner message of item 2, cut to the line since the dialogue repeats
             it, the direct buttons of item 5 and the Tx1-Tx6 fold-out; at most 48em wide the
             badge follows the buttons), the message lines (item 4 NEXT first,
             then items 6, the exception status, Pounce and Auto Seq off; one fixed line, two at
             most 48em wide, scrolling inside), the QSO section
             (the #60 dialogue table, item 7: its header row and qsoAreaRows (12) rows without
             scrolling, narrowQsoAreaRows (6) when the workspace is at most 48em wide; more
             rows scroll inside, kept at the newest row; "No QSO" while no QSO runs), the
             Calling me section (item 3: its header row and callingMeRows (5) rows, scrolling
             inside; "Nobody is calling" when none). Each
             section keeps its height whether it is empty or full; the open Tx1-Tx6 fold-out
             covers both sections in place, so it moves nothing. Heights
             follow the text size (rem), so 200 % text keeps the same rows. The whole stack fits the
             1366x768 screen (TC-007-009, TC-037-003); the default split (LowerPanel) leaves
             room for it.
             A running QSO is a contact with a DX call in replying..signoff
             (WstxContact::ContactState); a contact that is completed, logged or cancelled is
             gone from the pane, which then shows idle.
             Lines (each a message and its SNR, the QSO area lines with their UTC period
             start; no DT or audio frequency, which Band Activity and the waterfall markers
             show; SNR as "+12 dB" / "−8 dB"):
             1. Header: partner call and grid; its detail line the #55 shown name and continent,
             distance from the profile locator (the approximate entity distance without a grid),
             reports sent and received; idle: "No contact selected"; while an own CQ runs
             (contact state calling) "Calling CQ" with the detail line "Tx even (1st)" or
             "Tx odd (2nd)", the Tx period, whatever the receive display shows (#37,
             operator 2026-11-02); the badge Ready, Tx on, Transmitting or Receive only (Receive only, with CQ, Tune,
             Now and Auto Seq disabled and the reason beside them, while the transmit capability
             is not available: #22, it follows the pushed contact snapshot; only a running Tune
             can be turned off).
             2. Last partner message, while a QSO runs: the contact's ContactSnapshot
             last_rcvd as one line "<text>  <SNR>" with "×N" when the identical message was
             counted N > 1 times in a row; a new text replaces it.
             3. Calling me (#37, operator 2026-11-02, its own section since 2026-11-04, formerly
             the Others rows of the QSO table): a table with the columns "Calling me" (the
             caller's call as decoded, a hashed call as "<...>"), SNR (signed), Grid (the
             grid of its message, else empty) and Country (the #55 cty.dat name of its
             record, else empty).
             One line per station, its newest decode, at most maximumOtherLines lines, oldest
             first (period, then decode order) and kept at the newest line, from the decoded
             rows of the latest two published periods that
             are addressed to my call by the Band Activity mycall rule (a standard message to
             my call or to a filled-in hash <MYCALL>, or a nonstandard i3=4 message whose 'to'
             call is mine, #24) from another station than the partner (the
             partner of the last QSO stays excluded after it ended, until another contact
             runs), on any frequency, as soon as its row is decoded (operator 2026-11-04:
             everyone addressing me except the partner). While a QSO runs a caller within
             +/-50 Hz of my Rx or Tx offset (QsoPaneCrowding) is a ⚠ line ("EA8BIA ⚠ | 0 | IL18 |
             Canary Islands"), and a double-click (or Enter) on any line switches the contact
             to that station and replies (SelectDecodedRow with replace, then SetEnableTx on;
             ChangeContact keeps Enable Tx on). When no QSO runs (idle, finished, or an own
             CQ) a double-click (or Enter) answers (select, then
             SetEnableTx on). Stations that do not call me are not listed (Band Activity
             shows them). Worked-before marks (CL-010-13, #10 2026-11-04): each line
             carries the Band Activity marks of its sender, so only stations of interest
             are coloured: the background of the highest-priority enabled new_* slot of
             its record flags (BandActivityColours, the same Settings choice; mycall is
             not used, since every line calls me), none without such a flag, so a sender
             worked before on this band and mode has no colour; its hover text (title and
             aria-description) follows the compact BandActivityHover rule (#50, operator
             2026-11-04 "too much information"): one line joined by " · ", per kind
             (continent, DXCC, zone, grid, call) only the strongest reason whose slot is
             enabled, no country, continent or distance text, "New on <band>" followed by the
             worked-before status in parentheses ("(worked on <band> <MODE>)" or "(worked on
             another band or mode)") from the worked_status of the sender's records of the
             latest and the previous period (WstxLogbook::WorkedBeforeQuery),
             e.g. "New DXCC · New call"; a line without such a reason has no hover text. The
             double-click hint is the title of the section's "Calling me" header. When no row qualifies, the section shows the muted placeholder
             "Nobody is calling" instead of an empty list, in the same height.
             4. NEXT: "▸ next: <message>" with a progress bar and the countdown to
             the next period of the contact's parity, only while Enable Tx is on and the
             contact is calling or a QSO runs. While the station reports transmitting
             (station.tick transmitting, the station's keyed state, never the browser
             clock) the line is "▶ TX now: <message>" with "<n> s left" (the time to the end
             of the waveform, audio delay plus 12.64 s FT8 / 5.04 s FT4 after the period
             start), the message being the transmit view's last_text of this period, else
             the next message; during Tune (transmit view tune) "▶ TX now: Tune" with the
             Tune seconds left (watchdog tune_remaining_seconds); otherwise "▸ next: <message>" with "Tx in <n> s" (#37,
             operator 2026-11-02). The bar (#50, operator 2026-11-02) is the
             one period bar: its width is the elapsed part of the current period
             (15 s FT8, 7.5 s FT4) on the station's clock (Contact OperatorDisplays
             StationPeriodClock), so it restarts at the period start the station keys on;
             it is red, as the waterfall Tx marker rgb(255,64,64), in a period of my Tx
             parity while Enable Tx is on and whenever the station reports transmitting,
             and green, as the Rx marker rgb(48,208,80), in every other (receive) period.
             5. Direct buttons: CQ, Auto, PSK, Tune, HALT, Abort QSO (Esc), Log QSO (#39
             strategydef, operator Q5, Q17, Q29: "Auto" right of CQ, a toggle green while on and
             grey while off, WstxAutoControl::AutoToggle; "PSK", "Use PSK Reporter" as its title,
             right of Auto, a toggle green while on, WstxStrategy::PskrUse, disabled while the
             Settings switch is off; both follow only the pushed station state). (SetEnableTx (#37). Operator
             2026-11-03 ("We have two HALT buttons ... I do not understand why we need a Reply
             and an RR73 and a 73 button there"): RR73 and 73 are gone, Auto Seq sends them
             and the fold-out Next/Now overrides by hand as in WSJT-X; Reply, kept only as the
             operator's workaround until the #50 double-click fix was installed, is gone too:
             a double-click on a Band Activity row or a Calling me row, or the row menu Reply,
             starts the reply (with the WstxStrategy::DirectedCqRule warning for a CQ not answerable);
             this HALT is the one HALT of the operating view (OperatingScreen);
             Log QSO, offered (button and Alt+Q) while a QSO runs, logs the contact now, WstxLogbook::DirectLog
             (#41), and closes it, so nothing stays queued). A command's accepted result
             line goes when the QSO ends.
             6. Log outcome: after a completion or Log QSO is stored, "✓ Logged <call>" for loggedNoticeSeconds seconds, then nothing; a contact that could not
             be stored shows "Not logged <call> · <reason>" while that outcome holds.
             7. QSO dialogue (#37, operator 2026-11-02, revising "no dialogue"): the QSO
             section (fixed height, item 8) holds the
             ContactSnapshot
             dialogue of the running QSO only, as a table (#60, operator 2026-11-03, replacing
             the earlier line and arrow formats) with the header row "UTC | Direction |
             Exchange | Rep | Rx SNR | Tx SNR", one row per entry, oldest first and newest at the
             bottom, "×N" in Rep for N > 1 repeats (empty for one), no frequency and no other
             station (the callers are the Calling me section, item 3). The section scrolls
             inside, kept at its newest row, with the header row staying visible; it is the
             header row and qsoAreaRows (12) rows high (narrowQsoAreaRows at most 48em wide,
             item 8) and shows "No QSO" while no QSO runs; it never grows the page
             (TC-007-009); at 360 CSS px the table fits the pane width and the
             titles may be abbreviated (UTC, Dir, Exch, Rep, Rx, Tx) and the Direction calls
             may wrap at their spaces.
             It is gone with the QSO (completed, logged or cancelled), as the rest of the
             QSO view, and a reload or another browser shows the same entries.
             Columns: UTC is HH:MM:SS, the UTC period start, with no ◂/▸ direction mark.
             Direction is the two calls in the Band Activity (on-air) order, the recipient
             first and the sender second, with "◂" between them pointing to the recipient
             ("HB9BLA ◂ CT1BFP": CT1BFP sends to HB9BLA; "CT1BFP ◂ HB9BLA": I send to
             CT1BFP), a hashed call as decoded ("<PJ4/K1ABC>", "<...>"); a CQ is "CQ <call>"
             or "CQ DX <call>" (the words before the grid) without an arrow, its grid in
             Exchange. Exchange is the message after the two calls ("IM59", "+08", "R-02",
             "RR73", "73"); a message that does not start with two calls or a CQ (free text)
             is all Exchange with an empty Direction. Rx SNR and Tx SNR are on every dialogue
             row, received and sent alike (operator #60, 2026-11-03: "the RX and TX dB wherever
             possible on each line, always the one from the last transmission"): Rx SNR is our
             measured SNR of the latest received dialogue entry at or before that row, signed
             ("+8", "−12", "0"); Tx SNR is the latest report the partner sent us in a received
             dialogue entry at or before that row (an Exchange "R-02" gives "−2", a plain report
             "-05" gives "−5"); each is empty only while no such value exists yet. Example
             (operator, #60): "22:51:15 | HB9BLA ◂ CT1BFP | IM59 | | +8 |",
             "22:51:30 | CT1BFP ◂ HB9BLA | +08 | | +8 |", "22:51:45 | HB9BLA ◂ CT1BFP | R-02 | | +7 | −2",
             "22:52:00 | CT1BFP ◂ HB9BLA | RR73 | | +7 | −2", "22:52:15 | HB9BLA ◂ CT1BFP | 73 | ×2 | +9 | −2".
             Sent rows keep their own colour.
             Messages between two other stations are not QSO pane lines.
             There is no LAST row, no crowding badge and no status line
             for a finished contact. A status line under the header is shown only for an
             exception: a refused transmission, a halt pending, an unknown contact state.
             Auto Seq off (#11): while Auto Seq is off during a contact or CQ, a warning
             line among the message lines reads "Auto Seq off" (title: received messages do not
             advance the QSO) with an "Auto Seq on" button; when the contact's ContactSnapshot
             suggested_slot is set, the line adds "<call> expects" and a "Send <exchange>
             next" button (e.g. "Send 73 next", the full message as its title) that chooses
             that slot and arms (Reply). It is hidden otherwise and never clipped on the
             1366x768 screen.
             PSK Reporter lines (#39 strategydef, WstxStrategy::PskrUse): while Use PSK Reporter
             is on and a strategy or contest run's own contact has a target, two lines under the
             header, in the message lines' fixed area: "Hears us: <age> ago · <rp> dB", "Hears
             us: no" or "Hears us: unknown"; and "Tx <hz> Hz · open at his end: yes", "· no" or
             "· unknown". Hidden otherwise; never clipped on the 1366x768 screen; at 360 px they
             wrap inside the pane.
             Pounce (#42 WstxStrategy::Pounce): while a pounce run is active, a line under
             the header reads "Pouncing on <call> (<band>) · waiting for CQ or 73" (in its
             contact "· in QSO") with a "Stop pounce" button that stops the run; hidden
             otherwise and never clipped on the 1366x768 screen.
             A fold-out "Messages Tx1-Tx6" shows Tx1-Tx6, each with its Next choice
             (choose_next), a Now button (#37: choose_next, then SetEnableTx on when it is
             off, so the message goes from the next own period; disabled without a message,
             without transmit capability or on a completed contact) and its editable
             text (Tx5 is editable whenever a contact exists, also without a message, for
             WSJT-X Tx5 free text, #24 S1b; the others once they have a message), Skip Tx1,
             RRR/RR73 and Cancel contact in place, and above them the Activity choice (None,
             NA VHF, EU VHF, WW Digi, ARRL Digi, Field Day, RTTY Roundup, Hound; set_activity,
             WstxSpecialActivities::GridExchangeContest, #24 S2a, EuVhfExchange, #99, HoundOperation, #24 S4b) that shows the
             station's setting, with an Exchange entry beside it (ContestExchange, #24 S2b:
             shows settings.exchange; choosing Field Day or RTTY Roundup sends set_activity
             with the entered exchange, and changing the exchange while one of them is chosen
             sends it again; the next serial is shown while RTTY uses DX or # and while EU
             VHF is chosen, which sends set_activity without an exchange and shows a refusal,
             e.g. a locator of fewer than 6 characters, in the error field); the DX
             Call/Grid entry, report, Tx period, Auto Seq, Call 1st and Hold Tx are the
             ControlPanel below the pane (#37, operator 2026-11-03). On a station without
             transmit capability the transmit
             buttons are disabled with the reason. */
    }
}
