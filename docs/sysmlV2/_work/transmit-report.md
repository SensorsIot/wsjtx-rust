# Report: the transmit part

2026-11-15. Built by a subagent session by the method. Tests 1 to 5 pass. Nothing is
decided that no rule decides; the lines for the operator and for the main session stand
at the end. No file outside the part's slice was changed.

## What was written

| File | Content |
|---|---|
| `backend/transmit/Transmit.sysml` | the transmit part with six ports; `control` is not typed (marker), see "For the main session" |
| `backend/transmit/Schedule.sysml` | 1 clause, 1 rule element, 2 test cases: the start plan |
| `backend/transmit/TransmitState.sysml` | 6 clauses, 9 rule elements, 5 test cases: the transmit state and its stops, admission and transmission, Halt and the failures, the tone, the repetition limit |
| `backend/transmit/TxLevel.sysml` | 2 clauses, 3 rule elements, 3 test cases: the Tx level, the Set level run, the supervision |
| `interfaces/internal/TransmitControl.sysml` | 14 enumerations, 21 items, 3 data elements: the commands, their answers, the state transmit reports, the outcome, the start window, the Tx level |
| `_descriptions/transmit.md` | the functional description |

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-009-02 | transmit/Schedule | Schedule | The start plan for both modes. From FR-006 (was FR-006, FR-005). |
| TC-006-001 | transmit/Schedule | Schedule | Rewritten from its two tests. |
| **TC-006-002** | modes/MessageEncode (handed over) | Schedule | Taken up: the FT4 start plan, from its two tests. Its mode-change steps are qso's (handover row of modes). |
| CL-111-01 | transmit/TransmitState | TransmitState | Keeps the state, off at start, on only by an Arm. The start actions and what is not a start are qso's. From FR-008 (was FR-007, FR-008). |
| CL-111-03 | transmit/TransmitState | TransmitState | Keeps the stop with its cause and the order of causes. What stays of the QSO, the band and the mode change are qso's. From FR-008. |
| CL-009-03 | transmit/TransmitState | TransmitState | Keeps the request on the air: admission, key, audio, release, outcomes. The authority is `TransmitArming` (CL-111-01), the tone CL-111-06, the watchdog CL-039-06, the wire the station link's, playing the program audio's CL-009-06. From FR-006 (was FR-008, -009, -002). |
| CL-009-04 | transmit/TransmitState | TransmitState | Halt, failures, the release at station start and at the end of the process. From FR-008 (was FR-008, FR-006). |
| CL-111-06 | transmit/TransmitState | TransmitState | The tone in transmit's terms; the contact's answers (`stale_revision`, `transmit_unavailable`, `tx_watchdog`) are qso's. |
| CL-039-06 | transmit/TransmitState | TransmitState | Keeps the limit, the stop without a key and `spent`. Who is an operator, the count and the refusal of a run or an agent are qso's, auto's and mcp's. |
| CL-044-12 | transmit/TxLevel | TxLevel | The level, the stored file, the run, the manual level. The route is the station link's, the meter reading radio control's, the profile field the profile's. From FR-008 (was FR-009). |
| **CL-044-14** | transmit/TransmitState | TxLevel | Moved to the file of its thing. The error-field entries are the frontend's. From FR-008 (was FR-009). |
| **CL-044-13** | transmit/TransmitState | handed over: station link, frontend | The push `radio.tx_level` and the Settings section. Its content is `TxLevelStatus`. |
| TC-008-003 | transmit/TransmitState | TransmitState | Rewritten from 11 tests; verifies CL-111-01 and CL-009-03. |
| **TC-008-005** | new | TransmitState | Halt, the failures and the releases of TC-008-003, from 15 tests; verifies CL-009-04. The next free number of the series TC-008. |
| TC-111-013 | transmit/TransmitState | TransmitState | Rewritten from its two tests. |
| TC-111-010 | transmit/TransmitState | TransmitState | Rewritten from three tests; (f) is the limit test of `transmit_service.rs`. |
| TC-039-005 | transmit/TransmitState | TransmitState | The three tests of the transmit function. Its two station tests go to qso, auto and mcp. |
| TC-044-013 | transmit/TxLevel | TxLevel | Keeps (e), the level in a transmission; (a) to (d) are radio control's. |
| TC-044-014 | transmit/TxLevel | TxLevel | Rewritten from 8 tests; the route (g) and the profile field (h) left it. |
| **TC-044-017** | transmit/TransmitState | TxLevel | Moved with its clause; rewritten from 15 tests. |
| TC-111-001, -002, -009 | transmit/TransmitState | handed over: qso | They show the contact: the kept QSO, what is not a start, the band change. |
| TC-111-007 | transmit/TransmitState | handed over: station link | The wire. |
| TC-044-015, TC-044-018 | transmit/TransmitState | handed over: frontend | Browser cases. |
| TC-008-002, TC-044-016, TC-044-019, TC-111-015 | transmit | not carried | Planned live cases on the radio without a test. |
| CL-009-05, CL-043-01, CL-043-03 and 4 cases | transmit/TransmitState | clock (before this part) | - |
| CL-061-04, TC-061-005 | transmit/TransmitState | receive (before this part) | Transmit states `on_air` and `last_period_utc_ms`. |

## Handover rows taken up

