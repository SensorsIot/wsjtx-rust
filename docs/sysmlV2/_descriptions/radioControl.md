# Radio control

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the five files of
`backend/radioControl/`, `interfaces/internal/RadioControl.sysml`,
`interfaces/internal/Keying.sysml`, `interfaces/external/Cat.sysml`,
`interfaces/external/RadioProperties.sysml`, and of `Station.sysml`, `Context.sysml` and
`interfaces/internal/AudioControl.sysml` only the lines that attach radio control. Not
read: the code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Control selection | how the operator wants the radio controlled: mode, endpoint, PTT; intent only | `ControlSelection` |
| Configuration | what the operator sets of the radio: the control selection and the AGC | `RadioConfig` |
| Records | what radio control wants kept across sessions: the keying confirmation; no menu shows it | `RadioRecords`, `RadioMemory` |
| Assignment | the configuration with the profile's revision, as the station service gives it | `ControlAssignment` |
| Connection | the opened serial port with a radio that has answered; counted from station start | `RadioStatus::connectionNumber`, `CatState` |
| Exchange | one frame to the radio and the radio's answer to it | `ControlExchange` |
| Fact | one value the radio itself reported, with its place among the answers, its time and whether it is confirmed | `Fact`, `RadioFacts` |
| Reservation | radio control kept for a change of several steps of the station service | `ReserveRadio` |
| Keying | switching the transmitter on and off for transmit | `Keying`, `KeyingRules` |
| Place | where a serial port is attached to the PC: container and USB hub | `WstxAudioControl::RadioPlace` |
| Detection | the search for radios on the PC's serial ports, on the operator's request | `DetectRadios`, `RadioDetection` |
| Discovery | making sure at station start which radio is the profile's | `DiscoverRadio`, `StartDiscovery` |
| Keying confirmation | the operator's word, given once, that opening a port cannot key a transmitter | `KeyingConfirmation`, `RadioRecords::keyingConfirmed` |

"State" is the state of the connection (`CatState`); "condition" is where the keeping of
the connection stands (`AutomaticCatCondition`). "Reserve" has two meanings, each with its
own item: keeping radio control for a change (`ReserveRadio`), and keeping a radio for
this station process (`ReserveDevice`).

## 2. Place in the system

Position: `Station` > `Backend` > `StationProcess` > `radioControl`
(`RadioControlInterface`). Beside it in the process stands `catAdapter` (`CatAdapter`).

| Port of radio control | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `station` | `~RadioControl` | station service, `control` | `StationRadioControl` | in: `ControlAssignment`, `RadioMemory`, `TransmitterActivity`, `ReserveRadio`, `ReleaseReservation`, `OperationRequest`, `WithdrawRequest`, `ApplyAgc`, `DetectRadios`, `ApplyRecommended`, `DiscoverRadio`; out: `RadioReserved`, `OperationDone`, `ControlRefused`, `DetectionReport`, `DetectRefused`, `SettingsOutcome`, `SettingsRefused`, `RadioDiscovered`, `RadioKept`, `RadioStatus`, `AgcStatus`, `RadioMemory` |
| `transmit` | `~Keying` | transmit, `control` | `KeyingLink` | in: `KeyRequest`, `WithdrawKey`, `UnkeyRequest`, `ReadMeters`; out: `KeyConfirmed`, `KeyFailed`, `RadioAvailability`, `MeterValues`, `MetersRefused` |
| `backend` | `RadioAccess` | the CAT adapter, `serial` | `RadioAccessLink` | out: `OpenRadio`, `ReserveDevice`, `SetRate`, `CivFrame`, `CloseRadio`; in: `RadioOpened`, `DeviceReserved`, `AccessRefused`, `ReceivedBytes`, `RadioClosed`, `CloseFailed` |
| `native` | `NativeControlPort` | the adapter of a radio's native connection, `control` | `NativeControl` | out: `TuneRadio`, `WithdrawTune`; in: `RadioTuned`, `TuneRefused` |

The CAT adapter keeps a radio for one station process of the PC at a time: an
`OpenRadio` for a device another station process holds, and a `ReserveDevice` for a radio
another station process has reserved, are refused with `resourceInUse`. The CAT adapter's
port `radio` (`CatPort`) is joined to the transceiver of the context by `Cat`: `CivFrame`
out and in.

