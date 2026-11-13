package WstxOperatingChain {
    private import ScalarValues::*;
    attribute def ContestVerdict {
        doc /* WstxStrategy::Verdict with a contest in force, one per decoded record with a resolved
             sender that is standard, or a Field Day exchange (type field_day) to a call, in this
             order of tests: ignored (IgnoreLists, as a strategy); greyed
             (DirectedCqRule); "my own message"; "band unknown"; "band not in the contest"; "log
             unreadable"; "dupe" (DupeRule for the station band, mode class Digital; rank null,
             dupe true, also when it calls my call: operator #63 "non-dupe",
             WstxStrategy::CallerOfMyCall); a caller of my call (CallerOfMyCall, also a grid or Field Day
             exchange to it); else the callsign guard (SaneCall; a /R rover passes where a new grid counts,
             band_grid); else "not a CQ": a CQ or an RR73/73 to someone else counts as calling, in
             every contest. So the callable records have a rank by ContestValueOrder; every other has
             rank null. The reply's verdicts carry dupe, new_multiplier (the record's key is not
             yet in the period, false without a grid) and points (PointsRule; null when not known).
             POST /strategy/evaluate with strategy null and a contest in force returns these, with
             strategy the profile's name and contest the tally {qsos, multipliers, points, score}
             (null when the log is unreadable); explain false lists the ranked, the greyed and the
             dupes. A draft strategy still previews the draft. why: "calls my call", "new
             multiplier", "<n> points" joined by " \· ", or the reason above. */
    }

    // ---------------------------------------------------------------- messages
    enum def TxSlot { enum tx1; enum tx2; enum tx3; enum tx4; enum tx5; enum tx6; }
    attribute def BusyPartner {
        attribute busyPausedCallsMax : Integer = 6;
        doc /* #97 decision 7 (operator #93 2026-11-09; it replaces the WSJT-X stop of
             partnerWorksOther for the contacts that pause, AutoSequence; the #93 draft fca9822fe
             compared). Starts: a decoded standard message from the partner (the contact's DX
             call) to another call than mine that carries a grid, a report or an R-report (his QSO
             with that station in progress, also his own Tx1 to it); a hashed call "<...>" that is
             not filled with my call (WstxContact's hash table does not resolve it to my call) is
             another call. Holds (operator #93: "we pause counting ... till the called station
             finishes its other qso"): from then on, however long he is not decoded and also when
             he goes on with a further station, until he ends it: his RR73, RRR or 73 to another
             call, his CQ, his free text (a free text has no sender: it counts as his when decoded in
             his period within 10 Hz of his last decode; #97 coordinator default), or any message from him to my call (progress,
             AutoSequence); a new contact or the end of the contact clears it. Nothing but his own
             messages ends it, and the bound of TxWatchdog (N paused calls per message, #97 Q5)
             keeps it from extending a call without limit.
             When it counts: a send is paused when he is busy at its stop point, 1.2 s into its
             period (TxWatchdog): a publication that ends or starts it arriving before the stop
             point (1.1 s) counts for that send, one arriving after it (1.3 s) for the next.
             Split frequency ("check if we are not on his transmit frequency"; it applies to every
             contact that pauses, also while it is not pausing: an unattended run with busy_pause
             on, or a message whose N paused calls are used up): when he sends a decoded message to
             another call (any, busy or not; the trigger of partnerWorksOther, in replying and in a
             Tx1-skipped report) and my Tx signal is not clear of his signal, Tx moves before my next
             own period to the nearest candidate clear of it. Clear: my signal [f, f + width) keeps
             50 Hz from his [d, d + width): |f - d| at least width + 50, FT8 100 Hz, FT4 140 Hz
             (FT8 99 moves, 100 stays; FT4 139 moves, 140 stays). Candidates: WstxStrategy::FreeTxSlot's
             grid from 500 Hz inside the Tx range, clear of his signal and of decoded stations while
             one is free, at least 50 Hz from a frequency his PSK Reporter spots show him decoding in
             my Tx parity while one is free (else that is not used), the nearest to the current Tx,
             the lower on a tie; Rx stays on him. His decode arriving before the audio start of my
             next send moves the pending request (WstxQsoTransmit::TransmitSubmission replaces it); one
             arriving after the audio start lets that send finish where it is and moves the next. A
             refused move (set_frequency refused) falls back to the stop of partnerWorksOther (the
             transmit state off, cause partnerWorksOther), so Tx never stays on his signal. In
             manual operation this is the one automatic Tx move besides Hold Tx's rules, also with Hold Tx on (operator
             2026-11-09, #97 Q7 "yes, both"; an exception to CL-039-08); an explicit Tx action of the
             operator (also a click onto his signal) wins until his next message to another call,
             which moves it again. A contact that does not pause (a pounce, an MCP policy run, a run
             with busy_pause off) keeps partnerWorksOther's stop.
             Shown: the contact snapshot's watchdog carries busy_with (null, or the other call as
             decoded, at most 13 characters, "<...>" for an unresolved hash) and paused_calls (the
             paused calls of the message due next); GET /contact stays within its 4096 bytes in the
             maximum shape with a 13-character busy_with. The browser appends " · <call> busy with
             <other>, not counted (<k>/<N>)" to WD:n in the QSO pane and the station bar while
             busy_with is set (in a run's own contact the leave label carries it,
             WstxStrategy::LeaveCountLabel). busyPausedCallsMax is the default limit; the bound is
             the operator's current limitCalls. */
    }
    enum def TransmitRefusal {
        enum transmitUnsupported; enum notArmed; enum audioStarted; enum duplicateSequence;
        enum staleRequest; enum clockNotSynchronized; enum misalignedPeriod; enum stalePeriod;
        enum packRefused; enum frequencyOutOfRange; enum busy; enum notAuthorized;
        enum radioUnavailable;
    }
    attribute def TransmitRequest {
        attribute contactId : String[0..1];
        attribute requestSequence : Integer;
        attribute mode : WstxModeProcessing::Mode;
        attribute periodStartUtcMs : Integer;
        attribute messageText : String;
        attribute txOffsetHz : Integer;
        doc /* At most one request per station waits to be keyed. Admitted only
             while armed under TransmitAuthority; the service packs messageText
             (PackMessage), plans the start (PlanTransmitStart), encodes the 48 kHz
             waveform, keys PTT and plays (TransmitTiming). requestSequence is a
             strictly increasing safe integer per boot: a lower or equal sequence is
             duplicateSequence, never transmits twice and changes nothing (a retry does
             not disarm). A new admitted request REPLACES the pending one (replaced)
             while its audio has not started; a keyed request is replaced only by one
             for the same period. From keying a request for another period becomes the
             next pending request, started after the current one completes, and from
             audio start one for the same period is refused audioStarted (no disarm):
             the keyed request never makes another one busy or disarms (#10).
             Clock, alignment and lateness refusals (clockNotSynchronized,
             misalignedPeriod, stalePeriod) and packRefused or frequencyOutOfRange are
             checked at admission; the start is planned again at keying and at audio
             start, so a request that became stale is refused, never replayed. A
             request of another boot is refused at the wire (state_conflict). */
    }
}
