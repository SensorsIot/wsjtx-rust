# UDP sender

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: `backend/udp/Udp.sysml`,
`interfaces/external/Udp.sysml`, and of `Station.sysml`, `Context.sysml`,
`interfaces/internal/StationCommands.sysml` and `interfaces/internal/OperatingChain.sysml`
only the lines that attach the UDP sender, and `interfaces/internal/Decodes.sysml`. Not
read: the code, the issues, the old model, WSJT-X.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Source | the WSJT-X UDP protocol, whose layouts, type numbers and encodings the station follows | `Datagram` |
| Target | one program the station sends to, named by its address | `UdpTarget` |
| Active | a target with an open socket | `TargetStatus::active` |
| Selects | a target gets a message only when its list of messages names it | `UdpTarget::messages` |
| Pulse | the moment a target becomes active, and then every pulse interval of the source | `OutboundRules` |
| Header schema | the version of the source's header in the datagrams to one target | `UdpWire`, `TargetStatus::schema` |
| Instance name | the id of every datagram | `InstanceName` |
| Look | one pass in which the station sends what is due (a word of the test cases) | no element |

## 2. Place in the system

Position: `Station` > `backend` > `stations` (one per profile) > `udp : UdpService`.

| Port of udp | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `control` | `~UdpControlPort` | station service, `udp` | `UdpControl` | in: `UdpConfigured`, `UdpStationState`; out: `UdpSnapshot` |
| `decodes` | `~DecodesPort` | receive, `decodes` | `Decodes` | in: `ResultRecord`, `PeriodView` |
| `logged` | `~CompletedContactPort` | log, `logged` | `CompletedContact` | in: `FinishedContact`; out: `LogAnswer` |
| `peers` | `UdpPort` | the UDP peer of the context | `Udp` | out: `Datagram`; in: `PeerHeartbeat` |

The files of the part (2026-11-16): `backend/udp/Udp.sysml` (the part),
`backend/udp/UdpSender.sysml` (the targets and the instance name, with their cases),
`interfaces/internal/UdpControl.sysml` (the configuration, the station's state for
Status, the snapshot), `interfaces/external/Udp.sysml` (the exchange).

Limit, as written before the split: `FinishedContact` has no feature, the port toward the log
gives the UDP sender a `LogAnswer` to send that it never sends, and a `ResultRecord` does
not say which job it belongs to (three of the markers in section 10). The UDP sender does
not use `PeriodView`.

Not connected: the profile, transmit, qso, auto, ranking, radio control, the Flex adapter,
audio, the clock, spots, web and mcp. What the UDP sender needs of them reaches it through
the station service; it can command none of them.

## 3. Purpose and requirements

The UDP sender tells other programs what the station does, in the messages of the WSJT-X
UDP protocol, and takes no command from them. All twelve clauses name the interface `Udp`
as subject and derive from FR-012, which `Station.sysml` gives to udp.

| Clause | Promise | Element | Status |
|---|---|---|---|
| CL-040-01 | send every enabled target the messages it selects, each on its occasion | `OutboundRules`, `UdpWire` | implemented |
| CL-040-02 | send to every target of the list the operator configures, and follow a changed list at once | `UdpConfiguration` | implemented |
| CL-040-06 | take an IPv6 multicast group as a target and send to it with the hop limit and through the interface it names | `Ipv6Multicast` | implemented |
| CL-040-03 | take from the targets only the header schema a target's Heartbeat names, and drop every other datagram without an effect | `InboundRules` | implemented |
| CL-112-01 | give every datagram one instance name that no other running station of the same Windows account carries | `InstanceName` | implemented |
| CL-040-07 | send Status so that a target learns of every decode window and, within one pulse, the state of the station | `StatusCadence` | implemented |
| CL-112-02 | fill Status from the station's state with the meaning WSJT-X gives each field | `StatusFields` | implemented |
| CL-040-04 | send each message decoded by the live receive job once, in the text form WSJT-X gives it | `DecodeFields` | implemented |
| CL-112-03 | send the delta time of a decode rounded to one decimal | `DeltaTime` | implemented |
| CL-112-04 | send Clear when the operating selection changes to another band, and only then | `ClearRule` | implemented |
| CL-112-05 | send a logged contact from its stored record, with the exchanges WSJT-X sends for the record's activity | `LoggedFields` | implemented |
| CL-112-06 | tell a target with Close that the station stops sending to it | `CloseRule` | implemented |

## 4. Data and rules

### Which message on which occasion (`OutboundRules`)

A message goes to a target only while the target is active and selects it. Every datagram
carries the instance name as id and the target's header schema.

