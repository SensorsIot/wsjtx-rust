# Flex adapter

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the two files of
`backend/flexAdapter/`, `interfaces/external/FlexApi.sysml`, of
`interfaces/internal/AudioStreams.sysml` the port `CaptureSamples` with its two items, of
`interfaces/internal/RadioControl.sysml` the port `RadioControl`, and of `Station.sysml` and
`Context.sysml` only the lines that attach the adapter. Not read: the code, the issues, the
old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Radio | a FlexRadio reached over its own network API | `FlexApiPort` |
| Announcement | what a radio says about itself on the local network, unasked | `Announcement` |
| Saved address | the address and port of one radio, named by the profile | `NativeIntent::radioAddress` |
| Intent | what the profile says about its FlexRadio: client identity, receive antenna, saved address | `NativeIntent` |
| Session | the control connection to one radio with the client, the slice and the receive stream the adapter has there | `SessionLifecycle` |
| Handle | what the radio gives the adapter for one control connection; the radio names owners by it | `Greeting::handle` |
| Slice | the receiver the adapter asks the radio for | `SliceFacts` |
| Stream | the radio's DAX receive stream of that slice | `StreamPacket` |
| Turn | the place of one stream packet in the order of its count | `StreamIntake` |
| Packet (to audio) | a run of frames as audio takes them from any radio connection | `NativePacket` |
| Tune | bring the slice to a frequency and have the radio confirm it | `TuneSlice` |

"Packet" has two meanings, each with its own type: a packet of the radio's stream
(`StreamPacket`) and a packet given to audio (`NativePacket`).

## 2. Place in the system

Position: `Station` > `backend` > `stations` (one station process) > `flexAdapter`. The
part is present only on a profile that uses a FlexRadio through its native API (`[0..1]`).

| Port of the adapter | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `radio` | `FlexApiPort` | the FlexRadio of the context, `link` | `FlexApi` | in: `Announcement`, `Greeting`, `Reply`, `StatusLine`, `StreamPacket`; out: `CommandLine`, `Registration` |
| `samples` | `CaptureSamples` | audio, `native` | `CaptureSamplesLink` | out: `NativeFormat`, `NativePacket` |
| `control` | `~RadioControl` | radio control, `backend` | none (the connection `nativeControl` is marked in `Station.sysml`) | in: a `ControlRequest`; out: a `ControlOutcome` |

Limits: the model names radio control as the neighbour on `control` but not the items
exchanged: no item carries the intent, a tune or the session status
(marker 2 in section 10). `CaptureSamples` has no item for the input status (marker 3).
`StreamDiagnosis` has no connection that carries it out (marker 1).

Not connected: the station service, the profile, receive, transmit, the clock, the modes
part, the web adapter, the CAT adapter and the sound device. The adapter learns the
profile's intent only over `control`; nothing reaches the adapter
from transmit, and the sound device is not used on this connection.

## 3. Purpose and requirements

The adapter holds one session with a FlexRadio, takes up only what is free or its own
there, gives the radio's receive stream to audio as packets, tunes its slice on request,
and sends the radio nothing but the commands of that receive session. All seven clauses
derive from FR-023, which `Station.sysml` gives to the adapter.

| Clause | Promise | Element | Status (declared) |
|---|---|---|---|
| CL-013-01 | hold one session with the radio over its own network API, and report its state | `SessionLifecycle` | implemented |
| CL-013-02 | take up a radio only when it speaks the version of the API the station speaks, whatever its model and firmware | `ApiAdmission` | implemented |
| CL-013-03 | build every session from the profile's intent alone, and take up a radio, a client identity and a slice only when the radio shows them free or the adapter's own | `RadioChoice`, `SessionSetup` | implemented |
| CL-013-04 | change only the slice it created and take samples only from the stream it created, as long as the radio reports them under the adapter's handle | `OwnResources` | implemented |
| CL-013-05 | send the radio the commands of its receive session and no other, so that nothing it sends keys the radio or reaches another client | `ReceiveOnly` | implemented |
| CL-013-06 | give audio the radio's receive stream as packets of the form audio takes from any radio connection, with every known loss filled or flagged | `StreamIntake` | implemented |
| CL-013-07 | tune its own slice on request and give a frequency as confirmed only when the radio's own report of the slice shows it | `TuneSlice` | implemented |

