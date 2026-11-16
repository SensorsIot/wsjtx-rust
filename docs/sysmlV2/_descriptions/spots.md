# Spots

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the two files of `backend/spots/`,
`interfaces/internal/Hearing.sysml`, `interfaces/external/PskReporter.sysml`, and of
`Station.sysml`, `Context.sysml` and `interfaces/internal/ModeProcessing.sysml` only the
lines that attach spots. Not read: the code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Feed | the stream of PSK Reporter spots the station subscribes to at a broker | `PskReporter` |
| Spot | one reception report: who heard whom, on which band, mode and frequency, when, how strong | `Spot` |
| Target | the station called by the own contact of a strategy run or contest run, while that contact is active | `HearingFeed` |
| Counts | a spot counts until it is 600 s old | `HearingFeed::heardWindowSeconds` |
| Hears | a station hears the profile's call while a spot from that call received by it on the station's band and mode counts | `HearingReport::heardBy`, `HearingState` |
| Reports | the target sends spots: a spot it received, from any sender, counts | `TargetHearing::reports` |
| Decoded offset | a frequency the target decodes, as an audio offset from the confirmed dial, with the period parity of the sender | `DecodedOffset` |
| Session | one connection to the broker, from greeting to its end | `FeedSession` |
| The two switches | enabled (the station reads the feed) and use (runs use what the feed says): the configuration of spots | `SpotsConfig`, `FeedSwitches` |

"State" has two meanings, each with its own type: whether the target hears the station
(`HearingState`) and the state of the connection to the broker (`FeedState`).

## 2. Place in the system

Position: `Station` > `backend` > `stations` (one per profile) > `spots : SpotsService`.

| Port of spots | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `heardBy` | `HeardByPort` | ranking, `hearing` | `HeardByLink` | out: `HeardByReport` |
| `target` | `TargetHearingPort` | auto, `hearing` | `TargetHearingLink` | out: `TargetReport` |
| `pskReporter` | `PskReporterPort` | the PSK Reporter broker of the context | `PskReporter` | out: `Subscription`; in: `Spot` |

Ranking reads which stations hear us; auto reads what the station being called hears, for
the automatic choice of the transmit frequency (operator 2026-11-16).

Not connected: the station service, the profile, receive, transmit, radio control, the log,
the UDP sender, audio, the clock, the modes part, web and mcp. Spots can therefore take no
command and no setting and report no status; see the marker in section 10.

## 3. Purpose and requirements

Spots tells the station who hears it: it reads the PSK Reporter feed as a subscriber, makes
one hearing report from the spots, keeps the operator's two switches and reports the state
of the feed. The three clauses derive from FR-012, which `Station.sysml` gives to spots.

| Clause | Subject | Promise | Element | Status |
|---|---|---|---|---|
| CL-039-20 | spots | tell ranking which stations hear the profile's call and auto what the station being called hears and decodes, and say unknown where the feed cannot tell | `HearingFeed` | implemented |
| CL-039-26 | spots | read the feed and let runs use it only as the two switches of its configuration say, and report the state of the feed | `FeedSwitches`, `FeedStatus` | implemented |
| CL-039-27 | the interface `PskReporter` | take part in the feed as a subscriber to the spots of the own call and of the target, and wait longer after each ended session before connecting again | `FeedSession` | implemented |

## 4. Data and rules

### The spot (`Spot`)

A text field has 1 to 16 characters. A payload that does not give the fields in this form
is no spot.

| Field | Source key | Rule |
|---|---|---|
| `sender` | sc | the call that was heard |
| `receiver` | rc | the call that heard it |
| `mode` | md | |
| `band` | b | |
| `frequencyHz` | f | |
| `sentSeconds` | t_tx, else t | when the sender transmitted, seconds of UTC since 1970 |
| `reportedSnrDb` | rp | a whole number from -99 to 99; absent without it or with another value, and the spot counts all the same |

### The hearing report (`HearingReport`, `TargetHearing`, `HearingFeed`)

Everything in a report is about the station's band and mode: the band of the dial that
radio control confirms, else the band of the operating selection, and the station's
operating mode. A report is given at once from what the feed has delivered so far.

| Field | Rule |
|---|---|
| `inUse` | both switches are on; while false the report tells nothing: `heardBy` is empty and means unknown, and there is no target |
| `heardBy` | the calls of the stations at which a spot of the profile's call counts |
| `target` | absent while spots follows no target |
| `target.call` | |
| `target.state` | heard: a spot of the profile's call at the target counts. no: the feed is connected, the target's call forms a filter and no such spot counts. unknown: every other case |
| `target.spotSeconds`, `target.snrDb` | time and reported SNR of the newest such spot; present in the state heard (the SNR only when the spot names one) |
| `target.reports` | a spot received by the target on the station's band and mode counts, from the profile's call or any other sender |
| `target.decoded` | at most 32 offsets, the newest first, each pair of offset and parity once; an empty list means the target has no such spot; absent while unknown: without a band or a confirmed dial |

| Rule | |
|---|---|
| a spot is used | when its sender is the profile's call or its receiver is the target; every other is dropped, whatever topic it came on |
| a spot counts | until it is 600 s old, from the time its sender transmitted; a time ahead of the station's time counts as sent on arrival |
| decoded offsets come from | spots the target received from other senders on the station's band and mode that count; only an offset inside the range of transmit offsets of the mode |
| another band or mode | tells nothing about this one |
| forgotten | the spots the earlier target received, when the target changes; every spot, when the profile's call changes or the feed is switched off |

### The switches and the status (`FeedSwitches`, `FeedStatus`)