| Message | Occasion |
|---|---|
| heartbeat | at each pulse of the target; names the highest schema 3, the station's version and an empty revision |
| status | see "When Status is sent" |
| decode | once for each decoded record of the live receive job |
| clear | when the operating selection changes to another band |
| qso_logged, then logged_adif | when the log stores a contact for the first time |
| close | when the station stops sending to the target |
| any other message of the source | not sent |

### The header (`UdpWire`)

| Value | | Meaning |
|---|---|---|
| `schemaOut` | 2 | the header schema to a target until that target names a higher one |
| `schemaMax` | 3 | the highest header schema the station takes and names |
| `inboundMaxBytes` | 4096 | a longer datagram from a target is not read |

### A target (`UdpTarget`, `Ipv6Multicast`)

| Feature | Rule |
|---|---|
| `address` | an IPv4 or IPv6 address in numbers with a port from 1 to 65535; the unspecified address and 255.255.255.255 are not admitted; no two targets of a list have the same |
| `enabled` | a target that is not enabled is not sent to |
| `multicastTtl` | 1 to 255; the TTL to an IPv4 multicast address, the hop limit to an IPv6 multicast address; every target names one |
| `multicastInterface` | the interface the datagrams to a multicast address leave through; an IPv4 address, or for an IPv6 group its index; absent: the system chooses |
| `messages` | each message at most once; an empty selection sends nothing |

For an IPv6 multicast group: the reserved scopes 0 and 15 are not admitted; the interface
is its index, a decimal number from 1 to 4294967295 without a sign and without a leading
zero; a group of the scopes 1 and 2 names one, a wider scope may leave it out; an index no
interface of the PC has is admitted and the target shows `socketUnavailable`.

### The list of targets (`UdpConfiguration`)

The list of targets is the configuration of the UDP sender. The sender defines it; the
profile keeps it in the station config; the sender takes it at station start and whenever
the station config changes, and has no command and no file of its own for it.

| Rule | |
|---|---|
| at most | 16 targets, in the order the operator gave them |
| until the operator sets a list | one target: 127.0.0.1:2237, enabled, every message, TTL 1, no interface |
| after a changed list | at once: a target whose address, enabled, TTL and interface are unchanged keeps its socket, schema and status; every other is closed and opened again |
| a multicast target | is sent to with its TTL or hop limit, through its interface, with multicast loopback on |
| `WSTX_UDP` set to off | no socket; the list is shown as before |

### What the station service reads (`UdpSnapshot`, `TargetStatus`)

`UdpSnapshot`: `instanceName` (absent while the station has none), `configuration`,
`status` (one for each target of the configuration, in its order).

| `TargetStatus` | |
|---|---|
| `address` | |
| `active` | the target has an open socket |
| `schema` | the header schema of the datagrams to it |
| `lastSendMs` | time of the last datagram sent; absent until one is sent |
| `error` | `socketUnavailable`: the socket of an enabled target could not be opened with its settings. `sendFailed`: the last datagram could not be sent; the next one sent clears it. Absent while none holds |

### What the station takes from a target (`InboundRules`)

| Datagram at the socket of an active target | Result |
|---|---|
| a Heartbeat from the target's address, with the source's magic number, a schema from 2 to 3, the instance name as id, at most 4096 bytes | the schema of that target is raised to the datagram's; never lowered; a socket that is opened starts at 2; fields after the id are not read |
| a Heartbeat at the socket of a multicast target | does not come from the group's address; the target stays at 2 |
| every other datagram | dropped: it changes nothing and is not answered |
| a datagram longer than 4096 bytes | dropped; the ones behind it are read |

### The instance name (`InstanceName`)

The instance name is "WSTX-Rust - " and the station's name (`ProfileConfig::display_name`),
fixed at station start for the life of the process, as WSJT-X's "WSJT-X - <rig name>". It
is unique because the station's name is unique on the PC (operator 2026-11-16).

### When Status is sent (`StatusCadence`)

| Occasion | |
|---|---|
| the target becomes active | |
| a field of the message has changed | |
| a decode window of receive has begun since the last Status to the target | once for each, also for a window that began and ended in between |
| each pulse of the target | unchanged, also to a target that does not select the heartbeat |

Decoding is true from the start of a window's decode until that decode returns, however it
ends. Receive reports both in its status: whether a window is being decoded, and how many
windows have begun.

### What Status carries (`StatusFields`)

