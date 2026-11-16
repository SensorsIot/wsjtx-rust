# The finished model

Operator, 2026-11-15. This document describes the SysML model of wsjtx-rust as it is when
the conversion is finished. It states what is true of the finished model and nothing else:
it does not say what the model looks like today or how to get there.

Every rule has a number (for example M3.2). A check of an issue or a file against this
document names the rule it meets or breaks.

Where this document differs from a decision recorded on an issue, the difference comes to
the operator as a question. It is not resolved silently in either direction.

## M0. What the model is for

- **M0.1** The model exists for three things: it tells the definer what holds, the Markdown
  documentation is written from it, and it keeps the objects in order (each thing has one
  owner and one place, and nothing dangles).
- **M0.2** A construct that serves none of the three is not written.
- **M0.3** A part is well written when its functional description can be produced from it
  without a gap.

## M1. What the model contains

- **M1.1** The model states what the station promises to the outside and how its parts are
  joined. It states nothing that two correct implementations could do differently without
  anyone outside the part noticing.
- **M1.2** The model has three levels: the skeleton (parts, ports, interfaces, connections,
  states, events, data), prose (one sentence per effect or rule), and references to code
  and tests.
- **M1.3** Every state, event, data value and connection is skeleton. Prose introduces none.
- **M1.4** Every fact stands in exactly one place. Everything else refers to it.

## M2. The tree

- **M2.1** The model files (`.sysml`) and their folders are exactly these. There is no other
  model file.

```
docs/sysml/
├── Context.sysml
├── Requirements.sysml
├── Station.sysml
├── interfaces/
│   ├── internal/   StationLink, StationCommands, Strategies, RankingControl, AutoControl,
│   │               QsoControl, LogControl, ReceiveControl, TransmitControl, AudioControl,
│   │               RadioControl, Keying, Decodes, DisplayData, StationTime, OperatingChain,
│   │               Hearing, AudioStreams, ModeProcessing, ProfileAccess, RecordingTransfer,
│   │               UdpControl
│   └── external/   OperatorInteraction, Mcp, Cat, RadioProperties, FlexApi, SoundDevice,
│                   Udp, PskReporter, ClubLog, TimeSource
├── backend/
│   ├── station/        Station*, OperatingSelection, StationAuthority, Startup
│   ├── web/            Web*, Listener, ContentCoding
│   ├── mcp/            Mcp*, McpEndpoint
│   ├── profile/        Profile*, Recordings
│   ├── receive/        Receive*, ReceiveJob, Spectrum, LiveReceive
│   ├── modes/          Modes*, Decode, MessageEncode, MessagePayload
│   ├── clock/          Clock*, StationClock
│   ├── transmit/       Transmit*, TransmitState, Schedule, TxLevel
│   ├── operating/      Operating*, StrategySelection
│   │   ├── ranking/    Ranking*, ValueOrder, ContestRanking, IgnoreLists, WantedList,
│   │   │               MostWanted, Alert
│   │   ├── auto/       Auto*, TargetChoice, CqWhenIdle, TxSlot, BusyPause, Leave, Watchdog
│   │   └── qso/        Qso*, StandardQso, SpecialActivities, MessageChoice, HoldTx
│   ├── log/            Log*, Logbook, CountryFile
│   ├── spots/          Spots*, HearingFeed
│   ├── udp/            Udp*
│   ├── audio/          Audio*, AudioDevice, Capture, Endpoints, Playback
│   ├── radioControl/   RadioControl*, CatControl, CatLifecycle, RadioFacts, RadioSetup
│   └── flexAdapter/    FlexAdapter*, FlexSession
├── frontend/           BrowserClient*, OperatingScreen, BandActivityPane, SignalArea,
│                       QsoPane, LowerPanel, Settings
└── shared/             Units, Quantities, ModelBindings, ModelNotes
```

`*` marks a part's own file. `operating` is a part: it owns the strategies and contests
and holds the parts ranking, auto and qso.

- **M2.2** A station process has eighteen function parts: station, web, mcp, profile,
  receive, modes, clock, transmit, operating with ranking, auto and qso inside it, log,
  spots, udp, audio, radioControl and flexAdapter. The adapters and bindings toward the outside
  (audioAdapter, catAdapter) stand beside them.

## M3. Layers

- **M3.1** The order of the layers is: shared, interfaces, parts (`backend/*`, `frontend`),
  Station, Context.
- **M3.2** A file imports only from layers before it, and from Requirements.
- **M3.3** A part never imports another part. What two parts share stands in their interface.
- **M3.4** A transport file (StationLink, StationCommands, Mcp) and the operating chain's
  interface file may import a control interface. A control interface imports none of them.

## M4. What each kind of file holds

| Rule | File | Holds | Holds nothing else, in particular |
|---|---|---|---|
| **M4.1** | Context | the things the station exchanges messages with (people, programs, radios, services), each as a black-box part with a port and a connection | no inner structure of an outside thing; no requirement names one as subject; no file or operating-system service that one function reads or writes by itself: that is described with the function that uses it |
| **M4.2** | Requirements | each FR: number, title, one sentence; the behaviour baseline (the WSJT-X release the product is compared with) | no status, code link, issue reference, phase or date; no subject; no clause, test case or other requirement; no import of a part, an interface or `Station` |
| **M4.3** | Station | composition, connections, and the allocation of FRs to parts | no clause, no data |
| **M4.4** | A part's own file | its part definition and its ports | |
| **M4.5** | A function file | one function of the part: its clauses, behaviour, data and test cases | |
| **M4.6** | A control interface | the commands and state data of its function, defined once | |
| **M4.7** | A transport file | routes, wire field names, byte limits, the error body, the MCP tool catalogue, and data no single function owns (heartbeat, session); a view where the wire carries less than the function holds | no copy of a field its function defines |
| **M4.8** | Any other interface file | the port type, the two ends it joins, what crosses, and the clauses about the exchange itself | |

