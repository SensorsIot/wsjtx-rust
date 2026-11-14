package WstxBandActivity {
    private import ScalarValues::*;

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
    enum def BandActivitySlot {
        enum mycall; enum new_continent; enum new_continent_band; enum new_cq_zone; enum new_cq_zone_band;
        enum new_itu_zone; enum new_itu_zone_band; enum new_dxcc; enum new_dxcc_band; enum new_grid;
        enum new_grid_band; enum new_call; enum new_call_band; enum lotw;
    }
    attribute def BandActivityColours {
        attribute slots : Integer = 14;
        doc /* CL-050-02 (#50). The WSJT-X 3.3 DecodeHighlightingModel slots in its priority order
             (BandActivitySlot order, highest first) with its colours and default on/off except as
             stated below (row
             background; dark theme as the same colour at 0.2-0.35 alpha; the Day and Night themes
             transform the whole page): mycall #ff6666 on; new_continent #ff0063 on;
             new_continent_band #ff99c2 on; new_cq_zone #ffbf00 on; new_cq_zone_band #ffe499 on;
             new_itu_zone #a6ff00 off; new_itu_zone_band #ddff99 off; new_dxcc #ff00ff on;
             new_dxcc_band #ffaaff on; new_grid #ff8000 off; new_grid_band #ffcc99 off; new_call
             #00ffff on; new_call_band #99ffff on; lotw off (no source). Only stations of interest are
             coloured (operator 2026-11-03, a deliberate difference from WSJT-X): there is no cq slot
             (WSJT-X 'CQ in message' #66ff66), so a row that matches no slot, among them a CQ/QRZ line
             from a sender worked before on this band and mode, has no background, and New call and
             New call on band are on by default (WSJT-X: off). A row takes the highest-priority
             enabled slot it matches. Matches: mycall, a decoded message to the profile callsign
             (also from a sender worked before), also as a filled-in hash <MYCALL> or the 'to' call
             of a nonstandard i3=4 message (WSJT-X matches "[ <]MYCALL[ >]", #24 S1b); new_call,
             the worked-before status
             not_worked of the sending call; new_call_band, not_worked or worked_other_band_or_mode; every new_*
             slot also when the record carries flags.<slot> true (#55 supplies DXCC, continent and
             zone flags from cty.dat; a slot without data stays inactive). As in WSJT-X, every
             new_* slot applies only to CQ/QRZ lines, and a never-worked call matches new_call and
             new_call_band. Worked before on this band and mode has no colour.
             Operator decision (#55, 2026-11-03, CL-055-04), deviating from WSJT-X, which colours
             only CQ/QRZ and calling-me lines: the new_* slots apply to the sender of every decoded
             message (CQ, replies to others, reports, R-reports, RR73, 73; the sender call of
             WstxLogControl::DecodedEntity), and they match
             only the record's flags (WstxLogControl::DecodedEntity; the worked-before status adds no
             slots). A row without a flag has no colour: there is no cq slot (#50). A row
             to my call keeps mycall on top. A row with a reason of its colour carries the reason
             tip of BandActivityHover (#50 CL-050-08). Settings > General > Display lists the slots with their
             colours; the choice is per browser (browser storage). The #39 strategy mark is an
             accent (a left bar and the message text), never a row background.
             Row scheme (operator 2026-11-04, refining 2026-11-03; BandActivityScheme): what a
             slot colours depends on the row's mark, in BandActivityRowMark order. */
    }
    enum def BandActivityRowMark {
        doc /* #50 (operator 2026-11-04). The mark of a decoded Band Activity row, highest
             first; a row takes the first that applies. */
        enum partner; enum callsMe; enum newWholeRow; enum newSenderOnly; enum plain;
    }
    attribute def BandActivityScheme {
        attribute partnerFirst : Boolean = true;
        attribute partnerStripe : Boolean = true;
        doc /* CL-050-08 (#50, operator 2026-11-04). The sender of a row is recordFrom (the
             'from' call, also as a filled-in hash, or the sender of a nonstandard i3=4
             message); the partner is the dx_call of the contact snapshot the page already
             holds (WstxQsoControl::ContactSnapshot, no further request or poll) while the
             contact is prepared or running (replying, report, roger_report, rogers,
             signoff): from the contact preparation (select_row) until it is logged
             (completed) or cancelled. Marks (BandActivityRowMark):
             partner: a decoded row whose sender is the partner. All partner rows of the
             shown periods (latest and kept) are moved to the top of Band Activity, in
             whatever column order, newest period first, followed by a red separator
             stripe (a divider row without text, 3 px, #ff4040); the period blocks below
             keep their own order and dividers, and a period divider whose rows all moved
             up is dropped. A partner row carries a 4 px red left bar, a "◆ QSO" badge
             after its message (outside the message text) and a bold message; it has no
             slot background (also when it is to my call).
             callsMe: a decoded row to my call (as the mycall slot: also a filled-in hash
             <MYCALL> or a nonstandard i3=4 'to', #24) whose sender is not the partner:
             the whole row in the mycall colour, also when the sender was worked before on
             this band and mode (calling me is always actionable).
             newWholeRow: a CQ or QRZ message (text starting CQ or QRZ, or a nonstandard
             CQ) whose sender has an enabled new_* slot: the whole row in the colour of its
             highest-priority enabled slot.
             newSenderOnly: any other decoded row (a station in QSO with another station:
             replies, reports, R-reports, RR73, 73) whose sender has an enabled new_* slot:
             only the sender's call in the message carries that slot's colour (an inline
             mark around the call word, also inside < >), the rest of the row is plain.
             plain: everything else, no colour.
             The Settings > General > Display slot choice applies to every mark: with
             mycall off a callsMe row falls back to its new_* slots as a newWholeRow;
             without an enabled slot a newWholeRow or newSenderOnly row is plain.
             The #39 strategy accent and value order stay as they are; the partner block
             is a period block of its own for the strategy order. The reason tip of a row:
             BandActivityHover. */
    }
    attribute def BandActivityValue {
        attribute levels : Integer = 8;
        doc /* #55 (operator 2026-11-03, CL-055-04). The value of a Band Activity row, best
             first: 1 calling me (a decoded message to the profile callsign, matched as for the
             mycall slot, also a filled-in hash <MYCALL> or a nonstandard i3=4 'to', #24); 2 a strategy
             hit (a strategy active, WstxSettings::ValueView rank not null); 3 new DXCC or new
             continent (flags new_dxcc, new_continent); 4 new DXCC or continent on this band
             (new_dxcc_band, new_continent_band); 5 new CQ or ITU zone, ever or on this band;
             6 new grid, ever or on this band; 7 new call, ever or on this band; 8 no flag.
             The flags are those of WstxLogControl::DecodedEntity for its sender call, CQ or
             not. */
    }
    attribute def BandActivityHover {
        doc /* #55 (CL-055-04), #50 (operator 2026-11-04, CL-050-08: "too much information",
             "line them up horizontally", "the rest is already visible in the band activity").
             A Band Activity row's reason tip names only the reasons of its colour that the row
             does not show: no country, continent, distance (their columns show them) and no
             "Calls you" (the message shows my call). Per kind, in this order, the strongest
             reason whose slot is enabled in Settings (BandActivityColours): continent "New
             continent <cont>", else "New continent on <band>"; DXCC "New DXCC", else "New
             DXCC on <band>"; zone "New CQ zone <cq>", else "New ITU zone <itu>", else "New CQ
             zone on <band>", else "New ITU zone on <band>"; grid "New grid <square>", else "New
             grid on <band>"; call "New call", else "New on <band>" followed by the sender's
             worked-before status in parentheses ("(worked on another band or mode)" or "(worked
             on <band> <MODE>)", the record's worked_status, WstxLogbook::WorkedBeforeQuery; the
             status stays on the row while it is shown, also as a kept period, #50). An
             overall flag implies its on-band flag, so the on-band text appears only without
             it. Then the #39
             strategy verdict ("Strategy <name>: #<rank>" or "Directed CQ, not calling us: the
             strategy skips it, a double-click warns"). The reasons form one line joined by " · ", for
             example "New DXCC · New call", "New on 40m (worked on another band or mode)",
             "New CQ zone 10". A partner row carries no flag reason (its marker shows it). A
             row without such a reason has no tip; a worked-before status alone gives none.
             The tip is a compact one-line box (no native title, which wraps unpredictably) at
             the pointer while it is over the row, except over a cell with its own title (DXCC,
             Distance, the message of an a-priori decode), and under the row while the row has keyboard focus; it goes when the
             pointer leaves, focus moves or the row is redrawn, and follows a Settings slot
             change. The same text is the row's aria-description. <band> is the operating
             selection band ("this band" when none). The QSO pane callers keep their own list
             of reasons (QsoPane item 3). */
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
             the latest; a new receive identity (band/mode change, restart) clears it,
             an unknown-loss source epoch of the same receive does not (CL-061-01).
             A Tx period (the station's latest_decode transmitted marker, CL-061-04)
             shows one Tx marker row and no empty block; the receive period below it
             keeps its divider and stays when the next period arrives (CL-061-03).
             After a page load only the latest period shows until the next one arrives. Within a period the ActivityOrdering applies (column
             header click). DXCC shows the shown name of the sender's entity
             (WstxLogControl::DecodedEntity dxcc; title: name, continent, CQ and ITU zone),
             an explicit unavailable mark without one. Distance is the great-circle
             distance from the profile locator to a grid carried in the message (RR73 is
             the roger, never a grid; a grid from another row or the log is not used);
             without a grid the entity distance marked approximate ("~n km"); unavailable
             otherwise. The QSO pane header shows the partner's shown name and continent
             first on its detail line under the call and grid (GET /dxcc?call=, once per DX call), and the
             entity distance marked approximate when the contact has no grid. Colours (#50, BandActivityColours) are the WSJT-X
             row backgrounds; the only text mark is WSJT-X's a-priori marker: a record with
             a_priori N shows a small "aN" after its message, outside the message text
             (#56 slice 5, WstxModemDecode::APrioriHypotheses); worked before (WstxContact::
             WorkedBeforeQuery) feeds only the hover text (BandActivityHover); what a slot
             colours (whole row, sender call only, none) and the QSO partner's rows on top
             with their marker and the red stripe follow BandActivityScheme (#50, CL-050-08);
             rows are ordered
             by value (BandActivityValue, ActivityOrdering); row density (#55, operator 2026-11-03,
             CL-055-05): table rows with a fine pointer have 1 px vertical cell padding and line
             height 1.25 at the unchanged font size (at most 24 px per row), period dividers 1 px,
             so more stations fit; with a coarse pointer (touch) rows keep 8 px padding; at most
             44em wide (360 px, 200 % zoom) a row is a compact row without field labels (#37, live
             finding 2026-11-04: the earlier labelled card rows were about 325 px high, one
             decode on screen): UTC, dB, DT, Freq and the distance on the first line, then the
             message and the country, wrapping only between whole fields at the readable text
             size (usually two lines, about 45 px, still tappable), so at least six rows are on
             screen at 360x800 (TC-037-003); at most 48em wide Band Activity, above the QSO
             pane, has a fixed height (29rem) and scrolls inside; with a strategy active the strategy accent of
             WstxSettings::ValueView (ranked rows first in their period under the value sort, greyed directed
             CQs not for my continent). A selection of a CQ that is not answerable first shows the
             WstxValueOrder::DirectedCqRule warning; only its confirmation selects (during a contact a
             click on it offers nothing). Pointer: click selects (SelectDecodedRow, prepares, never
             transmits; while a contact is active a row that can start a contact for me, a
             CQ/QRZ complying with WstxValueOrder::DirectedCqRule or a row addressed to my call,
             only offers "Change contact to <call>", naming its sender, whose replacement keeps
             Enable Tx as it is, and a row of a QSO between others or a CQ directed elsewhere
             offers nothing (#37, CL-037-05); double-click
             replies (select, then SetEnableTx on; on a row of a QSO between others the command
             line reads "Call <sender>"), and on another station while a contact
             is active, or during an own CQ, it is itself the explicit
             WstxStandardQso::ChangeContact (replace true, no confirmation, as WSJT-X
             handleDecodeSelection widgets/mainwindow.cpp ~9122-9229 with quick_call on,
             DecodedMessageReaction.cpp ~411-413), so the next own period calls the new
             station and Auto Seq runs that QSO to its completion and log (#50, operator
             2026-11-02); a stale_revision refusal of its select_row or enable_tx (the
             contact revision moves with every transmit step) is retried at most twice
             with the reloaded snapshot, since the operator's choice is explicit. The
             double-click is the second press of the row (its click count 2), so a
             redraw of the Band Activity rows between the two clicks or during the
             second press still replies (#50, operator 2026-11-03 G8KHF after G6WCX:
             the browser drops a click whose pressed row was redrawn); the
             Reply menu item does the same; right-click
             opens a menu: Reply, Select, Set Rx here and, for a row with a resolved
             sender, "Pounce <call>" or "Stop pouncing <call>" (#42 WstxStrategy::Pounce)
             and "Ignore <call>" or "Stop ignoring <call>" (#42 WstxStrategy::
             IgnoreLists session list). Enter selects; the menu is also
             reachable with the keyboard (context-menu key / Shift+F10). */
    }
}
