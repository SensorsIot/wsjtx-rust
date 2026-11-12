package WstxRequirementsProfile {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    requirement 'CL-005-01' {
        doc /* A selected profile owns one process/listener; N is variable and storage, process and browser collections MUST NOT assume four entries. Four concurrent servers are sufficient for CR #5 acceptance; the implementation has no four-instance ceiling. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_01_to_FR_022 from 'CL-005-01' to 'FR-022';
    requirement 'CL-005-04' {
        doc /* Ownership, invalid storage, occupied endpoints and unavailable startup resources MUST fail explicitly without replacing saved configuration or disrupting a running instance. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_04_to_FR_016 from 'CL-005-04' to 'FR-016';
    dependency CL_005_04_to_FR_021 from 'CL-005-04' to 'FR-021';
    dependency CL_005_04_to_FR_022 from 'CL-005-04' to 'FR-022';
    requirement 'CL-005-05' {
        doc /* Standard audio with optional CAT/PTT remains the default. Audio and control selections MUST persist independently without claiming hardware availability. A schema-1 document naming native_flex stays refused; a native profile is a separate schema-2 document chosen at profile creation (FR-023, WstxProfiles::NativeProfileDocument). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_05_to_FR_001 from 'CL-005-05' to 'FR-001';
    dependency CL_005_05_to_FR_022 from 'CL-005-05' to 'FR-022';
    requirement 'CL-006-01' {
        doc /* Import only the bounded WAV capability below; preserve original bytes and expose immutable, explicitly timed samples without a codec or implicit resampler. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_01_to_FR_003 from 'CL-006-01' to 'FR-003';
    dependency CL_006_01_to_FR_018 from 'CL-006-01' to 'FR-018';
    verification 'TC-022-002' {
        doc /* #### TC-022-002 — Persistence and independent restart

             **Promises:** FR-001, FR-016, FR-022; CL-005-02, CL-005-04, CL-005-05.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, disposable storage,
             N real processes/windows. No full OS reboot is required or claimed by this case.

             **Setup partition:** Browser saves, recovery and restart observations use the
             common operational HTTPS/grant fixture; trusted plaintext loopback HTTP/startup
             compatibility remains independently mandatory, including the complete validation,
             error/storage/file invariants and exact8192 response-budget fixture. An ordinary
             unchanged-bootstrap restart retains unrevoked grants, without enrollment replay.

             **Steps:** Create an additional profile with `--create-profile`, independently check
             all creation defaults and UUID v4, and verify creation exits without listening. Save
             different editable values through each table profile's browser, record acknowledged
             revisions/UUIDs, stop all processes, clear inherited WSTX variables and restart using
             only the same paths plus explicit required TLS/token inputs. Reopen/refresh windows.
             Stop/restart only profile 1 again; then kill it after an acknowledged save and restart.

             **Oracle/outcome:** Saved fields, fixed endpoints, profile UUIDs and revisions exactly
             match the independent input/edit table; boot IDs change. Other profiles remain unchanged.
             A stale lock marker does not block restart and an orphan temporary file is never loaded.
             The fresh-process restart is evidence for process-independent storage; actual OS reboot
             is unexecuted unless separately reported from a disposable Windows VM.

             **Recovery/error variants:** Preserve independent byte hashes of all profile files.
             With the target stopped, test missing file, truncated JSON, malformed UTF-8, duplicate/
             unknown/missing fields, invalid UUID, schema 0/2, port 0/65536 and a 16,385-byte file;
             an otherwise valid 16,384-byte file padded with whitespace is accepted. Also try
             a schema-1 document naming `native_flex` and require `unsupported_connection_type`, without an attempted radio
             connection or a change to the standard profile's stored settings.
             Each invalid launch fails nonzero with the defined category and no listener or file rewrite;
             others remain usable. Restore the original bytes and restart successfully. During a
             save inject a deterministic denied-write/atomic-replace failure in disposable storage:
             no acknowledgement, no revision advance, previous complete JSON and current settings
             remain authoritative. At crash-before/after-replacement fault points require either
             complete old or complete new JSON, never a partial file; a lost response is reconciled
             by GET without replay. After a lost save response, ordinary Refresh, an announced GET or
             reconnect MUST NOT permit a second save: Save remains disabled until an explicit reload
             successfully validates the current authoritative profile. A failed explicit reload keeps
             that guard; a successful one recovers the committed revision without a second PUT.
             Test a relative profile argument from another working directory,
             a directory alias, absent parent on creation, existing empty/nonempty creation target,
             unknown/duplicate CLI flags and forbidden WSTX_BIND/WSTX_ORIGIN overrides. No fallback
             or mutation is permitted. This does not certify power-loss durability or WSJT-X migration.
             The cross-field response-budget fixture remains plaintext numeric loopback with
             an independently long saved Origin, not a protected browser/TLS/DNS/grant fixture.
             For the cross-field response budget, independently build the maximum-encoded-settings
             vector in 12.5. With the selected origin sized so its complete representation is exactly
             8,192 UTF-8 bytes, startup and GET succeed; save from revision 9,007,199,254,740,990 to
             9,007,199,254,740,991 and require a successful response of exactly 8,192 bytes. Increase
             that origin by one unescaped ASCII byte, then separately use a 9,000-character hostname:
             both launches fail `invalid_profile` before readiness without changing stored bytes.
             Use the numeric loopback address to transport the fixture requests and the saved origin
             as the exact Origin header; no external DNS or service is contacted. Other instances
             remain usable. These expectations come from the independent byte calculation, not the
             candidate's admission helper. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-02';
            verify 'CL-005-04';
            verify 'CL-005-05';
            verify 'FR-001';
            verify 'FR-016';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
    }
    verification 'TC-022-003' {
        doc /* #### TC-022-003 — Stop isolation and collision refusal

             **Promises:** FR-021, FR-022; CL-005-03, CL-005-04.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, N real server/browser
             instances, OS port reservations, ownership aliases/copies and disposable resource fixtures.

             **Setup partition:** Operational windows use the common four-process HTTPS/
             grant fixture; retain separate plaintext launch/configuration variants. Each
             negative launch has otherwise valid transport-specific TLS/token inputs, so the
             intended single fault is not replaced by a missing prerequisite or scheme mismatch.

             **Steps:** Stop profile 1 and query the other N-1 before, during and after its restart.
             While the original is running attempt: the same profile path, an alias to that directory,
             a copied directory retaining its UUID, and a new UUID/profile requesting an occupied
             port. For separate stopped copies test denied directory access, missing/unreadable TLS
             certificate/key, incomplete TLS pair, absent/invalid token and insecure remote binding.
             Test saved-origin port mismatch separately from a runtime scheme mismatch; the 4.2
             table supplies their distinct expected categories.
             Use a controlled startup resource failure for any exhaustion branch; never exhaust the
             operator PC. After failed launch remove the failing condition and launch successfully.

             **Oracle/outcome:** Only the stopped window becomes stale. N-1 Refresh requests continue
             to match their table identities within two seconds. Restart returns profile 1's UUID and
             saved revision with a fresh boot ID. Every conflicting launch fails within the ten-second
             fixture deadline, nonzero, with exactly the category mapped to its single injected
             fault by 4.2's startup-error table; no readiness, browser attachment, settings rewrite
             or existing-session interruption occurs. Pre/post byte hashes of saved files agree.
             Killing a process releases its ownership claim; a stale marker alone does not own it.
             A copied UUID is rejected until the owning process exits, irrespective of directory name.

             **Automation coverage:** Existing companions retain delivered profile launch,
             fault and lifecycle-isolation subsets. The operational HTTPS/grant browser
             fixture conversion and complete transport-partition companions remain pending;
             the expanded case is partial, with every existing launch/error oracle retained. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-03';
            verify 'CL-005-04';
            verify 'FR-021';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
    }
    verification 'TC-018-001' {
        doc /* TC-018-001
             CL-006-01, CL-006-02
             Construct byte-level PCM WAVs with 1, 2048, 4096, 4097 and 1,440,000 frames, endpoint samples -32768,-1,0,1,32767 and legal ancillary/padding chunks. Import, inspect blocks/metadata, replay twice and restart. Use the pinned actual recordings from chapter13 after retaining their license/provenance manifest; the verified22 inputs all fit the selected PCM capability.
             Provenance sweep (issue70, tests/recording-fixtures.test.cjs, no server): every one of the 22 FT8 and 3 FT4 original recordings in WSTX_SAMPLE_DIR has the sha256 of its manifest entry, and its hand-parsed RIFF/fmt header is PCM, 1 channel, 16 bit, 12000 Hz with a data size within the import cap; the enumeration equals the two manifests (25 files). Import (tests/recording.test.cjs): the first .wav entry of each manifest, one FT8 and one FT4 original, imports with rate_hz 12000, file_bytes equal to its length and stored bytes unchanged, and its replay paints waterfall rows.
             Hand-authored RIFF byte offsets/counts and exact signed-value/32768 mapping match; concatenated blocks equal input samples, <=4096 per block, contiguous offsets and one EOS; original bytes unchanged. Source UUID survives restart and repeats; job IDs differ, generations advance within a boot and reset to0 on restart, recording UTC remains null and no device opens. Analytical spectra repeat within 0.5 dB quantization plus 0.05 dB numerical tolerance. The actual recording proves non-synthetic input; it is not the calibration oracle. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
        }
        attribute executable : String = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-018-002' {
        doc /* TC-018-002
             CL-006-01, CL-006-02, CL-006-04
             Table-mutate each required WAV field/chunk, zero data, odd data, duplicate fmt/data, RIFF mismatch/overflow, truncation at each header/data boundary, rate/channel/format changes, 65 chunks, frame count max+1 and file cap+1; create legal exactly-at-cap ancillary data. Exercise slow/aborted/timed-out upload, cancel before/after validation commit and storage write/flush/manifest/cleanup failures, including restart at commit boundaries.
             Hand-specified errors follow 12.6; unsupported capability differs from malformed structure, exact limits accepted. Before manifest commit old bytes/ID remain; after it new bytes/ID remain even with lost response. No partial source becomes replayable, no unbounded pending file remains; startup cleanup keeps committed data and reports failure explicitly. Other station/profile/status remains available. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    dependency CL_005_01_verified_by_TC_022_001 from 'CL-005-01' to 'TC-022-001';
    dependency CL_005_04_verified_by_TC_022_002 from 'CL-005-04' to 'TC-022-002';
    dependency CL_005_04_verified_by_TC_022_003 from 'CL-005-04' to 'TC-022-003';
    dependency CL_005_04_verified_by_TC_022_004 from 'CL-005-04' to 'TC-022-004';
    dependency CL_005_05_verified_by_TC_022_001 from 'CL-005-05' to 'TC-022-001';
    dependency CL_005_05_verified_by_TC_022_002 from 'CL-005-05' to 'TC-022-002';
    dependency CL_006_01_verified_by_TC_018_001 from 'CL-006-01' to 'TC-018-001';
    dependency CL_006_01_verified_by_TC_018_002 from 'CL-006-01' to 'TC-018-002';
}
