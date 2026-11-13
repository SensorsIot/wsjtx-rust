package WstxRankingControl {
    private import ScalarValues::*;
    attribute def WorkedWindow {
        doc /* window all: the log's cached worked set (rebuilt after a log or country table
             change). today (the current UTC date) and from_to: a worked set built only from
             the records whose QSO_DATE lies in the window, inclusive; cached per (log
             revision, country table, first date, last date; today is its UTC date), at most 4
             windows, so it is not rebuilt per evaluation. A record without a date counts only
             for all. A rebuild takes about 100 ms with 26,902 QSOs (measured 2026-11-06, release
             build, two station steps), so it never runs on the station step: the step uses the
             last built set of the window at once, and a set missing or behind the log is
             built on its own thread for a later step. A selection and POST /strategy/evaluate
             (blocking threads) wait for the current set. With no set yet nothing is
             needed in that step (no claim of needed). */
    }
    attribute def MostWantedList {
        attribute entriesMax : Integer = 1000;
        doc /* D12. Source https://clublog.org/mostwanted.php?api=1: JSON {"1":"344","2":"123",
             ...}, rank to ADIF DXCC number (340 entries, verified 2026-11-06). Parsed exactly:
             an object of 1..1000 keys, each a positive integer in text, each value a positive
             integer below 10000 in text or as a number, no number twice; else the update fails,
             nothing changed. Stored in the profile folder as
             most_wanted.json {schema_version 1, profile_id, date (UTC date of the download), list}. cty.dat has no ADIF numbers: the
             table most_wanted::ENTITIES maps cty.dat entity full names to ADIF numbers (the
             340 current entities; WAE-only entities, Sicily, African Italy, Bear Island,
             Shetland Islands, European Turkey and Vienna Intl Ctr, carry their DXCC parent's
             number). A number of the list without a table entry is ignored and counted as
             unmapped in the status. An entity not in the table or not on the list has no rank
             (ValueOrder sorts it after the listed ones). A list once fetched stays until the next
             update. The file is read off the station step (the first
             GET /strategy, POST /strategy/evaluate or selection, on a blocking thread); the
             step only reads a parsed Arc behind a leaf lock. An unreadable file: no list,
             most_wanted_unreadable true.
             Status in the GET /strategy snapshot: most_wanted null or {date, entries,
             unmapped}, most_wanted_unreadable, most_wanted_attribution "Club Log Most Wanted
             list, Club Log (c) Michael Wells G7VJR, clublog.org".
             Browser, Settings > General: "List from <date> · <entries> entries" (and how many
             are not mapped), or "No list; strategies call the strongest first", with beside it one
             button "Update Most Wanted"; one click does everything. A failure keeps the list and shows the
             reason in one line.
             POST /strategy/most-wanted/download {v, profile_id, boot_id}:
             the station fetches the source once on the operator's click, with the User-Agent
             of most_wanted::USER_AGENT naming this project; a failure or a reply that is no list is 502 download_failed with
             error.reason, nothing changed. Exact keys, with the refusals of POST /strategy/ignore, and
             it returns the snapshot; no MCP tool dispatches to it. There is no automatic
             refresh. */
    }
    attribute def IgnoreLists {
        attribute sessionEntriesMax : Integer = 64;
        doc /* #42 (CL-042-02). A sender is ignored when its call (exactly, not as a prefix)
             is on the permanent list (configuration ignore_calls) or on the session list.
             The session list lives in station memory only (never persisted; a station
             restart empties it): at most 64 entries in the order added, each {call, band,
             expiry}, the band being the station band (CAT dial band, else the operating
             selection band; null when unknown) and the expiry session_ignore_minutes
             after the add, both taken when added (adding a listed call again renews
             them and moves it last; adding a 65th call drops the oldest). An entry ends
             at its expiry.
             Band change: the station's contact step (every 50 ms, whether or not a
             browser is connected) compares the station band with the band it saw last;
             any change (also to or from unknown) empties the session list, so it is
             empty before the next evaluation or run step on the new band.
             Effect: an ignored sender's verdict has rank null and is not greyed, why
             "<call> is ignored (session list)" or "(permanent list)" (session first when
             on both); so it gets no mark, a run never selects it, also when it calls me. A
             contact already in progress is not changed by ignoring its partner.
             Band Activity: the right-click menu offers "Ignore <call>" for a row with a
             resolved sender (session list), "Stop ignoring <call>" when that call is on
             the session list, and no ignore item for other rows. Settings > General: the
             permanent list (calls separated by spaces or commas, saved on change with
             PUT /strategy), the session expiry in minutes (saved on change), and the
             session list with each call's remaining minutes and a remove control; the
             list is read again when the drawer opens. */
    }
    attribute def Alert {
        attribute historyMax : Integer = 100;
        attribute dedupeMinutes : Integer = 10;
        doc /* #42 (CL-042-04, without a setting since #39 2026-11-06). Station side: the
             station's contact step (every 50 ms, whether or not a browser is connected) reads
             the records of the current live job past its alert cursor once each (a job not seen
             before from its first retained record); the cursor advances also while no strategy
             is active, so a later selection never alerts on older decodes. With an active
             strategy, each new record that is a Candidate of it (Verdict, its window and list)
             records an alert; a caller of my call, an ignored sender and a CQ greyed by
             DirectedCqRule never alert. Dedupe: no alert when the
             station recorded one for the same call and the same station band
             (station_band at that time; unknown counts as its own band) whose period
             start lies less than 10 minutes before this record's period start (exactly
             10 minutes later alerts again); this memory is kept apart from the history,
             so Clear does not reset it. An alert never transmits, never selects, arms or
             changes a contact, the automation run, the Tx watchdog or the strategy
             store.
             History: station memory only (it survives page reloads, a station restart
             empties it), the last 100 alerts in the order recorded (the 101st drops the
             oldest), each {id (1, 2, ... since the station started), utc (the record's
             period_start_utc), call, message (the record text), rule (the strategy name),
             band (station band, null when unknown), mode (the live
             job mode, ft8 or ft4), snr_db (null when unknown), dxcc (the full entity name
             of WstxCountryFile::EntityOfCall, null without an entity)}; revision counts every
             alert recorded and every clear since the station started.
             Routes (the StrategyHttp rules for Origin, authorization, media and size): GET
             /strategy/alerts (operating access, no query, empty body) -> {v 1,
             profile_id, boot_id, revision, alerts (oldest first)}. POST
             /strategy/alerts/clear {v, profile_id, boot_id}: exact keys, the refusals of
             POST /strategy/ignore (400 invalid_request with the field,
             unsupported_version, 403 wrong_profile, 409 state_conflict boot_id); it
             empties the history, revision + 1, and returns the alerts snapshot. No MCP
             tool dispatches to the clear (an MCP principal is refused, #58); wstx_read
             view alerts reads GET /strategy/alerts (WstxMcpInterface::ToolCatalog).
             Event: a display-subscribed peer receives alert.state {v 1, type
             "alert.state", data {profile_id, boot_id, alert_revision}} when the revision
             changes after it subscribed (never on subscription itself), paced with
             contact.state; the browser then reads GET /strategy/alerts.
             Browser: Settings > General shows an Alerts section: "Sound" and "Browser
             notification" checkboxes, both off by default, kept per browser and profile
             in localStorage (wstx.alerts.v1:<profile_id> = {sound, notify}; unreadable:
             both off); checking Browser notification is the only place that asks for the
             browser's notification permission (Notification.requestPermission on that
             click, never otherwise); a permission other than granted leaves it unchecked
             with the reason. The history list, newest first, each line "<HH:MM:SS> <call>
             <message> · <rule> · <band> <MODE> · <snr> dB · <dxcc>" (unknown parts left
             out), and a Clear button (POST /strategy/alerts/clear). An alert counts as new
             when its id is above the highest id this page has seen (the history read at
             page load or reconnect announces nothing): for each new alert a short tone
             (Web Audio, about 0.15 s) only when Sound is on and the page is visible, and a
             notification titled "Alert <call>" with body "<message> · <rule>" when Browser
             notification is on and permission is granted (also while the page is hidden);
             with both off nothing is announced (the history still lists it). */
    }
}
