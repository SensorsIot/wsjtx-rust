# Report: the radio control part

2026-11-15. Built by a subagent session beside transmit, profile and ranking; the operator
was not asked. Tests 1 to 5 pass. Thirteen lines wait for the operator (last but one
section). Every figure below was measured by a script
(`measure.py` in the scratchpad folder `radioControl`).

## What was written

| File | Content |
|---|---|
| `backend/radioControl/RadioControl.sysml` | the part with four ports and a reference to its radio; `RadioBinding`, `RadioAuthority`, `CatAdapter` |
| `backend/radioControl/CatControl.sysml` | 4 clauses, 4 rule elements, 6 test cases: the connection, the exchanges, changing a value, keying |
| `backend/radioControl/RadioFacts.sysml` | 1 clause, 1 rule element, 1 test case: the facts of the radio |
| `backend/radioControl/CatLifecycle.sysml` | 2 clauses, 2 rule elements, 1 test case: the permission and the retries |
| `backend/radioControl/RadioSetup.sysml` | 7 clauses, 8 rule elements, 5 test cases: detection, the menu items, the AGC, discovery at start |
| `interfaces/internal/RadioControl.sysml` | the station service's interface, the access to a serial port, the native connection: 3 port types, 5 interfaces, 37 items, 13 enumerations |
| `interfaces/internal/Keying.sysml` | written new: key, unkey, confirmation, failure, availability, the meters |
| `interfaces/external/Cat.sysml` | the serial link and the frame, following the Icom manual |
| `interfaces/external/RadioProperties.sysml` | the properties of a radio the station reads or sets |
| `_descriptions/radioControl.md` | the functional description |

`Station.sysml` is not changed; its new lines are under "For the main session".

## The control path, as cut from the code

| Thing | In the code | In the model |
|---|---|---|
| Typed operations, the CI-V coding, the one exchange at a time | `radio_control/mod.rs`, `actor.rs`, `executor.rs`, `transmit/codec.rs` | radio control (`ControlExchange`, `ReadCompareWriteVerify`, `KeyingRules`) |
| The serial port: find it, open it for this station alone, set the line, bytes in and out | `radioControl/windows.rs` (`SerialTransport`) | the CAT adapter; `RadioAccess` is the code's `Transport` plus the opening |
| One station process per radio | the lock per device (`claim_identity`, `radio-ownership`) and per port (`reserve_in`, `radio-reservation`) | the radio authority: grants `OpenRadio` and `ReserveDevice`, passes the rest on |
| Which radio is the station's | `Configuration` and `Authority::resource_id` | `RadioBinding` |
| Keying | `Actor::ptt`, `ptt_abortable`, `read_meters`, called by transmit | the port `transmit` (`Keying`) |
| Tuning a FlexRadio | `recording.rs` calls the session | the port `native` (`NativeControl`), small and marked |

The old model joined the native adapter and the authority to one port `backend`. A shared
end needs something that arbitrates it; the new part has `backend` for the serial path and
`native` for the native connection, as audio has `device` and `native`.

## Identities

32 identities are accounted for (test 1): 27 of the old slice, 2 handed over to radio
control, 3 new.

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-008-04 | CatControl | CatControl | "Windows shared-audio and IC-7300 receive-control matrix" becomes: control an IC-7300 on the port and addresses of the endpoint. From FR-009 only (was FR-002, FR-009). |
| CL-008-06 | CatControl | CatControl | Keeps: only the station's own operations reach a radio, each a bounded exchange. The built-in catalogue is sorted as code. |
| CL-008-05 | CatControl | RadioFacts | Keeps "no false readiness": the facts come from the radio's answers alone. "Audio never needs CAT, CAT never opens audio" is structure (no connection). |
| CL-044-09 | RadioSetup | CatControl | Read, compare, write, verify. It is the rule of every change, so it stands with the exchanges. |
| CL-022-03 | CatControl | CatLifecycle | Keeps the permission: connect by itself while it is given, reach no radio without it. The confirmation, the authorization and the adoption of the frequency are handed over. From FR-009 only (was FR-008, FR-009, FR-021). |
| CL-022-04 | CatLifecycle | CatLifecycle | The retries. |
| CL-044-01, -02, -03, -04, -10, -15 | RadioSetup | RadioSetup | Each one sentence; routes, profile fields and browser texts handed over. |
| CL-044-11 | CatControl | RadioSetup | Keeps the report of the AGC. The push and the Settings line are handed over. |
| TC-009-003 | CatControl | CatControl | "Control without audio" becomes the connection on a scripted port; verifies CL-008-04. |
| TC-009-001 | profile (handed over) | CatControl | Typed radio control: the exchanges; verifies CL-008-06. Split from the same test file as TC-009-003 by content. |
| TC-009-002 | receive (handed over) | CatControl | The radio half of the live case: the tests of `radio_hardware.rs`, started by hand. Its capture half (`audio_hardware.rs`, `audio_listen.rs`) is not radio control's. |
| TC-044-008, TC-044-012 | RadioSetup | CatControl | Beside CL-044-09. |
| TC-022-009 | CatControl | CatLifecycle | Rewritten from the two Rust test files; the browser test is the frontend's. |
| TC-044-001, -002, -003, -009, -020 | RadioSetup | RadioSetup | Rewritten from their tests. |
| **CL-008-09** | new | CatControl | Keying. The old model had the action `PttControl` and no clause for it. |
| **TC-009-006** | new | RadioFacts | The facts; four tests that carry the numbers of other cases or none. |
| **TC-009-007** | new | CatControl | Keying and the meters; three tests of `transmit_service.rs` and three of `radio_level_tests.rs`. |
| TC-044-010, TC-044-022 | CatControl, RadioSetup | handed over: frontend | Browser tests of Settings. |
| TC-044-004, -011, -021 | RadioSetup | not carried | Planned, live on the station's radio, no test exists. |

The new numbers are the next free ones of the series CL-008 and TC-009.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| The interface of each of the five connections | M5.8; M2.1 names the files; a connection is typed by what flows | `nativeControl`: `NativeControl`. `authorityRequestDelegation`: `RadioAccessOut`. `commonAuthority` and `authorizedBackend`: `RadioAccessLink`. `authorizedControlDelegation`: `RadioAccessIn`. All four stand in `interfaces/internal/RadioControl.sysml`, with one port type `RadioAccess`. |
| What the radio authority is | A part called an authority arbitrates (structure rule 7); the code's locks | It grants a device to one station process and passes the rest on. |
| Two ports for the two radio connections | A shared end names what arbitrates it (structure rule 4); as audio | `backend` and `native`. |
| `resourceContext` on every request | An interface imports no part (M3.2); the old `ControlRequest` referred to `WstxRadioControlPart::RadioBinding` | Gone. `RadioControlInterface::controlled` refers to the `RadioBinding`; one binding in `Station.sysml`. |
| Keying gets a clause | A promise is a requirement; a detail test noticed outside the part shows a missing promise (authoring rule 11) | CL-008-09 with TC-009-007. |
| `RadioProperties`: 1,287 lines of a general radio model after Hamlib's `rig.h` | No evidence, no statement; a followed source is referred to, not copied | 92 lines: what the station reads or sets. See the operator's line 6. |
| The built-in catalogue of commands | Could two correct implementations differ unnoticed: yes, nothing outside reads it | Dropped as code; `unsupported` stays as an error. |
| Radio control learns of the profile and of the transmitter | M5.3: a function learns profile values from the station service | `ControlAssignment` and `TransmitterActivity` on `RadioControl`; the code reads the profile store and the transmit owner itself. |
| The place of the radio, not the endpoints | The operator's answer 4 on audio: the station service gives audio `RadioPlace` | `RadioStatus::place`, `PortReport::place`, `RadioProposal::place`; the pairing with endpoints is audio's. |
| A discovered radio is saved by the station service | M5.3; M5.1 (the profile owns its settings) | `RadioDiscovered` carries the control; the code saves it in `discover_within`. |
| Each clause from one FR | Decided on the clock | All fourteen from FR-009. |
| CI-V bytes | A followed format is referred to | The source is named once, on `Cat`. The model says which commands the station sends and what it does with echo, refusal and oversize input. Three byte values stand in test conditions only. |
| The radio is a slave of the station (M5.6) | - | No item lets the radio command the station; unasked reports are passed over (`ControlExchange`). |
| Planned live cases without a test | Method, "Decided" | TC-044-004, -011, -021 not carried. |
| Empty event items | The operator's answer 9 on audio | Thirteen items with one sentence and no field. |

