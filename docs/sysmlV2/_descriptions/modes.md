# The modes part

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: `backend/modes/Modes.sysml`,
`Decode.sysml`, `MessagePayload.sysml`, `MessageEncode.sysml`,
`interfaces/internal/ModeProcessing.sysml`, and of `Station.sysml` and
`interfaces/internal/Decodes.sysml` only the lines that attach the part. Not read: the
code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Mode | FT4 or FT8 | `Mode` |
| Period | the time slot of a mode; even or odd | `Period`, `PeriodParity` |
| Window | the samples of one decode request, at 12 kHz, at most 30 s | `ProcessingRequest::samples` |
| Frame | one transmission of one message; as a result, one decoded frame | `ProcessingResult` |
| Payload | the 77 bits of a message | `ProcessingResult::payload77` |
| Family | the kind of message a payload holds | `PayloadFields`, `MessageFamily` |
| Hash | a call sent as a number of 10, 12 or 22 bits | `CallValue` |
| Context | what the station knows before a window is decoded | `APrioriContext` |
| A-priori type | which expected message helped a decode, 1 to 6 | `ProcessingResult::a_priori` |
| Lowest tone | the audio frequency a frame is placed at | `frequency_hz`, `toneZeroHz` |

"Decoded" has two meanings, each with its own element: a frame that was found (it is
returned), and the status of a payload that could be read (`FrameStatus::decoded`). A
returned frame may have the status unsupported or invalid_payload.

## 2. Place in the system

From `Modes.sysml`, `Station.sysml`.

**Position:** station, backend, station process, `modes`.

**Neighbours**

| Neighbour | Connection | Direction | Item |
|---|---|---|---|
| receive | `receiveModem` | receive to modes | `ProcessingRequest`, `Cancel`, `CallsUpdate` |
| receive | `receiveModem` | modes to receive | `ProcessingResult`, `WindowEnd` |
| transmit | `encodeModem` | transmit to modes | `EncodeRequest`, `AcceptedMessage` |
| transmit | `encodeModem` | modes to transmit | `Waveform`, `EncodeRefusal` |

**Not connected:** every other part. The modes part has no connection to audio, to the
radio, to the clock, to the profile, to the log or to the browser link. It cannot read a
device, a file, the network or the time; everything it works on arrives in a request.

**Limit:** `Cancel` carries nothing, by intent: one request runs at a time.

## 3. Purpose and requirements

The part decodes the FT8 and FT4 frames of a window, turns each payload into a message
with its fields, shows hashed calls it has learned, and turns a message into audio.

| Identity | Requirement | From | Status the model declares |
|---|---|---|---|
| CL-007-03 | The decoder MUST decode the FT8 and FT4 frames of a window as the published protocol defines their payload, channel code and waveform. | FR-004 | implemented |
| CL-007-06 | The decoder MUST decode at least the share of frames of each mode, with the accuracy of start, frequency and SNR, that the quality table states. | FR-004 | implemented |
| CL-007-07 | The decoder MUST return no frame from noise, from silence, from a signal of the other mode or from a word whose CRC fails. | FR-004 | implemented |
| CL-007-08 | The decoder MUST return the same frames in the same order whenever it is given the same request. | FR-004 | implemented |
| CL-007-04 | The decoder MUST decode on the processor within the stated time and memory, and end a window that exceeds a limit with the error that names the limit. | FR-004 | implemented |
| CL-057-02 | The decoder MUST leave one logical processor to the other functions of the station and return the same frames in the same order on any number of threads. | FR-004 | implemented |
| CL-007-10 | The decoder MUST try the messages the station expects, by its context, on a candidate that did not decode without help, and return such a frame only with a valid payload and enough confidence. | FR-004 | implemented |
| CL-007-09 | The payload function MUST give every returned frame exactly the fields of a decoded frame, with the fields of its message family. | FR-004 | implemented |
| CL-024-01 | The payload function MUST show a hashed call as the call itself once the station has learned that call, and as <...> until then. | FR-004 | implemented |
| CL-009-01 | The encoder MUST turn a message of every supported family into the FT8 audio that WSJT-X sends for it, and refuse a message that it cannot send unaltered. | FR-005 | implemented |
| CL-011-01 | The encoder MUST turn a message of every supported family into the FT4 audio that WSJT-X sends for it, with the packing and the refusals of FT8. | FR-005 | implemented |

