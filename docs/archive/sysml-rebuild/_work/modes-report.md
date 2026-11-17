# Report: the modes part

2026-11-15. Second part built by the method. Tests 1 to 5 pass; six lines wait for the
operator (last section).

## What was written

| File | Content |
|---|---|
| `backend/modes/Modes.sysml` | the part and its two ports |
| `backend/modes/Decode.sysml` | 7 clauses, 7 rule elements, 4 test cases |
| `backend/modes/MessagePayload.sysml` | 2 clauses, 2 rule elements, 4 test cases |
| `backend/modes/MessageEncode.sysml` | 2 clauses, 3 rule elements, 2 test cases |
| `interfaces/internal/ModeProcessing.sysml` | the mode, the period, the decode band; what crosses to receive and to transmit, each item with its fields |
| `interfaces/internal/Decodes.sysml` | reduced: `ResultRecord` is the frame of the modes part plus `sequence` |

## Identities

| Identity | New place | Note |
|---|---|---|
| CL-007-03 | Decode | Keeps its core. Derives from FR-004 only (was FR-003, FR-004, FR-018). |
| CL-007-04 | Decode | The time, the memory and the limits. |
| CL-007-06 | Decode | The quality table. |
| CL-007-07 | Decode | No false frame. |
| CL-007-08 | Decode | The same result every time; its three tolerances moved out of the sentence into `Repeatability`. |
| CL-007-10 | Decode | The a-priori hypotheses. |
| CL-057-02 | Decode | Keeps what another part notices: one processor is left free, and the result does not depend on the thread count. The rest was a description of the code. The priority of the audio threads is handed to audio. |
| CL-007-09 | MessagePayload | The fields of a frame. |
| CL-024-01 | MessagePayload | Keeps its core, the hash table. Its second half, contacts with a nonstandard call, is qso's and **needs a new identity**. Derives from FR-004 (was FR-024, FR-004). |
| CL-009-01 | MessageEncode | FT8 audio. |
| CL-011-01 | MessageEncode | FT4 audio. Its start plan (delay, stale start) is handed to transmit. Derives from FR-005 (was FR-005, FR-006). |
| TC-004-001, -002, -003, -005, TC-057-002, TC-005-001, -002, TC-024-001, -002, -010 | beside their clauses | Rewritten: setup, then one lettered condition per line with one set of values. Each verifies only clauses of this part. |
| TC-006-002 | handed over | transmit (start plan), qso (mode change) |
| TC-024-003 | handed over | qso |
| TC-024-004 | handed over | frontend |

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Where the period stands | Data that crosses a connection belongs to the interface (authoring rule 3); the handover list gives it to modes | `ModeProcessing::Period` and `PeriodParity`. `Period` also holds the frame length (12640, 5040 ms), because receive and transmit both read it. |
| Where the fields of a decoded frame stand | One fact, one place (M1.4); `ResultRecord` already specialized `ProcessingResult` | `FrameStatus`, `CallValue`, `Exchange`, `PayloadFields` and the frame's fields stand in `ModeProcessing::ProcessingResult`. `Decodes::ResultRecord` adds `sequence`. |
| The items on the two ports were empty | An item on a connection has features (structure rule 1) | Typed from the code: request, result, end of a window, calls, encode request, waveform, refusal, accepted message. |
| The WSJT-X release in every source reference | One fact, one place; the baseline is open (`@Conflict` in `Requirements`) | Every reference says "WSJT-X at the behaviour baseline". No file of this part names beta4 or beta5. |
| The packing rules, the channel code, the waveform formula | A followed format is referred to, not copied (data rule 1) | About 9,000 characters of bit layouts and formulas are gone; the model names the source and states the product's choices and differences. |
| Whether the hash table is the modes part's | A model file follows the thing; the ledger places CL-024-01 here | The table is the payload function's. Receive and transmit feed it through the two ports (`CallsUpdate`, `AcceptedMessage`). |
| TC-004-001, TC-004-002 and TC-004-005 name their tests by function; the files do not carry the number | The project's rule for these cases, guarded by `tools/sysml/tests/test_decoder_mode_traces.py`: they bind named tests, and a whole-file tag does not count | Test 5 of `part_done.py` accepts a named test that its file defines. The method's line on test 5 says so now. **To confirm.** |
| Names that are keywords of the language | The code's names win | `'standard'`, `'empty'`, `'state'` are written in quotes; `part_done.py` reads quoted literals. |

## Dropped as code or as history

- The parallel stages, the rounds of 10 ms, the counts of waveforms held (CL-057-02).
- The retry at the data point, the retry of an overlapped candidate, the weak-word guard, the
  subtraction of frames: how the decoder finds frames. Their tests are named as detail tests.
