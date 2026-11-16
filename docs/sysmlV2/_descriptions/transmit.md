# Transmit

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the four files of
`backend/transmit/`, `interfaces/internal/TransmitControl.sysml`, and of `Station.sysml`,
`AudioStreams.sysml`, `ModeProcessing.sysml`, `StationTime.sysml` and
`OperatingChain.sysml` only the elements transmit uses. Not read: the code, the issues, the
old model, and `Keying.sysml`, which radio control's part writes.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Transmit state | whether the station may transmit: on (armed) or off (disarmed) | `ArmState` |
| Stop | anything that switches the transmit state off | `Stops`, `DisarmCause` |
| Request | one message for one period, given by the contact | `TransmitRequest` (operating chain) |
| Outcome | one step in the life of a request | `TransmitOutcome`, `OutcomeKind` |
| Transmission | a request on the air: output open, radio keyed, waveform played, radio released | `Transmission` |
| Capability | whether the station can transmit at all | `Capability` |
| Start window | the part of a period in which a transmission may still start | `StartWindow` |
| Tone | the unmodulated Tune tone | `TuneTone` |
| Configuration | what the operator sets of transmitting: manual or automatic, the Tx level of each band, the power limit, the number of calls of the Tx watchdog and the Tune limit | `TransmitConfig` |
| Tx watchdog | the repetition limit of one message; the contact's (qso), which gives a Disarm with txWatchdog | `DisarmCause::txWatchdog` |
| Tune limit | how long a Tune tone may last | `TransmitConfig::tuneSeconds`, `TuneTone` |
| Tx level | how far the audio is turned down, in dB, one for each band | `TxLevel`, `BandLevel` |
| Manual, automatic | whether the operator sets the Tx level with a slider or transmit finds and corrects it | `LevelMode` |
| Finding | in automatic, the Tune tone first finds the Tx level with the radio's meters | `LevelFinding` |
| Profile power | the output power the Tx level is not to drive above | `TransmitConfig::powerLimitPct` |
| Ceiling | a level the supervision does not go up to again | `LevelMonitor` |
| On the air | the radio's switch is not released, a transmission's audio runs or the tone is on | `TransmitStatus::on_air` |

"Refused" has two meanings, each with its element: the outcome of a request
(`OutcomeKind::refused`) and the cause of a stop (`DisarmCause::refused`). "Failed"
likewise: `OutcomeKind::failed`, `DisarmCause::failed`, `StartupRelease::failed`.

## 2. Place in the system

Position: `Station.backend.stations.transmit`, a `TransmitService`.

| Port of transmit | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `operations` | `~TransmitControlPort` | station service, `transmit` | `TransmitControl` | in: `Halt`, `StationMode`, `StationBand`, `TransmitProfile`, `ProcessEnds`; out: `HaltReceipt`, `TransmitOutcome`, `TransmitStatus`, `TxLevelStatus`, `LevelFound` |
| `contacts` | `~MessageToSendPort` | qso, `transmit` | `MessageToSend` | in: `TransmitRequest`, `Arm`, `Disarm`, `Abort`, `SetTune`, `StepBegins`; out: `CommandAnswer`, `TransmitOutcome`, `TransmitStatus` |
| `encode` | `EncodeProcessing` | modes, `encode` | `EncodeProcessingLink` | out: `EncodeRequest`, `AcceptedMessage`; in: `Waveform`, `EncodeRefusal` |
| `audio` | `Playback` | audio, `transmit` | `PlaybackLink` | out: `OpenOutput`, `PlayProgram`, `SetScale`, `StopOutput`; in: `OutputStatus`, `PlayRefused` |
| `control` | not typed (marker) | radio control, `transmit` | `KeyingLink` in `Station.sysml` | key, release, their confirmation or failure, whether the radio is ready and transmits, the meters |
| `time` | `~StationTimePort` | clock, `time` | `StationTimeLink` | in: `StationTime` |

Transmit cannot reach the sound device, the radio's own connection, receive, the log or
the browser. It names no output device and no radio type: it asks audio to open the
profile's output and radio control to key. It learns the profile's values, the station's
mode and the end of the process from the station service. Receive learns that the station
is on the air from the station service, which reads it in `TransmitStatus`.

The contact's commands come only over `contacts`; the operator's starts and Tune reach
transmit through qso. The station service gives Halt and the station's facts over
`operations`.

## 3. Purpose and requirements

