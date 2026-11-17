# Report: the udp part

2026-11-15. Built by a subagent beside the receive part. Tests 1 to 5 pass. Five lines
wait for the operator (last section but two).

## What was written

| File | Content |
|---|---|
| `backend/udp/Udp.sysml` | the part with four ports, its two modules, three markers |
| `interfaces/external/Udp.sysml` | the port toward the targets, 12 clauses, 17 rule and data elements, 4 enumerations, 12 test cases |

## Identities

All 24 identities of the ledger arrived in `interfaces/external/Udp.sysml`, where they
stood before. None is new, none retires.

| Identity | Element it names | Note |
|---|---|---|
| CL-040-01 | `OutboundRules`, `UdpWire` | Which message on which occasion. The wire layout is the source's and is not written. |
| CL-040-02 | `UdpConfiguration` (with `UdpTarget`, `TargetStatus`, `UdpSnapshot`) | The list and its file. The routes are handed over. Derives from FR-012 only (was FR-012, FR-001). |
| CL-040-06 | `Ipv6Multicast` | |
| CL-040-03 | `InboundRules` | Written in the positive: what the station takes. Derives from FR-012 only (was FR-012, FR-008). |
| CL-112-01 | `InstanceName` | The read-only display and the route field are handed over. |
| CL-040-07 | `StatusCadence` | |
| CL-112-02 | `StatusFields` | Holds every field of Status now, not only dial and report. |
| CL-040-04 | `DecodeFields` | Holds every field of Decode and which record gives one; the text form is its core. |
| CL-112-03 | `DeltaTime` | The record without a period start moved to `DecodeFields`. |
| CL-112-04 | `ClearRule` | |
| CL-112-05 | `LoggedFields` | Keeps point 2 and 3 (the exchanges, one record gives the same messages). Point 1, the activity field of the log record, is the log's and needs an identity there. |
| CL-112-06 | `CloseRule` | Holds Close on a changed list too, which stood under CL-040-01. |
| TC-012-001 to TC-012-004, TC-012-006, TC-012-007, TC-112-001 to TC-112-006 | | Rewritten from the tests: setup, then one lettered condition per line. |

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Where udp's clauses stand | M2.1 gives `backend/udp/` the part's own file only; M4.4: that file holds the part and its ports; M6.3: a clause about an exchange stands in the interface file with the interface as subject; the ledger names this file | All twelve in `interfaces/external/Udp.sysml`, subject `Udp`. See line 1 for the operator. |
| The wire layout (magic number, encodings, field order, type numbers, the 15 s pulse) | A followed format is referred to, not copied; a value of a source is not written | Named once on `Datagram`. `UdpWire` keeps the product's three choices. |
| The numbers of the special operation | A value of a source | "The source's number for the activity"; the mapping is qso's (handed over). |
| `UdpHttp`, the wire keys, the refusal order of the route, 8192 bytes | M4.7: routes and wire names are the transport file's | Handed over. What udp decides stays: which list is admitted, the revision, `ConfigurationRefusal`. |
| One FR for each clause | Method, "Decided" | FR-012. |
| The port carries a datagram outward only, yet a Heartbeat is read | Structure rule 1: what crosses is typed | `in item heartbeat : PeerHeartbeat` on `UdpPort`. |
| "Send-only", "no inbound message acts" | Negatives with care: a function exists that reads datagrams | CL-040-03 in the positive, with a default for every other datagram. |
| The dependency links | M7.1 | 31 dropped; subject, derivation and typed features carry them. |
| The source's version | START-HERE, traps | "WSJT-X at the behaviour baseline"; no release, no checksum. |
| `StationState`, `FinishedContact` are not udp's and have no feature | The brief: use what stands there | Three markers on the part's ports. |
| Element names | Names are identities; the code's names win | `OutboundRules`, `InboundRules`, `UdpWire`, `UdpTarget`, `UdpConfiguration`, `TargetStatus`, `InstanceName`, `UdpSnapshot` kept. |

## The values

