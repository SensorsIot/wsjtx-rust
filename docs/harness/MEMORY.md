# Container handoff — 25 October 2026

## Subsequent decision: continue on the Windows PC

The operator chose to continue development here before moving to the container. This
Windows checkout is again the active supervisor checkout; coordinate ownership before
starting any container writer. The transfer instructions below remain available for
the later move.

Current continuation records are in SensorsIot/harness#6 (parallel issue workspaces)
and the project's issues. The operator explicitly accepted #14's four-role physical
architecture. GitHub blocking relationships now record integration/acceptance order;
approved isolated work may overlap once its shared contracts are settled. The first
hardware end-to-end target is an IC-7300 on another PC; FSD §4.5 and #8 own the details.
Transport and browser placement are not yet confirmed. Use current issue checkpoints
and the pinned parallel-work instructions rather than treating the original transfer
snapshot below as today's readiness verdict.

This is a transfer checkpoint requested by the operator, not a second backlog or FSD.
Read `AGENTS.md`, the harness reference index and the latest GitHub issue checkpoints.
The operator authorized continued development toward the complete application and
explicitly requested pushing this workspace, including agent instructions and memory.
The original transfer would have relinquished this session's write ownership; the
subsequent decision above keeps development on this PC for now.

## Get the repositories and skills

Authenticate privately to GitHub first: the product repository is public, but access to
the private harness and shared agent configuration is required. Never commit credentials.

```sh
git clone --branch master --recurse-submodules https://github.com/SensorsIot/wsjtx-rust.git
cd wsjtx-rust
python3 harness/core/tools/install_hooks.py
(cd harness && python3 core/tools/install_hooks.py)
```

The shared development skills repository is **https://github.com/SensorsIot/claude**,
whose `skills/`, `commands/` and `agents/` directories supply the user-level tools.
For a new Claude container with no existing configuration:

```sh
git clone https://github.com/SensorsIot/claude.git "$HOME/.claude"
```

If that directory already exists, inspect its origin and changes before updating it;
do not overwrite container configuration. Read its README for installation. For another
agent runtime, register the relevant `skills/*/SKILL.md` using that runtime's supported
skill discovery mechanism; cloning into `.claude` alone does not install Codex skills.
Use the project's pinned `harness/`, not a possibly older user-level harness skill.
`SensorsIot/Skills` is a separate legal-products library, not this development setup.
The Windows skills checkout has unrelated local changes; they are not part of this
project transfer. No authentication databases or raw session histories are copied.

## Last verified state

- Product implementation: `df4ed6fee8387a85377156fa764f996afaaa05bf`.
  Later commit `5278916fab131c91706db81343f162b51c440955` adopts reporting/checkpoints.
  The transfer commit adds this memory and preserves existing viewer preferences.
- Harness pin: `d53adffc8cb301b10a0af39cc9f2c1aeaccd0ecd`, branch `V2`, published.
  Its reporting improvement is complete in SensorsIot/harness issue #5.
- On the Windows PC, the complete gate passed on `5278916`: formatting/check/Clippy,
  14 browser/protocol tests, 28 model/tool tests and 6 Rust tests; no skips.
  Local evidence: `~/.cache/harness/wsjtx-rust/runs-rollout6-5278916fa.jsonl`.
  These are historical results, not proof that the new container passes.
- CR #5 implements persistent station profiles, independent server instances, strict
  bounded configuration, atomic revision saves and browser profile management.
  Two independent review findings were fixed and regression-tested. Issue #5 remains
  open for acceptance and final FSD/model reconciliation before closure.
- A Windows preview was installed and started with four independent profiles at
  `http://127.0.0.1:8081` through `:8084`. The operator saw Station 1 connected.
  Installation: `%LOCALAPPDATA%/WstxRust/preview/df4ed6fee`.
  Runtime state is PC-local; this transfer does not recreate or stop it.
- No working decoder, audio input, waterfall, CAT/PTT, transmit path or MCP exists yet.
  The current browser mostly shows connection status and profile settings.

## Continue here

First verify the clone, private submodule and tool availability. Rust 1.99.0 is pinned;
tests also need Node 24, npm dependencies, Playwright Chromium and Python 3.12.
Read `docs/harness/Project-Specifics.md` before running the gate. Existing acceptance
and profile/security tests include Windows-specific facilities; SysML's pinned Java
bootstrap also needs platform assessment. A Linux container has not been validated.
Preserve checks and coverage; establish the supported container execution arrangement
through the harness process before changing validation placement. Do not bypass hooks,
fabricate Windows results or automatically duplicate builds on GitHub Actions.

Then finish #5's acceptance/reconciliation and prepare **#6 — recorded audio input,
spectrum and waterfall**, the operator's next product priority. The display must work
with actual recordings. Use **one browser window per station**, waterfall above the
management/controls area, with a mouse-draggable horizontal divider. Define exact input
formats, resource limits, error states, fixtures and measurable display/link criteria
before implementing. Offline FT4/FT8 decoding follows in #7; remaining roadmap is #8–#13.
Issue #14's architecture/operator view acceptance is still open; publication is not
acceptance. Four servers are a test workload, not a product limit.

## Decisions to preserve

- One authoritative functional document: `docs/WSTX Rust FSD.md`, with subchapters.
  Product requirements/tests go into Markdown first, then synchronized SysML v2;
  compare meanings independently, implement from the reconciled model, and verify
  against the original Markdown expectations. Reconcile all clauses/tests BEFORE
  closing the issue. Correct SysML authoring rules when mismatches reveal a method gap.
- Harness instructions remain Markdown. General, Rust and project-specific layers
  are separate. GitHub issues hold approvals, reviews and execution evidence.
- The supervisor prepares/reviews/pushes; a CR agent implements; a separate reviewer
  independently checks it. Fresh reviewer context is the chosen current authority
  arrangement; an additional enforcement service remains only a proposal.
- Physical architecture: user, browser/viewer, station controller, radio. Audio and
  CAT are separate interfaces. Replace only the Hamlib functionality actually needed.
  No viewer tricks, fabricated nodes or PNG substitutes for a sound SysML model.
- Windows is the first release. Mac/Linux, parallel CPU work and measured acceleration
  remain goals; microcontrollers are secondary. Thin-link target is 32 kbit/s.
- Extract behavior from the experimental WSJT-X baseline; do not copy upstream code.
  Read licensing/provenance in README/FSD. Never push the `upstream` remote.
- Multiple independent saved station configurations, with no four-instance ceiling.
  Optional direct FlexRadio access is phase two (#13). MCP automation is #12 and
  must use the same station services as the browser.
- Local execution is selected. GitHub Actions is an explicitly selected manual
  alternative, not a duplicate automatic build. A container move is not evidence
  that Windows acceptance checks have passed there.

Project issues: https://github.com/SensorsIot/wsjtx-rust/issues.
Always pass `--repo SensorsIot/wsjtx-rust` to `gh` because the upstream remote can
otherwise cause it to select WSJTX/wsjtx. Review the preserved viewer preferences:
one entry references the old `PhysicalArchitecture.sysml`; it is historical UI state,
not a missing model that should be recreated as a workaround.
