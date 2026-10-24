# WSTX Rust Functional Specification Document

- Status: Initial draft for discussion
- Created: 2026-10-24
- Working name: WSTX Rust
- Repository: https://github.com/SensorsIot/wsjtx-rust
- Upstream baseline: WSJTX/wsjtx, commit `967c85a6119110788b0df3782cf796485b2cee14`

## 1. Purpose

Define the intended behavior and acceptance criteria for a Rust port of the complete WSJT-X repository. The port must preserve on-air interoperability and the workflows needed for weak-signal amateur-radio communication.

This is a starting specification, not a claim of implemented functionality. Confirmed decisions are listed separately from proposed requirements and open questions. Detailed parity requirements will be derived from the pinned upstream source, documentation, and reference runs.

## 2. Confirmed project decisions

- The project will port the whole upstream project to Rust.
- The `original` branch preserves the imported upstream source and history as a reference.
- The `master` branch is the development branch for the Rust port.
- Project documentation is stored in `docs/`.
- The upstream project is licensed under GPLv3. The port must meet applicable license and attribution requirements when distributed.

The upstream application files have been removed from the current `master` tree to establish a clean basis for the Rust project. The imported implementation remains on `original` and in Git history. The Rust workspace has not yet been created.

## 3. Scope

The intended end state covers the functionality of WSJT-X, MAP65, QMAP, and the supporting tools shipped in the upstream repository. Delivery can be incremental; full parity is the final target rather than the first release milestone.

### 3.1 Modes and protocols

The initial mode inventory includes FST4, FST4W, FT4, FT8, JT4, JT9, JT65, MSK144, Q65, WSPR, and Echo. Exact variants, submodes, timing options, message types, and special operating modes must be inventoried against the baseline before implementation is declared complete.

### 3.2 Application capabilities

- Receive and transmit audio processing and digital signal processing.
- Encoding, decoding, synchronization, and protocol message handling.
- Station configuration, radio control, and transmit/receive sequencing.
- Spectrum and waterfall displays, decoded-message views, and operator controls.
- QSO workflows, logging, reporting, and external application integration.
- EME operation, Doppler compensation, and wideband workflows represented by MAP65 and QMAP.
- Supporting command-line tools, data files, documentation, and packaging needed to replace the upstream distribution.

### 3.3 Language boundary

Application logic and protocol implementations are intended to be written in Rust. Whether native operating-system interfaces, device drivers, or external libraries may be used through bindings remains an open decision. Retaining the existing Fortran or C++ implementation is not the final implementation goal.

## 4. Proposed functional requirements

The following requirements are proposed for refinement during the upstream inventory.

| ID | Area | Required behavior |
| --- | --- | --- |
| FR-001 | Station setup | Configure and persist station identity, locator, devices, radio settings, and operating preferences. Validate values and explain invalid input. |
| FR-002 | Audio | Select supported input and output devices; capture receive audio and play generated transmit audio with the timing and sample handling required by each mode. |
| FR-003 | Receive processing | Process live audio and supported saved recordings; expose mode-appropriate filtering, synchronization, decoding options, and results. |
| FR-004 | Decoding | Decode the baseline mode and message variants, reporting available callsigns, locators, signal measurements, timing, and frequency information. |
| FR-005 | Encoding | Produce protocol-compatible messages, channel symbols, and waveforms for supported transmit modes and variants. |
| FR-006 | Time and sequencing | Schedule receive and transmit periods against UTC and apply each mode's timing rules. Surface clock or device problems that prevent reliable operation. |
| FR-007 | QSO operation | Support the baseline workflows for choosing a decoded station, preparing messages, progressing an exchange, and completing or aborting a contact. |
| FR-008 | Transmit control | Provide clear transmit state and an immediate halt action; handle PTT, radio errors, and device loss without leaving transmit active unintentionally. |
| FR-009 | Radio control | Support baseline radio-control capabilities, including frequency, mode, PTT, split operation, and supported device interfaces. The hardware support matrix is to be inventoried. |
| FR-010 | Displays | Provide spectrum, waterfall, decode, frequency, and operating-state views sufficient to carry out the baseline workflows. Pixel-identical UI reproduction is not yet a requirement. |
| FR-011 | Logging | Record completed contacts and support the baseline log formats, import/export paths, and duplicate or prior-contact indications where applicable. |
| FR-012 | Integrations | Preserve required external protocols and message formats, including baseline UDP integrations and reception-reporting workflows. |
| FR-013 | EME | Provide baseline astronomical information, Doppler handling, and Echo measurement workflows applicable to each application. |
| FR-014 | Wideband reception | Replace MAP65 and QMAP capabilities, including supported wideband input, band maps, polarization processing where applicable, and coordination with the narrowband application. |
| FR-015 | Utilities | Inventory and replace the user-facing upstream utilities and their documented inputs, outputs, and invocation behavior. |
| FR-016 | Settings and migration | Persist Rust application settings reliably. Define compatibility and migration behavior for existing WSJT-X profiles before a user migration release. |
| FR-017 | Help and notices | Provide operating guidance, version information, relevant attribution, license access, and a clear indication that this is an independent port. |

