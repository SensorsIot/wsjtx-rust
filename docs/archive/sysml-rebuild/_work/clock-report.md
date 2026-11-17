# Report: the clock part

2026-11-15. First part built by the method. Not finished: see "Not done".

## What was written

| File | Content |
|---|---|
| `backend/clock/Clock.sysml` | the part, its four ports, its modules |
| `backend/clock/StationClock.sysml` | 4 clauses, 5 rule elements, 6 test cases |
| `interfaces/internal/StationTime.sysml` | replaces `PeriodTiming.sysml`: station time, clock state, warning, quality |
| `interfaces/external/TimeSource.sysml` | request and reply, following RFC 4330 |

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-043-01 | transmit | StationClock | Keeps its core: station time is the PC clock plus the correction, with no source choice. Its wire and its Settings view are handed over and **need two new identities**, one for the station link and one for the frontend. |
| CL-043-02 | clock | StationClock | The estimate. |
| CL-043-03 | transmit | StationClock | Keeps its core: the correction and the state. Warnings moved to CL-009-05; capture warnings, texts and the transmit refusal are handed over. |
| CL-009-05 | transmit | StationClock | Keeps its core: the measurement against a time server, with the warnings. The transmit refusal is handed over (CL-009-02 states it). |
| TC-043-001, TC-043-002, TC-092-001, TC-092-002, TC-006-003, TC-092-003 | clock, transmit | StationClock | Rewritten: setup, then one lettered condition per line with one set of values. |

All four clauses derive from FR-006 only.

## Dropped as code or as history

- The reply validation rules and the offset formula of the time server exchange: the model names RFC 4330 and keeps one condition per rule in TC-006-003.
- That the measurement runs on its own thread: kept as what is observable ("reading never waits").
- The explanations: why the correction does not oscillate, which PC clock errors can be found, why 1000 ppm.
- All quotations, dates and issue numbers.
- Further value sets of the test cases beyond one per condition; they stay in the test files.

## Renamed

| Old | New | Cited by |
|---|---|---|
| package `WstxTransmitClock` | `WstxStationClock` | 8 code comments: `air.rs`, `clock.rs`, `main.rs`, `service.rs`, `transmit_http.rs`, `modes/transmit/mod.rs`, `tests/support.cjs`, `transmit_air_clock.rs` |
| element `TransmitClock` | `TimeServerCheck` | the same |
| package `WstxClockPart` | `WstxClock` | `Station.sysml` |
| package and file `PeriodTiming` | `StationTime` | `Station.sysml`, the parts receive, transmit, qso |
| port `timing` of the clock | `time` | `Station.sysml` |
| item `PeriodBoundaries` | `StationTime` | none |

## Checks

- `_work/check.py` on the four files: 0 findings.
- The pinned validator on the four files with their imports: no error in them. (The run reports errors in the old `Requirements.sysml`, which names every old package, and one in the taken-over `Decodes.sysml`.)
- Size: the four files have 18,500 characters. The old text they replace has about 35,000 (the old clock file 17,000, three clauses in transmit 12,000, two test cases there 6,000), of which about a quarter is handed over.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Which of the clock's 17 values stand in the model | The model/code line: would anyone outside the part notice another value? | 15 stay: the operator sees them, or a test case checks their border. Two are tuning and are dropped: the 60 s interval and the 1.5 s server timeout. Their rules stay as sentences. |
| The values also stand as constants in the code | Authoring rule 11: a contract test reads a value the model holds from the model. | Nothing changes in the model. Work for the code, listed below. |
| CL-043-03 and CL-009-05 are cut differently than before | One promise per clause; a split only where it buys something. | The correction and the state are CL-043-03; the measurement and the warnings are CL-009-05. |
| `Station.sysml` names the clock's old packages and ports | Renamed elements are followed by what cites them. | Updated in the new tree: three imports, three connections. The ports `time` of receive, transmit and qso follow when those parts are built. |

## Work for the code, when the new tree goes to main

- The clock's tests read their limits from the model, not from constants or literals.
- Eight code comments name `WstxTransmitClock` and `TransmitClock`.
- The clock's code moves from `server/src/transmit/` to `server/src/clock/`, and the type `ClockState` with it (it is defined in transmit's `schedule.rs`).

## Negative statements

