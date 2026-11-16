# Profile

A view of the model, written from `docs/sysmlV2` on 2026-11-16 (working tree, not
committed). It adds no fact and decides nothing. Read: the files of
`backend/profile/`, the data of a strategy in `interfaces/internal/Strategies.sysml`, `interfaces/internal/ProfileAccess.sysml`,
`interfaces/internal/RecordingTransfer.sysml`, and of `Station.sysml`, `Context.sysml`,
`backend/log/Log.sysml`, `backend/receive/Receive.sysml` and, of the control interfaces of
radio control, audio, transmit, receive, spots and udp, the configuration and record
types `ProfileAccess` refers to, and of `LogControl` the type `Continent`. Not read: the code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Profile | the saved configuration of one station, with its folder and its one recording; also the settings function of the station | `PersistedProfile` |
| Settings function | the profile as the one that creates, reads, changes and deletes the settings and applies the rules of their parts | `ProfileAccess`, `CollectionRule` |
| Document | the content of `profile.json`: identity and station config | `ProfileDocument` |
| Station config | every value the operator sets of this station, as the collection of the configurations of its parts | `StationConfig` |
| Operator's settings | what the operator's stations share: callsign, locator, continent, CQ words, the configurations of spots and udp | `OperatorSettings`, `OperatorConfig`, `OperatorDocument` |
| Operator's folder | the folder up to six stations of one operator share: `operator.json`, the strategies, the logbook, the country file, the Most Wanted list | `OperatorFolder` |
| Settings collection | settings whose members the operator creates, changes and deletes one by one: the strategies, the UDP targets | `SettingsCollection` |
| Hidden store | what the software keeps across sessions and no menu shows, as the collection of the records of the parts | `StationMemory` |
| The profile's own configuration | the station's name (display name) and what is set when the profile is made | `ProfileConfig` |
| Revision | the count of the changes of a shared file (`operator.json`, the strategies file); the station config has none | `OperatorDocument::revision`, `DefinitionsSnapshot::revision` |
| Folder | the profile's folder: the document, the hidden store, the recording and the files of other functions of this station | `ProfileFolder`, `ProfileOwnership` |
| Managed radio | a radio whose control mode is cat and whose endpoint reads as a radio connection | `WstxRadioControl::RadioConfig` |
| Native connection | a station that uses a FlexRadio through its native interface | `ConnectionType`, `NativeProfile` |
| Endpoint id | the form in which an audio device is saved | `EndpointIds` |
| Recording | a WAV file of the one form that the profile holds | `Recording`, `WavForm`, `StoredRecording` |
| Import | the way a recording comes into the profile, part by part | `ImportLifecycle`, `ImportView` |
| Part | a piece of the file of an import | `ImportChunk` |

"Endpoint" has two meanings: where the station listens (`Endpoint`: bind and origin) and
an audio device (`EndpointIds`). A third use is the endpoint of the
radio control (`RadioConfig::control`).

## 2. Place in the system

Position: `Station` > `Backend` > `StationProcess` > `profile : PersistedProfile`.
`Station.sysml` gives FR-001, FR-016, FR-018 and FR-022 to the profile.

| Port of the profile | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `context` | `~ProfileAccess` | station service, `profile` | `ProfileAccessLink` | out: `ProfileFolder`, `ProfileSnapshot`, `OperatorSnapshot`, `DefinitionsSnapshot`, `MemorySnapshot`, `SaveRefused`; in: `SaveProfile`, `SaveOperator`, `CreateEntry`, `UpdateEntry`, `DeleteEntry`, `SaveMemory` |
| `upload` | `~RecordingTransfer` | station service, `acceptedRecording` | `RecordingTransferLink` | in: `ReserveImport`, `ImportChunk`, `CancelImport`, `ReadImport`, `ReceiveBusy`; out: `ImportReserved`, `ImportView`, `ImportRefused`, `RecordingStatus` |
| `recordedSamples` | `RecordedSamples` | receive, `recorded` | `RecordedSamplesLink` | in: `OpenRecording`; out: `RecordedBlock`, `RecordingUnreadable` |

Not connected: web, mcp, the modes part, the clock, transmit, ranking, auto, qso, spots,
udp, audio, radio control and the Flex adapter. None of them can save the profile or bring
a recording; each gets its configuration and its records from the station service, over
its control interface, and keeps no file of its own for them. No outside thing of
`Context.sysml` is joined to the profile: its files are described here.

