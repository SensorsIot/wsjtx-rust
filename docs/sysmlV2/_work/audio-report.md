# Report: the audio part

2026-11-15. Third part built by the method. Tests 1 to 5 pass. The operator has answered
the twelve open lines (last section); one stays open, the thread priority.

## What was written

| File | Content |
|---|---|
| `backend/audio/Audio.sysml` | the audio part with six ports, and the audio adapter |
| `backend/audio/Capture.sysml` | 2 clauses, 2 rule elements, 2 test cases: the receive stream and the capture clock |
| `backend/audio/AudioDevice.sysml` | 1 clause, 1 rule element, 1 test case: the capture from a sound device |
| `backend/audio/Playback.sysml` | 1 clause, 1 rule element, 1 test case |
| `backend/audio/Endpoints.sysml` | 1 clause, 1 rule element, 1 test case |
| `interfaces/internal/AudioStreams.sysml` | packets in, the receive stream out, the program to play |
| `interfaces/internal/AudioControl.sysml` | commands of the station service, the capture state, the endpoint list |
| `interfaces/external/SoundDevice.sysml` | the sound endpoints, following Windows Core Audio |
| `Station.sysml` | three connections follow the new ports, one import added; the recording goes to receive, not to audio |

## The two radio connections

The operator, while the part was built: the FlexRadio is a different module and handles
audio very differently from the USB connection. What the code shows, and how the model is
cut by it:

| | Sound device (USB) | Native connection (Flex) |
|---|---|---|
| Where packets come from | WASAPI capture endpoint, through the audio adapter | the radio's DAX stream over UDP, through the Flex adapter |
| Port of audio | `device` (`AudioExchange`) | `native` (`CaptureSamples`) |
| Opening, loss, reopening | `DeviceLifecycle`, CL-008-08 | the Flex session; not audio's |
| Endpoint list | CL-044-07 | none |
| Playback | CL-009-06 | none (the code reports transmit as unsupported) |
| From packet to receive stream | `CaptureStream`, CL-008-02 | the same: the code feeds both through one queue, converter and epoch count |
| Capture clock | `CaptureClock`, CL-007-11 | the same rules; arrival times come from the Flex adapter |

So two clauses are common (the stream, the clock) and three are of the sound device only.
Nothing about DAX, VITA-49, 24 kHz or lost-packet counting is written here; it is on the
Flex adapter's handover list. The old model joined both connections to one port
`backend`; the new model has one port for each.

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-044-07 | audio/Endpoints | Endpoints | Keeps its core: the list by name. Its route and reply are handed to the station link. Derives from FR-002 only (was FR-002, FR-019). |
| TC-044-006 | audio/Endpoints | Endpoints | Rewritten from its two tests. |
| CL-008-02 | receive/LiveReceive | Capture | The ledger sent it to receive by its old file. Its text is the receive stream, its code is `audio.rs`, and FR-002 is audio's: it is audio's clause. Derives from FR-002 only (was FR-002, FR-003, FR-004). |
| TC-002-001 | profile/Profile | Capture | "Canonical live audio": verifies CL-008-02 only now (was CL-008-01, -02, -03). |
| TC-002-003 | receive/LiveReceive | AudioDevice | "Audio without CAT": keeps the capture state, loss and end; verifies CL-008-08 (was CL-008-02, CL-008-05). |
| **CL-008-08** | new | AudioDevice | The sound device half of CL-008-03 (states, loss, recovery) and of CL-008-05. |
| **CL-007-11** | new | Capture | The capture clock, from CL-007-05 and CL-043-03, handed over by the clock part. |
| **TC-007-011** | new | Capture | The capture steps of TC-004-004 and TC-092-003. |
| **CL-009-06** | new | Playback | Playing the program, from CL-009-03 (`AudioPlayback`, the render values of `TransmitTiming`). |
| **TC-008-004** | new | Playback | The three render tests of TC-008-003. |

