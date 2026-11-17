# Report: the profile part

2026-11-15. Built by a subagent beside transmit, radioControl and ranking; the operator was
not asked. `part_done.py profile` passes tests 1 to 5. What a rule decides is listed as
decided; what no rule decides is listed for the operator at the end and is not decided
here. Every figure is measured by a script (`measure.py` in the folder `profile` of the
session's scratchpad; it reads only).

## What was written

| File | Content |
|---|---|
| `backend/profile/Profile.sysml` | the profile part with four ports and one marker; 6 clauses, 6 rule elements, the enumeration `StartupOutcome`, 4 test cases: one station process for a profile, starting, saving, creating, the endpoint ids, the native connection |
| `backend/profile/Recordings.sysml` | 3 clauses, 4 rule elements, 2 test cases: the recording and its file, the import |
| `interfaces/internal/ProfileAccess.sysml` | the document and the limits (8 attribute definitions), 5 items, 3 enumerations, the port and its link |
| `interfaces/internal/RecordingTransfer.sysml` | the limits, 13 items, 2 enumerations and 2 ports with their links: the import (10 items, among them `Recording`), and receive's five elements `OpenRecording`, `RecordedBlock`, `RecordingUnreadable`, `RecordedSamples`, `RecordedSamplesLink`, kept as they were |

Together: 9 clauses, 6 test cases with 52 lettered conditions, 19 attribute definitions,
18 item definitions, 6 enumerations, 3 port definitions, 17 values.

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-005-01 | profile/Profile | Profile | Rewritten from `Store::open` and `lock`: one process for a profile, by two locks. Derives from FR-022. |
| CL-005-04 | profile/Profile | Profile | Keeps the start and the creation; the refusal of a save is CL-005-02's. Derives from FR-022 (was FR-016, FR-021, FR-022). |
| CL-005-02 | profile/Profile | Profile | Keeps the save and what outlasts a stop. Its browser half ("the browser MUST identify the selected profile and permit the bounded edits") is handed over. Was `partial`; every sentence written here has a test. Derives from FR-016 (was FR-001, FR-016, FR-019, FR-022). |
| CL-005-05 | profile/Profile | Profile | Keeps the devices and the control stored each by itself, and the new profile. Its native half is CL-013-08. Derives from FR-001. |
| CL-044-05 | profile/Profile | Profile | Rewritten from `validate_endpoints`, `endpoint_id`, `migrate` and `migrate_devices`. Derives from FR-001 (was FR-001, FR-002, FR-016). |
| **CL-013-08** | new | Profile | The profile's half of CL-013-03: the stored native intent. Derives from FR-001: the profile carries no FR-023 in `Station.sysml`. |
| **TC-023-007** | new | Profile | The two tests of `profile_tests.rs` that carry the tag TC-023-002. |
| TC-022-001, -002, -003 | profile/Profile | Profile | Rewritten from their tests; the browser steps and the answers of the routes are handed over. Were `partial`; each condition written here has a test. |
| CL-006-01 | profile/Recordings | Recordings | Keeps the form of the file, the bytes kept and the samples given. Derives from FR-018 (was FR-003, FR-018). |
| **CL-006-05** | new | Recordings | The import half of CL-006-02: a recording takes the place of the stored one only by a whole and valid import. |
| **CL-006-06** | new | Recordings | The import half of CL-006-04: one import at a time, every refusal with its reason. |
| TC-018-001, TC-018-002 | profile/Recordings | Recordings | Rewritten from their tests. TC-018-001 verifies CL-006-01 only (was also CL-006-02); TC-018-002 verifies CL-006-01, CL-006-05 and CL-006-06 (was CL-006-01, -02, -04). |
| CL-008-01 | profile/Profile | retired | Says what CL-005-05 says: the audio devices and the control stored each by itself, claiming no device. |
| TC-009-001 | profile/Profile | handed over: radioControl | Typed radio control (`server/tests/radio_control.rs`); nothing of it is shown at the profile. |
| TC-022-005 | profile/Profile | handed over: frontend, station link | The browser's status while a read of the profile is held. |
| TC-002-001 | profile/Profile | audio (arrived there) | Not touched. |

19 identities are accounted for in the ledger: 11 arrived, 4 new, 1 retired, 2 handed over,
1 arrived in audio.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Where the profile's own clauses stand | M2.1 gives `backend/profile/` the part's own file and `Recordings`; the ledger names `Profile.sysml` as the target of the six identities; M4.4 excludes nothing from a part's own file; a start, a creation and a lock are no exchange (M6.3 does not apply) | In `Profile.sysml`, package `WstxProfilePart`, with the part. Line 1 for the operator. |
| Each clause derives from one FR | Decided on the clock | Nine second FRs dropped. |
| CL-008-01 is retired | M1.4: every fact stands in one place; authoring "a second wording of the same rule is a defect" | Its promise is CL-005-05. |
| CL-006-05 and CL-006-06 are two clauses | M6.4: shown by different conditions and changing for different reasons (the storing of a recording; the admission of a command), as receive kept CL-006-02 and CL-006-04 apart | The next free numbers of the series. |
| The other functions' files in the folder are not described here | M4.1: a file one function reads or writes by itself is described with that function | `ProfileOwnership` says what the profile writes and that it leaves every other file. `pskr.json`, `udp.json`, `contacts.adi`, `cty.dat`, `audio-endpoint-names.json`, `receive-diagnostics.json` stay where they are described. |
| What crosses `contactStorage` | M4.1; M5.8: a connection carries no empty item | `ProfileFolder`: the place of the folder. The log keeps its files by itself. |
| What crosses `profileContext` | M5.3: the station service gives the functions the profile's values and is the gate for a change | `ProfileFolder`, `ProfileSnapshot`, `SaveProfile`, `SaveRefused`, `PresentEndpoints`. |
| The routes `GET` and `PUT /profile`, the recording routes, the events, the status codes | M4.7 | Not written; handed over. `HttpOutcome`, `HttpProfileGet`, `HttpProfilePut`, `HttpProfileRepresentation`, `HttpProfileError`, `PutDecision`, `GetDecision`, `HttpStatus`, `RecordingSnapshot`, `StartImportBody` leave the profile's files. |
| The checks of a save belong to the profile although they stand in `main.rs` | A model file follows the thing | `SaveSettings`; CL-005-02 names the module; 5 verdicts "difference in the code". |
| The import belongs to the profile although it stands in `recording.rs` | A model file follows the thing; operator on receive | CL-006-01, -05, -06 name the module; its other names have verdicts. |
| The check of profile and boot of a command | M5.3; handover row of receive | Not written; the station service's. |
| How the profile learns that receive is busy, and receive that an import runs | M5.3: state passes through the station service | `ReceiveBusy` and `RecordingStatus` on `RecordingTransfer`. |
| The device names at station start | M5.3; the list of endpoints is audio's | The station service gives `PresentEndpoints`; the rule of the change is the profile's (`EndpointIds`). |
| One document, not two | The code has one `Document` with an optional `native`; one fact, one place | `NativeProfileDocument` is gone; `ProfileDocument::native` is optional. |
| RIFF WAVE, the endpoint id, UUID, JSON | A followed source is referred to, not copied | Named once each; the product's checks and their order are written. |
| Limits kept as values | Values are sorted | 17 values. `readinessDeadlineSeconds` (10 s) is a value of a test and stands in TC-022-003; `normalCleanupMs` has neither code nor test and is dropped; `snapshotBytes` is the station link's. |
| Promises without a test | Decided on audio | None needed a line. |
| `Recording` keeps its name | Names are identities; `StationLink.sysml` imports it | It is now the stored recording as reported (`id`, `frames`, `file_bytes`), in the place of `RecordingView`. |

## Dropped as code or as history

- All 29 `dependency` lines and the 4 `satisfy` lines of the two old files, the dates, the
  issue numbers, "Oracle", "Automation coverage" and "review regression" in the old test
  cases.
- `ProfileLifecycle` (stopped, starting, running, saving, rejected): the states of the
  process; what is noticed outside is the outcome of a start and the answer to a save.
- `ImportEvent` and the transitions of `ImportLifecycle` as formal elements: no built part
  uses a state definition; the states are `ImportState`, and each state's sentences say
  what leaves it.
- The second reading of the document after the lock is taken, the threads, the 50 ms step
  that finds a time-out, the flag that a part is being taken ("worker"), the names of the
  temporary files, the text of the lines the station writes when it changes a device name.
- "The profile is validated before any request is accepted", "opens no browser", "reports
  no secret": no function exists that could do otherwise.
- The worst case of 2,018 bytes with an empty origin: a value of the test.
- `RecordingAvailability`, `SourceAvailability`: three cases that `StoredRecording` states
  in sentences.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| package `WstxProfiles` | `WstxProfilePart` (handover row of the top files) | `profile_tests.rs` (`WstxProfiles::StartupOutcome`), `tests/profiles.test.cjs` (`WstxProfiles::...`), header of `profile.rs` |
| package `WstxProfileRecordings` | `WstxRecordings` | none found in the code |
| `profileFileMaxBytes`, `profileHttpMaxBytes` (package level) | `WstxProfileAccess::ProfileLimits::...`, same names | `tests/profiles.test.cjs` `profileValue` |
| `WstxProfileAccess::maxRevision` | `ProfileLimits::maxRevision` | none found |
| `readinessDeadlineSeconds` | gone; 10 s in TC-022-003 | `tests/profiles.test.cjs` `readinessMs` |
| `HttpOutcome` | `SaveRefusal` (the profile's six); the others go to the station link | `tests/profiles.test.cjs` `outcomes('HttpOutcome')` |
| `ProfileRequest`, `ProfileOutcome` (empty) | `SaveProfile`, `ProfileSnapshot`, `SaveRefused`, `ProfileFolder`, `PresentEndpoints` | the log's marker text; `tools/sysml` tests name them |
| `NativeProfileDocument` | `ProfileDocument` with `native`; rules in `NativeProfile` | comment in `profile.rs` |
| actions `CreateProfile`, `LaunchSelectedProfile`, `SaveSelectedProfile`, `RecoverOrStopProfile` | attribute definitions `CreateProfile`, `OpenProfile`, `SaveSettings`, `ProfileOwnership` | none found |
| `ImportRecording`, `RecoverRecordedSource` (actions), `RecordedSource` (part) | `WavForm`, `ImportLifecycle`, `ImportAdmission`, `StoredRecording` | `tools/sysml` tests name `RecordedSource` |
| `RecordingMetadata`, `RecordingManifest`, `UploadChunk` | sentences of `StoredRecording`; `ImportChunk` | none found |
| `RecordingView`, `RecordingSnapshot` (attribute definitions) | `Recording`, `RecordingStatus` (items); the snapshot of the route is the station link's | none found |
| `ImportView` (attribute definition) | item, same features | none |
| `RecordingLimits::normalCleanupMs`, `snapshotBytes` | gone | none (`recordingLimit` reads six others, all kept) |
| port `ProfileAccess`: items `request`, `outcome` | `folder`, `saved`, `save`, `endpoints`, `refused` | `backend/log/Log.sysml` uses the port only |
| port `RecordingTransfer`: item `recording` | nine items | `Station.sysml` uses the link only |

Unchanged names that the code reads: `ProfileDocument::schema_version`, `revision`,
`connection_type`; `Settings::display_name`, `callsign`, `locator`; `Endpoint::'bind'`,
`origin`; `AudioSelection::input_device`, `output_device`; `StartupOutcome` and its nine
literals; `RecordingLimits::fileBytes`, `importMaxFrames`, `importMaxRiffChunks`, `rateHz`,
`rawChunkBytes`, `importCancelAckMs`.

## Negative statements

| Old statement | Result |
|---|---|
| "the number of profiles running at once MUST have no fixed limit" | positive: profiles run side by side, each in a process of its own; a profile shares no file, lock or state with another |
| "the target is never overwritten" | positive: "what exists is left as it is"; TC-022-002 (g) |
| "A launch never falls back to creation" | kept, short: "A start with --profile makes no profile"; the creation is the function that could |
| "The API edits no identity, endpoint or connection type" | positive: they "are the same after every save" |
| "A save never acknowledges a partial write, selects a path, activates a driver or merges silently" | the commit rule of `SaveSettings` says the first; the others dropped: no such function |
| "settings never assert device availability" | one sentence on `AudioSelection`: an entry names a device, it does not say the device is there |
| "A leftover temporary file is ignored and never promoted" | positive: "Only profile.json is read"; TC-022-002 (c), (i) |
| "No automatic backup selection, migration, autostart or device discovery; no guarantee against a hostile user or power failure" | dropped: no such function |
| "Radio serial, slice, DAX channel, stream ID, client handle and tuning are never persisted" | kept on `NativeIntent`: the Flex adapter knows them, and TC-023-007 (b), (e) show it |
| "A native profile names no audio device and no CAT control" | positive: its document has none, and a save with one is refused with the field |
| "It uses no codec and no resampler; another format is never coerced" | positive: another form is `unsupported_audio` |
| "no recording library, never client paths or file names" | positive: one recording or none; its files are named by its id |
| "Nothing claims a deletion, starts a replacement worker or reverts a committed recording" | positive: from the step that puts `current.json` in place the file is the stored recording, also when the import fails afterwards |
| "no recording is fabricated", "no durable cancelled job, synthetic job or cancellation marker" | dropped: no such function (the job is receive's) |
| "an unreadable manifest gives no authority to delete" | positive: while it cannot tell which recording is stored, the profile keeps every file named by a UUID |

## Settled from the code

- **Two locks.** One on `.profile.lock` in the folder, one on `<profile_id>.lock` in the
  account's local data. The old text had "exclusive ownership of the directory and of the
  UUID" without saying how; the top files' handover row said the lock was not in the model.
- **The order of a start's refusals**, and that `invalid_profile` has three places in it.
- **`audio_device_not_endpoint`** is a refusal of a save (the old model listed it as a
  conflict between `HttpOutcome` and CL-044-05).
- **A save's order:** the settings are judged before the profile and the revision are
  compared; `revision_exhausted` comes after `revision_conflict`.
- **A new profile has no `radio`.** A managed radio without radio settings gets them when
  the file is read (agc SLOW), and the file changes with the next save.
- **An import that ends by time is `failed`,** with `upload_timeout`, not `cancelled`; an
  import with a fault of the file is `failed` with that fault after its files are removed.
- **The idle time counts from the moment a part began,** not from its end.
- **A failure after the commit** leaves the new recording stored and the import `failed`.
- **A fault of the build wins over another form** in `WavForm`: the file is read to its end
  before `unsupported_audio` is given.
- **`storage_error` ends** when the files of an import have been removed, not only with a
  station start.
- **The cancellation of a reserved import** is `cancelled` at once, without `cancelling`.
- **The old `importMaxFrames` text "120 s at rateHz"** is right; the old `RecordingMetadata`
  bound "at most 1024 bytes" and the manifest's 256 are sizes of the reader, not written.

## What the comparison with the code found

| Finding | Result |
|---|---|
| The checks of a save and their order stand in `put_profile` of `main.rs`, with the decoding of the request | Work for the code. Five texts of `SaveRefusal` have the verdict "difference in the code"; the sixth, `storage_unavailable`, is shown once, with the import's. |
| The largest part (2048 bytes) and the announced length over `fileBytes` are checked in `recording_http.rs` | Work for the code. Two verdicts "difference in the code". |
| The import, its states and the stored recording stand in `recording.rs` beside receive's job | Work for the code. The names of that module that are receive's (5), audio's (5) and the station link's (1) have verdicts. |
| `MAX_RESPONSE` is private; `MAX_FILE`, `FILE_LIMIT` and `MAX_REVISION` are not found by name | Matched by reading. |
| The times of an import, the limits of `WavForm`, 64 and 256 bytes of the settings are numbers in the code, without a constant | Matched by reading. |
| `importCancelAckMs` has no constant in the code; `tests/recording.test.cjs` asserts it with the model's value | Kept as a promise; line 5 for the operator. |
| The tool keys a literal by its name | `ImportError::not_found` was matched to `Migration::NotFound`, and `cancelled` and `unsupported_audio` to texts of receive's errors; read: all three are texts of the import in `recording.rs` (`import_view`, `cancel_import`, `validate`). `storage_unavailable` and `wrong_profile` stand in two enumerations and are shown once; read: `put_profile` gives both for a save, `recording.rs` gives `storage_unavailable` for an import. |
| `StartupOutcome::ready` and `created` have no text in the code | Kept: every start has an outcome. Matched by reading (the process goes on, or ends with the exit code 0). |
| A refusal of the settings names its field without `settings.`; a refusal of the decoding and `audio_device_not_endpoint` name it with `settings.` | Work for the code; the wire form is the station link's. |

Test 4: 10 lines matched by the tool (8 literals, 2 environment variables), 94 with a
verdict: 48 matched by reading, 39 another part (18 radio control's, 5 receive's, 5 audio's, 5 the web adapter's, 6 others), 7 difference in the code, none inside.

## Edge cases and their homes

| Case | Home |
|---|---|
| missing, unreadable, oversize, malformed `profile.json`; a key twice, missing, unknown | `OpenProfile`, TC-022-002 (c), (d), TC-022-001 (b), TC-022-003 (e) |
| a file of exactly the largest size | TC-022-002 (d) |
| the revision at its end | `SaveSettings`, TC-022-002 (f) |
| two saves from one revision | `SaveSettings`, TC-022-001 (h) |
| a save that fails at each step; a process stopped before and after the commit | `SaveSettings`, TC-022-002 (h) |
| a temporary file left behind | `OpenProfile`, TC-022-002 (c), (i) |
| the same folder under another name; a copy of the folder | `ProfileOwnership`, TC-022-003 (b) |
| a lock file left by a process that ended | `ProfileOwnership`; shown by every restart of TC-022-002 (b) |
| the same `profile_id` under another account's data | TC-022-003 (d) |
| each value of `Settings` empty, at its longest and one beyond | TC-022-001 (d), (g), (i) |
| a device name that fits none or several present endpoints; no list | `EndpointIds`, TC-022-001 (k); without a list: the rule, no condition |
| a profile whose largest snapshot is exactly at and one over the limit | `OpenProfile`, TC-022-002 (j) |
| a native document with a null, an unknown key, a wrong address | `NativeProfile`, TC-023-007 (b) |
| a recording of 1 sample and of the most samples; a file at and over each limit | TC-018-001 (a), TC-018-002 (c), (d) |
| a file cut off at every byte | TC-018-002 (a) |
| an import that fails at each of its five steps, and after the commit | `ImportLifecycle`, TC-018-002 (f), (g) |
| a reservation, an idle import and a long import that run out of time | TC-018-002 (h) |
| a second part while one is taken; a part out of order; a part after the end | `ImportAdmission`, TC-018-002 (i), (m) |
| a cancellation in each state | `ImportLifecycle`, `ImportAdmission`; reserved and receiving in TC-018-002 (m), (i); validating and committing: the rule, no condition |
| files that cannot be removed | TC-018-002 (i), (j) |
| a folder with files and no `current.json`; each of the three files damaged or gone | `StoredRecording`, TC-018-002 (k), (n) |
| the station stops during an import | `ImportLifecycle`; shown by the station start of TC-018-002 (j) |
| an id for an import or a profile cannot be made | rare and harmless; not written |

## Not carried over

| What | Why |
|---|---|
| The browser steps of TC-022-001, -002, -003 (the form, Save, Reload, the lost reply, the window per station, 360 px) | handed over: frontend |
| TC-022-005 | handed over: frontend, station link |
| The web adapter's conditions of TC-022-003 (TLS pair, token, a bind that is not loopback, the certificate, the occupied port, the scheme of the origin) | handed over: web |
| The decoding conditions of TC-022-001 (not JSON, a number as text, a body of 8,193 bytes, another media type, `DELETE`) | handed over: station link |
| The route conditions of TC-018-002 and TC-018-003 in `tests/recording.test.cjs` (Origin, the cookie, media types, the status codes) | handed over: station link |
| `expected_authorization_corruption_blocks_profile_startup_without_rewriting_files` in `profile_tests.rs` | handed over: web (CL-022-02). Of the 7 tests of the file, 6 are bound. |
| The start without arguments ("environment mode": no profile, `WSTX_BIND`, `WSTX_ORIGIN`) | handed over: web, station |

## Size

Measured in characters.

| File | Old | New |
|---|---|---|
| `backend/profile/Profile.sysml` | 39,766 | 31,241 |
| `backend/profile/Recordings.sysml` | 22,584 | 19,847 |
| `interfaces/internal/ProfileAccess.sysml` | 10,326 | 11,285 |
| `interfaces/internal/RecordingTransfer.sysml` | 4,838 | 11,367 |
| Total | 77,514 | 73,740 |

The part is 5 % smaller than its old text. What left: the three test cases and the clause
that are not the profile's (5,515), the HTTP items and outcomes of `ProfileAccess` (2,142),
the five calculations about `PUT` and `GET` (4,022). What came: the items of the two
interfaces, which had three empty or one-line items for all of it (`RecordingTransfer.sysml`
more than doubled; 1,334 of its characters are receive's five elements and were there).

| Content | Characters |
|---|---|
| The 6 test cases, 52 lettered conditions | 20,718 |
| The 9 clauses | 3,795 |
| Definitions: rule elements, the document, items, enumerations, ports, the part | 47,408 |
| Imports | 1,819 |

## Checks

- `python docs/sysmlV2/_work/part_done.py profile`: all five tests pass: 19 identities, no
  finding in 4 files, no validator error in them, 10 names matched and 94 lines with a
  verdict, 6 test cases with their tests.
- `part_done.py receive` and `part_done.py log` still pass (both read one of the two
  interface files).
- `check.py` on the four files: no finding.
- Tests bound: 14 named tests (6 in `profile_tests.rs`, 7 in `recording_tests.rs`, 1 in
  `radio_setup_tests.rs`) and 3 whole files (`tests/profiles.test.cjs`,
  `tests/recording.test.cjs`, `tests/profile/recording-fixtures.test.cjs`).
- `git status`: `docs/sysmlV2/` is the only change.

## The functional description

`_descriptions/profile.md`, from the new files alone, 26,818 characters. It found six gaps.

| Gap | Settled how |
|---|---|
| A new profile has no radio settings, yet the text said a managed radio is read "with the RadioSettings of a profile that is created" | The two sentences now name the values `RadioSettings` gives. |
| When `ReceiveBusy` is first given | "at station start and" added. |
| Where the profile takes the current generation from | A marker on the port `RecordingTransfer`; line 3 for the operator. |
| How a function without a connection learns the place of the folder | A marker on the part; line 2 for the operator. |
| Which part ends a start with `endpoint_in_use` and the like | One sentence in `OpenProfile` names the web adapter and the station service; handed over. |
| What "a radio connection of radio control's catalogue" is | Handed over to radio control; named in text only until that part is built. |

## Markers

| Where | Marker | Says |
|---|---|---|
| `PersistedProfile` | `@NotStated` | how a function with a file in the folder and no connection to the profile learns the place of the folder |
| `RecordingTransfer` (port) | `@NotStated` | which function holds the generation that a reservation and a start of receive both raise |
| `ProfileOwnership`, `SaveSettings`, `CreateProfile`, `StoredRecording` | `@DiffersFromSource`, four | the lock; saving with a revision; a profile made by a command; a WAV file taken in before it is shown |
| `ProfileLimits::maxRevision`, `ProfileDocument`, `EndpointIds`, `WavForm` | `@FollowsSource`, four | RFC 7493; RFC 9562 and RFC 8259; the Windows Core Audio endpoint id; RIFF WAVE |

## Checked in WSJT-X (`D:\Github\wsjtx`)

| Question | WSJT-X does |
|---|---|
| How is a second instance kept out? | `main.cpp`: a `QLockFile` in the temporary folder, named by the application name, which holds the rig name of `--rig-name`; `tryLock`, and for a lock left behind a question whether to remove it. |
| Where do the functions keep their files? | Each opens its own file in the folder `Configuration::writeable_data_dir()` gives (`logbook/WorkedBefore.cpp`: `wsjtx_log.adi`; `logbook/AD1CCty.cpp`: `cty.dat`). The configuration gives the place; it does not read or write those files. |
| How does a WAV file come in? | `MainWindow::on_actionOpen_triggered`: a file dialog on any folder; refused while the decoder is busy; monitoring is switched off; the file is read and decoded at once. Nothing is copied or kept. |
| Is there a revision of the settings? | No: `MultiSettings` and `QSettings`; several configurations live in one settings file. |

## Work for the code, when the new tree goes to main

- The checks of a save move from `put_profile` (`main.rs`) to the profile; the route keeps
  the decoding.
- The import, the stored recording and `validate` move out of `recording.rs` to the
  profile; the two size checks of `recording_http.rs` with them.
- `MAX_RESPONSE` is private; the times of an import, the limits of `WavForm` and the sizes
  of the settings have no constant.
- The field of a refused save is named with and without `settings.`.
- The tests read from the old model by names that change: `WstxProfiles::StartupOutcome`,
  `WstxProfiles::profileFileMaxBytes`, `profileHttpMaxBytes`, `readinessDeadlineSeconds`
  (gone), `WstxProfileAccess::HttpOutcome` (the profile's six are `SaveRefusal`), and the
  defaults of `ProfileDocument`, `Settings`, `Endpoint`, `AudioSelection` (unchanged).
- The test tags: the two native tests of `profile_tests.rs` say TC-023-002 (TC-023-007);
  the import tests of `recording_tests.rs` say CL-006-02 and CL-006-04 (CL-006-05,
  CL-006-06); `absent_manifest_artifacts_...` says TC-018-003 (TC-018-002);
  `tests/recording.test.cjs` names TC-018-003 for conditions of TC-018-002.
- No test shows: a cancellation while the file is validated or committed; the names of
  the devices without a list of endpoints; `generation_exhausted` for a reservation.

## For the main session

### Handover rows (for `_work/handover.md`)

Rows "profile" that are taken up; each takes the place of the row of the same beginning.

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| profile | A `clock.json` left in a profile is ignored and left in place. **Taken up:** `WstxProfilePart::ProfileOwnership`: the profile writes its own files and leaves every other file of the folder as it is. The test stays the station link's (`clock_http_tests.rs` `no_clock_source_setting`). | CL-043-01, TC-092-004 | clock |
| profile | The lock on the profile directory. Not in the old model; the code takes it (`profile.rs`). **Taken up:** CL-005-01, `ProfileOwnership` (two locks: the folder's and the identity's), TC-022-003. | `profile.rs` | top files |
| profile | The settings and the recordings (RIFF WAVE PCM). **Taken up:** `WstxProfileAccess::ProfileDocument`, `WstxRecordings::WavForm`, `StoredRecording`. | old `Context.sysml`, `profile/Profile` | top files |
| profile | The package of the part's own file is `WstxProfilePart`. **Taken up.** | `Station.sysml` | top files |
| profile | The profile names the audio input and output by endpoint id (`settings.audio.input_device`, `output_device`); `audio-endpoint-names.json` lies in the profile's folder. Audio has no connection to the profile; the station service gives it the two endpoints (`AudioDevices`). **Taken up:** CL-044-05, `WstxProfilePart::EndpointIds`. The names file stays audio's (M4.1). | CL-008-01, CL-044-07 | audio |
| profile | The stored recording reaches receive as `RecordedBlock`s over `RecordedSamplesLink`. **Taken up:** CL-006-01 (`WavForm`, `StoredRecording`), CL-006-05 (`ImportLifecycle`), CL-006-06 (`ImportAdmission`), TC-018-001, TC-018-002. `RecordingTransfer.sysml` imports nothing of `ReceiveControl` any more; the import has `ImportState` and `ImportError` of its own. | CL-006-02, CL-006-04, TC-018-003, `recording.rs` 28 to 210, 3830 to 4077 | receive |
| profile | The logbook (`contacts.adi`) and the operator's country file (`cty.dat`) lie in the profile's folder; the log reads and writes them itself in the code. **Taken up:** `ProfileAccess` carries `ProfileFolder` on `contactStorage` and nothing else; the marker on `WstxLogPart::LogService` is answered by it. | `Logbook`, `ProfileCountryFile` | log |
| profile | The stored intent of a native profile. **Taken up:** CL-013-08, `WstxProfilePart::NativeProfile`, `WstxProfileAccess::NativeIntent`, TC-023-007 (the two tests of `profile_tests.rs`). The last step of the first TC-023-002 test in `native-flex.test.cjs` stays with TC-023-002. | CL-013-03, `NativeFlexWireSubset` (Profile), TC-023-002; `profile.rs` | flexAdapter |
| profile | `pskr.json` lies in the profile's folder. Spots has no connection to the profile. **Taken up as far as the profile goes:** the folder and its lock (`ProfileOwnership`); how spots learns the place of the folder is the marker on `PersistedProfile`. | `HearingFeed` | spots |
| profile | `udp.json` lies in the profile's folder and is written under the profile's lock. Udp has no connection to the profile. **Taken up as far as the profile goes:** the lock holds for the whole station process (`ProfileOwnership`); the place of the folder as for spots. | `UdpConfiguration` | udp |

New rows.

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| station | The station service takes `ProfileFolder` and `ProfileSnapshot` at station start and after every save, and gives each function what the document says. After an accepted save it ends a band or mode selection in progress with `state_conflict` and counts its operating revision on (`profile_changed`), gives receive the callsign (`set_my_call`), and has the authorization follow the control (`reconcile_control`; a failure there answers the save with `storage_unavailable` although the document is saved). It refuses a command of an import for another profile with `wrong_profile` and for another boot with `state_conflict` before it reaches the profile. | CL-005-02, `SaveSelectedProfile`; `main.rs` `put_profile`, `recording.rs` `reserve`, `profile_changed` | profile |
| station | The station service gives the profile `ReceiveBusy` (from receive: a job has not ended; a live job that ended has not let go, or a selection runs) and gives receive what `RecordingStatus` says (an import has not ended; `storage_error`), which receive's `Admission` needs. The generation is one count for receive's starts and the profile's reservations in the code (`admit_for`); which function holds it waits for the operator (marker on the port `RecordingTransfer`). | CL-006-04; `recording.rs` `admit_for` | profile |
| station | At station start, for a document with a device entry that is no endpoint id, the station service asks audio for its list and gives the profile `PresentEndpoints`; it writes one line for each entry that was changed or could not be ("migrated to endpoint", "not_found", "ambiguous", "device migration skipped (audio_unavailable)"). The start goes on in every case. | CL-044-05; `main.rs`, `radio_setup.rs` `migrate_devices` | profile |
| web | The start of the listener. `invalid_runtime_configuration`: one of `WSTX_TLS_CERT` and `WSTX_TLS_KEY` without the other; `WSTX_TOKEN` that is not 32 to 128 ASCII letters and digits; a bind that is not loopback without TLS, token and origin; TLS without token; token without TLS; a stored origin whose scheme is not the one of the listener. `resource_unavailable`: a certificate or key that cannot be read; a listener that cannot be opened. `endpoint_in_use`: the port is taken. The outcomes are literals of `WstxProfilePart::StartupOutcome`. The origin of the station is the stored origin, else scheme, address and port of the listener. The lines `WSTX profile <id> <name>`, `WSTX address`, `WSTX listening <origin>`. The conditions (b) last step, (c) and (e) of the old TC-022-003. | CL-005-04, `LaunchSelectedProfile`, TC-022-003; `main.rs` | profile |
| web | `authorization.json` and `.authorization-initialized.json` lie in the profile's folder and are written while the profile is held. A record that is expected (the marker file exists) and is missing or cannot be read ends the start with `resource_unavailable` and changes no file (`profile_tests.rs` `expected_authorization_corruption_blocks_profile_startup_without_rewriting_files`, CL-022-02). The MCP audit log is written into the folder the same way (`append_log_line`). | CL-022-02; `profile.rs` `load_authorization`, `read_authorization` | profile |
| web, station | A start without arguments runs a station without a profile ("environment mode": `WSTX_BIND`, `WSTX_ORIGIN`; `/profile` and the recording routes answer `not_found`). The profile part says nothing of it. Whether it stays a product function is to ask when web is built. | `LaunchSelectedProfile`; `main.rs` | profile |
| station link | `GET` and `PUT /profile`. Order of a `PUT`: Origin (403 `forbidden_origin`), access (401), media type `application/json` with at most `charset=utf-8` (415 `unsupported_media_type`), a body over 8192 bytes (413 `request_too_large`), the decoding (400 `invalid_settings` with the dotted path of a known key, else null), then the profile's `SaveRefusal`: 400 `invalid_settings` and `audio_device_not_endpoint` with the field, 403 `wrong_profile`, 409 `revision_conflict` and `revision_exhausted`, 503 `storage_unavailable`. 200 with `{profile_id, boot_id, revision, endpoint (the origin), connection_type, settings}`, at most `ProfileLimits::profileHttpMaxBytes`, also as the answer to a save. The error body `{error: {code, field}}`. 404 without a profile; another method 405. The event `profile.state` `{profile_id, boot_id, revision}`: once after the first subscription, then at each change. The code names the field of a refused value without `settings.` and of a refused key with it. | `HttpProfileGet`, `HttpProfilePut`, `HttpProfileRepresentation`, `HttpProfileError`, `HttpOutcome`, `PutDecision`, `GetDecision`, `HttpStatus`, TC-022-001 | profile |
| station link | The recording routes. `GET /recording`: `{v 1, profile_id, boot_id, generation, recording {id, rate_hz, frames, file_bytes, utc_anchor null}, source_error, storage_error, import (without recording_id; null once ended), job}`, the old limit 8192 bytes (`snapshotBytes`). `POST /recording/imports` `{v, profile_id, boot_id, generation}`: 201 `{v, id, generation, state reserved}` with `Location`. `PUT /recording/imports/{id}`: `audio/wav`, no content encoding, one `Content-Range: bytes start-end/total`, a body of 1 to 2048 bytes; 202 `{v, id, state receiving, received_bytes}`, 201 `{v, id, state completed, recording_id, generation}`; a body that is lost on the way cancels the import. `GET` and `DELETE /recording/imports/{id}`: 200 with `ImportView` and `v`. Status of a refusal: 422 `invalid_recording`, `unsupported_audio`, `recording_limit`; 408 `upload_timeout`; 413 `request_too_large`; 503 `storage_unavailable`; 404 `not_found`; 400 `invalid_request`, `unsupported_version`; 409 every other. The event `recording.state` carries of an import `{id, state, received_bytes, total_bytes, error}`; `received_bytes` alone at most once in 5 s. `StationLink.sysml` imports `WstxRecordingTransfer::Recording`, which is now the stored recording as reported, not an upload. | `ImportRecording`, `RecordingSnapshot`, `StartImportBody`, `UploadChunk`, TC-018-002, TC-018-003; `recording_http.rs` | profile |
| frontend | The profile form of Settings: the id and the name of the profile in the page and its title; Save and Reload; "Saved revision n", "Invalid callsign", "Reload saved settings before saving.", "Save outcome unknown", "Loaded saved settings."; one `PUT` for a save whose reply is lost; a text of the profile shown as text, never as markup; the native option shown as reserved; the form at 360 px. The recording controls of Settings > Expert: "No recording imported", "Recording ready", "Recording unavailable", the import with its cancel. The browser half of CL-005-02 ("identify the selected profile and permit the bounded edits") **needs a home** there. TC-022-005 is the frontend's. | CL-005-02, TC-022-001, TC-022-002, TC-022-005, CL-006-01 | profile |
| radioControl | `WstxProfileAccess` imports `WstxRadioControl::ControlSelection` for `Settings::control`; the tests read its three values of a new profile (`mode`, `endpoint`, `ptt`) by that name. Radio control says when a radio is managed (`manages_radio`: the mode cat and an endpoint that reads as a connection of its catalogue) and what `agc` and `power_limit_pct` do (CL-044-10, CL-044-12); the profile stores them (`RadioSettings`, `AgcSetting`). The form of an endpoint id and the change of a name to an id stand in `radio_control/setup.rs` and `radio_setup.rs`; CL-044-05 names both. CL-008-01 is retired; "typed IC-7300 control intent" is `ControlSelection`. TC-009-001 is radio control's. | CL-008-01, CL-044-05, TC-009-001 | profile |
| receive | `WstxReceiveJob::Admission` says "an import of a recording has not ended" and "the storage of the profile has an error": both are `WstxRecordingTransfer::RecordingStatus`, which the station service passes on. A recording the profile has answered `RecordingUnreadable` for is not shown as stored any more (`source_error`). The tests of the import in `recording_tests.rs` are bound to TC-018-002 now, `absent_manifest_artifacts_...` among them. | CL-006-02, CL-006-04, TC-018-003 | profile |
| flexAdapter | `WstxFlexSession::NativeIntent` (the form the adapter takes) and `WstxProfileAccess::NativeIntent` (the stored form) are two elements of one name; when the adapter is taken up, one refers to the other. | CL-013-03 | profile |

### Test cases handed over

| Test case | Shows | To |
|---|---|---|
| TC-009-001 Typed radio control | the CI-V exchange (`server/tests/radio_control.rs`) | radioControl |
| TC-022-005 Status readiness independent of settings transport | the browser while a read of the profile is held | frontend, station link |
| TC-022-001, its browser and route steps | the four windows, the form, the answers of `PUT /profile` to a body that cannot be decoded | frontend, station link |
| TC-022-002, its browser steps | the lost reply of a save | frontend |
| TC-022-003, its web steps | TLS, token, the occupied port, the other stations' windows | web, frontend |
| TC-018-002 and TC-018-003, their route steps in `tests/recording.test.cjs` | Origin, access, media types and status codes of the recording routes | station link |

### Changes needed outside the profile's files

- `Station.sysml`: none. The four ports of the profile keep their names and types.
- `backend/log/Log.sysml`: the marker on `LogService` ("what crosses the port contacts: its
  two items have no content") is answered; its text can become "of ProfileAccess only
  ProfileFolder crosses the port contacts".
- `_work/files.md`: `backend/profile/Profile.sysml`, `backend/profile/Recordings.sysml`,
  `interfaces/internal/ProfileAccess.sysml` and `interfaces/internal/RecordingTransfer.sysml`
  are built.
- `_work/ledger.md` (not the profile's rows): the row TC-092-004 names the profile; its
  profile half is the sentence in `ProfileOwnership`, without a test case of the profile.
- `START-HERE.md`: the state table (profile: built by a subagent; tests 1 to 5 pass; four
  new identities CL-006-05, CL-006-06, CL-013-08, TC-023-007; CL-008-01 retired; two markers;
  eight lines for the operator), and the ledger count.
- `Foundation/1-Finished-Model.md`: nothing, unless the operator answers line 1 with a new
  function file.

### Dependencies on interfaces built at the same time

`ProfileAccess.sysml` imports `WstxRadioControl::ControlSelection`
(`interfaces/internal/RadioControl.sysml`, which radioControl is building). If that element
is renamed or moved, the import and the sentence on `Settings::control` follow.
`parts.json` gives the validator that file. Nothing of transmit's or ranking's interfaces
is imported.

## For the operator

One line each; none is decided here.

1. **Done by rule M4.4 (a part's own file holds its part definition and ports): the clauses, rules and cases moved unchanged to `backend/profile/ProfileDocument.sysml` (package `WstxProfileDocument`; M2.1's `Profile*`); `Profile.sysml` keeps `PersistedProfile`; ledger targets changed.** Where the profile's own clauses stand. M2.1 gives the profile its own file and
   `Recordings`, so the six clauses about the document, the start and the save stand in the
   part's own file, which no other part does (udp put its clauses into its interface).
   WSJT-X: not applicable. Recommendation: add one function file to M2.1, for example
   `backend/profile/SavedProfile.sysml`, and move everything but the part definition there;
   the move changes no sentence.
2. **Decided by rule ("a function learns what the profile says from the station service, over its control interface", operator 2026-11-15 on audio): `contactStorage` and `strategyDefinitions` left `Station.sysml`, the profile's ports `contacts` and `definitions`, the log's and operating's ports to the profile and the marker went; the folder is `LogContext::folder`, `RankingContext::folder`, `ReceiveConfiguration::folder` and the new `OperatingContext::folder` (the value, as the context items carry the callsign: an import of `ProfileFolder` would make a cycle with `ProfileAccess`).** How a function learns the place of the profile's folder, and whether the log needs
   its connection to the profile.** Written: the profile gives `ProfileFolder`; each function
   keeps its own file (M4.1). Only the station service and the log are joined to the profile,
   and receive, spots, udp, audio, qso, transmit, ranking and web keep files there too
   (marker). WSJT-X: the configuration gives the data folder and each function opens its own
   file in it. Recommendation: the station service passes the folder with the profile's
   values on each control interface (M5.3); `contactStorage` then goes, and `LogContext`
   carries the folder.
3. **Answered (operator 2026-11-15): the generation goes. One job or import at a time is `busy`; stop, cancel, records and replay name the job or the recording and an old one is `not_found`. Removed: the count, `generation` on `StartLive`, `StopLive`, `StartReplay`, `ReadRecords`, `ReserveImport`, `ImportReserved`, `JobView`, `ReceiveStatus` and `JobIdentity`, the `state_conflict` for another generation, `generation_exhausted` (receive and import), the marker on `RecordingTransfer`. Work for the code: the counter in `recording.rs`, and the conditions of the tests that use it (receive's TC-018-003 (d), TC-009-004 (f); the import's (l)).** Who holds the generation and the one place for a job or an import. In the code one
   count is raised by a start of receive and by a reservation of an import, and each is
   refused while the other runs. Receive's built `Admission` says receive raises it; the
   profile's `ImportAdmission` says a reservation raises it (marker). WSJT-X: has no import;
   File > Open is not taken while the decoder is busy. Recommendation: the station service
   holds the count and the place, as the gate (M5.3), and gives each admitted command its
   generation; receive and the profile keep their own refusals. That changes two sentences
   of receive's `Admission`.
4. **Decided by rule (a new identity takes the next free number; one fact, one place for the retirement of CL-008-01).** The four new identities CL-006-05, CL-006-06 (the import halves of CL-006-02 and
   CL-006-04), CL-013-08 (the stored native intent) and TC-023-007 (its test case), and the
   retirement of CL-008-01 as the same promise as CL-005-05. Recommendation: keep all five.
5. **Decided by the rule on limits of time (operator 2026-11-15, on radio control): `importCancelAckMs` and `faultCleanupOutcomeMs` left (a cancellation is answered at once; files not removed in time fail the import); `reservationMs`, `uploadIdleMs` and `uploadTotalMs` stay, because the browser must keep sending within them; `profileHttpMaxBytes` is a size and stays. Work for the code: `tests/recording.test.cjs` reads `importCancelAckMs` from the model.** Which times and sizes are promises. Kept: `importCancelAckMs` (250 ms; only a test
   asserts it, with the model's value) and `profileHttpMaxBytes` (8192; a size of the reply
   on the wire that the profile checks at the start). Made a value of a test:
   `readinessDeadlineSeconds` (10 s, in TC-022-003). Dropped: `normalCleanupMs` (no code, no
   test). WSJT-X: none of them exists. Recommendation: as written; the station link refers
   to `profileHttpMaxBytes`.
6. **Answered (operator 2026-11-15): the start outcome belongs to the start of the station process, the station service's `Startup`; handed over when the station part is built; until then it stays in the profile. `OpenProfile` keeps its rule and names the five outcomes it gives; the web adapter names `endpoint_in_use`.** `StartupOutcome` stands whole in the profile, also `endpoint_in_use` and the cases of
   `invalid_runtime_configuration` and `resource_unavailable` that the listener gives. The
   tests read the enumeration as one. Recommendation: keep it in the profile; the web adapter
   names its conditions and refers to the literals.
7. **Answered (operator 2026-11-16): the conversion of device names at station start goes; CL-044-05 keeps "save an audio device only as its endpoint id"; `PresentEndpoints` left `ProfileAccess`; an older entry is taken as it is and the operator chooses the device again; TC-022-001 (k) is a planned line, its test `startup_migration_replaces_unique_friendly_names_only` unbound. Ids stay because identical radios have identical device names. Code: issue #229.** The change of a device name to its endpoint id at station start is the profile's
   rule,** and the station service brings the list of endpoints (`PresentEndpoints`). The
   other way is that the station service owns the change and saves through `SaveProfile`.
   WSJT-X: not checked. Recommendation: as
   written; the rule is about the stored document.
8. **Decided by rule (a clause derives from the one FR its part serves).** A profile of the native connection derives from FR-001, not from FR-023, because
   `Station.sysml` gives FR-023 to the Flex adapter alone. Recommendation: keep it; the
   clause is about what a profile stores.

## Not done, and what is not sure

- Nothing outside `docs/sysmlV2` was touched; nothing was committed or posted. Of
  `parts.json` only the key `profile` was written, of the ledger only the rows of the
  profile's identities (14 changed, 4 added after TC-018-002).
- Read in full: `profile.rs`, `profile_tests.rs`, `recording_http.rs`, the old
  `Profile.sysml` and `Recordings.sysml`, the two old interface files. Read in the parts that
  concern the profile: `main.rs` 1 to 1050 (the start, the router, `get_profile`,
  `put_profile`), `recording.rs` 1 to 560, 1608 to 1650, 3540 to 4323 (the WAV rules, the
  state, `open`, `cleanup`, the import, the replay), `recording_tests.rs` 596 to 628 and 1108
  to 1476 and 1583 to 1640 (the fixture and the eight tests of the import),
  `radio_setup.rs` 700 to 925 and its test of the migration, `radio_control/setup.rs`
  (`endpoint_id`, `migrate`), `flexAdapter/session.rs` (`Intent::valid`),
  `tests/profiles.test.cjs` 1 to 170, 1943 to 2105, 2246 to 2282, 2377 to 2409,
  `tests/recording.test.cjs` 1 to 434, `tests/profile/recording-fixtures.test.cjs`,
  `transmit/clock_http_tests.rs` (the test of `clock.json`).
- Not read: `tests/profiles.test.cjs` 171 to 1942 (the tests named TC-022-006, TC-073-001,
  TC-073-002: the browser's authorization), 2106 to 2245 and 2283 to 2376 (TC-022-004,
  TC-022-005, a review test of the browser's Refresh); `tests/recording.test.cjs` 435 to 608
  (the display tests TC-010-005 to -007, by their titles only); `client/app.js`,
  `client/recording.js`; `authorization.rs`; the tests of `recording_tests.rs` 1042 to 1121
  (a save while a selection runs: the station service's).
- TC-022-001 (a), (c) to (h), (j), TC-022-002 (a) to (g), (j) and TC-022-003 (a), (b), (d)
  to (g) are shown through the routes of a running station, not at the profile alone; they
  are bound to the whole file `tests/profiles.test.cjs`, which carries their numbers.
- TC-022-003 (a) says "it runs" for the restarted station; the test waits for the browser
  to connect and does not read the revision there.
- `ImportLifecycle` says a cancellation while the file is validated turns the import to
  cancelling; the code shows it (`cancel_import`, `write_chunk`), no test does.
- The sentence that a lock file left behind holds nothing rests on the operating system's
  lock (`File::try_lock`) and on the restarts of the tests; no test kills a process and
  starts it again at the profile alone.
- The validator accepts the four files with `RadioControl.sysml`; it was not run on
  `Station.sysml` with them.

## Changed after the report: the settings (operator 2026-11-15)

The operator decided on 2026-11-15 how the settings of a station are sorted and stored:
three stores (the station config, the hidden store of the station, the config of each
frontend), with definition files and data files as files of their own; a setting and a
record are defined by the part that uses them, in that part's control interface; the
profile only stores them, as collections by type (`WstxProfileAccess::StationConfig`,
`StationMemory`); a change takes one way (operator, station service, profile, and back to
the part as its new configuration). The model states this; the code still has a file for
each function, and the difference is work for the code (a later issue). The sections above
are as they were written; where they name a file of the function's own, a set command or a
storage refusal, this section holds.

Measured by `measure.py` in the session's scratchpad, subfolder `settings` (the tree
against a copy made before the change).

| File | Lines | Characters |
|---|---|---|
| `interfaces/internal/ProfileAccess.sysml` | 235 to 269 | 11,285 to 13,846 |
| `backend/profile/Profile.sysml` | 511 to 551 | 31,241 to 33,675 |
| `_descriptions/profile.md` | 379 to 424 | 26,818 to 31,017 |

The growth is the two stores as elements, the hidden store with its clause and its two
items, the planned line and four markers (`Profile.sysml` 1 to 3 markers,
`ProfileAccess.sysml` 0 to 2).

What the document is made of now:

| Element | What |
|---|---|
| `StationConfig` (new) | the station config: `station : ProfileConfig`, `radio : RadioConfig`, `audio : AudioConfig`, `transmit : TransmitConfig`, `receive : ReceiveConfig`, `spots : SpotsConfig`, `udp : UdpConfiguration`, `ranking : RankingConfig`, `native : NativeIntent[0..1]`, each of the other parts referred to by type |
| `StationMemory` (new) | the hidden store: `radio : RadioRecords`, `audio : AudioRecords` |
| `ProfileConfig` (new) | the profile's own configuration: `display_name`, `callsign`, `locator` (each with what it is and does), `endpoint`, `connection_type` |
| `ProfileDocument` | `settings`, `endpoint`, `connection_type` and `native` are one feature `config : StationConfig`; the text of the file names the keys the profile, audio and radio control have, and a marker names the keys that are not stated |
| `Settings` | gone: its three own values are `ProfileConfig`, `audio` is audio's `AudioConfig`, `control` and `radio.agc` are radio control's `RadioConfig`, `radio.power_limit_pct` is transmit's `TransmitConfig::powerLimitPct` |
| `AudioSelection`, `RadioSettings`, `AgcSetting` | gone from the profile's interface: defined by audio (`AudioConfig`), radio control (`RadioConfig`, with `WstxRadioProperties::Agc`) and transmit |
| `NamedEndpoint` | moved to `WstxAudioControl`; `PresentEndpoints` refers to it |
| `ProfileLimits::textMaxBytes` | gone: the length of a device id and of a control endpoint stands with `AudioConfig` and `ControlSelection` |
| `NativeIntent` | stays in the profile's interface, as the configuration of the parked Flex adapter, with a marker (the adapter has no control interface that could hold it) |
| `SaveProfile` | carries `config : StationConfig` in place of `settings` |
| `MemorySnapshot`, `SaveMemory` (new) | the hidden store from the profile, and a save of it; two more items on `ProfileAccess` (5 to 7) |
| `PersistedProfile` | two attributes, `config : StationConfig` and `memory : StationMemory`; its marker about the folder names ranking and receive only (definition and data files) |
| `ProfileFolder` | the folder is for definition files and data files |
| `EndpointIds` | the form of an endpoint id moved to `AudioConfig`; the refusal and the change of a name to its id at station start stay |
| `SaveSettings` | the order of the refusals names the values of the profile, audio and radio control; `radio.power_limit_pct` left the order |
| `KeepMemory` (new) | what the profile does with the hidden store |

Identities:

| Identity | What |
|---|---|
| CL-005-06 (new) | "Profile MUST keep the records the parts of its station hand over across every stop of the station, and show them in no menu (KeepMemory)", from FR-016, status target. The next free number of the series CL-005 (CL-005-03 is the web adapter's, still "TO PLACE"). It has no test case: no test exists |
| CL-005-02 | the sentence says "the station config" for "the settings"; status implemented to partial, because the code keeps the values of five configurations (transmit, receive, spots, udp, ranking) in files of the functions' own or, for the two limits of the Tx watchdog, in no file |
| TC-022-002 | one line more, (k), "Planned, no test yet": the configurations of transmit, receive, spots, udp and ranking after a stop and a start, and a record of radio control and of audio in the hidden store (10 to 11 lettered lines, 3 tests as before) |

No identity is retired or not carried. The ledger has one row more (570 to 571; 225 to 226
arrived).

Verdicts in `parts.json` (test 4: 7 matched, 96 with a verdict; before 10 and 94):

| Line of test 4 | Verdict |
|---|---|
| code `Agc::Fast`, `Agc::Mid`, `Agc::Slow` (3 added) | matched by reading: `WstxRadioProperties::Agc`, by which `RadioConfig::agc` is typed; the profile has no enumeration of its own for the AGC any more (the three literals of `AgcSetting` were the 3 matches that went) |
| model value `ProfileLimits::textMaxBytes` (1 taken out) | the value left the model |

`validate_with` of the profile has six files more: the control interfaces
`ProfileAccess` imports (`AudioControl`, `TransmitControl`, `ReceiveControl`, `Hearing`,
`external/Udp`, `RankingControl`).

Markers added (4): on `ProfileDocument` (the keys of five configurations in the file,
their names in `SaveRefused::field` and their place in the order of the refusals), on
`NativeIntent` (see above), on `SaveSettings` (whether a save the station makes by itself
counts the revision), on `KeepMemory` (the file and form of the hidden store, and what an
unreadable one means).

Differences in the code that test 4 does not show (work for the code):

- `profile.json` holds the profile's own values, `audio`, `control` and `radio` only. The
  Tx level (`tx-level.json`), the window dump (`receive-diagnostics.json`), the two PSK
  Reporter switches (`pskr.json`), the UDP targets (`udp.json`) and the session minutes
  (part of `strategy.json`) lie in files of their own; the two limits of the Tx watchdog
  are kept in no file.
- The code has no hidden store. `Store::read_document_file`, `write_document_file` and
  `remove_document_file` of `profile.rs` read and write one file for each record in the
  profile's folder (`radio-keying-confirmed.json`, `radio-settings-undo.json`,
  `audio-endpoint-names.json`), called by the function that owns the record.
- `settings.radio.power_limit_pct` stands inside the radio settings and is present only
  for a managed radio; in the model it is transmit's value.
- `PUT /profile` takes `display_name`, `callsign`, `locator`, `audio`, `control` and
  `radio`; the other configurations have routes and files of their own.

Decided by rule: the setting is defined with the part that uses it (the decision), so the
form of an endpoint id went to audio and the profile keeps the refusal; a clause is split
only where its members are shown by different tests (M6.4), so the hidden store has a
clause of its own; a clause's status follows the code.

Not decided, for the operator: see the session's final message (the revision and a save
the station makes itself; the file and form of the hidden store; the keys of the new
configurations in the file; whether a part waits for its record to be kept).

Not verified: the bodies of the tests of TC-022-001 to -003 were not read again; their
conditions are unchanged but for the names of the elements.

## Changed after the report: the operator's decisions on ignoring and directed CQs (2026-11-15)

The operator decided six points on 2026-11-15 (issue 228); the operating report's section
of the same name lists all six. Two touch the profile: the station's continent is a
setting of the station, saved in the station config, and the CQ words for this station
are a value of the station config. Both are the station's own values, so they stand in
`ProfileConfig` (the station's own values; the settings rule), and ranking is given them
by the station service. The one value of ranking's configuration, the session minutes,
goes with the session ignore list, so `RankingConfig` goes. Measured by `measure.py` in
the session's scratchpad folder `decisions`.

| File | Element | What |
|---|---|---|
| `ProfileAccess.sysml` | `ProfileConfig::continent` | new: `Continent[0..1]`, the continent the operator has set; absent, ranking derives it |
| | `ProfileConfig::cq_words` | new: `String[0..*]`, the CQ words for this station, each 1 to 8 of A to Z and 0 to 9, once; Settings proposes the continent's code and the country's word; also words for the station's own CQ (the contact's and Auto's); a marker: how the country's word is formed and how many words the list holds |
| | `StationConfig::ranking` | gone, with the import of `RankingConfig`; import of `WstxLogControl::Continent` |
| | marker on `ProfileDocument` | names the keys of `continent` and `cq_words` as not stated, beside those of the configurations of transmit, receive, spots and udp |
| `Profile.sysml` | `TC-022-002` (j) | "every value of ProfileConfig but continent and cq_words": the largest snapshot is shown without them |
| | `TC-022-002` (k) | planned: the station's continent and CQ words in the place of ranking's configuration |
| `_descriptions/profile.md` | sections 1, 4, 9, 10 | as the model now says |
| `_work/parts.json` | profile | `validate_with`: `LogControl.sysml` in the place of `RankingControl.sysml` |

Sizes (characters): `ProfileAccess.sysml` 13,846 to 14,893; `Profile.sysml` 33,890 to
33,970; `_descriptions/profile.md` 31,017 to 31,701.

No identity is new, retired or not carried; TC-022-002 is reworded in two lines. Test 4 of
the profile is unchanged (7 matched, 96 with a verdict): the two values have no number and
no literal of their own.

Differences from the code: `server/src/profile.rs` has neither value in `profile.json`
(the continent stands in `strategy.json`, `strategy.rs` `Config::continent`; the CQ words
do not exist). The keys in the file are not stated (marker).

For the operator: whether the station service takes an older `strategy.json`'s continent
into the station config once (line 4 of the operating report's section).

Not verified: the tests of TC-022-002 were not read again.

### Answered by the operator (2026-11-15)

The old file's continent is not moved into the station config. While the station has no
continent, neither set nor derived, the operator is shown an error message
(`ProfileConfig::continent`). The proposed country word is the primary prefix of the entity
of the profile's call in the country file (`cty.dat`; HB for Switzerland); the marker on
`cq_words` keeps only the number of words. Differences in the code: no error message, no
CQ words.

## Changed after the report: the station's name (operator 2026-11-16)

Six stations will run side by side on one PC, so each has a name. The operator decided:
the name is chosen when the radio is defined, as WSJT-X's rig name; the station offers the
chosen rig's name (IC-7300), for a FlexRadio its model and slice A to F (FLEX-6600 A), and
without a radio No radio; the operator takes it or types another; it stays until changed
and does not depend on the radio answering; no two stations of the PC share it. It is
`ProfileConfig::display_name` (its sentence rewritten, default No radio). The UDP instance
name is "WSTX-Rust - " and that name, fixed at station start (`InstanceName`): the claim of
the first free name with a number and the lock folder left, and the instance name is always
present. This changes the operator's #112 answer ("not a setting", the number on a clash,
the Flex name at the first ready session). TC-112-001 keeps (e), (f) and gets the planned
(i); (a) to (d), (g), (h) left. Work for the code: `udp.rs` `base_name`, `flex_name`,
`claim`; the uniqueness among the PC's stations at the choice (the station service's, with
the Settings field: handover rows).

## The settings questions, answered (2026-11-16)

- **A save the station makes by itself:** decided by the model as it stands: one way for a
  change (`SaveProfile`), and every save that is not refused raises the revision. The
  marker's only reason, radio control's reconnect on another revision, left with radio
  control line 12. Marker removed.
- **The keys of the new configurations in the file:** decided by the model's own names:
  `continent`, `cq_words` beside the other values of `ProfileConfig`; `transmit`,
  `receive`, `spots`, `udp` as objects with their values' names; a refused value is named
  `<part>.<value>`; the order of the refusals follows the definitions. Marker removed.
- **Whether a part waits for its record to be kept:** answered in each part's model: a
  record counts when it has come back as kept (`KeyingConfirmation`, `RadioMemory`,
  `LevelFound`); the undo record, the case in question, is gone.
- **The file and form of the hidden store (operator 2026-11-16):** `memory.json` beside `profile.json`, `schema_version` 1 and one key per part (`radio`, `audio`), written as the document is; an unreadable file or one of another schema gives every record its default, `MemorySnapshot::unreadable` true, and the file stays until the next keep. Work for the code: the records are files of their functions (`radio-keying-confirmed.json`, `audio-endpoint-names.json`).

## Changed after the report: the settings function and two levels (operator 2026-11-16)

Decided: data, management and use are divided; the profile is the settings function and
manages every config value and definition (create, read, update, delete, the files, the
rules of the parts applied); settings have an operator level, one folder shared by up to
six stations of the operator (fixed at `%LOCALAPPDATA%\WSTX-Rust\operator`, `--operator`
names another), and a station level, the profile's folder; the revision guards by level
(station config: none; shared files: yes). See the method's "Decided" list.

| Element | What changed |
|---|---|
| `ProfileAccess` | `OperatorConfig` (callsign, locator, continent, CQ words out of `ProfileConfig`), `OperatorSettings` (with `SpotsConfig`, `UdpConfiguration`, out of `StationConfig`), `OperatorDocument` (`operator.json`), `OperatorSnapshot`, `SaveOperator`; `ProfileFolder::operatorPath`; `StrategyDefinitions`, `DefinitionsSnapshot`, `SettingsCollection`, `CreateEntry`, `UpdateEntry`, `DeleteEntry`, `RenamedEntry`; refusals `entry_exists`, `entry_unknown`, `collection_full`; `revision_exhausted`, `ProfileLimits::maxRevision`, `ProfileDocument::revision` and `SaveProfile::expectedRevision` gone |
| `ProfileDocument.sysml` | new CL-005-07 (`OperatorFolder`, `SaveOperatorSettings`, TC-022-011); from operating CL-039-01 (`CollectionRule`, `StrategiesFile`, TC-039-001, -003, TC-097-002) and CL-097-01 (`StrategyCheck`, TC-097-001); `SaveSettings` without revision; `ProfileOwnership` shares the operator's folder; `OpenProfile` takes `--operator`; TC-022-001 and -002 without revision conditions, the callsign and locator conditions moved to TC-022-011 |

Differences in the code: no operator level and no `operator.json` (`profile.rs` keeps
callsign and locator in `profile.json`, `strategy.rs` keeps `strategy.json`, `udp.rs`
`udp.json`, spots `pskr.json`, the log `contacts.adi` and `cty.dat`, ranking
`most_wanted.json`, each in the profile's folder); the station config's revision
(`put_profile` in `main.rs`: `revision_conflict`, `revision_exhausted`); no CRUD of a
collection; no file lock between stations. The bound tests of TC-022-001 (f), (h) and
TC-022-002 (f) assert the revision; those of TC-039-001, -003 and TC-097-001 the whole
save of the strategies.

Not done: `_descriptions/profile.md` is not yet rewritten to these elements.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-022-001 (`ProfileDocument.sysml`): a document whose output is Speakers (USB Audio CODEC ): it stays as it is, also with a present output of that name.
- TC-022-002 (`ProfileDocument.sysml`): the configurations of transmit and receive saved in the document and the same after the station is stopped and started; a record of radio control and of audio kept in the hidden store and the same after the station is stopped and started.
- TC-022-011 (`ProfileDocument.sysml`): two stations of one operator's folder. A save of the operator's settings on one: the other gives the new settings. A save on the other made from the revision before: revision_conflict, the file unchanged. A QSO logged on one is in the worked set of the other. Without the folder, a station start makes it; --operator names another, and the strategies file, the logbook, the country file and the Most Wanted list lie there.
- TC-039-003 (`ProfileDocument.sysml`): an update of Test calls with leaving after 5 calls: the file holds the new value; a delete of Test calls: the file holds no strategy; an update or delete of Other: entry_unknown.
- TC-097-002 (`ProfileDocument.sysml`): of that file of version 1, and of one of version 4 with the keys continent, ignore_calls and session_ignore_minutes, neither the continent nor the ignore list is taken over; a file of version 1 with the continent XX is usable; a strategy of version 4 without cq_quiet_periods is read with a CQ pause of 8.
- TC-097-001 (`ProfileDocument.sysml`): a CQ pause of 0 and of 40 is taken; one of -1, of 41, as a text, null and left out is refused, naming cq_quiet_periods.

## Changed after the report: the Most Wanted list goes to the settings function (operator 2026-11-16)

Decided (operator 2026-11-16, "Profile fetches", by the rule that data, management and use are
divided): the profile fetches the Most Wanted list from Club Log and keeps it; ranking only
ranks by it.

| Element | What changed |
|---|---|
| CL-039-10 (`MostWanted.sysml`, ranking) | ranks by the list the settings function keeps; `MostWantedListRule` keeps the use only |
| CL-039-30 (new, `ProfileDocument.sysml`) | the fetch and the keeping: `MostWantedFetch`, `MostWantedFile` (keys schema_version, date, list; no profile_id, since the operator's folder is shared) |
| TC-039-031 | keeps `tc_039_031_every_bundled_entity_has_its_adif_number` |
| TC-039-055 (new) | `tc_039_031_parser_refuses_all_but_the_exact_list`, `tc_039_031_response_body` |
| `ClubLog.sysml` | the profile's end; the attribution line moved here; the file is the profile's |
| `ProfileAccess` | `MostWantedList`, `UpdateMostWanted`, `DefinitionsSnapshot::mostWanted` and `mostWantedUnusable`, `SaveRefusal::download_failed`, `SaveRefused::detail` |
| `RankingControl` | `RankingContext::mostWanted` in place of `folder`; `UpdateMostWanted`, `downloadFailed`, `storageUnavailable`, `RankingRefused::reason`, `mostWantedUnreadable`, the attribution gone |
| `Context.sysml` | Club Log connects to `profile.clubLog` |

Not bound any more: `strategy_tests.rs::tc_039_031_update_most_wanted_status_failures_and_mcp_refusal`
asserts that an agent may not update the list (issue 122: an agent is the operator).
Work for the code: the fetch lives in `most_wanted.rs` and `strategy.rs` (ranking's code), the
file in the profile's folder with profile_id, an agent is refused.

## Done: cty.dat is downloaded by the settings function (operator 2026-11-16, "Download, as WSJT-X")

| Element | What changed |
|---|---|
| `interfaces/external/CountryFiles.sysml` (new; M2.1 and `Context.sysml` name it) | `CtyQuery` (the source of WSJT-X), `CtyDownload` (`bytesMax` 1048576), `CountryFilesPort`, `CountryFiles` |
| CL-055-06 (new, `ProfileDocument.sysml`) | `CountryFileFetch`, `CountryFileStore` (cty.dat in the operator's folder, read by `CountryFile`); target, no test |
| `ProfileAccess` | `UpdateCountryFile`, `DefinitionsSnapshot::countryFile` and `countryFileUnusable`, `SaveRefusal::invalid_country_file` |
| CL-055-03 (`CountryFile.sysml`, log) | uses the file the settings function keeps; `ProfileCountryFile` says only which file is in use; partial |
| `LogControl` | `ReplaceCountryFile` carries the profile's file; `invalidCty`, `LogRefused::line`, `countryFileBytesMax`, `uploadUnreadable` gone; `CountryFileSource` bundled, downloaded |
| TC-055-003 | not carried: its test uploads a file |

Work for the code: no download (dxcc.rs takes an upload over the logbook routes); the check and the
file are the log's in the code.