The serial port is the endpoint's (`ControlSelection`); the device Windows has behind it is
`RadioStatus::deviceId`.

Not connected: radio control cannot reach the profile, audio, receive, the clock, the
modes part or the operating chain. What it needs of the profile comes in the assignment.
It learns what the transmitter does from the station service (`TransmitterActivity`). It
reports the place of the radio's port (`RadioStatus::place`) and has no access to a sound
endpoint.

## 3. Purpose and requirements

Radio control keeps the connection to the profile's radio, reads what the radio is set to,
changes frequency, mode and the settings the station looks after, keys the transmitter for
transmit, and finds and sets up a radio on request. All fourteen clauses derive from
FR-009, which `Station.sysml` gives to radio control. The status is the model's
declaration.

| Clause | Promise | Element | Status |
|---|---|---|---|
| CL-008-04 | control an Icom IC-7300 over its CI-V serial link, on the port and with the addresses of the profile's endpoint | `RadioConnection` | implemented |
| CL-008-06 | send a radio only the commands of its own operations, each as one exchange that ends with an answer or at a limit | `ControlExchange` | implemented |
| CL-044-09 | change a value only after reading it and only where it differs; count the change only when the radio reports the new value | `ReadCompareWriteVerify` | implemented |
| CL-008-09 | key and unkey for transmit, confirm each only by the radio's report, keep every other exchange away while the radio may be keyed | `KeyingRules` | implemented |
| CL-008-05 | report only what the radio answered; mark a fact not confirmed from the moment it may not hold | `FactRules` | implemented |
| CL-022-03 | connect by itself and stay connected while the profile's control is CAT with an endpoint it takes; reach no radio otherwise | `ControlGate` | implemented |
| CL-022-04 | try again by itself after a failed attempt whose port is closed, with growing waits up to a limit | `RetryCadence` | implemented |
| CL-044-01 | find the radios on the serial ports by reading only, after the operator's keying confirmation | `RadioDetection` | implemented |
| CL-044-02 | report where each identified radio's port is attached; propose the control of the one radio the station can control | `DetectionProposal` | implemented |
| CL-044-03 | read the menu items of an IC-7300 that decide whether the station can transmit through it, and say what each value means | `SettingsCheck` | implemented |
| CL-044-04 | set the recommended menu items only on request, keep the old values, set them back on request | `RecommendedSettings` | implemented |
| CL-044-10 | set the wanted AGC when a connection becomes ready and when asked within a change of the operating selection | `ManagedAgc` | implemented |
| CL-044-11 | report the wanted AGC, the radio's answer and the outcome at every change | `AgcReport` | implemented |
| CL-044-15 | make sure at station start, by reading only, which radio is the profile's; take the next free one when its own does not answer | `StartDiscovery` | implemented |

## 4. Data and rules

### The configuration, the records and the assignment (`RadioConfig`, `RadioRecords`, `ControlAssignment`)

Radio control defines its configuration and its records; the profile keeps them (the
station config and the hidden store) and the station service gives them: the
configuration in `ControlAssignment`, at station start and whenever the station config
changes; the records in `RadioMemory`, at station start.

| Field | Rule |
|---|---|
| `control.mode` | the control mode: disabled (default), the station controls no radio; cat, it keeps a connection to the radio of the endpoint |
| `control.endpoint` | the CAT port; absent exactly when the mode is disabled; otherwise a text of 1 to 256 bytes without control characters |
| `control.ptt` | the PTT method: disabled (default), the station cannot transmit; cat, transmit keys the radio over the connection; cat needs the mode cat |
| `agc` | the AGC radio control sets on the radio; present exactly for a managed radio, slow until the operator sets another |

| Record | Meaning | Without a record |
|---|---|---|
| `keyingConfirmed` | the operator has confirmed once that opening a serial port cannot key a transmitter | false: no port is opened to look for a radio |

Radio control hands a changed record over in `RadioMemory`; the station service answers
with the records as the profile holds them then. A changed record counts only when it has
come back.

