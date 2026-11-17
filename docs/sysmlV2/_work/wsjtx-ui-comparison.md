# The frontend against the WSJT-X UI (2026-11-17)

Compared: WSJT-X 3.3.0-beta6 (local tree `D:\Github\wsjtx`, tag v3.3.0-beta6; the behaviour
baseline is beta4): `widgets/mainwindow.ui` (198 controls, 149 actions, 15 menus),
`widgets/widegraph.ui`, `Configuration.ui` (tabs General, Radio, Audio, Tx Macros,
Reporting, Frequencies, Colors, Advanced, Alerts, Filters), against the built model.

## Outside the product's scope (FT8 and FT4 only)

JT4, JT9, JT65, MSK144, Q65, FST4, FST4W, WSPR, ISCAT, Echo, the astronomical data, frequency
calibration and equalization, Fox and SuperFox, OTP, the Q65 pileup, band hopping, TCI audio,
the VHF and microwave features, message averaging.

## Covered

Band buttons and mode; Monitor and the resume at start; Enable Tx as the starts; Halt Tx; Tune
with its watchdog; DX Call and Grid with Generate; Tx1 to Tx6 with Next and free text; Auto
Seq; Call 1st; Tx even/1st; Hold Tx; Rx and Tx offsets with Tx=Rx and Rx=Tx; the report; the
Tx watchdog; Log QSO (as resend; logging automatic); the ignore list; Best S+P (Auto and the
strategies); the Wide Graph's Zero, Gain and Flatten, the spectrum line, the Rx and Tx
markers; the highlight slots with on and off; the special activities NA VHF, EU VHF, Field
Day, RTTY Roundup, WW Digi, ARRL Digi, Hound; PSK Reporter; the UDP interface; the country
file download; several configurations (the stations); the keyboard shortcuts and mouse
commands in the help; the copyright notice and About (the help, CL-017-01); remembered
power per band (the Tx level).

## Missing (FT8 and FT4)

Operator 2026-11-17: "leave out" accepted (2, 5, 10, 13, 15, 17, 19, 21); the "add" items
and the open ones are asked one at a time.