## 4. Data and rules

### The API (`FlexApiPort` and its items)

The station speaks version 1.4.0.0 of the source (`ProtocolVersion::admitted`). Layouts,
ports and codes are the source's and are not repeated in the model.

| Item | Direction | What the station does with it |
|---|---|---|
| `Announcement` | in | reads serial, model, firmware version, address, port and `availableClients` (absent when the radio does not say); one without a serial is not used; the station sends none and asks for none |
| `Greeting` | in | `version` and `handle`, stated by the radio when the control connection opens |
| `CommandLine` | out | one of `Command`; the next is sent after the `Reply` to the one before |
| `Reply` | in | matched by the number the source puts on both; `code` 0 is done, every other code a refusal |
| `StatusLine` | in | of a client: handle, client identity, disconnected; of a slice: in_use, client_handle, RF_frequency, mode, rxant, dax, index_letter, removed; of a stream: type, dax_channel, client_handle, removed; everything else is passed over |
| `Registration` | out | a datagram from the stream's UDP port naming the client's handle; opens the way back for the stream |
| `StreamPacket` | in | one format is taken: two channels of 32-bit float at 24 kHz; `streamId`, `count` (0 to 15 and round again) |

| `Command` | The source's text |
|---|---|
| `info` | info |
| `subClientAll` | sub client all |
| `clientStartPersistenceOff` | client start_persistence off |
| `clientGui` | client gui, with a client identity |
| `subSliceAll` | sub slice all |
| `subDaxAll` | sub dax all |
| `clientUdpport` | client udpport, with a UDP port of the PC |
| `sliceCreate` | slice create, with rxant and mode |
| `sliceSet` | slice set, with a slice number and dax or mode |
| `streamCreate` | stream create type=dax_rx, with dax_channel |
| `sliceTune` | slice tune, with a slice number and a frequency in MHz to the hertz |
| `sliceRemove` | slice remove, with a slice number |

The adapter sends these and no other (`ReceiveOnly`).

### The intent (`NativeIntent`)

| Field | Form |
|---|---|
| `clientId` | 36 characters, each a hexadecimal digit or a hyphen |
| `rxAntenna` | 1 to 16 capital letters, digits and underscores |
| `radioAddress` | optional; absent means the adapter finds a radio by its announcement |

An intent outside these forms starts no session. A session is built from the intent and
from the frequency last confirmed, and from nothing else.

### The session's status (`SessionStatus`, `RadioFacts`, `SliceFacts`)

| Field | Rule |
|---|---|
| `state` | one of `SessionState` |
| `error` | one of `SessionError`; present in the states unavailable and conflict |
| `radioCode` | the code of the last `Reply` that refused a command in the current attempt or session |
| `session` | the number of sessions that became ready; a higher number voids every handle, slice number and stream identity read before |
| `radio` | serial, model, firmware, protocol, address; absent until a radio is chosen; shown and compared with nothing |
| `slice` | index, letter, frequencyHz, mode, rxAntenna, daxChannel, streamId, observedAt, as the radio last reported them; present in the state ready |
| `retryAfterMs` | the wait before the next attempt; present in unavailable and conflict |

A change of any field is reported at once.

### The diagnosis of the stream (`StreamDiagnosis`)

Read on request; no part of the status; every field starts over when a session becomes
ready.

| Field | Counts or measures |
|---|---|
| `accepted` | stream packets given on to audio |
| `foreign` | datagrams from another address than the radio's or under another stream identity |
| `invalid` | datagrams and lines that cannot be read, stream packets of another format or with a sample that is not finite |
| `lost` | turns given up |
| `late` | stream packets discarded |
| `lastPeak` | the largest magnitude of channel 0 in the packet last given on |
| `timestampKind`, `hostMinusRadioMs` | the kind of time stamp on the radio's last packet, and the PC clock minus it; measured only |
| `jitterMeanMs`, `jitterMaxMs` | how far the spacing of the packets is from their length: smoothed, and the largest |

### Values