An assignment whose `RadioConfig::control` differs (the rig, the endpoint, the PTT
method) is another radio connection; another AGC is set on the running one; a change
elsewhere in the station config changes nothing.

### The endpoint and the connection (`RadioConnection`)

| Form of the endpoint | Meaning |
|---|---|
| `COMn` | port n, rate auto, radio at 94, controller at E0 |
| `icom7300://COMn?baud=<rate>&radio=<address>&controller=<address>` | exactly these three keys in this order; the rate is `auto` or one of the six of the serial line; an address is two hexadecimal digits from 01 to EF, and the two differ |
| anything else | `invalidConfiguration` |

n is 1 to 256 without a leading zero, in capitals or not.

| Value | |
|---|---|
| Rates tried with auto | 9600, 19200, 4800, 115200, 57600, 38400, until the radio answers |
| Regular reading of the five facts | once a second while ready and nothing else is in work |
| From a request to close to the closed port | 250 ms |

A radio on this connection is taken to be an IC-7300 (`RadioStatus::model`).

### The serial link (`SerialLine`, `CivFrame`)

Eight data bits, no parity, one stop bit, no handshake; DTR and RTS are switched off
before the first byte and stay off; rates 4800, 9600, 19200, 38400, 57600, 115200. The port
is opened for this station alone. Opening a port can raise a line for a moment. A frame
has at most 32 bytes; the station sends from the address E0. The station's own frames come
back as an echo, and others may send unasked.

### Exchanges (`ControlExchange`)

Checks before anything is sent:

| Condition | Refusal |
|---|---|
| frequency outside 30000 to 74800000 Hz (`DialRange`), filter number outside 1 to 3, data filter number not 1 to 3 with the data mode on or not 0 with it off | `invalidRequest` |
| another connection than the current one | `staleContext` |
| an operation the station has not for this radio | `unsupported` |
| the request withdrawn | `cancelled` |
| a state other than ready | `unavailable` |
| another exchange, a reservation not its own, or the transmitter may be keyed | `busy` |

| Limit | Value | At the limit |
|---|---|---|
| one exchange | bounded in time (a value of the code, per rig) | `timeout`; what arrives does not extend it |
| an operation | the `withinMs` of its request | `timeout` |
| bytes in one exchange | 4096 | `limit` |
| frames in one exchange | 64 | `limit` |
| one frame | 32 bytes | `limit` |

The answer is a frame from the radio's address to the controller's that fits the command;
the echo, other addresses and unasked reports are passed over. A refusal of the radio is
`rejected`; an answer the source does not allow, and a frequency outside the range, is
`protocol`. A mode the station does not set is kept by its code. A frame is sent once.
**An exchange that fails with anything but `rejected` and `readbackMismatch` ends the
connection: the port is closed and the state is unavailable with that error.**

### Changing a value (`ReadCompareWriteVerify`)

| Step | Rule | Ends with |
|---|---|---|
| 1 | read the value | `rejected` when the radio refuses the read |
| 2 | the wanted value is there: nothing is written | confirmed by the read |
| 3 | AGC and menu items only: ask whether the radio transmits | `busy` while it does |
| 4 | write; the radio must acknowledge | `rejected` on a refusal |
| 5 | read again | `readbackMismatch` for another value; `indeterminate` without an answer or with a refused read |

Nothing is written twice and nothing is set back. `receiveSetup` does mode, data mode and
frequency in this order; when one was written, the three are read once more and must be
the wanted ones. The rule holds for the operations, the AGC and the menu items; keying is
not a change of a value.

### Facts (`Fact`, `RadioFacts`, `FactRules`)

Five facts: frequency (`hz`), mode (`ModeValue`: sideband or mode code, filter 1 to 3), data
mode (`DataValue`: on or off, filter), transmit state, split. Each has `querySequence`,
`observedAtMs` and `confirmed`.

| Event | Effect |
|---|---|
| the radio's answer to the read of a fact | sets that fact with the next sequence, confirmed; the four others stay |
| an acknowledgement, an echo, a wanted value | set nothing |
| a change of a value is begun | that fact is not confirmed until read again (`receiveSetup`: three facts; key and unkey: the transmit fact) |
| the state leaves ready, or a request to close | all five not confirmed; values and times stay |
| an answer after a request to close | sets the value, not confirmed |
| a new connection | the frequency is the first fact; the others are empty |