## 4. Data and rules

### 4.1 The mode and its period (`Mode`, `Period`, `PeriodParity`, `DecodeBand`)

| | FT8 | FT4 |
|---|---|---|
| Period length | 15000 ms | 7500 ms |
| Nominal start of a frame after the period start | 500 ms | 452 ms, counted to the leading ramp symbol |
| Length of a frame | 12640 ms | 5040 ms, with its two ramp symbols |

A period starts where UTC is a whole multiple of the period length. It is even when its
start divided by the period length is even, and odd otherwise. The DT of a decoded frame
is its start against the nominal start. The lowest tone of a decoded frame lies between
200 Hz and 3500 Hz, both included.

### 4.2 A decode request (`ProcessingRequest`, `APrioriContext`, `StationCalls`)

| Field | Type | Absent means |
|---|---|---|
| mode | `Mode` | – |
| samples | up to 360000 numbers: mono, 12 kHz, each finite | – |
| origin frame | place of the first sample in its 12 kHz stream | – |
| period start frame | place of one period start in that stream | the stream is not tied to station time |
| continuous | true for continuous receive, false for a recording | – |
| context: my call | text | the profile has no callsign |
| context: DX call | text | no contact |
| context: progress | calling, replying, report, roger report, rogers, signoff | – |
| context: receive and transmit audio frequency | Hz | – |
| context: CQ only | true while the station has not transmitted for some time | – |

The context is fixed for the whole window. `CallsUpdate` carries the same two calls; it
is given at station start and whenever one of them changes.

### 4.3 A decoded frame (`ProcessingResult`)

| Field | Type | Rule |
|---|---|---|
| status | decoded, unsupported, invalid_payload | see 5.2 |
| payload77 | 77 characters 0 and 1 | always present |
| i3, n3 | numbers | n3 only when i3 is 0 |
| text | at most 80 ASCII characters | only when the status is decoded |
| fields | one variant of `PayloadFields` | only when the status is decoded |
| start_frame | place of the frame's first symbol in the 12 kHz stream | the ramp symbol for FT4 |
| frequency_hz | the lowest tone | within 200 to 3500 Hz |
| snr_db | whole dB on the 2500 Hz scale of WSJT-X | absent for a frame not wholly inside the window, and without a noise baseline |
| a_priori | 1 to 6 | absent for a frame decoded without help |

**The fields by family** (`PayloadFields` and its variants)

| Family | Variant | Fields |
|---|---|---|
| 0.0 free text | `free_text` | value: 1 to 13 characters |
| 0.1 DXpedition | `dxpedition` | first, second, hashed call; report |
| 0.3, 0.4 Field Day | `field_day` | to, from, ack, transmitters, class, section |
| 0.5 telemetry | `telemetry` | value: 18 hexadecimal digits |
| 1, 2 standard | `standard` | to, from, ack, exchange (blank, grid, report or roger) |
| 3 RTTY | `rtty` | tu, to, from, ack, report, exchange (serial 0 to 7999, or state or province) |
| 4 nonstandard | `nonstandard` | full call, hashed call, hash second, cq, roger |
| 5 EU VHF | `vhf` | to, from, ack, report, serial, grid |
| 0.2, 0.6, 0.7, 6, 7 | none | status unsupported |

A call (`CallValue`) is a call, a token (CQ, DE, QRZ, a CQ modifier) or a hash. A hash has
its width and value; its text is the call the station has learned for it, and absent
until then.

### 4.4 An encode request and its answer (`EncodeRequest`, `Waveform`, `EncodeRefusal`)

A request carries the text, the mode, the lowest tone in Hz and the sample rate (12 kHz or
48 kHz). It is answered at once by one of two items.