The station service gives each function the folder of its files with its context: the
operator's folder to the log and ranking, the profile's folder to receive; operating keeps
no file. No other part is joined to the profile.

## 3. Purpose and requirements

The profile holds the station config and the hidden store of one station for one station
process, and the operator's settings and strategies its stations share; refuses a start it
cannot carry out with a reason; saves a change durably, a shared one only under the file's
lock and from its revision; creates, changes and deletes the members of a settings
collection by their key; and takes in one recording that it gives to receive as samples.
A setting and a record, and their rules, are defined by the part that uses them; the
profile applies the rules.

| Clause | FR | Promise | Element | Status |
|---|---|---|---|---|
| CL-005-01 | FR-022 | hold a profile and its folder for one station process at a time, so that profiles run side by side | `ProfileOwnership` | implemented |
| CL-005-04 | FR-022 | end a start or a creation it cannot carry out with its reason and leave the saved profile as it is | `OpenProfile`, `StartupOutcome` | implemented |
| CL-005-02 | FR-016 | keep identity and station config across every stop, and answer a save as done only when durable | `SaveSettings` | partial |
| CL-005-07 | FR-016 | keep the shared settings and files in the operator's folder, change a shared file only under its lock and from its revision, give its station another's change | `OperatorFolder`, `SaveOperatorSettings` | partial |
| CL-039-01 | FR-016 | create, change and delete a member of a settings collection only by its key and within its part's rules; keep the saved strategies across every stop | `CollectionRule`, `StrategiesFile` | partial |
| CL-097-01 | FR-016 | take a strategy only within the rules of a strategy, and name a value that does not | `StrategyCheck` | partial |
| CL-005-06 | FR-016 | keep the records the parts hand over across every stop, and show them in no menu | `KeepMemory` | target |
| CL-005-05 | FR-001 | store the audio devices and the radio control each by itself; make a profile with neither | `CreateProfile` | implemented |
| CL-044-05 | FR-001 | save an audio device only as the endpoint id of its direction; turn a name of an older file into the id at station start | `EndpointIds` | implemented |
| CL-013-08 | FR-001 | for the native connection, store the identity toward the radio, the antenna and at most an address, and neither device nor radio control | `NativeProfile` | implemented |
| CL-006-01 | FR-018 | take in only a WAV file of the one form within the limits, keep it byte for byte, give receive its samples | `WavForm`, `StoredRecording` | implemented |
| CL-006-05 | FR-018 | put a recording in the place of the stored one only by a whole and valid import; keep the stored one otherwise | `ImportLifecycle` | implemented |
| CL-006-06 | FR-018 | run one import at a time and answer every command it does not carry out with the reason | `ImportAdmission` | implemented |

The status is the model's declaration.

## 4. Data and rules

### The stores (`StationConfig`, `OperatorSettings`, `StationMemory`)

| Store | Holds | Kept by | Element |
|---|---|---|---|
| station config | what the operator sets of this station | the profile, in `profile.json` in the profile's folder | `StationConfig` |
| operator's settings | what the operator's stations share | the profile, in `operator.json` in the operator's folder | `OperatorSettings` |
| hidden store | what the software keeps of this station across sessions; no menu shows it | the profile | `StationMemory` |
| frontend config | the display choices of one frontend | that frontend | not in these files |

Beside them stand files of their own, each in the folder of its level: definition files,
which a settings dialog opens, and data files.