| Value | Is | Element |
|---|---|---|
| 5 s | the radio's time to take the connection, to answer a command, to report what is awaited | `SessionLifecycle::stepSeconds` |
| 1000 ms | the wait before the first new attempt, and after a session that was ready | `SessionLifecycle::firstRetryMs` |
| 4000 ms | the longest wait; each further attempt waits twice as long up to it | `SessionLifecycle::maxRetryMs` |
| 3 s | how long one attempt listens for announcements | `RadioChoice::listenSeconds` |
| 5 s | the spacing of the registrations on a saved address | `RadioChoice::keepAliveSeconds` |
| 48000 Hz | the rate of the packets given to audio | `StreamIntake::outputRateHz` |
| 5 packets | waiting behind a missing turn before it is given up | `StreamIntake::reorderPackets` |
| 200 ms | a longer pause between two stream packets is a loss of unknown length | `StreamIntake::unknownGapMs` |
| 10 ms | stream packets are gathered until a packet to audio holds this much | `StreamIntake::groupMs` |

## 5. Behaviour

### The session (`SessionLifecycle`, `SessionState`)

| State | Holds when |
|---|---|
| discovering | an attempt has begun and the adapter looks for a radio; with a saved address this state is passed at once; the state at station start |
| connecting | a radio is chosen and the session is being set up |
| ready | the slice and the stream are the adapter's; packets go to audio, the slice can be tuned |
| unavailable | the last attempt or session failed with an error that is no conflict |
| conflict | it failed with clientIdentityInUse, ownershipAmbiguous, sliceOwnership or daxChannelConflict |
| stopped | the station has ended |

The model gives the meaning of each state and the rules below; it has no state machine.

- From station start on the adapter chooses a radio and sets the session up.
- A ready session ends with resourceLost, daxChannelConflict or transportLost.
- After a failure the next attempt follows after the wait of `retryAfterMs`.
- The adapter ends a session by closing the control connection and relies on the radio
  to release the client's slice and stream.

| `SessionError` | When |
|---|---|
| discoveryUnavailable | the adapter cannot listen for announcements |
| radioNotFound | no radio announced itself |
| capacityClients | every radio that announced itself takes no further client |
| incompatibleApi | the radio speaks another version than the admitted one |
| clientIdentityInUse | another client of the radio carries the profile's client identity |
| ownershipAmbiguous | the radio attributes a slice to the adapter before the adapter created one |
| capacitySlices | the radio has no slice to give |
| sliceOwnership | the radio reports the created slice as another client's |
| antennaUnavailable | the created slice has another antenna than the profile names |
| capacityDax | every DAX channel is in use |
| daxChannelConflict | a slice with a lower number uses the adapter's DAX channel |
| radioRefused | the radio refused a command; `radioCode` holds the code |
| transportLost | the control connection did not open, or it ended |
| protocolError | the radio sent what the adapter cannot follow |
| timeout | a greeting, a reply or an awaited status did not come within 5 s |
| resourceLost | the radio does not report the slice or the stream as the adapter's any more |

### Which radio (`RadioChoice`, `ApiAdmission`)

| Situation | What the adapter does |
|---|---|
| the intent has a saved address | connects to that radio alone, listens for no announcement; the radio's facts come from its answer to `info`, asked after the version check |
| no saved address | listens for announcements for 3 s, on every address of the PC unless `WSTX_FLEX_DISCOVERY` names another address and port; several stations of one PC listen at the same time; takes the first radio whose `availableClients` is not 0, at the address and port announced |
| only radios without a free client heard | capacityClients |
| none heard | radioNotFound |
| the adapter could not listen | discoveryUnavailable |
| the radio states another version than 1.4.0.0 | incompatibleApi before the first command; the status shows the version stated |
| a radio of any model and firmware on the admitted version | taken up |

The adapter tells the radio the UDP port of its stream and no address. On a saved address
it sends a `Registration` from that port right after, and again every 5 s;
`WSTX_FLEX_REGISTER_PORT` names one port of the radio in place of the source's two.

### Setting a session up (`SessionSetup`)

In: the intent. Out: the status. A failure ends the attempt with the error named; a
refused command is radioRefused where no other is named; a wait beyond 5 s is timeout.

