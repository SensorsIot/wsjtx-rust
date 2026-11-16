# The station clock

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: `backend/clock/Clock.sysml`,
`backend/clock/StationClock.sysml`, `interfaces/internal/StationTime.sysml`,
`interfaces/external/TimeSource.sysml`, and of `Station.sysml`, `Context.sysml` and
`interfaces/internal/Decodes.sysml` only the lines that attach the clock. Not read: the
code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Station time | the PC clock plus the clock's correction | `StationTime`, `TimeBase` |
| Correction | what the clock adds to the PC clock, in milliseconds | `Correction`, `ClockQuality::correctionMs` |
| Observation | a published decode that names a sending call other than the profile's own | `AirClock` |
| Vote | one per station: the median of its DT plus the current correction | `AirClock` |
| Estimate | the median of all votes | `AirClock`, `AirEstimate` |
| Evidence | an estimate with enough votes, enough of them on one side | `AirClock` |
| Reading | the latest valid answer of a time server | `TimeServerReading` |
| Step | a jump of the PC clock beyond 100 ms | `Correction::maxStepMs` |

"State" has two meanings, each with its own type: the state of station time
(`StationTimeState`: synchronized, unsynchronized) and the state of the PC clock against the
time server (`ClockState`: synchronized, unsynchronized, unknown).

## 2. Place in the system

From `Clock.sysml`, `Station.sysml`, `Context.sysml`.

**Position:** station context, station, backend, station process, `clock`.

**Neighbours**

| Neighbour | Connection | Direction | Item |
|---|---|---|---|
| receive | `timeReceive` | clock to receive | `StationTime` |
| transmit | `timeTransmit` | clock to transmit | `StationTime` |
| qso | `timeQso` | clock to qso | `StationTime` |
| station service | `clockStatus` | clock to station | `ClockQuality` |
| receive | `decodesClock` | receive to clock | `ResultRecord` |
| time server (outside) | `timeSourceLink` | both | `TimeRequest`, `TimeReply` |

**Not connected:** the clock has no connection to the radio, to audio, to the browser link,
to the log or to the profile. It cannot key, cannot read or write a setting, and cannot
reach an operator.

**Limit:** the item on `decodesClock` does not carry everything the clock uses; see section 10.

## 3. Purpose and requirements

The clock holds station time, corrects it from the stations heard, checks the PC clock
against a time server and warns the operator.

| Identity | Requirement | Status the model declares |
|---|---|---|
| CL-043-01 | The clock MUST hold station time as the PC clock plus its own correction. | implemented |
| CL-043-02 | The clock MUST estimate how far station time is off from the stations it decodes. | implemented |
| CL-043-03 | The clock MUST move its correction toward the middle of the stations heard when their estimate is evidence, and keep it otherwise. | implemented |
| CL-009-05 | The clock MUST measure the PC clock against a time server and warn the operator when the PC clock is off, when no server answers, or when the correction is large although the PC clock is right. | implemented |

All four derive from FR-006.

## 4. Data and rules

**Station time** (`TimeBase`, `StationTime`). Station time is the PC clock plus the
correction, for every function alike. The correction is 0 at station start.

**The estimate** (`AirClock`)

| Value | Is | Rule |
|---|---|---|
| minimum SNR | -20 dB | a decode is an observation from this SNR upward |
| largest DT | 3000 ms | a decode is an observation up to this DT, either way, against the uncorrected PC clock |
| window | 120 s | the estimate uses the observations of this time |
| side margin | 100 ms | a vote counts as later or earlier beyond it |
| fewest stations | 4 | the estimate is evidence from this many votes |
| same side | 80 % | the estimate is evidence when this share lies on one side |
| largest age | 60 s | an estimate counts up to this age |

For an even count, the median is the floor of the mean of the middle pair.

**The check against a time server** (`TimeServerCheck`), following RFC 4330

| Value | Is | Rule |
|---|---|---|
| servers | ch.pool.ntp.org, time.windows.com, pool.ntp.org | asked in this order until one answers validly; `WSTX_SNTP_SERVERS` gives another list, and an empty value means none is asked |
| largest offset | 500 ms | synchronized up to it, unsynchronized beyond |
| largest age | 600 s | a reading counts up to this age; without one the state is unknown |