## M5. Architecture

- **M5.1** The station process (one per profile) is the single source of truth for
  everything about its own station. What the stations of one operator share (the
  operator's settings, the strategies, the UDP and PSK Reporter configuration, the
  logbook) stands in one shared folder of the operator: each station reads it, and
  changes it only under the file's lock and revision. Every fact has exactly one owning
  function.
- **M5.2** The browser and agents hold copies only: a snapshot, pushed changes and
  requests. A request is not a fact until the station has accepted it. The browser is the
  origin of two things only: its identity key and its presentation preferences.
- **M5.3** Commands and state pass through the station service, which is the only gate
  through which a change from outside enters. Commands reach a function only from the
  station service.
- **M5.4** A stream connects its producer and its consumer directly inside the station
  process.
- **M5.5** StationLink is the only connection between the browser and the server. The
  browser client has one port, and the frontend connects only to `web`.
- **M5.6** The radio is a slave of the station.
- **M5.7** A strategy defines, ranking orders, Auto executes. Whatever decides or acts at
  run time belongs to Auto. The operating chain commands only downward: ranking, auto, qso,
  transmit. An answer on the same connection is not a command upward.
- **M5.8** Every connection is typed by an interface from `interfaces/`, is named after
  what flows over it, and carries no empty item.
- **M5.9** Receive and transmit do not know which radio type is in use: samples pass
  through audio, control passes through radio control.
- **M5.10** The operator is the licensed person who operates the station through the
  browser. An agent is a program that operates it through MCP, with equal rights. The word
  "user" does not occur.

## M6. Requirements, clauses and tests

- **M6.1** An FR is about the station as a whole and names no subject; `Station.sysml` gives
  it to the part that carries it. Its status is computed: implemented when all its
  clauses are, partial when some are, target when none is or it has no clause.
- **M6.2** A clause stands in the function file of its part, names that part as its
  subject, and derives from one FR. Nothing satisfies a clause formally: the subject names
  its owner.
- **M6.10** The element that holds a clause's values and rules stands directly after the
  clause, in the same file, and the clause's sentence names it. Where that element uses
  something defined in another file, it refers to it by type, not only by name in a text.
- **M6.3** A clause about an exchange stands in the interface file, with the interface as
  its subject.
- **M6.4** A clause is one promise: one sentence with MUST, SHOULD or MAY, complete without
  its values. Its values, ranges, sequences and rules stand in the typed element it names,
  one sentence per feature, effect or rule. A clause is divided only where its members
  belong to different parts, are shown by different tests or change for different reasons.
- **M6.5** A test case stands beside its clause and verifies it.
- **M6.6** Status, code links and test links are tags on the clause.
- **M6.7** Model and code are bound in both directions by stable names.
- **M6.8** A contract test takes its values from the model.
- **M6.9** Every clause names its subject.

## M7. Notation

- **M7.1** The links are `satisfy` (an FR by a part), `verify` (a clause by a test case)
  and derivation (a clause from an FR). There is no `dependency`.
- **M7.2** Status, test level and test location are typed values, not sentences.
- **M7.3** No text restates what the structure already says: its own number, its clause
  list, its cost.
- **M7.4** No text tells history: no date, no issue number, no "formerly", no "replaces".

## M8. Finished

- **M8.1** The model is finished when every rule above holds on main.
- **M8.2** Every rule that a tool can check is checked in the gate, with no exemption list.
- **M8.3** Every rule names its check. During the rebuild there are three:

| Check | Covers |
|---|---|
| The script `docs/sysmlV2/_work/check.py`, run after every part | M2.1, M4.2, M5.10, M6.2, M6.4, M6.10, M7.1, M7.3, M7.4, and lines over 100 characters |
| The part's functional description, written from the new files alone | M0.3, M1.2, M1.3, M1.4: a table cell that no model element fills is a gap, and two elements that disagree are listed |
| The operator's reading of the part, its description and its report | M0.2 and M1.1, which are judgements; the report lists what was dropped as code |

  The structure rules M3, M4.1, M4.3 and M5 are checked by the model tools.

## Open points

These are not decided by this document. Each needs the operator's answer before the rule
it touches is applied.

1. **M2.1, `interfaces/internal/Keying.sysml`** exists on main and is not in the tree. It is
   decided when transmit and radio control are built.
2. **M2.1, log:** answered (operator 2026-11-15): the contest counting stands in
   `ranking/ContestRanking.sysml`; the log gives the QSOs of a period.
3. **M6.2 differs from the authoring skill,** which asks for a subject and a satisfier on
   every requirement. The project's form wins (operator 2026-11-15): a satisfier of a
   clause serves none of the three purposes of M0.1.
4. **The model tools must run on `docs/sysmlV2`** for the structure rules; whether they can
   is not yet known.

5. **M2.1, other content of `docs/sysml/`:** the folders `data/` (`hamlib-models.json`) and
   `reference/` hold no model file. Whether they stay there is not decided here.

## Sources

The rules restate, without their history: the consolidated target structure on #53
(2026-11-13) with its additions of the same day, the harness standard `sysml-v2.md`
("What belongs in the model"), the authoring skill, and the model tools' contract in
`tools/sysml/README.md`.