| Row (from) | Where it stands now |
|---|---|
| Admission by station time (clock) | `StartPlan`: refused with `clockNotSynchronized` while `StationTime::timeState` is not synchronized. A smaller offset is the clock's own state. |
| Halt does not wait (top files) | `HaltTransmit`, first rule. |
| The start plan; `AcceptedMessage`; 48 kHz (modes) | `StartWindow`, `StartPlan`, `Admission`. |
| Playback through audio (audio) | `Transmission`, `Failures`, `TxLevel`; no device is named. |
| On the air (receive) | `TransmitStatus::on_air`, `last_period_utc_ms`. |
| Native Flex profile (flexAdapter) | `TransmitProfile::configured` is false, so the capability is unsupported. TC-023-003's comparison is not taken up (the Flex adapter is parked). |
| The release at the end of the process (udp) | `HaltTransmit`, `SafetyReleases::exitReleaseMaxMs`; TC-008-005 (q) is the planned line. |
| TC-006-002 (modes) | arrived in `Schedule`. |
| The port `time` (top files) | `time : ~StationTimePort`. |

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Commands from the contact (Arm, Disarm, Abort, WatchdogStop, SendCount, StepBegins, the tone) | The operating chain commands downward (M5.7); a control interface defines the commands of its function once (M4.6); the chain's file may import it (M3.4) | Defined in `TransmitControl`; `MessageToSendPort` has to carry them. |
| `TransmitRefusal`, `TransmitOutcome` | What a part returns is defined in its interface file; a control interface imports no chain file (M3.4) | In `TransmitControl`. `OperatingChain` still holds a second `TransmitRefusal`. |
| `StartWindow` in the interface | What two parts share stands in their interface (M3.3): qso chooses the period by it | In `TransmitControl`; `StartPlan` refers to it by type. |
| CL-044-14 and TC-044-017 in `TxLevel.sysml` | A function file holds one function (M4.5); a model file follows the thing | Moved from `TransmitState`. |
| CL-044-13 | "Settings shows" is the frontend's, a push the station link's (M4.7) | Handed over. |
| TC-111-001, -002, -009 | A test case stands beside its clause (M6.5); they show the contact | Handed to qso. |
| TC-008-003 divided | A case is divided where its members are shown by different tests; a new identity takes the next number | TC-008-005. |
| One FR per clause | Method, "Decided" | FR-006 for the start plan and the transmission, FR-008 for the rest. |
| Profile values | A function learns them from the station service (M5.3) | `TransmitProfile`. |
| No radio type, no device | M5.9 | The key and the meters over `control`, the output over `audio`. The IC-7300 counts of the ALC are marked. |
| Period, parity, station time state | One fact, one place (M1.4) | `Period`, `PeriodParity`, `StationTimeState` are used, not restated. |
| The sample rate | M1.4 | Audio's `ProgramPlayback::sampleRateHz`; not restated. |
| Field names | The code's names win | Reported data has the code's names (`arm_state`); commands the model's. |
| Enumeration names | The code's names win | `Capability`, `OutcomeKind` (were `TransmitCapability`, `TransmitOutcomeKind`). |
| Status | A clause's status follows the code | All nine `implemented`; CL-111-01 and CL-111-03 were `partial`. |
| Planned live cases | A case is written only when a test exists | Four not carried. |
| The clock's and the measurement's fields of the code's `View` | The clock owns them | Not in `TransmitStatus`. |

## Dropped as code or as history

- The owner thread, its lock, the halt flag and the condition variable; the 2 ms step of
  the thread; the catch of a panic as a mechanism (kept: transmit itself fails,
  `ownerFault`).
- `keyLeadMs` 0, and the render values of the old `TransmitTiming` (they are audio's).
- The hash table as an object (kept: `AcceptedMessage`).
- The CI-V bytes of PTT and of the meters, the lease and the transmit hold: radio control's.
- The meter sink, the `tx-meters`, `tx-monitor` and `tx-level` threads, the 256 bytes of
  the level file, the 5 ms wait of the run.
- `TransmitSafetyPolicy` (three flags fixed to false), `TransmitAuthority`'s two flags.
- The "Not delivered yet" sentences of CL-111-01 and CL-111-03, all dates, issue numbers,
  slice names and operator quotations.
- The ALC onset reasoning of CL-044-14 ("reads 4-7, about 6 per dB"): the tests (j), (k)
  carry the values.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| package `WstxTransmit` | `WstxTransmitState` | old imports in Schedule, TxLevel, qso, frontend files; comments in `service.rs`, `transmit_http.rs` |
| package `WstxTransmitSchedule` | `WstxSchedule` | old `TransmitState` |
| `Ft8Schedule`, `Ft4Schedule`, `PlanTransmitStart`, `ScheduleRefusal` | `StartWindow` (interface), `StartPlan`; the refusals are `TransmitRefusal` | comment in `service.rs` |
| `TransmitAuthority` | rules of `TransmitArming`, `Capability`, `TransmitProfile` | `OperatingChain::TransmitRequest` text, comments in `service.rs` |
| `TransmitTiming` | `Transmission`, `HaltTransmit`, `Failures` | comments in `service.rs`, `radio_level.rs` |
| `StopOrder` | `Stops` | none found |
| `StartupSafetyRelease`, ExitRelease | `SafetyReleases` | comments in `service.rs`, `transmit_http.rs` |
| `SetTune` (action) | `SetTune` (item), `TuneTone` (rules) | none |
| `HaltTransmit` (action), `AbortTransmission` | `Halt`, `Abort` (items), `HaltTransmit` (rules) | comment in `service.rs` |
| `StationModeGate` | rules of `Admission` and `Transmission`; item `StationMode` | comments in `service.rs`, `contact_tests.rs` |
| `TransmitWatchdog`, `TransmitHaltUse` (interface) | `TxWatchdog`, `WatchdogView`; the use of Halt is qso's | comments in `service.rs`, `transmit_service.rs` |
| `TransmitWire` | handed to the station link | comments in `transmit_http.rs` |
| `TransmitCommand`, `TransmitState` (two empty items) | 15 command items, `TransmitStatus` | none |
| `TransmitCapability`, `TransmitOutcomeKind` | `Capability`, `OutcomeKind` | none |
| port `timing : ~PeriodTimingPort` | `time : ~StationTimePort` | `Station.sysml` (already `transmit.time`) |
| port `audio : AudioExchange` | `audio : Playback` | `Station.sysml` (already `PlaybackLink`) |

## Negative statements

| Old statement | Result |
|---|---|
| Never armed at startup, never persisted | positive: off at every station start, nothing of an earlier run is taken up |
| No PTT or audio while disarmed | positive: no request is admitted while off (`Admission`); TC-008-003 (a) |
| The automatic CAT lifecycle never emits PTT | radio control's; handed over |
| A missed period is never moved or replayed | positive: "a request stays with its period" (`StartPlan`) |
| Halt never waits for decode, receive or display | kept: Halt exists and could wait (`HaltTransmit`) |
| Disarm never unbounds a keyed transmission | positive: "a Disarm does not move the deadline" |
| The watchdog stop never keys, never halts | positive: "the radio's switch is not touched and halt_state stays" |
| The startup release never keys, is sent once | positive: "one release", "once for each run" |
| The recovery of an indeterminate switch never keys | kept as "it does not key": the function could |
| Tune never changes the transmit state | kept with its one exception, which the old text hid |
| The SNTP offset never refuses transmit | the clock's |
| Set level writes no radio setting | kept as "the run sends the radio no setting": radio control has setters |
| No outcome from a client timeout | kept in `TransmitOutcome` |

## Settled from the code

- **The order of the admission checks** is the code's; `notArmed` stands after
  `transmitUnsupported`, and a refused request uses up its sequence.
- **A request while the tone is on** is refused with `busy` and switches a state that is
  on off. The old text does not say so.
- **Tune ends a state that is on** when it ends by a lost capability, revision or output.
- **`SetWatchdogs` outside its ranges** is refused with `frequencyOutOfRange` in the code.
  The model says so; the routes refuse it earlier with their own code.
- **`runEnded`** is in the code's enumeration and in the order; no code gives it.
- **The release deadline** counts from the audio start on a clock that does not step
  (`monotonic_ms`); the model says "the start of the audio plus".
- **An Arm with the cause auto also ends `tx_expired`** in the code; the contact does not
  give one while `spent`.
- **Set level arms with the cause operator**, which marks the operator as seen and ends a
  watchdog stop. The model says "an Arm with the cause operator".
- **The warning limits of the SWR** are meter counts 80 and 120 in the code; the model
  gives the SWR (2.0, 3.0), which `swr_x10` maps exactly.
- **FT4's audio delay** is 300 ms; `Period::ft4NominalStartMs` (452, for the DT of
  received frames) is another quantity. WSJT-X has both.