Transmit holds the transmit state, puts each admitted request on the air in its period,
stops at once on Halt, releases the radio on every failure, plays the Tune tone, keeps
the repetition limit and the level of its audio. `Station.sysml` gives FR-006 and FR-008
to transmit.

| Clause | Promise | Elements | From | Status |
|---|---|---|---|---|
| CL-009-02 | plan the start of a transmission for its period from station time; start a late one inside the start window by leaving out what has passed; refuse what cannot start in that period | `StartPlan` | FR-006 | implemented |
| CL-111-01 | hold the one transmit state, off at every station start; switch it on only by an admitted Arm; report it with the cause of its last change in each direction | `TransmitArming` | FR-008 | implemented |
| CL-111-03 | switch the state off at every stop with its cause; of several stops in one step of the contact show the first of a fixed order | `Stops` | FR-008 | implemented |
| CL-009-03 | put every admitted request on the air in its period, keyed before its audio and released after its last sample; report every step as an outcome | `Admission`, `Transmission` | FR-006 | implemented |
| CL-009-04 | end a transmission or a tone at once on Halt; release the radio on every failure; switch off a radio found transmitting at station start or left keyed at the end of the process | `HaltTransmit`, `Failures`, `SafetyReleases` | FR-008 | implemented |
| CL-111-06 | play the Tune tone on request, whatever the transmit state and without changing it; end it at its limit | `TuneTone` | FR-008 | implemented |
| CL-044-12 | play the audio at the Tx level of the station's band, set by the operator in manual and found with the Tune tone in automatic | `TxLevel`, `LevelFinding` | FR-008 | implemented |
| CL-044-14 | read the meters once in every transmission, correct the level in automatic by one step at most for the next, report trouble that lasts, halt on an SWR fault | `LevelMonitor` | FR-008 | implemented |

The status is the model's declaration, not a test result.

## 4. Data and rules

### The state transmit reports (`TransmitStatus`)

| Field | Type | Meaning, and when absent |
|---|---|---|
| `capability` | `Capability` | unsupported: the profile is not set up to transmit; unavailable: set up, and the radio is not ready; available |
| `arm_state` | `ArmState` | the transmit state |
| `last_disarm_cause` | `DisarmCause` | why it last went off; startup at station start |
| `last_arm_cause` | `ArmCause` | operator or auto; absent until first switched on |
| `stopped_in_step` | Boolean | a stop happened since the last `StepBegins` |
| `tune` | Boolean | the tone is on |
| `pending_sequence` | Integer | the request that waits: the one for a later period, else the one whose audio has not started; absent without one |
| `last_text` | String | the message last put on the air |
| `last_period_utc_ms` | Integer | the period of the transmission whose audio started last; absent before the first |
| `halt_state` | `HaltState` | idle, stopped or pending: the result of the last Halt |
| `refusal` | `TransmitRefusal` | the latest refusal; absent after an accepted request, Arm or tone |
| `ptt` | `PttState` | released, keyed, or indeterminate (not confirmed; the radio may transmit) |
| `transmitting` | Boolean | the audio of a transmission runs or the tone is on |
| `on_air` | Boolean | `ptt` is not released, the audio of a transmission runs or the tone is on |
| `tune_remaining_seconds` | Integer | what is left of the running tone before its limit, rounded up; 0 without one |
| `outcomes` | `TransmitOutcome` list | the latest 32, the oldest first |
| `startup_release` | `StartupRelease` | pending, notNeeded, released or failed |

### An outcome (`TransmitOutcome`)

| Field | Meaning |
|---|---|
| `outcome_sequence` | counts the outcomes since station start, from 1 |
| `request_sequence` | the request |
| `kind` | accepted, replaced, started, completed, halted, aborted, refused, failed |
| `refusal` | present for refused |
| `failure` | present for failed |
| `audio_start_utc_ms` | present for started and completed, and for failed when the audio had started |

### Commands and their answers (`Halt` on `TransmitControlPort`, the others on `MessageToSendPort`)

| Command | Carries | Answer |
|---|---|---|
| `Arm` | the cause operator or auto | `CommandAnswer` |
| `Disarm` | the cause | `CommandAnswer` |
| `Abort` | the cause | `CommandAnswer` |
| `Halt` | a command id | `HaltReceipt` with the halt state |
| `SetTune` | on or off; to switch on the offset | `CommandAnswer` |
| `StepBegins`, `StationMode`, `StationBand`, `TransmitProfile`, `ProcessEnds` | see their rows in section 5 | none |