The result is used for the warnings only. A measurement is taken at station start and then
repeatedly. A round without a valid answer keeps the previous reading. After a step the
state is unknown until the next reading. The latest result is available at once, also while
a measurement runs.

**What the clock gives** (`StationTime`, `ClockQuality`)

| To | Field | Type | Absent means |
|---|---|---|---|
| receive, transmit, qso | UTC in milliseconds | Integer | – |
| | time state | `StationTimeState` | – |
| station service | time state | `StationTimeState` | – |
| | correction | milliseconds | – |
| | warning | `ClockWarning` | none holds |
| | time server state | `ClockState` | – |
| | time server reading: server, offset, round trip, age | `TimeServerReading` | no valid answer yet |
| | Windows time service: running, stopped, disabled, unknown | `WindowsTimeState` | – |
| | estimate: median, stations, later, earlier, age | `AirEstimate` | no estimate yet |

## 5. Behaviour

**The correction** (`Correction`). Every completed decode window gives a new estimate.

| Situation | What the correction does |
|---|---|
| the estimate is evidence | moves toward the correction minus the estimate's median, by at most 1000 ms within one period of the current mode |
| mixed sides, too few votes, or no estimate | stays as it is |
| a step of the PC clock | the observations and the estimate are discarded; the step is subtracted from a nonzero correction; a correction of 0 stays 0 |
| the correction is beyond 3000 ms after a step | restarts at 0 |

**The state of station time.** Unsynchronized while a counting estimate is evidence and its
median is beyond 1000 ms. **Synchronized in every other case.**

**The warning** (`WarningRule`). The first whose condition is met:

| Order | Warning | Condition |
|---|---|---|
| 1 | PC clock off | the time server state is unsynchronized |
| 2 | NTP unreachable | a round since start has asked a server and no reading counts |
| 3 | stations off | the time server state is synchronized and the correction is beyond 500 ms |

**None in every other case.**

## 6. Implemented in and tested by

The part names its modules: `server/src/transmit/air.rs`, `server/src/transmit/clock.rs`,
`server/src/transmit/windows_time.rs`. The model names no set of detail tests for the clock.

## 7. What it relies on from outside

| Element | Needed from it |
|---|---|
| `WstxDecodes::ResultRecord` | the sending call and the SNR of a decode |
| not stated | the DT of a decode, the end of a decode window |
| `WstxRequirements::'FR-006'` | the requirement the four clauses derive from |
| the mode | the length of "one period of the current mode" |

Named in text with no element behind the name: "the profile's own call", "a completed decode
window".

## 8. Differences from a named reference

None recorded. The time server exchange follows RFC 4330, SNTP version 4.

## 9. Verification

| Case | Verifies | Shows | Declared |
|---|---|---|---|
| TC-043-001 | CL-043-02 | what counts as an observation, one vote per station, the median, when an estimate is evidence | level 2, development PC, implemented, `server/tests/transmit_air_clock.rs` |
| TC-092-001 | CL-043-01, CL-043-03 | the correction and the state of station time at each border | the same |
| TC-043-002 | CL-043-03 | the correction settles within two periods and does not swing | the same |
| TC-092-002 | CL-043-03, CL-009-05 | a PC clock that is off does not stop a transmit start | the same |
| TC-006-003 | CL-009-05 | the measurement: replies, server order, a step during the exchange, the borders of the state | level 2, development PC, implemented, `server/tests/transmit/transmit_clock.rs` |
| TC-092-003 | CL-043-03, CL-009-05 | the three warnings at their borders; station time under every state of the time server | level 2, development PC, implemented, `server/tests/transmit_air_clock.rs` |

Every requirement of section 3 has a case. No case states that it ran.

## 10. Open points, gaps and disagreements

**Marked by the model**

- `NotStated` on the clock's `decodes` port: which item gives the clock the DT of a decode,
  the end of a decode window and the period of the current mode. `ResultRecord` carries the
  sending call and the SNR, and none of these three. Sections 4 and 5 use all three.

**Gaps**

- **Audio.** By decision, audio reads station time from the clock. `Station.sysml` has no
  such connection yet.

**Disagreements and observations**

- `Correction::maxStepMs` is used by both the correction and the time server check; it is
  defined in `Correction` and the check refers to it.
- `Station.sysml` connects `clock.time` to ports `time` of receive, transmit and qso. Those
  parts are not built in this tree yet.
- The clock names no set of detail tests.