## 5. Proposed quality and compatibility requirements

- **On-air compatibility:** Preserve the protocol definitions and interoperability of the selected upstream baseline. A language rewrite must not silently change message encoding or waveform conventions.
- **Decoder quality:** Measure decoding success, false positives, sensitivity, and runtime against reference recordings and controlled signals. Numeric tolerances and acceptance thresholds must be agreed per mode.
- **Timing:** Meet each mode's receive and transmit deadlines on a documented reference machine. Hardware and performance budgets remain to be selected.
- **Platforms:** Windows, Linux, and macOS are the proposed target platforms, following upstream's platform scope. Supported versions and architectures remain open.
- **Reliability:** Recover from device and connection errors with understandable status information; preserve settings and logs across ordinary restarts.
- **Maintainability:** Keep protocol and signal-processing logic testable independently of the graphical interface and physical radio hardware.
- **Licensing:** Choose dependencies compatible with distribution of the port under GPLv3 and retain applicable third-party notices.

## 6. Acceptance and validation approach

1. Build a traceability inventory linking upstream applications, modes, workflows, utilities, and integrations to specification requirements and Rust components.
2. Pin the reference implementation to the baseline commit and record its build configuration and relevant runtime settings.
3. Establish reference vectors for message packing, error-correction coding, symbol generation, and waveforms. Require exact results where the protocol defines discrete values; define justified tolerances for floating-point processing.
4. Compare decoders on the same recordings and controlled signal conditions, including weak signals, overlapping signals, timing offsets, and frequency offsets.
5. Test transmit and receive interoperability with the reference implementation, initially using recorded audio or controlled loopback setups.
6. Validate operator workflows, device behavior, file formats, and integrations using documented scenarios.
7. Run the required platform checks and record any unsupported capability explicitly before declaring a release ready.

Full-project completion requires every inventory item to be implemented and accepted, or explicitly excluded through a documented scope decision. A successful FT8 demonstration alone does not establish full parity.

## 7. Proposed delivery milestones

| Milestone | Deliverable | Exit evidence |
| --- | --- | --- |
| M0: Baseline and specification | Preserve `original`; inventory upstream features and licensing; establish the Rust development structure. | Traceability inventory, agreed initial scope, and a reproducible build skeleton. |
| M1: Protocol foundation | Implement shared message and signal primitives; select a first mode after the inventory. | Reference-vector comparisons and an offline encode/decode demonstration. |
| M2: First usable operating path | Connect audio, sequencing, basic operator controls, and the initial radio-control path. | A complete validated operating scenario for the selected mode. |
| M3: WSJT-X parity | Implement the remaining narrowband modes, operating workflows, logging, and integrations. | Requirement coverage and per-mode compatibility results. |
| M4: Full repository parity | Implement MAP65, QMAP, remaining utilities, and supporting distribution assets. | Completed upstream inventory coverage and end-to-end validation. |
| M5: Release preparation | Finalize branding, notices, documentation, migration, and platform packaging. | Reproducible packages and documented acceptance results. |

No delivery dates or effort estimates have been agreed.

## 8. Licensing, attribution, and branding

- A distributed port derived from the upstream implementation must comply with GPLv3, including retaining relevant notices, marking modifications and their dates, and providing the complete corresponding source and necessary build files for distributed binaries.
- Translation into Rust does not itself remove the upstream copyright or license obligations.
- Bundled components and assets may have separate terms. Record their provenance and applicable notices as they are reused or translated; the initial license check was not a full dependency audit.
- The upstream trademark policy covers its names and program icons separately from the software license. Select distinct release branding consistent with that policy.
- `WSTX Rust` is the requested working title for this document; it has not been cleared as a product name.
- Private development does not by itself require publishing the repository.

## 9. Open decisions

1. What is the final public product name?
2. Should the Rust application suite remain separate executables or share one application shell?
3. Which mode and user workflow should form the first usable milestone?
4. Which GUI, audio, radio-control, and DSP libraries should be selected?
5. What native-library bindings are permitted within the all-Rust goal?
6. Which operating-system versions, CPU architectures, and radio devices are required initially?
7. What quantitative decoder, timing, and resource targets define acceptable parity?
8. How much compatibility with existing settings, command-line interfaces, and UI layout is required?
9. Should future upstream fixes be incorporated continuously or through explicit baseline updates?

## 10. References

- [Upstream source at the imported baseline](https://github.com/WSJTX/wsjtx/tree/967c85a6119110788b0df3782cf796485b2cee14)
- [Upstream program and mode overview](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/README.md)
- [Upstream GPLv3 license](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/COPYING)
- [Upstream trademark policy](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/TRADEMARK.md)