Transmit has no command that sets a value of its configuration: the station service gives
the configuration in `TransmitProfile`, at station start and whenever the station config
changes. A level transmit finds goes the other way as `LevelFound` and is answered by a
`TransmitProfile`: with that level when the profile has saved it, with the level before
when it could not.

### Arming (`TransmitArming`)

An Arm is refused with the first that holds; a refused Arm changes nothing but
`refusal`.

| Order | Condition | Refusal |
|---|---|---|
| 1 | the capability is unsupported | transmitUnsupported |
| 2 | the capability is unavailable | radioUnavailable |
| 3 | `ptt` is indeterminate, `startup_release` is failed, or transmit itself has failed | radioUnavailable |

### Admission of a request (`Admission`)

A request is refused with the first that holds; its outcome is refused.

| Order | Condition | Refusal | A state that is on |
|---|---|---|---|
| 1 | the sequence is 0 or not higher than every one before | duplicateSequence | stays on |
| 2 | the capability is unsupported | transmitUnsupported | goes off, refused |
| 3 | the transmit state is off | notArmed | - |
| 4 | the capability is not available | radioUnavailable | goes off, refused |
| 5 | the tone is on | busy | goes off, refused |
| 6 | another mode than the station's (an absent station mode refuses nothing) | staleRequest | goes off, refused |
| 7 | the start cannot be planned now | clockNotSynchronized, misalignedPeriod, stalePeriod | goes off, refused |
| 8 | the audio of the transmission for the same period and mode has started | audioStarted | stays on |
| 9 | the modes part refuses the message at 48 kHz | frequencyOutOfRange for that reason, packRefused for every other | goes off, refused |

At most two requests are held: the current one and one for a later period.

| The current request is | An admitted request for | Result |
|---|---|---|
| not keyed | any period | takes its place; the old one is replaced |
| keyed, audio not started | the same period and mode | takes its place; the old one is replaced |
| keyed | another period | becomes the next one; a next one already held is replaced |

Every admitted request is given to the modes part as `AcceptedMessage`.

### The start plan (`StartPlan`, `StartWindow`, `Period`)

| | FT8 | FT4 |
|---|---|---|
| Period length | 15000 ms | 7500 ms |
| Audio delay after the period start | 500 ms | 300 ms, counted to the ramp symbol |
| Latest share of the period | 75 % | 75 % |
| Frame length | 12640 ms | 5040 ms |

The window of a period is open until the earlier of: 75 % of the period, or the audio
delay plus the frame length. Computed from these values: FT8 until 11250 ms, FT4 until
5340 ms.

| When the plan is made | Result |
|---|---|
| station time is not synchronized | clockNotSynchronized |
| the period start is not a whole multiple of the period length | misalignedPeriod |
| up to the audio delay after the period start | audio at the audio delay, from sample 0 |
| later, the window open | audio at once, from the sample that would play then (the time since the audio delay in samples, rounded down) |
| the window closed | stalePeriod; the request is not moved to a later period |

The next period of a parity is the earliest period of that parity whose window is open.

### Timing of a transmission (`Transmission`, `HaltTransmit`, `Failures`, `SafetyReleases`)

| Value | Is |
|---|---|
| `releaseMarginMs` 1000 | the release deadline is the audio start plus the audio still to play plus this |
| `releaseBoundFt8Ms` 14500, `releaseBoundFt4Ms` 7000 | the deadline is not later than this after the period start |
| `haltBoundMs` 250 | from Halt to the stopped output and the confirmed release, while radio control answers |
| `keptReceipts` 16 | a Halt that repeats one of the latest ids gets the first receipt |
| `keyExchangeMaxMs` 1000 | the wait for a key or a release to be confirmed |
| `exitReleaseMaxMs` 500 | the wait for the release at the end of the process |
| `keptOutcomes` 32 | the outcomes `TransmitStatus` holds |

### The tone (`TuneTone`)

The offset is from 200 to 2950 Hz. A SetTune to switch on is refused with the first that
holds: transmitUnsupported (capability unsupported); radioUnavailable (capability not
available, `ptt` indeterminate, startup release failed, transmit failed); busy (a request
is held or a tone is on); frequencyOutOfRange.

### The Tx level (`TxLevel`, `TxLevelStatus`)

| Value | Is |
|---|---|
| `levelMinDb` -40, `levelMaxDb` 0 | the range, in whole dB |
| `playbackScale` 0.5 | the scale at 0 dB; the scale of a level is this times 10 to the power of level / 20 |
| `tuneReadMs` 1000 | how often the meters are read while the tone is on outside a finding |
| `meterReadMaxMs` 400 | the wait for one reading |

