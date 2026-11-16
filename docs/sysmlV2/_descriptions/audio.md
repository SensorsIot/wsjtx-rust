# Audio

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the five files of `backend/audio/`,
`interfaces/internal/AudioControl.sysml`, `interfaces/internal/AudioStreams.sysml`,
`interfaces/external/SoundDevice.sysml`, and of `Station.sysml`, `Context.sysml` and
`interfaces/internal/StationTime.sysml` only the lines that attach audio. Not read: the
code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Radio connection | where the receive audio comes from: the sound device of a radio on USB, or the native network connection of a radio | `AudioInterface` |
| Packet | a run of frames as the radio connection delivers them | `NativePacket` |
| Receive stream | the audio audio gives to receive: mono, 12 kHz, full scale 1 | `SampleBlock`, `CaptureStream` |
| Epoch | a stretch of the receive stream without a loss of unknown length; frames count from 0 in each | `EpochProposal` |
| Gap of known length | frames missing between two packets whose places are known | `NativePacket::firstFrame` |
| Glitch | a packet flagged as a discontinuity that still continues the packet before it in place and time | `CaptureStream`, `CaptureMarks` |
| Tie | the station time at which the first frame of an epoch stands | `CaptureClock` |
| Drift | how far, and how fast, the capture clock moves away from the tie | `CaptureClock`, `AudioStatus` |
| Endpoint | one capture or render endpoint of the PC, named by its id | `Endpoint`, `EndpointEntry` |
| Program | what transmit gives audio to play: a waveform, or a tone | `PlayProgram` |

"State" has two meanings, each with its own type: the state of the capture (`AudioState`)
and the state of the output (`OutputState`).

## 2. Place in the system

| Port of audio | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `status` | `AudioStatusPort` | station service, `audioStatus` | `AudioControl` | in: `AudioDevices`, `AudioMemory`, `ListEndpoints`; out: `AudioStatus`, `EndpointList`, `ListRefused`, `AudioMemory` |
| `time` | `~StationTimePort` | clock, `time` | `StationTimeLink` | in: `StationTime` |
| `receive` | `ReceiveSamples` | receive, `audio` | `ReceiveSamplesLink` | out: `EpochProposal`, `SampleBlock`, `CaptureMarks`, `StreamFailure`; in: `StartCapture`, `StopCapture`, `EpochAccepted` |
| `transmit` | `~Playback` | transmit, `audio` | `PlaybackLink` | in: `OpenOutput`, `PlayProgram`, `SetScale`, `StopOutput`; out: `OutputStatus`, `PlayRefused` |
| `device` | `~AudioExchange` | audio adapter, `host` | `AudioExchangeLink` | in: `NativeFormat`, `NativePacket`; out: `RenderFrames` |
| `native` | `~CaptureSamples` | Flex adapter, `samples` | `CaptureSamplesLink` | in: `NativeFormat`, `NativePacket` |

The audio adapter (`AudioDeviceAdapter`) stands beside audio. Its port `device`
(`SoundDevicePort`) is joined to the sound device of the context by `SoundDevice`: in the
active `Endpoint`s and the `CaptureStream`, out the `RenderStream`.

The Flex adapter is present only on a profile that uses a FlexRadio through its native
API. Audio's packets come from one of the two connections, by the profile's radio type.
The receive stream is the same for both. A sound device is listed, opened and played to
only on the USB connection.

Audio cannot reach the profile, radio control, the modes part or the radio's control path.
What it needs of the first two comes from the station service: its configuration, the two
endpoints the operator chooses (`AudioConfig`, given in `AudioDevices`), its records
(`AudioRecords`, given in `AudioMemory`) and the place of the radio's serial port
(`RadioPlace`). Audio defines the configuration and the records; the profile keeps them.

## 3. Purpose and requirements

Audio turns the packets of the radio connection into the receive stream, keeps that stream
tied to station time, plays the transmit program, and lists the sound endpoints. All five
clauses derive from FR-002, which `Station.sysml` gives to audio.

| Clause | Promise | Element | Status |
|---|---|---|---|
| CL-008-02 | give receive the audio as one mono 12 kHz stream in which every loss is marked and no sample is made up | `CaptureStream` | implemented |
| CL-007-11 | tie the frame count of each epoch to station time, follow the drift, warn when the tie is missing or the drift is high | `CaptureClock` | implemented |
| CL-008-08 | capture from the sound device the profile names, report the state, open it again after a loss | `DeviceLifecycle` | implemented |
| CL-009-06 | play the program on the output device the profile names, report when all of it is played or the device is lost | `ProgramPlayback` | implemented |
| CL-044-07 | list the sound endpoints by name, so the operator can tell them apart and sees which belongs to the radio | `EndpointNaming` | implemented |

