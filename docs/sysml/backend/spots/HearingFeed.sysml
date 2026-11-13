package WstxHearingFeed {
    private import ScalarValues::*;
    attribute def HearingFeed {
        attribute heardWindowSeconds : Integer = 600;
        doc /* The read-only PSK Reporter MQTT feed (#39, the operator's agreement of
             2026-11-04): whether the current target hears my call and which frequencies it
             decodes. Everything works without it: no connection is unknown, never an error
             for the operator, and receive and the 50 ms station step never wait on it (its
             own thread does all network waiting; the station reads a short-held lock).
             Broker: mqtt.pskreporter.info port 1884, MQTT 3.1.1 over TLS, trusting only the
             compiled-in ISRG Root X1 and X2 with the name checked (that chain validated on
             2026-11-06); a broker moved to another CA shows an error in Settings and needs
             a new build. The broker's page states no formal terms and no rate limit, says
             "No account and no polling", is provided by Tom M0LTE, and says the feed
             originates from Philip Gladstone at pskreporter.info, used with permission.
             Client id: wstx, my call and 4 characters of the boot id (alphanumeric, at most
             23 bytes), so that the operator of the broker can identify the station. No
             user name, password or will. QoS 0, clean session.
             The station sends only the MQTT handshake, keep-alive pings every 45 s of
             silence (keep-alive 60 s), its subscriptions and DISCONNECT. Exactly two filters
             of the filtered feed, never the raw feeds: pskr/filter/v2/+/+/<my call>/+/#
             and, only while a strategy or contest run's own contact has a DX call and
             PskrUse is on (not a pounce, an MCP policy run or a manual contact),
             pskr/filter/v2/+/+/+/<target>/#, replaced when the target changes. A call
             forms a topic segment only as 1..16 of A-Z 0-9; any other call, such as one
             with a slash or anything decoded with an MQTT wildcard, gets no subscription and
             stays unknown (the broker documents no form for it).
             Reconnect: 5 s after every session end, doubling to 300 s; it starts over only
             after a session of 60 s, and no change of a setting skips the wait. 90 s without
             any packet ends a session. A packet over 4096 bytes or outside the subset is a
             protocol error and ends the session; a payload that is no spot is dropped.
             A spot: f (Hz), md, b, sc, rc and t_tx (or t when absent), fields of 1..16
             characters, and rp (the receiver's reported SNR in dB, an integer -99..99;
             absent or another value: unknown, the spot still counts). The payload decides, not the topic: a spot neither from my call nor
             to the current target is dropped. A time ahead of the station counts as now.
             Hearing: the target hears us when a spot from my call to that receiver on the
             station's mode and band is at most heardWindowSeconds old. 600 s because
             reporters upload in batches up to about 5 minutes late, so a spot can only be
             expected within that delay plus one more upload; an older spot no longer
             describes this path. Newest time per (receiver, band, mode) with that spot's rp,
             at most 256 entries, the oldest going first.
             Frequencies the target decodes: spots to the current target from other senders
             (at most 128, forgotten when the target changes), as audio offset = f minus the
             radio's confirmed dial of this band, with the parity of their t_tx (the period of
             the sender's transmission), only for the station's mode and band, at most
             heardWindowSeconds old, inside the free slot range of the mode, newest first and
             distinct per (offset, parity), at most 32. A spot on another band or mode is
             ignored. An unknown dial or band gives none.
             He reports (#97, #94 "reports its stations"): at least one spot whose receiver is the
             current target, from any sender (my call included), on the station's band and mode,
             at most heardWindowSeconds old, whatever its offset (the 32-offset bound and the slot
             range do not apply to this test). A spot of my call at him (he hears us) is one. With
             no target subscription yet, or one younger than a spot's upload delay, he reports only
             when such a spot has arrived: until then the PSK case is no_reports (TxMoveRule).
             Setting: on by default, because the operator agreed to this read-only
             subscription; it is the master switch beneath PskrUse. pskr.json {schema_version
             2, profile_id, enabled, use} beside profile.json (use: PskrUse; a file of
             schema_version 1 reads with use true and is written as 2 by the next change; a
             foreign or broken file reads as on with use true, naming invalid_pskr). Off
             disconnects and forgets everything the feed said. Each change of the switch ends the
             session of the earlier setting; the status shows connecting while the switch
             is on and the station waits for its next attempt, and off only when no connection
             can be made.
             GET /pskr {v 1, profile_id, boot_id, enabled, use, state off|connecting|connected|error,
             error (code or null), last_spot_utc_s, storage_error}, read once on each
             connection; POST /pskr {v 1, profile_id, boot_id, enabled} (operating access,
             the browser only) saves the switch and POST /pskr/use {v 1, profile_id, boot_id,
             use} saves PskrUse (exact keys and the refusals of POST /pskr each); a display-subscribed peer receives pskr.state
             with the same data on a change, for spots at most once per 30 s, and renders the
             age from station.tick. No polling (WstxStationLink::PushedStationState).
             Tests: WSTX_PSKR=off opens no connection; WSTX_PSKR=tcp:<loopback>:<port> speaks
             plain MQTT to a local peer; nothing else can replace the broker. */
    }
    attribute def PskrUse {
        doc /* Use PSK Reporter (Q17, Q29): a toggle next to Auto (WstxQsoPane::QsoPane),
             kept across restarts in pskr.json use (HearingFeed), on by default. The Settings
             switch (HearingFeed enabled) stays the master: with it off the toggle is disabled
             (title "PSK Reporter is off in Settings") and counts as off. POST /pskr/use saves
             it; pskr.state pushes it. With it off, runs use no spot: no target subscription, no
             target hears us or reports (LeaveRule uses n, never m, the contest stays nothing,
             TxMoveRule's case is no_reports, ValueOrder hears_us ties), and FreeTxSlot ignores his
             end.
             While it is on, a strategy or contest run's own contact has a target, the QSO pane
             shows two lines under the header: "Hears us: <age> ago · <rp> dB" from the newest
             spot of my call at the target (age from station.tick: "<n> s" below 120 s, else
             "<n> min" in whole minutes; rp signed as "−12"; "· ? dB" without rp),
             "Hears us: no" when the feed is connected, the call has a subscription and no such
             spot is at most 600 s old, and "Hears us: unknown" otherwise; and "Tx <hz> Hz ·
             open at his end: yes" (no frequency he decodes from my Tx parity lies within 50 Hz
             of the slot), "· no" (the slot was chosen although one does, FreeTxSlot), or
             "· unknown" (he has no such spot). The run snapshot (GET /automation, read on
             automation.state) carries hearing {state heard|no|unknown, reports (he reports,
             HearingFeed; false also when unknown), spot_utc_s, snr_db} and
             tx_slot {hz, power_db, his_end yes|no|unknown}; a change of either increments the
             run revision. The QSO pane's PSK line itself is #95's. */
    }
}
