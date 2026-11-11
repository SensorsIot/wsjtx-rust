package WstxBandActivityPane {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import ModelNotes::*;
    doc /* The Band Activity pane of the operating screen in the browser client: which decoded
         messages it shows, in which order, with which colours and marks, and what the
         operator does on a row. The pane is this product's own design; WSJT-X is a source
         only where an element names it. Where the pane stands in the workspace and the
         strategy element above it are WstxOperatingLayout::OperatingScreen; what a
         selection does in the contact engine is WstxStandardContact; the verdicts of a
         strategy and of a contest are WstxStrategy::ValueView and WstxContest::ContestView.
         Declared coverage and a verification case are not an execution result. */
    // ------------------------------------------------------------ the function and its sources
    action def ShowBandActivity {
        doc /* The function of WstxArchitecture::BrowserClient that this package describes;
             the part performs it as its action showBandActivity. It shows what the station
             publishes and sends the operator's row actions to the station as requests. It
             decodes nothing and holds no station state. Ordering, colouring, marking and
             the tip are local: they send no request and change no decoding, contact state
             or log ('CL-010-06').
             My call and my locator are the callsign and locator of the selected profile's
             settings; the band is the band of the operating selection, "this band" without
             one. The entity, flags and worked-before status of a sender are those the
             record carries (WstxContact::DecodedEntity); the pane asks for none of them.
             All its tests are the bound contract tests of the cases below; it has no detail
             tests of its own. */
        attribute implementation : String =
            "client/recording.js; client/contact.js; client/recording.css";
        in item page : WstxOfflineDecode::ResultPage[0..1] {
            doc /* Arrives on BrowserClient::station. Its records are the rows; its
                 latest_decode (WstxRadioIO::LatestDecodePeriod, also carried by the receive
                 snapshot) is the view they belong to. When the browser reads a page is
                 WstxStationProtocol::PushedStationState and 'CL-057-01'. */
        }
        in item contact : WstxContact::ContactSnapshot[0..1] {
            doc /* Arrives on BrowserClient::station. The pane takes the QSO partner from
                 the snapshot the page already holds and sends no request for it. */
        }
        attribute latest : LatestView[0..1] { doc /* Absent until a view is published. */ }
        attribute shown : ShownPeriods;
        attribute ordering : RowOrdering;
        attribute slotChoice : SlotChoice;
        attribute layout : RowLayout;
    }
    // ------------------------------------------------------------ what is shown
    attribute def LatestView {
        doc /* What the pane shows of the latest published view of the current receive.
             Its rows are all records inside the view's range of sequences and, with clock
             correlation, of its UTC period, whatever the page size and the display
             profile. A view with a higher id replaces the rows at once, also while pages
             of the earlier view are still on their way. A snapshot or a page of an earlier
             view, of another receive identity or of an earlier connection changes neither
             the rows nor the reading position.
             The status line under the heading "Band Activity" names the mode and the UTC
             period of the view, and reads "Latest decode period" without a view.
             A complete view without records shows the note "No stations decoded"; in
             every other case without a row a placeholder says why none is shown. */
        @LeftOpen { what = "the wording of the other placeholders (no decoder, receive " +
            "stopped, still loading, an empty partial view); none claims a finished decode"; }
        attribute partial : Boolean {
            doc /* The view's attempt is not complete; the status line then reads "Partial". */
        }
        attribute loading : Boolean {
            doc /* Records of the view remain to be read, whether or not the view is
                 complete; the status line then reads "Loading results". */
        }
        attribute historyIncomplete : Boolean {
            doc /* The station answered that the reading position has expired; the status
                 line then warns that the history is incomplete. */
        }
        attribute messageCount : Integer {
            doc /* The count beside the heading, as "<n> messages": the rows of the latest
                 view; in a Tx period the rows below the Tx marker. */
        }
        attribute rowsMax : Integer = 2048 {
            doc /* The station retains no more records than this for a receive
                 (WstxRadioIO::LiveResultWindow), so a view never holds more rows. */
        }
    }
    attribute def ShownPeriods {
        doc /* Which T/R periods of the current receive the pane shows, newest first: the
             latest view on top and below it the kept periods, each under a divider row
             that reads "<MODE> period <UTC> UTC". A kept period shows the rows the browser
             already holds, with the worked-before status they were read with; no earlier
             period is kept, paged or fetched. ViewChange says what each change keeps. */
        attribute keptPeriodsMax : Integer = 1 { doc /* Two after ViewChange::lossEpoch. */ }
    }
    enum def ViewChange {
        doc /* The occasions that change the shown periods. A view that only grows (the
             same id with more records or turning complete) changes nothing of them. */
        enum otherParity {
            doc /* A new view whose period has the other T/R parity than the latest: the
                 latest becomes the one kept period when it has rows; the period kept
                 before goes. */
        }
        enum sameParityOrUncorrelated {
            doc /* A skipped period, or either view without a UTC period: only the new view. */
        }
        enum txPeriod {
            doc /* The new view is a Tx period, marked by the station (latest_decode
                 transmitted, 'CL-061-04'); the browser infers none. It shows one Tx marker
                 row "Tx <UTC> · this station transmitted · no decode", the status line
                 "Tx · <MODE> period <UTC> UTC · this station transmitted, no decode" and
                 no note of an empty period. The periods below follow otherParity. */
        }
        enum afterTxPeriod {
            doc /* The view that follows a Tx period: the marker goes and the period kept
                 below it stays below the new view, whatever its parity. */
        }
        enum lossEpoch {
            doc /* An unknown-loss source epoch of the same receive ('CL-061-01'): the
                 latest and the kept period both stay, each under its divider. The first
                 view of the new identity keeps of them only the period one T/R period
                 before it. A kept row stays bound to the identity it was read under. */
        }
        enum newReceive {
            doc /* Any other change of the receive identity (band or mode change, receive
                 stop and start, another input, a station restart, another profile):
                 nothing of the earlier receive stays. */
        }
        enum pageLoad {
            doc /* Only the latest view until the next arrives; no period is fetched back. */
        }
    }
    enum def Column {
        doc /* The columns of a decoded row, left to right in this order, with the header
             labels UTC, dB, DT, Freq, Message, DXCC, Distance. A value the record lacks is
             shown as an unavailable mark, never as a default or an invented value. */
        @LeftOpen { what = "the glyph of the unavailable mark; one glyph for all columns"; }
        @Conflict { what = "header label Distance here; recording.js labels the column Dist"; }
        enum utc {
            doc /* The record's period start: HH:mm:ss in FT8, HH:mm:ss.s in FT4; "Unknown"
                 without clock correlation. */
        }
        enum dB {
            doc /* The record's signal-to-noise ratio in dB. */
            @NotStated { what = "the number form of dB (recording.js shows one decimal " +
                "and no plus sign, as -12.3)"; }
        }
        enum dt {
            doc /* The record's time offset relative to the station clock in seconds, with
                 its sign and one decimal; a value that rounds to zero reads "+0.0";
                 "Unknown" without clock correlation. Positive is late. */
            @Conflict { what = "\"Unknown\" for DT without correlation here; recording.js " +
                "activityRow shows the unavailable mark and \"Unknown\" only under UTC"; }
        }
        enum freq { doc /* The record's lowest-tone audio frequency in Hz, as 3499.9. */ }
        enum 'message' {
            doc /* The decoded text as published, as literal text; a hashed call reads as
                 the station gives it (WstxOfflineDecode::HashResolution). A record whose
                 payload is not decoded shows its status in place of a text. A record
                 decoded with an a-priori hypothesis N shows a small "aN" after the text
                 and outside it (WstxOfflineDecode::APrioriHypotheses); this is the only
                 text mark of a row. */
        }
        enum dxcc {
            doc /* The sender's entity by its shown name; the title adds continent and zones. */
        }
        enum distance {
            doc /* The great-circle distance in km from my locator to a grid carried in
                 this message; RR73 is never a grid, and a grid from another row or from
                 the log is not used. Without a grid the entity distance, marked
                 approximate as "~<n> km". */
        }
    }
    attribute def CssPx :> Real { doc /* A length in CSS pixels. */ }
    attribute def Em :> Real { doc /* A length in em of the normal text size. */ }
    attribute def Rem :> Real { doc /* A length in em of the root text size. */ }
    enum def PointerKind { enum fine; enum coarse; }
    attribute def RowLayout {
        doc /* The size and wrapping of the rows. The rules hold together for every
             viewport from viewportWidthMin up and every text scale from 1 to
             textScaleMax; a rule that depends on the pointer or on a width names it.
             - Message, numbers and time are at least normalTextMin times the text scale,
               the header labels at least headerTextMin times the text scale.
             - A numeric or time cell never wraps. The message takes the remaining width
               and wraps between words; a word is broken only when it cannot fit.
             - Every value stays visible inside its own cell, and the page never scrolls
               horizontally.
             - With a PointerKind::fine pointer a decoded row is at most rowHeightMax
               high, with cellPadding above and below the text and lineHeight; a divider
               has the same padding. With a coarse pointer a cell keeps touchPaddingMin.
             - While the pane's table is at most compactBelow wide a row is compact: no
               field labels; UTC, dB, DT, Freq and the distance on the first line, then
               the message and the entity name; it wraps only between whole fields. Then
               at least compactRowsMin rows are on screen at 360 by 800 CSS pixels, each
               at most compactRowHeightMax high. The column headers stay available to
               assistive technology.
             - While the workspace is at most fixedHeightBelow wide the pane is
               fixedHeight high and scrolls inside.
             - While the workspace shows two columns (WstxOperatingLayout::OperatingScreen)
               the pane takes between shareMin and shareMax of their width. */
        @NotStated { what = "which limit holds when the text scale makes a line of normal " +
            "text higher than rowHeightMax (16 px times 2 times 1.25 against 24 px)"; }
        attribute viewportWidthMin : CssPx = 360.0;
        attribute textScaleMax : Real = 2.0;
        attribute normalTextMin : CssPx = 16.0;
        attribute headerTextMin : CssPx = 14.0;
        attribute rowHeightMax : CssPx = 24.0;
        attribute cellPadding : CssPx = 1.0;
        attribute lineHeight : Real = 1.25 { doc /* A multiple of the text size. */ }
        attribute touchPaddingMin : CssPx = 8.0;
        attribute compactBelow : Em = 44.0;
        attribute compactRowsMin : Integer = 6;
        attribute compactRowHeightMax : CssPx = 48.0;
        attribute fixedHeightBelow : Em = 48.0;
        attribute fixedHeight : Rem = 29.0;
        attribute shareMin : Real = 0.55;
        attribute shareMax : Real = 0.60;
    }
    metadata paddingOfTheScreenCase : Conflict about RowLayout, 'TC-007-002' {
        what = "TC-007-002 and WstxOperatingLayout::operatingLayout002 expect 8 CSS px " +
            "vertical cell padding and labelled responsive rows at every width; RowLayout " +
            "gives 1 px with a fine pointer and compact rows without labels";
    }
    // ------------------------------------------------------------ order
    enum def SortField {
        doc /* What the rows of a period are ordered by, and the header that chooses it.
             The UTC and Distance headers choose nothing. */
        enum 'value' {
            doc /* Chosen by the DXCC header and by the Value control of the strategy
                 element; it has one direction. By RowValue best first, then the stronger
                 signal first with an unavailable one last, then the publication sequence
                 ascending. With a strategy or a contest active the rows with a verdict
                 keep the station's order among themselves (WstxStrategy::ValueView,
                 WstxContest::ContestView). */
        }
        enum frequency { doc /* Freq header: numeric, first ascending. */ }
        enum signalStrength { doc /* dB header: numeric, first descending. */ }
        enum dt { doc /* DT header: numeric with its sign, first ascending. */ }
        enum 'message' {
            doc /* Message header: the literal text as ASCII without regard to case, first
                 ascending. */
        }
    }
    enum def SortDirection { enum ascending; enum descending; }
    attribute def RowOrdering {
        doc /* The operator's choice of order, one for the pane. It orders the rows inside
             each shown period; the periods and the partner block keep their places.
             - A header is chosen with a pointer click, or with Enter or Space while it has
               the keyboard focus. Choosing another header orders by its field in that
               field's first direction; choosing the header of the current field reverses
               the direction, except for value.
             - A row whose key is unavailable comes last in both directions; rows with
               equal keys follow the publication sequence ascending in both directions.
             - The whole latest view is ordered again after every page that arrives.
             - The choice stays over a new period, a change of mode and a reconnect to the
               same profile. Another validated profile sets it back to value; a profile
               identity that is not valid changes nothing. */
        @NotStated { what = "where the choice is kept and whether it survives a page " +
            "reload (recording.js keeps it in the page only; a reload gives value)"; }
        @NotStated { what = "what a header announces about the current order " +
            "(recording.js sets aria-sort on the chosen header and none on the others)"; }
        attribute field : SortField = SortField::'value';
        attribute direction : SortDirection = SortDirection::ascending {
            @Conflict { what = "ascending beside field value here; recording.js starts " +
                "with descending and announces the value order as descending, which the " +
                "ordering test of TC-007-006 expects"; }
        }
    }
    enum def RowValue {
        doc /* The value of a row, best first. A row has the first value that applies. The
             flags are those of the record for its sender, whatever the kind of message
             and whether or not their colour slot is chosen. */
        enum callingMe { doc /* A decoded message to my call (ColourSlot::mycall). */ }
        enum strategyHit {
            doc /* A strategy is active and its verdict ranks the row (WstxStrategy::ValueView). */
        }
        enum newEntity { doc /* Flag new_dxcc or new_continent. */ }
        enum newEntityOnBand { doc /* Flag new_dxcc_band or new_continent_band. */ }
        enum newZone { doc /* A new CQ or ITU zone flag, ever or on this band. */ }
        enum newGrid { doc /* Flag new_grid or new_grid_band. */ }
        enum newCall { doc /* Flag new_call or new_call_band. */ }
        enum noFlag { doc /* Every other row, also one whose payload is not decoded. */ }
    }
    // ------------------------------------------------------------ colours, marks and the tip
    enum def ColourSlot {
        doc /* The colour slots in their priority, highest first, each with its colour and
             whether it is chosen by default. A row is coloured only through the chosen
             slots it matches and takes the highest of them; RowMark says what the slot
             colours. A row that matches no chosen slot has no colour, also a CQ.
             mycall matches a decoded message addressed to my call, also as a filled-in
             hash and as the 'to' call of a nonstandard message. Every new_ slot matches
             the flag of its name on the record, for the sender of every kind of message;
             the worked-before status adds no slot.
             On the dark theme a slot colours with its colour at an alpha between 0.2 and
             0.35; the Day and Night themes transform the whole page. The strategy accent
             (WstxStrategy::ValueView) is never a background and replaces no slot. With a
             contest in force WstxContest::ContestView says which slots apply. */
        @FollowsSource { reference = "WSJT-X 3.3 DecodeHighlightingModel: the slots, " +
            "their order and colours"; }
        @DiffersFromSource { what = "no CQ slot; new_call and new_call_band chosen by " +
            "default; the new_ slots apply to the sender of every message, not only to " +
            "CQ and QRZ lines, and outside those colour only the sender's call"; }
        @LeftOpen { what = "the alpha of each slot inside 0.2 to 0.35; the cases give " +
            "the values a test asserts"; }
        enum mycall { doc /* #ff6666, chosen. */ }
        enum new_continent { doc /* #ff0063, chosen. */ }
        enum new_continent_band { doc /* #ff99c2, chosen. */ }
        enum new_cq_zone { doc /* #ffbf00, chosen. */ }
        enum new_cq_zone_band { doc /* #ffe499, chosen. */ }
        enum new_itu_zone { doc /* #a6ff00, not chosen. */ }
        enum new_itu_zone_band { doc /* #ddff99, not chosen. */ }
        enum new_dxcc { doc /* #ff00ff, chosen. */ }
        enum new_dxcc_band { doc /* #ffaaff, chosen. */ }
        enum new_grid { doc /* #ff8000, not chosen. */ }
        enum new_grid_band { doc /* #ffcc99, not chosen. */ }
        enum new_call { doc /* #00ffff, chosen. */ }
        enum new_call_band { doc /* #99ffff, chosen. */ }
        enum lotw { doc /* Not chosen; no record carries its data, so it never matches. */ }
    }
    attribute def SlotChoice {
        doc /* The operator's choice of slots, made under Settings > General > Display,
             which lists every slot with its colour. It starts with the defaults of
             ColourSlot, is kept in the browser's storage and so holds for this browser
             over reloads and restarts, and applies at once to the rows shown and to
             their tips. */
        @NotStated { what = "whether anything sets the choice back, whether profiles share " +
            "it, and what an unreadable stored choice gives (recording.js: one choice per " +
            "browser, never set back; a slot without a stored value takes its default)"; }
        attribute chosen : ColourSlot[0..14];
    }
    enum def RowMark {
        doc /* The mark of a decoded row, highest first; a row takes the first that
             applies. The sender of a row is the sender call of WstxContact::DecodedEntity.
             The partner is the DX call of the contact from its preparation until it is
             logged or cancelled. */
        enum partner {
            doc /* The sender is the partner. All partner rows of the shown periods stand
                 at the top of the pane, newest period first, whatever the order chosen,
                 above one separator stripe: a row without text, 3 px high, #ff4040. A
                 partner row has a 4 px red bar at its left edge, a bold message and the
                 badge "◆ QSO" after the message and outside its text; it has no slot
                 colour, also when it is addressed to my call. A divider whose rows all
                 moved up is not shown. Without a partner there is no stripe. For the
                 order of a strategy the partner rows are a period of their own. */
        }
        enum callsMe {
            doc /* A message to my call from another sender: the whole row in the mycall
                 colour, also when the sender was worked before on this band and mode.
                 With mycall not chosen the row is a newWholeRow. */
        }
        enum newWholeRow {
            doc /* A CQ or QRZ whose sender has a chosen new_ slot: the whole row in the
                 colour of the highest such slot. */
        }
        enum newSenderOnly {
            doc /* Any other message whose sender has a chosen new_ slot: only the
                 sender's call in the message, also inside < >, carries that colour. */
        }
        enum plain { doc /* Every other row: no colour. */ }
    }
    calc def ReasonTip {
        doc /* The one-line tip of a decoded row. It names the reasons of the row's colour
             that the row does not show itself: never the entity, continent or distance
             and never that the row calls me.
             - One reason per kind, in the order continent, DXCC, zone, grid, call; of a
               kind the first of these whose slot is chosen and whose flag is set:
               "New continent <continent>", "New continent on <band>"; "New DXCC", "New
               DXCC on <band>"; "New CQ zone <n>", "New ITU zone <n>", "New CQ zone on
               <band>", "New ITU zone on <band>"; "New grid <square>", "New grid on
               <band>"; "New call", "New on <band>".
             - "New on <band>" is followed by the sender's worked-before status when it has
               one: "(worked on another band or mode)" or "(worked on <band> <MODE>)".
             - Then the verdict of the strategy or contest, when the row has one
               (WstxStrategy::ValueView, WstxContest::ContestView).
             - The parts are joined by " · ". A partner row names no flag reason. A row
               without any part has no tip; a worked-before status alone gives none.
             The tip is a box of one line, not the browser's title. It shows at the pointer
             while the pointer is over the row, except over a cell that has a title of its
             own, and under the row while the row has the keyboard focus. It goes when
             the pointer leaves, the focus moves or the row is drawn again. The same text
             is the row's accessible description. */
        in entity : WstxContact::DecodedEntity[0..1];
        in choice : SlotChoice;
        return tip : String[0..1];
    }
    metadata workedBeforeShown : Conflict about ReasonTip, 'CL-010-13' {
        what = "CL-010-13 promises the worked-before status of every decoded call by text " +
            "or icon as well as colour; ReasonTip and recording.js show it only after " +
            "\"New on <band>\", so a call worked on this band and mode shows none";
    }
    // ------------------------------------------------------------ what the operator does
    enum def RowInput {
        doc /* The operator's inputs on a decoded row and the effect of each. Every decoded
             row can take the keyboard focus. A divider, the stripe, the Tx marker and a
             placeholder take no input, and any other key or pointer action on a row does
             nothing. A row is always selected under the receive identity and sequence it
             was read with. */
        @NotStated { what = "which touch gestures select, reply and open the menu " +
            "(contact.js handles the click, the second mouse press and the browser's " +
            "context-menu event only)"; }
        enum click {
            doc /* Pointer. WstxStandardContact::SelectDecodedRow without replace: it
                 prepares a contact and never turns Enable Tx on. The first click of a
                 doubleClick selects nothing by itself.
                 - A CQ the station refuses as not answerable
                   (WstxStrategy::DirectedCqRule) shows its warning; only the operator's
                   confirmation selects it, and a declined warning sends nothing more.
                 - While a contact is active, a row that can start a contact for me (a CQ
                   or QRZ that DirectedCqRule leaves to me, or a message to my call) only
                   offers "Change contact to <sender>"; accepting it is
                   WstxStandardContact::ChangeContact and leaves Enable Tx as it is. A row
                   of a QSO between others or a CQ directed elsewhere offers nothing,
                   takes an earlier offer away and leaves no refusal text. */
        }
        enum enterKey { doc /* Keyboard, on the focused row: as click. */ }
        enum doubleClick {
            doc /* Pointer: the second press on the same row, also when the rows are drawn
                 again between the two presses or during the second. It is the operator's
                 explicit choice: SelectDecodedRow with replace, without asking, also
                 during a contact or an own CQ, then WstxStandardContact::SetEnableTx on;
                 what the engine does then is 'CL-050-04'. The DirectedCqRule warning of
                 click applies. On a row of a QSO between others the command line reads
                 "Call <sender>". A stale_revision refusal of either request is repeated
                 at most twice with the reloaded snapshot. */
            @NotStated { what = "what doubleClick and the menu's Reply do while transmit " +
                "is not available (contact.js: the double-click only selects; Reply is " +
                "disabled)"; }
        }
        enum rightClick { doc /* Pointer: opens the row menu at the pointer. */ }
        enum menuKey {
            doc /* Keyboard, on the focused row: the context-menu key or Shift+F10 opens it. */
        }
    }
    enum def RowMenuItem {
        doc /* The items of the row menu, top to bottom in this order. An item is chosen with
             the pointer or the keyboard. Escape, a press outside the menu and a chosen item
             close it; Escape then does nothing else (WstxOperatingLayout::KeyboardShortcuts). */
        enum reply { doc /* As RowInput::doubleClick. */ }
        enum select { doc /* As RowInput::click. */ }
        enum setRxHere {
            doc /* Sets only the Rx offset: the row frequency (WstxContact::FrequencyControls). */
        }
        enum pounce {
            doc /* Only for a row with a resolved sender: "Pounce <call>", or "Stop
                 pouncing <call>" while that pounce runs (WstxStrategy::Pounce). */
        }
        enum ignore {
            doc /* Only for a row with a resolved sender: "Ignore <call>", or "Stop ignoring
                 <call>" while the session list holds it (WstxStrategy::IgnoreLists). */
        }
    }
    // ------------------------------------------------------------ requirements
    requirement 'CL-010-09' {
        doc /* The browser MUST show the latest published decode period of the current
             receive with each record's period time and signed timing relative to the
             station clock, say when that view is partial, still loading or empty
             (LatestView, Column), and let the operator order its rows (RowOrdering). */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    requirement 'CL-057-03' {
        doc /* The browser MUST show only the latest period and, below a divider, the one
             period it replaced when that has the other T/R parity, and fetch no earlier
             period (ShownPeriods, ViewChange). */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js";
    }
    requirement 'CL-061-03' {
        doc /* The browser MUST show a period in which this station transmitted as the one
             Tx marker row the station's marker calls for, never as an empty period, and
             keep the receive period below it (ViewChange::txPeriod, afterTxPeriod). */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    requirement 'CL-050-02' {
        doc /* The browser MUST colour a row only through the ColourSlot it matches, in their
             priority and with their defaults, and keep the operator's SlotChoice per browser. */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "client/recording.js; client/logbook.js; client/recording.css";
    }
    requirement 'CL-050-08' {
        doc /* The browser MUST mark each decoded row by what makes it interesting, the
             QSO partner first (RowMark), and give it the one-line ReasonTip. */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "client/recording.js; client/contact.js; client/recording.css";
    }
    requirement 'CL-055-04' {
        doc /* The browser MUST treat the sender of every decoded message alike, whatever
             the kind of message: colour it by its flags (ColourSlot, RowMark), name its
             reasons on hover (ReasonTip; for a caller in the QSO pane
             WstxOperatingLayout::QsoPane) and, by default, order the rows by RowValue. */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "client/recording.js; client/contact.js; client/logbook.js";
    }
    requirement 'CL-055-05' {
        doc /* The browser MUST keep decoded rows as low as RowLayout states, so that more
             stations fit at the same text size, and keep them tappable with a coarse
             pointer and in the compact form. */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.css";
    }
    requirement 'CL-037-05' {
        doc /* While a contact is active, a click on a row MUST offer a contact change
             only for a row that can start a contact for me, naming its sender, and offer
             nothing for any other row (RowInput::click). */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "client/contact.js; client/recording.js; server/src/contact_http.rs";
    }
    requirement 'CL-037-06' {
        doc /* The browser MUST give each operator input on a decoded row the effect
             RowInput and RowMenuItem state, every effect reachable with the pointer and
             with the keyboard. */
        subject browser : WstxArchitecture::BrowserClient;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js";
    }
    satisfy 'CL-010-09' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-057-03' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-061-03' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-050-02' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-050-08' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-055-04' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-055-05' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-037-05' by WstxArchitecture::physicalStation.frontend.browsers;
    satisfy 'CL-037-06' by WstxArchitecture::physicalStation.frontend.browsers;
    dependency CL_010_09_to_FR_010 from 'CL-010-09' to 'FR-010';
    dependency CL_010_09_to_FR_019 from 'CL-010-09' to 'FR-019';
    dependency CL_057_03_to_FR_010 from 'CL-057-03' to 'FR-010';
    dependency CL_057_03_to_FR_019 from 'CL-057-03' to 'FR-019';
    dependency CL_061_03_to_FR_010 from 'CL-061-03' to 'FR-010';
    dependency CL_061_03_to_FR_019 from 'CL-061-03' to 'FR-019';
    dependency CL_050_02_to_FR_019 from 'CL-050-02' to 'FR-019';
    dependency CL_050_08_to_FR_019 from 'CL-050-08' to 'FR-019';
    dependency CL_055_04_to_FR_019 from 'CL-055-04' to 'FR-019';
    dependency CL_055_05_to_FR_019 from 'CL-055-05' to 'FR-019';
    dependency CL_037_05_to_FR_007 from 'CL-037-05' to 'FR-007';
    dependency CL_037_06_to_FR_007 from 'CL-037-06' to 'FR-007';
    dependency CL_037_06_to_FR_019 from 'CL-037-06' to 'FR-019';
    // ------------------------------------------------------------ verification cases
    verification 'TC-007-006' {
        doc /* The latest period, its timing and the order of its rows, from station to pane.
             Setup: the receive manager and its API with scripted samples, clocks and
             results (server); Chromium at 1440 by 900 with scripted receive snapshots and
             result pages, which are presentation fixtures and not decoder truth.
             (a) Server, anchor 2026-10-27T12:00:00Z at frame 0: FT8 starts at frames 3600,
                 6000 and 8400 give DT -0.2, +0.0 and +0.2 in period 12:00:00; FT4 starts
                 at 3024, 5424 and 7824 give the same, and frame 95424 gives +0.0 in
                 12:00:07.5. Without correlation period and DT are null.
             (b) Server: of a completed, an overrun, a cancelled and a failed attempt only
                 the completed one publishes a complete view; the last published view
                 stays.
             (c) A view 12:00:15 of 18 records (sequences 1 to 18; DT -0.2, +0.2, then
                 -0.01) beside a record 0 of 12:00:00, read in pages of 16: 16 rows, then
                 18, none of record 0; ordered by Freq ascending the first rows read UTC
                 "12:00:15" and DT "-0.2", "+0.2", "+0.0".
             (d) Freq descending chosen before the second page arrives: after it the first
                 row is sequence 18.
             (e) A next view 12:00:30 (id 2, not complete) whose second page is held back:
                 16 latest rows, the status line reads Partial and Loading results, and
                 the 18 rows of 12:00:15 stand below a divider naming 12:00:15 UTC.
             (f) Then an empty complete view 12:00:45 (id 3), then the held page of id 2:
                 no latest row, the note "No stations decoded", the kept rows unchanged
                 and the reading position at 37.
             (g) A page that names a newer view than the snapshot did: the records of that
                 view are read from its first sequence and none is left out.
             (h) Five records of one period, sequences 0 to 4: Freq 1000, 200, 3499.9,
                 1000, 500; dB -20, +10, none, -5, 0; DT -0.2, +0.2, 0, -0.1, +0.1; text
                 "CQ Z9ZZ JO00", "cq A1AA IO00", "CQ B1BB JN00", a payload that is not
                 decoded, " CQ SPACE JO00". At first: 1, 4, 3, 0, 2. Freq: 1, 4, 0, 3, 2,
                 again: 2, 0, 3, 4, 1. dB: 1, 4, 3, 0, 2, again: 0, 3, 4, 1, 2. DT: 0, 3,
                 2, 4, 1, again: 1, 4, 2, 3, 0. Message: 4, 1, 2, 0, 3, again: 0, 2, 1,
                 4, 3.
             (i) Message descending stays over a new period, a change to FT4 under a new
                 receive identity and a reconnect; with every DT unknown both DT
                 directions give 0, 1, 2, 3, 4; a profile identity that is no UUID keeps
                 the choice; another valid profile gives the value order; ordering sends
                 no request.
             (j) At 1440 and 360 px wide, text scale 1 and 2: no horizontal page scroll and
                 no cell whose content leaves it.
             (k) Planned, live on the station with a radio, receive only, FT8 and FT4: the
                 rows are those of the latest period with their period time and DT. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-007-02'; verify 'CL-010-09'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String =
            "tests/ui-operating.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-057-004' {
        doc /* Only the latest period and the one of the other parity.
             Setup: the station's router and Chromium with a scripted correlated FT8
             receive snapshot and results route (presentation fixtures).
             (a) Periods 12:00:00 (3 records), then 12:00:15 (2): the 12:00:15 rows on
                 top, the 12:00:00 rows below one divider.
             (b) Then 12:00:30 (2): its rows on top and the 12:00:15 rows below one
                 divider; never more than two periods.
             (c) Then 12:01:00 (1, a skipped period): only its row and no divider.
             (d) Throughout: no result is read below the first sequence of the view then
                 current; no page error. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-057-03'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    verification 'TC-061-004' {
        doc /* A Tx period shows the Tx marker and no empty period.
             Setup: as TC-057-004; no station.tick reports transmitting.
             (a) 12:00:00 with 3 records, then 12:00:15 as a Tx period (transmitted true,
                 no records): the marker row "Tx 12:00:15 · this station transmitted · no
                 decode" on top, then the divider "FT8 period 12:00:00 UTC" and the three
                 rows; the status line "Tx · FT8 period 12:00:15 UTC · this station
                 transmitted, no decode"; the count "3 messages"; neither "No stations
                 decoded" nor "No verified stations".
             (b) Then 12:00:30 with 2 records: its rows on top, the 12:00:00 rows below
                 the divider "FT8 period 12:00:00 UTC", no marker.
             (c) Then 12:00:45, a receive period without records: the note "No stations
                 decoded" and the 12:00:30 rows below their divider; no page error. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-061-03'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    verification 'TC-050-002' {
        doc /* The colour slots, their defaults and the operator's choice.
             Setup: the candidate server and Chromium. Job 1: "CQ K1ABC" (worked on this
             band and mode, no flag), "CQ W1XYZ" and "K9XX W2AB R-05" (senders with
             new_call and new_call_band) and a free-text row. Job 2: "CQ K1AA" (no flag),
             "CQ K2BB" (new_call_band), "CQ K3CC" (new_call, new_call_band) and "HB9BLA
             K1AA R-05" to my call.
             (a) No row carries a text mark; Settings lists no CQ slot.
             (b) Job 1 with the defaults: the row "CQ W1XYZ" and the call W2AB alone are
                 rgba(0,255,255,0.24); "CQ K1ABC" and the free text have no slot and
                 rgba(0,0,0,0).
             (c) New call not chosen: both are rgba(153,255,255,0.2), and the choice is in
                 the browser's storage.
             (d) Rows made with several slots: mycall wins over new_continent, and that
                 over new_dxcc; New grid and New ITU zone are not chosen at first.
             (e) Job 2: K1AA no slot and rgba(0,0,0,0); K2BB rgba(153,255,255,0.2); K3CC
                 rgba(0,255,255,0.24); the row to my call mycall only,
                 rgba(255,102,102,0.32). */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-050-02'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    verification 'TC-050-008' {
        doc /* The row marks, the partner block and the reason tip.
             Setup: the fixture station and Chromium at 1440 by 900; band 40m. Kept period
             12:00:00: "CQ K1PT FN42" (new_call_band), "CQ K7OLD FN42", "K9XX W1AA R-03".
             Latest period 12:00:15: "HB9BLA K1PT FN42" (new_call_band), "HB9BLA K2CM
             -05", "HB9BLA K3NB R-07" (new_call_band), "CQ OA4DX FH17" and "K9XX YO3ABC
             -07" (both new_dxcc, new_dxcc_band, new_call, new_call_band; Peru, Romania),
             "CQ K1WB FN42", "W9AA W2CD 73", "CQ JA1ZZ PM95" (new_cq_zone,
             new_cq_zone_band, CQ zone 25). K2CM, K1WB and W2CD are worked on 40m FT8,
             K3NB on another band or mode, the others not.
             (a) No contact: no stripe. The three rows to my call are whole rows of
                 rgba(255,102,102,0.32) with the tips "New on 40m", none, and "New on 40m
                 (worked on another band or mode)".
             (b) "CQ OA4DX FH17": whole row rgba(255,0,255,0.26), tip "New DXCC · New
                 call". "K9XX YO3ABC -07": only YO3ABC in that colour, the message cell
                 transparent, the same tip. "CQ JA1ZZ PM95": whole row
                 rgba(255,191,0,0.26), tip "New CQ zone 25". The rows without a flag: no
                 colour and no tip.
             (c) No row has a title; each accessible description equals the tip. The tip
                 is one line at the pointer over the YO3ABC message, absent over its DXCC
                 cell and over an uncoloured row, shown for the focused K3NB row and gone
                 when the focus moves.
             (d) A contact with K1PT in replying: "HB9BLA K1PT FN42", then "CQ K1PT FN42",
                 then one stripe row without text of rgb(255,64,64), then the other rows
                 as before with the kept divider. The partner rows have no slot colour and
                 no tip, a 4 px bar of rgb(255,64,64) at the left, a bold message and the
                 badge " ◆ QSO". At 360 by 800 the stripe is 3 px high and as wide as the
                 pane. After ordering by Freq the partner rows are still first.
             (e) mycall and new_call not chosen: K2CM no colour; K3NB a whole row of
                 rgba(153,255,255,0.2); the OA4DX and YO3ABC tips "New DXCC · New on 40m".
             (f) The contact completed: no stripe and no partner row; "HB9BLA K1PT FN42"
                 is a callsMe row.
             (g) Band 20m: a row with the tip "New on 20m (worked on another band or
                 mode)" keeps it when the next period moves it below the divider, while
                 that period is partial and when it is complete.
             (h) Throughout: no worked-before query is sent; no page error. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-050-08'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "tests/ui-operating.test.cjs; tests/receive-page.test.cjs";
    }
    verification 'TC-055-006' {
        doc /* Every sender is coloured, named in the tip and ordered by value.
             Setup: the station's router with a profile whose log holds DL1ABC JO62 on
             20m FT8; Chromium at 1440 by 900 with one period 12:00:15 of scripted records,
             band 20m, a strategy "Hover test" whose verdict ranks "W9AA W2CD 73" first.
             (a) Server, /receive/results: the sender of "K9XX G4XYZ -10" has England with
                 the new call, DXCC and ITU zone flags; of "K9XX YO3ABC R-07" Romania with
                 new DXCC; of "K9XX DL1ABC RR73" Germany and no flag.
             (b) Browser, the rows from top to bottom: "HB9BLA W1XYZ -12" (new_call), whole
                 row rgba(255,102,102,0.32), tip "New call"; "W9AA W2CD 73", no colour,
                 tip "Strategy Hover test: #1"; "K9XX YO3ABC -07" (new_dxcc, new_call),
                 only YO3ABC rgba(255,0,255,0.26), tip "New DXCC · New call"; "CQ JA1AAA
                 PM95" (new_cq_zone, zone 25), whole row rgba(255,191,0,0.26), tip "New CQ
                 zone 25"; "CQ G4XYZ IO91" (new_grid), no colour, no tip; "K1ZZ W3EF RR73"
                 (-4 dB) then "K9XX W2AB R-05" (-20 dB), both new_call, only the sender
                 rgba(0,255,255,0.24), tip "New call"; "FREE TEXT"; "CQ K1ABC FN42"
                 (worked, no flag), no colour, no tip.
             (c) Each accessible description equals the tip.
             (d) New grid chosen in Settings: the G4XYZ row is rgba(255,128,0,0.26) with
                 the tip "New grid IO91".
             (e) The Freq header orders by frequency ascending; the DXCC header gives the
                 order of (b) again. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-055-04'; verify 'CL-055-02'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "server/src/dxcc_tests.rs; tests/ui-operating.test.cjs";
    }
    verification 'TC-055-007' {
        doc /* Low rows at the same text size.
             Setup: Chromium at 1366 by 768 with a fine pointer and one period of 30
             records.
             (a) A decoded row is at most 24 px high.
             (b) The text size of a row is that of normal operating text.
             (c) At least 8 rows are fully visible in the table.
             (d) The style rule for a coarse pointer gives a cell at least 8 px padding
                 above and below. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-055-05'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    verification 'TC-037-004' {
        doc /* A contact change is offered only for a row that can start a contact for me.
             Setup: the candidate server and Chromium at 1366 by 768; my continent EU;
             rows "CQ K1ABC FN42", "QRZ W1XYZ FN31", "HB9BLA DL1ABC JO31", "W4WFC DL1FRH
             JO30", "CQ EU G4ABC IO91", "CQ DX K2DX FN42" (North America), "CQ NA K3NA
             FN42" and "CQ DX DL2DX JO31" (Europe); a running contact with IW9FRA; a
             scripted command route that refuses select_row without replace as
             directive_not_answerable for the last two rows and as contact_active for the
             others, and accepts everything else.
             (a) A click on each of the rows of K1ABC, W1XYZ, DL1ABC, G4ABC and K2DX
                 offers "Change contact to" with that call.
             (b) A click on "W4WFC DL1FRH JO30" and on each of the last two rows takes the
                 offer away, shows none and leaves the command line empty.
             (c) A double-click on "W4WFC DL1FRH JO30" sends select_row with replace true,
                 then enable_tx, and the command line reads "Call DL1FRH: accepted". */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-037-05'; verify 'CL-037-06'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    verification 'TC-037-005' {
        doc /* The keyboard inputs on a row. The pointer inputs and the menu items are
             shown by TC-007-009, the double-click by TC-037-004.
             Setup: the candidate server and Chromium with scripted decoded rows; contact
             commands are recorded.
             (a) Enter on the focused row "CQ K1ABC FN42" sends one select_row with
                 exactly the row's source, job, generation and sequence, and no enable_tx.
             (b) Planned: the context-menu key and Shift+F10 on a focused row open the
                 menu at that row with the items Reply, Select, Set Rx here, Pounce and
                 Ignore in this order.
             (c) Planned: Escape with the menu open closes it, sends no command and leaves
                 a running contact as it is. */
        subject browser : WstxArchitecture::BrowserClient;
        objective { verify 'CL-037-06'; }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio";
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String =
            "tests/contact.test.cjs::TC-007-003 QSO pane candidates and TC-007-001 selection without transmit";
    }
    dependency CL_010_09_verified_by_TC_007_006 from 'CL-010-09' to 'TC-007-006';
    dependency CL_057_03_verified_by_TC_057_004 from 'CL-057-03' to 'TC-057-004';
    dependency CL_061_03_verified_by_TC_061_004 from 'CL-061-03' to 'TC-061-004';
    dependency CL_050_02_verified_by_TC_050_002 from 'CL-050-02' to 'TC-050-002';
    dependency CL_050_08_verified_by_TC_050_008 from 'CL-050-08' to 'TC-050-008';
    dependency CL_055_04_verified_by_TC_055_006 from 'CL-055-04' to 'TC-055-006';
    dependency CL_055_02_verified_by_TC_055_006 from 'CL-055-02' to 'TC-055-006';
    dependency CL_055_05_verified_by_TC_055_007 from 'CL-055-05' to 'TC-055-007';
    dependency CL_037_05_verified_by_TC_037_004 from 'CL-037-05' to 'TC-037-004';
    dependency CL_037_06_verified_by_TC_037_004 from 'CL-037-06' to 'TC-037-004';
    dependency CL_037_06_verified_by_TC_037_005 from 'CL-037-06' to 'TC-037-005';
}