## 4. Data and rules

### Packets (`NativeFormat`, `NativePacket`)

| Field | Rule |
|---|---|
| `rate` | 44100 or 48000 Hz |
| `channels` | 1 or 2; channel 0 is used |
| `encoding` | float32, pcm16, pcm24, pcm32 |
| `frames` | 1 to 8192 |
| `firstFrame` | the place in the connection's own count; a place beyond the expected one is a gap of known length |
| `arrivalTime` | on the PC's monotonic clock; absent when the connection cannot say, the packet then starts a new epoch |
| `silent` | no samples delivered; the frames count as zeros and as measured |
| `discontinuity` | frames may be missing before this packet |

### The receive stream (`CaptureStream`)

| Rule | Value |
|---|---|
| level changed by at most 0.1 dB | up to 3500 Hz |
| level lowered by at least 60 dB | from 5500 Hz |
| a sample stands at its place in the packets | to within one frame of the stream |
| the stream does not depend on how frames are cut into packets | |
| audio holds audio that receive has not taken | up to 500 ms and 64 packets; more is a loss (`queueFull`) |
| a flagged packet continues in time | when its arrival time is within 2 ms of the time expected |

| Occasion | Result |
|---|---|
| gap of known length | the frames of the gap are left out, the count runs on, the next block is marked |
| a packet audio could not take; a packet without arrival time; a packet that steps back; a jump of the PC clock; a flagged packet that does not continue in time | the epoch ends; a new one starts and names the cause (`CaptureEvent`); untaken samples of the old epoch are discarded |
| a flagged packet that continues in place and time | stays in the stream, block not marked, frames counted as glitch frames |
| a silent packet | zeros; frames counted as zero-filled |
| every `CaptureEvent` | counted |

An epoch (`EpochProposal`) has a number, a reason (`captureStart`, `captureLoss`), a trigger (absent
for a start) and the arrival time of its first packet (absent when that packet has none).
No sample of an epoch is sent before receive has taken the epoch up (`EpochAccepted`,
by its number; another number is refused with `staleAcknowledgement`). A
stream that fails says why (`SourceError`); after `unavailable` it goes on with a new
epoch when the connection is open again.

### The capture clock (`CaptureClock`)

| Rule | Value |
|---|---|
| an epoch is tied when its first packet has an arrival time and the PC clock was read around a monotonic reading | within 2 ms |
| the station time of a frame | its PC clock time plus the clock's correction |
| a jump of the PC clock against the monotonic clock ends the epoch (`clockStep`) | beyond 20 ms |
| distances from the tie are averaged | over about one second |
| the tie is moved to the averaged distance | when it moved by more than 50 ms |
| a distance from the average restarts the average and the rate | beyond 200 ms |
| the rate of the drift is known | after 60 s of the stream |
| warning `driftHigh` | while the known rate is beyond 1000 ppm, either way |
| warning `uncorrelated` | while the capture runs and the epoch is not tied |
| no epoch, or capture not running | no warning |

### The sound device (`DeviceLifecycle`, `SoundDevicePort`)

| Rule | Value |
|---|---|
| the device is the capture endpoint of `AudioConfig::input_device`; no other is opened | |
| a capture without a named endpoint | refused, `unavailable` |
| a device failing with `unavailable` while wanted is opened again | first after 1000 ms, then twice as long each time, up to 8000 ms; a new start begins at 1000 ms |
| every other error | ends the capture until it is started again |
| every opening | starts a new epoch |
| a stop is answered with `closed` or `failedClose` | within 250 ms |
| a device that does not close | `unavailable` with `failedClose`; closing is tried again; not opened meanwhile |

### Playback (`ProgramPlayback`, `PlayProgram`)

| Rule | Value |
|---|---|
| the device is the render endpoint of `AudioConfig::output_device`; rate of program and device | 48000 Hz, one or two channels |
| a device that has not opened | unavailable after 1000 ms |
| a program is kept queued at the device | up to 100 ms |
| silence queued without a program | at most 20 ms |
| a device that takes no sample while a program plays | `deviceLost` after more than 500 ms |
| audio waits for the device to close after `StopOutput` | up to 250 ms |
| the program goes to every channel, each sample times the scale, limited to full scale | |
| `PlayProgram` is taken in the state ready, once for each opening | otherwise `PlayRefused`: the error of a failed output, else unavailable |
| `SetScale` | from the next sample; a tone keeps its phase |

### The endpoint list (`EndpointNaming`, `EndpointEntry`)