| Part | Its configuration | Its records in `StationMemory` | Defined in |
|---|---|---|---|
| profile | `station : ProfileConfig` (station config); `operator : OperatorConfig` (operator's settings) | none | `ProfileAccess` |
| radio control | `radio : RadioConfig` | `radio : RadioRecords` | `RadioControl` |
| audio | `audio : AudioConfig` | `audio : AudioRecords` | `AudioControl` |
| transmit | `transmit : TransmitConfig` | none | `TransmitControl` |
| receive | `receive : ReceiveConfig` | none | `ReceiveControl` |
| spots | `spots : SpotsConfig` (operator's settings) | none | `Hearing` |
| udp | `udp : UdpConfiguration` (operator's settings) | none | `UdpControl` |
| Flex adapter | `native : NativeIntent`, with `native_flex` only | none | `ProfileAccess`, with a marker |
| operating | the saved strategies (`StrategyDefinitions`, in the strategies file of the operator's folder) | none | `Strategies` |

### The document (`ProfileDocument`, `ProfileConfig`, `Endpoint`, `NativeIntent`)

`profile.json` is one JSON object: `schema_version`, `profile_id` and the station config:
the keys of `ProfileConfig`, `audio`, `control`, `radio`, `transmit`, `receive` and
`native`. A file that also holds `revision`, `callsign`, `locator`, `continent`,
`cq_words`, `spots` or `udp` is read without them; their values are not taken over.

`operator.json` in the operator's folder (`OperatorDocument`) is one JSON object with
`schema_version` 1, `revision`, `callsign`, `locator`, `continent` (left out when absent),
`cq_words`, `spots` and `udp`. Of `OperatorConfig`: `continent` is one of the seven, or
absent (ranking derives it; with no continent, neither set nor derived, the operator is
shown an error message); `cq_words` are the CQ words for this operator's stations, each 1
to 8 of A to Z and 0 to 9, once; Settings proposes the continent's code and the country's
word, the primary prefix of the entity of the call in the country file, such as HB, DL or
JA; how many words the list holds is not stated (marker).

| Key | Value | Value of a new profile | Changed by a save |
|---|---|---|---|
| `schema_version` | 1 with `standard`, 2 with `native_flex` | 1 | no |
| `profile_id` | UUID of version 4, lower case | new | no |
| `display_name` | 1 to 64 bytes, no control character, no white space at either end | New station | yes |
| `endpoint.bind` | IP address and port 1 to 65535 | 127.0.0.1:8080 | no |
| `endpoint.origin` | absent, or scheme (http, https), host and port, nothing else; its port is the port of bind | absent | no |
| `connection_type` | `standard`, `native_flex` | `standard` | no |
| `audio.input_device`, `audio.output_device` | absent, or 1 to 256 bytes without control character | absent | yes, each by itself |
| `control` | mode disabled or cat; endpoint absent with disabled, 1 to 256 bytes with cat; ptt disabled or cat, cat only with mode cat | disabled, absent, disabled | yes |
| `radio` | present exactly for a managed radio: `agc` (`RadioConfig::agc`) | left out | yes |
| `native` | present exactly with `native_flex`: `client_id` (UUID), `rx_antenna` (1 to 16 of A to Z, 0 to 9, "_"), `radio_address` (IPv4 and a port other than 0, may be left out) | left out | no |

A key that is absent, given twice or unknown, a value of another type or outside its rule
makes the file no valid profile. `null` stands for an absent device, control endpoint and
origin; `radio`, `native` and `radio_address` are left out when absent.

| Key of `operator.json` | Value | Value without a file |
|---|---|---|
| `revision` | the count of the saves | 0 |
| `callsign` | empty, or 3 to 12 of A to Z, 0 to 9 and "/", with a letter and a digit | empty |
| `locator` | empty, or 4, 6 or 8 characters: AA00, AA00AA, AA00AA00 with A to R, digits, A to X, digits | empty |
| `continent`, `cq_words` | as above | absent, none |
| `spots`, `udp` | the configurations of these parts | their defaults |

### Limits (`ProfileLimits`, `RecordingLimits`)

| Limit | Value | At the limit |
|---|---|---|
| `profileFileMaxBytes` | 16384 | a larger `profile.json`: `invalid_profile` |
| `profileHttpMaxBytes` | 8192 | a profile whose largest possible snapshot is larger: `invalid_profile` at the start |
| `displayNameMaxBytes` | 64 | a longer name: `invalid_settings` |
| `rateHz` | 12000 | another rate: `unsupported_audio` |
| `fileBytes` | 3145728 | a larger file: `recording_limit`; a larger announced total: `request_too_large` |
| `importMaxFrames` | 1440000 | more samples: `recording_limit` |
| `importMaxRiffChunks` | 64 | more chunks: `recording_limit` |
| `rawChunkBytes` | 2048 | the type of `ImportChunk::bytes` holds no more |
| `reservationMs` | 30000 | a reserved import without a part: `upload_timeout` |
| `uploadIdleMs` | 15000 | a receiving import without a new part: `upload_timeout` |
| `uploadTotalMs` | 1800000 | an import not complete: `upload_timeout` |

### What crosses `ProfileAccess`

| Item | Direction (from the profile) | Content | When |
|---|---|---|---|
| `ProfileFolder` | out | the paths of the profile's folder and of the operator's folder | once, at station start |
| `ProfileSnapshot` | out | the document | at station start, after every change of the document, and as the answer to an accepted save |
| `OperatorSnapshot` | out | `operator.json`, and whether it is unusable | at station start, after every save of it, when another station has saved it, and as the answer to a `SaveOperator` or to a command for the UDP targets |
| `DefinitionsSnapshot` | out | the saved strategies, the revision of their file, whether it is unusable, the strategies read under another name | at station start, after every change, when another station has changed them, and as the answer to a command for the strategies |
| `SaveOperator` | in | `expectedRevision`, `settings` (`OperatorSettings`) | a change of a shared setting |
| `RuleFacts` | in | the entity names of the country file in use, the names of the built-in strategies | at station start and whenever one changes; the rules of a collection take their facts from it |
| `CreateEntry`, `UpdateEntry`, `DeleteEntry` | in | the collection, `expectedRevision`, the key (update, delete), the strategy or the target (create, update) | one member of a settings collection |
| `MemorySnapshot` | out | the hidden store | at station start, and as the answer to every `SaveMemory`: the new store when it is durable, the one before when it could not be kept |
| `SaveProfile` | in | `profileId`, `config` (`StationConfig`) | a save of this station's settings |
| `SaveMemory` | in | `memory` (`StationMemory`) | a part has changed a record |
| `SaveRefused` | out | `reason` (`SaveRefusal`), `field` | the answer to a save that is not carried out |

Each command has one answer; the profile deals with one command after the other.

### What crosses `RecordingTransfer` and `RecordedSamples`

| Command | Carries | Answer | Refusal |
|---|---|---|---|
| `ReserveImport` | nothing | `ImportReserved` (`id`) | `ImportRefused` |
| `ImportChunk` | `id`, `start`, `total`, 1 to 2048 `bytes` | `ImportView` | `ImportRefused` |
| `CancelImport` | `id` | `ImportView` | `ImportRefused` |
| `ReadImport` | `id` | `ImportView` | `ImportRefused` |
| `OpenRecording` | `id` | `RecordedBlock`s to the end | `RecordingUnreadable` |

`ImportView`: `id`, `state`, `received_bytes`, `total_bytes` (absent before the first
part), `error` (absent while it runs and when completed), `recording_id` (absent until the
file is the stored recording). `RecordingStatus`, given at station start and at every
change: `recording` (`id`, `frames`, `file_bytes`; absent when none is stored or it cannot
be read), `source_error`, `storage_error`, `running` (the import that has not ended).
`ReceiveBusy`, from the station service at station start and at every change:
`notReleased`, `jobRunning`. `RecordedBlock`: `firstFrame`, 1 to 4096 `samples`,
`endOfStream`; mono, 12 kHz, each sample the stored 16-bit value divided by 32768, from
frame 0 without a gap, with no tie to station time.

### Which file is a recording (`WavForm`)

The file is read in this order; the first fault decides.

| # | Check | Fault |
|---|---|---|
| 1 | at most `fileBytes` | `recording_limit` |
| 2 | begins with RIFF, a length and WAVE; the length plus 8 is the file's length | `invalid_recording` |
| 3 | chunks to the end, each with name and length, odd ones followed by one byte; none reaches beyond the end; at least 8 bytes for each | `invalid_recording` |
| 4 | at most `importMaxRiffChunks` chunks | `recording_limit` |
| 5 | one fmt chunk, before the data chunk | `invalid_recording` |
| 6 | fmt length 16 or 18 | `unsupported_audio` |
| 7 | PCM, one channel, `rateHz`, 16 bits | `unsupported_audio`, unless a fault of the build is found as well |
| 8 | 2 bytes for a frame, 24000 bytes for a second; the two further bytes of a fmt chunk of 18 are 0 | `invalid_recording` |
| 9 | one data chunk after fmt, of even length above 0 | `invalid_recording` |
| 10 | at most `importMaxFrames` samples | `recording_limit` |

A chunk of another name is passed over and kept with the file. A file that ends where a
part is expected: `invalid_recording`. A file that cannot be read for another reason:
`storage_unavailable`.

### The stored recording and the folder (`StoredRecording`, `ProfileOwnership`)

| File | Holds |
|---|---|
| `profile.json` | the document |
| the hidden store (file and form not stated, marker) | `StationMemory` |
| `.profile.lock` | the lock of the folder |
| `<profile_id>.lock` in `wstx-rust-profile-locks` of the account's local application data (or of the temporary folder) | the lock of the identity |
| `recordings/<id>.wav` | the file of the import as it came |
| `recordings/<id>.json` | `schema_version` 1, `recording_id`, `file_bytes`, `frames`, `rate_hz` |
| `recordings/current.json` | `schema_version` 1 and the `recording_id` of the stored recording |

The profile writes these, and a temporary file beside `profile.json` while it saves. Every
other file of the folder it leaves as it is.

## 5. Behaviour

**Default: a command that is refused changes nothing, and a start that is refused changes
no file.**

### Opening at station start (`OpenProfile`, `ProfileOwnership`)

The first of these that holds ends the start.

| # | Condition | Outcome |
|---|---|---|
| 1 | arguments other than `--profile` and a folder (with at most one `--operator` and a folder), `--create-profile` and a folder, or `--create-native-flex-profile` with a folder, an antenna and at most an address; `WSTX_BIND` or `WSTX_ORIGIN` in the environment | `invalid_runtime_configuration` |
| 2 | no such folder; `profile.json` cannot be opened or read | `resource_unavailable` |
| 3 | `profile.json` over `profileFileMaxBytes`, or not the JSON object of the document | `invalid_profile` |
| 4 | `schema_version` 1 with `native_flex` | `unsupported_connection_type` |
| 5 | `schema_version` 2 without `native`; any other `schema_version` | `unsupported_schema` |
| 6 | another pairing of schema, connection type and `native`; a `NativeIntent` outside its rules | `invalid_profile` |
| 7 | `profile_id`, a value of `StationConfig` or the `Endpoint` outside its rule | `invalid_profile` |
| 8 | a lock held by another process | `profile_in_use` |
| 9 | a lock that cannot be taken for another reason | `resource_unavailable` |
| 10 | the largest snapshot the profile could ever give is over `profileHttpMaxBytes` | `invalid_profile` |

The folder is taken by its real place, so every name of it is the same folder. The two
locks are held until the process ends, however it ends; a lock file left behind holds
nothing. A copy of a folder with the same `profile_id` is refused like the folder itself. A
device entry that is no endpoint id ends no start. A managed radio without `radio` is read
with `RadioConfig::agc` slow. A temporary file beside `profile.json` is not used.
An outcome other than `ready` and `created` is written to the output, beginning with its
name and a colon (then "selected profile" and the folder, where one was named), and ends
the process with an exit code other than 0 before the station listens. The web adapter and the station service add their own reasons.

### Creating (`CreateProfile`, `NativeProfile`)

| Command | Result |
|---|---|
| `--create-profile` and a folder | the folder is made new and `profile.json` written with the values of a new profile; the process ends with `created`, exit code 0, and runs no station |
| `--create-native-flex-profile` with a folder, an antenna and at most an address | the same, with `schema_version` 2, `native_flex` and a `NativeIntent` of a new `client_id` |
| a folder that exists (also empty), a parent that does not exist, a file that cannot be written | `resource_unavailable`; what exists is left |
| an antenna or an address outside the rules | `invalid_runtime_configuration`; no folder |

A start with `--profile` makes no profile.

### Saving (`SaveSettings`, `KeepMemory`, `EndpointIds`, `NativeProfile`)

The first of these that holds refuses a `SaveProfile`.

| # | Condition | Refusal | Field |
|---|---|---|---|
| 1 | `profileId` no UUID | `invalid_settings` | none |
| 2 | a value of `StationConfig` outside the rule its definition gives, in the order `display_name`, `audio.input_device`, `audio.output_device`, `control.mode`, `control.rig`, `control.endpoint`, `control.ptt`, `radio`, then transmit's and receive's values (`transmit.tuneSeconds`) | `invalid_settings` | the first |
| 3 | on a native profile: a device, a control mode other than disabled, a control endpoint, a ptt other than disabled | `invalid_settings` | the first |
| 4 | an input that is no capture endpoint id, an output that is no render endpoint id | `audio_device_not_endpoint` | the device |
| 5 | another profile | `wrong_profile` | |
| 6 | the file cannot be written | `storage_unavailable` | |

A save that is not refused writes the whole file anew beside `profile.json`, makes it
durable and puts it in place in one step; only then is it answered. Until that step the saved profile is the one before, and a save that fails
leaves no file behind. A process that stops while it saves leaves the whole old or the
whole new document. `profile_id`, `endpoint`, `connection_type` and `native` never change.
A station config without `RadioConfig::agc` for a managed radio keeps the saved one. The
station config has one maintainer, its station's browser: saves are carried out one after
the other, and the later one stands.

### The operator's folder and settings (`OperatorFolder`, `SaveOperatorSettings`)

The operator's folder is `WSTX-Rust\operator` in the account's local application data, or
the folder `--operator` names; it is made at station start when missing, and one that
cannot be made or used ends the start with `resource_unavailable`. A station changes a file
of it only while it holds that file's lock, for the change alone; another station waits.
When another station has changed `operator.json` or the strategies file, the profile reads
it anew and gives its snapshot.

| # | A `SaveOperator` is refused when | Refusal |
|---|---|---|
| 1 | a value of `OperatorSettings` is outside its rule, in the order callsign, locator, continent, cq_words, then spots' and udp's values | `invalid_settings` with the field |
| 2 | `expectedRevision` is not the revision of `operator.json` | `revision_conflict` |
| 3 | the file cannot be written | `storage_unavailable` |

A save not refused writes `operator.json` with the revision one higher, under the lock, in
one step, and is answered with the new `OperatorSnapshot`. Without a file the settings are
their defaults at revision 0; a file that cannot be used gives the defaults with
`unusable` true and is left until the next save.

### A settings collection (`CollectionRule`, `StrategiesFile`, `StrategyCheck`)

| Collection | Key | Rules (of the part) | Kept in | Answered with |
|---|---|---|---|---|
| `strategies` | the name, without regard to letter case | `WstxStrategies::StrategyForm` | `strategy.json` in the operator's folder | `DefinitionsSnapshot` |
| `udpTargets` | the address | `UdpTarget`, `UdpConfiguration` | `operator.json` | `OperatorSnapshot` |

| # | A command is refused when | Refusal |
|---|---|---|
| 1 | the member is outside its part's rules | `invalid_settings` with one value |
| 2 | create: the key is held; update to another key that is held | `entry_exists` |
| 3 | create: the collection holds as many members as its rules allow | `collection_full` |
| 4 | update, delete: the key is not held | `entry_unknown` |
| 5 | `expectedRevision` is not the revision of the collection's file | `revision_conflict` |
| 6 | the file cannot be written | `storage_unavailable` |

A command not refused writes the file with the change and the revision one higher, in one
step; a member keeps its place, a new one goes to the end. The strategies file is one JSON
object with `schema_version` 4, `revision` and `configuration` (the saved strategies,
`active` null, no `contest`), read at station start by `StrategyReading`; one with
`profile_id` is read without it; one that cannot be used gives no strategy, `unusable`
true, and is left until the next change.

The hidden store (`KeepMemory`): read when the profile is opened and given as
`MemorySnapshot`; a store never kept gives every record as its definition gives it. A
`SaveMemory` is kept whole and made durable before it is answered; one that cannot be kept
is answered with the store of before. Keeping it does not change the document. The
profile reads no record.

An endpoint id is `{0.0.1.00000000}.{GUID}` for an input and `{0.0.0.00000000}.{GUID}`
for an output. A device entry of an older file that is no endpoint id is taken as it is and
not changed; audio finds no endpoint of it, and the operator chooses the device again.

### An import (`ImportLifecycle`, `ImportState`)

| State | Does | Leaves by |
|---|---|---|
| `reserved` | has an id and no file | first part: `receiving`; `CancelImport`: `cancelled` at once; `reservationMs` or `uploadTotalMs`: `cancelling` (`upload_timeout`) |
| `receiving` | adds each part to its file | the part that completes the file: `validating`; `CancelImport`: `cancelling` (`cancelled`); `uploadIdleMs` or `uploadTotalMs`: `cancelling` (`upload_timeout`); a part that fails: `cancelling` with its error |
| `validating` | makes the file durable, reads it as `WavForm`, writes its description | valid: `committing`; a fault of `WavForm` or a failed step: `cancelling` with it; `CancelImport`: `cancelling` (`cancelled`) |
| `committing` | puts `current.json` in place in one step; from then on the file is the stored recording; removes the files of the one before | done: `completed`; a failure after the step: `cancelling` (the new recording stays stored) |
| `cancelling` | removes the files of the import | removed: `cancelled` when its error is `cancelled`, else `failed`; not removed, or not in time: `failed` with `storage_unavailable`, and `storage_error` is set |
| `completed`, `cancelled`, `failed` | the ends; `ImportView` keeps showing the import | the next reservation, or the station's stop |

Until `current.json` is in place, the stored recording is the one of before. When the
station stops, an import that has not ended is gone with its files.

### Which command is carried out (`ImportAdmission`)

| Command | Refusals, in order |
|---|---|
| `ReserveImport` | `busy` (`notReleased`); `storage_unavailable` (`storage_error` set); `busy` (`jobRunning`, an import not ended, or files of an ended import still being removed) |
| `ImportChunk` | `request_too_large` (total over `fileBytes`); `not_found`; `upload_timeout`; `cancelled`; `state_conflict` (another part being taken, `start` not the bytes taken so far, another `total`); `invalid_state` (neither reserved nor receiving) |
| `CancelImport` | `not_found`; `invalid_state` (committing); an ended import is answered as it is |
| `ReadImport` | `not_found` |

An admitted reservation takes the place of the import
that ended last. A `CancelImport` is answered at once, before the files
are removed.

### The stored recording (`StoredRecording`)

| At station start | Result |
|---|---|
| `current.json` names a UUID, the description is that recording's, the file reads as `WavForm` with the stated length and samples | stored |
| no `current.json` and no file named by a UUID and `.wav` or `.json` | none stored |
| anything else | cannot be read: `source_error` `recording_unavailable`, no `recording`, until an import is completed |

At station start and after every import each file of `recordings` that does not belong to
the stored recording is removed; while `current.json` does not tell which is stored, the
files named by a UUID are kept. A folder that cannot be made, read or cleared sets
`storage_error`, which ends when the files of an import have been removed or with a
station start that finds the folder in order. `OpenRecording` for a file that does not
open, does not read as `WavForm` or has another count of samples is answered
`RecordingUnreadable`, and the recording cannot be read from then on.

## 6. Implemented in and tested by

The part names `server/src/profile.rs`. CL-005-04, CL-005-02, CL-005-05 and CL-013-08 also
name `server/src/main.rs`; CL-044-05 names `server/src/radio_setup.rs` and
`server/src/radio_control/setup.rs`; CL-006-01 and CL-006-05 name `server/src/recording.rs`,
CL-006-06 that and `server/src/recording_http.rs`. The model names no set of detail tests
for the profile.

## 7. What it relies on from outside

| Element | Needed from it |
|---|---|
| `WstxRadioControl::ControlSelection` | the three features of the radio control in the document and their values in a new profile |
| `WstxStrategies::Strategy`, `StrategyForm`, `StrategyReading`, `ConfigurationKeys` | a strategy, its rules, how its file is read, the names of its values |
| `WstxUdpControl::UdpTarget`, `UdpConfiguration`; `WstxHearing::SpotsConfig` | the shared configurations of udp and spots and the rules of a target |
| `WstxRequirements` FR-001, FR-016, FR-018, FR-022 | the requirements the clauses derive from |

Named in text without an element: "a radio connection of radio control's catalogue" (when
a radio is managed); the origin of the station, under which the largest snapshot is
measured; the reasons the web adapter and the station service add to a start; the folder
`recordings` and the files of the other functions; `--profile` and the two creation
commands as the arguments of the process.

## 8. Differences from a named reference

Reference: WSJT-X at the behaviour baseline.

| Topic | WSJT-X | This product | Recorded as |
|---|---|---|---|
| One instance | one lock file in the temporary folder, named by application and rig name; offers to remove a lock left behind | locks on the folder and on the identity; a lock left behind needs no removal | deliberate (`ProfileOwnership`) |
| Saving settings | each setting written as it changes | all settings of the station together | deliberate (`SaveSettings`) |
| Several instances | each instance (`--rig-name`) its own settings and log | the stations of one operator share one folder with the shared settings and the logbook | not recorded as a difference in the model |
| A new configuration | settings made at the first start; further configurations inside one settings file | a command of its own, a folder of its own | deliberate (`CreateProfile`) |
| A WAV file | opened from any place and decoded at once | taken into the folder first; receive shows it as a spectrum | deliberate (`StoredRecording`) |

The document's identity follows RFC 9562 and its file RFC 8259; `WavForm` follows the RIFF WAVE specification; `EndpointIds` follows the Windows Core
Audio endpoint id.

## 9. Verification

| Case | Verifies | Shows | Declares |
|---|---|---|---|
| TC-022-001 | CL-005-02, CL-005-05, CL-044-05 | which station settings are taken and refused, that a save of one profile touches no other, the change of a device name to its id | cost 2, development PC, implemented; `tests/profiles.test.cjs` and three named tests |
| TC-022-002 | CL-005-02, CL-005-04, CL-005-05 | creation, saves that outlast a stop, files that are no profile, a save that fails or is cut off at each step, the largest snapshot; planned, no test yet: the configurations of transmit and receive and the records of the hidden store after a stop and a start | cost 2, development PC, implemented; `tests/profiles.test.cjs` and two named tests |
| TC-022-003 | CL-005-01, CL-005-04 | one process for a profile through any name and copy, a file that cannot be read or written | cost 2, development PC, implemented; `tests/profiles.test.cjs` and one named test |
| TC-022-011 | CL-005-07 | the callsign and locator taken and refused; planned, no test yet: two stations of one operator's folder, a stale save, a QSO seen by both, the folder made and named | cost 2, development PC, implemented; `tests/profiles.test.cjs` and one named test |
| TC-039-001 | CL-039-01 | a strategy created by name; a key more, a name twice and a 17th refused | cost 2, development PC, implemented; one named test (it asserts the whole save) |
| TC-039-003 | CL-039-01 | the strategies file after a create; a strategy of a class that does not exist; planned: update, delete, unknown name | cost 2, development PC, implemented; one named test |
| TC-097-002 | CL-039-01 | files of versions 1 to 4 as they are read; the names read; unusable files | cost 2, development PC, implemented; four named tests |
| TC-097-001 | CL-097-01 | every value at its bounds is taken; each refusal names its value; the names of the built-ins refused | cost 2, development PC, implemented; three named tests |
| TC-023-007 | CL-013-08 | the document of the native connection, what is refused in it, its creation | cost 2, development PC, implemented; two named tests |
| TC-018-001 | CL-006-01 | files taken in byte for byte, their samples as blocks, the same recording after a station start | cost 2, development PC, implemented; one named test and two test files |
| TC-018-002 | CL-006-01, CL-006-05, CL-006-06 | files that are no recording, imports that fail at each step, run out of time or are cancelled, the folder after a fault | cost 2, development PC, implemented; six named tests and one test file |

Every clause has a case, except CL-005-06 (the hidden store), which no test shows yet:
its planned line stands in TC-022-002.

## 10. Open points, gaps and disagreements

### Marked by the model

| Where | Marker | Says |
|---|---|---|
| `OperatorConfig::cq_words` | not stated | how many words the list holds |
| `NativeIntent` | not stated | the control interface of the adapter that defines this configuration: `NativeControlPort` names no item that carries it, so its three values are defined in `ProfileAccess` |

### Gaps

| Element | Missing | In the model or only in the files read | Assumed |
|---|---|---|---|
| `OpenProfile`, `StartupOutcome::endpoint_in_use` | which part ends a start with `endpoint_in_use`, and the other reasons of the web adapter and the station service | only in the files read (their parts are not built) | nothing |
| `RadioConfig` | what "reads as a radio connection of radio control's catalogue" means | only in the files read | nothing |

### Disagreements and observations

- (Answered 2026-11-15: the profile has one port to the station service.)
- `Station.sysml` types `web.recording` to `station.upload` with `RecordingTransferLink`
  as well; the items of that interface are those of an import between the station service
  and the profile.
- `RecordingUnreadable` has no feature.
- `ImportError` holds `recording_unavailable`, which no command of an import is refused
  with; it is the value of `RecordingStatus::source_error`.
- Weak links: the files of other functions in the folder, `WstxReceiveJob::Admission`.
- `SaveRefused::field` names values of `StationConfig` in words, not by a typed element.
