# Use cases: plan (2026-11-17)

Operator decisions:
- Use cases are end-to-end processes, trigger to an outcome that can be checked; watching,
  alerts, log sync and spots are steps inside them; functions alone (look back, reference
  data) are no use case.
- 3 is "Set the output power without splatter": output power set on the radio per band,
  audio drive kept below the ALC (option A, written into the model: CL-044-18).
- 6 "Answer a direct call" added.
- 16 "Settings check" added (option B): one walk through every settings area, each value
  checked against the radio, the audio, the clock and the destinations, ending ready to
  operate or with each failure and its reason; the one way of checking all functions.
- A function the rig lacks is greyed out, its hover says why (RadioAbility, written).
- After the list is written: a coverage check: every clause and every setting of
  settings.csv in at least one use case; what no use case needs is a missing use case or
  a function with no job.

List (16): 1 Set up the first station; 2 Add a station to the shack; 3 Set the output
power without splatter; 4 Answer a CQ; 5 Call CQ and work a caller; 6 Answer a direct
call; 7 Move to another band or mode; 8 Hunt with a strategy; 9 Operate a contest;
10 Operate a special activity; 11 An agent operates the shack; 12 Restart the station;
13 Lose and regain the radio; 14 Clock out of step; 15 Operate from another screen;
16 Settings check.

Status: list agreed; UseCases.sysml written (16 use case defs, each step subsets its
clauses; validated); the settings check built as a target (supervisor SettingsCheck.sysml,
CL-001-01; frontend CheckView, CL-001-02; StationCommands CheckSettings, SettingsCheckReport);
M2.1, M3.1, M4.9 and M7.1 updated; settings.csv brought up to date (8 new rows, the audio
drive renamed).

Coverage (2026-11-17): 231 of 239 clauses in a use case. Not in any:
- CL-010-18 ADIF update and export of the logbook;
- CL-040-03 UDP inbound (Heartbeat), CL-040-06 IPv6 multicast targets;
- CL-055-06 fetching the newest country file;
- CL-006-01, CL-006-05, CL-006-06 the recording import and replay; CL-052-01 the window dump.
Settings: every setting is checked by the settings check or taken only within its rule;
the check gained PTT over CAT, the AGC, the contest period and the Most Wanted list.
Decided: group A (ADIF update and export, the UDP connection, the country file fetch) are
steps of SetUpFirstStation (operator: A). Debugging functions need no use case (operator):
the recording import and replay and the window dump carry @Debugging (ModelNotes), and the
new rule M6.11 (checked by check.py) asks every other clause to be carried by a use case
step. Coverage: 235 of 239 carried, 4 debugging, M6.11 has no finding.
