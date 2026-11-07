# HB9BLA agent handover

## Start

Use **`D:\Github\wsjtx-rust` on HB9BLA (`192.168.0.37`)**. Read `AGENTS.md`,
`MEMORY.md`, the pinned harness and current GitHub issues. The operator authorizes
continued implementation, tests, parallel agents and radio work until they return.
Read the current authority binding before functional edits. With canonical SysML, use
model requirements/tests, independent review, code, ordinary gates and live acceptance.
Archived functional Markdown is not maintained or used as an implementation oracle.
Do not close partial issues or bypass red checks.

Use the checked-out commit, current GitHub checkpoint and station-running receipt to
identify source and deployed versions separately. Previously recorded results are not
passes for a changed candidate. HB9BLA has Rust/MSVC, Python, Node and browser prerequisites;
verify their availability in the actual agent environment before starting work.

## Preserve the runtime

- Station: **https://192.168.0.37:18081**, task `WSTX Rust Station HB9BLA`;
  receipt `%LOCALAPPDATA%\WstxRust\station\station-running.json`.
- IC-7300: **COM3**, USB Audio CODEC; in use on **20 m FT8 (14.074 MHz USB-D)**; **AGC SLOW**
  for FT8/FT4 (operator finding: it removes the AGC line between periods). Read back before
  changes — CI-V reads first and writes only on a difference.