| Answer | Carries |
|---|---|
| `Waveform` | the packed message (normalized text, 77 bits, i3, n3, family) and the samples: mono, peak 1, from the first sample of the frame to its last |
| `EncodeRefusal` | one reason, below |

| Reason | When |
|---|---|
| empty | nothing is left of the text after it is normalized |
| tooLong | more than 37 characters, or a free text of more than 13 |
| invalidText | a character that no supported family can carry |
| unsupportedFamily | a family the station does not send (DXpedition, WSPR) |
| notExact | a receiver would show the message differently from the text |
| roundTripMismatch | the packed bits do not unpack to the normalized text |
| frequencyOutOfRange | the tones would leave the audio band of the mode |

The families sent: standard, portable, nonstandard, free text, telemetry, Field Day, RTTY
Roundup, EU VHF.

### 4.5 The waveforms (`Ft8WaveformContract`, `Ft4WaveformContract`)

| | FT8 | FT4 |
|---|---|---|
| Lowest tone accepted | 200 to 2950 Hz | 200 to 2916.666667 Hz |

With such a lowest tone all tones lie within 200 Hz to 3000 Hz. The channel code, the
tones and the waveform are those of the reference. The FT4 waveform holds one ramp symbol
before the tones and one after them.

### 4.6 Quality and resources (`DecodeQuality`, `DecodeBudgets`, `DecodeThreads`, `Repeatability`, `FalseFrames`)

| Quality | FT8 | FT4 |
|---|---|---|
| Strong level, weak level | -15 dB, -18 dB | -10 dB, -13 dB |
| Signals of a level that decode | at least 90 % strong, 50 % weak | the same |
| Pairs two tone spacings apart, both decode | at least 90 % | the same |
| Pairs one spacing and 6 dB apart | the stronger in at least 90 %, the weaker in at least 50 % | the same |
| Start within | 240 frames | 144 frames |
| Frequency within | 1 Hz | 3 Hz |
| Reported SNR | -25 to 60 dB | -21 to 60 dB |

A reported SNR lies within 1 dB of what the decoder of WSJT-X reports for the same frame,
and for a strong signal within 3 dB of its true SNR. Two runs of one request give the same payloads in the same order, each start within
1 frame and each frequency within 0.2 Hz (FT8) or 0.5 Hz (FT4).

| Resource | Limit | At the limit |
|---|---|---|
| A window of 15 s of FT8 | 5 s | – |
| A window of 7.5 s of FT4 | 3 s | – |
| A recording of 120 s | 40 s | – |
| The first decode after a start | 2 s longer | – |
| Four stations decoding at once | 2 times the time of one | – |
| Memory of one decode | 64 MiB | – |
| Growth of the station process | 96 MiB | – |
| Looking for a `Cancel` | every 50 ms | – |
| End of a cancelled request | 250 ms after its `Cancel` | – |
| Candidates in one window | 256 | one more: `searchLimited` |
| Frames returned | 2048 | one more: `decodeLimit` |
| Size of one frame as JSON | 1024 bytes | a larger one is not returned: `decodeLimit` |
| Threads | the logical processors less one, at least one | – |

The times and the memory hold on the reference PC (AMD Ryzen 9 3900X, 32 GB, Windows 11)
with one decode thread for each station.

## 5. Behaviour

### 5.1 Decoding a window (`DecodeWindow`, `DecodeError`)

| Situation | Result |
|---|---|
| a window shorter than one frame of its mode | no frame |
| an FT8 frame inside the window, or reaching out by at most half a symbol at either end | returned; one that starts before the window gets the window's first sample as its start |
| an FT4 frame inside the window | returned |
| a frame reaching further out | not returned |
| a frame with the payload of an earlier one, starting within half a symbol of it | not returned again, in the same window or, in continuous receive, in a later one |
| a word that fails the parity check or the CRC | no frame |

Frames come back one by one while the request runs; `WindowEnd` follows the last. The
frames returned before it stay valid.

| Error in `WindowEnd` | When |
|---|---|
| none | the whole window was searched |
| cancelled | receive withdrew the request |
| invalidSamples | a sample is not a finite number, or a window of continuous receive starts before the one before it |
| searchLimited | more candidates than the decoder searches |
| decodeLimit | the window is longer than 30 s, or a frame exceeds the limits of what one request may return |