| Value of `SpotsConfig` | Until it is set | Rule |
|---|---|---|
| `enabled` | on | the station reads the feed; switching it off ends the session and forgets every spot and the time of the last one |
| `use` | on | runs use what the feed says; counts only while enabled is on; with one of the two off the report tells nothing and the target is not subscribed |

The two switches are the configuration of spots. Spots defines them; the profile keeps
them in the station config; the station service gives them in `SpotsConfiguration`, at
station start and whenever the station config changes, and spots follows a changed switch
at once. Spots has no command that sets a switch.

`FeedStatus`: `enabled`, `use`, `state`, `error` (present in the state error),
`lastSpotSeconds` (absent until a spot arrives after the feed was switched on).

### The session (`FeedSession`, `FeedError`)

| Rule | Value |
|---|---|
| broker | mqtt.pskreporter.info, port 1884, over TLS; accepted only under the built-in roots ISRG Root X1 and X2 and only for that name |
| client identifier | wstx, the letters and digits of the profile's call, four letters and digits of the boot identity; at most 23 characters |
| greeting | no login name, no password, no will, clean session, keep-alive 60 s; subscriptions at QoS 0 |
| the station sends | the greeting, its subscriptions and their removal, pings, the farewell; nothing else |
| filter for the own call, in every session | `pskr/filter/v2/+/+/<call>/+/#` |
| filter for the target, while both switches are on and a target is followed | `pskr/filter/v2/+/+/+/<target>/#`; removed and made anew when the target changes or the second switch goes off |
| a call forms a filter | with 1 to 16 characters, each a capital letter or a digit; every other call gets no subscription |
| ping | before the station's own silence reaches the keep-alive |
| a session begins | when the feed is switched on, the profile has a call and the wait is over |
| the station ends a session with the farewell | when the feed is switched off or on again, the profile's call changes, the station stops |
| wait before the next attempt | 5 s, then twice as long each time up to 300 s; an attempt that lasted 60 s starts at 5 s again; a change of a switch does not shorten it |
| packet from the broker longer than 4096 bytes | `protocolError` |
| `WSTX_PSKR` | `tcp:<address>:<port>` of a loopback address: that peer, without TLS; any other value: no connection |

| `FeedError` | When |
|---|---|
| `resolveFailed` | the broker's name was not resolved |
| `connectFailed` | no address of the broker took the connection |
| `tlsFailed` | the secured connection was not made or the certificate was not accepted |
| `connectionRefused` | the broker answered the greeting with a refusal |
| `connectionTimeout` | no answer to the greeting in time, or nothing from the broker for one and a half times the keep-alive |
| `connectionLost` | reading or writing failed |
| `connectionClosed` | the broker closed the connection |
| `protocolError` | a packet too long, or one a subscriber does not receive |
| `subscribeRefused` | the broker refused a subscription |

## 5. Behaviour

The connection (`FeedState`): off (switched off, or no session tried since station start,
or no connection allowed), connecting (an attempt runs, or the station waits after a
session it ended itself), connected (the broker has accepted the greeting), error (the
last session ended with a `FeedError` and the station waits). The model gives the meaning
of each state and the rules of `FeedSession`; it has no state machine.

**Default: where the feed cannot tell, the answer is unknown.**

## 6. Implemented in and tested by

| Element | Module |
|---|---|
| `SpotsService` | `server/src/operating/qso/pskr.rs` |

The model names no detail tests for spots.

## 7. What it relies on from outside

Used and not defined here: FR-012; `WstxModeProcessing::PeriodParity`; the profile's call;
the station's boot identity; the confirmed dial (radio control); the
operating selection and the operating mode; the range of transmit offsets of a mode; the
strategy run, the contest run and their own contact.

Outside sources: MQTT 3.1.1 (OASIS); the PSK Reporter MQTT feed and the payload of a spot.

## 8. Differences from a named reference

None stated.

## 9. Verification

| Case | Shows | Verifies | Level | Test |
|---|---|---|---|---|
| TC-039-020 | the hearing report from spots written by hand, and the first switch as it is until it is set; 8 conditions and 1 planned | CL-039-20, CL-039-26 | 2, development PC | `server/src/operating/qso/pskr_tests.rs` |
| TC-039-048 | the reported SNR, the parity, the second switch, the state of the target's hearing; 4 conditions | CL-039-20, CL-039-26 | 2, development PC | four named tests in `pskr_tests.rs` |
| TC-039-052 | the session with a broker on the loopback address; 12 conditions | CL-039-27 | 2, development PC | twelve named tests in `pskr_tests.rs` |

One condition is written as planned, with no test yet: a report is given at once while the
feed waits on the network (TC-039-020 i).

## 10. Open points, gaps and disagreements

Marked by the model:

1. `SpotsService`, not stated: which connection brings spots what it needs from the rest
   of the station and takes its status: the two switches and `FeedStatus` (the station
   service), the profile's call, the target of a run's own contact, the station's band and
   mode, the confirmed dial and the range of transmit offsets of the mode. The part is
   joined to ranking, auto and qso by the hearing report and to the broker, and to nothing
   else.

Gaps found while writing this view:

1. `FeedStatus` and `FeedSwitches` are data of the function; no item on a port carries
   them (the marker above).
2. "The range of transmit offsets of the mode" has no element in the files read.
3. "Strategy run", "contest run" and "own contact" have no element in the files read; the
   target is said in words.
4. `Subscription` stands for a filter asked for and for one given up; no feature says
   which.
5. The model gives no value for "in time" of the greeting; the session's rules say only
   that the answer must come in time.

Disagreements: none between the files read.
