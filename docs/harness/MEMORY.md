# Current project memory

Read `AGENTS.md`, the pinned harness, `Harness-Overview.md` and the exclusive functional
authority binding in `Project-Specifics.md` before continuing. Recheck Git, issue ownership
and runtime state; current contracts and issue evidence are authoritative for their scope.

The functional entry point is `docs/sysml/Requirements.sysml`. Its canonical-authority
marker together with absence of the active FSD selects SysML-only authority. Archived
functional Markdown is historical and is never maintained or read as an active oracle.
Do not infer execution or acceptance from model status declarations or a successful parser.

Application implementation, builds, installs, live tests and radio acceptance run on
HB9BLA (`192.168.0.37`, checkout `D:\Github\wsjtx-rust`), where the product and the
transceiver are; PC Andreas does SysML model and documentation work. See
[machines and roles](Project-Specifics.md#machines-and-roles).
Use the current GitHub issue checkpoint and private runtime receipt for actual deployed
source and work remaining, rather than a remembered version. Preserve existing credentials,
normal checks, independent review and one shared-file/integration writer.

`HB9BLA-HANDOFF.md` identifies runtime/data locations. The pinned `harness/` is the process
source; do not replace it with a user-level skill or update its pin without its review.

## Working state and rules (2026-11-06)

- **Lifecycle:** every open issue carries one `cr:*` label (preparing … accepted); read
  `python harness/core/tools/cr_state.py status` (with `HARNESS_REPO` set inline) before
  anything else. Slices of one issue (e.g. #24, #39, #44) are tracked per slice.
- **Merge queue:** CRs land only through `harness/core/tools/merge_queue.py` (submit /
  worker / status). Agents never `git push` in this project (the agent guard refuses it
  from CR worktrees); harness pin bumps are pushed by the coordinator from a worktree
  outside `.git/harness-parallel/worktrees`.
- **CR rules in force:** implement and test the function first (for real where it matters),
  and only when it is OK have the review, to find undesired behaviour (operator 2026-11-06);
  hand in each reviewed slice at once; agents run fast checks only (build, lint, changed tests,
  red-on-parent, SysML check) plus that function test, and leave the suites to the gate; merge main only after a conflict bounce, and the re-review reads only the
  resolution (`resolution_diff.py`); the reviewer posts its own verdict — an implementer
  never posts or relays one. Set `HARNESS_REPO` only inline on queue/lifecycle commands.
- **Radio:** before any agent Tx, `.harness/deploy/radio-preflight.ps1 -Holder <run>` must
  exit 0 (RF power, one live writer; `-Attended` for a short attended test;
  [handoff](HB9BLA-HANDOFF.md#preserve-the-runtime)).
- **Operator design rules** (recorded on the issues): clear client–server — the server
  pushes state over one WebSocket, HTTP only for commands and the reconnect snapshot, no
  client polling (#10); Band Activity colours only interesting stations (#50); CI-V
  always reads first and writes only on a difference (#44); Windows-only product for now.
- **Open work and decisions** for the next session: the newest comments on #10, #37,
  #39, #44, #50, #61 and the contest issue #63. Decided 2026-11-06: #22 drops radio identity;
  #40 is send-only UDP (all inbound removed, including UDP Halt; the operator may correct this reading); #56 accepts the current
  corpus result with a live comparison as evidence. #24 S5 waits for the SuperFox licence
  answer the operator requested by e-mail.