| Step | What happens | Failure |
|---|---|---|
| 1 | the control connection is opened and the greeting read | transportLost |
| 2 | the version check | incompatibleApi |
| 3 | `subClientAll`, then `clientStartPersistenceOff`, whose reply shows that the list of clients has arrived | a client carrying the profile's client identity (capitals disregarded): clientIdentityInUse, before `clientGui` is sent |
| 4 | `clientGui` with the client identity, `subSliceAll`, `subDaxAll` | a slice in use attributed to the adapter's handle: ownershipAmbiguous; the slice is left as it is |
| 5 | `clientUdpport` | |
| 6 | `sliceCreate` with the profile's antenna and the mode DIGU, without a frequency; created when a status shows it in use under a handle | reply code 50000001, 50000003 or 5000001D: capacitySlices; another handle: sliceOwnership; another antenna: the slice is removed, antennaUnavailable |
| 7 | the DAX channel is the lowest of the source's eight that no reported slice uses; `sliceSet` unless the slice has it; a status must show it | none free: the slice is removed, capacityDax |
| 8 | `streamCreate` for that channel; the stream is the adapter's when a status shows a DAX receive stream of that channel under the adapter's handle | refused: the slice is removed, radioRefused; a reply naming another stream: protocolError |
| 9 | with a frequency confirmed before, the slice is brought to it as a tune does | a failure ends the attempt |
| 10 | ready; `session` is one higher | |

### What is the adapter's own (`OwnResources`, `ReceiveOnly`)

- The adapter's handle is the one of the current session's greeting. A handle, a slice
  number and a stream identity of an earlier session count for nothing.
- Every `sliceSet`, `sliceTune` and `sliceRemove` names the adapter's own slice.
- A stream packet is taken when it comes from the address of the session's radio and
  carries the identity of the adapter's stream; every other datagram is counted as
  foreign and discarded.
- What the radio cannot give is reported as capacityClients, capacitySlices or
  capacityDax; what another client holds stays as it is.
- Of two sessions that chose one DAX channel at the same time, the one with the higher
  slice number ends with daxChannelConflict and chooses again.
- With its commands the adapter asks for a receiver and a receive stream, tunes that
  receiver and gives it up.

### From stream packets to audio's packets (`StreamIntake`)

| Occasion | Result |
|---|---|
| a stream packet of the adapter's stream | each frame stands twice; the format given to audio is 48000 Hz, two channels, float32 |
| another format, or a sample that is not finite | discarded, counted invalid |
| a packet ahead of its turn | waits |
| a turn whose packet is missing, with 5 packets waiting behind it | given up: filled with zeros of one stream packet's length, counted lost; audio takes the zeros as samples |
| the packet of a turn given up arriving later; a packet arriving twice | discarded, counted late |
| eight or more stream packets lost in a row | the next ones are discarded as late until the count has come round |
| a pause of more than 200 ms between two stream packets | a loss of unknown length: what waits is given on first, the count starts over, the packet to audio has `discontinuity` |
| the first packet of a session that follows a lost one | has `discontinuity` |
| outside the state ready | no packet is given |

| Field of `NativePacket` | Rule |
|---|---|
| `firstFrame` | counts every frame given to audio, the zeros of turns given up among them; runs on from one session to the next |
| `arrivalTime` | when the first stream packet of the packet arrived at the PC, less the length of that packet and of the turns given up before it; the radio's time stamp is measured and not used; when the PC's clock cannot be read the time runs on from the packet before, and without one the field is absent |
| `silent` | false in every packet |
| `discontinuity` | as in the table above |
| length | stream packets are gathered until a packet holds 10 ms or more; a stream packet that brings `discontinuity`, or has no arrival time, ends the packet before it early and starts a new one |

### Tuning (`TuneSlice`, `TuneRefusal`)

In: `frequencyHz`. Out: `confirmedHz` or a `refusal`.

| Step | Rule |
|---|---|
| read first | the mode and frequency of the slice as last reported are compared with DIGU and the frequency asked; `sliceSet` and `sliceTune` are sent only for what differs; with nothing to write no command is sent |
| after a write | `subSliceAll`, since a radio may answer a tune and report nothing |
| confirmed | when a status of the slice shows the frequency together with DIGU |
| deadline | the status must come by the deadline of the request, and at most 5 s after the tune began |
| status | the slice facts show the slice as the radio reports it before the answer is given, after a confirmation and after a refusal |
| kept | the frequency last confirmed is kept until the station ends; every later session brings its slice to it |