### 5.2 From payload to fields (`UnpackPayload`)

| Payload | Status | Text and fields |
|---|---|---|
| family 0.2, 0.6, 0.7, 6 or 7 | unsupported | none |
| a supported family, content inside its domain | decoded | the family's variant |
| a supported family, content outside its domain | invalid_payload | none |

A standard message whose grid field holds RR73 has the exchange roger RR73.

### 5.3 Decoding with the context (`APrioriHypotheses`)

Tried on a candidate that did not decode without help, by the progress of the contact.

| Condition | Effect |
|---|---|
| CQ only is set | only the CQ type is tried |
| a type names my call | tried only with a call that packs exactly as the call of a standard message |
| a type names the DX call | tried only with such a DX call as well, and within 50 Hz of the receive frequency and, for FT8, of the transmit frequency |
| a frame is found | returned only with the status decoded and a confidence of at least 0.17; an FT8 frame of the CQ type needs no confidence |

**Every other candidate stays undecoded.**

### 5.4 Hashed calls (`HashResolution`)

One table of calls exists for each station process, for as long as it runs.

| Occasion | The table learns |
|---|---|
| a `CallsUpdate` | my call |
| a frame returned | the sending call of a standard message; the full call of a nonstandard message whose hash is the call addressed |
| an `AcceptedMessage` | each call of a standard (without /R or /P), Field Day or RTTY message; the call of a nonstandard CQ; each call in angle brackets |

A call is learned from 3 characters upward.

| Hash | Shown as |
|---|---|
| its call is known | the call in angle brackets; the call is the text of the `CallValue` |
| its call is not known | `<...>`, no text |
| two calls share a 10-bit or 12-bit hash | the one learned last |
| it equals the hash of my call | my call, wherever WSJT-X fills my call in, also after 1000 other calls |
| it equals the hash of the DX call of the latest `CallsUpdate` | that DX call, wherever WSJT-X applies its DX call |

A frame keeps the text it was returned with when its call is learned later. The table
shows the 1000 calls learned last for a 22-bit hash; for a 10-bit and a 12-bit hash a call
stays known for as long as the process runs.

### 5.5 From text to audio (`PackMessage`)

1. The text is normalized: upper case, one blank between words, none at the ends.
2. The family is chosen in the order of WSJT-X.
3. The packed bits are unpacked again; the message is packed only when that gives the
   normalized text.
4. The bits get the CRC and the parity (for FT4 after scrambling) and become tones; the
   waveform holds the symbols and nothing before or after them.

**A text that fits no family is sent as free text when it has at most 13 characters of the
free-text alphabet, and is refused otherwise.**

## 6. Implemented in and tested by

| Function | Modules |
|---|---|
| Decode | `server/src/decoder/mod.rs`, `search.rs`, `subtraction.rs`; `server/src/modes/decoder/`: `apriori.rs`, `baseband.rs`, `bitmetrics.rs`, `channel.rs`, `coarse_ft4.rs`, `fit.rs`, `history.rs`, `parallel.rs`, `physical_ft4.rs`, `physical_sync.rs`, `snr.rs`, `synchronization.rs`, `waveform.rs` |
| Payload | `server/src/decoder/payload.rs`, `server/src/modes/decoder/hashes.rs` |
| Encode | `server/src/transmit/pack.rs`, `server/src/modes/transmit/mod.rs`, `waveform.rs` |

Detail tests are named for the decode function: nine test files beside the decoder's
modules and `server/tests/modes/decoder_live.rs`. The model names none for the payload and
the encode function.

## 7. What it relies on from outside

| Element | Needed from it |
|---|---|
| `WstxRequirements::'FR-004'`, `'FR-005'` | the requirements the clauses derive from |
| `WstxRequirements::BehaviorBaseline` | the WSJT-X release that "the behaviour baseline" means |
| QEX, The FT4 and FT8 Communication Protocols; WSJT-X | the payload, the channel code, the waveform, the packing order, the a-priori types and the confidence, the hash rules |

