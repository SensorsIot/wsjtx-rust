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
- IC-7300: **COM3**, USB Audio CODEC; last prepared for **FT4, 14.080 MHz USB-D,
  FIL1 3000 Hz, both notch filters off, centred PBT**. Read back before changes.
  The camera microphone belongs to Dictate, not the radio.
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
```

Use this synchronization set, not stale `synchronization-inputs-final`/`-lf` caches.
Evidence: `.git\migration-evidence\hardware-preparation\`; original design: sibling
`design\`. JDK/Pilot: `%USERPROFILE%\.cache\wsjtx-rust\sysml-tools`.
[GitHub handoff assets](https://github.com/SensorsIot/wsjtx-rust/releases/tag/handoff-2026-10-27)
preserve public inputs/evidence and product-only branch/dirty-worktree backups.
Read `product-migration-audit\RESTORE.md`; fetch bundled tips under a backup
namespace, never overwrite main or blindly apply historical FSDs. Private proof/audit
stays `.git\migration-private\` and must not be uploaded publicly.

Use the exact harness gitlink of the checked-out candidate. A source-harness publication
alone is not project adoption: updates require their separate rollout and actual trial.
Skills source is `D:\Github\agent-skills`; registered skills preserve user state. Never
install Fortran locally.