| Field | Content |
|---|---|
| Dial frequency | the dial that radio control confirms, else the nominal frequency of the operating selection, else 0 |
| Mode, Tx mode | FT8 or FT4, the station's operating mode |
| DX call, DX grid | those of the contact, else empty |
| Report | the report of the contact, else the report set for the station, as a plain number: "-9", "3", "0" |
| Tx enabled | transmission is armed |
| Transmitting | the station transmits |
| Decoding | see above |
| Rx DF, Tx DF | the receive and the transmit offset of the contact settings |
| DE call, DE grid | the profile's call and locator |
| Tx watchdog | the watchdog has expired |
| Special operation | the source's number for the activity of the contact settings |
| T/R period | 15 for FT8, 7 for FT4 |
| Configuration name | the station's name (`ProfileConfig::display_name`) |
| Tx message | the next message of the contact, else empty |
| Sub-mode, Fast mode, Frequency tolerance | empty, false, and the value the source reads as not applicable |

### What a Decode carries (`DecodeFields`, `DeltaTime`)

A record gives a Decode when its status is decoded and it carries the start of its period
(`period_start_utc`).
The records of the live receive job are taken in the order of their sequence, each once,
when they are published. A record that gives no Decode and a record published while no
target is active are not sent afterwards. A played recording is no live job.

| Field | Content |
|---|---|
| New | true |
| Time | the start of the record's period, as the time of day in UTC |
| SNR | the record's SNR rounded to a whole number, a half away from zero; 0 without one |
| Delta time | the record's DT in seconds, rounded to one decimal, a tie away from zero, in single precision; a magnitude below 0.05 gives 0; no DT gives 0 |
| Delta frequency | the record's frequency rounded to a whole number of Hz |
| Mode | "~" for FT8, "+" for FT4 |
| Message | the record's text; a standard message that acknowledges with R and carries a signal report has the R joined to the report ("R-09", "R+03"); a hashed call stands as the record gives it |
| Low confidence, Off air | false |

### Clear (`ClearRule`)

Clear goes to every target that selects it when the band of the operating selection
becomes another band than the last one it named, however the change comes about and
whether or not a Decode was sent since the last Clear. While the selection names no band,
the last band it named counts. **Every other change sends none.**

### Logged contacts (`LoggedFields`)

Both messages are made from the record the log has stored. They are sent when a record is
stored for the first time; a record stored already and records taken from an ADIF file
send none.

| Field of QSO Logged | Content |
|---|---|
| Date and time off, on | the record's end and start, in UTC |
| DX call, DX grid, Report sent, Report received, Tx power, Comments, My call, My grid | CALL, GRIDSQUARE, RST_SENT, RST_RCVD, TX_PWR, COMMENT, STATION_CALLSIGN, MY_GRIDSQUARE; an absent field is empty |
| Tx frequency | FREQ in Hz; 0 without one |
| Mode | SUBMODE where MODE is MFSK, else MODE |
| Name, Operator call, every field after Exchange received | empty |

| Activity of the record | Exchange sent | Exchange received |
|---|---|---|
| na_vhf, ww_digi, arrl_digi | first four characters of MY_GRIDSQUARE | first four of GRIDSQUARE |
| field_day, rtty | STX_STRING; without it RST_SENT, a blank, STX | SRX_STRING; without it RST_RCVD, a blank, SRX or else STATE |
| eu_vhf | RST_SENT, STX, a blank, first six characters of MY_GRIDSQUARE | RST_RCVD, SRX, a blank, first six of GRIDSQUARE |
| hound, none, no activity | empty | empty |

An exchange whose parts are not all in the record is empty.

Logged ADIF: an empty line, then `<adif_ver:5>3.1.8`, `<programid:9>WSTX-Rust` and `<EOH>`
each on its own line, then the record's fields as the log writes them, then ` <EOR>`.

### Close (`CloseRule`)

Close goes once to an active target that selects it: when a changed list leaves the target
out, disables it or changes its address, TTL or interface, before the socket is closed;
and when the station process ends on an interrupt or a close of its console, on a logoff
or on a shutdown of Windows. Transmission is released first, and Close is given to the
network without waiting.

## 5. Behaviour

The model has no state machine for the UDP sender. Its behaviour is the mapping of
occasions to messages in section 4. **Default: no other message of the source is sent, and
a datagram from a target that is not the Heartbeat described has no effect.**

## 6. Implemented in and tested by

| Element | Module |
|---|---|
| `UdpService` | `server/src/operating/qso/udp.rs`, `server/src/network_message.rs` |

The model names no detail tests for the UDP sender.

## 7. What it relies on from outside