| # | WSJT-X | The station today | Recommendation |
|---|---|---|---|
| 1 | Decode: decode the last period again | none | **decided 2026-11-17: neither manual nor automatic** (the contact's context is set before the partner's reply; no evidence of a miss); the code's unused `Redecode` goes |
| 2 | Erase: clear Band Activity | none (only the latest two periods show) | leave out: the view clears itself |
| 3 | Tx Macros: stored free texts for Tx5 | none | **decided 2026-11-17: add**, a shack-level list (one entry at a time), default "TNX 73 GL"; Tx5's field offers it |
| 4 | CW ID after 73 | none | **decided 2026-11-17: leave out** (every message carries the call) |
| 5 | Calling CQ forces Call 1st; the respond choice | Call 1st only | leave out |
| 6 | Split operation (Rig, Fake It) | none chosen | **decided 2026-11-17: add**, a station setting None (default), Rig, Fake It; radio control sets the second VFO or moves the dial around each transmission, transmit shifts the tone |
| 7 | Band Activity filters (hide worked before, by continent, by keyword) | only the strategy's and the contest's | **decided 2026-11-17: through the strategy and the contest**: with a strategy active Band Activity shows only what it ranks, messages to the station's call and the partner's rows; filtered means not shown; Show all (off by default) for every strategy; no separate filters |
| 8 | Azimuth, miles, US state, principal prefix shown | distance in km only | **decided 2026-11-17: add the azimuth** (with a grid in the message) **and miles**, km or miles a choice of each browser; US state and principal prefix left out |
| 9 | Waterfall: palette choice, averaging, time stamps, start frequency and zoom, cumulative spectrum, reference spectrum | fixed span 0 to 3000 Hz, one palette | **decided 2026-11-17: a thin line across the waterfall at each period start on live receive, no time written**; the ruler of seconds stays; the rest left out |
| 10 | Highlight colours editable | on and off only | leave out |
| 11 | Audio alerts per event (my call, CQ, DX call, new DXCC, ...) | alerts of the strategy only | **decided 2026-11-17**: each strategy has a tenth decision Alert, Off (default) or a sound, sounding when it newly ranks a station (a contest: a new multiplier); a message to the station's call from another station than the partner rings, once per caller and contact, its sound a choice of each browser (default an old telephone's ring, can be off); one set of sounds (old phone, bell, chime, beep); Sound and notification stay per browser; no per-event checkboxes |
| 12 | ALL.TXT: a file of every decode | none | **decided 2026-11-17: add**, every decode and every transmitted message, WSJT-X's line format, one file per station and month |
| 13 | Save received audio (.wav) | the decode windows for diagnosis only | leave out |
| 14 | Cabrillo export, contest log window | the contest's count and score only | **decided 2026-11-17: add the export** (Settings > Files, a contest and its period, Cabrillo 3.0 from the logbook, the header kept in the shack's settings); no second contest log |
| 15 | Uploads to Cloudlog, Wavelog, eQSL; LoTW user list | the UDP interface to logging programs | leave out: programs on UDP do it |
| 16 | Log QSO dialog (name, comment, power before logging) | automatic logging, no edit | **decided 2026-11-17: no dialog**; the logging program adds name and comment |
| 17 | Decode depth (Fast, Normal, Deep), AP on or off, threads, decoder start | fixed by the station | leave out |
| 18 | Working frequencies, editable | WSJT-X's default list by reference | **decided 2026-11-17: like WSJT-X**, an editable table at the shack level (one row at a time, Reset to WSJT-X's defaults); the band selector offers its frequencies for the mode |
| 19 | Rig mode (USB, Data), Tx audio source | by the radio's recommended settings | leave out |
| 20 | User Guide, release notes, sample download | none | **decided 2026-11-17**: the help links to WSJT-X's online User Guide and to the station's own guide once it exists; **every control shows a short hover help** (what it does, its key, why it is disabled); no release notes, no samples |
| 21 | AutoGrid (the locator from GPS) | none | leave out |

## Also decided while comparing (2026-11-17)

- **Log automatically** (shack setting, on by default) governs QSOs by hand only: off, a
  completed QSO by hand shows "Log <call>?" in the QSO pane, Log QSO writes it, Discard drops
  it; Auto always logs at completion; no waiting list; the logbook stays write-once; with
  nothing waiting Log QSO sends the newest record again.

## Writing the additions into the model (progress)

Order: 20 and 8 and 9 and 7 (frontend only); 3 (profile, qso, frontend); 16 (qso, log,
profile, frontend); 11 (operating, ranking, frontend); 18 (profile, supervisor, frontend);
6 (radio control, transmit, frontend); 12 and 14 (log, profile, frontend). New clauses are
targets; every part's five tests run after each item.

Done, all eleven: 20, 8, 9, 7 (frontend); 3 (QsoShared::macros, collection txMacros);
16 (CL-085-04, LogConfirmRule; ConfirmLog, DiscardLog); 11 (Strategy::alert, AlertSound,
CL-042-08 CallAlert); 18 (WorkingFrequencies, collection workingFrequencies,
ResetFrequencies, SelectBand::nominalHz); 6 (CL-008-13 SplitKeying, CL-009-07 SplitRule,
TransmitConfig::split); 12 (CL-010-20 HeardFile, the log's decodes port); 14 (CL-010-21
CabrilloExport, LogShared::cabrillo). New clauses are targets; verdicts in parts.json.

## Work for the code

1. Hover help on every control; the guide links in the help.
2. Azimuth and miles; the period lines in the waterfall; Band Activity filtered by the
   strategy, Show all for every strategy.
3. Tx macros; Log automatically with the confirmation by hand.
4. Each strategy's alert sound; the ring of a station calling.
5. Editable working frequencies with Reset; SelectBand with a frequency.
6. Split operation (Rig, Fake It).
7. ALL.TXT per station and month; the Cabrillo export.
8. The code's unused `Redecode` goes (item 1).