- RF power is whatever the radio reads, not a fact of this page: agent Tx is authorized at
  1 W (`.harness/deploy/radio-authorization.json`), and on 2026-11-06 the radio read `0026`
  (about 10 W; #44). **Before keying, an agent runs
  `.harness/deploy/radio-preflight.ps1 -Holder <run>` and keys only on exit 0, under its lease**
  (`-Status`, `-Release`). It stops an idle station gracefully for the CI-V read, because the
  station holds COM3, starts it again, and records the value; it writes nothing to the radio.
  Above the authorization it refuses, with no override: do not key, and report it to the
  supervisor. The power is lowered only on the supervisor's go-ahead under the #44 write consent
  (read, write, read back, record the old value, restore it afterwards); otherwise the test
  waits. Because it restarts the station, do not run it while the operator is operating, unless
  agreed: it sees only PTT and a contact, not someone watching Band Activity.
  A contact you did not start, seen while another run's lease is live,
  is that run's. The station itself does not check this.
- Function test before review ([CR process](../../harness/core/docs/CR-Process.md), step 2): a
  few short transmissions on a development build need no prior review (operator 2026-11-06: "If
  they are short, nobody will complain"). Long or unattended automatic running on the air
  needs its safety review first.
  The camera microphone belongs to Dictate, not the radio.
- Station log: `%LOCALAPPDATA%\WstxRust\station\profiles\ic7300\contacts.adi`, updated on
  2026-11-04 from the operator's Log4OM export (26,886 QSOs). A rerun of Update logbook
  with the same export adds nothing.
- Install: build `resources\station-update\make_package.py <commit> <green gate log>` (a
  merge-queue log under `.git\harness-parallel\queue\logs\` that shows the push), then
  `station-update.ps1 -Manifest …`, then `.harness\deploy\station-probe.ps1 -Manifest …`;
  afterwards `cr_state.py installed <commit> --since <previous>`. Check `/transmit` is
  idle first; never install while the operator is in a QSO without asking.
- Official WSJT-X **3.3.0-beta4** runs alongside ours as `WSTX-Comparison`,
  Rig=None, no CAT/PTT, Fast/AP-off. A connected Edge frontend runs here too.
- Keep credentials private. Codex is signed in. Development secrets/SSH keys and
  GitHub access are transferred separately; verify readiness without printing values.
  Read `%LOCALAPPDATA%\WstxMigration\credential-tools\PRIVATE-CREDENTIAL-HANDOFF.md`.
  Scoped Infisical authentication/secret reading works with normal TLS validation;
  native CLI use still needs standard Windows CA trust. Do not bypass TLS.

## Continue from current ownership

GitHub issues own the approved work order, current candidate, review, actual evidence and
next action. Check them before applying an old branch, patch or diagnostic recommendation.
Keep open runtime work in its owning #7/#8/#9/#10/#11/#12/#13 issue; a helper report or
isolated passing test is not issue completion. Preserve known model, code and radio
ownership and one integration writer across the two PCs.

The model/authority transition is #20 with the separate project harness rollout #21.
Shared model writes and publication are serialized with the documentation lane. Once the
canonical marker and functional archive are published together, prepare future changes
in SysML directly. The modem's test fixtures remain internal diagnostics, not a requested
offline-decoding product. Keep the existing0..3000Hz/2.93Hz-bin display contract unless an
approved functional requirement changes it.

## Inputs and unfinished work

Verified inputs are `.git\migration-data\`; configure each development shell:

```powershell
$data = Join-Path (git rev-parse --path-format=absolute --git-common-dir) 'migration-data'
$env:WSTX_SAMPLE_DIR = Join-Path $data 'recordings'
$env:WSTX_DECODER_CACHE = Join-Path $data 'quality'
$env:WSTX_DECODER_VECTORS = Join-Path $data 'frozen'
$env:WSTX_DECODER_SYNCHRONIZATION = Join-Path $data 'synchronization'
$env:WSTX_DECODER_OFFICIAL_FT8 = Join-Path $data 'official-ft8\210703_133430.wav'
$env:CARGO_BUILD_JOBS = '2'
$sim = Join-Path (git rev-parse --path-format=absolute --git-common-dir) 'harness-parallel\resources\issue-18\delivery-v2\CR18-simulated-samples-v2-03aef7cde-toold06cee63463b'
$env:WSTX_SIMULATOR_SAMPLE_DIR = Join-Path $sim 'ft4'
$env:WSTX_SIMULATOR_ORACLE_DIR = Join-Path (git rev-parse --show-toplevel) 'fixtures\decoder'
```

Without these, a push that selects any suite whose `needs` in `.harness/suites.yaml`
names a WSTX_* input is refused red. The merge-queue worker reads the same inputs from
`queue.env` in `.harness/config.yaml`; run it as a background job from the main checkout:

```bash
HARNESS_REPO=D:/Github/wsjtx-rust python D:/Github/harness-mq/core/tools/merge_queue.py worker
```

`D:\Github\harness-mq` is a harness clone at the pinned (or newer reviewed) commit; keep it
and the main checkout's `harness` submodule on the same commit. Agent builds use their own
`CARGO_TARGET_DIR=D:/wstx-build/<worktree>` and `TEMP`/`TMP=D:/wstx-tmp/<worktree>` (never
inside a worktree, never shared). Agents do not wait for `busy` (it starves them when the
queue gates back to back): they run beside the gate at BelowNormal with 2 build jobs and
rerun a timing-sensitive failure once. Gate builds go to
`D:/harness-cargo-target/wsjtx-rust/<checkout>` and are pruned by the gate itself; agent
build directories are pruned with `harness/core/tools/build_prune.py agent-dirs --root DIR
--apply` (harness/core/docs/Parallel-Work.md, "Build output").

Use this synchronization set, not stale `synchronization-inputs-final`/`-lf` caches.
Evidence: `.git\migration-evidence\hardware-preparation\`; original design: sibling
`design\`. JDK/Pilot: `%USERPROFILE%\.cache\wsjtx-rust\sysml-tools`.
[GitHub handoff assets](https://github.com/SensorsIot/wsjtx-rust/releases/tag/handoff-2026-10-27)
preserve public inputs/evidence and product-only branch/dirty-worktree backups.
Read `product-migration-audit\RESTORE.md`; fetch bundled tips under a backup
namespace, never overwrite main or blindly apply historical FSDs. Private proof/audit
stays `.git\migration-private\` and must not be uploaded publicly.

Use the exact harness gitlink of the checked-out candidate. A source-harness publication
alone is not project adoption: a pin update is its own harness change, reviewed and then
pushed.
Skills are the pinned harness's, through the generated `.claude/skills/` entrypoints
(`install_skills.py`); registered user skills preserve user state. Never
install Fortran locally.