### Keying (`Keying`, `KeyingRules`)

| Request | Carried out | Answer |
|---|---|---|
| `KeyRequest` | after the exchange in work and a reservation have ended | `KeyConfirmed` when the radio reports the transmitter on |
| | `withinMs` ends first, or `WithdrawKey` before the command went out | `KeyFailed` busy; nothing sent |
| `UnkeyRequest` | whether or not the radio may be keyed, also on a closing connection whose port is open | `KeyConfirmed` when the radio reports it off |
| `ReadMeters` | only while the radio may be keyed; alc, po, swr in this order | `MeterValues`: the ALC on the radio's own scale (0 to 255), the output power in percent of full power, ten times the SWR; a refused meter is absent |
| | otherwise | `MetersRefused` busy; nothing sent |

A command must be acknowledged (`rejected`), then the radio is asked for its transmit
state: the other state is `readbackMismatch`, no report `indeterminate`.
`RadioAvailability::mayBeKeyed` is true from the moment a key command is to go out until
an unkey is confirmed; in that time the only frames to the radio are an unkey or a meter
read. A connection that closes while the radio may be keyed sends one unkey first, within
250 ms. A key or unkey ends a meter read in work; a failed meter read leaves the
connection as it is.

| `KeyFailure` | From |
|---|---|
| busy, rejected, readbackMismatch | the same error |
| timeout | timeout, cancelled, partialWrite |
| indeterminate | indeterminate, protocol, limit |
| unavailable | every other error |

### The radio's status (`RadioStatus`, `AutomaticCatStatus`, `AgcStatus`)

`RadioStatus`: connection number, state, error, device, effective rate, model, the facts,
the automatic status, the place of the profile's port, and whether the keying confirmation
is stored.

| `CatState` | Meaning |
|---|---|
| closed | not open |
| connecting | the port is being opened and the radio asked for the first time |
| ready | the radio answered |
| closing | being closed, or the port did not close |
| unavailable | failed, port closed |

`AgcStatus` (`AgcReport`): without a wanted AGC everything is absent; before the radio was
asked only the target; after an attempt the connection, the value reported, the outcome
(unchanged, written, notApplied with the error) and the trigger (connect, selection). A
failed attempt keeps the value last reported on the same connection.

### Detection (`RadioDetection`, `DetectionProposal`, `SettingsCheck`)

| Port | State |
|---|---|
| the station's own connection | `stationCat`; not opened again; identity and menu items read through the connection while ready |
| not on a Silicon Labs CP210x (USB 10C4:EA60) | `notRadioBridge`; not opened |
| not reached within detection's limit of time | `notProbed` |
| held by another station or program | `inUse` |
| cannot be opened | `unavailable` |
| opened, no answer | `noReply` |
| a radio answered | `identified` |

At most 64 ports get a report; the asking of one port is bounded in time. An opened port is asked for the
transceiver identity at 9600, 19200, 38400 and 115200, first all radios at once, then the
address of each known model; the asking ends at the first rate with an answer.

| Model | Address | The station |
|---|---|---|
| IC-7300 | 94 | can control it |
| IC-705, IC-9700, IC-7610 | A4, A2, 98 | names it only |
| another identity | | reports it as it is |

A proposal is made when exactly one radio the station can control was found: mode cat, the
endpoint with the port, rate and address the radio answered at, PTT by CAT, AGC slow.

| Menu item | ok | advice | blocking | Recommended |
|---|---|---|---|---|
| `usbSend`, `usbKeyingCw`, `usbKeyingRtty` | OFF | | DTR, RTS | OFF |
| `dataMod` | USB | MIC/USB | every other value | USB |
| `usbModLevel` | 1 to 255 | | 0 | not set |
| `civTransceive` | OFF | ON | | OFF |
| `dataOffMod` | information only | | | not set |

An item the radio does not give is unreadable.

### The recommended menu items (`RecommendedSettings`)

| Refusal | When |
|---|---|
| `stateConflict` | another connection than the current one |
| `radioUnavailable` | the state is not ready |
| `transmitArmed` | the transmitter is armed |
| `unsupportedRadio` | the radio does not answer with the identity of an IC-7300 |

