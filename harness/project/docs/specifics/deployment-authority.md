**Layer:** HOW. **Scope:** this project's development environment and procedures.

## Deployment authority

This is the project's binding of the harness
[deployment authority](../../../general/core/docs/standards/security.md#deployment-authority)
rules.

**Mechanism.** There is one deploy mechanism: the Windows release executable built on
HB9BLA and installed there at user level by the reviewed, versioned deploy scripts under
`tools/deploy/`.
`tools/deploy/` is a product path: a change to it is a CR with review and the merge
queue's gate, and suite `deploy-tooling` tests it. The **mechanism paths** are every file
under `tools/deploy/station-update/` (`station-update.ps1`, `make_package.py`,
`launcher.ps1`) plus `tools/deploy/agent-client.ps1`, `tools/deploy/station-probe.ps1`,
`tools/deploy/live-page-check.ps1` and `tools/deploy/station-process.ps1` (the station's
process list, Ctrl+C helper and task settle, shared by the update, the page check and the
test bench). Every step of the
[standing deploy policy](#standing-deploy-policy) lives in those files. `.gitattributes`
marks them `-text`, so their bytes in git, in a checkout and in a package are the same.
The live page check's checker `tools/test/node/live-page-check.cjs` is a test tool, gated by
CRs, and is not pinned: the deploy runs it from the repository root it passes (`-Repo`, the main
checkout `D:\Github\wsjtx-rust`) with that checkout's `node_modules`, not from the package.

A deploy is one line in Git Bash on HB9BLA, given only the commit, which runs
`make_package.py` as extracted from the commit it installs, so no working folder is read:

```bash
set -o pipefail; git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> [--dry-run]
```

The commit is the one the merge queue pushed; Alex runs the same line (`alex.install` in
`harness/project/config.yaml`).

A push is one line `<old>..<new>  HEAD -> master` in a merge-queue log under
`.git\harness-parallel\queue\logs\`; its verdict is the log's last line beginning with
`harness gate`. A green push has the verdict `harness gate: <n> suites, green`, a harness
push one beginning with `harness gate: harness change`. The command accepts a commit C on
GitHub master when a green push has C as its new tip (that log is the push-gate log), or when
C's chain, walked back from the push of C through each push's old tip, is one or more harness
pushes followed by a green push whose new tip G is an ancestor of C, and every path of the
diff from G to C is a harness path of G: the harness checkout (the one submodule path that
`.gitmodules` at G names and that is a gitlink in G's tree), `harness/project` and the
`harness_paths` of `harness/project/config.yaml` at G. Such a package is C's build; its
gates.json adds `gated_commit` (G) and `harness_push_logs` (a copy of each harness push's
log, newest first), and G's log is its gate receipt.

It refuses (exit 1, before any step) any other argument list, a commit not on GitHub master,
a commit of the walk that no push has as its new tip (a commit inside a push, a commit
pushed by hand outside the merge queue, or a chain without a green push), a commit of the
walk that more than one log shows pushed, a push of the chain that is neither green nor a
harness push, a G that is not an ancestor of C, and a diff from G to C holding paths that are
no harness paths (the first 10 named). A log without a push line is ignored. It builds the package in
`.git\harness-parallel\resources\station-update\packages\<ver>\`, never in a working tree,
or reuses one there whose manifest names the commit (a folder holding anything else is
refused); it copies the mechanism files from the commit's `git archive` export into the
package's `deploy\` folder and lists their SHA-256 in the manifest. It then runs the
package's own copy,
`<package>\deploy\tools\deploy\station-update\station-update.ps1 -Manifest <package>\manifest.json [-DryRun]`,
which refuses to run from anywhere else, and exits with its exit. It verifies the package, checks the pins, waits for
an idle station, stops it gracefully, switches `active.json`, starts the task, switches
back on failure, runs the probe and the live page check from the package, returns to the
previous version when either fails and posts the install record (a stop it has to force:
[Standing deploy policy](#standing-deploy-policy) item 5). Exit 0: installed (or the
dry run passed); 1: refused, failed or returned, or a forced stop whose PTT release was not
confirmed; 3: the station stayed busy, nothing
changed; 6: the radio did not answer, nothing changed. A parameter the script does not
declare stops the call at binding, before any step.
`station-update.ps1 -Rollback` returns to the previous version and never asks. The
operator's one-time `setup-once.ps1` (in `.git\harness-parallel\resources\station-update\`,
not used by deploys) points the scheduled task at `station\launcher.ps1`, which runs the
version named in `active.json`; the task names no repository path and no deploy changes it.
The manual `windows-rust.yml` workflow and its `wstx-rust-windows-x64` artifact are build
evidence only: that artifact is never installed on the station.

### Standing deploy policy

The operator's policy, verbatim: "The operator is kept out of the loop, with one exception:
when a decision is needed." It binds the deploy part of the harness rule
[standing deploy and consent policies](../../../general/core/docs/CR-Process.md#standing-deploy-and-consent-policies). A deploy
under it needs no OK per install.

1. **When a deploy applies without asking.** All of these hold:
   - the push gate is green on exactly that commit, or the commit rests on its newest
     green-gated ancestor through harness pushes only and its diff from that ancestor holds
     only harness paths (make_package.py, F1 of #334), and the package matches it (the
     package checks of `station-update.ps1`);
   - the station is idle, checked inside `station\logs\update.lock`, which the deploy holds
     from the check until the station has stopped. Idle means all of: the update lock is
     free; no live radio lease (`.git\harness-parallel\radio\lease.json` missing or
     expired); exactly one station process; GET /transmit shows `arm_state` `disarmed`,
     `ptt` `released` and `transmitting` false; GET /contact shows no contact, or one that
     is `idle`, `completed` or `cancelled`; GET /automation shows no run, or a stopped one;
     GET /radio shows `state` `ready`, read in the same pass after the others. A state that
     cannot be read counts as busy. While busy, the deploy reads again every
     10 s for up to 300 s, then gives up with the station untouched (exit 3); the CR stays
     landed and the deploy is retried later. A radio that is not `ready` (or whose reply
     cannot be read) is the reason `waiting for the radio (state <state>)` and waits the
     same way; when it still does not answer after 300 s and the station is otherwise idle,
     the deploy prints `WAITING FOR THE RADIO: the radio did not answer for 300 s, nothing
     changed (state <state>)` and exits 6: it stages and stops nothing, runs no probe and
     no page check, makes no return and posts no record; the same command run again later
     repeats the whole check, and exit 6 is reported to the operator. `-DryRun`, `-Rollback` and the switch-back after a failed
     probe or page check do not read the radio. A station that is down is not idle. A contact
     the agents did not start is never aborted by them; a deploy it blocks past the wait is
     reported to the operator;
   - it is outside the scheduled-job window. The product has no scheduled job, so the
     window is none.
2. **The mechanism is pinned.** [Deploy pins](../Project-Specifics.md#deploy-pins) lists one line per mechanism
   file.
3. **The deploy runs the bytes of the commit it installs.** `make_package.py` runs as
   extracted with `git show`; `station-update.ps1`, the probe and the page check run from
   the package. The page check takes the repository root, the shared folder and the agent
   client as parameters and derives none of them from its own location. The page check and
   the update dot-source `station-process.ps1` from the package beside them. Before any write,
   `station-update.ps1` compares each mechanism file of the package with the pins of the
   commit's own `harness/project/docs/Project-Specifics.md` (read with `git show`), and
   compares the launcher in the station folder with its pin (item 4). A commit without that
   file, or whose file has no Deploy pins section, has no pins. This holds for the commit to
   install and for the running commit. The install record's `cr_state.py installed` runs
   `harness\general\core\tools\cr_state.py` of the repository.
4. **A changed mechanism deploys without an OK.** The deploy installs a commit whose
   mechanism files or pins differ from those of the running commit like any other commit:
   pins that differ from the running commit's pins, a running commit without pins and a
   station launcher that differs from its pin are no refusal; the deploy logs one step per
   difference (`deploy mechanism changed: <what>`) and goes on. It refuses before any write,
   with exit 1 and its reason, when the commit to install has no deploy pins, when its pins
   do not name the mechanism files in their order, or when a mechanism file of the package
   differs from its pin (`<path> differs from its pin`). When the station launcher differs
   from the package launcher, it saves the station launcher in the station folder's `logs\`
   and writes the package launcher after the stop, before starting the task; the
   switch-back restores the saved launcher with the profile. The task itself is never
   changed. `-Rollback` never asks and checks no pins, so the automatic return always works.
   `station-update.ps1` has no parameter for an operator's OK: a call that names one stops
   at parameter binding before any step.
5. **Proof and return.** After the switch the probe runs, inside the lock. The deploy then
   releases `update.lock`, and the live page check runs (it takes the lock itself for its
   restart). Probe not `PASS`, page check `RED` or `ERROR`: the previous version is
   reinstalled without asking, under the lock again, and each CR in the install goes back
   to step 2. Page check `BUSY` or `NOT-EXERCISED`: no return, and the result is recorded;
   before the live acceptance of the CRs of that install the page check runs again, and
   acceptance needs its `PASS`.
   **A forced stop.** Every stop (the switch, a switch-back, a return, `-Rollback`) sends
   Ctrl+C, then Ctrl+Break after 8 s, and logs whether each signal was delivered; a signal
   that was not names the helper's failed call and its Windows error
   (`AttachConsole error <n>` or `GenerateConsoleCtrlEvent error <n>`, or `error unknown`). A
   station still running 8 s later is force-stopped, after one line with the transmit state
   one GET /transmit reads just before it (`-Rollback` reads none). The next start that
   becomes ready reads GET /transmit every 2 s for at most 30 s until `startup_release` is no
   longer `pending`: PTT is confirmed when it is `not_needed` or `released`, `ptt` is
   `released` and `transmitting` false; anything else, and every forced stop under
   `-Rollback`, is not confirmed and logged with `check the radio`. A forced stop without that
   confirmation ends the update with exit 1 and starts no further stop: no switch-back and no
   return; a failed probe or page check then gives the record `not returned`, not a return,
   and the record goes to the issues a return's record would go to. The install record has
   one `Station stop:` line per stop (`graceful`, or `forced` with the Ctrl+C delivery and
   the PTT result after it).
6. **Install record.** Every install posts its record on each CR issue it moves to
   installed (`cr_state.py installed <commit> --since <previous>` finds them); after a
   return, on each issue the subjects of `<previous>..<commit>` name that is open and carries
   `cr:landed` or `cr:installed` (the deploy reads each with `gh issue view`; for any other
   issue it logs `record not posted on #<n>: <closed | at <label> | no cr state | state
   cannot be read>` and posts nothing). The record holds the
   commit, the previous version, the SHA-256 of the package executable, the SHA-256 of each
   mechanism file, the probe result line, the page check result line, and any return to the
   previous version. It holds no quote, dollar sign or backtick.
7. **Accepted limit** (operator, verbatim): "I accept knowingly that this guards against
   accidents and shortcuts, not against a deliberate swap by a session running under my
   account."

   The rules of the table under [rules not met](#rules-not-met) stay not met.

### Standing consent at 1 %

The operator's consent, verbatim: "Transmitting is not a concern: tests transmit at 1 % RF
power, except QSO tests." It covers the real IC-7300 once the operator has decided #239;
until then live tests key the simulator ([Simulator live tests](#simulator-live-tests)).
Cost 4 and 5 live tests run without asking when all of these hold:

- `tools/test/powershell/radio-preflight.ps1` has taken the radio lease and set RF power to
  `0003` (1 %, 1.2 % of the control) with read-back before anything keys;
- the test transmits only on 10, 15, 20 or 40 m;
- afterwards it restores the power found and every setting it changed.

A QSO test keys under this consent with the two exceptions, power and bounds of
[QSO tests](#qso-tests).

### Keying the radio

How an agent keys the real IC-7300; when it may, the [standing consent](#standing-consent-at-1-)
says.

- **RF power** is whatever the radio reads: each test sets the level it needs, and nothing
  keys at an assumed one. The value of CI-V `14 0A` is the radio's RF POWER control from
  `0000` to `0255`, not watts, and Po also follows the Tx level and the profile's limit.
  Measured on 20 m at -19 dB, without a wattmeter: `0128` gave Po 34–43 %; `0003`, `0013`
  and `0026` gave Po 0 to 1 %. Short keying without a QSO uses `0003`; a QSO test keys its
  SWR check at `0128` and its QSO at `0255` ([QSO tests](#qso-tests), items 4 and 7). CI-V
  reads first and writes only on a difference.
- **Preflight.** Before keying, an agent runs
  `tools/test/powershell/radio-preflight.ps1 -Holder <run> -PowerBcd <value>` and keys only
  on exit 0, under its lease (`-Status`, `-Release`). `-Port COM<n> -Baud <n>`, both or
  neither, name the CAT port (the simulator profile's: `-Port COM4 -Baud 115200`); without
  them it is `radio-port.json`'s (COM3, the real IC-7300). The lease and each record of
  `preflight.jsonl` hold the port and baud; `-Restore`, a renewal and `-NoWrite` use the live
  lease's port, and a call naming another one while that lease is live exits 2 and opens no
  port. It stops an idle station gracefully,
  because the station holds the port, reads the power, writes it only if different, reads it
  back, starts the station again and records the old value. It refuses to key only when the
  power cannot be read, written or confirmed by the read-back: exit 2, nothing keys, and the
  agent reports it to the coordinator. Afterwards `radio-preflight.ps1 -Restore -Holder <run>`
  puts the old value back and ends the lease; when that fails the lease stays for another
  try. With no live lease (it expired, a renewal failed, or `-Release` gave up the old value,
  which it prints), run `-PowerBcd <old value from preflight.jsonl>`, then `-Release`.
  Because it restarts the station, it does not run while the operator is operating, unless
  agreed: it sees only PTT and a contact, not someone watching Band Activity.
- **Contacts.** A contact you did not start, seen while another run's lease is live, is that
  run's; the station itself does not check this. A stop a test triggers never aborts a
  contact at or after RR73 or 73: that contact ends on its own.
- **Set back.** A cost-4/5 live test sets back what it changed
  ([testing](../../../general/core/docs/standards/testing.md#cost-levels)): band, frequency,
  mode, strategy, Auto, Hold Tx, Tx/Rx, theme and power. A CAT setting change resets the
  receive-only setup confirmation ([CAT confirmation](#simulator-live-tests)), which the
  operator then gives again.

### Simulator live tests

Live tests run against the FT-8 Band Simulator instead of the transceiver
(handoff: SensorsIot/FT-8-Band-Simulator
`docs/ImplementerPackage/README.md`). Transmitting into the simulator, QSOs included, needs
no consent: nothing reaches an antenna. The tester uses FT4 unless a case needs FT8.

- **Profile.** `%LOCALAPPDATA%\WstxRust\station\profiles\SIM-IC7300`: CAT and PTT on COM4
  (`icom7300://COM4?baud=115200&radio=94&controller=e0`), the VB-Audio cables of the
  handoff, its own `contacts.adi`, `udp.json` with one target `127.0.0.1:22370` (`qso_logged`,
  `logged_adif`), `pskr.json` disabled. The
  operator profile `ic7300` and its logbook are never touched; their hashes are taken before
  and compared after.
- **Switch.** The real IC-7300 may be on or off: with `WSTX_RADIO_DISCOVERY=off` the station
  opens only COM4. `tools/test/powershell/station-switch.ps1 -To simulator` (the tester or
  the coordinator) backs up `station\launcher.ps1` once, points its profile line at `profiles\SIM-IC7300` and sets
  `WSTX_RADIO_DISCOVERY=off` and `WSTX_PSKR=off` (without discovery off, a silent COM4 makes
  the station adopt the real radio on COM3), and `WSTX_UDP=off` unless every target of the
  profile's `udp.json` is on `127.0.0.1` and none on the operator logger's port 2237 (it says
  which, and why UDP stays off), stops the station gracefully
  (Ctrl+C, `station-control.ps1`, as `radio-preflight.ps1` does), restarts the task, reads
  the profile back (`GET /radio`, `station-running.json`) and compares the hashes of the
  operator profile and its logbook; any difference exits non-zero. Return:
  `station-switch.ps1 -To back`, the last step of the tester's run, or the coordinator: the
  backed-up launcher (without one, the pinned launcher), the same restart. `-DryRun` prints
  every step and changes nothing.
- **CAT confirmation.** A new profile, and any change of its CAT setup, needs the operator's
  receive-only confirmation in the browser (Settings, "CAT receive-only confirmation");
  until then CAT stays closed. Agents never change the CAT endpoint during a simulator run.
- **Emulator.** Each run starts its own IC-7300 emulator on COM5 at 115200 baud and stops it:
  `tools/test/powershell/emulator.ps1 -Start` refuses while any process runs the emulator on
  COM5 or its record names a live one, starts `simulator.py --serial COM5 --baud 115200` of
  `D:/Github/IC-7300 simulator` as its own hidden process with stdin held open, waits until its
  new run folder starts the serial transport and records it (pid, creation time, command) in
  `<git common dir>/harness-parallel/radio/emulator.json` beside the radio lease; `-Stop` ends
  exactly the recorded process and its descendants, never another; `-Status` reads it. The
  run's order: `station-switch.ps1 -To simulator`, `emulator.ps1 -Start` once the station runs
  (the station opens COM4 before the emulator's transport), test, halt, `emulator.ps1 -Stop`,
  `station-switch.ps1 -To back`; the station is not restarted while the emulator runs, with
  one exception: the radio preflight of a QSO test stops and restarts it on SIM-IC7300 while
  the emulator runs ([QSO tests](#qso-tests), item 7).
- **Band simulator.** Operated as its project describes it: the tester skill
  `skills/wsjtx-simulator-testing/SKILL.md` and the handoff package of
  SensorsIot/FT-8-Band-Simulator. Agents here do not change the simulator projects.
  `GET /radio` reads `ready` when CAT works.
- **Deploys.** A deploy writes the pinned launcher, so the station returns to `ic7300`;
  switch back to the simulator afterwards if the run continues.
- **Keying the emulator** is not a transmission. Before every keying the agent confirms
  that the active profile is SIM-IC7300; no simulated contact reaches the real logbook, the
  operator's logger, Club Log or PSK Reporter; a loopback listener the test run starts in its
  run folder may receive the station's UDP messages (WSJT-X QSO Logged and Logged ADIF) and
  count the records of each QSO, and the run stops it at its end; an agent returns the
  station to the `ic7300` profile only with `station-switch.ps1 -To back`, after the emulator
  is stopped. Live tests key the simulator: the IC-7300 emulator and the band simulator. The
  real IC-7300 is keyed once the operator has decided so in #239 (`alex.restrictions`).
- **Administrator rights.** Agents have none. A step that needs them is a script the
  operator runs in an elevated shell, restoring what it changed in a `finally` block.

### QSO tests

A CR whose acceptance names a QSO is tested by an agent with the QSO test driver
`tools/test/powershell/qso-test.ps1`, run as `powershell -NoProfile -ExecutionPolicy Bypass
-File tools/test/powershell/qso-test.ps1 -Holder <run> -Issue <n> -Item <k>`; its tests are
`test_qso_test.py` beside it (suite test-bench). The operator's bounds, approved on
2026-11-12, 2026-11-13 and 2026-11-14 and bound by #192 (its decision comments quote them),
are its items 3 to 11; the numbers follow #192:

3. **Profile guard** (2026-11-14). It keys only while `GET /transmit` `profile_id` is the
   one of `profiles\SIM-IC7300\profile.json`, and takes the preflight's `-Port` and `-Baud`
   from that profile's `control.endpoint`; an endpoint naming COM3, or one that does not
   parse, exits 2 before any preflight call. It checks the profile before the preflight,
   before Tune and before every own transmission, and every command it sends carries that
   `profile_id`, so a station running another profile refuses it (`wrong_profile`); any other
   profile ends the run under the stop order, naming #239. It never switches the profile; the
   bench is the tester's.
4. **Use** (2026-11-12). Only where an acceptance item names a QSO, under this consent, with
   two exceptions to `0003`: the SWR key at `0128` and the QSO at `0255`. It answers a CQ;
   the CQ path or Auto only where the item names it.
5. **Target** (2026-11-13), from the decode data, never the text: a general CQ (`fields.type`
   standard, `fields.to.kind` token, `fields.to.text` exactly CQ; a nonstandard call is
   skipped); his newest decoded message is that CQ; not field_day, rtty, vhf or dxpedition;
   `worked_status` present and not worked_this_band_and_mode; fewer than 2 other stations
   sent to his call in the two most recent decoded periods that each follow one of his CQs.
   While fewer than two such periods are decoded it waits without keying. He is dropped when
   he does not call CQ again within two of his cycles (his Tx period plus the next: 30 s FT8,
   15 s FT4) or his newest message is no longer a CQ. Waiting does not count.
6. **Tx frequency** (2026-11-13). Before its first command the driver records Hold Tx Freq,
   `rx_hz` and `tx_hz`; before the first call it sets Hold Tx Freq on and `tx_hz` by
   `set_frequency`; at the end it sets all three back. `tx_hz` is an f with lo ≤ f ≤ hi −
   width in an open range of the newest `free_tx_slots` build whose `rx_parity` is his Tx
   parity: the f nearest his frequency that is `split_clear` of his signal, with none the lo of
   the nearest range. While the build is null, has the other parity or has no such f, it
   does not call.
7. **Power and SWR** (2026-11-12, 2026-11-13). The preflight sets `0128` with read-back
   (`-Holder <run> -Minutes 90` on the port of item 3); after each preflight call the driver
   waits up to 60 s for `GET /radio` ready, else not tested before keying. It subscribes to
   `radio.tx_level`, runs Tune for 3 s and reads the pushes received between the Tune-on reply
   and the Tune-off command with `meters`, `po_pct` and `swr_x10` not null; the SWR is their
   highest `swr_x10`. No such push, `po_pct` 0 in every one, `swr_x10` 30 or more (SWR 3.0) or
   `swr_fault`: not tested, no `0255` write, the reading reported to the operator. Otherwise
   the preflight sets `0255` with read-back, which renews the lease.
8. **Counting and time** (2026-11-13). A transmission is a distinct non-null
   `last_period_utc`; Tune is not counted. `watchdog.tx_calls` 6 or below is accepted, 7 or
   above ends the run before keying; the driver never sets it. No call within 30 minutes of
   the `0255` read-back: not tested. Phase 1, before the first answer: at most 4 calls to one
   station, then another target; at most 10 transmissions, then not tested. A limit counts
   whole sends: the send that reaches it ends before the abort, which comes before the next
   own period. Phase 2 starts
   at a decoded message from the target to the own call; the QSO runs to the 73 under the
   station's rules and is logged normally; a silent partner, or an end by the station's
   watchdog or leave rule, is not tested with the observation. The backstop is 30 minutes from
   the first call; reaching it is a fail.
9. **Stop order**, at every end: Auto off; abort the contact the driver started unless it is
   at rogers, signoff or completed (it ends on its own and the driver waits; one aborted at
   the backstop stays unlogged, and the test fails); Halt only if PTT is still keyed; the
   item 6 values set back; `-Restore` with read-back, a BUSY restore retried every 10 s.
   Without a live lease the value restored is `rf_power_old_bcd` of this holder's first
   `preflight.jsonl` record with verdict PASS and restore false, set on that record's port,
   then the lease is released. A contact the driver did not start is never aborted.
10. **Verdicts** (2026-11-13). Failed: the backstop or a wrong action, whatever else happens:
    (a) a new `last_period_utc` while the transmit state is off (no accepted start since the
    last stop, judged on the state read before it appeared), outside Tune, or after the stop
    order released PTT; a send on the air when a stop arrives may finish; (b) a keyed CQ or a
    message to another call than the target; (c) in a manual test QSO with Hold Tx Freq on, a
    `tx_hz` other than the driver's, except the busy move (while `busy_with` is set or in the
    step that cleared it) until #109 or #314 lands, and not checked in Auto; (d) one message
    keyed more than `tx_calls` times, or twice that with busy pauses; (e) a completed contact
    with outcome unsaved or an error; (f) the previous message keyed again in the second own
    period after a decode that moved `contact.state` forward. Passed: the target's contact
    completed with `last_disarm_cause` contact_completed, its dialogue with his message to the
    own call, a report each way and RR73 or 73, the log saved without error. Not tested beats
    passed: the cases of items 3, 5, 7 and 8, and every `last_disarm_cause` other than
    contact_completed and the driver's own abort, with the cause and the newest outcomes
    failure recorded.
11. **Records and retries** (2026-11-21). Each verdict is appended to `qso-tests.jsonl`
    beside `preflight.jsonl` under the issue and item, with the deployed revision (the
    `x-wstx-source-commit` of `GET /`) and the radio (the `profile_id` of `GET /transmit`).
    Not tested leaves the item open, with no revert and no escapes row, retried at another
    time or band. At most 3 attempts per item per deployed revision and per radio: the
    simulator and the real IC-7300 each have their own 3, and a newly deployed revision starts
    at 0. The records of earlier revisions, and those without a revision, stay in the file and
    do not count. A 4th attempt on the same revision and radio is refused before the preflight
    and names the operator, who decides it. A station that reports no deployed revision (no
    `x-wstx-source-commit`, more than one, `unknown`, or not 40 lowercase hex) is refused
    before anything is touched, with no attempt counted. Beyond C of #171 the operator is
    asked only for a high SWR, no Po or no fresh reading, and for an item left not tested 3
    times on one revision and radio.

**Stated limits.** The decode data does not mark a Fox's own plain CQ or the contests with
the standard exchange (ARRL Digi, WW Digi); the driver cannot recognise either, and the
pile-up and newest-message rules skip them often, not always.

### Operator role and returns

The operator is asked only for open questions and changes to the product contract, whether
to push past a red test, and items only a person can judge. An installed CR that fails acceptance or is returned gets a row in the
escapes ledger.

### Probe, tests and drill

**After every install** `station-update.ps1` runs the independent probe itself (policy
item 5). Run by hand, `PROBE FAIL` (exit 1) calls for `station-update.ps1 -Rollback`;
`PROBE ERROR` (exit 2) is a wrong argument, not a verdict:

```powershell
<package>\deploy\tools\deploy\station-probe.ps1 -Manifest <package>\manifest.json
```

It is read-only. It asks Windows which process listens on TCP 18081, hashes that
process's executable itself and requires the candidate's commit directory and the digest
of the package's own `wstx-rust.exe` (recomputed, not read from the manifest), then HTTP
200 from `https://192.168.0.37:18081/` over TLS that Windows trusts. In the same
response, the station's `x-wstx-source-commit` header must be the candidate's commit
(CL-033-01). This is the commit the running service itself reports. `make_package.py`
compiles it in as `WSTX_SOURCE_COMMIT`, and a build without one reports `unknown`, which
fails. An older build sends no header, for example a rollback target. The probe
then says so and keeps the image digest as the identity. Last, it checks that the launcher
receipt agrees with what it observed. Tests of the deploy mechanism, its pins and its drill
are suite `deploy-tooling` (cost 2, `harness/project/suites/deploy-tooling.yaml`):
`python -m unittest discover -s tools/deploy/tests -v`.

The operator can check the result without any agent; this is not a step of each install:

```powershell
(Invoke-WebRequest -UseBasicParsing https://192.168.0.37:18081/).Headers['x-wstx-source-commit']
```

It prints the commit the station reports. Compare it with the commit announced on the
issue.

**When `station-update.ps1` changes** run the refusal drill and record its output on the
change's issue (suite `deploy-tooling` runs it too, through `test_station_drill.py`):

```powershell
python tools\deploy\station_drill.py
```

It runs a copy of the script against a sandbox station, with `LOCALAPPDATA` in a temporary
directory and the task, firewall, processes, network and git replaced by mocks. Starting
or stopping anything records a sentinel and throws. Before running, it parses the script
and refuses any command (also inside `"$(...)"`), .NET type or call target it has not
classified, `$ExecutionContext`, an environment variable other than `LOCALAPPDATA`, and a
literal absolute path other than the repository and the deploy-authority root. This keeps
the commands the drill knows away from the live station. It is no sandbox against a
script written to escape it: read a changed script's diff before drilling it. Each case damages one thing in a package built as `make_package.py`
builds it and requires the refusal's own message, no sentinel and an unchanged
destination (version folders, `active.json`, profiles, launcher; `logs\` may change).
The cases are: tampered artifact, manifest naming another artifact, changed gate
record, gate record of another commit or artifact or not passed, changed push-gate log,
commit not on GitHub master, master unreachable, abbreviated commit, package paths that
escape or name a stream, gate record outside the package, no executable, wrong firewall
scope, task not on the launcher and a staged copy that differs. Two controls show the
mocks refuse nothing by themselves: the intact package passes `-DryRun`, and without it
the script reaches the station stop. Two `LIMIT` cases are expected to be accepted: a
consistent rewrite of executable and records, and an older commit on master. Its two
approval cases apply only with a deploy authority, which this project does not use; the
drill reports them not applicable.

The drill runs the package's own pinned copy with a scripted clock (10 s polls from
12:00:00) and a sandbox station whose state the package's agent client reports. The idle
cases (TC-171-01) each require the busy reason in the refusal, no stop sentinel and an
unchanged destination: update lock held, a live radio lease, no and two station processes,
transmit armed, PTT keyed, transmitting, a contact replying, a contact replying after a
`device_lost` disarm, an automation run active, and a state that cannot be read. Busy that
clears at 290 s proceeds to the stop; still busy at 300 s gives up. The radio cases
(TC-196-04) add a radio `closed`, `connecting`, `closing`, `unavailable` or whose
reply cannot be read: each waits to `12:05:00 WAITING FOR THE RADIO` with exit 6 and no
stop; a radio `ready` from the first reading, or from 290 s, proceeds to the stop; transmit
armed until 310 s with the radio closed ends with the busy reason and exit 3. A second
update started between the idle check and the stop is refused because the first holds the
lock. The pin cases (TC-196-01, TC-196-02): all pins equal passes `-DryRun`; a working-folder
copy of the script is refused (only the package's copy runs); a package file edited after
the build, a commit without pins and pins in another order each refuse with exit 1 and
their reason before any write; new pins that differ from the running pins, a running commit
without pins and a station launcher that differs from its pin log `deploy mechanism changed:`
and reach the stop; a call naming an operator's-OK parameter stops at binding before any
step. No case prints a `Deploy OK` line or reads a comment. `-Rollback` with differing pins
or with the radio closed reaches the stop without asking, and `-DryRun` does not read the radio.

### Rules not met

These rules of the harness's deployment authority stay not met, by the operator's decision:
the deploy authority stays off, and the gate, the package checks, the
idle check, the probe, the automatic return and the pinned, versioned deploy scripts take its
place. The [standing deploy policy](#standing-deploy-policy) authorizes this mechanism in place
of an OK per install:

| Rule | State |
|---|---|
| Credentials outside the agents | Not met: agents run as the HB9BLA user and can write the version directory, `active.json`, the receipt, the gates record and the package and station-update scripts. Only the task and firewall changes need the operator's elevation. |
| Approval names the candidate | Not met: the manifest names commit and executable SHA-256, but the agents write it and no approval is bound to it. |
| Verify before writing | Not met in full: `station-update.ps1` refuses a changed artifact, package path, gates record, push-gate log, unpublished commit, task or firewall scope before writing, but against an agent-written manifest beside the artifact. |
| Prove the result | Not met in full: `station-update.ps1` checks the launcher receipt and HTTP 200, and `station-probe.ps1` checks, independently of the receipt, that the process listening on 18081 runs the candidate's bytes, answers over trusted TLS and reports the candidate's commit itself (`x-wstx-source-commit`); the operator can read that report without an agent. But an agent runs the probe and the rollback after it, and on HB9BLA everything except the operator runs with the agents' rights. |
| Show the refusals | Not met in full: `station_drill.py` shows each refusal of `station-update.ps1` before the destination changes (above), and that a consistent rewrite of artifact and records and an older commit on master are accepted. |

**Platform limits.** `execution_mode: local`: the hooks and the push gate run on the
client with the agents' own rights. The repository has no branch protection and no
required remote status check. There is no environment approval. None of these rules is
enforced by the platform.