Decided by the operator: no function exists that sets the PC clock, so nothing is written about it. Applied to every negative of the old clock text:

| Old statement | Result |
|---|---|
| The clock never sets the PC clock and never starts or configures a time service | dropped: no such function exists |
| The operator does not choose a time source; there is no source setting | dropped: no such setting exists |
| Station time is never unknown | made impossible by a type: `StationTimeState` has two values; `ClockState`, with unknown, is the time server's |
| The time server offset is never applied | positive: "its result is used for the warnings only"; shown by TC-092-003 |
| Reading never waits for a measurement | positive: "the latest result is available at once, also while a measurement runs"; shown by TC-006-003 (h) |

## The values, read again by kind

After the modes part, each value is sorted as a value of a source, of a test or of the
promise. All 15 of the clock are the product's own rules and stay: none is copied from
RFC 4330, and none is a sample size or a fact about a test file (those stand in the test
cases). Two names follow `shared/Units` now: `windowSeconds`, `maxAgeSeconds`.

| Values | Count | Noticed outside as |
|---|---|---|
| `TimeBase::startCorrectionMs` | 1 | the correction shown at station start |
| `AirClock`: `minSnrDb`, `maxDtMs`, `windowSeconds` | 3 | which decodes count; they set the number of stations the operator sees. The weakest of the 15 |
| `AirClock`: `sideMarginMs`, `minStations`, `sameSidePct`, `maxAgeSeconds` | 4 | the later and earlier counts shown, and when the correction moves |
| `Correction`: four limits | 4 | station time itself, and the state that refuses a transmission |
| `TimeServerCheck`: `maxOffsetMs`, `maxAgeSeconds` | 2 | when the operator is warned |
| `WarningRule::stationsOffMs` | 1 | when the operator is warned |

## Settled from the code

- **Status.** The old model marks the four clauses `partial`. The code has all of it and six bound tests; the clauses are `implemented`.
- **TC-043-002** was `partial` in the old model because of its capture clock steps, which are audio's now. Its clock part is tested (`applied_correction_converges_without_oscillation`) and written.

## Not carried over

Four planned test cases have no test in the code and are not written: TC-043-004 (live clock from the air), TC-092-006 (live clock state after the deploy), TC-092-007 (live PC clock offset), TC-092-008 (live call on a sparse band). They are live cases on the station.

## The functional description

Written from the new files alone: `_descriptions/clock.md`. It found five gaps. Three were
settled from the code, one is a marker, one is on the handover list.

| Gap | Settled how |
|---|---|
| Whether a decode carries the call, the SNR and the DT | From the code and the interface: `ResultRecord` has the call and the SNR, and no DT. The code hands the clock a DT and a period computed by receive. **Marker `@NotStated`** on the clock's `decodes` port; handed over to receive. |
| How the clock learns "one period of the current mode" | The same marker: the code passes the period with the end of a decode window. |
| When the quality is given | From the code: it is read at one instant. One sentence added to `ClockQuality`. |
| Audio's connection to the clock | On audio's handover list. |
| The clock names no detail tests | None exist; all of the clock's tests are bound to a case. An observation, not a gap. |

## The done-test (`part_done.py clock`)

All five tests pass: 10 identities accounted for, no finding of the script, no validator
error, 21 values and names matched with the code, 6 test cases with their test.

What the comparison with the code found on its first run:

| Finding | Result |
|---|---|
| The model named the warning `timeServerUnreachable`; the code says `NtpUnreachable`, on the wire `ntp_unreachable`. | The model follows the code: `ntpUnreachable`. A rename of mine, taken back. |
| The clock's state type `ClockState` is defined in `server/src/transmit/schedule.rs`, a module of transmit. | A difference in the code, not in the model. Work for the code: the type moves with the clock. |
| Two constants of the code are not in the model: the 60 s interval and the 1.5 s server timeout. | Inside: the two tuning values dropped earlier. |
| Six reasons for refusing a time server reply are not in the model. | Inside: the model follows RFC 4330, and TC-006-003 (b) shows the refusals. |
| The model's start value 0 of the correction has no constant in the code. | Matched by reading: the code starts at 0 without naming it. |

## Not done

- The clock's code comments are not changed; nothing outside `docs/sysmlV2` was touched.
