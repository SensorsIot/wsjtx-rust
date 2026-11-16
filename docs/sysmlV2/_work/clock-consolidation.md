# Consolidation of the time functions

2026-11-15. Every function about clocks and time in the old model (`docs/sysml`), where it
is modelled today and where it belongs. Found by a search of the whole model
(`_work/find_time.py`).

| # | Function | Modelled today in | Belongs to | Verdict |
|---|---|---|---|---|
| 1 | Holds station time: the PC clock plus a correction | `clock/StationClock`; CL-043-01, CL-043-03 in `transmit/TransmitState` | clock | pull together |
| 2 | Corrects it from the stations heard | `clock/StationClock` (AirClock, CL-043-02); CL-043-03 | clock | pull together |
| 3 | Checks the PC clock against a time server; reads the Windows time service | `clock/StationClock` (TransmitClock); CL-009-05 in `transmit/TransmitState` | clock | pull together |
| 4 | Clock state and the warnings `pc_clock_off`, `ntp_unreachable`, `stations_off` | CL-043-03 in `transmit/TransmitState` | clock | wrong part |
| 5 | Publishes time | `interfaces/internal/PeriodTiming` (to receive, transmit, qso), `ClockStatus` (to station) | clock | right place; the items are empty |
| 6 | Admits a transmission only when the clock is synchronized | CL-009-05, CL-009-02 | transmit | right |
| 7 | Plans the start of a transmission inside a period | `transmit/Schedule` | transmit | right |
| 8 | The period: 15 s for FT8, 7.5 s for FT4, even and odd, starting at UTC multiples | `transmit/Schedule` (Ft8Schedule), `receive/LiveReceive` (RelativeDecodeTiming), `PeriodTiming` (PeriodParity) | modes | stated three times |
| 9 | The capture clock: ties the sound card's sample count to UTC, tracks drift, re-anchors; warnings `uncorrelated`, `drift_high` | `receive/LiveReceive` (CL-007-05, LiveWindowSchedule); the warnings in CL-043-03 | audio | wrong part |
| 10 | The receive windows and the decode deadline per period | `receive/LiveReceive` | receive | right |
| 11 | The DT of a decode | `receive/LiveReceive` | receive | right; depends on 8 |
| 12 | `station.tick`: UTC and period to the browser | `operating/qso/QsoWire` (StationTickEvent) | the station link | wrong part |
| 13 | `GET /clock` and the `clock.state` event | CL-043-01 in `transmit/TransmitState` | the station link | wrong part |
| 14 | UTC in the top bar, period progress, the clock view in Settings, the status line, the error field entries | `frontend`; CL-043-01, CL-043-03 | frontend | pull together |

## Decided

- **The mode owns its period length and its nominal start. The clock owns the time**
  (operator 2026-11-15). The clock publishes station time and nothing about periods. A
  function that needs a period boundary derives it from the time and the mode's length.
  Consequences: the interface `PeriodTiming` carries time, not boundaries, and its name and
  the item `PeriodBoundaries` no longer fit; `PeriodParity` and the period lengths belong to
  modes; transmit and receive read them there.

- **The capture clock (9) is audio's** (operator 2026-11-15). The sample count is audio's own
  thing. Audio reads station time from the clock and stamps its stream: sample N was at
  time T; it tracks the drift and re-anchors. Receive gets a stream that carries its time.
  Consequences: audio needs a connection to the clock, which does not exist today; the
  warnings `uncorrelated` and `drift_high` are audio's; row 9 and the capture part of
  CL-007-05 and CL-043-03 go onto audio's handover list.

- **The clock's interfaces are renamed and filled** (operator 2026-11-15): the file
  `interfaces/internal/PeriodTiming.sysml` becomes `StationTime.sysml`, with the interface
  `StationTime` (time and state, to the functions that keep time, audio among them) and
  the interface `ClockStatus` (state, correction, warning and the two measurements, to the
  station service).

## Open

- **Who else needs time:** log, spots, udp and auto carry times in what they send or
  record; whether they get it in the items they receive or need the clock is not checked.
