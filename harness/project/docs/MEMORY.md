# Current project memory

Pointers only: every rule and fact lives in the document named here, and the current state
lives in Git and the GitHub issues. Recheck them before continuing. The HB9BLA handover
follows the pointers, from [Start](#start) to [Inputs and unfinished work](#inputs-and-unfinished-work).

- **Start:** [AGENTS.md](../../../AGENTS.md), then the `harness-coordinator` skill (the main
  session's role) and the [Harness Overview](Harness-Overview.md).
- **Product authority:** the [functional authority binding](Project-Specifics.md#exclusive-functional-authority);
  entry point `docs/sysml/Requirements.sysml`.
- **Machines:** [machines and roles](Project-Specifics.md#machines-and-roles); the issue's
  `owner:` label names the machine building it.
- **Runtime and data locations on HB9BLA:** [Preserve the runtime](#preserve-the-runtime) and
  [Inputs and unfinished work](#inputs-and-unfinished-work) below.
- **Taking a new harness pin on this clone:** [every clone takes the pin](../../general/core/docs/Harness-Changes.md#every-clone-takes-the-pin).
- **Where every CR stands:** `python harness/general/core/tools/cr_state.py status` and
  `python harness/general/core/tools/merge_queue.py status`.
- **Open work and decisions:** the open issues and their newest comments; a paused CR's
  [checkpoint](../../general/core/docs/CR-Reporting.md#restart-and-handoff-checkpoint)
  names its next action and owner. Deployed source: the issue checkpoint and the private
  runtime receipt, never a remembered version.
- **The harness layout (#230):** everything under `harness/` is the harness: the general
  harness (the submodule `harness-general`) at `harness/general/`, the project harness at
  `harness/project/`. A branch from before #230 has the submodule at `harness` and the project
  harness at its old places; see [the layout change](#the-layout-change).

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
- IC-7300: **COM3**, USB Audio CODEC; in use on **20 m FT8 (14.074 MHz USB-D)**; agent tests that
  make QSOs use at least 30 W, short non-QSO keying 1 W, set by the test; **AGC SLOW**
  for FT8/FT4 (operator finding: it removes the AGC line between periods). Read back before
  changes — CI-V reads first and writes only on a difference.
- RF power is whatever the radio reads, not a fact of this page: each test sets the level it
  needs (operator 2026-11-07: "the power should be set by the tests"). The value of `14 0A` is the
  radio's RF POWER control from `0000` to `0255`, not watts, and Po also follows the Tx level and
  the profile's limit. Measured on 20 m at -12 dB: `0077` gave Po 24-26 %, `0090` gave Po 30-31 %;
  `0003` showed Po 0 %; no wattmeter. A test that makes QSOs ("for qsos, you need at least 30W")
  uses `0090` or more and checks Po on its first Tx; short keying without a QSO may use `0003`.
  **Before keying, an agent runs
  `harness/project/deploy/radio-preflight.ps1 -Holder <run> -PowerBcd <value>` and keys only on
  exit 0, under its lease** (`-Status`, `-Release`). The level is required: nothing keys at an
  assumed one. It stops an idle station gracefully, because the station holds COM3, reads the
  power, writes it only if different, reads it back, starts the station again and records the
  old value. It refuses to key only when the power cannot be read, written or confirmed by the
  read-back: exit 2, do not key, and report it to the coordinator. **Afterwards
  `radio-preflight.ps1 -Restore -Holder <run>` puts the old value back and ends the lease**;
  when that fails the lease stays for another try. With no live lease (it expired, a renewal
  failed, or `-Release` gave up the old value, which it prints), run `-PowerBcd <old value from
  preflight.jsonl>`, then `-Release`. Because it restarts the station, do not run it while the operator is operating, unless
  agreed: it sees only PTT and a contact, not someone watching Band Activity.
  A contact you did not start, seen while another run's lease is live,
  is that run's. The station itself does not check this.
- Agent tests transmit only on 10, 15, 20 or 40 m (the IC-7300's antenna). A stop a test
  triggers never aborts a contact at or after RR73 or 73: that contact ends on its own.
- A cost-4/5 live test sets back what it changed ([testing](../../general/core/docs/standards/testing.md#cost-levels)):
  band, frequency, mode, strategy, Auto, Hold Tx, Tx/Rx, theme and power. A CAT setting change
  resets the receive-only setup confirmation, which must then be given again.
- Function test before review ([CR process](../../general/core/docs/CR-Process.md), step 2): a
  few short transmissions on a development build need no prior review (operator 2026-11-06: "If
  they are short, nobody will complain"). Long or unattended automatic running on the air
  needs its safety review first.
  The camera microphone belongs to Dictate, not the radio.
- Station log: `%LOCALAPPDATA%\WstxRust\station\profiles\ic7300\contacts.adi`, updated on
  2026-11-04 from the operator's Log4OM export (26,886 QSOs). A rerun of Update logbook
  with the same export adds nothing.
- Install under the standing deploy policy ([deployment authority](Project-Specifics.md#deployment-authority)):
  in Git Bash, `git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> <green gate log>`
  (a merge-queue log under `.git\harness-parallel\queue\logs\` that shows the push), then the
  package's own `deploy\tools\deploy\station-update\station-update.ps1 -Manifest …` that it
  prints. That one run waits for an idle station and an answering radio (at most 300 s, else
  exit 3 for a busy station or exit 6 for a radio that did not answer, nothing changed),
  installs, runs the probe and the live page check, returns to the previous version
  when either fails, moves the CRs to installed and posts the install record. Exit 6: the
  radio did not answer and nothing changed; report it to the operator and run the same
  command again once the radio answers. A contact you did not start is never aborted
  to make the station idle.
- A deploy of a commit from before #230 runs that commit's own script, whose record step calls
  the harness at its old place. In a checkout already in the new layout that call fails: the
  log says "record not posted" and the install itself goes ahead. The coordinator then posts
  the record by hand (`python harness/general/core/tools/cr_state.py installed <commit> --since
  <previous>` and the install record on each issue it moves).
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

Without these, a push that selects any suite whose `needs` in `harness/project/suites.yaml`
names a WSTX_* input is refused red. The merge-queue worker reads the same inputs from
`queue.env` in `harness/project/config.yaml`; run it as a background job from the main checkout:

```bash
HARNESS_REPO=D:/Github/wsjtx-rust python D:/Github/harness-mq/core/tools/merge_queue.py worker
```

`D:\Github\harness-mq` is a harness clone at the pinned (or newer reviewed) commit; keep it
and the main checkout's `harness/general` submodule on the same commit. Agent builds use their own
`CARGO_TARGET_DIR=D:/wstx-build/<worktree>` and `TEMP`/`TMP` set to that same folder (never
inside a worktree, never shared): Cargo creates it before the linker needs it, so no
one has to make a temp folder first (link.exe fails with LNK1104 on a missing one). Agents do not wait for `busy` (it starves them when the
queue gates back to back): they run beside the gate at BelowNormal with 2 build jobs and
rerun a timing-sensitive failure once. Gate builds go to
`D:/harness-cargo-target/wsjtx-rust/<checkout>` and are pruned by the gate itself; agent
build directories are pruned with `harness/general/core/tools/build_prune.py agent-dirs --root DIR
--apply` (harness/general/lang/rust/standard.md, "Build folders").

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

## The layout change

#230 moved the general harness from the submodule path `harness` to `harness/general` (submodule
name `harness-general`, its own module store `.git/modules/harness-general`) and the project
harness under `harness/project/`. A checkout moves between the layouts by the merge queue's
sequence (`git checkout -q --detach -f <commit>`, `git clean -q -fd`,
`git submodule update --init --recursive -q`) only after a one-time step, because the sequence
alone leaves the other layout's submodule behind:

- **Old layout to new**: `git -C <checkout> submodule deinit -f harness` at the moment that
  checkout switches, then the sequence: the merge queue's worktree right before it takes #230's
  candidate (the queue idle), the main checkout when it takes master after #230 landed, and every
  other worktree when it rebases or merges onto master after #230. A checkout that stays on a
  branch from before #230 is not touched: the deinit would take its harness away. Without it the gitfile `harness/.git` stays, and every git call from
  `harness/project/` (the radio preflight's lease folder among them) resolves to the old
  submodule instead of the checkout. A checkout that already moved without the step: delete the
  file `harness/.git`; `git -C <checkout>/harness/project rev-parse --show-toplevel` then names
  the checkout itself.
- **New layout to old** (a parent checked out by hand, a branch older than #230):
  `git -C <checkout> submodule deinit -f harness/general`, then the sequence. Without it
  `harness/general` stays inside the old submodule and the old submodule's files stay deleted;
  the repair is `git -C <checkout> submodule update --init --force` and
  `git -C <checkout>/harness clean -ffdq`.

Then, once per clone, `install_hooks.py` of the new pin (the operator's; its hooks enter
through shims in the clone's git directory, harness#136, so each checkout and worktree runs
its own pre-push in either layout), and `secrets.md` moves to `harness/project/secrets.md`.