Apply sets, in the order `usbSend`, `usbKeyingCw`, `usbKeyingRtty`, `dataMod`,
`civTransceive`, each item that differs from its recommended value. The first failure ends
the request. The old values are not kept; nothing is set back (operator 2026-11-15).

### The AGC (`ManagedAgc`)

| Occasion | Rule |
|---|---|
| a connection becomes ready | once; again when the assignment names another AGC; waits while the transmitter is not at rest; busy is tried again after 2 s, every other end is final for the connection |
| `ApplyAgc` in a reservation | at once; nothing is sent while the transmitter is not at rest; the outcome is reported and does not fail the change |
| no AGC in the configuration | nothing is read or set |

An attempt the radio does not answer in time ends with `timeout`.

### Discovery at station start (`StartDiscovery`, `KeyingConfirmation`)

| Situation | Answer |
|---|---|
| no keying confirmation; a profile on the native connection | `RadioKept`; no port opened |
| mode cat, endpoint taken, port present, answers with a radio the station can control, granted to this station | `RadioKept`; no other port opened |
| that port does not; or a profile never saved | the other ports on a known serial adapter in list order; the first that opens, answers and is granted: `RadioDiscovered` |
| saved with the mode disabled; endpoint not taken | `RadioKept`; no port opened |
| no radio found | `RadioKept` |

Discovery is bounded in time. The frames sent are reads of the identity. The reservation
lasts as long as the station process. The keying confirmation is
`RadioRecords::keyingConfirmed`, set by the first `DetectRadios` that carries it and handed
over to be kept; it counts when it has come back as kept, and without a record the keying
is not confirmed.

## 5. Behaviour

### Keeping the connection (`ControlGate`, `RetryCadence`)

| Assignment | Radio control |
|---|---|
| mode disabled | opens nothing, sends nothing; closes a connection that is connecting, ready or failed; the condition is disabled |
| mode cat, endpoint not taken | opens nothing; waitingForDevice with invalidRequest |
| mode cat, endpoint taken | one attempt at once at station start and for every other assignment; another assignment closes the connection first |

| After | Next attempt |
|---|---|
| a failed attempt whose port is closed | after 1 s, then 2, 4, 8, 8 s; retryWaiting with the error and the time left |
| the state ready | the row of failures starts anew |
| an attempt that could not start (reservation, operation in work) | at the next occasion; no wait grows |
| an attempt refused before a port is opened | counts as failed |
| a port that did not close | none while the station process runs: quarantined with failedClose |

**Default: by itself radio control sends only the five reads, the AGC of the assignment,
and the unkey of a connection that closes while the radio may be keyed.**

## 6. Implemented in and tested by

| Part | Modules |
|---|---|
| `RadioControlInterface` | `server/src/radio_control/mod.rs`, `actor.rs`, `executor.rs`, `catalogue.rs`, `setup.rs`; `server/src/transmit/codec.rs`; `server/src/radioControl/cat_lifecycle.rs`, `radio_agc.rs`; `server/src/radio_setup.rs` |
| `CatAdapter` | `server/src/radioControl/windows.rs`, `server/src/radio_setup.rs` |

Detail tests: for radio control in `server/tests/radio_control.rs` and
`server/src/radio_control/setup_tests.rs`; for the CAT adapter in
`server/tests/receive/radio_native.rs`.

## 7. What it relies on from outside

| Element | Needed for |
|---|---|
| `WstxAudioControl::RadioPlace` | the place of a port in `RadioStatus`, `PortReport`, `RadioProposal`, `RadioDiscovered` |
| `WstxRequirements::'FR-009'` | the derivation of the clauses |
| the station service | the assignment, the transmitter's activity, every command; it saves a discovered radio as the profile's control |

Named in text without an element behind the name: the "known serial adapter".

## 8. Differences from a named reference

The link follows the Icom IC-7300 Full Manual A7292-4EX-12a, section 19, CI-V command
table. No difference is stated.

## 9. Verification

