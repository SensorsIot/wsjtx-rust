# Report: the receive part

2026-11-15. Fourth part built by the method. Tests 1 to 5 pass. The lines for the operator
are in the last section but one; none is answered yet.

## What was written

| File | Content |
|---|---|
| `backend/receive/Receive.sysml` | the receive part with eight ports |
| `backend/receive/ReceiveJob.sysml` | 4 clauses, 5 rule elements, 3 test cases: the job and its end, admission, the records of a live job and its epochs, the window counters and the dump |
| `backend/receive/Spectrum.sysml` | 1 clause, 3 rule elements, 2 test cases: the two rows |
| `backend/receive/LiveReceive.sysml` | 3 clauses, 6 rule elements, 3 test cases: windows, timing and views; the schedule on station time; transmit periods and the receive level |
| `interfaces/internal/ReceiveControl.sysml` | the commands of the station service, their answers, the state receive reports, the window counters |
| `interfaces/internal/Decodes.sysml` | the record with its period and DT; the view of a period |
| `interfaces/internal/DisplayData.sysml` | the thin and the detailed row |

Changed in files of other parts, each because receive's exchange needs it:

| File | Change |
|---|---|
| `interfaces/internal/AudioStreams.sysml` (audio, built) | `EpochTie`, `CaptureTie` on `ReceiveSamples`; `CaptureCounts` as `CaptureMarks::events` |
| `interfaces/internal/StationTime.sysml` (clock, built) | `StationHeard`, `WindowDone`, `StationsHeardPort`, `StationsHeard` |
| `backend/clock/Clock.sysml` (clock, built) | the port `decodes` with its `@NotStated` is replaced by `heard : ~StationsHeardPort` |
| `interfaces/internal/RecordingTransfer.sysml` (profile, taken over) | `OpenRecording`, `RecordedBlock`, `RecordingUnreadable`, `RecordedSamples`, `RecordedSamplesLink` |
| `Station.sysml` | `recordedInput` is typed `RecordedSamplesLink`; `decodesClock` is replaced by `stationsHeard : StationsHeard connect receive.heard to clock.heard`; two imports |

