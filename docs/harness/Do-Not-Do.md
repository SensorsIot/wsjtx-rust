# Do Not Do


**Status:** present-state. **Layer:** HOW. **Scope:** WSTX Rust bindings. **Nature:**
orientation (an index).

A distilled index of prohibitions. Each line points to the document that owns the full
rule. If a line ever conflicts with that document, the document wins.

## Architecture and data

- **MUST NOT** add a writer to a data store beyond its declared writers without an
  architecture change. → [WSTX Rust FSD](../WSTX%20Rust%20FSD.md)
- **MUST NOT** silently change architecture, a public contract or a fail-safe. → [WSTX Rust FSD](../WSTX%20Rust%20FSD.md)

## Security and data handling

- **MUST NOT** trust request, database, API, upload or translation data without
  validation. → [security](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/security.md)
- **MUST NOT** inline a secret, or print one, even masked. → [security](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/security.md)
- **MUST NOT** answer personal data from memory or echo it into logs, commits or issues. → [security](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/security.md)

## Process

- **MUST NOT** weaken or delete a test to make a CR pass, or change in a CR the checks
  that judge it. → [CR process](https://github.com/SensorsIot/harness/blob/V2/core/docs/CR-Process.md)
- **MUST NOT** push past a red gate unless the operator decides. → [CR process](https://github.com/SensorsIot/harness/blob/V2/core/docs/CR-Process.md), step 4
- **MUST NOT** close an issue from a commit message (`fixes #N`). → [CR process](https://github.com/SensorsIot/harness/blob/V2/core/docs/CR-Process.md), step 7
- **MUST NOT** claim a `Target` check ran. → [testing](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/testing.md)

## Rust

- **MUST NOT** use `unsafe` without listing the crate in these bindings. → [Rust standard](https://github.com/SensorsIot/harness/blob/V2/lang/rust/standard.md)
- **MUST NOT** `unwrap()` or `expect()` on external input (audio, files, network, arguments). → [Rust standard](https://github.com/SensorsIot/harness/blob/V2/lang/rust/standard.md)
- **MUST NOT** add a dependency without naming it and its purpose in the commit body. → [Rust standard](https://github.com/SensorsIot/harness/blob/V2/lang/rust/standard.md)
- **MUST NOT** translate or copy upstream WSJT-X code; behaviour is implemented independently from documentation and observed behaviour. → [FSD purpose](../WSTX%20Rust%20FSD.md#1-purpose)
