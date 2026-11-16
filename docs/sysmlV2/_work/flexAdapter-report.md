# Report: the Flex adapter part

2026-11-15. Built by a subagent beside the main session, by the method. Tests 1 to 5 pass.
Nothing was asked of the operator; the open lines are at the end, under "For the operator".

## What was written

| File | Content |
|---|---|
| `backend/flexAdapter/FlexAdapter.sysml` | the part with its three ports, its modules, its detail tests, three markers |
| `backend/flexAdapter/FlexSession.sysml` | 7 clauses, 11 data and rule elements, 2 actions, 3 enumerations, 3 test cases |
| `interfaces/external/FlexApi.sysml` | the API of the radio: 7 items, the 12 commands the station sends, the admitted version, the port, the interface |
| `_descriptions/flexAdapter.md` | the functional description, from the new files alone |
| `_work/ledger.md` | 12 rows of the part settled, 1 new row (CL-013-07) |
| `_work/parts.json` | the key `flexAdapter`: 3 files, 45 verdicts |

## What was read

In full: `server/src/flexAdapter/session.rs` (1597 lines), `wire.rs` (451), `flex/mod.rs`
(10), `session_tests.rs` (317), `wire_tests.rs` (233), `flex_http.rs` (87),
`tests/flexAdapter/native-flex.test.cjs` (728), `tests/flex-emulator.cjs` (288),
`tests/flex-live-check.cjs` (127). In part, at the places that name the session:
`main.rs`, `recording.rs`, `authorization_http.rs`, `radio_setup.rs`,
`receive/receive_startup.rs`, `profile.rs`, `profile_tests.rs`, `client/recording.js`.
The old model: the three old files in full. On GitHub (read only): issues 166, 168 and 212
for decisions already taken.

## Decisions of the operator found on the issues

They were taken before the rebuild and bind it; none was made here.

| Where | Decision | Effect here |
|---|---|---|
| issue 166, 2026-11-12 | The packet diagnostics stay the adapter's own, on its own route; radio control gets link and slice facts only | `StreamDiagnosis` is no part of `SessionStatus`; marker 1 on the part: no connection carries it yet |
| issue 166, 2026-11-12 | `GET /native-flex` and the push `radio.native` stay, keys unchanged | handed to the station link |
| issue 166, 2026-11-12 | No transmit port; Flex transmit is issue 167 | the part has no playback port; CL-013-05 says what holds now |
| issue 166, 2026-11-13 | The sample port is capture-only: "samples with gaps marked, plus input status" | `CaptureSamples` carries no input status yet: marker 3 and a change asked of the main session |
| issue 166, 2026-11-13 | The Flex adapter attaches to radio control directly; the authority stands only before the CAT adapter | as `Station.sysml` joins it; the binding `flexContext` there is to be looked at with radio control |
| issue 212 | Receive learns the Flex link only from its input, through audio | the same change of `CaptureSamples` |
| issue 168 | The conversion "adds CL-013-07 (the persisted native intent) to the profile tree" | the number is used here for the tuning; see the operator's line 3 |

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-013-01 | FlexSession | FlexSession | Core kept: the station's own session over the radio's network API, without a bridge program. Now also the state of the session, the authorization and the retry, from `NativeFlexWireSubset`. |
| CL-013-02 | FlexSession | FlexSession | Core kept: which radios are taken up. The admitted version; model and firmware are shown and not judged. |
| CL-013-03 | FlexSession | FlexSession | The session half: built from the intent alone, nothing taken that is not free or the adapter's own. The stored intent is the profile's half and is handed over. |
| CL-013-04 | FlexSession | FlexSession | Core kept: only the own slice and the own stream; a shortage is reported. |
| CL-013-05 | FlexSession | FlexSession | **Meaning narrowed.** Old: shared transmit authority is coordinated before transmit is enabled. The code has no transmit on this connection. New: the adapter sends the commands of its receive session and no other. Derives from FR-023 only (was FR-008, FR-009, FR-023). Operator's line 2. |
| CL-013-06 | FlexSession | FlexSession | Core kept in the adapter's half: the same receive path as any radio connection. Here: the stream to audio in audio's packet form. The halves of the profile, the station and the browser are handed over. |
| **CL-013-07** | new | FlexSession | The tuning of the slice, from `NativeFlexWireSubset` (Tuning, Read first), which had no number. |
| TC-023-001 | FlexSession | FlexSession | Rewritten from its 14 tests in `native-flex.test.cjs` and 10 named Rust tests: 23 conditions and 1 planned. |
| TC-023-002 | FlexSession | FlexSession | Rewritten from its tests: 9 conditions and 1 planned. |
| TC-023-003 | FlexSession | FlexSession | Its adapter conditions: 4, and 4 planned. Its browser, profile and transmit steps are handed over. Verifies no FR any more (was FR-008, FR-009, FR-023). |
| TC-023-004, -005 | FlexSession | not carried | Planned, live on a FlexRadio, no test. |
| TC-023-006 | FlexSession | not carried | Planned, a transmission on a FlexRadio, no test. |
| `NativeFlexWireSubset`, `NativeFlexBoundary` | FlexSession | dissolved | Two requirements without a number, 14,418 characters. Their content went into the seven clauses' elements, to the handover list, or was dropped (below). |

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| One function file | M2.1 names `FlexAdapter` and `FlexSession` | Everything of the session stands in `FlexSession`. |
| The API is referred to, not copied | data rule for a followed format | The source is named once, on `FlexApiPort`. No layout, port number or packet class is written. The 12 commands the station sends are an enumeration with the source's text for each. |
| The admitted version | one fact, one place | `ProtocolVersion::admitted` in the interface file; the source reference and `ApiAdmission` name it. |
| All clauses are `implemented` | a clause's status follows the code: built and tested | Old: all `partial`. No test runs against a real radio; the emulator tests are the evidence. |
| TC-023-004, -005, -006 not carried | a case is written only when a test exists | Listed in the ledger. |
| Test cases keep their three numbers and verify several clauses | M6.7, the tags in the code | The tests carry TC-023-001 to -003 in their names; a new case number would stand in no test file. |
| The tests of the live check script are no conditions | a case shows something at a part boundary | Six tests of `native-flex.test.cjs` test the script `flex-live-check.cjs` (stops when the radio is held, reports a slice left behind). Only what they show of the product is written: TC-023-001 (k). |
| Promises without a test | noted in the test case as "Planned, no test yet" | Six lines: TC-023-001 (x), TC-023-002 (j), TC-023-003 (e) to (h). |
| CL-013-07 | a new identity takes the next free number of its series | The tuning clause. |
| One FR for each clause | a clause derives from the one FR its part serves | FR-023 for all seven. |
| The session's states are an enumeration with rules, no state machine | behaviour rule 9 and the finished examples (audio) | `SessionState`, `SessionLifecycle`. |
| The old `@Conflict` on the part ("native Flex adds no part") | M2.2 names the part | Removed; `WstxArchitecture` is no package of the new tree. |
| The old `@Conflict` on `nativeSamples` | the handover row from audio | Answered: the samples go to audio's port `native`. |
| Where the status, the intent and the tune cross | M5.3, M5.6; the connection `nativeControl` has no interface | Not decided here. Port `control` keeps `~RadioControl`; marker 2 names what is missing. |
| The session data stand in the function file | data follows its users; the interface that would carry them is not built | `SessionStatus`, `SessionState`, `SessionError`, `RadioFacts`, `SliceFacts`, `TuneRefusal`, `NativeIntent` move to the interface of `nativeControl` when radio control is built. |

