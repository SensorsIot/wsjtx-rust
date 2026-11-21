# Project-specific harness bindings

**Layer:** HOW. **Scope:** this project's development environment and procedures.

The [general harness](https://github.com/SensorsIot/harness/tree/main/core) defines the
development process. The [Rust harness](https://github.com/SensorsIot/harness/tree/main/lang/rust)
defines reusable Rust rules and checks. This document binds those reusable instructions
to this repository's toolchain, paths, test prerequisites and selected execution mode.
Run the commands below from the repository root.

- [Machine](specifics/machine.md)
- [Windows build and packaging](specifics/windows-build-and-packaging.md): [Crates that need `unsafe`](specifics/windows-build-and-packaging.md#crates-that-need-unsafe), [Workspace](specifics/windows-build-and-packaging.md#workspace), [Test tools](specifics/windows-build-and-packaging.md#test-tools)
- [GitHub Actions](specifics/github-actions.md)
- [Local Windows development](specifics/local-windows-development.md): [Functional test selection](specifics/local-windows-development.md#functional-test-selection), [Model values read by tests](specifics/local-windows-development.md#model-values-read-by-tests), [Timing suites](specifics/local-windows-development.md#timing-suites), [Live page check](specifics/local-windows-development.md#live-page-check), [Parallel groups and shared resources](specifics/local-windows-development.md#parallel-groups-and-shared-resources), [Gate preview and manual runs](specifics/local-windows-development.md#gate-preview-and-manual-runs), [Inputs](specifics/local-windows-development.md#inputs)
- [Merge queue](specifics/merge-queue.md)
- [Same-machine development](specifics/same-machine-development.md)
- [Deployment authority](specifics/deployment-authority.md): [Standing deploy policy](specifics/deployment-authority.md#standing-deploy-policy), [Deploy pins](#deploy-pins), [Standing consent at 1 %](specifics/deployment-authority.md#standing-consent-at-1-), [Keying the radio](specifics/deployment-authority.md#keying-the-radio), [Simulator live tests](specifics/deployment-authority.md#simulator-live-tests), [QSO tests](specifics/deployment-authority.md#qso-tests), [Operator role and returns](specifics/deployment-authority.md#operator-role-and-returns), [Probe, tests and drill](specifics/deployment-authority.md#probe-tests-and-drill), [Rules not met](specifics/deployment-authority.md#rules-not-met)
- [References](specifics/references.md)
- [Product model maintenance](specifics/product-model-maintenance.md): [Exclusive functional authority](specifics/product-model-maintenance.md#exclusive-functional-authority)
- [Project model documentation contract](specifics/project-model-documentation-contract.md): [Required sequence for functional issues](specifics/project-model-documentation-contract.md#required-sequence-for-functional-issues), [Limits for experiments](specifics/project-model-documentation-contract.md#limits-for-experiments)

### Deploy pins

The SHA-256 of each mechanism file's blob at this commit, then its path, in the order
`station-update.ps1` reads them. A change to a mechanism file changes its pin in the same
CR (policy item 4). Suite `deploy-tooling`
(`test_deploy_pins.py`) recomputes every pin from git.

```text
ef106effe4e5b85a9c02a21dd8808d04281b239feecc5f54a5fe932eb2827c09  tools/deploy/station-update/station-update.ps1
b611766f68a987b450c15d38233c3c9eab5eb2eef58d9cc93db56fdce62fef07  tools/deploy/station-update/make_package.py
8579d535aa68596bd466b0fc400e4d8a8ca25c50e42291b3a09648ab01455509  tools/deploy/station-update/launcher.ps1
9d0524dfc1dc536f5d54e3a1b956b737f5b2b8a5a1ccfebaa896b97241c89dd2  tools/deploy/agent-client.ps1
506cc03746fb8bce42cd20bbafbe83715cf21bf502acb7ab558a5513a9b1f770  tools/deploy/station-probe.ps1
639f288c5b18f992e50f6d435a05dc47c890826a6de48b5b39407467eee4ee9f  tools/deploy/live-page-check.ps1
```