| Value | Kept as | Why |
|---|---|---|
| 16 targets | `UdpConfiguration::targetsMax` | a limit of the promise; matched by the tool |
| schema 2 and 3 | `UdpWire::schemaOut`, `schemaMax` | the product's choice within the source's negotiation; matched by the tool |
| 4096 bytes | `UdpWire::inboundMaxBytes` | how the station tolerates an oversize datagram; matched by the tool |
| TTL 1 to 255, port 1 to 65535, index 1 to 4294967295 | constraint and sentences on `UdpTarget`, `Ipv6Multicast` | which target is admitted |
| 127.0.0.1:2237 | sentence in `UdpConfiguration` | the default list |
| 15 s pulse, message type numbers, magic number | not written | the source's |
| T/R period 15 and 7 | sentence in `StatusFields`, with a conflict marker | see line 3 for the operator |
| 64 datagrams read per look | dropped | tuning |
| 99 numbers tried for the name | dropped | rare and harmless |
| 65,536 bytes of `udp.json`, the revision's highest value and `counter_exhausted` | dropped | rare and harmless; no test |
| 8192 bytes body | handed over | the route's |
| 50 ms station step | dropped | the station service's; udp's rules name occasions |

## Dropped as code or as history

- The socket's own address and port (loopback or unspecified, ephemeral).
- "Written atomically (temporary file, flush, replace) under the profile's lock".
- The cursor of the decodes; kept as "each once" and "not sent afterwards".
- That the lock file is named after the name with other characters replaced.
- The package text of decisions D1 to D7, the quotations, dates, issue numbers,
  checksums and the release numbers.
- The explanation why the Status follows the decode windows in WSJT-X.
- "WSPRDecode is not applicable": covered by "no other message of the source is sent".
- "A killed process sends nothing": no function could.

## Renamed or moved