## Dropped as code or as history

- The bounds on lines, commands and datagrams (4096, 1024, 16384 bytes), the limit of 64
  tracked clients, slices and streams, one command's number, the read loop and its waits,
  the size of the receive buffer.
- Every value of the source: the ports 4992, 4991 and 4993, the packet type, the vendor
  identifier, the packet classes, 128 frames a packet, the three capacity codes as
  values (they stand in one sentence of `SessionSetup`, as the product's reading of them).
- The frequency range of a tune (30 kHz to 74.8 MHz) and the refusal `invalid_request`:
  the station's bands lie inside, no request causes it.
- The smoothing of the jitter, the announcement's count of free slices (read, not used).
- Measurements and their dates: the reorder and loss rates of a routed path, the decode
  counts of a comparison, the frozen time stamp of one radio, the list "FLEX-6600,
  firmware 4.3.16.42034, 4 slices", the checksum of the reference archive.
- "No vendor code is translated, linked, run or redistributed": a rule for the code's
  making, not a promise of the product.
- From `NativeFlexBoundary`: the common connector that is not built, "an in-process mutex
  is insufficient", "no fixed four-client promise", "Phase 2": no code and no test.
- The test double of the session.
- All dates, issue numbers and names of persons.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| requirement `NativeFlexWireSubset` | dissolved | comments in `session.rs`, `wire.rs`, `flex-emulator.cjs`; `tools/sysml` may name it |
| requirement `NativeFlexBoundary` | dissolved | comments in `flex/mod.rs`, `session.rs` |
| `FlexApiItem`, `item exchange` of `FlexApi` | seven typed items on `FlexApiPort` | `Context.sysml` uses `FlexApiPort` and `FlexApi` only (validated) |
| code `State`, `Error` | `SessionState`, `SessionError` (the 16 that a session can fail with), `TuneRefusal` (the four codes of `Error::selection_code`) | the model splits what the code holds in one enumeration |
| code `Snapshot` | `SessionStatus` and, apart, `StreamDiagnosis` | operator, issue 166 |
| code `Intent` | `NativeIntent` | |
| code `Counters` and the measurement fields of `Snapshot` | `StreamDiagnosis` | wire names `vita.tsi` → `timestampKind`, `vita.host_minus_radio_ms` → `hostMinusRadioMs` |

## Negative statements

| Old statement | Result |
|---|---|
| MUST NOT require SmartSDR, SmartSDR CAT or DAX as bridges | positive: the adapter holds its session over the radio's own network API (CL-013-01) |
| never sends client disconnect, start_persistence on, load_from, tx, xmit | kept as a rule over a closed set: the adapter sends the commands of `Command` and no other (CL-013-05). The function that writes a command could send any text; TC-023-001 (h) shows it. |
| discovery never sends a datagram | kept in one sentence on `Announcement` ("the station sends none and asks for none"): the adapter does send datagrams (`Registration`), so the case exists |
| no radio identity saved; the serial never saved or compared | positive: `RadioFacts` are shown and compared with nothing; the stored half is the profile's |
| a changed slice index MUST NOT redirect a station to another's slice | positive: a handle, slice number or stream identity of an earlier session counts for nothing (`OwnResources`) |
| no takeover of a client identity | positive: the attempt ends before `clientGui` is sent |
| without stealing another profile's slice | positive: what another client holds stays as it is |
| VITA time stamps are not used | kept: "measured and not used"; the adapter reads them |
| datagrams from another address are never accepted | positive: the rule of acceptance in `OwnResources` |
| reconnect MUST NOT replay an old transmit request | dropped: no transmit function on this connection |
| Monitor-off and receive state do not affect the session | dropped: nothing joins receive to the adapter |
| the standard path never opens a native socket | structure: the part is `[0..1]`; handed to the station |
| no request accepts a slice, stream or handle as authority | the station link's; handed over |

## Settled from the code

- **Channels.** The old text said "channel 0 only" enters the queue. The adapter gives
  both channels; audio uses channel 0.
- **Lost packets.** The old text: "becomes silence". The code writes zeros as samples and
  does not mark them: `NativePacket::silent` is never set, so audio's marks of
  zero-filled frames stay 0 and only `StreamDiagnosis::lost` counts the loss. Written as
  it is; operator's line 4.
- **Groups.** Old: "groups of at least 10 ms". A packet that brings a discontinuity ends
  the group before it early.
- **Discovering.** The state is entered at the start of every attempt, also with a saved
  address.
- **The info answer.** On a saved address a failed `info` is passed over; the radio's
  facts then stay empty.
- **The tune's deadline** is the request's, and at most 5 s.
- **The push's size.** The old text names 4096 bytes for `radio.native`. `main.rs` sends
  an optional push only up to 2048 bytes of text. The station link's to settle.
- **The startup resume.** The old text names `radio_unavailable` after the wait; a test
  shows it (see "For the main session", row 5).
- **`intent_domains`** in `session_tests.rs` carries no tag; it is bound by name in
  TC-023-002 (i).

## What the comparison with the code found

| Finding | Result |
|---|---|
| The adapter's nine values are private constants, fields or numbers in a function; the tool reads public constants only | 9 verdicts "matched by reading", each naming the constant |
| `CONTROL_PORT`, `DISCOVERY_PORT` | values of the source: not written, 2 verdicts |
| `MAX_LINE`, `MAX_COMMAND`, `MAX_DATAGRAM` | inside, 3 verdicts |
| The 12 commands are text in the code | 12 verdicts, each naming the text and the function |
| `Error` has 22 variants; 16 are `SessionError`, `Cancelled` is in `TuneRefusal`; `Unauthorized` and `Stopped` are states | `NotReady`, `Busy`: matched by reading (radioUnavailable); `InvalidRequest`: inside |
| The tool keys a literal by its name alone | `unauthorized` and `stopped` matched `Error::Unauthorized` and `Error::Stopped`; read: `State` has exactly the seven literals of `SessionState` |
| `WireError` (10 variants), the enumeration `Line` | inside or matched by reading, 16 verdicts; the tool reads `Line` only to the fields of its variant `Reply` |
| The capture state of the native connection (`NativeInput`) stands in `session.rs` | In the model it is audio's; handed over. Work for the code. |
| The band selection (`recording.rs`) calls the adapter's tune directly, and `authorization_http.rs` sets the authorization | In the model both come over `control` from radio control. Work for the code. |
| `flex_http.rs` (the route, the push, the radio object of the selection) | The station link's; not a module of this part. |
| The two environment variables are read in `main.rs` | Named in `RadioChoice`; the tool does not look in `main.rs`. |

Counts of test 4: 27 names matched by the tool, 45 lines with a verdict (28 matched by
reading, 15 inside, 2 values of the source).

## Edge cases and their homes

| Case | Home |
|---|---|
| no radio; only full radios; cannot listen | `RadioChoice`; TC-023-002 (e), (f), TC-023-003 (b); (h) planned |
| a radio on another version | `ApiAdmission`, TC-023-003 (c) |
| the client identity in use; a slice already under the new handle | `SessionSetup` 3 and 4, TC-023-002 (c), (d) |
| no slice free; no DAX channel free; another antenna | `SessionSetup` 6 and 7, TC-023-003 (a); (e), (f) planned |
| two stations choose one DAX channel | `OwnResources`, TC-023-001 (r) |
| the radio restarts with other handles and numbers; old stream identities go on | `OwnResources`, TC-023-002 (a) |
| the slice or the stream is taken from a ready session | `SessionLifecycle` (resourceLost); TC-023-003 (g) planned |
| the authorization goes while ready | `SessionLifecycle`, TC-023-002 (h) |
| a packet out of order, within and beyond 5 places | `StreamIntake`, TC-023-001 (o), (s) |
| a packet twice | `StreamIntake`, TC-023-001 (t) |
| 7 and 8 packets lost in a row | `StreamIntake`, TC-023-001 (t). At 8 the stream falls short with no epoch: stated, operator's line 8 |
| a pause above 200 ms; the count shifted by it | `StreamIntake`, TC-023-001 (l), (m), (u) |
| a packet from another address or stream | `OwnResources`, TC-023-001 (b), (g) |
| a packet of another format; a sample not finite | `StreamIntake`, TC-023-001 (w) |
| the PC clock cannot be read | `StreamIntake` (the time runs on; else absent); rare, no condition |
| audio does not take the packets | audio's (`CaptureStream::queueMs`); the frame count runs on |
| a tune to the frequency the slice has | `TuneSlice`, TC-023-001 (d) |
| a radio that answers a tune and reports nothing; a slow path | `TuneSlice`, TC-023-001 (e), (n) |
| a tune outside ready; a tune withdrawn; two tunes at once | `TuneRefusal`; TC-023-001 (x) planned; the second of two is radioUnavailable, no condition |
| a frequency outside 30 kHz to 74.8 MHz | cannot occur from the station's bands; code |
| a line or datagram beyond the bounds | default: protocolError, or counted invalid; code |
| the session lost during a tune | `TuneRefusal::radioUnavailable`; no condition |

## Not carried over

| What | Why |
|---|---|
| TC-023-004, TC-023-005, TC-023-006 | planned, no test |
| The six tests of the live check script, but for (k) | they test a test tool |
| "the emulator sends what a real FLEX-6600 sent" | a test of the emulator |
| The design notes of `NativeFlexBoundary` | no code, no test |

## Size

Measured in characters by a script (`measure.py` in the session's scratchpad).

| | Old | New |
|---|---|---|
| `FlexAdapter.sysml` | 722 | 2,404 |
| `FlexSession.sysml` | 36,536 | 36,993 |
| `FlexApi.sysml` | 385 | 5,683 |
| Total | 37,643 | 45,080 |

The part is 7,437 characters larger than its old text. Where the size sits:

| Content | Old | New |
|---|---|---|
| The clauses (old: 6 numbered and 2 without a number; new: 7) | 18,417 | 2,539 |
| The data and rule elements of the clauses (11 attribute definitions, 2 actions, 3 enumerations) | none | 20,509 |
| The test cases (old: 6, of them 3 planned; new: 3) | 16,779 | 11,981 |
| The interface file, whose port carried one empty item before | 385 | 5,683 |

The growth is the interface file (5,298) and the typed elements: what was one paragraph
of 13,338 characters is now seven sentences and sixteen elements. The test cases are
4,798 shorter although they carry 36 conditions and 6 planned lines; the old three ran
to 13,355 characters without a letter.

## Checks

- `part_done.py flexAdapter`: all five tests pass: 13 identities, no finding of the
  script in 3 files, no validator error in 3 files, 27 names matched and 45 lines with a
  verdict, 3 test cases with their tests. `part_done.py clock`, `modes` and `audio`
  still pass.
- The validator on the whole new tree: no error on a line of the three files, on the
  line of `Station.sysml` that joins `audio.native` to `flexAdapter.samples`, or on the
  lines of `Context.sysml` that join `flexAdapter.radio`. The line of `nativeControl`
  and of the binding `flexContext` have errors that name radio control's ports and types,
  which are not built.
- `check.py` on the whole tree: no finding names a file of this part.
- `git status`: `docs/sysmlV2/` is the only change.
- Not run: no Rust or Node test was run. The conditions are written from the tests as
  read, not from a run.

## The functional description

`_descriptions/flexAdapter.md`, from the new files alone. The first writing found two
gaps, repaired in the model: the error of a refused `streamCreate` (radioRefused), and
the state `discovering` on a saved address. Three observations stay: the model has no
frequency range for a tune (the radio's refusal decides); three items of the API carry no
typed field (their content is the source's); "the frequency last confirmed" is no data
element. The three markers are its open points.

## Markers

| # | Where | `NotStated` |
|---|---|---|
| 1 | part `FlexAdapter` | which connection carries `StreamDiagnosis` out of the adapter |
| 2 | port `control` | which items carry `NativeIntent`, the authorization, the tune and `SessionStatus` |
| 3 | port `samples` | which item carries the input status to audio |

## The control side: what the adapter needs from radio control's interface

Written against `interfaces/internal/RadioControl.sysml` as it stands (a taken-over copy):
the port `control` is `~RadioControl`, with `request : ControlRequest` in and
`outcome : ControlOutcome` out. None of its requests fits; what is needed:

| # | Direction | What | In the code today |
|---|---|---|---|
| 1 | in | the profile's intent (`NativeIntent`), once, at station start | `main.rs` gives it to `Session::start` |
| 2 | in | the station's authorization to reach the radio, on and off at any time | `authorization_http.rs` calls `set_allowed` with the grant of the profile's scope |
| 3 | in | a tune: the frequency in Hz, a deadline, and a way to withdraw it | `recording.rs` calls `Session::tune` with a deadline of 5 s and the selection's cancel flag |
| 4 | out | the answer to that tune: the confirmed frequency, or one of `TuneRefusal` | `Result<u64, Error>` and `Error::selection_code` |
| 5 | out | `SessionStatus` at every change | `Session::snapshot` and `revision`, read by `flex_http.rs` |

`RadioResultStatus` (confirmed, unavailable, unsupported, rejected, failed) has no value
for a timeout and none for a withdrawn request. `ApplyRadioSettings` carries a whole
`RadioSettings`; the adapter takes a frequency and sets the mode DIGU itself.

To revisit when radio control is built:

1. The interface that types `nativeControl`; then markers 1 and 2, and the home of
   `SessionState`, `SessionError`, `SessionStatus`, `RadioFacts`, `SliceFacts`,
   `TuneRefusal` and `NativeIntent` (data that crosses a connection belongs to its
   interface file).
2. The binding `flexContext` of `Station.sysml` (`flexAdapter.control.request
   .resourceContext = radioBinding`): the adapter uses no resource context; the operator
   put the authority before the CAT adapter only.
3. The frequency range of a tune: the code has 30 kHz to 74.8 MHz, the numbers of
   `CatRequest`.
4. `SliceFacts::observedAt` and `SessionStatus::session` are what the code gives the
   radio object of the selection as `observed_at_ms` and `connection_generation`; the
   mapping of `SessionState` to that object's state stands in `flex_http.rs`.
5. "Read first" in `TuneSlice` is the rule radio control has for CAT; one of the two
   should name the other.
6. Detect radio and the CAT discovery are refused on a native profile (`radio_setup.rs`).
7. The readiness of the radio as one state (issue 132) and what a not-usable radio means
   for receive on a native profile (issue 212).

## Work for the code, when the new tree goes to main

- `NativeInput` (the capture state of the native connection) moves from the Flex module
  to audio; the adapter gives packets and an input status.
- The tune and the authorization reach the adapter through radio control, not from
  `recording.rs` and `authorization_http.rs`.
- The comments in `session.rs`, `wire.rs`, `flex/mod.rs` and `flex-emulator.cjs` name
  `WstxFlexSession::NativeFlexWireSubset` and `NativeFlexBoundary`, which are dissolved.
- The tests carry no tag of CL-013-07; `intent_domains` carries none at all; the six
  live check tests carry case numbers and are tool tests.
- `server/src/flex/mod.rs` and `server/src/flexAdapter/` are two folders for one part.
- No test reads a value from the model.

## For the main session

### Handover rows (in the table's format)

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| station link | `GET /native-flex` (no query, no body; `not_found` on a profile of the sound device connection) and the push `radio.native` (to each peer once as its snapshot, then at each change of `SessionStatus`, not for the stream diagnosis). Keys of both: `profile_id, boot_id, state, error, radio_code` (8 hexadecimal digits), `session, radio {serial, model, firmware, protocol, address}, slice {index, letter, frequency_hz, mode, rx_antenna, dax_channel, stream_id}, retry_after_ms, transmit` (always `unsupported`); the snapshot adds `v, packets {accepted, foreign, invalid, lost, late}, last_peak, vita {tsi, host_minus_radio_ms}, arrival {jitter_mean_ms, jitter_max_ms}`. The wire names of `SessionState` and `SessionError` are their snake_case forms. In `/receive/selection`: `control` is `native`, `selection.origin` is `native_readback`, and the `radio` object has `connection_generation` = `SessionStatus::session`, the state ready, connecting (discovering, connecting), closed (stopped, unauthorized) or unavailable (unavailable, conflict), the session's error, and the frequency only while ready. `/receive` `audio.device_id` is `native_flex`. Operator on issue 166: route and push stay, keys unchanged. The old text names 4096 bytes for the push; `main.rs` takes an optional push up to 2048 bytes of text. "No request accepts a slice, stream or handle as authority" is a negative; decide by the rule. | `NativeFlexWireSubset` (Push, Read first), TC-023-001, TC-023-003; `flex_http.rs` | flexAdapter |
| frontend | The status line of the native connection: in the receive details below the operating radio line, not in the top bar; "Native FlexRadio <state> · <error> · <model firmware serial address API> · slice <letter frequency mode antenna> · transmit unsupported"; "Native FlexRadio status stale · station disconnected" on a lost station link; the error-field entry `nativeRadio` while the session is not ready, which opens the line; "No audio input" does not apply to a native profile; the connection type is shown and cannot be changed (Standard, Native FlexRadio); no page scroll at 1366x768; the page sends no request for the status. | `NativeFlexWireSubset` (Push), TC-023-003; `client/recording.js`, `client/app.js` | flexAdapter |
| profile | The stored intent: `connection_type` `native_flex`, schema version 2, `native {client_id, rx_antenna, radio_address}` with `radio_address` optional, an IPv4 address with a port other than 0; no radio identity, slice number, handle or stream identity is stored; a native profile names no audio device and no CAT control (refused by field: `audio.input_device`, `audio.output_device`, `control.mode`, `control.endpoint`, `control.ptt`); the connection type is chosen at creation (`--create-native-flex-profile <directory> <rx antenna> [<address:port>]`) with a new client identity. The form the adapter takes is `WstxFlexSession::NativeIntent`. This is the profile's half of CL-013-03 and **needs a new identity**: CL-013-07 is the tuning clause now, the next free is CL-013-08. Tests: `profile_tests.rs` `native_schema_two_document_is_exact_and_standard_schema_one_is_unchanged` and `native_profile_creation_persists_intent_without_runtime_handles` (tagged TC-023-002), and the last step of the first TC-023-002 test in `native-flex.test.cjs` (the file unchanged, keys `client_id` and `rx_antenna` only). | CL-013-03, `NativeFlexWireSubset` (Profile), TC-023-002; `profile.rs` | flexAdapter |
| station | A profile of the native connection starts the Flex adapter at station start with the profile's intent; an intent the adapter does not take ends the start with `resource_unavailable`. A profile of the sound device connection has no Flex adapter and opens no connection to a radio it could hear (TC-023-003, mixed profiles). The environment variables `WSTX_FLEX_DISCOVERY` and `WSTX_FLEX_REGISTER_PORT` are read at station start (`main.rs`); a value that cannot be read is `invalid_runtime_configuration`. The authorization the adapter waits for is the grant of the profile's scope, as for automatic CAT; without one nothing reaches a radio, and when the last one is withdrawn the session is closed (TC-023-002 (h)). | CL-013-01, CL-013-06, `NativeFlexWireSubset` (Authorization); `main.rs`, `authorization_http.rs` | flexAdapter |
| station | **Startup, a correction to the row "The startup function, whole":** a test shows the Flex wait and `radio_unavailable`. `native-flex.test.cjs`, "CL-045-02 a native station resumes its receive at startup, waiting a bounded time for its session": a spectrum choice resumes `started`; a band choice resumes and the new slice stands on the band's frequency; with no radio the resume ends `failed` with `radio_unavailable` after more than 15 s and less than 30 s. | CL-045-02, TC-023-002; `receive_startup.rs` | flexAdapter |
| audio, receive | The capture on the native connection. A start while the session is not ready is refused (`radio_unavailable` on `/receive/start`). A running capture outlasts a lost session: its state is unavailable with `SourceError::unavailable` and the session's `retryAfterMs`, and it runs on without a request in a new epoch (`captureLoss`, `nativeDiscontinuity`) with the first packet of the next session (TC-023-002 (b)). It has no opening and no closing state. `CaptureMarks::zeroFilledFrames` stays 0 there: the adapter fills a lost stream packet with zeros and does not mark them silent. In the code this state stands in the Flex module (`NativeInput` in `session.rs`). Operator on issue 166: the capture-only port carries "samples with gaps marked, plus input status"; issue 212: receive learns the link only from its input, through audio. | `NativeFlexWireSubset` (Loss, Samples), TC-023-002; `session.rs`, `recording.rs` | flexAdapter |
| transmit | On a profile of the native connection transmit is not offered: the capability is `unsupported`, Enable Tx is refused, HALT and Abort answer as on a station without transmit configuration (TC-023-003 compares the two). The Flex adapter has no playback port and sends no keying command (CL-013-05). Flex transmit is issue 167. | CL-013-05, `NativeFlexWireSubset` (Transmit), TC-023-003, TC-023-006 | flexAdapter |
| radioControl | The control side of the Flex adapter: the five things it needs over `nativeControl` and the seven points to revisit, in `_work/flexAdapter-report.md`. Detect radio is refused on a native profile (`invalid_request`). | `NativeFlexWireSubset` (Tuning, Read first), TC-023-003; `recording.rs`, `radio_setup.rs` | flexAdapter |

For the table "Test cases handed over":

| Test case | Shows | To |
|---|---|---|
| TC-023-003, its mixed-profile and browser steps | a station of the sound device connection beside a native one: `/native-flex` 404, `control` manual and native, the unchanged `audio_unconfigured`; the same answers of the transmit safety on both; the refused profile edits and Detect radio; the status line, the error-field entry and the page | station link, profile, transmit, radioControl, frontend |
| "CL-045-02 a native station resumes its receive at startup" (`native-flex.test.cjs`) | the resume on a native profile | station |
| TC-023-002, its last step and the two tests of `profile_tests.rs` | the stored intent | profile |

The row "flexAdapter" of the handover list (from audio) is taken up: **Taken up:**
CL-013-06 and `WstxFlexSession::StreamIntake` (24 kHz to 48 kHz, the order of the packets,
lost and late ones, `discontinuity`, `arrivalTime`), CL-013-01 and `SessionLifecycle`
(the state of the session). "A Flex profile has no sound device, no endpoint list and no
playback" is structure: the adapter has no such port.

### Changes asked in files this part may not edit

1. `interfaces/internal/AudioStreams.sysml`, port `CaptureSamples`: the input status the
   operator decided on issue 166. Proposed, word for word:

   ```
   item def InputStatus {
       doc /* Whether the connection can deliver packets now. */
       attribute available : Boolean;
       attribute retryAfterMs : Integer[0..1] {
           doc /* The time to the connection's next attempt. Absent while it is
                available, and when no attempt is planned. */ }
   }
   port def CaptureSamples {
       doc /* Written from the side that delivers the packets. */
       out item format : NativeFormat;
       out item packet : NativePacket;
       out item input : InputStatus;
   }
   ```

   With it, marker 3 on `FlexAdapter::samples` goes, and `StreamIntake` gets one
   sentence: "The input is available in the state ready; outside it
   InputStatus::retryAfterMs is SessionStatus::retryAfterMs."
2. `backend/audio/` (built): one rule for the capture on the native connection, from the
   row "audio, receive" above; it closes gap 2 of `_descriptions/audio.md`.
3. `Station.sysml`: no line needs a change for this part; the ports are still `control`,
   `samples` and `radio`. Open there: the interface of `nativeControl` and the binding
   `flexContext` (with radio control), and a connection for `StreamDiagnosis` (the
   operator's line 1).
4. `_work/files.md`: the three files of this part are rebuilt.
5. `START-HERE.md`: the state table (flexAdapter: tests 1 to 5 pass); the ledger count
   rises by 10 arrived identities (6 clauses of the old model, 1 new clause, 3 test
   cases), 3 not carried.
6. `_work/parts.json`: the key `flexAdapter` was removed once by another session's write
   of the whole file while this part was built, and put back. It should be checked once
   more when all sessions are done; the block is kept in `mykey.py` in the scratchpad.

## For the operator

One line each, with a recommendation. WSJT-X has no native FlexRadio connection: it
reaches a FlexRadio through Hamlib CAT and a sound device, so it gives no answer to lines
1 to 8; where it says something, the line names it.

1. **Where the stream diagnosis leaves the adapter.** Issue 166 keeps it the adapter's own,
   on its own route, apart from radio control; the target structure lets state pass only
   through the station service, and the adapter has no port toward it (marker 1).
   Recommendation: a status port on the adapter joined to the station service, as audio
   has, for `StreamDiagnosis`; radio control gets `SessionStatus`. WSJT-X keeps the
   diagnostics of its sound input apart from the transceiver state.
2. **CL-013-05 says something narrower than before.** Old: shared transmit authority is
   coordinated before transmit is enabled. New: the adapter sends the commands of its
   receive session and no other. Recommendation: keep the number on this sentence;
   transmit coordination gets its own clauses with issue 167. The other way: retire
   CL-013-05 and give the sentence a new number.
3. **CL-013-07 is the tuning clause.** Issue 168 had foreseen that number for the stored
   intent in the profile. Recommendation: keep it here, since the number stood in no model
   file; the profile takes CL-013-08.
4. **A lost stream packet is filled with zeros that audio takes as samples.** Receive's
   window marks do not see them; only `StreamDiagnosis::lost` counts. The model says what
   the code does. Recommendation: a change request for the code, to mark the filled
   frames `silent`, which means exactly this in `NativePacket`; then a window with filled
   frames is known to receive.
5. **Nine values are kept.** `stepSeconds` 5, `firstRetryMs` 1000, `maxRetryMs` 4000,
   `listenSeconds` 3, `keepAliveSeconds` 5, `outputRateHz` 48000, `reorderPackets` 5,
   `unknownGapMs` 200, `groupMs` 10. Recommendation: keep the first three and
   `outputRateHz`, `reorderPackets`, `unknownGapMs` (each is seen at the boundary: the
   timing of the status, the format, the counts, the break of an epoch); cut
   `listenSeconds`, `keepAliveSeconds` and `groupMs` as code if a shorter model is
   wanted (no test asserts 3 s or 10 ms; one asserts a second registration within 8 s).
6. **The two environment variables** are named in `RadioChoice`, as the clock names its
   own; the code reads them at station start in `main.rs`. Recommendation: keep them
   here, they set this part only.
7. **The live check script** (`tests/flex-live-check.cjs`) is the method of the planned
   live cases TC-023-004 and -005, which are not carried. Its six tests against the
   emulator are tool tests. Recommendation: no case until a run on a radio is a test in
   the tree.
8. **Eight or more packets lost in a row within 200 ms** shorten the stream by up to 16
   packets (85 ms) without a new epoch; the model states the rule as the code and its
   test have it. Recommendation: accept; the shift is once and far inside what a decode
   tolerates.
9. **All seven clauses are `implemented`** by the rule, on emulator tests alone; that the
   radio releases a client's slice when the connection closes is shown only by the
   emulator. For information.

## Not sure

- Whether the 16 members of `SessionError` are exactly those a session can fail with:
  read from `attempt`, `run` and `check_own`; `InvalidRequest` could reach the status only
  through a command the adapter cannot write, which its fixed texts exclude.
- "FlexLib 4.3.16" in the source reference comes from the old text and the reference
  archive kept outside the tree; the code names the API wiki and the version 1.4.0.0
  only.
- The sentence that the adapter gives packets "in the state ready" follows the thing, not
  the code: in the code packets go on only while a capture is attached to the session.
- TC-023-001 (f) and (k) and TC-023-002 (b) show the adapter together with audio, receive
  and the modes part; they are kept because no narrower test shows the arrival time and
  the flagged first packet.

## Not done

- Nothing outside `docs/sysmlV2` was touched; nothing was committed or posted.
- No file of another part, no top file and no working file other than the ledger rows
  and the key in `parts.json` was edited.

## Changed after the report: the radio authorization (operator 2026-11-15)

The operator decided on 2026-11-15 that the radio authorization is not part of the
product. The adapter no longer waits for an authorization: it holds its session from
station start on. The part stays parked; this is the smallest change that keeps its model
true and valid. The code still has the authorization, and the difference is work for the
code (issue 226). The sections above are as they were written; where they name the
station's authorization, this section holds.

Measured by `measure.py` in the session's scratchpad (the tree against a copy made before
the change):

| File | Lines | Characters |
|---|---|---|
| `backend/flexAdapter/FlexSession.sysml` | 631 to 622 | 36,993 to 36,406 |
| `backend/flexAdapter/FlexAdapter.sysml` | 45 to 45 | 2,228 to 2,199 |
| `interfaces/internal/RadioControl.sysml` (radio control's file) | 581 to 555 | 25,461 to 24,179 |
| `_descriptions/flexAdapter.md` | 365 to 361 | 23,670 to 23,243 |

Removed from the model:

| Element | What was removed |
|---|---|
| CL-013-01 | "while the station is authorized to reach the radio" |
| `SessionState` | the literal `unauthorized` (7 to 6); the state at station start is `discovering` |
| `SessionLifecycle` | the three lines about the session without the authorization and the end of a session when it goes; the adapter chooses a radio and sets the session up from station start on |
| `FlexAdapter::control`, its `@NotStated` | "the station's authorization" among the things no item carries |
| `WstxRadioControl::NativePermission` and the item `permission` of `NativeControlPort` | whole (need 2 of "The control side" above) |
| TC-023-001 | "each authorized" in the setup |
| TC-023-002 | the condition (h) whole: a station without a grant reaches no radio, and leaves it when the grant goes (10 to 9 lettered lines, the planned (j) counted; 2 tests as before) |

The letters of the conditions that stay are unchanged; (h) of TC-023-002 is not used
again. No identity is retired or not carried; the ledger is unchanged.

Verdict added in `parts.json` (test 4: 26 matched, 46 with a verdict; before 27 and 45):

| Line of test 4 | Verdict |
|---|---|
| code `Error::Unauthorized` (the tool keys `State::Unauthorized` by the same name) | difference in the code: the code still has the radio authorization; removed from the product (operator 2026-11-15), issue 226 |

Differences in the code that test 4 does not show (work for the code, issue 226):

- `Session::set_allowed` and the field `allowed` (`session.rs`); `cat_tick` in
  `authorization_http.rs` sets it from the grant every 50 ms; `run` waits in
  `State::Unauthorized` until it is set, and a session starts in that state.
- The test "TC-023-002 a native station reaches no radio without a grant and leaves it
  when the grant goes" in `tests/flexAdapter/native-flex.test.cjs` shows the removed
  condition only; every station of that file enrolls a browser (`grant` of
  `tests/support.cjs`) before the adapter does anything.
- In "Work for the code" above, the line that the authorization reaches the adapter
  through radio control is void; the tune still does.

Lines "For the operator": the decision answers none of the nine. In "The control side"
need 2 is void, and of the handover row "station" nothing changes.

Not verified: `FlexSession.sysml` was searched for the terms and the elements around the
hits were read, not the whole file; `session.rs` was read at `State`, `Error`, `run` and
`set_allowed`, not in full; `native-flex.test.cjs` was searched, not read.