The level that counts is the entry of the station's band (`StationBand`) in
`TransmitConfig::levels`, taken at station start, from every `TransmitProfile` and at
every `StationBand`; the profile keeps it in the station config. While the band is unknown
or has no entry, the level before stays (0 dB at station start), with `stored` false. A
level transmit finds is given as `LevelFound` for the band and counts only when it has
come back in a `TransmitProfile`. Manual: the operator's level, nothing found or
corrected. Automatic: found with the Tune tone and corrected in each transmission. A radio
that does not report its ALC works as manual.

| Value of `TransmitConfig` | Is | Until it is set |
|---|---|---|
| `levelMode` | manual or automatic | automatic |
| `levels` | the Tx level of each band, within the range | none: 0 dB |
| `powerLimitPct` | the profile power, 1 to 100 | absent: no limit |
| `tuneSeconds` | the Tune limit, 1 to 300 | 90 |

`TxLevelStatus`: `managed`, `mode`, `level_db`, `stored`, `alc` (unknown, available,
unavailable), `assistant` (the level is found), `result` of the last finding, `meters`
(`alc` in percent of the radio's ALC zone, `po_pct`, `swr_x10`), `power_limit_pct`,
`warnings`.

## 5. Behaviour

**Default: an event that no row below names changes nothing.**

### The transmit state (`TransmitArming`, `Stops`)

| Event | Result |
|---|---|
| station start | disarmed, cause startup, no cause of switching on; nothing of an earlier run is taken up |
| an admitted `Arm` | armed; `last_arm_cause` set; `refusal` cleared |
| `Disarm`, `Abort` | disarmed with the cause they name |
| `Halt` | disarmed, halt |
| a refused request that switches off | disarmed, refused |
| a failed transmission | disarmed with the cause of the failure |
| while on: the capability is not available | disarmed, deviceLost |

Disarm and the lost capability drop each request that is not keyed (refused, notArmed); a
keyed transmission goes on to its end. A Disarm leaves the switch and `halt_state` as they
are.

The shown cause is that of the stop standing first in this order, among the stops since
the later of the last `StepBegins` and the last admitted Arm: halt; deviceLost;
failed; refused; contactCancelled given by Abort; txWatchdog;
partnerWorksOther; bandChanged; modeChanged; contactCancelled given by Disarm;
contactCompleted.

### A transmission, step by step (`Transmission`)

| Step | When | What transmit does | If it goes wrong |
|---|---|---|---|
| 1 | before the period start | nothing | - |
| 2 | from the period start, not keyed | examines the request again: the station's mode and the start plan | refused with staleRequest or the plan's refusal; disarmed, refused |
| 3 | then | opens the output (`OpenOutput`) | failed, audioUnavailable; not keyed |
| 4 | the output open | keys the radio; keyed when radio control has confirmed | switch in use: refused, busy; not confirmed: failed (see failures) |
| 5 | from the audio delay after the period start | plans once more and plays the waveform from the planned sample at the scale of the Tx level; sets `last_text` and `last_period_utc_ms`; outcome started | plan fails: refused, radio released; program refused: failed |
| 6 | audio reports finished | stops the output and releases the radio; outcome completed; the state stays on; the next request becomes the current one | release not confirmed: failed, pttIndeterminate |
| 7 | the release deadline passes without that report | - | failed, audioStalled |

A report of the end that is seen only after the deadline still completes. A Disarm does
not move the deadline.

### Failures (`Failures`)

Every failure stops the output, releases the radio when it is keyed or its switch is not
released, gives the outcome failed, switches the state off and drops a next request.

| Failure | `TransmitFailure` | Cause of the stop |
|---|---|---|
| the output does not open | audioUnavailable | deviceLost |
| the key is not confirmed | pttTimeout, pttRejected, pttReadbackMismatch, pttIndeterminate; radioLost when radio control cannot be reached | failed for pttRejected and pttReadbackMismatch, deviceLost for the others |
| the program is refused | audioUnavailable or audioDeviceLost | deviceLost |
| the output fails while playing | audioDeviceLost | deviceLost |
| the release deadline passes | audioStalled | deviceLost |
| the release after the last sample is not confirmed | pttIndeterminate | deviceLost |
| keyed, and the capability is not available | radioLost | deviceLost |
| transmit itself fails | ownerFault, for the current and the next request | failed; Arm is refused from then on; Halt is still answered |

While `ptt` is indeterminate, no request waits, no tone is on and the capability is
available, transmit asks for the release again; it does not key.

### Halt, Abort and the end of the process (`HaltTransmit`, `SafetyReleases`)

| Event | What transmit does |
|---|---|
| `Halt` | taken at every moment; waits for no step of transmit, no decoding, no display. Stops the output at once, releases the radio when something is keyed or the switch is not released, ends the tone, gives the current and the next request the outcome halted, disarms with halt |
| `Halt` while the output opens or the key waits | that wait ends; the radio is not keyed |
| `Halt` while the key is exchanged | the release follows |
| `Halt` with a command id of one of the latest 16 | the receipt of the first; nothing else |
| `Abort` | as Halt, but: it waits for a step under way; the outcome is aborted; the cause is the one named; `halt_state` stays; a release that is not confirmed sets `refusal` to radioUnavailable |
| `ProcessEnds` | stops the output and releases as for a Halt; when the radio's switch may be on, one release is asked for and waited for at most 500 ms; no other part's work is waited for before it |
| radio control first reports, from a fresh reading, that the radio transmits, and transmit has not keyed since station start | one release: confirmed gives released, not confirmed failed. Once per run, whatever the profile says. In every other case notNeeded; a radio that transmits later is left alone |

The receipt: idle when nothing was keyed, stopped when the release was confirmed, pending
when it was not confirmed within 250 ms.

### The tone (`TuneTone`)

| Event | Result |
|---|---|
| an admitted `SetTune` on | opens the output, keys, plays the tone at the scale of the Tx level. Output not open or program not taken: refused busy; key not confirmed: refused radioUnavailable; each after a release |
| `SetTune` off | always admitted; the tone ends with a release |
| `Halt`, `Abort` | the tone ends with a release |
| it has lasted the Tune limit (`TransmitConfig::tuneSeconds`, 90 s until set; a changed limit holds for the next tone) | ends with a release |
| the output fails; the capability is not available | ends with a release; a state that is on goes off with deviceLost |

Neither the start nor the end of the tone changes the transmit state or its causes,
except in the last row.

### Finding the level with the Tune tone (`LevelFinding`)

In automatic, with a managed radio, a tone that is switched on starts at -30 dB. Every
400 ms transmit reads the meters and decides by the first that holds:

| Reading | Result |
|---|---|
| no ALC value | ends, no_alc |
| SWR 3.0 or more | ends, high_swr |
| ALC above 0, or output power above the profile power | the level one step below, not below -40, is found; stored |
| the level is 0 dB | 0 dB is found; max_without_alc |
| otherwise | one step up; the tone follows |

A reading that fails ends the finding with its failure, the end of the tone with aborted;
neither finds a level. A level found is given as `LevelFound` and the tone goes on at it;
if it does not come back as saved, storage_unavailable and the level before. After a
finding without a level the tone goes on at the level before. A level found ends
`swr_fault` and the ceiling. The finding changes neither the transmit state nor its
causes, and sends the radio no setting.

### Supervision in normal operation (`LevelMonitor`)

One reading per transmission, when half of the audio left at the audio start has played;
none when less than 2000 ms was left, for a tone, or during a finding. The transmission
does not wait for it; a failed reading changes nothing. The level moves only in automatic;
the warnings and the SWR fault hold in both modes.

| Reading (automatic) | Level |
|---|---|
| ALC above 8 %, or output power above the profile power | one down, not below -40 |
| ALC 0, output power below 80 % of the profile power, and the level above is below the ceiling | one up, not above 0 |
| otherwise; and always without a profile power for the step up | unchanged |

A level lowered directly after the reading that raised it is the ceiling; it ends with a
level found with the Tune tone, another profile power and a station start. The changed
level is stored for the band and used from the next transmission on.

| Warning | Condition, in three readings in a row; gone with the first reading without it |
|---|---|
| alc_high | ALC 50 % or more |
| po_low | output power below 50 % of the profile power |
| swr_high | SWR 2.0 or more |

An SWR of 3.0 or more: transmit halts as for a Halt (cause halt), no more holds the
operator as seen, and shows swr_fault until a reading with a lower SWR or a level found
with the Tune tone; a reading without an SWR value leaves it.

## 6. Implemented in and tested by

Modules: `server/src/transmit/service.rs`, `server/src/transmit/schedule.rs`,
`server/src/transmit_http.rs`, `server/src/radio_level.rs`. Detail tests:
`server/src/radio_level_tests.rs` (the bound of one meter reading and its test seam).

## 7. What it relies on from outside

| Element | Needed from it |
|---|---|
| `WstxOperatingChain::TransmitRequest` | the request: sequence, mode, period start, text, Tx offset |
| `WstxModeProcessing::EncodeRequest`, `Waveform`, `EncodeRefusal`, `AcceptedMessage`, `Period` | the waveform of a message; the period and frame lengths |
| `WstxAudioStreams::OpenOutput`, `PlayProgram`, `SetScale`, `StopOutput`, `OutputStatus`, `PlayRefused` | the output and its state |
| `WstxStationTime::StationTime` | station time and whether it is synchronized |

Named in text with no element behind the name in the files read: the key, the release,
their confirmation and failure, the readiness of the radio, the report that it transmits,
and the meters (the port `control`); the contact's own answers
(`transmit_unavailable`, `tx_watchdog`) in TC-111-010.

## 8. Differences from a named reference

Reference: WSJT-X at the behaviour baseline.

| Topic | Reference | This product | Recorded as |
|---|---|---|---|
| Start late in a period | up to 75 % of the period, also when no audio of the frame is left (FT4 between 5340 and 5625 ms) | the window closes when the frame's audio would have ended | deliberate |
| Tx watchdog | limits the time of repeated transmissions in minutes | limits the repetitions of one message | deliberate |
| Tx level | the Pwr slider, 0 to -45 dB in 0.1 dB; per band only when "Remember power settings by band" is set, with a separate Tune value | manual: a slider, -40 to 0 in whole dB, always per band, the same for Tune; automatic (the default): found with Tune and corrected from the ALC | deliberate (operator 2026-11-15) |

## 9. Verification

| Case | Verifies | Shows | Declared |
|---|---|---|---|
| TC-006-001 | CL-009-02 | the next period of a parity and the start plan of FT8, with its three refusals | cost 2, development PC, implemented; 2 tests of `transmit_vectors.rs` |
| TC-006-002 | CL-009-02 | the same for FT4, and a period that fits one mode only | cost 2, development PC, implemented; 2 tests of `transmit_ft4_vectors.rs` |
| TC-008-003 | CL-111-01, CL-009-03 | off at start; the refusals of Arm; key before audio; late start; the refusals of a request; replacement and the next request; the station's mode; a restart; a station profile; late end reports | cost 2, development PC, implemented; 10 tests |
| TC-008-005 | CL-009-04 | Halt in every phase and its 250 ms; each failure with its cause; the release deadline; a fault of transmit; the release at station start; Abort | cost 2, development PC, implemented; 15 tests |
| TC-111-013 | CL-111-03 | the shown cause of two stops in one step; a txWatchdog stop keys and halts nothing | cost 2, development PC, implemented; 3 tests |
| TC-111-010 | CL-111-06 | the tone with the state off, busy, its limit | cost 2, development PC, implemented; 2 tests |
| TC-044-013 | CL-044-12 | when the level reaches the output; the scale | cost 2, development PC, implemented; 1 test |
| TC-044-014 | CL-044-12 | a finding, the level of the configuration, a level that is not saved, the meters during a tone | cost 2, development PC, implemented; 8 tests |
| TC-044-017 | CL-044-14 | the one reading, the step, the ceiling, the warnings, the SWR fault | cost 2, development PC, implemented; 15 tests |

Every clause has a case. Lines marked "Planned, no test yet": TC-008-003 (l) the 33rd
outcome, and `on_air` with `last_period_utc_ms`; TC-008-005 (q) the release at the end of
the process and the 17th Halt receipt; TC-044-014 (h) the tone after a finding, the
transmit state unchanged, the limit of the tone, manual, the level of each band;
TC-044-017 (m) the reading in manual.

## 10. Open points, gaps and disagreements

Marked by the model:

- `TransmitService::control` (NotStated): the port type of the connection to radio
  control, which is defined with radio control; transmit keys and releases the radio over
  it, learns whether the radio is ready and whether it transmits, and asks for the meters.
- `TxLevelStatus::result` (NotStated): the result of a run whose meter reading fails in
  another way than by a missing radio; the code shows the name of the failure as radio
  control gives it, which is no `LevelResult`.

Gaps:

- Who sends `Halt` is the station service by the port; who may send it is not
  transmit's.

Disagreements and observations:

- None left after the changes of 2026-11-15.
