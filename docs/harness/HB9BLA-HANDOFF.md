# HB9BLA agent handover

## Start

Use **`D:\Github\wsjtx-rust` on HB9BLA (`192.168.0.37`)**. Read `AGENTS.md`,
`MEMORY.md`, the pinned harness and current GitHub issues. The operator authorizes
continued implementation, tests, parallel agents and radio work until they return.
Keep Markdown requirements/tests → synchronized SysML → independent review → code
→ ordinary gates → live acceptance. Do not close partial issues or bypass red checks.

Published integration: `74146d89b`, all thirteen selected gate groups green.
Deployed source: `582e08595`, nine selected groups green; executable SHA256
`b96c6f5cc635b58408bcb0c142367a813666474829c7a8a8fc69994dd3c5013e`.
Full results came from the previous PC. HB9BLA has Rust 1.99/MSVC, Python 3.12,
Node 24, Playwright/Chromium and verified hooks; compiler/linker/browser smokes pass.

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

## Continue in this order

1. Verify actual latest-period rows, signed DT and selectable sorting in the deployed
   browser, including narrow/enlarged text. Previous-PC Computer Use stopped before
   its Chrome refresh. Keep the user's **0–3000 Hz, existing 2.93 Hz/bin source**.
2. **#10 grey waterfall rows:** reviewed requirements/model-only commit `083ece294`
   (`cr10/detailed-continuity`) has **no implementation**. Apply that scoped commit
   onto a fresh current-main branch. Implement the bounded eight-row history,
   eviction watermark and catch-up policy; review/gate and observe two healthy peers
   for at least sixty seconds. Requirements already passed meaning/Pilot review.
3. **#7 decoder:** reviewed optional Deep branch `cr7/deep-ft8`, `8bd8e5b174`,
   remains unmerged: 18/21 reference messages versus baseline16, zero extras in that
   comparison. Two complete-frame misses remain; one partial-start message is outside
   contract. Do not loosen CRC/confidence gates. Read
   `D:\Github\wsjtx-rust-recordings\handoff\deep-ft8-8bd8e5b174\CONTINUE.md`.
4. **#18 samples:** eight WAVs are verified. Portable-helper admission still needs
   absolute/escaping filename refusal and correction of its FT8 source/CMake
   provenance sentence. Preserve its reviewed known-answer data; issue remains open.
5. Use the transferred operating inventory/eighteen flows to specify mode/band/CAT,
   Monitor/Stop/re-decode, then transmit/QSO/logging in existing issues. The current
   decoder-mode selector does not retune the radio. MCP reuses the same station engine.

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

Harness pin stays `1c6ffbb3`; source V2 `a9950ab9` early-failure improvement still
needs separate project adoption/trial. Skills: `D:\Github\agent-skills`, thirty valid
skills registered without replacing user state. Never install Fortran locally.