- **WSJT-X** (`Modulator.cpp`, `TxStartPolicy.hpp`, `Configuration.cpp`): delay 500 and
  300 ms, latest start 0.75, Tx watchdog default 6 (minutes there), Tune watchdog 90 s.

## What the comparison with the code found

| Finding | Result |
|---|---|
| The limits of `radio_level.rs` are `pub(crate)` or private; the tool reads public constants | 9 verdicts "matched by reading" |
| Audio delay, 75 %, release bounds, tone range, watchdog defaults, 32 outcomes, 16 receipts, 1 s and 500 ms are literals or private | 13 verdicts |
| The results, warnings and refusals of the Tx level are texts, not enumerations | 11 verdicts; all 16 literals of `LevelResult`, `LevelWarning` and `LevelRefusal` were checked by reading |
| `ClockState` and `Parity` live in `transmit/schedule.rs` | 4 verdicts; work for the code |
| `PttError`, `AudioPoll`, `Program` are transmit's reading of radio control's and audio's items | 6 verdicts |
| SWR limits as meter counts | 2 verdicts "difference in the code" |
| `MAX_SAFE`, `SAMPLE_RATE_HZ` | 2 verdicts |
| The tool matched 62 names by itself | 6 values, 56 literals. A literal that two enumerations share is matched once; the ten enumerations taken from `service.rs` were compared by reading, literal by literal. |
| The tool reads an enumeration up to its first closing brace | `Program::Tone` and the later literals of an enumeration with a field are not listed; read by hand |

## Edge cases and their homes

| Case | Home |
|---|---|
| a request while off; with a sequence used before; with sequence 0 | `Admission`; TC-008-003 (a), (d) |
| a request exactly at the audio delay, 1 ms after, 1 ms before the window closes, at its close | `StartPlan`; TC-006-001 (c) to (e), TC-006-002 (c) to (e) |
| a period that fits one mode only | TC-006-002 (f) |
| a second request before the key; after the key; after the audio start; for another period | `Admission`; TC-008-003 (e), (f) |
| the station's mode changes after admission | `Transmission`; TC-008-003 (h) |
| the safety revision changes between Arm and request; while keyed | `Admission`, `Failures`; TC-008-003 (g), TC-008-005 (i) |
| Halt with nothing keyed; during the opening; during the key; during the audio; twice | `HaltTransmit`; TC-008-005 (a) to (f) |
| a release that is not confirmed | `Failures`; TC-008-005 (h), (m), (p) |
| the output never reports the end; reports it late; after the deadline | `Transmission`, `Failures`; TC-008-003 (k), TC-008-005 (j), (k) |
| the radio transmits at station start; later; after an own key | `SafetyReleases`; TC-008-005 (n), (o) |
| two stops in one step, in both orders | `Stops`; TC-111-013 |
| the tone with the state off; while a request waits; at its limit | `TuneTone`; TC-111-010 |
| the limits at 0, 100, 0 s, 301 s | `TxWatchdog`; TC-039-005 (b) |
| the level below -40, above 0; changed during a transmission | `TxLevel`; TC-044-013 |
| the level file missing, of another schema, out of range, unwritable | `TxLevel`; TC-044-014 (e), (f), TC-044-017 (g) |
| ALC exactly at the limit; at the floor; at the highest level | `LevelMonitor`, `SetLevelRun`; TC-044-017 (a), TC-044-014 (a) |
| two neighbouring levels that would alternate | `LevelMonitor` (ceiling); TC-044-017 (h), (l) |
| a reading without ALC; without SWR | `SetLevelRun`, `LevelMonitor`; TC-044-014 (d), TC-044-017 (d) |
| a late start with under 2 s of audio | `LevelMonitor`; TC-044-017 (b) |
| the 33rd outcome; the 17th Halt receipt; the release at the end of the process | planned lines in TC-008-003 (l), TC-008-005 (q) |
| a request text over 64 characters, a malformed body, another boot | the station link's |

## Not carried over

| What | Why |
|---|---|
| TC-008-002, TC-044-016, TC-044-019, TC-111-015 | planned live cases without a test |
| `runEnded` "not delivered yet", the three commands "to be retired" | plans, not the built state |
| The 250 ms "while CAT answers" proof through the wire | the station link's and radio control's |

## Size

Measured in characters by `measure.py` and `measure2.py` (scratchpad, folder `transmit`).

| | Old | New |
|---|---|---|
| `backend/transmit/` (4 files) | 119,814 | 69,593 |
| of the old text: the clock's 15 elements | 37,555 | - |
| of the old text: receive's 4 elements | 7,551 | - |
| `TransmitControl.sysml` | 6,936 | 21,963 |
| Total | 126,750 | 91,556 |

The part is 72 % of its old text. Without what the clock and receive took before it, the
old text is 81,644, and the part is 112 % of that. Where the size sits and what grew:

| Content | Old | New |
|---|---|---|
| The 9 clauses kept | 15,515 | 3,670 |
| The 9 test cases kept and TC-008-005 | 18,167 | 34,242 |
| The 13 rule elements of the function files | - | 25,056 |
| `TransmitControl.sysml` | 6,936 | 21,963 |
| Imports and derivations | - | 4,447 |
| The 11 identities handed over or not carried | 13,257 | - |

The growth is in two places. The test cases are written from 60 tests with one value per
condition (TC-008-003 was 3,917 characters for what is now 13,135 in two cases). The
interface had two empty items and now holds 21 items and 14 enumerations. The clauses
shrank to a quarter; their rules stand in the rule elements. The description is 30,458
characters.

## Checks

- `part_done.py transmit`: all five tests pass: 49 identities, 5 files without a finding,
  no validator error, 62 names matched with the code and 47 lines with a verdict, 10 test
  cases with their tests.
- The validator on the part's files with the 14 files it needs reports no error in a
  file of the part. It reports two errors in `RankingControl.sysml` (lines 228 and 300),
  a file another session builds.
- 60 distinct tests are bound, each defined in the file named: 27 in
  `server/tests/transmit_service.rs`, 20 in `radio_level_tests.rs`, 4 in
  `transmit_state_tests.rs`, 3 in `transmit_http_tests.rs`, 2 each in the two vector
  files, 1 each in `contact_tests.rs` and `strategy_tests.rs`.