| `TuneRefusal` | When |
|---|---|
| radioTimeout | the radio did not answer or did not report the frequency in time |
| radioRejected | the radio refused a command |
| radioUnavailable | the session is not ready, is lost during the tune, or serves another tune |
| cancelled | the request was withdrawn before or while it was served |

## 6. Implemented in and tested by

| Element | Module |
|---|---|
| `FlexAdapter` | `server/src/flex/mod.rs`, `server/src/flexAdapter/session.rs`, `server/src/flexAdapter/wire.rs` |

Detail tests: `server/src/flexAdapter/wire_tests.rs` and
`server/src/flexAdapter/session_tests.rs`, for the reading of the radio's lines,
announcements and packets, the adapter's record of the radio's clients, slices and
streams, the text form of a frequency, and the measurement of a packet's time stamp.

## 7. What it relies on from outside

Used and not defined here: FR-023; `NativeFormat` and `NativePacket` of the audio streams;
`Encoding` of the sound device interface; the port type `RadioControl`; the profile's
intent, which reaches the adapter over `control`.

Named in text with no element behind the name: the environment variables
`WSTX_FLEX_DISCOVERY` and `WSTX_FLEX_REGISTER_PORT`.

Outside sources: the SmartSDR TCP/IP API at the admitted version, with FlexLib 4.3.16 as
its reference implementation; discovery and stream packets in the form of ANSI/VITA 49.0.
The adapter relies on the radio to release a client's slice and stream when its control
connection closes.

## 8. Differences from a named reference

None stated.

## 9. Verification

| Case | Shows | Verifies | Level (declared) | Test |
|---|---|---|---|---|
| TC-023-001 | the session, the stream and the tuning on a radio that several stations share; 23 conditions and 1 planned | CL-013-01, -02, -04, -05, -06, -07 | 2, development PC, automated | `tests/flexAdapter/native-flex.test.cjs` and ten named tests in `session_tests.rs` and `wire_tests.rs` |
| TC-023-002 | a session from the profile's intent alone: a restarted radio, an occupied identity, an ambiguous slice, the next free radio, no radio, the return to the selected frequency; 8 conditions and 1 planned | CL-013-01, -03, -04, -07 | 2, development PC, automated | `tests/flexAdapter/native-flex.test.cjs`, `session_tests.rs::intent_domains` |
| TC-023-003 | what the radio cannot give: slices, clients, the version, a full radio on a saved address; 4 conditions and 4 planned | CL-013-01, -02, -03, -04 | 2, development PC, automated | `tests/flexAdapter/native-flex.test.cjs` |

Every clause has a case. Written as planned, with no test yet: a tune withdrawn and a tune
outside the state ready (TC-023-001 x); the waits between attempts (TC-023-002 j);
antennaUnavailable, capacityDax, sliceOwnership and resourceLost, discoveryUnavailable
(TC-023-003 e to h).

## 10. Open points, gaps and disagreements

Marked by the model (`NotStated`):

1. On the part: which connection carries `StreamDiagnosis` out of the adapter; radio
   control takes `SessionStatus` only, and the adapter has no port toward the station
   service.
2. On the port `control`: which items of the control connection carry the profile's
   `NativeIntent`, the request and the answer of `TuneSlice`, and `SessionStatus`; the requests and outcomes of `RadioControl` name none
   of them.
3. On the port `samples`: which item carries the input status to audio (that the session
   is not ready, and when the next attempt follows); `CaptureSamples` carries the format
   and the packets only.

Gaps found while writing this view:

1. The model states no frequency range for a tune: a frequency the radio does not take
   is the radio's refusal (radioRejected).
2. `Registration`, `CommandLine` beyond its command, and `StatusLine` carry no typed
   field; their content is the source's.
3. `SessionSetup` and `TuneSlice` name "the frequency last confirmed", which no element
   holds as data; it is kept inside the adapter.

Two gaps of the first writing were repaired in the model: the error of a refused
`streamCreate` (radioRefused), and the state `discovering` on a saved address.

Disagreements and observations:

- Weak links (a name in text only): the environment variables; `SessionLifecycle` names
  `SessionStatus::retryAfterMs` and the elements of the other clauses in its text.

- None between the files read.