| Field | Rule |
|---|---|
| `name` | the friendly name, runs of blanks made one, none at its ends, after "(" or before ")" |
| `label` | the name; same-named present endpoints of one list get " #n" by the order of their ids; the radio's endpoint ends with " — " and the model |
| `radio` | the model, for the one endpoint of a list at the radio's place (`RadioPlace`: the same container, or the same USB hub that is not a root hub); absent with none or several there, and without a `RadioPlace` |
| `present` | false for an endpoint the profile names that is not there: label "<name> · not present" or "Unknown device · not present" |

The configuration (`AudioConfig`): `input_device` and `output_device`, each absent or the
id of an endpoint of its direction (a text of 1 to 256 bytes; for an input
`{0.0.1.00000000}.{GUID}`, for an output `{0.0.0.00000000}.{GUID}`), each set by itself.

Kept data: the record `AudioRecords::lastNames` holds the last known name of each endpoint
of `AudioConfig`, and no other. Audio renews it at station start and with every list and
hands the changed record over to be kept (`AudioMemory`); the profile keeps it in the
hidden store. Without a record no name is known. The list is refused with
`deviceLimit` beyond 64 endpoints in a list or for an id or name that is empty or longer
than 256, and with `audioUnavailable` when the endpoints cannot be read.

## 5. Behaviour

Capture state (`AudioState`): closed, opening, running, closing, unavailable. The model
gives the meaning of each state and the rules of `DeviceLifecycle`; it has no state
machine.

Output state (`OutputState`): opening, ready (silence), playing, finished (every sample
played), failed (`OutputError`: unavailable, unsupportedFormat, deviceLost), closed. A
waveform plays from its sample `skip` to its last; a tone plays until stopped.
`StopOutput` ends the program at once, also during an opening.

## 6. Implemented in and tested by

| Element | Module |
|---|---|
| `AudioInterface` | `server/src/audio.rs`, `server/src/transmit/playback.rs`, `server/src/source.rs` |
| `AudioDeviceAdapter` | `server/src/audio/windows.rs`, `server/src/modes/playback/windows.rs` |
| CL-044-07 | `server/src/radio_setup.rs`, `server/src/radio_control/setup.rs` |

The model names no detail tests for audio.

## 7. What it relies on from outside

Used and not defined here: station time (`WstxStationTime::StationTime`); FR-002; the
profile's radio type; the two endpoints and the radio's place, given by the station
service; the waveform of the modes part (mono, 48 kHz, peak 1).

Outside sources: Windows Core Audio (MMDevice API and WASAPI, shared mode, event driven).

## 8. Differences from a named reference

None stated.

## 9. Verification

| Case | Shows | Verifies | Level | Test |
|---|---|---|---|---|
| TC-002-001 | the receive stream from scripted packets, 16 conditions | CL-008-02 | 2, development PC | `server/tests/audio_contract.rs`, `server/tests/audio_receive.rs` |
| TC-007-011 | the tie to station time, 4 conditions | CL-007-11 | 2, development PC | four named tests in `audio_contract.rs`, `recording_tests.rs`, `clock_http_tests.rs` |
| TC-002-003 | the capture from a sound device: state, loss, end; 6 conditions | CL-008-08 | 2, development PC | `server/tests/audio_contract.rs` |
| TC-008-004 | a program on a scripted output device, 5 conditions and 3 planned | CL-009-06 | 2, development PC | three named tests in `server/tests/transmit_service.rs` |
| TC-044-006 | names, labels and remembered names, 6 conditions and 1 planned | CL-044-07 | 2, development PC | `server/src/radio_control/setup_tests.rs`, `server/src/radio_setup_tests.rs` |

Four conditions are written as planned, with no test yet: `deviceLimit` (TC-044-006 g), a
refused `PlayProgram`, the 1000 ms of opening an output and the 250 ms of `StopOutput`
(TC-008-004 f to h).

## 10. Open points, gaps and disagreements

Markers in the model: none.

Gaps found while writing this view:

1. The tie needs the clock's correction; `StationTime` carries the time and its state,
   and the correction only as part of that time.
2. Whether `StartCapture` and the warnings apply on the native connection as on the sound
   device: `CaptureClock` and `CaptureStream` are written for both; `DeviceLifecycle` for
   the sound device only. The state of the capture on the native connection is the Flex
   adapter's and not yet written.
3. `StartCapture`, `StopCapture`, `OpenOutput` and `StopOutput` carry no field: each is
   an event with nothing to say beyond itself. `RenderFrames` and the two streams of
   `SoundDevice` are frames in the device's own format.
4. What a second `OpenOutput` is answered with.

Disagreements: none between the files read.