- `git status`: `docs/sysmlV2/` is the only change.
- Ledger when this was written: 570 rows, 224 arrived, 37 handed over, 17 not carried,
  4 retired, 21 new. Of the 49 rows of the part: 19 arrived in transmit, 7 in the clock,
  2 in receive, 12 handed over, 9 not carried. The whole counts change while other
  sessions work.

Read in full: `service.rs`, `schedule.rs`, `playback.rs`, `transmit_http.rs`,
`radio_level.rs`, `transmit_service.rs` (1763 lines), `transmit_http_tests.rs`,
`radio_level_tests.rs` (to line 1004 of 1068; the rest is TC-044-023, radio control's), the two
schedule tests of each vector file. Read in part: `transmit_state_tests.rs` (the helpers,
TC-111-010, TC-111-013), `strategy_tests.rs` (the core test of TC-039-005 and the start of
one station test), `contact_tests.rs` (the mode gate test), the old `TransmitState.sysml`
(lines 1 to 648 and 936 to 1145 of 1191; lines 649 to 935 are the clock's cases, the
last 46 receive's clause and its cases). Not read:
`contact.rs`, `automation.rs`, `RadioProperties.sysml`, the other parts' reports and
descriptions except receive's.

## The functional description

`_descriptions/transmit.md`, from the new files alone. It found:

| Gap | Settled how |
|---|---|
| Who gives `runEnded` | `DisarmCause` says: the contact or a run, with Disarm or Abort. |
| Which refusal `SetWatchdogs` gets | Stated from the code (`frequencyOutOfRange`). |
| The commands of the contact and the outcome have no item on `contacts` | Not in transmit's files; line for the main session. |
| The type of `control`; the source of the safety revision | Markers. |
| The result of a run whose reading fails otherwise | Marker on `TxLevelStatus::result`. |
| The ALC counts on another radio | Marker on `LevelMonitor`. |

## Work for the code, when the new tree goes to main

- `ClockState`, `Parity` and the period lengths stand in `transmit/schedule.rs`; they are
  the clock's and the modes part's.
- The code's `View` carries the clock's state and measurement; transmit packs and encodes
  by calling the modes part's functions directly and teaches the hash table itself.
- `radio_level.rs` holds the meter scales of the IC-7300 (`po_percent`, `swr_x10`) and the
  route; the scales are radio control's, the route the station link's. Its limits are
  meter counts.
- `transmit_http.rs` holds transmit's join to audio and radio control and the wire.
- The contact calls the transmit core directly (`arm_automatic`, `abort`, `watchdog_stop`,
  `begin_step`, `start_tune`, `next_period`); in the model these are items.
- `SetWatchdogs` out of range answers `FrequencyOutOfRange`.
- Tests carry other numbers than their case: the Halt and failure tests (TC-008-003, now
  TC-008-005), the limit test (TC-008-001, bound by TC-111-010 and TC-039-005), the mode
  gate test (TC-007-008), `watchdog_stop_never_touches_ptt` (no case number).
- No test reads a value from the model.

## For the main session

Changes to files outside the slice, word for word.

1. `backend/transmit/Transmit.sysml`, when `Keying.sysml` is settled: replace the port
   `control { @NotStated { ... } }` by `port control : Keying;` and add
   `private import WstxKeying::Keying;`; add `interfaces/internal/Keying.sysml` and what it
   imports to `validate_with` of the key "transmit" in `parts.json`.
2. What transmit needs on `control` (compared with `Keying.sysml` as it stood when this
   was written):

   | Transmit needs | Fields | In `Keying.sysml` |
   |---|---|---|
   | key | the time allowed (`Failures::keyExchangeMaxMs`, 1000 ms) | `KeyRequest::withinMs` |
   | withdraw a key that waits (Halt) | - | `WithdrawKey` |
   | release | the time allowed (1000 ms; 500 ms at the end of the process) | `UnkeyRequest::withinMs` |
   | confirmation | which state | `KeyConfirmed::keyed` |
   | failure | the reason: busy, unavailable, timeout, rejected, readbackMismatch, indeterminate | `KeyFailed::reason`, `KeyFailure` (the same six) |
   | the radio is ready | Boolean | `RadioAvailability::ready` |
   | the radio transmits, from a fresh confirmed reading; absent without one | Boolean, optional | `RadioAvailability::transmitting` |
   | the switch may be on (end of the process) | Boolean | `RadioAvailability::mayBeKeyed` |
   | read the meters, only while keyed | the time allowed (`TxLevel::meterReadMaxMs`, 400 ms) | `ReadMeters::withinMs` |
   | the meters | ALC (absent when the radio refuses it), output power in percent of full scale, ten times the SWR; each optional | `MeterValues::readings` (`MeterReadings`, not read) |
   | the reading failed | the reason | `MetersRefused::reason` |
   | **the current safety revision** | Integer, absent while none holds | **not in `Keying.sysml`** |

3. `interfaces/internal/OperatingChain.sysml`: `MessageToSendPort` needs, beside
   `out item request : TransmitRequest;`:
   `out item arm : Arm; out item disarm : Disarm; out item abort : Abort; out item tune : SetTune; out item watchdogStop : WatchdogStop; out item sendCount : SendCount; out item step : StepBegins; in item answer : CommandAnswer; in item outcome : TransmitOutcome; in item status : TransmitStatus;`
   with `private import WstxTransmitControl::*` for these. Its `enum def TransmitRefusal`
   is to be removed in favour of `WstxTransmitControl::TransmitRefusal`. The text of
   `TransmitRequest` restates `Admission` and names `TransmitAuthority`,
   `PlanTransmitStart` and `TransmitTiming`, which are gone.
4. `Station.sysml`: no change; the port names are kept (`operations`, `contacts`,
   `encode`, `audio`, `control`, `time`).
5. `_work/files.md`: the four files of `backend/transmit/` and `TransmitControl.sysml` are
   built.
6. `_work/parts.json`: a script of this session replaced the verdict lines inside the key
   "transmit" only.
7. `interfaces/internal/ReceiveControl.sysml`, `OnAir`: its two values are
   `WstxTransmitControl::TransmitStatus::on_air` and `last_period_utc_ms`.
8. `_work/handover.md`, rows that are taken up (add "**Taken up:**" to each): the rows
   "transmit" from clock (admission), top files (Halt), modes (start plan), audio
   (playback), receive (on the air), flexAdapter (native profile), udp (release at the end
   of the process), and the row "receive, transmit, qso, audio" (port `time`).
9. `_work/handover.md`, new rows:

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| qso | The contact's side of the transmit state: the start actions switch it on with `Arm` (cause operator or auto); each stop of the contact is a `Disarm` or an `Abort` with its cause (completed, cancelled, partner works another station, band change, mode change); what stays of the QSO at each stop; the QSO goes on only by Reply or "send next". The contact gives `StepBegins` at each step, refuses a start while `TransmitStatus::stopped_in_step` is true (`state_conflict`), and refuses a start or a tone from a run or an agent while `WatchdogView::spent` is true (`tx_watchdog`). It answers a refused tone with `stale_revision` and `transmit_unavailable`. TC-111-001, TC-111-002 and TC-111-009 go with it. | CL-111-01, CL-111-03, CL-111-06, `StopOrder`, TC-111-001, -002, -009 | transmit |
| qso | The count of the repetition limit: the contact counts the sends of one message, gives `SendCount` and `WatchdogStop`; transmit holds the limit only (`WatchdogView::tx_calls`). The station tests `tc_039_005_automation_never_resets_the_tx_watchdog` and `tc_039_005_only_a_browser_action_counts_for_the_watchdog` (`strategy_tests.rs`) show the contact, the run and MCP; TC-039-005 stands in transmit with the three tests of the transmit function. | CL-039-06, TC-039-005, `TransmitWatchdog` | transmit |
| qso | The contact chooses the period of a request by `WstxTransmitControl::StartWindow` (the next period of a parity whose window is open); the code calls transmit's `next_period`. Halt is the operator's emergency stop only; the contact and the runs use `Disarm` and `Abort`. | `Ft8Schedule`, `TransmitHaltUse` | transmit |
| auto | `DisarmCause::runEnded` (a run ended and left its contact unfinished) has its place in the order of stops; no code gives it. | CL-111-03 | transmit |
| station | The station service gives transmit `TransmitProfile` (configured: control over CAT, PTT over CAT and an output device named; levelManaged; powerLimitPct), `StationMode` at every change, `OperatorSeen` for an accepted action of the browser (restart for a strategy selection or run start), and `ProcessEnds`. It checks that the sender may transmit before `Arm`, a tone and `SetLevel` (`not_authorized`, `unauthorized`), reads `TransmitStatus::on_air` and `last_period_utc_ms` for receive's `OnAir`, and joins the clock's state, measurement and warning to the transmit view of the wire. In the code transmit's hardware reads the profile (`Station::update`) and the clock. | `TransmitAuthority`, CL-009-03, CL-044-12, `TransmitWire` | transmit |
| station link | The transmit routes and pushes: `GET /transmit` with its keys (the latest 8 outcomes, names in snake_case, `tx_remaining_calls` null for an unbounded contact); `POST /transmit/command` (arm, disarm, request, tune, set_watchdogs; `out_of_range`; a message text of at most 64 characters; the same reply for a repeated command id among the latest 16, `state_conflict` for another body or boot); `POST /transmit/halt` (202 with `halt_state`, admitted for every boot); the event `transmit.state` (1024 bytes, `transmit_revision`, the changed fields, the tone's countdown at most every 5 s below Detailed); `POST /radio/tx-level` (set_level, manual; 401 without the right to transmit) and the event `radio.tx_level` with the keys of `TxLevelStatus` and `keying_confirmed`. CL-044-13 and TC-111-007 go with it; its tests are `transmit_wire_is_exact_halt_is_always_admitted_and_plaintext_never_arms` and `the_route_refuses_bad_requests_and_a_station_without_a_grant`. | `TransmitWire`, `HaltTransmit`, CL-044-12, CL-044-13, TC-111-007, TC-044-014 (g) | transmit |
| frontend | Settings > Radio > Audio: the Set level button, the line with the level and the last result, the meters, the profile power field, the slider only while the ALC is unavailable; the error-field entries of `LevelWarning` (swr_fault as an error, the others as warnings); "WD n calls" in the transmit line. TC-044-015 and TC-044-018 go with it. | CL-044-13, CL-044-14, TC-044-015, TC-044-018 | transmit |
| radioControl | The meters are read only while the radio is keyed by the station (else busy, nothing sent); a refused ALC reading is a missing value; a reading that stalls gives way to a release within 250 ms and keeps the connection; the scales of the IC-7300 (output power 143 = 50 %, 213 = 100 %; SWR 48 = 1.5, 80 = 2.0, 120 = 3.0) stand in `radio_level.rs`. Tests: `meters_are_read_only_under_the_transmit_hold_in_the_manual_frames`, `a_stalled_meter_read_gives_way_to_the_release_and_keeps_the_connection`, `meter_scales_follow_the_manual_table` (TC-044-013 a to d). The key and release bytes with their readback, no poll while keyed, one release when a keyed connection closes, a key that times out closes the connection, a withdrawn key sends nothing: `ci_v_ptt_bytes_readback_and_hold_exclude_polling`, `closing_a_keyed_connection_sends_one_off_only_switch_and_timeouts_close`, `a_halt_aborts_a_key_waiting_for_the_cat_owner_without_bytes` (`transmit_service.rs`). The read-only lifecycle sends no PTT command. Transmit needs the current safety revision. | CL-044-12, TC-044-013, CL-009-03, CL-009-04, `PttControl` | transmit |
| profile | `settings.radio.power_limit_pct`, 1 to 100, absent by default; 0 and 101 are refused (`profile_power_limit_is_saved_kept_absent_by_default_and_validated`). `tx-level.json` in the profile's folder is transmit's file; writing it does not change the revision. | CL-044-12, TC-044-014 (h) | transmit |
| modes | `accepted_requests_teach_the_station_hash_table` (`transmit_service.rs`) shows what the modes part learns from `AcceptedMessage`; transmit binds it to no case. | CL-024-01 | transmit |

## For the operator

One line at a time; each with what WSJT-X does and a recommendation.

| # | Line | WSJT-X | Recommendation |
|---|---|---|---|
| 1 | **Answered (operator 2026-11-15): none; the radio authorization is not part of the product, so the model has no safety revision and the marker is gone.** Which connection gives transmit the safety revision (marker on `TransmitArming`)? `Keying.sysml` as radio control's session wrote it has none. | No such number: one program, one operator at the radio. | Radio control gives it in `RadioAvailability`: it knows when the radio or its control is set up anew, and transmit already reads that item before every key. |
| 2 | **Answered (operator 2026-11-15): only over the chain; Tune too goes through qso. `TransmitControlPort` keeps Halt, SetLevel and the station's facts.** The contact gives transmit Arm, Disarm, Abort, the watchdog stop and the tone over the chain's connection, not through the station service (M5.7 against M5.3). Decided by M5.7; confirm. | One program; the sequencer sets the Tx enable itself. | Keep. The contact acts every 50 ms and on each decode; a detour through the station service adds nothing. |
| 3 | **Answered (operator 2026-11-15): the ALC is a reading of radio control in percent of the ALC zone (limits 8 and 50); the level per band, manual (slider) or automatic (default; Tune finds it and goes on, each transmission corrects one step); no Set level button. See the section "Changed after the report: the Tx level".** The ALC limits of the supervision (10 and 60) are counts of the IC-7300 meter, in transmit, which is not to know the radio (M5.9; marker on `LevelMonitor`). | No ALC supervision; a manual Pwr slider. | Radio control gives the ALC as a share of the radio's ALC zone; the limits become about 8 % and 50 %. A code change; until then the marker stays. |
| 4 | **Answered (operator 2026-11-15): FR-008 now reads "Show the transmit state, keep the transmit drive level, set by the operator or found from the radio's ALC, halt at once on request, and unkey the transmitter on a PTT, radio or device fault."** CL-044-12 and CL-044-14 (Tx level) derive from FR-008; the old model had FR-009, which is radio control's. No FR names the level of the transmit audio. | - | Keep FR-008 and add "and keep the level of the transmit audio" to its sentence, or leave it. |
| 5 | **Answered (operator 2026-11-15): kept whole; when the frontend is built the push stays CL-044-13 with the station link and the Settings section takes the next free number with the frontend.** CL-044-13 (the push of the Tx level and the Settings section) is handed to the station link and the frontend as a whole; its data is `TxLevelStatus`. | - | Keep; number the frontend's half when the frontend is built. |
| 6 | **Answered (operator 2026-11-15), after reading the tests condition by condition: the three go to qso as handed; TC-111-010 keeps (a), (c), (f) and a planned (h), its (d), (e), (g) are the contact's answers and become TC-111-017 (qso); TC-111-013 keeps (c) to (g) with its second test, its (a), (b) are the contact's state_conflict and become TC-111-018 (qso) with the first test.** TC-111-001, -002 and -009 are handed to qso although the ledger aimed them at transmit; TC-111-010 and TC-111-013 stay in transmit although they run through the contact. | - | Keep: the first three show what the contact does, the other two what transmit does. |
| 7 | **Answered (operator 2026-11-15), after reading all 25 bound tests: the division stands; each test shows conditions of its own case only. Fixed: TC-008-003 (d) "through P + 31 s" (the test runs to there, not 20 s after); TC-008-005's setup names TC-008-003. Work for the code: the test of TC-008-003 (j) is to assert that the request is accepted and fails with audioUnavailable (it passes on any refusal now); 8 tests of TC-008-005 say TC-008-003 in their comments, (h)'s says TC-007-008.** (`watchdog_stop_never_touches_ptt` is bound, to TC-039-005 (d); an earlier note said otherwise.) TC-008-003 is divided; TC-008-005 is new (Halt, failures, releases). | - | Keep; the two cases have 12 and 17 lettered conditions. |
| 8 | **Answered by the settings decision (operator 2026-11-15): `SetWatchdogs` left the model; the ranges stand with `TransmitConfig`; the code's refusal is work for the code.** `SetWatchdogs` outside its ranges is refused with `frequencyOutOfRange` (the code). | Spin boxes that cannot leave their range. | Keep the model as the code is; give the code its own refusal later. No route reaches it today. |
| 9 | **Answered (operator 2026-11-15): `runEnded` left the model (no code gives it; a run that ends cancels its contact); `DisarmCause::operator` left with it by #121 (Enable Tx retired, no producer). The texts of line 2 that named Enable Tx now name the operator's starts.** `runEnded` is a cause no code gives. | - | Keep the literal; auto gives it when auto is built. Or drop it from the code. |
| 10 | **Answered (operator 2026-11-15), then simplified: "Tx watchdog" is the repetition limit only, and qso's whole (limit, count, calls left, expired; Disarm with txWatchdog); `WatchdogStop`, `OperatorSeen`, `spent`, `tx_expired`, `WatchdogView` left transmit; CL-039-06 and TC-039-005 go to qso, TC-039-005 (c), (d) are TC-111-013 (h), (i); the SWR fault barrier is the station service's with code `swr_fault` (#122 Q3 now (b)). First answer: the limit (from `TransmitConfig::txCalls`), the count, `tx_remaining_calls` and "unbounded"; `SendCount` is gone; transmit keeps `WatchdogStop` with `tx_expired`, `spent` and the Tune limit. TC-039-005 keeps (a) (spent), (c) and (d); (b) and the calls left go to qso (handover row).** `tx_remaining_calls` is reported by transmit from a count the contact holds (`SendCount`). | One watchdog in the main window. | Move the remaining calls to the contact's view when qso is built; transmit keeps the limit and the stop. |
| 11 | **Answered (operator 2026-11-15): deleted; the ledger marks the four retired.** The four live cases on the radio (TC-008-002, TC-044-016, TC-044-019, TC-111-015) are not carried, by the rule on planned cases. They are the acceptance on the transceiver. | - | Keep them out of the model; hold them as a checklist for the operator outside it. |
| 12 | **Answered by the rule on planned lines (operator 2026-11-15, on audio): they stay as notes for the implementer; added since: TC-044-014 (h), TC-044-017 (m), TC-111-010 (h), radio control's TC-009-007 (i).** Three planned lines: TC-008-003 (l), TC-008-005 (q), TC-044-014 (h). | - | Keep as notes for the implementer. |

## Changed after the report: the radio authorization (operator 2026-11-15)

The operator decided on 2026-11-15 that the radio authorization is not part of the
product: no safety revision, no confirmation of the setup, no grant. The model states the
station without it; the code still has it, and the difference is work for the code (issue
226). The sections above are as they were written; where they name the safety revision,
`notAuthorized` or `authorityChanged`, this section holds.

Measured by `measure.py` in the session's scratchpad (the tree against a copy made before
the change):

| File | Lines | Characters |
|---|---|---|
| `backend/transmit/TransmitState.sysml` | 659 to 631 | 41,490 to 39,538 |
| `backend/transmit/TxLevel.sysml` | 317 to 316 | 19,880 to 19,749 |
| `interfaces/internal/TransmitControl.sysml` | 488 to 474 | 21,963 to 21,226 |
| `_descriptions/transmit.md` | 473 to 463 | 30,458 to 29,289 |

Removed from the model:

| Element | What was removed |
|---|---|
| `Arm` | the feature `safetyRevision` |
| `SetTune` | the feature `safetyRevision` |
| `DisarmCause` | the literal `authorityChanged` (14 to 13 literals) |
| `TransmitFailure` | the literal `authorityChanged` (10 to 9) |
| `TransmitRefusal` | the literal `notAuthorized` (13 to 12) |
| `LevelRefusal` | the literal `radio_unavailable` (5 to 4): `start_assistant` gives it only when the transmit state is off and no safety revision holds; a radio that is not ready is the Arm's `radioUnavailable`, which `LevelAnswer::transmitRefusal` carries. `LevelResult::radio_unavailable` stays |
| `Capability` | "or no safety revision holds" from unavailable |
| `TransmitArming` | the condition "no safety revision holds" of the Capability; the refusal `notAuthorized` of Arm; "under that safety revision"; the `@NotStated` about the connection that gives the revision (1 marker to 0 in the file, and the import of `NotStated`) |
| `Stops` | the stop by another safety revision with `authorityChanged`; `authorityChanged` in the order of the shown cause; "the two losses" is "the lost Capability" |
| `Admission` | the refusal `notAuthorized` |
| `Failures` | the failure of a keyed transmission by a changed safety revision |
| `TuneTone` | the refusal `notAuthorized`; the sentence about a SetTune without a revision (refused with `notArmed` while the state is off); the end of the tone by another revision |
| `SetLevelRun` | the refusal `radio_unavailable`; "under the current safety revision" |
| CL-009-04 | "or its authority" in the sentence: "on every failure of the radio or the output" |
| TC-008-003 | the revision 7 of the setup; in (a) the Arm with the revision 6 and the SetTune without a revision; the condition (g) whole; the test `arm_is_refused_while_ptt_is_indeterminate_and_submit_checks_the_safety_revision`, which showed (g) only here (12 to 11 lettered lines, 11 to 10 tests) |
| TC-008-005 | in (i) the cause `authorityChanged` for the revision 8 instead of 7. The test of the row above stays bound here: it shows (m) |
| TC-111-010 | the revision 7 of the setup and of (a); the condition (b) whole (`stale_revision`); in (d) the sender without the right to transmit (7 to 6 lettered lines, 3 tests as before) |
| TC-039-005 | the revision 7 of the setup |

The letters of the conditions that stay are unchanged; (g) of TC-008-003 and (b) of
TC-111-010 are not used again.

No identity is retired or not carried: every clause keeps its promise without the
authorization, and every test case keeps conditions. The ledger is unchanged.

Verdicts added in `parts.json` (test 4: 60 matched, 49 with a verdict; before 62 and 47):

| Line of test 4 | Verdict |
|---|---|
| code `TransmitFailure::AuthorityChanged` (the tool keys `DisarmCause::AuthorityChanged` by the same name) | difference in the code: the code still has the radio authorization; removed from the product (operator 2026-11-15), issue 226 |
| code `TransmitRefusal::NotAuthorized` | the same; given for another safety revision (`arm_refusal`, `submit`, `start_tune`) and for a sender without a grant (`transmit_http.rs`), and by nothing else |

Differences in the code that test 4 does not show (work for the code, issue 226):

- `Core::arm`, `arm_automatic` and `start_tune` take a safety revision; `Context` carries
  `safety_revision`; `Station::update` (`transmit_http.rs`) takes it from the CAT gate, and
  `Context::capability` is available only while one holds.
- The code has two ways to switch the tone on: `start_tune` (whatever the transmit state,
  with a revision) and `set_tune` (only while the state is on, with the revision it was
  switched on under; `notArmed` otherwise). The route `tune` of `POST /transmit/command`
  and the Set level run use the second. The model has one `SetTune`, whatever the transmit
  state (CL-111-06). The first assertion of
  `nothing_is_keyed_or_played_without_explicit_armed_authority` that a `set_tune` is
  refused while the state is off shows the second way and is no condition of the model
  any more.
- `radio_level.rs` `start_assistant` refuses with `radio_unavailable` without a revision.
- The tests that set a revision (`Fake::revision` in `transmit_service.rs`, `REV` in
  `transmit_state_tests.rs`) and the three assertions on `NotAuthorized` and
  `AuthorityChanged` in `transmit_service.rs`.

Lines "For the operator" that the decision answers: line 1 (marked above). Line 7 gives
the two cases 12 and 17 lettered conditions; they have 11 and 17 now, the planned line of
each counted.

Not verified: `Schedule.sysml` and `Transmit.sysml` were searched for the terms, not read
again; the bodies of the tests of TC-008-005 other than the two that set a revision were
not read again.

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
| `interfaces/internal/TransmitControl.sysml` | 474 to 485 | 21,226 to 22,156 |
| `backend/transmit/Transmit.sysml` | 35 to 38 | 1,665 to 1,845 |
| `backend/transmit/TransmitState.sysml` | 631 to 628 | 39,538 to 39,362 |
| `backend/transmit/TxLevel.sysml` | 316 to 310 | 19,749 to 19,288 |
| `_descriptions/transmit.md` | 463 to 474 | 29,289 to 30,053 |

Moved in (transmit defines them now):

| Element | What |
|---|---|
| `TransmitConfig` (new, in `WstxTransmitControl`) | the configuration: `levelDb` (the transmit audio level), `powerLimitPct` (the power limit), `txCalls` = 6 (the number of calls of the Tx watchdog), `tuneSeconds` = 90 (the Tune limit), each with what it does and its range |
| `TransmitProfile` | carries `config : TransmitConfig`; its own `powerLimitPct` went into the configuration; `configured` and `levelManaged` stay (they follow from the configurations of radio control and audio) |
| `LevelFound` (new) | a level transmit has found, given to be saved; answered by a `TransmitProfile` with that level, or with the level before when it could not be saved |
| `TransmitService` | one attribute: `config : TransmitConfig` |

Left:

| Element | What left |
|---|---|
| `SetWatchdogs` | the command, its place on the port and in the text of `CommandAnswer` and of `TransmitRefusal::frequencyOutOfRange` |
| `ManualLevel` | the command and its place on the port and in `LevelAnswer` |
| `LevelRefusal` | the literals `alc_available`, `invalid_request` and `storage_unavailable` (4 to 1: `busy`) |
| `TxWatchdog` | "at every station start they are txCallsDefault and tuneSecondsDefault; SetWatchdogs sets both ..."; the two values `txCallsDefault` and `tuneSecondsDefault`, which are the values of `TransmitConfig::txCalls` and `::tuneSeconds` now. It says: the limits are those of the configuration; a changed number of calls shows in `tx_remaining_calls` at once (`Core::view`), a changed Tune limit holds for the next tone (`until_utc_ms` is set when the tone starts) |
| `TxLevel` | the file `tx-level.json` with its form and its faults; "storing it does not change the revision of the profile"; the four refusals of `ManualLevel`. It says: the level is `TransmitConfig::levelDb`; a level transmit finds is given as `LevelFound` and counts when it has come back |
| CL-044-12 | "keep that level across a restart of the station" left the sentence: the profile keeps it (CL-005-02) |
| TC-039-005 (b) | "SetWatchdogs with 0 and with 100 calls, and with 0 and with 301 s: refused": the refusal of the function's own set command; the ranges stand with `TransmitConfig`. The letter stays with its other condition; 4 lettered lines and 3 tests as before |
| TC-044-014 | in (b) "the file holds schema_version 1 and level_db -28" and "the revision of the profile unchanged"; in (c) and (d) "no file"; in (d) the refusal of `ManualLevel` with `alc_available`, with `invalid_request` for -41 and 1, and "stored in the file"; in (e) the three bad files. Kept with the setup changed: the level in the configuration at station start (e), a level given during a tone (d), a level found that does not come back as saved (f). 8 lettered lines and 8 tests as before: each bound test still shows a kept condition |
| TC-044-017 (c), (g) | "in the file" is "found and taken"; "the file cannot be written" is "the level found does not come back as saved"; 12 lettered lines and 15 tests as before |

No identity is retired or not carried.

Marker added (1, on `TxLevel`; the file has 2 now): who refuses a level the operator sets
by hand while the radio reports its ALC, and during a Set level run. The code refuses it in
transmit (`set_manual`: `alc_available`, `busy`); with one way for a change, the new
configuration reaches transmit only when it is saved.

Verdicts in `parts.json` (test 4: 60 matched, 47 with a verdict; before 60 and 49):

| Line of test 4 | Verdict |
|---|---|
| model value `TransmitConfig::txCalls`, `TransmitConfig::tuneSeconds` (2 added) | difference in the code: the code keeps this in a file of the function's own; the settings are sorted into three stores (operator 2026-11-15). Here the code keeps the value in no file |
| model literal `LevelResult::storage_unavailable` (1 added; the tool keyed the literal under `LevelRefusal` before) | the same; the text is the result of `store_level` when `tx-level.json` cannot be written |
| `LevelRefusal::alc_available`, `::invalid_request`, `::storage_unavailable`, `TxWatchdog::txCallsDefault`, `::tuneSecondsDefault` (5 taken out) | they left the model |

**Checked, as asked: the code does not save the two limits of the Tx watchdog.**
`Core::new` (`server/src/transmit/service.rs`) starts with `tx_calls: 6` and
`tune_seconds: 90`; `set_watchdogs` sets the two fields of the running process; no file
name and no `write_document_file` stands near them, `qso-settings.json` holds
`auto_seq` and `call_first` only, and the browser (`client/contact.js`) sends
`set_watchdogs` and keeps the two values in no storage. They start at 6 and 90 with every
station start. WSJT-X saves both (`Configuration.cpp`: `TxWatchdog`, default 6, and
`TuneWatchdogTime`, default 90).

Differences in the code that test 4 does not show (work for the code): `radio_level.rs`
keeps `tx-level.json` (its header says why: "a level change never advances the profile
revision, which would reconnect CAT"); `set_manual` and the route behind it;
`set_watchdogs` reaches transmit as a command of the contact (`contact.rs`, refused for a
run or an agent with `operator_required`) and as an action of `POST /transmit/command`
(`transmit_http.rs`); the power limit stands in the profile's radio
settings.

Decided by rule: no part has a set command of its own for a config value (the decision),
so `SetWatchdogs` and `ManualLevel` left and their ranges stand with the values; a
condition that shows only the function's file or the refusal of its set command left its
case.

Answered later (operator 2026-11-15): the level set by hand is line 3 (manual or automatic); the limits of the Tx watchdog are qso's and an agent is the operator (#122); the revision of a found level stays with the profile's questions. As written: Not decided, for the operator: who refuses a level set by hand while the radio reports its
ALC (the marker); whether a level the station finds counts the profile's revision (marker
on the profile's `SaveSettings`); that only the operator in the browser may change the two
limits (the code's `operator_required`), which had no sentence in transmit's files and is
the station service's to state.

Not verified: the bodies of the eight tests of TC-044-014 and of the tests of TC-044-017
(c) and (g) were not read again; the conditions were rewritten from the case's own text
and the names of the tests.

## Changed after the report: the commands over the chain (operator 2026-11-15)

Line 2 answered: the contact's commands (Arm, Disarm, Abort, SetTune, WatchdogStop,
SendCount, StepBegins) reach transmit only over `MessageToSend`; the operator's Enable Tx
and Tune go station service → qso → transmit. `TransmitControlPort` lost those seven items
and `CommandAnswer`; it carries Halt, the configuration and the station's facts. In the
code `POST /transmit/command` and its panel in `client/contact.js` reach transmit past the
contact: work for the code (handover row to the station link).

## Changed after the report: the Tx level (operator 2026-11-15)

Line 3 answered. The operator decided:

- The ALC is a reading of radio control like the output power, in percent of the radio's
  ALC zone. The supervision's limits are 8 % (`alcLimit`, was the count 10) and 50 %
  (`alcHigh`, was 60); the IC-7300 counts 10 and 60 round to these, so every decision of
  the tests stays. The marker on `LevelMonitor` is gone.
- The Tx level is kept per band (`TransmitConfig::levels`, `BandLevel`), for transmissions
  and Tune alike. A band without an entry keeps the level before (WSJT-X: a band without a
  stored value takes the slider's present one).
- `TransmitConfig::levelMode`, manual or automatic, automatic by default. Manual: the
  operator's slider (WSJT-X's Pwr), nothing found or corrected. Automatic: no slider; the
  Tune tone finds the level and goes on at it; each transmission corrects it by one step at
  most. A radio without an ALC reading works as manual.
- Tune is a toggle in both modes. There is no Set level button: `SetLevel`, `LevelAnswer`,
  `LevelRefusal` left; `SetLevelRun` is `LevelFinding`. The finding does not switch the
  transmit state (the code's run arms and disarms) and leaves the tone on.
- The meter reading, the warnings and the SWR fault hold in both modes.
- New item `StationBand` on `TransmitControlPort`: the station service gives the band.
- The marker on `TxLevel` (who refuses a level set by hand while the ALC is reported) is
  answered: in automatic the operator sets none.

Test cases: TC-044-014 and TC-044-017 keep their letters; the ALC values are written in
percent (the tests use the IC-7300 counts); the setup names the mode. Planned lines:
TC-044-014 (h) (the tone after a finding, the unchanged transmit state, manual, the level
of each band), TC-044-017 (m) (the reading in manual), radio control's TC-009-007 (i) (the
ALC in percent).

Verdicts in `parts.json`: `LevelFinding::*` renamed from `SetLevelRun::*`;
`LevelMonitor::alcLimit` and `alcHigh` and the literals of `LevelMode` are differences in
the code.

Work for the code: radio control converts the ALC; per-band levels; the mode with its
default; Tune finds the level in automatic without arming and keeps the tone on;
`POST /radio/tx-level` and `set_manual` go; `tx-level.json` (already listed).

Handover rows added: frontend (the mode, the slider only in manual or without ALC, no Set
level button), station link (`/radio/tx-level` goes, `mode` in the push), station
(`StationBand`), radio control (the ALC in percent). `settings.csv`: the level per band and
the mode.