- `ChannelFrame`, `Ft4ChannelFrame`: CRC polynomial, sync tones, Gray map, scrambling vector.
- The waveform formulas and the measured error budgets of the two tolerances.
- Seven values that are sample sizes or facts about a test file: `signalsPerLevel`,
  `overlapPairs`, the four counts of the sample recordings, and the 1000 windows of noise.
  They stand in the test cases. The five minimums of `DecodeQuality` are shares now
  (operator 2026-11-15).
- The protocol's values in the two waveform elements (symbol count, tone spacing, Gaussian
  BT, samples per symbol): the source defines them. The two tolerances stand in the test
  cases only. The elements keep the accepted range of the lowest tone (operator
  2026-11-15).
- The family rules of `PackMessage` with their bit fields.
- The part's attributes `currentReceiveSettings` and `intendedModeCapabilities`.
- All dates, issue numbers and slice names.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| package `WstxModemDecode` | `WstxDecode` | **tests read values by this name:** `server/tests/decoder_signal.rs`, `server/src/receive_http_tests.rs`, `physical_ft4_test.rs`; comments in `search_test.rs`, `contact_http.rs`, `history.rs`, `modes/transmit/mod.rs`, `bitmetrics.rs`; `docs/harness/Project-Specifics.md` |
| package `WstxOfflineDecode` | `WstxMessagePayload` | comments in `payload.rs`, `hashes.rs`, `recording.rs`, `pack.rs`, `service.rs`, `contact.rs`, `contact_tests.rs`; `interfaces/external/Udp.sysml` |
| `APrioriContext`, `DecodeBand` | moved to `WstxModeProcessing` | three comments |
| `APrioriContext::myCall`, `dxCall` (29 bits each) | `calls : StationCalls` (two texts) | packing a call to bits is inside the part |
| `AdvanceDecode`, `MeasureFrame` | `DecodeWindow`; the rules on start, frequency and SNR stand on the fields | old qso text, old `Decodes` |
| `PackRefusal` | `EncodeRefusalReason`, with `frequencyOutOfRange` | none |
| `MessageFamily::standardCalls`, `portableCalls` | `'standard'`, `portable` | the code's names |
| `StandardExchange`; `RttyFields::exchangeKind`, `serial`, `stateToken` | `Exchange`, with the kinds `'state'` and `serial` | the code has one exchange type |
| `strongDecodedMin`, `weakDecodedMin`, `overlapDecodedMin`, `oneSpacingStrongDecodedMin`, `oneSpacingWeakDecodedMin` (counts) | the same names ending in `Pct` (90, 50, 90, 90, 50) | **read by name** in `server/tests/decoder_signal.rs` |
| `minimumToneZeroHz`, `maximumToneZeroHz` | `minTone0Hz`, `maxTone0Hz` | the code's names |
| requirement def `HashResolution` | attribute def of the same name | seven comments |
| `PeriodTiming::PeriodParity` | `ModeProcessing::PeriodParity` | old qso data |

## Negative statements

| Old statement | Result |
|---|---|
| The modem reads no device, file, network or clock | dropped: the part has no connection to any of them |
| The modem decodes no SuperFox frame and runs no FT8var decoder | kept as differences from WSJT-X on `DecodeWindow` |
| A frame outside the window is never published | positive: which frames are returned, with one default |
| A call is never guessed from its hash | dropped: no function guesses |
| The table is never shared between profiles and never saved | positive: one table for each station process, for as long as it runs |
| Invalid content never falls back to free text | positive: its status is invalid_payload |
| WSJT-X's truncating free text is not reproduced | kept as a difference from WSJT-X on `PackMessage` |
| No frame from noise, silence, the other mode, a failed CRC | kept: it is the promise CL-007-07, and a decoder can do it |

## Settled from the code

- **Status.** CL-007-04 was `partial`; every one of its limits is read from the model by a
  test. It is `implemented`. TC-004-001, -002 and -003 were `partial` because of conditions
  without a test; those are not carried, and the cases are `implemented`.
- **The window.** The old text said 30 s for FT8 and 15 s for FT4. The decoder takes 30 s for
  both; a shorter FT4 window is receive's choice.
- **The limits of a request.** 2048 frames and 1024 bytes for each, from `history.rs`.
- **The overlap groups.** The old text had the two groups mixed; the fixture says: two tone
  spacings apart, and one spacing with 6 dB between the frames.
- **The corpus from the air.** The test asks for 401 of 409 frames; the old case said "the
  pinned count".
- **The exchange.** The code has six kinds; the old model had four and modelled the RTTY
  exchange apart.

## Not carried over