| Old | New | Cited by (measured) |
|---|---|---|
| item `UdpItem` | `Datagram` | none |
| `UdpHttp` | handed to the station link | 1 citation (`udp_tests.rs`) |
| `UdpTarget::multicastTtl`, `multicastInterface` and the other features | kept; their wire keys are the station link's | |
| `TargetStatus` as text | typed; `lastSendMs`, `TargetError` | none |
| `UdpWire::magic`, `heartbeatSeconds`, `outboundSchema`, `maximumSchema`, `inboundDatagramBytesMax` | `schemaOut`, `schemaMax`, `inboundMaxBytes` (the code's names); the first two are the source's and gone | 1 citation of `WstxUdp::UdpWire` |
| `InstanceName::lockFolder` | a sentence | none |
| the wire names `socket_unavailable`, `send_failed`, `invalid_configuration` | literals in the model's form | the station link maps them |

`WstxUdp` is cited 18 times in 10 code files; the package keeps its name.

## Negative statements

| Old statement | Result |
|---|---|
| Send-only; no inbound message acts | positive: CL-040-03 and `InboundRules`, shown by TC-012-003 |
| Never lowers the schema | kept in the positive form "the schema of a target is not lowered": a function raises it (TC-012-003 d) |
| No Clear on a mode change, a restart, a loss epoch, a stop, a new job, an Erase | one default: "every other change sends none"; the test's cases stand in TC-112-004 (d). An Erase in the browser reaches no function of udp: dropped, and the difference from WSJT-X is marked |
| A played recording sends no Decode | positive: "a played recording is no live job"; marked as a difference; TC-012-002 (g) |
| The name is not a setting; a radio change while running does not change it | "fixed once for the life of the process and is not a setting"; TC-112-001 (f) |
| A killed process sends nothing; never a "+" or a leading zero in the report | dropped: no function could; the report's form is stated |
| No datagram while the station has no name | kept as a rule of `OutboundRules`: the function that sends exists; TC-112-001 (g), TC-112-006 (b) |
| The exit does not delay the transmit release | positive: "transmission is released first"; TC-112-006 (a) |

## Settled from the code

- **Close** goes also to a target whose address, TTL or interface changes, and only to
  one that is active and selects close.
- **Decode needs a finite frequency and a text** besides the period start; written as
  "status decoded".
- **QSO Logged, mode**: the record's SUBMODE where its MODE is MFSK.
- **The rtty and field_day exchange** is taken from STX_STRING and SRX_STRING first, and
  put together from the report and the serial or state without them.
- **A band that is not named** keeps the last band: clearing the selection and choosing
  another band sends one Clear.
- **The multicast TTL** is asked of every target, also a unicast one.
- **A host name** is not an address.
- **Records published without an active target** are passed over.
- **The CAT model** is IC-7300 for every CAT connection (a constant of the code).

## What WSJT-X does (checked in `D:\Github\wsjtx`, tag v3.3.0-beta6)

| Topic | WSJT-X | The model |
|---|---|---|
| Schema negotiation | `MessageClient::parse_message` takes a higher schema from any datagram it accepts | difference recorded |
| Decodes of a played file | `postDecode` passes `m_diskData` as Off air | difference recorded |
| Clear | `band_activity_cleared` runs whenever the Band Activity window is erased (`DisplayText::erase`) | difference recorded; the old clause said "as WSJT-X" |
| Status at the pulse | `MessageClient::heartbeat` sends the Heartbeat only | difference recorded |
| T/R period | `statusUpdate` sends the highest value ("not applicable") when its T/R period control is not shown; FT8 and FT4 do not show it | **conflict marked**, line 3 for the operator |
| Report | `QString::number` of the report | followed |
| Delta time | parsed from the one-decimal decode line | followed |
| Instance | the name is the application name with the rig name; a second start with a held lock asks the operator | the station numbers the name instead; line 4 for the operator |

## What the comparison with the code found

| Finding | Result |
|---|---|
| Seven message type numbers are public constants | inside: the source's; 7 verdicts |
| `BODY_MAX` stands in `udp.rs` | the route's limit; handed over, 1 verdict |
| The modules have no public enumeration and no wire name the tool reads | 13 literals matched by reading |
| A value named `heartbeatSeconds` would have been compared with the type number `HEARTBEAT = 0` | not written: the pulse is the source's |
| The tests stand in `server/src/log/udp_tests.rs`, the code in `server/src/operating/qso/udp.rs` | work for the code |
| Two tests of the log (`tc_011_001`, `tc_011_002`) stand in udp's test file | TC-012-002 (h) cites what they show at udp's boundary; the cases are the log's |
| The decoding flag is set in `recording.rs` (receive) | receive's `ReceiveStatus::decoding` and `decode_windows`; TC-012-007 (e) binds the test |

## Edge cases and their homes

| Case | Home |
|---|---|
| 16 and 17 targets | `targetsMax`, TC-012-004 (c), (d) |
| TTL 0 and 256; port 0; unspecified and broadcast address | `UdpTarget`, TC-012-004 (c), TC-012-006 (a) |
| the same address twice; a message twice; an unknown message | `UdpTarget`, TC-012-004 (c) |
| interface index 0, with a sign, with a leading zero, above the range, a name | `Ipv6Multicast`, TC-012-006 (a) |
| an index no interface has | `TargetError::socketUnavailable`, TC-012-006 (d) |
| file missing, not understood, with old keys | `UdpConfiguration`, TC-012-004 (a), (e), (f) |
| the save fails | `ConfigurationRefusal::storageUnavailable`, TC-012-004 (g) |
| a list made from an old revision | `staleRevision`, TC-012-004 (c) |
| datagram of 4097 and of 5000 bytes; schema 1 and 4; id cut off or not UTF-8 | `InboundRules`, TC-012-001 (c), TC-012-003 (d) |
| Heartbeat from another address or with another id | `InboundRules`, TC-012-003 (c) |
| window begun and ended between two looks | `StatusCadence`, TC-012-007 (c) |
| 14 s and 15 s after the pulse | TC-012-007 (d) |
| record without a period start; without a DT; DT at a tie | `DecodeFields`, `DeltaTime`, TC-112-003 |
| two stations with one name; a killed holder; lock folder not usable | `InstanceName`, TC-112-001 (b), (c), (d) |
| a Flex session never ready | `InstanceName`, TC-112-001 (g), TC-112-006 (b) |
| a contact saved twice | `LoggedFields`, TC-012-002 (e), TC-112-005 (g) |
| an exchange with a missing part | `LoggedFields`, TC-112-005 (d) |
| more than 99 stations with one name; the revision at its highest value | rare and harmless: code |
| a send that fails | `TargetError::sendFailed`; no test |

## Not carried over

| What | Why |
|---|---|
| TC-012-004: another profile, another boot, an extra key of the envelope, v 2, text/plain, 8193 bytes, a query, the refusal order | the route; handed over to the station link |
| TC-012-003: the exact key lists of the snapshot | wire names; station link. The case keeps what the view carries |
| TC-112-005: the refusal of an invalid activity, `contacts.adi`, the export, the restart | the log's; handed over |
| The counts 8, 3 and 18 of the vector set | facts about the fixture |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| `backend/udp/Udp.sysml` | 500 | 2,424 |
| `interfaces/external/Udp.sysml` | 55,152 | 45,459 |
| Total | 55,652 | 47,883 |

The part is 14 % smaller than its old text.

| Content | Old | New |
|---|---|---|
| The twelve test cases (59 conditions) | 19,714 | 18,709 |
| The twelve clauses | 12,744 | 3,424 |
| Rule and data elements, port, part | 15,065 | 19,331 |
| The package text of decisions | 4,422 | in the elements |
| Imports, tags, derivations, test bindings | not measured apart | 6,419 |

## Checks

- `part_done.py udp`: all five tests pass: 24 identities, no finding of the script, no
  validator error, 4 values matched with the code and 21 lines with a verdict, 12 test
  cases with their tests.
- The validator on the whole new tree reports no error in the two files. The lines of
  `Station.sysml` that join `udp.decodes` and `udp.logged` have none; the line to
  `station.udp` fails on the station service's side (not built).
- Read in full before writing: `udp.rs`, `network_message.rs`, `udp_tests.rs`,
  `udp_vectors.rs` with the list of its vectors, the test of TC-012-007 in
  `recording_tests.rs`, and the callers in `main.rs`, `logbook_http.rs`, `contact_http.rs`,
  `recording.rs`, `contact.rs`.

## The functional description

`_descriptions/udp.md`, from the new files alone (21,024 characters). It lists four
markers and found five gaps; one was settled.

| Gap | Settled how |
|---|---|
| Which item tells of the decode windows | From the handover list of receive: `ReceiveStatus::decoding` and `decode_windows`, through the station service. Sentence and marker changed. |
| The pulse interval has no value | the source's |
| `Datagram` and `PeerHeartbeat` have no field | messages in the source's format |
| The activities are named in words | qso's vocabulary; handed over |
| All clauses name the interface | line 1 for the operator |

## Work for the code, when the new tree goes to main

- `udp.rs` moves out of `operating/qso/`, `udp_tests.rs` out of `log/`; the two log tests
  in it move to the log.
- The routes `GET /udp` and `PUT /udp` and `BODY_MAX` move to the station link's code.
- One comment names `WstxUdp::UdpHttp`.
- The tests read no value from the model.
- `Activity::special_operation` stands in `contact.rs`.

## For the main session

Rows for `_work/handover.md`, in its format:

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| station link | `GET /udp`: no query, no body; `{v 1, profile_id, boot_id, instance_name, revision, configuration {targets} or null, configuration_error, status [{address, active, schema, last_send_utc_ms, error}]}`; 404 without a UDP sender. `PUT /udp`: `{v, profile_id, boot_id, expected_revision, configuration {targets}}`, application/json, at most 8192 bytes (the code's `BODY_MAX` in `udp.rs`), no query; refusals in this order: 400 `invalid_request` for the envelope (a missing key named as field, an extra key without one), 400 `invalid_request` field v for a v that is no non-negative integer, 400 `unsupported_version` field v, 400 `invalid_request` for profile_id, boot_id, expected_revision, then the configuration's field (`configuration`, `targets`, `targets[i]`, `targets[i].<key>`), 403 `wrong_profile`, 409 `state_conflict` boot_id, 409 `stale_revision` expected_revision, 409 `counter_exhausted`, 503 `storage_unavailable`; 413 and 415. Accepted: 200 with the new snapshot. The wire keys of a target: address, enabled, multicast_ttl, multicast_interface, messages; the messages by the names of `WstxUdp::OutboundMessage`; the errors `socket_unavailable`, `send_failed`, `invalid_configuration`. The data is `WstxUdp::UdpSnapshot`, `UdpTarget`, `TargetStatus`, `ConfigurationRefused`. | CL-040-02, `UdpHttp`, TC-012-004, TC-012-003 | udp |
| station | The station service gives udp its state and the target list: `WstxStationCommands::StationState` has no feature and `StationStatusPort` carries nothing else (marker on udp's port `status`). Udp needs: the profile's call, locator, display name and radio control (CAT with an endpoint or not); the operating mode; the confirmed dial; the band and the nominal frequency of the operating selection; the contact's DX call, DX grid, report, next message, Rx and Tx offset and activity; armed, transmitting, watchdog expired; `ReceiveStatus::decoding`, `decode_windows` and the kind of the job; the model and slice letter of a ready Flex session; a new target list with the revision it was made from. Udp gives `UdpSnapshot` or `ConfigurationRefused`. The station service also tells udp when the process ends (`udp::exit` in `main.rs`). | `OutboundRules`, `UdpHttp`, CL-112-06 | udp |
| log | The log gives udp the stored record once, when it stores a contact for the first time: at completion or Log QSO, and by an explicit save with the outcome saved; not for a contact that is stored already and not for records added from an ADIF file. `CompletedContactPort` lets udp send a `LogAnswer`, which it never does, and `FinishedContact` has no feature (marker on udp's port `logged`). The activity of a record is the log's: the field APP_WSTXRUST_ACTIVITY (field_day, rtty, eu_vhf, na_vhf, ww_digi, arrl_digi, hound; absent for none), written after the contact id and the source, read back, refused as `log_invalid_field` `record.app_wstxrust_activity`, kept by Update logbook when valid, and a save that differs in the activity only is already saved. This is point 1 of CL-112-05 and **needs a new identity** in the log; CL-112-05 keeps the exchanges. The tests `tc_011_001_...` and `tc_011_002_...` stand in `server/src/log/udp_tests.rs`. | CL-112-05, TC-112-005, TC-011-001, TC-011-002 | udp |
| qso | The activities and the number WSJT-X gives each for the Status field Special operation (none 0, na_vhf 1, eu_vhf 2, field_day 3, rtty 4, ww_digi 5, hound 7, arrl_digi 8; `contact.rs` `Activity::special_operation`). Udp's `StatusFields` says "the source's number for the activity" and `LoggedFields` names the activities in words. | `OutboundRules`, CL-112-02 | udp |
| transmit | When the station process ends, transmission is released first and Close is sent afterwards; the release returns within 500 ms and waits for no send (`udp::exit`; ExitRelease). Shown by TC-112-006 (a). | CL-112-06 | udp |
| flexAdapter | The model and the slice letter of the session at its first ready name the UDP instance ("WSTX-Rust - FLEX-6600 A"). Udp has no connection to the Flex adapter; it gets them through the station service. | CL-112-01 | udp |
| radioControl | The CAT model in the instance name is the constant IC-7300 of `udp.rs`. The old text fixes the name "after radio discovery (CL-044-15) and before the server serves; if discovery moves the profile to another radio, the name takes that radio's model": the order at station start is the station service's and radio control's. | CL-112-01 | udp |
| receive | Udp takes `ResultRecord` over `Decodes` and uses of it: `sequence`, `status`, `text`, `fields` (a standard message, its acknowledgement and its report), `frequency_hz`, `snr_db`, `period_start_utc`, `dt_seconds`. It does not use `PeriodView`. Missing for udp: which job a record belongs to (source, job, generation), the job's mode and that the job is live, so that a played recording gives no Decode and a new job starts at its first record (marker on udp's port `decodes`). | CL-040-01, CL-112-03 | udp |
| frontend | Settings > Logging & Reporting shows the instance name as text ("not fixed yet" while there is none) and the list of targets with their status. | CL-112-01, CL-040-02 | udp |
| profile | `udp.json` lies in the profile's folder and is written under the profile's lock. Udp has no connection to the profile. | `UdpConfiguration` | udp |

Rows of `_work/handover.md` that are taken up (to mark "**Taken up**"):

- "udp | The lock per instance name": `WstxUdp::InstanceName`.
- "udp | The UDP Decode message carries the filled-in text unchanged": `WstxUdp::DecodeFields`, "a hashed call stands as the record gives it". An interface file cannot import `WstxMessagePayload::HashResolution` (M3.2); it is named in no import.
- "udp | Whether a window is being decoded and how many were begun": `WstxUdp::StatusCadence`; TC-012-007 (e) binds the test. That a window of a transmit period does not count is receive's and is not repeated.

Other files:

- `Station.sysml`: nothing must change for the part to be valid.
- `interfaces/internal/StationCommands.sysml` (the station service's): `StationState` needs the features listed in the row "station"; the target list and its answer need items on `StationStatusPort` or a port of their own (line 2 for the operator).
- `interfaces/internal/OperatingChain.sysml`: the connection `loggedContact` is typed by `CompletedContact`, whose port lets the consumer answer. Udp answers nothing.
- `interfaces/internal/Decodes.sysml`: no change asked in `ResultRecord`. What is missing is in the row "receive".
- `_work/files.md`: the two files are built.

## For the operator

1. **Answered (operator 2026-11-16), done properly: udp has its control interface `interfaces/internal/UdpControl.sysml` (M4.6, added to M2.1): `OutboundMessage`, `UdpTarget`, `UdpConfiguration`, `TargetError`, `TargetStatus`, `UdpSnapshot`, the new `UdpConfigured` and `UdpStationState` (what Status needs, in place of the empty `StationState`), the port and the interface `UdpControl`; `StationStatus` left `StationCommands.sysml`; `Station.sysml` connects `udpControl`. The function file `backend/udp/UdpSender.sysml` holds CL-040-02 with `TargetList` (the rules that stood in `UdpConfiguration`), CL-112-01 with `InstanceName`, TC-012-004 and TC-112-001, subject `UdpService`. `Udp.sysml` keeps the exchange; TC-012-002 verifies CL-040-01 and -04 only (CL-040-02 by TC-012-004). The marker on udp's port is gone. Line 2 is answered by the same change.** All twelve clauses of udp stand in the interface file `interfaces/external/Udp.sysml` and name the interface as subject, also those about the file `udp.json`, the lock of the instance name and the list of targets. M2.1 gives udp no function file, so M6.3 decided. WSJT-X: not applicable. Recommendation: keep it; if the operator wants the part to read like the others, add one function file `backend/udp/UdpSender.sysml` to M2.1 and move the elements that are not about the exchange (`UdpConfiguration`, `InstanceName`, `TargetStatus`) with their clauses.
2. **Answered with line 1: `UdpControl` carries `UdpConfigured` and `UdpStationState` in and `UdpSnapshot` out; the profile validates the list, so there is no refusal of udp's own.** How the target list reaches udp and how its answer returns: `StationStatus` carries the station state toward udp and nothing back. WSJT-X sets its one target in its settings dialog. Recommendation: when the station service is built, give `StationStatusPort` the items for it (in: the list with its revision; out: `UdpSnapshot`, `ConfigurationRefused`), typed by the elements of `WstxUdp`; until then the marker on udp's port `status` stands.
3. The T/R period of Status: the station sends 15 for FT8 and 7 for FT4; WSJT-X sends the value "not applicable" (4294967295) in FT8 and FT4, because its T/R period control is not shown in these modes (`statusUpdate`, read at tag v3.3.0-beta6). Nobody recorded this difference; the test and the vector ask for 15. Marked `@Conflict` on `StatusFields`. Recommendation: follow WSJT-X (a change of the code), because a program that reads the field expects what WSJT-X sends; or record the difference as deliberate.
4. **Answered by the station's name (operator 2026-11-16): the name is unique on the PC, so there is no clash.** The instance name on a clash: WSJT-X takes its name from the rig name given at its start and, when the lock is held, asks the operator; the station adds a number by itself. The model writes the station's rule and marks nothing, because the form of the name is not the protocol's. Recommendation: leave it unmarked.
5. **Decided on #112 (operator 2026-11-11, round 3): Clear only on a band change; Erase sends none; the difference is deliberate.** Clear: the old clause said "Clear only on a band change, as WSJT-X". WSJT-X sends Clear whenever its Band Activity window is erased, also by the operator. The model marks this as a deliberate difference, because the old clause lists the Erase among the cases without Clear. Recommendation: keep it so; confirm that it is deliberate.

## Not sure

- WSJT-X was read at the local tree, tag v3.3.0-beta6. `Requirements.sysml` names beta4
  as the behaviour baseline; the old text built the vectors from beta5.
- That FT8 and FT4 hide the T/R period control was read from the lists of shown controls
  in `on_actionFT8_triggered` and `on_actionFT4_triggered`; WSJT-X was not run.
- The events on which the process sends Close (interrupt, console close, logoff,
  shutdown) are taken from the one console handler in `server/src/modes/playback/windows.rs`,
  which takes every console event; the list of events is its comment's.
- `TargetStatus::lastSendMs` is named by the model's rule for units; the wire name is
  `last_send_utc_ms`.

## Not done

- Nothing outside `docs/sysmlV2` was touched. `_work/handover.md`, `_work/files.md`,
  `Station.sysml`, `StationCommands.sysml`, `OperatingChain.sysml` and `START-HERE.md` are
  not changed.

## Decided by the operator (2026-11-15)

| Line | Answer | Done |
|---|---|---|
| 3 | the T/R period of Status follows WSJT-X: not applicable in FT8 and FT4 | `StatusFields` says so; the `@Conflict` is gone; TC-012-002 (a) no longer names the period and (i) is "Planned, no test yet". The code and its vector send 15 and 7: a change request when the tree is on main |
| receive's job | from the period view | `PeriodView::job`; the marker on udp's port `decodes` is gone |

Open: lines 1, 2, 4, 5.

## Changed after the report: the settings (operator 2026-11-15)

The operator decided on 2026-11-15 how the settings of a station are sorted and stored:
three stores (the station config, the hidden store of the station, the config of each
frontend), with definition files and data files as files of their own; a setting and a
record are defined by the part that uses them, in that part's control interface; the
profile only stores them, as collections by type (`WstxProfileAccess::StationConfig`,
`StationMemory`); a change takes one way (operator, station service, profile, and back to
the part as its new configuration). The model states this; the code still has a file for
each function, and the difference is work for the code (a later issue). The sections above
are as they were written; where they name a file of the function's own, a set command or a
storage refusal, this section holds.

Measured by `measure.py` in the session's scratchpad, subfolder `settings` (the tree
against a copy made before the change).

| File | Lines | Characters |
|---|---|---|
| `interfaces/external/Udp.sysml` | 808 to 768 | 45,285 to 42,777 |
| `backend/udp/Udp.sysml` | 38 to 41 | 1,998 to 2,195 |
| `_descriptions/udp.md` | 352 to 343 | 21,024 to 20,415 |

The list of targets was udp's own element already (`WstxUdp::UdpConfiguration`); it is the
configuration type now, to which the profile refers.

| Element | What |
|---|---|
| `UdpConfiguration` | the configuration: `targets` and `targetsMax`; `revision` left. It says what the list is until the operator sets one (one target, 127.0.0.1:2237) and that the sockets follow a changed list at once |
| `UdpService` | one attribute: `configuration : UdpConfiguration`; the marker on its port `status` names the configuration in place of "a new target list with the revision it was made from" and of `ConfigurationRefused` |

Left:

| Element | What left |
|---|---|
| `UdpConfiguration` | the file `udp.json`; what a missing and a broken file mean; the two keys an older file may name; the revision of the list and "saved before it holds" |
| `ConfigurationError`, `ConfigurationRefusal`, `ConfigurationRefused` | the three elements: a file not understood, and the refusals of a new list (`invalidRequest`, `staleRevision`, `storageUnavailable`) |
| `UdpSnapshot` | `revision` and `configurationError`; `configuration` is always present |
| CL-040-02 | "and keep that list in the profile": the profile keeps it (CL-005-02). The clause says: send to every target of the list, and follow a changed list at once |
| TC-012-004 | the title "and its file"; in (a) "revision 0", "no error", "no file is written"; in (b) "revision 1" and "the same after a restart"; in (c) "a list made from revision 0", "nothing saved" and "a configuration that names instance_name"; in (d) "revision 2"; in (e) the broken file (the condition stays with the setup "while the station has no target"); (f) whole (a file that names `instance_name` and `accept_commands`); (g) whole (a save whose write fails). 7 to 5 lettered lines; the test file as before. The letters (f) and (g) are not used again |
| TC-012-004 | `verify 'CL-112-01'` left its objective: (f) and the last entry of (c) were what showed the instance name here; TC-112-001 verifies the clause |
| TC-012-003 (b) | "the revision" and "and its error" of the view; "and nothing else" |
| TC-012-006 (a) to (c) | "not taken ... and nothing saved", "saved as given, the same after a restart", "taken": said as what is a target of `UdpTarget` and what is none; 5 lettered lines as before |
| `CloseRule` | "a saved list" is "a changed list" |

The conditions of TC-012-004 (c) and TC-012-006 (a) stay: they show the rules of
`UdpTarget`, which are udp's. Who refuses a list outside them is the profile
(`SaveRefusal::invalid_settings`). No identity is retired or not carried.

Planned, no test yet: the profile keeps the list across a restart; the line stands in the
profile's TC-022-002 (k).

Verdicts in `parts.json` (test 4: 4 matched, 17 with a verdict; before 4 and 21): four
taken out, the model literals of `ConfigurationError` and `ConfigurationRefusal`. Test 4
shows no new line.

Differences in the code that test 4 does not show (work for the code):
`operating/qso/udp.rs` keeps `udp.json` with a revision of its own (`Owner::open`,
`Owner::put` with `stale_revision`, `storage_unavailable` and `invalid_request` with the
field `parse_config` names); `GET` and `PUT /udp`; the view gives `revision` and
`configuration_error`.

Not decided, for the operator: nothing of udp's own beyond the open lines of the report.
The name of each value of a target in `SaveRefused::field` is in the profile's marker.

Not verified: of `udp_tests.rs` the first 65 lines of
`tc_012_004_target_configuration_and_persistence` and the lines 925 to 953 were read; that
"the target gets Heartbeat and Status only" holds with an empty list as it does with a
broken file is taken from the rule of `DecodeFields` in the model (line 345 of `Udp.sysml`: a record published
while no target is active is not sent afterwards), not from a test with an empty list.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-012-004 (`UdpSender.sysml`): one target created, changed and deleted by its address (WstxProfileAccess::CreateEntry, UpdateEntry, DeleteEntry): the sender follows each at once; the other targets keep their sockets.
- TC-112-001 (`UdpSender.sysml`): a station named IC-7300: WSTX-Rust - IC-7300; one named FLEX-6600 A: WSTX-Rust - FLEX-6600 A, from station start on; the configuration name of Status is the station's name.
- TC-012-002 (`Udp.sysml`): the T/R period of Status as not applicable; the code and its test send 15 for FT8 and 7 for FT4.
- TC-012-002 (`Udp.sysml`): after (h), Log QSO (the log's ResendLast): QSO Logged and Logged ADIF of that contact once more.