| Case | Shows | Verifies | Level | Test |
|---|---|---|---|---|
| TC-009-003 | the connection on a scripted port, 6 conditions | CL-008-04 | 2, development PC | `server/tests/radio_control.rs`, one named test in `radio_native.rs` |
| TC-009-001 | the exchanges on a scripted port, 9 conditions | CL-008-06 | 2, development PC | `server/tests/radio_control.rs` |
| TC-009-002 | the station's own IC-7300 read and set by hand, 4 conditions | CL-008-04 | 4, station; partial, started by hand | `server/tests/receive/radio_hardware.rs` |
| TC-044-012 | frequency, mode, data mode and a menu item are read before they are set, 8 conditions | CL-044-09 | 2, development PC | `radio_control.rs`, `executor.rs` |
| TC-044-008 | the AGC is read before it is set, 7 conditions | CL-044-09 | 2, development PC | `radio_agc_tests.rs` |
| TC-009-007 | keying, unkeying and the meters on a scripted radio, 8 conditions | CL-008-09 | 2, development PC | three named tests in `transmit_service.rs`, three in `radio_level_tests.rs` |
| TC-009-006 | the facts follow the radio's answers, 5 conditions | CL-008-05 | 2, development PC | four named tests |
| TC-022-009 | the connection kept by itself, 14 conditions | CL-022-03, CL-022-04 | 2, development PC | `cat_lifecycle_tests.rs`, `auth_tests.rs` |
| TC-044-001 | detection reads and does not write, 10 conditions | CL-044-01, CL-044-03 | 2, development PC | `setup_tests.rs`, `radio_setup_tests.rs`, one named test in `windows.rs` |
| TC-044-002 | the place, the proposal and the refusals, 5 conditions | CL-044-01, CL-044-02 | 2, development PC | `setup_tests.rs`, `radio_setup_tests.rs` |
| TC-044-003 | the recommended items set and set back, 8 conditions and 1 planned | CL-044-04 | 2, development PC | `radio_setup_tests.rs` |
| TC-044-009 | the wanted AGC at a connection and in a change, and its report, 7 conditions | CL-044-10, CL-044-11 | 2, development PC | `radio_agc_tests.rs`, `radio_setup_tests.rs` |
| TC-044-020 | the radio of the profile at station start, 9 conditions | CL-044-15 | 2, development PC | `radio_setup_tests.rs` |

Every clause has a case. One condition is written as planned, with no test yet: the
record of old values has come back as kept before the first item is set, and an apply
whose record does not come back is refused (TC-044-003 i).

## 10. Open points, gaps and disagreements

Marked by the model:

1. `NativeControlPort` (`NotStated`): the items that carry the profile's intent for the
   native connection to the adapter and the state of its session back; their data stand in
   the adapter's function file.

Gaps found while writing this view:

1. `Station.sysml` still joins the control path by connections without an interface, joins
   the native adapter to radio control's port `backend`, and binds a `resourceContext` that
   no item of the new interfaces has. The Flex adapter's port `control` is typed by the
   port of the station service's interface (`~RadioControl`), not by `NativeControlPort`.
2. Radio control keeps two files in the profile's folder and has no connection to the
   profile.
3. (Dropped with `RadioBinding`, operator 2026-11-15.)
4. What the station service does with `RadioDiscovered` beyond saving the control is not
   radio control's and is not written here.
5. `ReleaseReservation`, `RadioReserved`, `WithdrawRequest`, `ApplyAgc`, `WithdrawKey`,
   `CloseRadio`, `RadioClosed`, `CloseFailed`, `DeviceReserved`, `RadioKept`,
   `DiscoverRadio`, `WithdrawTune` and `ReceivedBytes` carry no field: each is an event
   with nothing to say beyond itself, or bytes as they arrive.
6. The limits of time are values of the code, per rig (operator 2026-11-15); the model
   says only that an exchange, a detection and a discovery end.
7. `RadioStatus::model` is the rig the operator chose (`ControlSelection::rig`);
   `IdentifiedRadio::model` is what a radio answered.

Disagreements: none between the files read. Weak links (a name in a text, not a typed
reference): `WstxCat::SerialLine` and `WstxCat::Cat` from the function files;
`WstxRadioControl::ControlOperation` and `WstxKeying::Keying` from `Cat.sysml`.