`part_done.py clock`, `modes` and `audio` still pass after these changes.

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-006-02 | receive/ReceiveJob | ReceiveJob | Keeps the job's states and its end. The import's states go to the profile. From FR-003 (was FR-018, FR-019). |
| CL-006-04 | receive/ReceiveJob | ReceiveJob | Keeps one job at a time and the refusals. The limits of an import go to the profile, those of the display to the station link. From FR-003 (was FR-021). |
| CL-008-03 | receive/ReceiveJob | ReceiveJob | Keeps the records and the job across a loss; its sound device half is audio's CL-008-08. From FR-003 (was FR-002, -009, -019, -021). |
| CL-052-01 | receive/ReceiveJob | ReceiveJob | Keeps the counters and the dump; routes and the Settings control are handed over. |
| CL-006-03 | receive/ReceiveJob | Spectrum | Keeps the two rows and their numbers. Its display half goes to the frontend and needs a new identity there. From FR-003 (was FR-010, -019, -021). |
| CL-007-01 | receive/LiveReceive | LiveReceive | Live FT4 and FT8: windows, records with period and DT, the view. From FR-003 (was FR-003, -004, -018). |
| CL-007-05 | receive/LiveReceive | LiveReceive | The windows on the periods of station time. The capture clock went to audio (CL-007-11). From FR-006 (was FR-003, -004, -021). |
| **CL-061-04** | transmit/TransmitState | LiveReceive | Moved: no decode, no level and marked rows in a transmit period are receive's behaviour, in receive's code, shown by a test of the live worker. From FR-003 (was FR-007, -010, -019). |
| **TC-061-005** | transmit/TransmitState | LiveReceive | Moved with its clause. |
| TC-018-003 | receive/ReceiveJob | ReceiveJob | Rewritten from five tests; import, browser and routes left it. |
| TC-009-004 | receive/ReceiveJob | ReceiveJob | Rewritten from four tests; verifies CL-008-03 only (was five clauses). |
| TC-052-001 | receive/ReceiveJob | ReceiveJob | (a) to (e) from its test file; the routes (f), the marks (g, audio's TC-002-001 k) and the browser (h) left it. |
| TC-010-001, TC-010-004 | receive/ReceiveJob | Spectrum | Rewritten from three tests. |
| TC-004-004 | receive/LiveReceive | LiveReceive | Rewritten from eight tests; verifies CL-007-05 only. The drift test is audio's TC-007-011 (c). |
| **TC-007-012** | new | LiveReceive | The receive half of TC-007-006 (frontend) and the window tests the code binds to TC-002-001 (audio's case now). The next free number of the series TC-007. |
| TC-009-002 | receive/LiveReceive | handed over: radioControl | A live case by hand on the radio and its sound device. |
| TC-010-002, -003, -005, -006, -007 | receive/ReceiveJob | handed over: station link, frontend | The link's events and the browser's display. |
| TC-061-006, TC-061-007 | transmit/TransmitState | frontend; not carried | The browser; a planned live case without a test. |
| CL-045-01 to -03, TC-045-001, -002 | receive/Startup | handed over: station | Decided by the operator before the writing. |

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| The view of a period: CL-010-09 and TC-007-006 are the frontend's | A clause keeps its identity where its core is; "Band Activity shows" is the frontend's | The view is a rule element of CL-007-01 (`PeriodViews`); its tests are bound by TC-007-012. |
| CL-061-04 | A model file follows the thing; a clause stands in the function file of its part (M6.2) | Moved to receive, as CL-008-02 moved to audio. |
| CL-006-03 stays in receive | FR-003 ("into spectrum") is receive's; the tests that verify it are the numbers of the rows | The display half is handed to the frontend. |
| Each clause derives from one FR | Method, "Decided" | FR-003, and FR-006 for CL-007-05. |
| The tie of an epoch reaches receive as an item | An item on a connection has features (structure rule 1); the capture clock is audio's (operator) | `CaptureTie` on audio's stream. In the code receive makes the tie itself. |
| The capture's event counts reach receive as an item | The same; audio's handover line names them | `CaptureMarks::events`. |
| The recording as samples | A stream joins producer and consumer directly (M5.4); the recording does not pass through audio (operator) | `RecordedSamples` in `RecordingTransfer.sysml`, the profile's interface, with its own block (up to 4096 samples, an end mark, no tie). |
| The clock's exchange | Operator's decision 2 | `StationsHeard` in the clock's interface file. |
| The station is on the air | Operator's decision 1; commands and state pass through the station service (M5.3) | `OnAir` on `ReceiveControl`. |
| The calls and the contact's state | M5.3; receive has no connection to qso or the profile | `ContactContext` on `ReceiveControl`, typed by the modes part's `APrioriContext`. In the code receive reads the contact. |
| Profile, boot and profile revision of a command | The station service is the gate (M5.3) | Handed to the station service; receive checks the generation. |
| `radio_unavailable` on a start | Receive does not know the radio type (M5.9) | Handed to the station service. |
| The kept records are read through the station service | M5.3; no connection joins receive's `decodes` to web | `ReadRecords`, `RecordsPage`, `CursorExpired` on `ReceiveControl`. Page bytes and the limit's range are the link's. |
| Field names | The code's names win; the wire names of a record are those of its fields (modes) | Data that goes to the wire as it is has the code's names (`first_sequence`); commands have the model's. |
| Status | A clause's status follows the code | All eight `implemented`; four were `partial`. |
| The filling in of hashed calls | Operator's decision 3 | Not in receive; work for the code. |

## Dropped as code or as history

- The worker thread, its join before the next admission as a mechanism (kept as "has not
  given up everything it held"), the two transforms of the code, block reuse, "one worker,
  two blocks".
- The limits of a block the window buffer takes (240 samples, order, marks): detail tests.
- The 8192 samples of history of the spectrum and its errors; the 128 blocks taken between
  decoder steps; the 2 ms and 20 ms waits; the 1024 bytes of the setting file.
- `Correlation`, `SourceTiming`'s native fields, `external_accuracy`, `segment`: inside, or
  audio's.
- `LatestDecodePeriod::abandoned` and `qualifiedWindow` of the old model: the code has
  `transmitted` instead.
- The package `IndependentVerification` (a second copy of eight test cases).
- The DT ranges of the old CL-007-05 (FT8 -1.6 to +0.56 s and the like): they follow from
  the window ends and carry a margin the code does not state.
- The cancel times of the old text (50 ms, 250 ms, 1 s): the code holds no such value for
  receive and no test of receive asserts one.
- All dates, issue numbers and slice names.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| package `WstxRecordingReceive` | `WstxReceiveJob` | old `OperatingScreen`, `Receive` text |
| `ReceiveLifecycle` (state machine) | `JobLifecycle` (rules over `ReceiveState`) | none found in the code |
| `LiveWindowSchedule` | `LiveWindows`, `WindowSchedule` | old CL-007-05 |
| `PublishResults`, `LiveResultWindow` | `LiveResults` | none |
| `LatestDecodePeriod` | `WstxDecodes::PeriodView` | none |
| `LiveTimedResultRecord` | `WstxDecodes::ResultRecord` (with period and DT) | none |
| `RelativeDecodeTiming` | `RecordTiming` | none |
| `CalculateSpectrum`, `ReplaySpectrum` | `ThinSpectrum`, `DetailedSpectrum`, `ReplayPacing` | none |
| `ReceiveCommand` (one empty item) | eight command items | none |
| port `timing : ~PeriodTimingPort` | `time : ~StationTimePort` | `Station.sysml` |
| `SpectrumFrame`, `DetailedSpectrumFrame` specializing `ProcessingResult` | items of their own with `RowIdentity` | none |
| `DecodesPort::result` only | `result` and `periodView` | `Station.sysml` uses the interface |

## Negative statements

| Old statement | Result |
|---|---|
| No file-decoding product operation | positive: a replay makes spectrum rows (`ReceiveKind::spectrum`); `ReadRecords` in the mode spectrum is `invalid_request` |
| Never auto-replays | dropped: no function replays by itself |
| No second worker | positive: one job at a time (`Admission`) |
| Never fabricates samples or UTC accuracy | audio's (CL-008-02); for receive positive: period and DT are absent without a tie |
| Receive never stops the capture for a transmission | positive: "the stream runs on; no epoch begins" (the code has `StopCapture`, so the rule is stated) |
| `complete` and `transmitted` never cleared | kept as "are set and are not cleared": the view is published again and could clear them |

## Settled from the code

- **FT4 windows** without a tie are 15 s long, every 7.5 s (the modes handover asked).
- **`last_overrun`** names the window that was given up; when a late window waited and a
  third came due, it is the waiting one that the code names. The model says "the one being
  decoded"; see the lines for the operator.
- **A row's `tx`** is true also when the row is finished while the station is on the air,
  not only for a transmit period.
- **The dump setting** that cannot be read is `storage_unavailable`, one that is not valid
  `invalid_diagnostics`.
- **A refused record** ends the job with `decode_limit`; a record over 2048 bytes is
  refused without stopping later ones in the code, the others stop them. The model states
  the common rule.
- **The order of the admission checks** is the code's: `busy` stands at two places.
- **The replay's pacing**: a row is published when the time of its last sample has passed,
  so a recording of 12120 samples completes after 1.01 s.
- **A test file the notes had missed**: `server/src/transmit/recording_tx_tests.rs` (the
  transmit periods), read in full.

## What the comparison with the code found

| Finding | Result |
|---|---|
| `recording.rs` holds receive, the import (profile), the band selection (station), the radio cache (radio control) and the drift (audio) | Named as receive's module; verdicts for `FILE_LIMIT` and the audio state texts. Work for the code. |
| Receive's limits are literals: 2048 records, 2 MiB, 2048 bytes, 60 dB, 16 periods, 90 dB, 4096, 480, 2400 | 9 verdicts "matched by reading". |
| The constants of the diagnostics are `pub(crate)` or private | 4 verdicts. |
| `LIVE_WINDOWS` is an array in units of 100 ns | 4 verdicts. |
| The error codes, states, modes and kinds are texts, not enumerations | 17 verdicts; all 27 literals of the four enumerations were checked by reading against the texts of `recording.rs` and `receive_diagnostics.rs`. |
| `DETAIL_RECENT` | The station link's; handed over. |
| The tool matched 10 names by itself | `size`, `hop` and 8 texts of the form `=> "..."`. |

## Edge cases and their homes

| Case | Home |
|---|---|
| two starts at once; a start while a job ends | `Admission` (busy), TC-018-003 (a), (c) |
| a job that fails and completes at the same moment | `JobLifecycle`, TC-018-003 (a) |
| stop of a job that has ended | `JobLifecycle`: answered unchanged |
| the stream does not start; does not close | `Admission`, `JobLifecycle`, TC-018-003 (d) |
| record 2048 and 2049; 2 MiB exactly | `LiveResults`, TC-009-004 (a), (c) |
| cursor before, at and beyond the kept range | `LiveResults`, TC-009-004 (b) |
| a frame with a frequency that is not a number | TC-009-004 (d) |
| the sequence, the view id and the generation at the end of their counts | `LiveResults`, `PeriodViews`, `Admission`; TC-009-004 (d), TC-007-012 (h); generation planned |
| gap of known length; loss of unknown length | `EpochHandling`, TC-009-004 (e), (f) |
| glitches that continue in time | TC-009-004 (g) |
| a frame exactly between two periods | `RecordTiming`, TC-007-012 (d) |
| no tie | `LiveWindows`, `RecordTiming`, `PeriodViews`, `TransmitPeriods`; TC-007-012 (a), (d), (e) |
| less than a frame of audio in a window | `LiveWindows`, TC-007-012 (b), TC-004-004 (b) |
| a window comes due while another is decoded | `LiveWindows`, TC-007-012 (g), TC-004-004 (c) |
| a late window that adds nothing | `WindowSchedule`, TC-004-004 (d) |
| the tie or the correction moves, forward and back, by more than a period | `WindowSchedule`, TC-004-004 (e), (f) |
| a recording of 1 sample; a row cut by the end | `ReplayPacing`, TC-010-004 (c), (d) |
| an input longer than a window | TC-010-001 (c), TC-010-004 (b) |
| the setting file missing, foreign, of another schema, with an extra key | `WindowDiagnostics`, TC-052-001 (c) |
| the dump folder full by count and by size | TC-052-001 (d), (e) |
| a write of the dump fails | `WindowDiagnostics`; no test |
| the station keys in the middle of a period | `TransmitPeriods`, TC-061-005 (b), (c) |
| a block that overlaps, is unmarked after a gap or holds a bad sample | detail tests (`receive_integration.rs`); audio's stream excludes them |

## Not carried over

| What | Why |
|---|---|
| TC-061-007, TC-045-002 | planned live cases without a test |
| The cancel times and the DT ranges | no evidence in the code |
| `CL-057-01`'s publication tick in receive | inside: how the link learns of a new view; handed to the station link |

## Size

Measured in characters by a script.

| | Old | New |
|---|---|---|
| `backend/receive/` without `Startup` | 103,744 | 49,592 |
| `Startup.sysml` (handed to the station service) | 8,785 | - |
| `ReceiveControl`, `Decodes`, `DisplayData` | 10,422 | 19,534 |
| Total without `Startup` | 114,166 | 69,126 |
| CL-061-04 and TC-061-005 (in transmit) | 4,795 | in the files above |

The part is 61 % of its old text. Where the size sits:

| Content | Characters |
|---|---|
| The eight test cases (the six that existed before: 14,623; TC-061-005: 1,903) | 21,049 |
| The eight clauses | 2,934 |
| Imports, status and level tags, derivations | 6,496 |
| Rule elements, the part and the three interface files | 38,647 |

The interface files grew from 10,422 to 19,534: `ReceiveControl` had one empty command
item and now holds eight commands, their answers, the state and the window counters.

## Checks

- `part_done.py receive`: all five tests pass: 29 identities, 7 files without a finding of
  the script, no validator error, 10 names matched with the code and 41 lines with a
  verdict, 8 test cases with their tests.
- `part_done.py clock`, `modes`, `audio`: still pass.
- The validator on `Station.sysml` with all built files reports no error on a line that
  joins receive to audio, the modes part or the clock. Its errors there name parts that
  are not built yet.
- `git status`: `docs/sysmlV2/` is the only change.
- Ledger when this was written: 560 rows, 134 arrived, 28 handed over, 10 not carried,
  3 retired, 11 new. These counts include what the three subagent sessions had entered
  by then and change while they work.

## The functional description

`_descriptions/receive.md`, from the new files alone. It found:

| Gap | Settled how |
|---|---|
| `ReceiveStatus::generation` said "for each admitted start", `EpochHandling` also raises it | Sentence completed in `ReceiveControl`. |
| How a live job gets and ends its stream, and a replay its recording | `JobLifecycle` names `StartCapture`, `StopCapture`, `OpenRecording`; `EpochHandling` names `EpochAccepted`. |
| How long after a prompt window ends its records are published | Not in the model; line 3 for the operator. |
| When `ReceiveStatus` is reported | As audio: "at the moment it is read". |
| What `limit` of `ReadRecords` may be | The link's (1 to 16); handed over. |

## Work for the code, when the new tree goes to main

- Receive reads the transmit owner (`observe_transmit`) and the contact's context; in the
  model the station service gives `OnAir` and `ContactContext`.
- Receive makes the tie of an epoch and follows the drift; in the model audio gives
  `CaptureTie`.
- Receive's publication fills in and teaches the hash table; in the model the modes part
  does.
- Receive tells the clock through `clock.station.observe` and `period_done`; the model
  names the exchange `StationsHeard`.
- `recording.rs` holds five parts; receive's own is the job, the live worker, the windows'
  schedule, the publication and the replay.
- The profile, boot and revision checks, and `radio_unavailable`, stand in receive's
  functions; in the model they are the station service's.
- Tests carry other numbers than their case now: the four window tests of
  `receive_integration.rs` (TC-002-001), five tests of `recording_tests.rs` (CL-010-09,
  TC-007-006), the lifecycle tests (TC-009-004 where the case is TC-018-003), and
  `recording_tx_tests.rs` stands in `transmit/`.
- Period lengths and nominal starts stand a fourth time in `period_parameters`.
- No test reads a value from the model.

## For the operator

One line at a time; each with a recommendation.

| # | Line | Recommendation |
|---|---|---|
| 1 | CL-061-04 and TC-061-005 moved from transmit to receive. | Keep. What the clause promises is done by receive; transmit only says when it is on the air. |
| 2 | **Decided by precedent (transmit line 5, operator 2026-11-15): the frontend's half is numbered when the frontend is built.** CL-006-03 stays in receive (the rows); the showing of spectrum and waterfall needs a new identity in the frontend. | Keep; number it when the frontend is built. |
| 3 | **Answered 2026-11-15: a promise of receive.** `WindowSchedule::ft8PublishedByMs` 15000 and `ft4PublishedByMs` 7500; TC-004-004 (i) binds the busy-period test, (j) is the planned FT4 line. The old CL-007-05 promised every FT8 decode by period start + 15.0 s and FT4 by + 7.5 s. Receive's model gives the window ends (13.8 s, 6.5 s) and no deadline. The FT8 deadline is shown by the modes part's TC-057-002 on the busy recording; nothing shows the FT4 one. WSJT-X (`widgets/mainwindow.cpp`, `m_hsymStop`) fixes when a decode starts (FT8 after 13.8 to 14.4 s, FT4 after 6.0 s) and states no time by which it ends. | Decide whether the deadline is a promise of receive (a value in `WindowSchedule`), stays with modes, or is dropped. Recommended: a value of receive, 15000 and 7500 ms, with the FT4 line "Planned, no test yet". |
| 4 | **Accepted (the main session merges, operator's rule for subagent parts).** Four built or taken-over files of other parts were changed (table at the top). | Accept; each is an item receive's exchange needs. `CaptureClock` and `AirClock` should name the new items when their parts are next touched. |
| 5 | `ContactContext`: the calls and the contact's state reach receive through the station service, not from qso directly. | Keep (M5.3). The alternative is a connection qso to receive. |
| 6 | The kept records are read through `ReceiveControl` (`ReadRecords`), because web has no `decodes` connection. | Keep; or give web a `decodes` connection, which M5.4 would also allow. |
| 7 | **Decided by rule (the model states the built behaviour): `LiveExchange` now says that a further window while the late window waits gives the waiting window up too and `last_overrun` names it (`recording.rs` 3020-3041).** `last_overrun` when a late window waited and a third window came due: the code names the waiting window, the model's sentence the one being decoded. | Leave the sentence; the case needs a decode longer than a whole period. Or state both. |
| 8 | The part's type is `ReceiveService` (the old name). The model describes jobs, not a pipeline. | Rename to `ReceiveService` with transmit, which has the same pattern (`TransmitService`). |
| 9 | **Decided by rule (planned lines stay as notes); the generation's end left with the generation (profile line 3).** Two planned lines: TC-018-003 (f) the refusals of a replay and the generation's end; TC-004-004 (i) FT4's window ends through the live job. | Keep as notes for the implementer. |
| 10 | Three subagent sessions build log, spots and udp, and flexAdapter (operator's request during this part). Their reports come separately. | - |

## Facts read for other parts

Taken over unchanged from the working notes of this part: what was read in the code and the tests about the startup function (station service), the routes and events (station link), the stored recording (profile) and the map of `recording.rs`. Each is a pointer for the part that takes it up, which reads the code again.

### Startup (read in full: old `Startup.sysml`, `receive_startup.rs`, `receive_startup_tests.rs`)

Code facts:
- File `receive-startup.json` in the profile folder, at most 1024 bytes:
  `{schema_version 1, profile_id, monitor_off_at_startup, last_receive null | {mode, band, input_device}}`.
  Mode spectrum, ft4 or ft8; band one of `selection::BANDS` or null; input_device 1 to 256
  characters without control characters. Unknown key refused.
- Load: missing file = defaults (off false, nothing stored), no error. Unreadable metadata =
  defaults with `storage_unavailable`. Present but foreign profile, other schema, bad mode
  or band, empty device, extra key, oversize, malformed = defaults with `invalid_startup`;
  the next write replaces it.
- Write: atomic; skipped when nothing changed and no storage error; a failed write keeps the
  old record, sets `storage_unavailable`, and receive goes on.
- A started receive (direct, or by a band selection) stores mode, band and input; the
  operator's stop stores `last_receive` null and keeps the setting.
- `set_monitor_off`: wrong profile `wrong_profile`, other boot `state_conflict`.
- Resume, once, on its own thread: off -> `off`; nothing stored -> `idle`; no audio input in
  the profile -> `failed` `audio_unconfigured`; else `waiting`. A stored band with a mode
  other than spectrum: the band selection the band button makes, retried every 250 ms while
  refused `radio_unavailable`, `busy` or `state_conflict` and the wait (`CAT_WAIT` 20 s) has
  not passed; success -> `started`; an operator's receive, selection or import found ->
  `skipped`; any other failure -> receive starts on the stored mode on the present dial ->
  `started_untuned` (stored band kept). Without a band: on a Flex profile wait up to the
  same time for the session, then start -> `started`. A failed start -> `failed` with the
  start's error.
- The resume uses the profile's audio input, not the stored `input_device`.
- Tests (all in TC-045-001): `startup_choice_round_trips_and_stop_clears`,
  `startup_file_invalid_or_foreign_is_ignored` (8 files),
  `startup_resume_starts_stored_band_and_mode` (ft4 20m -> 14080000 Hz),
  `startup_resume_off_or_stopped_stays_off`, `startup_resume_retries_transient_selection_refusals`
  (40m -> 7074000), `startup_resume_cat_unavailable_falls_back_to_plain_receive` (wait 300 ms),
  `startup_http_view_and_monitor_off_update`, `startup_resume_never_arms_or_keys`.
- TC-045-002 is a planned live case without a test: not carried (method).
- No test shows: `storage_unavailable` on a failed write; the Flex wait; `radio_unavailable`
  named in the old text for a Flex session that does not come (the code starts receive anyway
  and reports the start's error).

Sorting:
- CL-045-01 keeps the record; its routes go to the station link, its control to the frontend.
- CL-045-03 is a negative. The resume makes a band selection, which reaches CAT; a test
  exists (`startup_resume_never_arms_or_keys`). To decide by the rule on negatives.
- FRs: one each (method): CL-045-01 was FR-016 and FR-003; CL-045-02 FR-003 and FR-021;
  CL-045-03 FR-008.

**Open question for the operator (not yet asked):** who makes the band selection of a
resume in the model? In the code receive calls the selection itself (both live in
`Recording`). In the model the band and mode selection is the station service's
(`OperatingSelection`), and a function is commanded only by the station service (M5.3).
Candidates: (a) receive keeps the record and gives the station service the stored choice
at station start; the station service makes the selection and the start, and owns the
resume's states; CL-045-02 then moves to station. (b) receive asks the station service for
the selection and keeps the resume's states.

Asked on 2026-11-15 with three options: (a) record in receive, resume in station;
(b) all in receive, which asks the station service for the selection; (c) the whole
function to the station service, `Startup` moves from `backend/receive/` to
`backend/station/` (a change of M2.1). Recommended: (c). **Answer: (c).** Done: M2.1, the method, `files.md`, the ledger (five
identities handed over to station) and the handover list. Receive has four files now:
`Receive`, `ReceiveJob`, `Spectrum`, `LiveReceive`, and 19 identities.

### `recording.rs` 1000 to 1345: start and stop of live receive (read in full)

- Start is refused: `wrong_profile` (another profile); `state_conflict` (another boot,
  another generation, another profile revision); the admission's refusal (see `admit_for`,
  not yet read); `storage_unavailable` (no id); `radio_unavailable` (a Flex profile whose
  session is not ready); `audio_unavailable` (the worker cannot start; not Windows).
- A started job: a new id, the admitted generation, kind live, state running,
  processed_frames 0; audio state opening; the latest decode cleared. For ft4 or ft8 the
  station's operating mode becomes that mode.
- A Flex profile receives from its session through the same path; any other from the sound
  device named in the start.
- A finished worker is joined before another start is admitted (`live_owner_released`).
- Stop is refused: `wrong_profile`, `state_conflict`, `not_found` (no live receive, or
  another job id). A job that has not ended becomes cancelling; the shown spectrum frames
  are cleared; a band selection in progress that belongs to the job is cancelled. Stop
  forgets the stored receive choice (the station service's startup function now).
- `receive_start` (the operator's start) stores the choice with the band of that moment.

### `recording.rs` 544 to 772: views and what other functions read (read in full)

- The receive snapshot (`live_view`, the body of `GET /receive`): v, profile_id, boot_id,
  generation; `audio` {state, device_id, device_name, error, retry_after_ms, loss_epochs,
  last_loss} (closed with nulls and 0 without live receive); `source` {id, kind live,
  sample_rate 12000, channels 1, next_frame, segment}; `job` {id, mode, state, error,
  processed_frames, first_sequence, next_sequence, available_count, last_overrun
  {first_frame, end_frame}, latest_decode}; `clock` {basis system_utc, correlated,
  utc_anchor, canonical_anchor_frame, uncertainty_ns, external_accuracy unknown}.
- `receive_clock`, `capture_warning`: the capture clock's drift and warning (audio's in the
  model).
- Rx level: given only while audio runs and the station is not on the air.
- Transmit periods: receive reads the transmit owner's on-air state without waiting
  (`observe_transmit`); a period is a Tx period when its start is in the kept 16; a window
  is a Tx window when its period is. Without a tie there is no Tx period.
- What others read from receive: the live identity (source, job, generation, mode) for
  ft4 and ft8; the station's operating mode (the mode of the last started ft4 or ft8 job
  or selection; kept across a stop) which transmit is told after every change; the latest
  publication (id, first, next, complete, period); whether a decode runs and how many
  windows began (UDP Status); the kept records after a sequence; one record by its full
  identity.

### `recording.rs` 28 to 210: the stored recording as a stream (read in full)

- The WAV rules (`validate`) are the profile's (Recordings): at most 3,145,728 bytes
  (`FILE_LIMIT`), RIFF/WAVE, at most 64 chunks, one `fmt ` (PCM, mono, 12000 Hz, 16 bit)
  before one `data`, at most 1,440,000 frames (120 s). Errors `recording_limit`,
  `invalid_recording`, `unsupported_audio`, `storage_unavailable`. Hand to profile.
- What crosses from the profile's recording to receive (`SourceFile`): blocks of at most
  4096 frames, counted from 0 without a gap, 16-bit values divided by 32768, the last
  block marked as the end of the stream, no timing (no tie to UTC). A file that cannot be
  opened, is no longer valid, or differs from the stored frame count is
  `recording_unavailable`.
- This differs from audio's `SampleBlock` (at most 240 frames, no end mark, with timing):
  the port `recorded` needs its own item or a wider one.

### `recording.rs` 211 to 340 and 3761 to 3830: job, state, admission (read in full)

- `Job`: id, source_id (absent for a live job before its first epoch is taken up),
  generation, kind (`live` or `spectrum`), state, processed_frames, error.
- One job at a time for a station. Admission (`admit_for`) refuses:
  `busy` while the last live worker has not released its resources, while a band or mode
  selection runs that is not the one asking, while an import has not ended, or while a job
  has not ended; `state_conflict` for a selection token that is not current;
  `storage_unavailable` while the profile's storage has an error;
  `generation_exhausted` at the count's end. An admitted start raises the generation by
  one and clears the shown frames and the live state.
- The recording snapshot (`GET /recording`): v, profile_id, boot_id, generation, recording
  {id, rate_hz, frames, file_bytes, utc_anchor null}, source_error, storage_error, import,
  job. The pushed `recording.state`: generation, source_id, job_id, state, import.
- `State` also holds the selection (`operating`), the operating mode, and whether a decode
  runs with the count of windows begun.

Still to read: `recording.rs` 3533 to 3760 (open, cleanup) and 3830 to 4077 (import; the
profile's), `receive_http.rs`, the diagnostics module, then every test of the slice.

### `receive_http.rs` (read: pushed state, devices, start, stop, results)

All of it is transport (station link, M4.7); handed over, not receive's.
- `receive.state` data: profile_id, boot_id, generation, source_id, job_id, state, audio,
  clock {correlated, utc_anchor, canonical_anchor_frame, uncertainty_ns}, job {error,
  first_sequence, next_sequence, available_count, last_overrun, latest_decode}. The first
  one on a socket and one of a new identity hold every field; a later one the identity and
  only the audio, clock and job fields that changed.
- `GET /audio/devices` (audio's list by id and name): at most 64, id and name 1 to 256,
  reply at most 16384 bytes, else `device_limit`; `audio_unavailable`. Issue #223 asks for
  its tests. Audio's model has the endpoint list only; hand `devices` to audio or to the
  station link when read again.
- `POST /receive/start` {v, profile_id, boot_id, generation, profile_revision, mode}: mode
  spectrum, ft4 or ft8; the device is the profile's (`audio_unconfigured` without one);
  202 with the snapshot. A contact step follows a start and a stop, so a mode change
  reaches the contact at once (qso's).
- `POST /receive/stop` {v, profile_id, boot_id, generation, job_id}: 202.
- `GET /receive/results?source_id&job_id&generation&cursor&limit`: limit 1 to 16, default
  16; `cursor_expired` is 410; each record gets its entity and new-flags from the log
  (`dxcc::annotate`), which is not receive's.

### Test bodies read: `receive_http_tests.rs` 175 to 289 and 593 to 838

- `live_native_fixture_reaches_real_manager_http_and_browser_callsign` and the FT4 twin
  (release builds only): a stored two-channel fixture as live input through the real
  routes and a browser; the assertions are in `tests/receive-integration.test.cjs` (not
  yet read). After a stop audio is closed within 5 s.
- `live_native_busy_period_rows_promptly` (Windows, release only; tagged CL-057-01,
  CL-057-02, CL-007-05, TC-057-001, TC-057-002): the busy recording as live capture in two
  FT8 periods 30 s apart: each period's view has at least 25 records and is published not
  later than its period start + 15.0 s; the browser paints exactly those rows within
  300 ms of the publication (frontend's).
- Not receive's in this file: `live_native_page_kept_across_restart` (frontend, #22 and
  #50), `resource_station_process_delta_and_owner_release` (modes' TC-004-003, 96 MiB),
  the two `receive_state_*` tests (station link, CL-010-15).

### Test bodies read: `server/tests/source_contract.rs` (all), `tests/receive-integration.test.cjs` (outline)

- `source_contract.rs` tests the taking up of an epoch and the block's limits, which are
  audio's interface (`AudioStreams`): an acceptance with another number is refused
  (`staleAcknowledgement`); an acceptance that reuses the old source for a new epoch is
  refused (`invalidContext`); a block of 0 or 241 samples, a sample that is not finite, a
  block at the count's end: refused; a tie needs a UTC text and an uncertainty of at most
  2,000,000 ns. Audio's TC-002-001 (o) has the first; the others are detail of the
  interface. Nothing for receive.
- `tests/receive-integration.test.cjs` (107 lines) is the browser's side of TC-009-004: it
  reads `GET /receive` (audio running, source live, job mode), one results page (at most
  3072 bytes, record 0 is CQ K1ABC FN42 with the fixture's fields, start frame and
  frequency within tolerance), the DT cell shows a dash without a tie, the refusals of the
  routes, and that the record stays readable after a stop. Frontend and station link;
  for receive: a record stays readable after the job is stopped.
- `tests/recording.test.cjs` (608 lines): the browser's side of the recording and display
  cases (TC-010-00x, TC-018-00x). Frontend; not read for receive.

### Map of `server/src/recording.rs` (4,323 lines; one object `Recording` for many parts)

| Lines | Content | Part |
|---|---|---|
| 28 to 210 | WAV validation, `SourceFile` (reads a stored recording as blocks) | profile (Recordings) and receive (replay) |
| 211 to 340 | `Import`, `Job`, `State`, `Recording` | shared state |
| 341 to 543 | `LatestDecode`, `TxPeriods`, `LiveState`, `LiveInput`, error maps | receive (live) |
| 544 to 770 | `live_view`, `receive_clock`, `capture_warning`, `rx_level`, `observe_transmit`, records | receive; capture clock is audio's |
| 1000 to 1611 | `receive_start`, `receive_stop`, `receive_results`, `publish_*` | receive |
| 1612 to 2033 | hashes, profile change, radio connect, CAT maintain, radio cache | radio control, station |
| 2034 to 2495 | `selection_*` | station (OperatingSelection) |
| 2496 to 3074 | `LiveWorker`: run, epoch, step, track_clock, analyze | receive (live) |
| 3075 to 3395 | period parameters, `LIVE_WINDOWS`, `window_schedule`, `ClockTracker`, timing helpers | receive; `ClockTracker` is audio's |
| 3396 to 3532 | `DETAIL_RECENT`, `LiveSpectrum` | receive (spectrum) |
| 3533 to 3794 | `Resources`, `open`, cleanup, snapshot, state event | shared |
| 3795 to 4077 | admission, import: reserve, chunk, cancel | profile (Recordings) |
| 4078 to 4323 | `replay`, `cancel_job`, `run`, `release` | receive (job) |

Other receive code: `receive.rs` (270, the window buffer), `receive_http.rs` (452, routes),
`spectrum.rs` (64), `receive/receive_diagnostics.rs` (217).

## Decided by the operator (2026-11-15)

| Line | Answer | Done |
|---|---|---|
| 1 | CL-061-04 and TC-061-005 are receive's | stays |
| 3 | the deadline is a promise of receive | `WindowSchedule::ft8PublishedByMs`, `ft4PublishedByMs`; TC-004-004 (i), (j) |
| 5 | the calls and the contact's state reach receive through the station service | `ContactContext` stays |
| 6 | the kept records are read through the station service | `ReadRecords` stays |
| 8 | rename the part's type | `ReceiveService` in the four files, `Station.sysml` and the description. `tools/sysml/architecture-oracle.json` cites `ReceivePipeline`: work for the tools |
| from udp | udp learns the job from the period view | `WstxDecodes::JobIdentity`, `PeriodView::job`; the rows use the same element (`RowIdentity` is gone); udp's marker on `decodes` is gone |

Open: lines 2, 4, 7, 9.

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
| `interfaces/internal/ReceiveControl.sysml` | 306 to 312 | 14,345 to 14,589 |
| `backend/receive/Receive.sysml` | 38 to 41 | 1,791 to 1,973 |
| `backend/receive/ReceiveJob.sysml` | 321 to 311 | 19,725 to 18,931 |
| `_descriptions/receive.md` | 335 to 331 | 20,664 to 20,522 |

Moved in (receive defines it now):

| Element | What |
|---|---|
| `ReceiveConfig` (new, in `WstxReceiveControl`) | the configuration: `window_dump` = false, the window dump switch, with what it does |
| `ReceiveConfiguration` (new) | the item that carries it, at station start and whenever the station config changes; one item more on `ReceiveControlPort` |
| `ReceiveService` | one attribute: `config : ReceiveConfig` |

Left:

| Element | What left |
|---|---|
| `SetWindowDump` | the command and its place on the port |
| `DiagnosticsView` | `storage_error`; "the answer to an accepted SetWindowDump" |
| `ErrorCode` | the literal `invalid_diagnostics` (17 to 16). `storage_unavailable` stays: `Admission` gives it |
| `WindowDiagnostics` | the file `receive-diagnostics.json` with its form, its faults and the refusal of a setting that cannot be stored. It says: the dump is `ReceiveConfig::window_dump`, and a changed switch holds from the next window (`note_window` reads the switch for each window) |
| TC-052-001 (c) | "Switched on: the file holds ...; the dump is on after the station is opened again; a file of another profile, of schema version 2, and with one more key: off with invalid_diagnostics". Kept: the dump off until it is switched on, and no window. 5 lettered lines and the one test file as before |

The folder `diagnostic-windows` with the dumped windows stays receive's: they are data
files. No identity is retired or not carried: CL-052-01 promised the counters and the
dump, never the keeping of the switch.

Planned, no test yet: the profile keeps the switch across a restart; the line stands in the
profile's TC-022-002 (k).

Verdicts in `parts.json` (test 4: 10 matched, 42 with a verdict; before 10 and 43): one
taken out, model literal `ErrorCode::invalid_diagnostics`. Test 4 shows no new line.

Differences in the code that test 4 does not show (work for the code):
`receive/receive_diagnostics.rs` keeps `receive-diagnostics.json` (`Diagnostics::load`,
`set_window_dump` with `wrong_profile`, `state_conflict` and `storage_unavailable`), and
`diagnostics_view` gives `storage_error`.

Not decided, for the operator: nothing of receive's own. The resume of receive at station
start (the stored choice and "Monitor off at startup") is the station service's and is not
written (see the session's final message).

Not verified: of `receive_diagnostics_tests.rs` the test
`window_dump_setting_defaults_off_and_persists` was read in full; the others were not read
again.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-018-003 (`ReceiveJob.sysml`): StartReplay refused with no_recording, not_found and recording_unavailable.
- TC-004-004 (`LiveReceive.sysml`): the prompt and the late end of FT4 through the live job, and its views by the period start + 7.5 s.