The five new numbers are the next free ones of the series each was split from. No rule of
the foundation says how a new identity is numbered; see the first line for the operator.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Which clauses are audio's | A model file follows the thing; FR-002 is given to audio; samples pass through audio (M5.9) | CL-008-02 moves from receive. Playback and the capture clock get clauses here. |
| The capture clock is audio's although receive's code follows the drift | The handover list of the clock part; a model file follows the thing | `CaptureClock` here; the difference is work for the code. |
| One port for each radio connection | A shared end names what arbitrates it (structure rule 4); the operator's remark on the Flex | `device` and `native`; `Station.sysml` follows. |
| Transmit's connection to audio had the adapter's interface | A connection is named after what flows and typed by it (M5.8) | New `Playback` port and `PlaybackLink`; `Station.sysml` follows. |
| The items on the ports were empty or one general `SampleBlock` | An item on a connection has features (structure rule 1) | Typed from the code: packet, epoch, block, marks, failure, the playback commands and status. |
| What the station service gives audio | M5.3; only the station service is joined to the profile | `AudioDevices` (the profile's two endpoints) and `ListEndpoints` with `RadioPlace`, on `AudioControl`. |
| Who opens the capture | A stream joins its producer and its consumer directly (M5.4); playback already works so | `StartCapture` and `StopCapture` on the stream connection, from receive, which names no device. |
| WASAPI details | A followed source is referred to, not copied | The source is named once on `SoundDevicePort`; the model states which formats the station takes. |
| The thread priority | The model/code line | Not written. What is noticed outside is stated by `renderBufferMs` and TC-008-004 (e). |
| `PlayRefused` | Every request has its answer (structure rule 2) | Added from the code after the description found the gap. |

## Dropped as code or as history

- The queue's buffers, their reuse and locking; that the I/O thread never waits.
- The filter's length (257 taps) and delay; the model states pass band, stop band and alignment.
- The block length of 240 frames; the frame count's end (it is `counterExhausted`).
- The three flag bits; they are three fields of `NativePacket`.
- COM apartments, the capture thread, the render loop's fill decisions (`Fill`).
- The drain rule of the render buffer as a description; kept as "finished when the device has played every sample" and TC-008-004 (c).
- The level counters of the capture (`native_channel_zero_*`): no test and no reader outside found.
- `DeviceIntent`, the old `SampleBlock` text on ownership and memory, `SourceDescriptor` (receive's identity record; handed over).
- All dates, issue numbers and slice names.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| package `WstxAudio` | `WstxAudioDevice` | `tools/sysml/tests/test_architecture_structure.py`; old profile and receive text |
| package `WstxAudioCapture` | `WstxCapture` | none found in the code |
| package `WstxAudioEndpoints` | `WstxEndpoints` | none found in the code |
| package `WstxAudioPlayback`, action `AudioPlayback` | `WstxPlayback`, `ProgramPlayback` | three comments in `server/src/transmit/playback.rs`, old `TransmitControl` |
| port def `AudioStatus` | `AudioStatusPort`; `AudioStatus` is the item, as the code's struct | `Station.sysml` uses the interface only |
| port `backend` of audio | `device` and `native` | `Station.sysml` (updated) |
| `AudioExchangeLink` between transmit and audio | `PlaybackLink` | `Station.sysml` (updated) |
| `NativeFormat` (enumeration) | `WstxSoundDevice::Encoding`; `NativeFormat` is rate, channels and encoding | the code's names |
| `NativePacket::deviceFrame`, `packetQpc100ns`, `timestampError` | `firstFrame`, `arrivalTime` (absent for a timestamp error) | none |
| `renderStallMs` | `stallMs` | the code's `STALL_MS` |
| `AudioCommand`, `AudioOutcome` | the three commands, `AudioStatus`, `EndpointList`, `ListRefused` | none |

## Negative statements

| Old statement | Result |
|---|---|
| No default-device fallback | positive: "the station opens the endpoint it names and no other" |
| Audio issues no CAT or PTT command; capture never invokes CAT | dropped: audio has no connection to the control path |
| Capture never opens the output; playback never touches CAT | dropped: no such function |
| No disk spool, no audio archiving | dropped: no such function |
| Without fabricating samples or UTC accuracy | kept in CL-008-02 ("no sample is made up"): the converter could pad, and a gap could be filled. The UTC half is positive: an epoch is tied or not tied. |
| A timestamp error or gap is not silence | positive: `silent` frames count as measured zeros; a gap leaves frames out |
| The label never shows the id | dropped: the rule says what the label is |

## Settled from the code

- **Render channels.** The old text said "any channel count". The code takes one or two.
- **Status.** The old test cases were `partial`; every condition written here has a test.
- **Retry.** The wait doubles across successes too; only a new start begins at 1000 ms.
- **`deviceLimit`** is also given for an empty or over-long id or name (256).
- **The tie** is to the PC clock; station time is that plus the clock's correction, which
  receive adds in the code.
- **A stream failure** is not always the end: after `unavailable` the stream goes on with a
  new epoch.
- **`OutputStatus::position`** was written first and removed: nothing in the code gives the
  position to transmit.

## Corrections made after the first run

The operator asked for no shortcuts. The first version passed the five tests while parts
of it were written from the old text or from tests read in part. Read in full afterwards:
`radio_setup.rs` (the list), `setup.rs` (names and labels), both endpoint tests,
`audio_receive.rs`, the format test, the capture controller, the output device code, the
drift test. What changed:

| Was | Is |
|---|---|
| render: any number of channels | one or two |
| "a profile without an input has the state unavailable" | a capture without a named endpoint is refused |
| "no frame is lost, repeated or reordered" by moving the tie | removed: it is receive's promise about its windows |
| `StopOutput` closes within 250 ms | audio waits up to 250 ms |
| `SetScale` for a tone only | for the program that plays |
| scale "from 0 to 1" | no range: the code has none |
| TC-044-006 (b), (e) and TC-007-011 (c) from the old text | from the tests |
| TC-002-001 without the tests of `audio_receive.rs` | conditions (m) to (p) |
| the endpoint list bound to no module | bound to radio control's two modules, 26 verdicts |

## What the comparison with the code found

| Finding | Result |
|---|---|
| The drift of the capture clock is followed in `recording.rs` (receive), with four private constants | Work for the code. Six verdicts. |
| The endpoint list stands in `radio_setup.rs` and `radio_control/setup.rs` | Work for the code. The clause names the two modules. |
| The transmit output's adapter is `server/src/modes/playback/windows.rs`, the function `server/src/transmit/playback.rs` | Work for the code: neither folder is the part. |
| `source.rs` calls itself "canonical receive values" and holds what crosses from audio to receive | Named as audio's module here; receive will name it too. |
| The tool keys a literal by its name alone | `closed`, `opening`, `unavailable`, `unsupportedFormat` occur in two enumerations and `finished` matched `Fill::Finished`. Checked by reading: all five enumerations of the code (`AudioState`, `SourceError`, `CaptureEvent`, `OutputState`, `OutputError`, `Encoding`) have exactly the model's literals. |
| The tool reads public constants only | `MAX_ENDPOINTS` and the drift constants are private; matched by reading. |

## Edge cases and their homes

| Case | Home |
|---|---|
| packet of 0 or more than 8192 frames | `CaptureEvent::invalidPacket`, TC-002-001 (g) |
| receive does not take the stream | `queueMs`, `queuePackets`, TC-002-001 (j) |
| gap of known and of unknown length | `CaptureStream`, TC-002-001 (e), (g), (n) |
| flagged packet at the border of 2 ms | `glitchToleranceMs`, TC-002-001 (h) |
| packet without arrival time | `NativePacket::arrivalTime`, TC-002-001 (f) |
| sample not finite | TC-002-001 (d) |
| the frame count at its end | `SourceError::counterExhausted`; rare and harmless, no condition |
| PC clock jumps | `clockJumpMs`, TC-007-011 (b) |
| drift at the limit | TC-007-011 (d) |
| device missing, lost, not closing | `DeviceLifecycle`, TC-002-003 (a), (e) |
| format not taken | TC-002-003 (f) |
| two endpoints of one name; endpoint not present; file missing | `EndpointNaming`, TC-044-006 |
| more than 64 endpoints | `EndpointNaming`; no test |
| program shorter than the buffer; device stops taking samples | TC-008-004 (c), (d) |
| play in a state other than ready | `PlayRefused`; no test |
| two programs at once | impossible: one program for each opening |

## Not carried over

| What | Why |
|---|---|
| TC-009-002, the capture half (live IC-7300 capture, by hand) | a live case; stays with receive and radio control, handed over |
| TC-002-003 "no audio archiving", "no CAT bytes" | negatives without a function |
| The capture level counters | no reader outside the part found |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| The five files of `backend/audio/` | 10,300 | 27,100 |
| The three interface files | 4,500 | 17,000 |
| CL-008-02, TC-002-001, TC-002-003 (in receive and profile) | 2,900 | in the files above |
| The capture clock in CL-007-05 and CL-043-03; the render values of `TransmitTiming` | not measured apart; CL-007-05 has 2,100 in all | in the files above |
| Total | about 19,000 | 44,100 |

The part is more than twice its old text. The operator allows it where it is needed
(method test 7 is changed). Where the size sits:

| Content | Characters |
|---|---|
| The five test cases (the same three in the old model: 4,400) | 10,800 |
| The three interface files, whose ports carried empty items before | 17,000 |
| Imports, status and level tags, derivations | 4,600 |
| Clauses, rule elements and the two part definitions | 11,700 |

## Checks

- `part_done.py audio`: all five tests pass: 10 identities, no finding of the script, no
  validator error, 32 names matched with the code and 72 lines with a verdict, 5 test
  cases with their tests. `part_done.py clock` and `modes` still pass.
- The validator on `Station.sysml` and `Context.sysml` with the new files reports no
  error on a line that joins audio's ports. All its errors there name parts that are not
  built yet (their types and ports do not exist).
- `git status`: `docs/sysmlV2/` is the only change.

## The functional description

`_descriptions/audio.md`, from the new files alone. It found five gaps.

| Gap | Settled how |
|---|---|
| Which clock reading the tie uses | From the code: the PC clock; station time is that plus the clock's correction. Sentence changed. |
| What a `PlayProgram` outside the state ready is answered with | From the code: refused. `PlayRefused` added. |
| How audio learns the profile's endpoints and the radio's endpoint | First a marker; fixed on the operator's word: the station service gives `AudioDevices` and `RadioPlace`. |
| The capture state on the native connection | The Flex adapter's; on its handover list. |
| Seven items carry no field | Decided, line 9 below. |

## Work for the code, when the new tree goes to main

- The drift tracking and the capture warning move from `recording.rs` to audio.
- The endpoint list moves out of radio control's modules.
- The output device code moves out of `modes/` and `transmit/`.
- The tests of TC-007-011 and TC-008-004 carry the old numbers TC-004-004, TC-092-003 and
  TC-008-003, or none; `audio_contract.rs` cites CL-008-03 and CL-008-05 where the clause
  is CL-008-08 now.
- Three comments in `playback.rs` name `WstxAudioPlayback::AudioPlayback`; a tool test names
  `WstxAudio`.
- Receive and transmit read the device from the profile; in the model the station service
  gives it to audio (`AudioDevices`).
- `source.rs` holds the interface from audio to receive and receive's source records in one
  file.
- The tests read no value from the model. Of the 25 values the tool finds three as
  constants of the code; 22 are matched by reading or stand in another part's module.

## Decided by the operator (2026-11-15)

| # | Line | Answer | Done |
|---|---|---|---|
| 1 | How a new identity is numbered | as recommended: the next free number of its series | In the method under "Decided". |
| 2 | A part larger than its old text | yes, if needed | Method test 7 changed; the report measures the growth. |
| 3 | The port `recorded` | it was probably there for testing | The port left audio. `Station.sysml` joins the recording to `receive.recorded`. What a recording is, is decided with receive. |
| 4 | Audio has no connection to the profile or radio control | fix it | The station service gives `AudioDevices` and, with `ListEndpoints`, `RadioPlace`. The marker is gone. |
| 5 | The capture clock in audio | it is special and belongs to audio alone | Stays; in the method under "Decided". |
| 6 | Who commands audio | asked for a proposal; confirmed | See below. Code change: issue #225. |
| 7 | `AudioStatus` carries the drift and the warning | probably | Stays: audio owns the capture clock, so its drift and warning are audio's facts (M5.1), and state passes through the station service (M5.3). |
| 8 | CL-008-02 moved to audio | right if the arguments are good | Stays. The clause is the receive stream, FR-002 is audio's, the code is `audio.rs`. |
| 9 | Items without a field | mine to decide | An event with nothing to say stays an item with one sentence (`StartCapture`, `StopCapture`, `OpenOutput`, `StopOutput`): it is skeleton. Two got their field from the code: `EpochAccepted::proposal`, `ListEndpoints::radio`. Frames in a device's own format stay without fields. |
| 10 | The thread priority | keep as an issue, discuss later | Not written. Listed in `START-HERE.md` under the open points. |
| 11 | `source.rs` | check | See below. |
| 12 | Promises without a test | note them in the model | Four lines "Planned, no test yet": TC-044-006 (g), TC-008-004 (f), (g), (h). |

### Line 6: the proposal, as written

| What | From | Over | Why |
|---|---|---|---|
| The profile's two endpoints (`AudioDevices`) | station service | `AudioControl` | Only the station service is joined to the profile; a change from outside enters there (M5.3). Receive and transmit then need not know a device or a radio type (M5.9). |
| The request for the endpoint list, with the radio's place | station service | `AudioControl` | An operator's request; the radio's place is radio control's fact and reaches audio through the station service. |
| Open and close the capture (`StartCapture`, `StopCapture`) | receive | the stream connection | A stream joins producer and consumer directly (M5.4). The operator's command is "start live receive", which the station service gives to receive; asking for the stream follows from it. |
| Open, play, stop the output | transmit | the playback connection | The same, and already so. |

This differs from the code in one way: receive and transmit read the device from the
profile themselves. Confirmed by the operator (2026-11-15). The code change is the product
change request #225 on GitHub; it waits until the new tree is on main.

### Line 11: `source.rs`

It holds two things. One is what crosses from audio to receive: the block, the epoch
proposal, the stream's errors, the rule that no sample goes out before the epoch is taken
up. That is the code of the interface `AudioStreams`, used by `audio.rs`, by the Flex
session, and by receive. The other is receive's own record of a source: its identity and
its timing.

The model needs no change: audio owns the interface file, so audio names the module, and
receive does not name it a second time. The code would be clearer if the two halves were
two files, the identity records with receive; its header calls the whole "canonical
receive values". Listed as work for the code; nothing depends on it.

## Not done

- Nothing outside `docs/sysmlV2` was touched.
- `backend/flexAdapter/FlexAdapter.sysml` (taken over) still fits: its port `samples` is
  `CaptureSamples`. Its text is rebuilt with its part.

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
| `interfaces/internal/AudioControl.sysml` | 106 to 153 | 4,558 to 7,075 |
| `backend/audio/Audio.sysml` | 42 to 49 | 1,915 to 2,289 |
| `backend/audio/AudioDevice.sysml` | 73 to 73 | 4,072 to 4,080 |
| `backend/audio/Endpoints.sysml` | 82 to 83 | 4,741 to 4,776 |
| `backend/audio/Playback.sysml` | 92 to 92 | 5,325 to 5,330 |
| `_descriptions/audio.md` | 227 to 234 | 13,840 to 14,390 |

The growth is the configuration and the record types and the form of an endpoint id, which
came from the profile.

Moved in (audio defines them now):

| Element | What |
|---|---|
| `AudioConfig` (new, in `WstxAudioControl`) | the configuration: `input_device`, `output_device`, each with what it does; the rule of the two entries and the form of an endpoint id, from `WstxProfileAccess::AudioSelection` and `WstxProfilePart::EndpointIds`, with the source reference |
| `AudioRecords` (new) | the record `lastNames`: the last known name of each endpoint of the configuration |
| `NamedEndpoint` | moved in from `WstxProfileAccess` |
| `AudioMemory` (new) | the item that carries the records, both ways |
| `AudioDevices` | carries `config : AudioConfig` in place of `input` and `output` |
| `AudioStatusPort` | two items more: `kept` and `keep`, both `AudioMemory` |
| `AudioInterface` | two attributes: `config : AudioConfig`, `records : AudioRecords` |

Left:

| Element | What left |
|---|---|
| `EndpointNaming` | "kept in the profile's file audio-endpoint-names.json"; "a missing or unreadable file means that no name is known". It says: the names are `AudioRecords::lastNames`, renewed at station start and with every list and handed over to be kept |
| TC-044-006 (e) | "the file holds" is "AudioRecords holds"; "the names of the file" is "the names of the record"; 7 lettered lines and 2 tests as before |
| CL-008-08 | "the sound device the profile names" is "the input device of its configuration" |
| `DeviceLifecycle`, `ProgramPlayback` | `AudioDevices::input` and `::output` are `AudioConfig::input_device` and `::output_device` |

No identity is retired or not carried. Test 4 is unchanged (32 matched, 72 with a
verdict).

Differences in the code that test 4 does not show (work for the code): `radio_setup.rs`
(`remember`) reads and writes `audio-endpoint-names.json` itself, through
`profile::Store`; a write that fails is written to the log and the names are used as they
are.

Not decided, for the operator: nothing of audio's own.

Not verified: the body of the test of TC-044-006 (e) was searched for the file name (lines
922 and 960 of `radio_setup_tests.rs`), not read in full again.