Used and not defined here: FR-012; `WstxDecodes::ResultRecord` with its sequence, period
start, DT, SNR, frequency, text and status, the live receive job, and whether a decode runs
and how many windows have begun; `WstxUdpControl::UdpStationState`;
`WstxOperatingChain::FinishedContact`; the stored record of the log with its ADIF fields
and its activity; the activities na_vhf, ww_digi, arrl_digi, field_day, rtty, eu_vhf and
hound; the operating selection, the operating mode, the confirmed dial; the contact and
the contact settings; the profile's call, locator and display name; the session of
a FlexRadio.

Outside sources: WSJT-X at the behaviour baseline (`Network/NetworkMessage.hpp`,
`Network/MessageClient.cpp`, `widgets/mainwindow.cpp`, `widgets/mainwindow_qso.cpp`,
`widgets/logqso.cpp`); RFC 4291, section 2.7.

## 8. Differences from a named reference

Reference: WSJT-X at the behaviour baseline. These six are recorded as deliberate.

| Topic | Reference | This product |
|---|---|---|
| Played recording | sends its decodes with Off air true | sends no Decode |
| Commands | acts on Reply, Clear, Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch Configuration and Configure | acts on none |
| Header schema | takes a higher schema from any datagram it can read | only from a Heartbeat of the target's own address with the station's id |
| Status | sent on a change only | sent again at each pulse although nothing changed |
| Clear | sent whenever its Band Activity window is erased, by the operator as well | on a band change only |
| Logged ADIF | programid WSJT-X | programid WSTX-Rust, and the product's fields APP_WSTXRUST_CONTACT_ID, APP_WSTXRUST_SOURCE and APP_WSTXRUST_ACTIVITY |

The model also marks one unresolved conflict with the reference: the T/R period of Status.
This product sends 15 for FT8 and 7 for FT4; WSJT-X sends the value it reads as not
applicable in the modes whose T/R period control is not shown, FT8 and FT4 among them.

## 9. Verification

All twelve cases declare level 2, development PC, automation implemented.

| Case | Shows | Verifies | Test |
|---|---|---|---|
| TC-012-001 | the datagrams byte for byte, what is read as a Heartbeat, the text form; 5 conditions | CL-040-01, CL-040-03, CL-040-04 | `server/tests/udp_vectors.rs`, `server/src/log/udp_tests.rs` |
| TC-012-002 | the messages to two targets; 8 conditions | CL-040-01, CL-040-04 | `udp_tests.rs` |
| TC-012-003 | nothing a target sends acts on the station; the schema; 4 conditions | CL-040-03 | `udp_tests.rs` |
| TC-012-004 | the list of targets; 5 conditions | CL-040-02 | `udp_tests.rs` |
| TC-012-006 | IPv6 multicast targets; 5 conditions | CL-040-06 | `udp_tests.rs` |
| TC-012-007 | Status with the decode windows and the pulse; 5 conditions | CL-040-07 | `udp_tests.rs`, `server/src/recording_tests.rs` |
| TC-112-001 | the instance name; 2 conditions and a planned line | CL-112-01 | `udp_tests.rs` |
| TC-112-002 | the dial frequency and the report of Status; 2 conditions | CL-112-02 | `udp_tests.rs` |
| TC-112-003 | the delta time of a Decode; 2 conditions | CL-112-03, CL-040-04 | `udp_tests.rs` |
| TC-112-004 | Clear on a change of band only; 4 conditions | CL-112-04 | `udp_tests.rs` |
| TC-112-005 | the exchanges of QSO Logged; 7 conditions | CL-112-05 | `udp_tests.rs` |
| TC-112-006 | Close when the station ends; 2 conditions | CL-112-06 | `udp_tests.rs` |

Every clause has a case.

## 10. Open points, gaps and disagreements

Marked by the model:

1. (Answered 2026-11-16: `UdpControl` carries the configuration and `UdpStationState`.)
2. `StatusFields`, conflict: the T/R period, as in section 8.
3. Port `decodes`, not stated: how the UDP sender tells that a `ResultRecord` belongs to
   a live receive job and to which one, so that a played recording gives no Decode and a
   record is sent once; the record carries its sequence and no job.
4. Port `logged`, not stated: `FinishedContact` has no feature. The UDP sender needs the
   stored record of a contact, once, when the log stores it for the first time, and gives
   no `LogAnswer`.

Gaps found while writing this view:

1. The length of the pulse interval is the source's and is not in the model.
2. `Datagram` and `PeerHeartbeat` carry no field: they are messages in the source's
   format.
3. The activities of a record are named in words; no enumeration in the files read.
4. (Answered 2026-11-16: the targets and the instance name stand in `UdpSender.sysml` with
   `UdpService` as subject; the ten clauses of the exchange stay in the wire file.)

Disagreements: none between the files read.