| What | Why |
|---|---|
| TC-004-001 (e), TC-004-002 (j): the SIM18 fixtures decode exactly | no test |
| TC-004-002 (b), second half: a station 80 dB below another | no test |
| TC-004-002 (k), (l): the weak-word guard, the retry at the data point | inside; their tests are detail tests |
| TC-005-001 and -002: an invalid tone is refused | no request can cause it; a detail of the code's interface |
| TC-057-002: best wall times per thread count | a report, not an expectation |

## Edge cases and their homes

| Case | Home |
|---|---|
| a window shorter than a frame; longer than 30 s | `DecodeWindow`; `DecodeError::decodeLimit` |
| a sample that is not finite | `DecodeError::invalidSamples` |
| a frame at the window's edge | `DecodeWindow`, TC-004-002 (f) |
| the same payload twice | `DecodeWindow`, TC-004-002 (g) |
| 256 and 257 candidates | `DecodeBudgets::candidateCap`, TC-004-003 (d) |
| the ends of the decode band | TC-004-001 (a), TC-004-002 (a) |
| no call, a call that does not pack | `StationCalls`, `APrioriHypotheses` |
| a hash before its call is known; two calls with one hash; a full list | `HashResolution`, TC-024-001 |
| an empty text, a long text, a text of another family | `EncodeRefusalReason`, TC-005-001 (b) |
| the ends of the transmit band | the waveform contracts, TC-005-001 (e), TC-005-002 (d) |
| two requests at once | impossible: one request runs at a time (`ReceiveProcessing`) |

## Checks

- `part_done.py modes`: all five tests pass: 24 identities accounted for, no finding of the
  script, no validator error, 41 names matched with the code and 53 lines with a verdict,
  10 test cases with their tests. `part_done.py clock` still passes.
- Size: the five files have 60,000 characters. The old text they replace has about 85,000
  (the four files 75,500, `ModeProcessing` 4,500, the moved part of `Decodes` 5,300).
- The description `_descriptions/modes.md` has 21,000 characters.

## The functional description

Written from the new files alone. It found three gaps.

| Gap | Settled how |
|---|---|
| What a 10-bit or 12-bit hash shows for a call that left the list of 1000 | From the code: those two lists do not forget. One sentence added. |
| How long "some time" is for `cqOnly`, how the progress follows the contact | On qso's handover list: qso builds the context (300 s in the code). |
| `decodeLimit` names its limits in words; the values are in the part's file | An interface cannot refer to a part. Left as it is; listed in the description. |

## What the comparison with the code found

| Finding | Result |
|---|---|
| The period length is written three times in the code, the nominal start and the frame length once more in receive | Work for the code. The model states them once. |
| `Parity` is defined in transmit's `schedule.rs` | Work for the code. |
| The contact engine calls the packer directly | On qso's handover list: `Station.sysml` has no connection between qso and modes. |
| `WaveformError::InvalidTone` | Inside: no request can cause it. |
| An environment variable in `synchronization.rs` | Inside: read in test builds only. |
| `modes/transmit/mod.rs` includes transmit's and the clock's modules by path | Work for the code: the folder is not the part. |

## Work for the code, when the new tree goes to main

- The tests read `WstxModemDecode::DecodeQuality::…` and `DecodeBudgets::…`; the package is
  `WstxDecode`. The reader's folder is `docs/sysml`.
- `decoder_signal.rs` reads eleven values of `DecodeQuality` that are gone or renamed: it
  takes the group sizes and the counts of the sample recordings from its fixtures, and the
  five minimums as shares.
- The tests of TC-004-001, TC-004-002 and TC-004-005 carry no tag with the case's number.
- One definition of the period, the nominal start and the frame length, read by transmit,
  receive and qso.
- `Parity` moves with the period.
- About 20 comments name `WstxModemDecode`, `WstxOfflineDecode` and elements that moved.
- `tools/sysml/tests/test_decoder_mode_traces.py` and the architecture oracle name the old
  packages.

## For the operator

1. **Test 5 accepts a named test.** Changed in `part_done.py` and in the method, from the
   existing rule for TC-004-001 and -002. To confirm.
2. **`Cancel` has no field.** M5.8 asks that a connection carries no empty item. A cancel
   has nothing to carry; the item says so. To accept, or to model the cancel otherwise.
3. **CL-024-01 is cut.** The hash table stays; contacts with a nonstandard call go to qso
   and need a new identity there.
4. **CL-057-02 is cut down to two facts.** The description of the parallel stages is gone.
5. **`Period` holds the frame length,** which the handover list did not name.
6. **`Decodes.sysml` was reduced now,** before receive is built, so that the frame's fields
   stand once.

## Not done

- Nothing outside `docs/sysmlV2` was touched.
- `Udp.sysml` and `DisplayData.sysml` still name what moved; they are on the handover list.