Named in text with no element behind the name: "candidate", "confidence", "noise
baseline", "the free-text alphabet". The first three are terms of the reference.

## 8. Differences from a named reference

Reference: WSJT-X at the behaviour baseline. All are recorded as deliberate.

| Topic | WSJT-X | This product |
|---|---|---|
| SuperFox | decodes SuperFox frames in Hound mode | does not |
| Second FT8 decoder | runs one when its option is on | has its own decoder only |
| Accepting a word | checks the CRC | checks the parity as well |
| A-priori word of low confidence | shown with a question mark | not returned |
| A-priori types 7 and 8 | tried after the last FT8 pass | types 1 to 6 only |
| A compound call of the station in the context | packed as a hash | taken as absent |
| Learning sent calls | from its DX call field | from the messages transmit accepts |
| The DX call for hashes | from its DX call field | from the station's current contact |
| A text that fits no family | cut down to 13 characters of free text | refused |

## 9. Verification

| Case | Verifies | Shows | Declared |
|---|---|---|---|
| TC-004-001 | CL-007-03, CL-007-06, CL-007-10 | FT4: every family, the band ends, the quality counts, the sample recording, a-priori types 1 and 6 | level 2, development PC, implemented; four named tests |
| TC-004-002 | CL-007-03, CL-007-06, CL-007-10 | FT8: the band ends, the quality counts, the sample recording, 401 of 409 frames from the air, frames at the window's edges, one payload on two carriers, a-priori types 3 and 6 | level 2, development PC, implemented; ten named tests |
| TC-004-003 | CL-007-04, CL-007-07, CL-007-08 | no frame from noise, silence, the other mode or a wrong CRC; the border 256 and 257 candidates; the times and the memory; two equal runs | level 2, development PC, implemented; eight named tests |
| TC-057-002 | CL-057-02 | the same frames on 1, 4 and 12 threads; shared work in order; a cancel during shared work | level 2, development PC, implemented |
| TC-004-005 | CL-007-09 | payloads at the borders of their fields; the status of an unsupported and an invalid payload | level 2, development PC, implemented; three named tests |
| TC-024-001 | CL-024-01 | what the table learns and fills in, my call, 1000 calls, two calls with one hash, accepted messages | level 2, development PC, implemented |
| TC-024-002 | CL-024-01 | hashed calls in the frames a station publishes, before and after the call is known, and after my call changes | level 2, development PC, implemented |
| TC-024-010 | CL-024-01 | the DX call in a DXpedition message | level 2, development PC, implemented |
| TC-005-001 | CL-009-01 | FT8: bits and tones against WSJT-X, the refusals, the waveform at both rates, the band borders, the round trip through the decoder | level 2, development PC, implemented |
| TC-005-002 | CL-011-01 | FT4: the same | level 2, development PC, implemented |

Every requirement of section 3 has a case. No case states that it ran.

## 10. Open points, gaps and disagreements

**Marked by the model:** none.

**Gaps**

- **How long "some time" is** for CQ only (`APrioriContext::cqOnly`), and how the progress
  follows the contact: not in the files read. The function that builds the context states
  them; it is not built in this tree yet.
- **`DecodeError::decodeLimit`** names "the limits of what one request may return" in
  words; the values are `DecodeBudgets::recordCap` and `recordMaxBytes`. The interface
  cannot refer to the part's file, so the link is by text only.

**Disagreements and observations**

- `PeriodParity` is defined here and used by no element of the modes part; transmit and qso
  use it.
- `Period` holds the nominal start and the frame length, which the modes part itself does
  not use: the decoder returns a start in frames, and receive forms the DT.
- `Decodes.sysml` types its `ResultRecord` as a `ProcessingResult` with a sequence number.
  `DisplayData.sysml` types a spectrum frame as a `ProcessingResult` too, which would give
  it the fields of a decoded frame.
- The interface text on `snr_db` does not give the lowest and highest value; `DecodeQuality`
  does.
- No detail tests are named for the payload and the encode function.