## Dropped as code or as history

- The lease numbers, the channels and threads of the actor, the publication counter, the
  private request id, the limit of 9,007,199,254,740,991 answers.
- The catalogue file, its schema, its limits (256 KiB, 32 models, 128 commands) and its
  revision text.
- The windows of a probe (250 ms to all, 120 ms to one address, 300 ms for a menu item,
  30 ms of quiet), the 500 ms and 100 ms of trying a rate, the step of 4 s of a menu
  exchange, the 256 bytes of one read.
- Overlapped I/O, `CancelIoEx`, the DCB fields, the lock file paths and their coding.
- The 50 ms tick of the lifecycle and its lock order.
- The whole of the old sections 4.5 and 12.8 on live audio, receive results and their
  routes (they are audio's, receive's and the station link's, and built).
- The texts of the guidance and the labels of menu values (the frontend's words; the
  model keeps the severity).
- All dates, issue numbers, slice names, "delivered", "target", review findings.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| package `WstxRadioIO` | `WstxCatControl` | comments in `actor.rs`, `executor.rs`, `codec.rs`, `transmit/service.rs`, `operating/qso/udp.rs` |
| action `PttControl` | `KeyingRules` with CL-008-09 | the same four files |
| action `ExecuteCat`, attribute `Limits` | `ControlExchange`, `RadioConnection` | none |
| action `MaintainCommissionedCat` | `ControlGate`, `RetryCadence` | none |
| `RadioFacts` (in the function file), `FactProvenance`, `QueryCompletion` | `WstxRadioControl::RadioFacts`, `Fact`; rules in `FactRules` | none |
| `CatRequest`, `CatResult`, `RadioObservation`, `CatOperation` | `OperationRequest`, `OperationDone`, `RadioFacts`, `ControlOperation` | none |
| `ControlRequest`, `ControlOutcome` and the eight items after Hamlib | gone | `tools/sysml` (below) |
| part def `RustRadioDriver` | `CatAdapter` (already so in `Station.sysml`) | `tools/sysml.py`, `tools/sysml/architecture-oracle.json` and three tool tests |
| port `backend` of radio control for both connections | `backend` and `native` | `Station.sysml` |
| `KeyCommand`, `KeyOutcome`, `MayKeyAnswer` | `KeyRequest`, `UnkeyRequest`, `KeyConfirmed`, `KeyFailed`, `RadioAvailability` | none |
| `AutomaticCatStatus::scope`, `retryAfterMilliseconds`, `errorCode` | no scope (the station link's); `retryAfterMs`, `error` | `tools/sysml/pending-structure.json` |

Kept by name because others import them: `WstxRadioControl::RadioControl` (port type;
`FlexAdapter.sysml`), `StationRadioControl`, `ControlSelection` (`ProfileAccess.sysml`),
`WstxRadioProperties::Radio`, `WstxCat::CatPort` and `Cat` (`Context.sysml`),
`WstxKeying::Keying` and `KeyingLink`.

## Negative statements

| Old statement | Result |
|---|---|
| Audio never requires CAT; CAT never opens audio | dropped: no connection between the two |
| Catalogue data cannot authorize raw or transmit commands | positive: only the station's own operations reach a radio (CL-008-06) |
| No retry of an issued exchange, no write replay, no rollback | positive: a frame is sent once; nothing is written twice, nothing set back |
| No address scan | positive: detection asks all radios at once and then the address of each known model |
| The lifecycle never sends a setter or PTT | positive, as a default: by itself radio control sends the five reads, the AGC of the assignment and the unkey of a closing connection (`ControlGate`) |
| Detection never writes a setting, never keys | positive: the frames sent are the two kinds of read (`RadioDetection`); shown by TC-044-001 (i) |
| Apply and undo never key and never change frequency or mode | not written as a rule: they have no function for it; TC-044-003 (h) shows it |
| No normal Connect or Disconnect button; the routes refuse | the station link's and the frontend's; handed over |
| No serial enumeration or fallback while CAT is disabled | positive: a profile saved with the mode disabled keeps its control and no port is opened (`StartDiscovery`) |
| A capability grants no permission | dropped: the model has no capability description any more |

## Settled from the code

- **The order of the checks** of a request is not one order: through the owner a withdrawn
  request and a busy owner are found before the values are checked. The model lists the
  checks without an order.
- **An unkey** waits for an exchange in work like a key; it is taken on a closing
  connection whose port is open.
- **The meters** are read in the order ALC, Po, SWR; the old text named Po first.
- **Apply recommended** is refused while the transmitter is armed; the AGC waits while it
  is armed, tunes or transmits. Two different conditions, both from the code.
- **Auto rate** stops at errors of the port and goes on after a timeout.
- **Discovery** asks the profile's own port whether or not it sits on a known serial
  adapter; only the other ports are filtered by the adapter.
- **`waitingForDevice` with `invalid_request`** for an endpoint that is not taken: no
  attempt is made.
- **TC-044-001** was `partial` because no test showed the lines DTR and RTS; the test
  `opened_ports_hold_dtr_and_rts_disabled` in `windows.rs` shows the line settings, and
  it is bound now. That the lines are low on a real port is still not shown.
- **TC-044-002** was `partial` for the proposal at 19200: the tests show COM3 at 9600 from
  the station's own connection and COM4 at 19200; conditions (a) and (b) say that.
- **TC-044-003**: the record is read after the apply returns; "before the first write" is
  written as planned (i).

## What the comparison with the code found

49 names and values matched by the tool; 77 lines with a verdict: 52 matched by reading,
14 inside, 3 differences, 4 audio's, 3 the profile's, 1 the station link's.

| Finding | Result |
|---|---|
| The CI-V coding stands in `server/src/transmit/codec.rs` | Named as radio control's module. Work for the code: it is in transmit's folder. |
| `server/src/radio_control/` and `server/src/radioControl/` are two folders for one part | Work for the code. |
| The endpoint list, the pairing of endpoints and the change of device names stand in `setup.rs` and `radio_setup.rs` | Verdicts name audio and the profile. Work for the code. |
| `RadioConnection::closeMaxMs` (250 ms) has no value in the code; three tests assert it | A difference; the operator's line 4. |
| The result of an AGC attempt and the refusal of apply are one text in the code, outcome and error in the model | Two differences in form. |
| The tool keys a literal by its name alone | `rejected`, `unavailable`, `unchanged`, `written`, `invalidRequest`, `busy`, `closing`, `connecting`, `ready` matched names of other enumerations. Compared by reading: `CatState` has the five variants of `State`; `ControlError` the sixteen of `Error`; `ControlOperation` the nine of `Operation`; `Setting` the seven of `Setting`; `Agc`, `Sideband`, `Meter` theirs. |
| The tool reads public constants and enumerations only | `DELAYS`, `Gate`, `RETRY`, `EXCHANGE`, `DETECT_BUDGET`, `PORT_BUDGET` matched by reading. |
| Of 20 values in the model, 3 are public constants of the code | 17 are literals or private constants; no test reads a value from the model. |

## Edge cases and their homes

| Case | Home |
|---|---|
| endpoint that is no radio connection | `RadioConnection`, TC-009-003 (a); `ControlGate` (waitingForDevice) |
| port held by another program or station | `resourceInUse`; TC-009-003 (f), TC-022-009 (g), TC-044-001 (h) |
| radio silent, radio at another rate | `RadioConnection`, TC-009-003 (b), TC-022-009 (g) |
| cable removed while ready | `FactRules`, TC-009-006 (d); `RetryCadence`, TC-022-009 (f) |
| port that does not close | `failedClose`, `RetryCadence` (quarantined), TC-022-009 (e), TC-009-003 (e) |
| ends of the frequency range, of the filter numbers | TC-009-001 (b) |
| oversize frame, flood of frames or bytes | `ControlExchange`, TC-009-001 (d) |
| answer in pieces; echo; unasked report | `ControlExchange`, TC-009-001 (c), (d) |
| two requests at once | busy, TC-009-001 (e), (i) |
| request withdrawn before and during an exchange | TC-009-001 (f), (g) |
| the radio changed by hand during a change | `ReadCompareWriteVerify`, TC-044-012 (f) |
| the radio refuses a read, a write; acknowledges and does not change | TC-044-012 (b), (g); TC-044-008 (d) to (f) |
| the radio transmits when a setting is to change | busy; TC-044-008 (c), TC-044-003 (d), TC-044-009 (c) |
| key while a reservation holds; key withdrawn | `KeyingRules`, TC-009-007 (e) |
| acknowledgement of a key missing | TC-009-007 (d) |
| connection closes while keyed | TC-009-007 (c) |
| meter read stalls while an unkey comes | TC-009-007 (g) |
| permission withdrawn during a change | TC-022-009 (l) |
| another assignment while connecting | TC-022-009 (d) |
| long pause of the station | `RetryCadence` (one attempt), TC-022-009 (a) |
| two radios the station can control; none | `DetectionProposal`, TC-044-002 (c) |
| unknown transceiver identity | `RadioDetection`, TC-044-001 (e) |
| menu item the radio does not give | `SettingsCheck` (unreadable), `RecommendedSettings` (not set) |
| apply fails half way | `RecommendedSettings`, TC-044-003 (e), (f) |
| record of another radio; unreadable record | `RecommendedSettings`; no test |
| two stations, one radio; reserved and not yet opened | `StartDiscovery`, TC-044-020 (f) |
| more than 64 ports; detection longer than 40 s | `RadioDetection`; no test for 64, TC-044-020 (h) for the time |
| the sequence of answers at its end | rare and harmless; code |

## Not carried over

| What | Why |
|---|---|
| TC-044-004, TC-044-011, TC-044-021 | planned live cases on the station's radio, no test |
| The capture half of TC-009-002 | audio's by content; `audio_hardware.rs` and `audio_listen.rs` stay tests by hand without a case here |
| The capability model of `RadioProperties` | no code, no test |
| `radio_http.rs` | routes; the station link's |
| The catalogue | code |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| The five files of `backend/radioControl/` | 99,724 | 66,642 |
| `interfaces/internal/RadioControl.sysml` | 7,681 | 25,461 |
| `interfaces/internal/Keying.sysml` | 744 | 3,805 |
| `interfaces/external/Cat.sysml` | 361 | 2,197 |
| `interfaces/external/RadioProperties.sysml` | 99,115 | 3,907 |
| Total | 207,625 | 102,012 |
| Total without `RadioProperties` | 108,510 | 98,105 |

The function files are smaller by a third. `RadioControl.sysml` (interface) is more than
three times its old text: the old file carried eight general items after Hamlib and one
status; the new one carries what the code exchanges on three connections.

| Content of the new files | Characters |
|---|---|
| The 13 test cases (102 lettered conditions, 1 of them planned) | 29,797 |
| The 14 clauses | 5,237 |
| Imports, status and level tags, derivations | 7,448 |
| Rule elements, interface items, part definitions | 59,530 |

The old slice had 13 clauses and 14 test cases; the new one has 14 and 13.

## Checks

- `part_done.py radioControl`: all five tests pass: 32 identities, no finding in 9 files,
  no validator error, 49 matched and 77 with a verdict, 13 test cases with their tests.
- `part_done.py` for flexAdapter, log, audio, receive and profile still passes (they
  validate with `RadioControl.sysml` or hand an identity over).
- `check.py` on the whole tree: `interfaces/internal/Keying.sysml` is reported as not in
  the target tree (M2.1), as expected; `files.md` is not edited. No other finding in the
  part's files.
- A copy of `Station.sysml` with the lines below was validated with the whole tree: no
  error on a line of the radio's control path. `nativeControl` gives one warning (a
  member name inherited twice) because the Flex adapter's port is still `~RadioControl`.

## The functional description

`_descriptions/radioControl.md`, from the new files alone (26,471 characters). What it
found and what was done:

| Gap | Settled how |
|---|---|
| No item gave an operation its time, and none withdrew it | From the code (`Request::deadline`, `cancelled`): `OperationRequest::withinMs`, `WithdrawRequest`. |
| Where `RadioStatus::model` and `place` come from | Sentences added in `RadioConnection` and `DetectionProposal`. |
| How radio control knows that the transmitter is armed | `TransmitterActivity` from the station service. |
| Two files in the profile's folder, no connection to the profile | Stays, as audio's names file; handed to the profile. |
| `Station.sysml` and the Flex adapter's port do not fit the new interfaces | For the main session. |
| No limit for an apply or undo as a whole | Left: the code bounds each exchange only. |
| `RadioStatus::model` is an assumption, not a fact | The operator's line 9. |

## Markers

| # | Where | `NotStated` |
|---|---|---|
| 1 | port type `NativeControlPort` | the items that carry the profile's intent for the native connection to the adapter and the state of its session back |

No `Conflict` and no `LeftOpen`.

## Work for the code, when the new tree goes to main

- The CI-V codec moves out of `transmit/`; the two folders of radio control become one.
- The endpoint list, the pairing of endpoints with a port and the change of device names
  move out of radio control's modules (audio, profile).
- Detection reports the place of a port; the station service completes the proposal with
  audio's endpoints. Discovery reports the radio; the station service saves it.
- Radio control gets the profile's control, the permission and the transmitter's activity
  from the station service; today `radio_setup.rs`, `radio_agc.rs` and `recording.rs` read
  the store, the authorization and the transmit owner.
- The meters cross as percent and ten times the SWR; today `radio_level.rs` (transmit)
  converts the radio's counts. The mapping of radio control's errors to `KeyFailure`
  stands in `transmit/service.rs`.
- Comments name `WstxRadioIO::PttControl` (four files) and `WstxRadioIO` (`udp.rs`).
- Tests carry numbers that changed: the keying tests TC-008-003, the meter tests
  TC-044-013, the fact tests TC-009-003 and TC-009-005; CL-008-09, TC-009-006 and
  TC-009-007 are on no test yet.
- `tools/sysml`: `test_radio_properties.py` reads the old `RadioProperties`; the
  architecture oracle and `pending-structure.json` name `RustRadioDriver`,
  `WstxRadioControl::` items and `AutomaticCatStatus`.
- No test reads a value from the model.

## For the main session

### `Station.sysml`, word for word

Replace the two import lines

```
    private import WstxRadioControl::RadioControl;
    private import WstxRadioControl::StationRadioControl;
```

by

```
    private import WstxRadioControl::StationRadioControl;
    private import WstxRadioControl::RadioAccess;
    private import WstxRadioControl::RadioAccessLink;
    private import WstxRadioControl::RadioAccessOut;
    private import WstxRadioControl::RadioAccessIn;
    private import WstxRadioControl::NativeControl;
```

Replace the two port lines

```
        port authorityRequest : RadioControl;
        port authorizedControl : ~RadioControl;
```

by

```
        port authorityRequest : RadioAccess;
        port authorizedControl : ~RadioAccess;
```

Replace everything from `metadata radioPath : NotStated` to the line
`binding flexContext bind flexAdapter.control.request.resourceContext = radioBinding;`
(the marker, the five connections and the three bindings) by

```
        interface nativeControl : NativeControl
            connect radioControl.native to flexAdapter.control;
        interface authorityRequestDelegation : RadioAccessOut
            connect radioControl.backend to authorityRequest;
        interface commonAuthority : RadioAccessLink
            connect authorityRequest to authority.requests;
        interface authorizedBackend : RadioAccessLink
            connect authority.authorized to authorizedControl;
        interface authorizedControlDelegation : RadioAccessIn
            connect authorizedControl to catAdapter.authorized;
        binding controlledRadio bind radioControl.controlled = radioBinding;
```

The line `interface transmitControl : KeyingLink connect transmit.control to
radioControl.transmit;` and the line of `stationControl` stay. `private import
ModelNotes::NotStated;` has no use left in the file unless another marker is added.

### Other files this part may not edit

1. `backend/flexAdapter/FlexAdapter.sysml` (parked): the port becomes
   `port control : ~NativeControlPort` with
   `private import WstxRadioControl::NativeControlPort;` in place of the import of
   `RadioControl`. Its marker 2 then reads: the items of `NativeControlPort` carry the
   permission (`NativePermission`), the tune (`TuneRadio`, `WithdrawTune`) and its answer
   (`RadioTuned`, `TuneRefused`); missing are the profile's `NativeIntent` and
   `SessionStatus`, whose data stand in `FlexSession.sysml` (marker on
   `NativeControlPort`). Until then `Station.sysml` validates with a warning on
   `nativeControl`.
2. `backend/transmit/Transmit.sysml`: as transmit's report asks, `port control : Keying;`
   with `private import WstxKeying::Keying;`. Since transmit's table was written,
   `MeterReadings` changed: `alc` (the radio's scale, 0 to 255), `poPct`, `swrTimesTen`.
   `validate_with` of "transmit" then needs `interfaces/internal/Keying.sysml` and
   `interfaces/external/RadioProperties.sysml`.
3. `_work/files.md`: `interfaces/internal/Keying.sysml` is to be listed as a target file
   if the operator agrees (line 1); the five files of `backend/radioControl/` and
   `RadioControl.sysml`, `Cat.sysml`, `RadioProperties.sysml` are rebuilt.
4. `START-HERE.md`: a row "Part radioControl" in the state table; the open points
   "Keying.sysml is not in the tree" and "Five connections have no interface" change.
5. `backend/audio/Endpoints.sysml` (built): TC-044-006 can take the rule of the radio's
   place from `audio_endpoints_match_by_shared_usb_parent` (`setup_tests.rs`): same hub,
   two endpoints under the hub, same container under different hubs, only a root hub in
   common. The same test is TC-044-002 (d) here.
6. `_work/ledger.md`: the rows of TC-009-001 (profile's, handed over) and TC-009-002
   (receive's, handed over) were changed to arrived in `CatControl.sysml`; three rows
   were added after TC-009-002.
7. The names of four tests in `@TestedBy` are longer than a line and are written in two
   strings joined by `+`; `part_done.py` joins them. The rule says a test name is not
   split; at 100 characters a line it cannot be kept.

### Handover rows (in the table's format)

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| station | The station's authorization decides the permission radio control gets (`WstxRadioControl::ControlPermission`): unauthorized without a grant for the profile's radio, commissioningRequired until the operator has confirmed the control selection as it is ("Confirm receive-only setup"), eligible otherwise; a profile without an authorization has none. A change of the control selection raises the safety revision and needs the confirmation again; the confirmation itself reaches no radio. The station service gives radio control `ControlAssignment` at station start and at every change of the profile or of the authorization, and `TransmitterActivity` at every change of transmit's state. In the code `cat_gate` and `cat_tick` (`authorization_http.rs`) compute the gate every 50 ms and radio control's modules read the transmit owner. The station half of CL-022-03 **needs a home**: CL-022-02 is still "TO PLACE". Tests: `commission_zero_native_io_case` and the `commission_http_*` tests of `auth_tests.rs`; `selection_http_tests.rs` "Confirmation alone has zero native effects" (tagged TC-022-009). | CL-022-03, `MaintainCommissionedCat`; `authorization_http.rs`, `authorization.rs` | radioControl |
| station | The band and mode change uses radio control so: `ReserveRadio` (the wait of 3 s, `LEASE_WAIT`), a read of the transmit state (refused while the radio transmits), `receiveSetup` to the band's frequency in USB with filter 1 and the data mode on with filter 1, `ApplyAgc` for FT8 and FT4, `ReleaseReservation`. A connection made under another profile revision is shown as unavailable with `state_conflict` (`bound_snapshot`). When the connection is ready with a confirmed frequency and the band of the selection is unknown, a frequency that is the preferred entry of exactly one band in the station's mode becomes the selection (origin `cat_readback`), without a restart of receive and without a new operating revision; a known selection stays. Tests of the last: `station_port_released_by_other_program_reconnects_and_restores_selection` and `station_readback_adoption_needs_exact_operating_mode_entry_and_unknown_band` in `cat_lifecycle_tests.rs` (tagged TC-022-009). The tests `query_provenance_...` and `transition_lease_...` of `server/tests/radio_control.rs` carry CL-008-07 and TC-009-005; the first is also bound to TC-009-006, the second to TC-009-001 (i). | CL-022-03, CL-008-07, CL-044-16, TC-009-005; `recording.rs` 1830 to 1875, 2160 to 2400, `station/selection.rs` | radioControl |
| station | At station start the station service asks radio control to make sure of the profile's radio (`DiscoverRadio`) before the radio connection is first opened, before it listens and before the Tx level and the endpoint names are loaded; `WSTX_RADIO_DISCOVERY=off` turns it off (`main.rs`). With `RadioDiscovered` it saves the control (the revision rises), asks audio for the endpoints at the radio's place and saves the one capture and the one render endpoint found there, none otherwise; it keeps `settings.radio` or takes the default; the stored Tx level is removed; the confirmation of the setup is needed again (the safety revision rises, `reconcile_control`). It writes the line "radio discovery: COMn (model) is this station's radio". In the code `discover_within` (`radio_setup.rs`) does all of it. Shown by TC-044-020 (b) and `discovery_moving_to_another_radio_requires_the_confirmation_again`. | CL-044-15; `radio_setup.rs`, `main.rs` | radioControl |
| station | The station service completes the proposal of a detection with the sound endpoints at the radio's place, from audio's list (`EndpointEntry::radio`); radio control gives the place and no endpoint. In the code `detect` pairs them itself and reports `audio {input, output}` with the states one, none and ambiguous for each port. `RadioStatus::model` is what the station service gives udp for the instance name. | CL-044-02, CL-112-01; `radio_setup.rs` | radioControl |
| station link | The routes of radio control, each with a body of at most 1024 bytes: `GET /radio` (`v, profile_id, boot_id, connection_generation, state, error, device_id, effective_baud, observation {frequency_hz, mode, filter, data, data_filter, split, rx_tx, observed_at_ms}`; an unknown mode as two hexadecimal digits); the radio object of `/receive/selection` with `observations` (each fact `value, query_sequence, observed_at_ms, confirmed`, confirmed only while ready); `POST /radio/operation` (the five reads; `set_frequency`, `set_mode`, `set_data` and `receive_setup` are refused with `selection_unavailable` and reach no radio); `POST /radio/connect` and `/radio/disconnect`, which check their bodies and refuse with 409 `automatic_lifecycle` without reaching a radio; `POST /radio/detect` (`keying_inhibit_confirmed`; the report `ports [{port, friendly_name, vid, pid, instance_id, state, radios, audio}], manual, supported_radios, proposal, settings {port, source, civ_baud, items [{item, name, value, label, recommended, severity, message}], error}, audio_error`); `POST /radio/settings/apply` and `/undo` (`connection_generation`; the outcome `action, result, written, failed_item, error, undo`); the event `radio.agc` (`target, connection_generation, value, result, trigger`, once the station has a target and at each change); the status of `POST /authorization/v1/status` (`condition, error, retry_after_ms, commissioned`). The wire names of `ControlError`: `busy, cancelled, radio_timeout, radio_rejected, readback_mismatch, radio_failed_close, state_conflict` (staleContext), `invalid_request` (invalidRequest, invalidConfiguration), `selection_unavailable` (unsupported), `radio_unavailable` (every other), and `port_in_use` for resourceInUse in the status. The condition names are the model's literals as they stand. Tests: `deprecated_connect_and_disconnect_validate_then_refuse_with_zero_io` (`auth_tests.rs`), `http_detect_and_settings_routes_refuse_like_operating_mutations` (`radio_setup_tests.rs`). | CL-008-06 (old section 12.8), CL-044-01, CL-044-04, CL-044-11, CL-022-03, `AutomaticCatStatus`; `radio_http.rs`, `radio_setup.rs`, `station/selection.rs`, `radio_agc.rs` | radioControl |
| profile | The profile holds `settings.radio {agc}` exactly while the control is CAT with an endpoint radio control takes (`manages_radio`, `WstxCatControl::RadioConnection`); the default is SLOW; a file saved without it is read with SLOW and is not rewritten; `PUT /profile` refuses `radio` for another control and `settings.radio.agc` outside FAST, MID, SLOW. This is the profile's half of CL-044-10; radio control keeps the setting of the AGC. Tests: `profile_radio_settings_default_migrate_and_validate` and `profile_put_keeps_saves_and_refuses_radio_settings` in `radio_agc_tests.rs` (tagged TC-044-009). TC-044-002 kept its radio control conditions; the refusal of friendly names and the change of names to ids (`profile_put_refuses_friendly_names_and_accepts_endpoint_ids`, `startup_migration_replaces_unique_friendly_names_only`, `endpoint_id_syntax_and_friendly_name_migration`, all tagged TC-044-002) show CL-044-05. Radio control keeps two files in the profile's folder and has no connection to the profile: `radio-keying-confirmed.json` (`schema_version 1, keying_inhibit_confirmed`) and `radio-settings-undo.json` (`schema_version 1, profile_id, civ_address, items [{item, old, new}]`, at most 4096 bytes). | CL-044-10, CL-044-05, CL-044-04, CL-044-15, TC-044-009 (h), TC-044-002 (f), (g) | radioControl |
| frontend | Settings > Radio: "Confirm receive-only setup" and "Confirm changed receive-only setup" with the summary of endpoint, model, PTT and setup revision; no Connect or Disconnect control; the status "CAT unavailable · reason · automatic retry in n s" and "COMn in use by another program"; the chip "CAT setup not confirmed"; "Actual rig frequency unknown" (the browser test of TC-022-009 in `tests/radio-selection.test.cjs`). The AGC select and its line ("Radio AGC SLOW · set to SLOW and read back", "read back, already as set", "not applied · busy", "not yet read from the radio"), hidden without a managed radio; "AGC SLOW · recommended for FT8/FT4" (TC-044-010). The line of Detect radio that says discovery is off until confirmed once (TC-044-022). The words of the settings check (the messages of `guidance` and the labels MIC, ACC, MIC/ACC, USB, MIC/USB, OFF, DTR, RTS, the level in percent) and the list "Yaesu, Kenwood, Elecraft" of radios to set up by hand are texts; the model keeps `Severity`. | CL-022-03, CL-044-11, CL-044-15, CL-044-03, TC-044-010, TC-044-022, TC-022-009 | radioControl |
| transmit | **Taken up:** the row "radioControl" of transmit: CL-008-09, `WstxCatControl::KeyingRules`, TC-009-007 with the six tests it names. `MeterReadings` gives the output power in percent and ten times the SWR; the conversion from the radio's counts stands in `radio_level.rs` and is radio control's in the model. The ALC crosses in the radio's counts (transmit's line 3 for the operator). The mapping of radio control's errors to `KeyFailure` is stated in `KeyingRules` and stands in `transmit/service.rs` (`map_actor_error`). The safety revision is not in `Keying`: radio control has it only from the station service's assignment (the operator's line 3). The release at station start when the radio is found transmitting uses `RadioAvailability::transmitting` and `UnkeyRequest`; it is transmit's. | CL-044-12, TC-044-013, `PttControl` | radioControl |
| flexAdapter | **Taken up in part:** `WstxRadioControl::NativeControl` types `nativeControl`, with `NativePermission` (need 2), `TuneRadio`, `WithdrawTune` (need 3) and `RadioTuned`, `TuneRefused` (need 4). Needs 1 and 5 (`NativeIntent`, `SessionStatus`) are marked on `NativeControlPort`: their data stand in the adapter's function file and an interface imports no part. Point 2 (the binding `flexContext`) is answered: no item has a resource context. Point 3: `DialRange` is `WstxRadioProperties::DialRange`. Point 6: `DetectRefusal::invalidRequest` and `StartDiscovery`. Points 4, 5 and 7 wait for the adapter. | `NativeFlexWireSubset`; `_work/flexAdapter-report.md` | radioControl |

### Rows of the handover list taken up

| Row | Taken up as |
|---|---|
| "A radio's model, its capabilities, the requested settings and the observed state are four separate things" | `FactRules`: what the profile wants, what a request asks and what the radio reported are kept apart; the model as identified (`IdentifiedRadio`) apart from the model assumed (`RadioStatus::model`). The capability description is dropped; "grants no permission" is a negative without a function. |
| "The CAT adapter's type is `CatAdapter`. Five connections have no interface" | the part file; the lines for `Station.sysml` above |
| "Which endpoint shares the radio's USB parent ... `RadioPlace` ... CL-008-05" | `DetectionProposal` refers to `RadioPlace` by type; `RadioStatus::place`; CL-008-05's audio half is dropped as structure. That detection gives the same names as the endpoint list follows from the station service using audio's list. |
| "The control side of the Flex adapter" | the row "flexAdapter" above |
| "The CAT model in the instance name" | `RadioStatus::model`; the order at station start is in the row "station" above |
| "The meters ... the key and release bytes" (transmit) | the row "transmit" above |
| TC-009-002 | `CatControl.sysml`, its radio half |
| TC-023-003, the refused Detect radio on a native profile | `DetectRefusal::invalidRequest`; the test is the Flex adapter's |

## For the operator

One line each. WSJT-X controls a radio through Hamlib behind one `Transceiver` interface
(`Transceiver/TransceiverBase.hpp`); where it says something, the line names it.

1. **Done by rule (M5.8, M4.6): `Keying.sysml` is in the tree and types the connection transmit → radio control on both ends.** Is `interfaces/internal/Keying.sysml` added to the tree (M2.1)? WSJT-X has no
   separate keying interface: `do_ptt` is one method of the transceiver beside frequency
   and mode, with the PTT method (VOX, CAT, DTR, RTS) a setting. Recommendation: add it.
   The connection from transmit to radio control exists in `Station.sysml`, M5.8 wants it
   typed by an interface of its own name, and `RadioControl.sysml` is the station
   service's control interface (M4.6), which keying does not pass through. The other way:
   its nine items move into `RadioControl.sysml`.
2. **Answered (operator 2026-11-15), wider than asked: the radio authority is no part. The code has two lock files (`claim_identity` in `windows.rs` while a port is open; `reserve_in` in `radio_setup.rs` for a discovered radio until the process ends); both rules stand in `CatAdapter`. `RadioAuthority`, `Backend.radioAuthority`, the two process ports, the four connections, `RadioAccessOut` and `RadioAccessIn` left; one connection `serialAccess` (`RadioAccessLink`) joins `radioControl.backend` to `catAdapter.serial`.** The two process ports and the two delegations of the serial path. `authority` is a
   reference inside the station process, so `radioControl.backend` could be joined to
   `authority.requests` and `authority.authorized` to `catAdapter.authorized` directly;
   the ports `authorityRequest` and `authorizedControl` and two of the five connections
   then serve none of the three purposes (M0.2). WSJT-X has no authority between
   instances that was found: each instance opens its own rig. Recommendation: drop the two
   ports and the two delegations; `RadioAccessOut` and `RadioAccessIn` go with them.
   Until then all five are typed.
3. **Answered (operator 2026-11-15): none; the radio authorization is not part of the
   product, and the model has no safety revision.**
   **Which connection gives transmit the safety revision** (transmit's line 1, which
   recommends `RadioAvailability`). Radio control knows it only because the station
   service gives it in the assignment; the code's `cat_tick` gives it to transmit
   directly, with the gate. WSJT-X has no such number. Recommendation: the station
   service gives it to transmit over `TransmitControl` (M5.3); `Keying` stays without it.
4. **Answered (operator 2026-11-15): a promise; its reason is the reconnect after another assignment or a Disconnect, which waits for the closed port (`cat_lifecycle.rs` 123, 131); no band change waits on it.** Is "a connection asked to close gives up its port within 250 ms" a promise? The
   code has no such value; three tests assert it and the old text names it. No such time
   was found in WSJT-X (`close_rig` in `Configuration.cpp`; not read through).
   Recommendation: keep it
   (`RadioConnection::closeMaxMs`): a band change and a withdrawn permission rely on it.
5. **Decided by precedent (CL-022-03 kept its number when narrowed): both keep their numbers; the dropped halves are a negative statement and the catalogue's schema field (`catalogue.rs`), a code detail; the refusal `unsupported` stays in `ControlExchange`.** CL-008-05 and CL-008-06 say something narrower than before. CL-008-05: the facts
   come from the radio's answers alone (was also: audio and CAT do not need each other).
   CL-008-06: only the station's own operations reach a radio (was also: a versioned
   catalogue). Recommendation: keep both numbers on these sentences. The other way: retire
   them and give the sentences new numbers.
6. **Answered (operator 2026-11-15): the product's scope is the rigs Hamlib supports; FR-009 says so and Hamlib's list stays data (`hamlib-models.json`); the old property catalogue stays out of the model, as it describes nothing built; each rig's properties come with its code.** `RadioProperties` shrinks from 1,287 lines to 92. The old file described every
   property of a radio after Hamlib's `rig.h` as planned; the code reads five facts, sets
   three of them, the AGC and five menu items, and reads three meters. Decided by "no
   evidence, no statement", and listed here because of its size and because a tool test
   reads the old file. WSJT-X models nothing of Hamlib; it calls it. Recommendation:
   accept; if the list is wanted as a reference, it belongs beside
   `docs/sysml/reference`, not in the model.
7. **Answered (operator 2026-11-15): the confirmation of the setup, the grant and the
   safety revision get no clause; CL-022-03 is kept without the permission and promises
   the connection while the profile's control is CAT with an endpoint that is taken.**
   **CL-022-03 keeps the permission only.** The confirmation of the setup, the grant and
   the safety revision are the station service's (the row "station"), and no clause of
   the new tree carries them yet (CL-022-02 is "TO PLACE"). Recommendation: they get
   their clause in `backend/station/StationAuthority.sysml`; CL-022-03 stays here.
8. **Decided by rule (M5.3 and the answer 4 on audio); the code change joins issue 225.** Detection and discovery do more in the code than in the model. In the code
   detection pairs the sound endpoints with the port and discovery saves the profile; in
   the model radio control reports the place and the radio, and the station service does
   the rest (M5.3, and the answer 4 on audio). WSJT-X has neither; the operator picks
   rig, port and sound card. Recommendation: as modelled, and the code change joins
   issue 225.
9. **Answered (operator 2026-11-15): the rig is the operator's choice, as in WSJT-X: `ControlSelection::rig` (`RigModel`: the catalogue's name and Hamlib's number), `RadioStatus::model` its name; no identity query at every connection; CL-008-04 is the clause of the rig icom.ic7300. Work for the code: the rig is hidden in the endpoint's scheme `icom7300://`; the catalogue already lists models with their Hamlib number.** The model of the radio is assumed, not asked. Every CAT control is taken to be an
   IC-7300 (the endpoint list, the UDP instance name); the identity is asked only by
   detection and before apply and undo. WSJT-X takes the model the operator chose.
   Recommendation: ask the identity once at every connection and report it in
   `RadioStatus::model` (a code change); until then the sentence in `RadioConnection`
   says what holds.
10. **Decided by rule (a case is written when a test exists).** TC-009-002 is carried as a case started by hand (cost 4, on the station,
    automation partial), because its tests exist (`radio_hardware.rs`, ignored unless
    selected). The three other live cases have no test and are not carried.
    Recommendation: keep it so.
11. **Answered (operator 2026-11-15): limits of time are no values of the model; the rules say that an exchange, an attempt, a detection and a discovery end in time (timeout, notProbed). Dropped: connectMaxSeconds, exchangeMaxMs, operationMaxSeconds, setupMaxSeconds, detectMaxSeconds, portMaxSeconds, ManagedAgc::exchangeMaxSeconds, discoveryMaxSeconds. Kept: closeMaxMs (it bounds the reconnect, line 4) and closingUnkeyMaxMs (the transmitter off when a keyed connection closes); the cadences pollSeconds, the retry 1 to 8 s and the AGC retry 2 s are not limits and stay.** Three limits of time are written as values of the promise: 5 s for connecting,
    1 s for an exchange, 5 s for `receiveSetup` (and 2 s for one value). In
    `HamlibTransceiver.cpp` WSJT-X sets no time limit of its own for an exchange (a search
    found the cache timeout only). Recommendation: keep the three that the station
    service waits on; the others in this report's list of dropped values stay code.
12. **Answered (operator 2026-11-15), as WSJT-X: a new connection only when `RadioConfig::control` changes (the rig, the endpoint, the PTT method); `profileRevision` left `ControlAssignment` and `OperationRequest`; `staleContext` is another connection alone. Work for the code: `Key` (`cat_lifecycle.rs`) still holds `profile_revision`, `radio_id` and `safety_revision`, so every profile save reconnects; the test of TC-009-001 (f) makes staleness by another profile revision. Earlier: `radioId` and `safetyRevision` are gone
    with the radio authorization; `profileRevision` and the endpoint are left, and
    whether a renamed station should reconnect the radio stays open.**
    **`ControlAssignment` carries four values of identity** (`radioId`, `safetyRevision`,
    `profileRevision`, the endpoint) because any change of one reconnects the radio in
    the code, also a renamed station. WSJT-X opens the rig again when one of its rig
    parameters differs (`ParameterPack`, `Configuration.cpp`), not for another setting.
    Recommendation: keep as the code has it; whether a change
    of the display name should reconnect the radio is a product question for an issue.
13. **Answered (operator 2026-11-15): dropped: the part, `RadioControlInterface::controlled`, the binding in `Station.sysml` and its mention in M2.2; the port is the endpoint (configuration), the device `RadioStatus::deviceId`.** `RadioBinding` has no function of its own. M2.2 names it; in the code it is the
    endpoint read as port and addresses plus the device behind it. It is written as the
    radio the station controls, referred to by radio control. Recommendation: keep it so,
    or drop it from M2.2 and let `RadioStatus::deviceId` say the same.

## What was verified and what was not

Read in full: the old `backend/radioControl/` (five files), the old `RadioControl`,
`Keying` and `Cat` interfaces; `radio_control/mod.rs`, `actor.rs`, `executor.rs`,
`catalogue.rs`, `setup.rs`; `transmit/codec.rs`; `radioControl/cat_lifecycle.rs`,
`radio_agc.rs`; `radio_setup.rs`; `radio_http.rs`; `station/selection.rs`; the tests
`server/tests/radio_control.rs`, `setup_tests.rs`, `radio_setup_tests.rs`,
`cat_lifecycle_tests.rs`, `radio_agc_tests.rs`.

Read in part:

- `radioControl/windows.rs`: the claim of a device, the opening, the line settings, read,
  write, close and the line test; not the enumeration of ports and their topology.
- `recording.rs`: lines 1640 to 2420 (the radio owner and the selection); not the rest.
- `auth_tests.rs`: lines 1940 to 2410 (the automatic CAT tests); not the commission tests
  before them.
- `transmit/service.rs`, `transmit_http.rs`, `server/tests/transmit_service.rs`,
  `radio_level_tests.rs`: the keying and meter parts and the six tests bound to
  TC-009-007.
- `radio_hardware.rs` in full, `radio_native.rs` to line 90.
- `authorization_http.rs`: `cat_gate` and `cat_tick` only. `authorization.rs`, `main.rs`
  (beyond a search), `radio_level.rs`, `selection_http_tests.rs` and
  `radio_http_tests.rs`: not read.
- The old `RadioProperties.sysml`: its head, its end and its list of definitions, not
  every definition.
- The three browser tests: read, and handed over.

Not verified:

- That `Station.sysml` as a whole validates: it does not yet (parts not built); only the
  lines of the control path were checked on a copy.
- No test was run; the test names were checked by `part_done.py` (test 5) and by reading.
- That the conditions of a test case are all the test asserts: each condition was taken
  from an assertion read; not every assertion became a condition.
- WSJT-X was looked at in `Transceiver/*.hpp`, `TransceiverFactory.hpp` and by search in
  `Configuration.cpp`, not read through.

## Not done

- Nothing outside `docs/sysmlV2` was touched; nothing was committed or posted.
- `Station.sysml`, `FlexAdapter.sysml`, `Transmit.sysml`, `files.md`, `handover.md` and
  `START-HERE.md` are not edited; their lines are above.
- The profile's intent and the session status of the native connection have no item
  (marker 1); the Flex adapter is parked.

## Changed after the report: the radio authorization (operator 2026-11-15)

The operator decided on 2026-11-15 that the radio authorization is not part of the
product: no safety revision, no confirmation of the setup, no grant. The model states the
station without it: radio control reaches the radio by CAT whenever the profile's control
is CAT with an endpoint it takes. The code still has the authorization, and the
difference is work for the code (issue 226). The sections above are as they were written;
where they name the permission, the grant, the confirmation of the setup or the safety
revision, this section holds.

Measured by `measure.py` in the session's scratchpad (the tree against a copy made before
the change):

| File | Lines | Characters |
|---|---|---|
| `interfaces/internal/RadioControl.sysml` | 581 to 555 | 25,461 to 24,179 |
| `backend/radioControl/CatLifecycle.sysml` | 142 to 131 | 8,472 to 7,698 |
| `backend/radioControl/RadioSetup.sysml` | 434 to 432 | 25,349 to 25,178 |
| `_descriptions/radioControl.md` | 423 to 420 | 26,471 to 26,103 |

Removed from the model:

| Element | What was removed |
|---|---|
| `ControlPermission` | the enumeration, whole (unauthorized, commissioningRequired, eligible): with the two refusals gone one literal was left, which says nothing |
| `ControlAssignment` | the features `permission`, `radioId` and `safetyRevision`; another radio connection is an assignment that differs in `profileRevision` or the endpoint. `radioId` is a name the authorization makes (`authorization_http.rs`, a UUID of the scope) and that the key of the connection alone reads (`Key` in `cat_lifecycle.rs`) |
| `AutomaticCatCondition` | the literals `unauthorized` and `commissioningRequired` (9 to 7) |
| `NativePermission` and the item `permission` of `NativeControlPort` | whole; see the Flex adapter's report |
| `ControlGate` | the permission in each of its three cases: the cases are the mode disabled, the mode cat with an endpoint that is not taken, and the mode cat with one that is; "when the permission is given" as an occasion of an attempt |
| CL-022-03 | "while the station service gives it the permission for that radio, and reach no radio without it" |
| TC-022-009 | "under the permission" in its title; the station's authorization in the setup; in (a) "Eligible"; in (c) unauthorized and commissioningRequired; in (d) and (e) the safety revision as what makes another assignment; in (h) unauthorized and commissioningRequired; in (l) the withdrawn permission, now the control disabled; in (m) the confirmation of the setup, the endpoint changed and confirmed again, and the revoked authorization; the condition (n) whole (15 to 14 lettered lines, 2 test files as before) |
| TC-044-020 | the station's authorization in the setup; the last sentence of (b), commissioningRequired after a discovery; the test file `server/src/auth_tests.rs`, which showed that sentence only (2 test files to 1) |

The letters of the conditions that stay are unchanged; (n) of TC-022-009 is not used
again.

**CL-022-03 is kept, not retired.** Its promise had two halves: radio control connects
the profile's radio by itself and keeps it connected, and it reaches no radio without the
permission. The first half stays whole and is what TC-022-009 (a) to (m) and (o) show; of
the second half the part stays that does not come from the authorization: no radio is
reached while the mode is disabled or the endpoint is not taken. Its sentence is now
"Radio control MUST connect the profile's radio by itself and keep it connected while the
profile's control is CAT with an endpoint it takes, and reach no radio otherwise".
**CL-022-04 is unchanged:** the retry after a failed attempt names nothing of the
authorization. No identity is retired or not carried; the ledger is unchanged.

Verdicts in `parts.json` (test 4: 49 matched, 74 with a verdict; before 49 and 77):

- Removed, because their literal left the model:
  `model literal AutomaticCatCondition::commissioningRequired`,
  `model literal AutomaticCatCondition::unauthorized`,
  `model literal ControlPermission::eligible`.
- Rewritten: the four verdicts of `AutomaticCatCondition::disabled`, `quarantined`,
  `retryWaiting` and `waitingForDevice`, which said that the enumeration has exactly the
  nine texts of the code. It has seven; the verdict of `disabled` holds the difference:
  "the code still has the radio authorization; removed from the product (operator
  2026-11-15), issue 226".

Test 4 shows no new line for radio control: `Gate` and `Key` are `pub(crate)` and the
conditions are texts, which the tool does not read. Differences in the code, read (work
for the code, issue 226):

- `Gate::Unauthorized` and `Gate::CommissioningRequired`, the texts `unauthorized` and
  `commissioningRequired` of `Lifecycle::status`, and the fields `radio_id` and
  `safety_revision` of `Key` (`cat_lifecycle.rs`); `Lifecycle::new` starts with
  `Gate::Unauthorized`.
- `cat_gate` and `cat_tick` (`authorization_http.rs`) compute the gate from the grant and
  the confirmation; without them the gate is the control selection alone.
- The tests make "another assignment" by another safety revision (`eligible(2)` in
  `cat_lifecycle_tests.rs`: (d), (e)), and close a connection by `Gate::Unauthorized`
  where the model says the control disabled ((l),
  `station_revocation_during_rf_work_cancels_it_and_releases_without_reopen`). (h) and
  (c) are shown for `Gate::Disabled` beside the two removed values. (m) and (o) stand in
  `auth_tests.rs`, in a flow that enrolls a browser and confirms the setup before the
  radio is reached; the kept part of (m), the renamed profile, is shown there only.
- `auth_tests.rs` `discovery_moving_to_another_radio_requires_the_confirmation_again`
  (tagged TC-044-020 (b)) and `selection_http_tests.rs`
  `live_native_selection_commission_has_zero_native_effects` (tagged TC-022-009) show the
  confirmation only and are bound by no case now.
- `failed_store_write_quarantines_and_releases_cat_with_zero_reopen` (the removed
  condition (n)).

Lines "For the operator" that the decision answers: 3 and 7 (marked above), and 12 in
part (marked above). Line 4 names "a withdrawn permission" as one of two that rely on the
250 ms; the band change is left.

Left untouched because the decision does not name them:

- `KeyingConfirmation`, `RadioStatus::keyingConfirmed`, `DetectRadios::keyingInhibitConfirmed`
  and `DetectRefusal::confirmationRequired`: the operator's word that opening a serial
  port cannot key a transmitter, kept in `radio-keying-confirmed.json`. It is a
  confirmation and is asked in Settings, but it is not the confirmation of the setup of
  the authorization (`authorization.rs`): it guards the opening of a port by detection
  and discovery, not the reaching of the radio by CAT under a grant.
- The radio authority (`RadioAuthority`, `RadioAccess`, the ports `authorized`,
  "granted"): it gives a serial port to one station process of the PC at a time and has
  nothing of the three things.

Not verified: `CatControl.sysml`, `RadioFacts.sysml`, `Keying.sysml`, `Cat.sysml` and
`RadioProperties.sysml` were searched for the terms and their hits read, not read again
in full; `auth_tests.rs` was read from its module `automatic_cat` on (the tests bound by
TC-022-009 and TC-044-020), not in full; `radio_setup_tests.rs` was not read again, so
that it shows the kept part of TC-044-020 (b) rests on the report above.

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
| `interfaces/internal/RadioControl.sysml` | 555 to 604 | 24,179 to 27,002 |
| `backend/radioControl/RadioControl.sysml` | 80 to 87 | 4,126 to 4,505 |
| `backend/radioControl/RadioSetup.sysml` | 432 to 434 | 25,178 to 25,396 |
| `_descriptions/radioControl.md` | 420 to 436 | 26,103 to 27,578 |

The growth is the configuration and the record types with one sentence for each value.

Moved in (radio control defines them now):

| Element | What |
|---|---|
| `RadioConfig` (new, in `WstxRadioControl`) | the configuration: `control : ControlSelection` (control mode, CAT port, PTT method, each with what it does) and `agc : Agc[0..1]`. It takes the place of `WstxProfileAccess::RadioSettings::agc` and `AgcSetting`; "managed radio" is defined here |
| `RadioRecords` (new) | the records: `keyingConfirmed` and `settingsUndo : SettingsUndo[0..1]` |
| `SettingsUndo` (new) | the undo record: the address of the radio and the items; `UndoItem` moved up beside it and got its sentence |
| `RadioMemory` (new) | the item that carries the records: from the station service at station start, from radio control when it has changed one, answered with the records as the profile holds them then |
| `ControlAssignment` | `control` and `agc` are one feature `config : RadioConfig`; `profileRevision` stays |
| `RadioControl` (port) | two items more: `kept` and `keep`, both `RadioMemory` |
| `RadioControlInterface` | two attributes: `config : RadioConfig`, `records : RadioRecords` |

Left:

| Element | What left |
|---|---|
| `KeyingConfirmation` | "kept in the profile's file radio-keying-confirmed.json"; "a missing or unreadable file, and a write that failed, mean not confirmed". It says: the record is `RadioRecords::keyingConfirmed`, handed over, and counts when it has come back as kept |
| `RecommendedSettings` | "the record is the profile's file radio-settings-undo.json"; the refusal `invalidUndoRecord` for a record that cannot be read |
| `SettingsRefusal` | the literal `invalidUndoRecord` (9 to 8 literals). `storageUnavailable` stays: the changed record did not come back as kept |
| TC-044-020 | "stored" and "the file" in the setup and in (g) are the record; 9 lettered lines and 1 test as before |
| TC-044-003 | (i), planned, says: the record has come back as kept before the first item is set, and an apply whose record does not come back is refused; 9 lettered lines as before |
| CL-044-10 | "the AGC the profile wants" is "the AGC of its configuration" |

No condition and no test left a case: the conditions on the record say what the record
does. No identity is retired or not carried.

Verdicts in `parts.json` (test 4: 49 matched, 73 with a verdict; before 49 and 74): one
taken out, model literal `SettingsRefusal::invalidUndoRecord`. Test 4 shows no new line:
the names of the code's files and refusals are texts, which the tool does not read.

Differences in the code that test 4 does not show (work for the code): `radio_setup.rs`
keeps `radio-keying-confirmed.json` and `radio-settings-undo.json` itself, through
`profile::Store::write_document_file`; `read_undo` refuses with `invalid_undo_record` and
`storage_unavailable`; the record of the keying carries `schema_version` and the undo
record `schema_version` and `profile_id`, which the model does not state (the form of the
hidden store is the profile's).

Decided by rule: a record is defined by the part that makes it (the decision); a refusal
for a file that cannot be read left with the file.

Answered (operator 2026-11-15): the undo goes; the check and Apply stay. Removed: `UndoRecommended`, `SettingsUndo`, `UndoItem`, `RadioRecords::settingsUndo`, `SettingsOutcome::undo`, the refusals `undoPending`, `nothingToUndo`, `storageUnavailable` of `SettingsRefusal`; CL-044-04 says "set ... only on the operator's request"; TC-044-003 keeps (a), (b), (d) to (h) without the record, (c) and (i) left. Work for the code: `radio-settings-undo.json`, `undo` in `radio_setup.rs` and its route and tests. As written: Not decided, for the operator: whether radio control waits for the undo record to come
back as kept before it writes the first menu item (the model says so, as the code writes
the file first; the planned line (i) carries it).

Not verified: the bodies of the tests of TC-044-003 and TC-044-020 were searched for the
two file names (lines 163 to 171, 1050, 1092, 1229, 1232 of `radio_setup_tests.rs`), not
read in full again.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-009-007 (`CatControl.sysml`): its counts 0, 10, 60 and 120 of the ALC: 0, 8, 50 and 100 percent.
