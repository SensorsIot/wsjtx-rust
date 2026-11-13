package WstxQsoWire {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-019';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::AutomationState;
    private import WstxStandardQso::'TC-007-004';
    private import WstxQsoControl::ContactAction;
    requirement 'CL-010-15' {
        doc /* Expose the contact operations only through the versioned WstxContact wire contract: exact routes, keys and byte caps, command_id idempotency, contact_revision, the ContactRefusal codes, the contact.state and station.tick events, and the stated Thin/Off byte budget, leaving StatusReply and the compressed-route allowlist unchanged. Details: WstxQsoControl::ContactWire, ContactCommand, CommandReceipt, ContactSnapshot, ContactStateEvent, StationTickEvent. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/logbook_http.rs; server/src/main.rs";
    }
    dependency CL_010_15_to_FR_019 from 'CL-010-15' to 'FR-019';
    dependency CL_010_15_to_FR_021 from 'CL-010-15' to 'FR-021';
    verification 'TC-007-005' {
        doc /* TC-007-005 — Pushed contact, transmit and receive state without polling
             CL-010-15
             #80 (operator 2026-11-09): the two-browser 32 kbit/s link workload is retired; the link budgets are targets judged from the link byte log (CL-003-05, TC-080-001). What remains are the unshaped pushed-state cases (WstxStationLink::PushedStationState).
             Setup: actual candidate server and Chromium on an unshaped local connection, the contact engine and #9 transmit owner on the recording hardware double, hand-authored result rows published by a test-only control peer, a request recorder.
             Steps: another client changes the contact and the transmit state; an own contact command, a command right after another, a stale safety revision, Esc and CQ during unanswered commands; an older GET /contact held across events; contact.js loaded after the socket's first event; a running Tune on Thin and on Detailed; receive.state with a job, audio and a refused event; contact.state carrying a contact and its dialogue rows.
             Expected: transmit.state and contact.state carry all fields first and then only what changed, shown with no GET /transmit and no GET /contact; an own command reads no GET /contact and a refusal shows its code; the next command goes with the receipt's revision; a stale safety revision is read at once and the CQ retried; nothing queued follows an abort; an older read never replaces a pushed change; a contact client loading after the first event has the state without a read; a Tune countdown alone at most once per 5 s below Detailed; receive.state carries the job and the audio, read again only for a new state, a refused event or a failed read; dialogue rows in order including a continuation at the same sequence.
             2 — Isolated automated functional tests; Windows development PC, real browser/server, no link simulator; no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/contact.test.cjs; server/src/contact_http_tests.rs; server/src/receive_http_tests.rs; tests/ui-operating.test.cjs";
        objective {
            verify 'CL-010-15';
        }
    }
    dependency CL_010_15_verified_by_TC_007_004 from 'CL-010-15' to 'TC-007-004';
    dependency CL_010_15_verified_by_TC_007_005 from 'CL-010-15' to 'TC-007-005';

    // ---------------------------------------------------------------- displays
    attribute def OperatorDisplays {
        attribute utcClockText : String;
        attribute periodElapsedSeconds : Integer;
        attribute periodSeconds : Integer = 15;
        attribute transmitting : Boolean;
        attribute rxLevelDb : Integer[0..1];
        assert constraint progressBounds { periodElapsedSeconds >= 0 and periodElapsedSeconds < periodSeconds }
        assert constraint levelBounds { rxLevelDb == null or (rxLevelDb >= 0 and rxLevelDb <= 90) }
        doc /* D11 adopted. UTC clock HH:MM:SS (MW labUTC) from the server's UTC
             observation in the status stream, advanced locally between observations
             for display only; marked stale with the link; never a scheduling input.
             Tx progress (MW ~8388): #50, one period bar only, the QSO pane's NEXT bar
             (its width the elapsed part of the period, FT4-NOTE 7.5) with the countdown or,
             while #9 reports an active transmission, "▶ TX now" with the seconds left
             (#37, QsoPane NEXT); the top bar shows UTC only.
             The bar is red in a period of my Tx parity while Enable Tx is on and whenever
             transmitting is true, green otherwise (WstxQsoPane::QsoPane NEXT).
             StationPeriodClock (#50, operator 2026-11-02): the UTC clock, the bar and the
             countdown run on the station's UTC (the transmit owner's now_utc_ms, system
             clock plus the #43 correction, the clock the transmitter keys on), never on the
             browser's wall clock: each station observation (station.tick utc_ms and the
             ContactSnapshot utc_ms) gives offset = utc_ms - browser monotonic time at its
             receipt; the shown station time is the browser monotonic time plus the
             largest offset received in the last 20 s (a late delivery only lowers an
             offset); an offset more than 500 ms below that estimate is a backward step
             of the station clock (#43) and restarts the estimate at once. The bar is redrawn at least every 100 ms with no animated width
             change, so it restarts at 0 at each period start within 100 ms plus the
             link's one-way delay. Rx level meter (widgets/
             signalmeter.cpp, meterwidget.cpp): 0..90 dB, rxLevelDb = round(10 log10(mean(s^2))) with s
             the canonical receive samples scaled to 16-bit full scale (32768), over the
             last status interval, at most one value per second on the status link;
             labelled "high" above 85 dB and "low" below 15 dB (meterwidget.cpp ~61/~64 thresholds)
             in text and colour; null shows unavailable when audio is not running. #61
             CL-061-04: the station measures no level while on the air and for the rest of
             that Tx period (null then, "Tx · not measured" while transmitting); a level and
             its low/high entry refer to receive periods only. */
    }
    item def StationTickEvent {
        attribute v : Integer = 1;
        attribute 'type' : String = "station.tick";
        doc /* New versioned WebSocket event, exactly
             {v:1,type:"station.tick",data:{profile_id,boot_id,utc_ms,period_ms,
             transmitting,rx_level_db}}, at most 224 bytes (the exact keys with two UUIDs
             and a 13-digit utc_ms already need 220; corrected from 192 by the #10
             implementation, review required). Rate per peer by its display
             subscription: Detailed 1 per second; Thin and Off 1 per 5 s; plus at most one
             extra event per transmit start/stop. A peer that never chose a display
             subscription (a bare status observer) receives neither event. The browser interpolates the UTC clock
             and Tx progress locally from utc_ms with its monotonic clock between ticks
             (display only); rx_level_db shown is the latest tick value. Budget: Off idle
             with two clients adds at most 2 x (224 + 2 WS + 29 TLS + 160 accounted
             TCP/ACK) / 5 s = 166 B/s per direction, so the status-only idle total stays
             within WstxStationLink::ThinLinkBudget 1000 B/s; Thin stays within the
             existing 3000 B/s live envelope. Both are targets judged from
             WstxStationLink::LinkTrafficLog (#80). */
    }
}
