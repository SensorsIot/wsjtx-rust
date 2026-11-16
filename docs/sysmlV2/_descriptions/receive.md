# Receive

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the four files of
`backend/receive/`, `interfaces/internal/ReceiveControl.sysml`, `Decodes.sysml` and
`DisplayData.sysml`, and of `Station.sysml`, `AudioStreams.sysml`, `ModeProcessing.sysml`,
`StationTime.sysml` and `RecordingTransfer.sysml` only the elements receive uses. Not read:
the code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Job | one piece of work of receive; one runs at a time | `JobView` |
| Live job | a job on the receive stream, in the mode spectrum, FT4 or FT8 | `ReceiveKind::live`, `ReceiveMode` |
| Replay | a job that shows the stored recording as spectrum rows | `ReceiveKind::spectrum` |
| Epoch | a stretch of the receive stream without a loss of unknown length | `EpochProposal` (audio's) |
| Tie | where an epoch stands on the PC clock | `CaptureTie` (audio's) |
| Window | a run of the latest samples given to the modes part to decode | `LiveWindows` |
| Prompt and late window | the two windows of a period of a tied epoch | `WindowSchedule` |
| Record | one decoded frame with its number, period and DT | `ResultRecord` |
| View | which records are the decodes of one period | `PeriodView` |
| Row | one line of the spectrum: thin (one second, 128 levels) or detailed (0.2 s, 1024 levels) | `SpectrumFrame`, `DetailedSpectrumFrame` |
| Transmit period | a period the station was on the air in | `TransmitPeriods` |

"Spectrum" has two meanings, each with its own element: the mode of a live job that only
makes rows (`ReceiveMode::spectrum`) and the kind of job that replays a recording
(`ReceiveKind::spectrum`).

## 2. Place in the system

Position: `Station.backend.stations.receive`, a `ReceiveService`.

| Port of receive | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `jobs` | `~ReceiveControlPort` | station service, `receive` | `ReceiveControl` | in: `ReceiveConfiguration`, `StartLive`, `StopLive`, `StartReplay`, `CancelJob`, `OnAir`, `ContactContext`, `ReadRecords`, `ReadDiagnostics`; out: `JobAccepted`, `Refused`, `RecordsPage`, `CursorExpired`, `DiagnosticsView`, `ReceiveStatus` |
| `audio` | `~ReceiveSamples` | audio, `receive` | `ReceiveSamplesLink` | in: `EpochProposal`, `CaptureTie`, `SampleBlock`, `CaptureMarks`, `StreamFailure`; out: `StartCapture`, `StopCapture`, `EpochAccepted` |
| `recorded` | `~RecordedSamples` | profile, `recordedSamples` | `RecordedSamplesLink` | out: `OpenRecording`; in: `RecordedBlock`, `RecordingUnreadable` |
| `processing` | `ReceiveProcessing` | modes, `receive` | `ReceiveProcessingLink` | out: `ProcessingRequest`, `Cancel`, `CallsUpdate`; in: `ProcessingResult`, `WindowEnd` |
| `decodes` | `DecodesPort` | ranking, qso, udp (`decodes` each) | `Decodes` | out: `ResultRecord`, `PeriodView` |
| `display` | `DisplayDataPort` | web, auto (`display` each) | `DisplayData` | out: `SpectrumFrame`, `DetailedSpectrumFrame` |
| `time` | `~StationTimePort` | clock, `time` | `StationTimeLink` | in: `StationTime` |
| `heard` | `StationsHeardPort` | clock, `heard` | `StationsHeard` | out: `StationHeard`, `WindowDone` |

Receive cannot reach the radio's control path, the sound device, transmit, the log or the
browser. It learns that the station is on the air, and the station's calls and contact,
from the station service (`OnAir`, `ContactContext`). It names no device and no radio
type: it asks audio for the stream and the profile for the recording.

## 3. Purpose and requirements

Receive runs one job at a time. A live job turns the receive stream into spectrum rows
and, for FT4 or FT8, into the decoded frames of each period; a replay turns the stored
recording into spectrum rows. `Station.sysml` gives FR-003 and FR-006 to receive.

| Clause | Promise | Elements | From | Status |
|---|---|---|---|---|
| CL-006-02 | report the state of the job at every moment; give the end state only when the job has let go of its source | `JobLifecycle` | FR-003 | implemented |
| CL-006-04 | run one job at a time; answer every start that is not admitted with the reason | `Admission` | FR-003 | implemented |
| CL-008-03 | number the records of a live job without a gap, keep the latest for reading, go on under a new job identity after a loss in the capture | `LiveResults`, `EpochHandling` | FR-003 | implemented |
| CL-052-01 | keep the counters of the latest decode windows; while the dump is on, write each FT8 prompt window to a file | `WindowDiagnostics` | FR-003 | implemented |
| CL-006-03 | make a thin row for each second and a detailed row for each fifth of a second, by the stated transform | `ThinSpectrum`, `DetailedSpectrum`, `ReplayPacing` | FR-003 | implemented |
| CL-007-01 | in a live FT4 or FT8 job, give the stream to the modes part in windows; publish every frame with period and DT, and each period's decodes as one view | `LiveWindows`, `RecordTiming`, `PeriodViews` | FR-003 | implemented |
| CL-007-05 | end the windows at fixed moments of each period of station time; keep one prompt and one late window per period when the tie or the correction moves | `WindowSchedule` | FR-006 | implemented |
| CL-061-04 | decode nothing and measure no level in a period the station transmitted in; mark its view and rows | `TransmitPeriods`, `RxLevel` | FR-003 | implemented |

The status is the model's declaration, not a test result.

## 4. Data and rules

### The job (`JobView`, `ReceiveStatus`)

| Field | Rule |
|---|---|
| `id` | new for every admitted start, and for every later epoch of a live job |
| `source_id` | the recording, or the current epoch of the stream; absent for a live job before its first epoch |
| `kind` | `live` or `spectrum` |
| `state` | `running`, `cancelling`, `completed`, `cancelled`, `failed` |
| `processed_frames` | how far the job has come; the length of the recording when a replay has completed |
| `error` | present in the state failed |

`ReceiveStatus` holds the job last admitted (also after its end), the
state of live receive (`LiveView`, from the admission of a live job until the next admitted
start), the view last published, whether a window is being decoded and how many windows
were given to the decoder since station start.

### Admission (`Admission`)

A start is refused with the first of these that holds.

| # | Answer | When |
|---|---|---|
| 2 | `recording_unavailable`, `no_recording`, `not_found` | for a replay: the stored recording is damaged; none is stored; the command names another recording |
| 3 | `busy` | a live job that has ended has not given up everything it held; a band or mode selection runs that did not make this start |
| 4 | `storage_unavailable` | the storage of the profile has an error |
| 5 | `busy` | a job or an import of a recording has not ended |

An admitted start clears the rows, records and views of the job
before it. A live start whose stream cannot be started is answered `audio_unavailable`;
its job has failed. `StopLive` is answered `not_found`
without a live job or for another job, `CancelJob` for another job.

### Records (`ResultRecord`, `LiveResults`)

A record is the frame of the modes part plus `sequence` (0 for the first record of a job),
`period_start_utc` and `dt_seconds` (both absent while the epoch is not tied).

| Rule | Value |
|---|---|
| records kept | the latest 2048 and at most 2 MiB; the oldest leave and `first_sequence` grows |
| a record is refused | longer than 2048 bytes; frequency not a number or outside 200 to 3500 Hz; SNR not a number or beyond 60 dB either way; frame starting at or after the sample the stream has reached; sequence count at its end (`counter_exhausted`) |
| after a refusal | the window's decoding ends, the job fails with `decode_limit`, no later frame becomes a record |
| kept records are readable | until the next start is admitted, also after the job has ended |

| `ReadRecords` | Answer |
|---|---|
| another source or job, or no live job | `Refused` `not_found` |
| mode spectrum; cursor beyond `next_sequence` | `Refused` `invalid_request` |
| cursor before `first_sequence` | `CursorExpired` with `first_sequence` and `next_sequence` |
| otherwise | `RecordsPage`: the records from the cursor, at most `limit`, `more`, and the view last published |

### Timing of a record (`RecordTiming`)

The station time of a sample is the PC clock time its epoch's tie gives it, plus the
clock's correction. A frame belongs to the period whose nominal start is nearest to its
start (the later one when two are equally near); its DT is its start against that nominal
start and lies within half a period either way.

### The view of a period (`PeriodView`, `PeriodViews`)

| Field | Rule |
|---|---|
| `id` | 1 for the first view of a job, one higher for each view of another period |
| `first_sequence`, `next_sequence` | the kept records of the period; equal when it has none |
| `period_start_utc` | absent while the epoch is not tied; the view then spans the records of one window |
| `complete` | a window of the period was decoded to its end |
| `transmitted` | the station transmitted in the period; no record |

### Spectrum rows (`ThinSpectrum`, `DetailedSpectrum`)

| | Thin | Detailed |
|---|---|---|
| window | 2048 samples every 256 | 4096 samples every 480 |
| weighting | periodic Hann; amplitude = 2 x magnitude / sum of weights, bin 0 once | the same |
| kept | lowest 512 bins (0 to 3000 Hz) in 128 groups of 4; the largest of a group | lowest 1024 bins, each its own |
| row | one second; per group the largest value of the windows that start in it | 2400 samples; per bin the root of the mean squared amplitude of the windows that start in it |
| level | 20 log10 limited to -120 to 0, plus 120, rounded: 0 to 120 | the same |
| after a break in the stream | windows start anew at the next whole second | at the next multiple of 2400 |

A row carries the job it belongs to (`RowIdentity`), its sequence, its first and end
sample and `tx`.

### The windows of a tied epoch (`WindowSchedule`)

| Window | FT8 ends after the period start | FT4 | Length |
|---|---|---|---|
| prompt | 13.8 s | 6.5 s | one period |
| late | 15.7 s | 7.9 s | one period |

### Window counters and the dump (`WindowCounters`, `WindowDiagnostics`)

Receive keeps the counters of the latest 20 windows: mode, origin, length, late, the
period start as sample and as UTC, the window's offset from it, the zeros (count, longest
run, and those among the first 141696 samples of the period), the zero-filled and glitch
frames and the event counts of the capture, the drift, and the name of the dump file.

| Dump | Rule |
|---|---|
| setting | `ReceiveConfig::window_dump`, receive's configuration: off until switched on; the station service gives it in `ReceiveConfiguration`, at station start and whenever the station config changes; the profile keeps it in the station config; a changed switch holds from the next window |
| what is written | each FT8 prompt window: a WAV file (mono, 12 kHz, 16 bit) and a JSON file with the counters, in the folder `diagnostic-windows` |
| kept | the newest 20 windows, at most 16 MiB |
| a failed write | `dump_error` `dump_failed` until the next good write; decoding unchanged |

### The receive level (`RxLevel`)

10 log10 of the mean squared sample with full scale as 32768, rounded, 0 to 90; one value
from about a second of samples. Absent while the capture does not run, while the station is
on the air and for the rest of a transmit period.

## 5. Behaviour

### The states of a job (`JobLifecycle`)

| Occasion | Result |
|---|---|
| a start is admitted | a job `running`; a live job asks audio for the stream, a replay asks the profile for the recording |
| `StopLive`, `CancelJob` for a job that has not ended | `cancelling`; nothing more of the job is published |
| the job has let go of its source and its end was asked for | `cancelled`, also when it failed or completed meanwhile |
| ... and it had an error | `failed` with the error |
| ... otherwise (a replay that has shown every sample) | `completed` |
| a live job's stream does not close | the state stays until it is closed; then `audio_close_failed` unless the end was asked for |
| `StopLive`, `CancelJob` for a job that has ended | answered with the job unchanged |

**A job gets no end state while it still holds its source.**

| Error of the stream | Job error |
|---|---|
| `unsupportedFormat` | `unsupported_audio` |
| `failedClose` | `audio_close_failed` |
| `counterExhausted` | `counter_exhausted` |
| `cancelled` | `cancelled` |
| the end of the stream | `audio_unavailable` |
| `unavailable` | none: the job goes on (below) |
| every other | `audio_failed` |

### Epochs (`EpochHandling`)

| Occasion | Job id | Records | Decoder memory, windows, spectrum | View, `last_overrun` |
|---|---|---|---|---|
| first epoch of a job | kept | - | start | - |
| later epoch | new id | numbered from 0 again | start anew | cleared |
| gap of known length | kept | kept | decoder memory cleared | view cleared |
| stream fails `unavailable` | new if a source had been taken up | - | source forgotten; goes on with a new epoch | - |
| later epoch cannot get a source id | job `failed` (`storage_unavailable`) | | | |

`loss_epochs` counts the later epochs whose reason is a loss in the capture; `last_loss`
is the trigger of the latest.

### Windows (`LiveWindows`, `WindowSchedule`)

| Situation | Windows |
|---|---|
| epoch not tied | one ends at every multiple of the period length in the sample count; two periods long |
| epoch tied | prompt and late window of each period (section 4) |
| less than one frame of the mode since the last break | no window |
| another window comes due while one is decoded | the one being decoded is given up: `last_overrun` names it, its view has `complete` false |
| the late window comes due while the prompt window is decoded | it waits |
| the tie or the correction moves | every end moves by the same amount; one moved into the past ends with the next sample; none is left out, repeated or moved by a period |
| mode spectrum | none |

Each window goes to the modes part as one request with the place of its first sample, the
place where the period of its middle begins, and the contact context last given. After
every decoded window receive tells the clock (`WindowDone`); for every record that names
its sender it gives the clock the sender, the SNR and the DT without the clock's
correction (`StationHeard`).

### Publishing a view (`PeriodViews`)

| Situation | Result |
|---|---|
| a window was decoded (running job) | the view of its period is published |
| the window begins after the nominal start of its period and is not the late window | nothing |
| the period is earlier than the one last published | nothing |
| same period, records beginning at the same `first_sequence` | the same id; `next_sequence` grows; `complete` and `transmitted` are set, not cleared |
| otherwise | a view with the next id; at the end of the id count `counter_exhausted`, and the view stays |
| the job ends | the view stays as it was |

### Transmit periods (`TransmitPeriods`)

| Rule | |
|---|---|
| which period | one in which `OnAir::onAir` was true, and the one `lastPeriodStartMs` names; the latest 16 are remembered |
| its windows | not decoded; the view has `transmitted` true, `complete` false, no record |
| rows | `tx` true when their middle lies in such a period, and when they are finished while the station is on the air |
| the stream | runs on; no epoch begins |
| epoch not tied | no transmit period; windows are decoded; only the level stops while on the air |

### Publishing rows (`ReplayPacing`)

A live job publishes a row when the stream has brought the last window that starts in it.
A replay publishes in the time of the recording: a detailed row not before the time of its
last sample has passed since the start of the job. Its last rows are shorter.

## 6. Implemented in and tested by

The part names `server/src/recording.rs`, `server/src/receive.rs`, `server/src/spectrum.rs`
and `server/src/receive/receive_diagnostics.rs`. Detail tests:
`server/src/recording_tests.rs` and `server/tests/receive_integration.rs`, for the
conversion of a time to UTC text and the limits of a block the window cutting takes.

## 7. What it relies on from outside

| Element | Needed from it |
|---|---|
| `WstxAudioStreams` (audio) | the stream, its epochs, the tie, the marks and event counts, the stream's errors |
| `WstxModeProcessing` (modes) | the request for a window, the decoded frame, `DecodeError`, `Period`, `DecodeBand`, `APrioriContext` |
| `WstxStationTime` (clock) | station time; the two items receive gives the clock |
| `WstxRecordingTransfer` (profile) | the stored recording as blocks |

Named in text without an element: the import of a recording and the band or mode
selection (both make a start `busy`); the storage of the profile and its folder.

## 8. Differences from a named reference

Reference: WSJT-X at the behaviour baseline.

| Topic | Reference | This product | In the model |
|---|---|---|---|
| The DT of a decode | reported with each decode | the same, one DT in a record | follows the source (`RecordTiming`) |
| While the station transmits | stops its audio input and draws no waterfall row | keeps the stream and marks the rows | deliberate (`TransmitPeriods`) |

## 9. Verification

| Case | Verifies | Shows | Declared |
|---|---|---|---|
| TC-018-003 | CL-006-02, CL-006-04 | a job holds its state until it has let go; busy meanwhile; a failed live start | cost 2, development PC, implemented; five named tests |
| TC-009-004 | CL-008-03 | numbering, the 2048 and 2 MiB limits, reading by cursor, refused frames; job identity across a gap and a loss | cost 2, development PC, implemented; four named tests |
| TC-052-001 | CL-052-01 | zero counts, the WAV file, the dump off and on, file names and what is kept | cost 2, development PC, implemented; one test file |
| TC-010-001 | CL-006-03 | the thin values against a transform computed apart; the last row of a replay | cost 2, development PC, implemented; two named tests |
| TC-010-004 | CL-006-03 | the detailed values and rows likewise | cost 2, development PC, implemented; one named test |
| TC-007-012 | CL-007-01 | window cutting; period and DT; views; overrun; the DT given to the clock | cost 2, development PC, implemented; eight named tests |
| TC-004-004 | CL-007-05 | the schedule, the late window, moved ends, steps of station time | cost 2, development PC, implemented; eight named tests |
| TC-061-005 | CL-061-04 | no decode, no level and marked rows in a transmit period | cost 2, development PC, implemented; one test file |

Every clause has a case. Lines the cases mark "Planned, no test yet": TC-018-003 (f) the
refusals of a replay; TC-004-004 (i) the FT4 ends through the
live job.

## 10. Open points, gaps and disagreements

**Marked by the model:** none in the receive files.

**Gaps:**

| Element | Missing |
|---|---|
| `ReceiveStatus` | when receive reports it: on every change, or when asked. The model says "at the moment it is read". |
| `ReceiveConfiguration`, `ReadDiagnostics`, `OnAir`, `ContactContext` | whether they are taken while no job runs. Nothing limits them, so: always. (Assumed.) |
| `LiveResults` | what `limit` may be; the model leaves it to the asker. |
| `WindowSchedule` | how long after a prompt window ends its records are published; the model gives the window ends only. |
| `ThinSpectrum` | the rows of a live job in the mode spectrum and in FT4 or FT8 are the same; stated only by the absence of a rule. |

**Disagreements and observations:**

- `ErrorCode::busy` has two causes at two places of the order (`Admission`).
- `ReceiveService` is named a pipeline; the model describes jobs.
- Weak links (by name in text): the import of a recording, the band or mode selection.
