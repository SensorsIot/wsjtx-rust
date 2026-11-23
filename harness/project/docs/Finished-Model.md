# The finished model

**Layer:** HOW. **Scope:** the rules of this project's SysML model (`docs/sysml/`) and of its
binding to the code and the tests.

This document states what is true of the finished model and nothing else. Every rule has a
number (for example M3.2); a check of an issue or a file against this document names the
rule it meets or breaks. Where this document differs from a decision recorded on an issue,
the difference comes to the operator as a question; it is not resolved silently in either
direction.

Where these rules differ from the general [SysML authoring skill](../../general/core/skills/sysml-authoring/SKILL.md)
and the [SysML standard](../../general/core/docs/standards/sysml-v2.md), these rules win: the
skill lets the project harness fix a form. The differences are named in the rules: an FR
names no subject (M6.1); nothing satisfies a clause (M6.2); a test case stands planned
until its test is written, and a clause may have none (M6.5); a code link stands on the part (M6.6);
there is no `dependency` (M7.1).

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
- **M1.5** The model states the present only. It holds no history: no former name, no
  retired identity, no superseded text. History is in git.

## M2. The tree

- **M2.1** The model files (`.sysml`) and their folders are exactly these. There is no other
  model file. Beside them, `docs/sysml/data/` holds the data files the model names, and
  nothing else stands in `docs/sysml/`.

```
docs/sysml/
├── Context.sysml
├── Requirements.sysml
├── Shack.sysml
├── UseCases.sysml
├── interfaces/
│   ├── internal/   StationLink, StationCommands, Strategies, RankingControl, AutoControl,
│   │               QsoControl, LogControl, ReceiveControl, TransmitControl, AudioControl,
│   │               RadioControl, Keying, Decodes, DisplayData, StationTime, OperatingChain,
│   │               Hearing, AudioStreams, ModeProcessing, ProfileAccess, RecordingTransfer,
│   │               UdpControl, WebControl
│   └── external/   ExternalPort, OperatorInteraction, Mcp, Cat, RadioProperties, FlexApi,
│                   SoundDevice, Udp, PskReporter, ClubLog, CountryFiles, TimeSource
├── backend/
│   ├── supervisor/     Supervisor*, OperatingSelection, StationAuthority, Startup,
│   │                   SettingsCheck
│   ├── web/            Web*, Listener, ContentCoding
│   ├── mcp/            Mcp*, McpEndpoint
│   ├── profile/        Profile*, ProfileDocument, Recordings
│   ├── receive/        Receive*, ReceiveJob, Spectrum, LiveReceive
│   ├── modes/          Modes*, Decode, MessageEncode, MessagePayload
│   ├── clock/          Clock*, StationClock
│   ├── transmit/       Transmit*, TransmitState, Schedule, TxLevel
│   ├── operating/      Operating*, StrategySelection
│   │   ├── ranking/    Ranking*, ValueOrder, ContestRanking, IgnoreLists, WantedList,
│   │   │               MostWanted, Alert
│   │   ├── auto/       Auto*, TargetChoice, CqWhenIdle, TxSlot, Leave, AutoMode
│   │   └── qso/        Qso*, StandardQso, SpecialActivities, MessageChoice, QsoTransmit,
│   │                   HoldTx
│   ├── log/            Log*, Logbook, CountryFile
│   ├── spots/          Spots*, HearingFeed, SpotsReporting
│   ├── udp/            Udp*, UdpSender
│   ├── audio/          Audio*, AudioDevice, Capture, Endpoints, Playback
│   ├── radioControl/   RadioControl*, CatControl, CatLifecycle, RadioFacts, RadioSetup
│   └── flexAdapter/    FlexAdapter*, FlexSession
├── frontend/           BrowserClient*, OperatingScreen, BandActivityPane, SignalArea,
│                       QsoPane, LowerPanel, Settings
└── shared/             Units, ModelBindings, ModelNotes
```

`*` marks a part's own file. `operating` is a part: it owns the strategies and contests
and holds the parts ranking, auto and qso.

- **M2.2** A station's backend has eighteen function parts: supervisor, web, mcp, profile,
  receive, modes, clock, transmit, operating with ranking, auto and qso inside it, log,
  spots, udp, audio, radioControl and flexAdapter. The adapters and bindings toward the
  outside (audioAdapter, catAdapter) stand beside them.
- **M2.3** The code follows the tree. A part's Rust code stands in `server/src/<part>/`
  (operating: `server/src/operating/` with `ranking/`, `auto/` and `qso/`), its browser code
  in `client/src/<part>/`, code that no part owns in `server/src/shared/`, and a test file
  beside its module. Every code module belongs to exactly one part, by the part's
  `@ImplementedIn`. A part whose modules stand elsewhere carries `@CodeDiffers` on its part
  definition, naming them.

## M3. Layers

- **M3.1** The order of the layers is: shared, interfaces, parts (`backend/*`, `frontend`),
  Shack, Context, UseCases.
- **M3.2** A file imports only from layers before it, and from Requirements. UseCases takes
  its actors from Context.
- **M3.3** A part never imports another part. What two parts share stands in their interface.
- **M3.4** The control interfaces are the interfaces of the functions that
  `WstxStationLink::WireNames` lists. A control interface imports no transport file
  (StationLink, Mcp) and not the operating chain's interface file (OperatingChain); it may
  import another control interface for a type that interface's function owns. A type stands
  in the control interface of the function that owns it. An external interface imports no
  control interface. StationCommands is the supervisor's
  control interface: the one set of commands that web and mcp both give, and the
  supervisor's own state and records.

## M4. What each kind of file holds

| Rule | File | Holds | Holds nothing else, in particular |
|---|---|---|---|
| **M4.1** | Context | the things the station exchanges messages with (people, programs, radios, services), each as a black-box part with a port and a connection | no inner structure of an outside thing; no requirement names one as subject; no file or operating-system service that one function reads or writes by itself: that is described with the function that uses it |
| **M4.2** | Requirements | the authority marker; each FR: number, title, one sentence; the behaviour baseline (the WSJT-X release the product is compared with) | no status, code link, issue reference, phase or date; no subject; no clause, test case or other requirement; no import of a part, an interface or `Shack` |
| **M4.3** | Shack | composition, connections, and the allocation of FRs to parts | no clause, no data |
| **M4.4** | A part's own file | its part definition, its ports and its code link (`@ImplementedIn`) | |
| **M4.5** | A function file | one function of the part: its clauses, behaviour, data and test cases | |
| **M4.6** | A control interface | the commands and state data of its function, defined once | |
| **M4.7** | A transport file | routes, wire field names, byte limits, the error body, the MCP tool catalogue, and data no single function owns (heartbeat, session); a view where the wire carries less than the function holds | no copy of a field its function defines |
| **M4.8** | Any other interface file | the port type, the two ends it joins, what crosses, and the clauses about the exchange itself | |
| **M4.9** | UseCases | the end-to-end processes of the actors of Context with the shack: goal, actors, steps and variants, each step subsetting the clauses that carry it, and the outcome | no rule, no value, no clause; no step that names a clause only in text |

## M5. Architecture

- **M5.1** The shack is the setup on one PC: one operator, and the stations, each with its
  own profile, its saved configuration. A station is the program that operates one radio,
  or one slice of a FlexRadio, with its UI: its frontend (the browser clients) and its
  backend (its process). The word "station" names nothing else. The station is the single
  source of truth for everything about itself. What the stations of the shack share (the
  shack's settings with the call sign and the locator, the strategies, the UDP and PSK
  Reporter configuration, the logbook) stands in the shack's folder: each station reads it,
  and changes it only under the file's lock and revision. Every fact has exactly one owning
  function.
- **M5.2** The browser and agents hold copies only: a snapshot, pushed changes and
  requests. A request is not a fact until the station has accepted it. The browser is the
  origin of one thing only: its presentation preferences.
- **M5.3** Commands and state pass through the supervisor, which is the only gate through
  which a change from outside enters. Commands reach a function only from the supervisor.
- **M5.4** A stream connects its producer and its consumer directly inside the station
  process.
- **M5.5** StationLink is the only connection between the browser and the server. The
  browser client has one port toward the station, and the frontend connects only to `web`;
  its port toward the operator is the context's.
- **M5.6** The radio is a slave of the station.
- **M5.7** A strategy defines, ranking orders, Auto executes. Whatever decides or acts at
  run time belongs to Auto. The operating chain commands only downward: ranking, auto, qso,
  transmit. An answer on the same connection is not a command upward.
- **M5.8** Every connection is typed by an interface from `interfaces/`, is named after what
  flows over it, and carries no empty item. An item is empty when it carries nothing
  nameable: no type, or a type with neither doc nor feature. A command whose type is the
  whole message is not empty; an abstract grouping item stands when a typed item subsets it.
- **M5.9** Receive and transmit do not know which radio type is in use: samples pass
  through audio, control passes through radio control.
- **M5.10** The operator is the licensed person who operates the shack's stations through
  their browsers. An agent is a program that operates a station through its MCP. It gives
  every command the browser gives except saving the station config and saving the shack's
  settings: the station's setup is the operator's. The word "user" does not occur.
- **M5.11** A port definition specializes `ExternalPort` only where its interface crosses a
  process, device or network boundary and something reacts to its status. A transition guard
  reads a status's availability, never its reason. `status` is `out` on the port definition
  that specializes `ExternalPort`; nothing else redefines or derives it.

## M6. Requirements, clauses and tests

- **M6.1** An FR is about the station as a whole and names no subject; `Shack.sysml` gives
  it to the part that carries it. Its status is computed from its clauses: implemented when
  all are implemented, target when all are target or it has none, partial otherwise.
- **M6.2** A clause stands in the function file of its part, names that part as its
  subject, and derives from one FR, the one its part serves. That it uses another function's
  output, or is shown on a screen, adds no second FR. Nothing satisfies a clause formally:
  the subject names its owner.
- **M6.3** A clause about an exchange stands in the interface file, with the interface as
  its subject.
- **M6.4** A clause is one promise: one sentence with MUST, SHOULD or MAY, complete without
  its values. Its values, ranges, sequences and rules stand in the typed element it names,
  one sentence per feature, effect or rule. A clause is divided only where its members
  belong to different parts, are shown by different tests or change for different reasons.
- **M6.5** A test case stands beside its clause and verifies it. It is a skeleton and a
  title: its identity, a one-line title, `subject`, `verify`, `@TestLevel`, `@Automation`
  and `@TestedBy`; the bound test is the description of the test. A case whose test is not
  yet written is `planned` and has no `@TestedBy`; a partial or implemented case is bound
  only to tests that show what its clause promises. A clause without a case stands at target
  or partial; built and tested is `implemented`, and an implemented clause has a bound case. A clause that prevents something (a refusal, a
  disabled control, a MUST NOT) has a case bound to a negative test: a test that tries it
  and sees it refused.
- **M6.6** Status and test links are tags on the clause and on its case. The code link
  (`@ImplementedIn`, the modules) is a tag on the part definition, and a clause inherits it;
  a clause whose code lies in other modules carries its own, which wins.
- **M6.7** Model and code are bound in both directions by stable names: the model binds a
  case to its tests (`@TestedBy`), and each such test names its cases in a tag
  (`// Proves: TC-022-004`), on the test itself. A tag names test cases only: no FR, no
  clause, no shorthand, no issue number. A detail test carries no tag; its file is named by
  its part's `@DetailTests`.
- **M6.8** A contract test takes its values from the model. Every value of the model is
  verified in one of two ways: the code holds it in a constant named after the value's
  feature, which the model tool compares; or a contract test bound to the clause's case reads
  it from the model and compares a measured behaviour with it. No test compares a value of
  the program with itself.
- **M6.9** Every clause and every test case names its subject.
- **M6.10** The element that holds a clause's values and rules stands directly after the
  clause, in the same file, and the clause's sentence names it. Where that element uses
  something defined in another file, it refers to it by type, not only by name in a text.
- **M6.11** Every clause is carried by a step of a use case (`UseCases`), except a clause of
  a debugging function, which carries `@Debugging`.
- **M6.12** An identity keeps its meaning and is never declared again with another one. The
  model lists only the identities that exist; one that any earlier commit of the main
  branch declared counts as used. A new identity takes the next free number of the series
  it was split from.
- **M6.13** Where the code does not yet do what the model states, the model says so in the
  present: by the status of the clause (target or partial), or, for a value, a name or an
  enumeration literal below the clauses, by `@CodeDiffers` on the element, saying what the
  code does today. Where the code matches, there is no `@CodeDiffers`.

## M7. Notation

- **M7.1** The links are `satisfy` (an FR by a part, in Shack), `verify` (a clause by a test
  case), derivation (a clause from an FR) and the subsetting of a clause by a step of a use
  case. There is no `dependency`.
- **M7.2** Status, test level and test location are typed values, not sentences.
- **M7.3** No text restates what the structure already says: its own number, its clause
  list, its cost.
- **M7.4** No text tells history: no date, no issue number, no "formerly", no "replaces".
- **M7.5** A definition is named in UpperCamelCase; a feature, an enumeration literal and an
  action in lowerCamelCase. No name holds an underscore. A package is named `Wstx` followed
  by its file's name; a part's own file adds `Part` (`WstxClockPart`). A name on the wire or
  in the station's files is the model name as `WstxStationLink::WireNames` writes it; a name
  of an outside format (ADIF, FlexRadio, PSK Reporter) and an id that is data stay as their
  source writes them.
- **M7.6** A model file holds model elements only. The one comment is the authority marker
  `// Canonical authority: SysML` on the first line of `Requirements.sysml`; there is no
  other `//` comment and no `/* */` outside a `doc`. Lines are wrapped at 100 characters; a
  path or a test name is not split.

## M8. Finished

- **M8.1** The model is finished when every rule above holds on the main branch.
- **M8.2** Every rule that a tool can check is checked in the gate, with no exemption list.
  Every check has, besides its accepted case, one negative test per way its rule can be
  broken.
- **M8.3** Every rule names its check:

| Check | Covers |
|---|---|
| `python tools/sysml.py check`, in the gate | M1.5 (no retired identity), M2.1, M2.3, M3, M4.1 to M4.3, M4.9, M5.5, M5.8, M5.10, M5.11 (the guard and the status direction), M6.1, M6.2, M6.4, M6.5 (form, a bound partial or implemented case, an implemented clause has a bound case), M6.6, M6.7, M6.9 to M6.13, M7.1, M7.3 to M7.6 |
| The reviewer's reading of the candidate | M0.2, M0.3, M1.1 to M1.4, M5.1 to M5.4, M5.6, M5.7, M5.9, M5.11 (only where something reacts), M6.3, M6.5 (a preventing clause has a negative test), M6.8, M7.2 |

## Authoring

How a statement gets into the model. These rules apply wherever the model is written.

- **A1 Clean files.** The model files are the canonical source of the project, without
  contradictions, duplications, omissions, comments or old text. A defect found is repaired
  in the model at once, also in a part not otherwise touched; a note elsewhere is no repair.
- **A2 No functional description beside the model.** An FSD is written only on request, as
  a view of the model ([fsd-from-model](../../general/core/skills/fsd-from-model/SKILL.md)).
- **A3 Inside or outside.** A statement is sorted by one question: could two correct
  implementations differ on it without anyone outside the part noticing? If so, it is code
  and is not written. A test case is sorted the same way: one that shows something at a part
  boundary stands; one of the inside is a detail test of its part.
- **A4 Values.** A value is of one of three kinds. A value of a protocol or another source
  is not written: the source reference covers it. A value of a test (a sample size, a
  count that describes a fixture, a tolerance) stands in the bound test. A value of the
  promise (a limit, a share, a range that someone outside the part relies on) stands in the
  clause's element. That a test reads a value from the model, or that the code holds it,
  does not make it a promise.
- **A5 Limits of time.** A limit of time is a value of the code unless something outside the
  part waits on the number or it bounds the transmitter's switch; the model then says that
  the thing ends in time. A cadence is no limit.
- **A6 Evidence.** A statement stands on evidence: the code and its tests, or the operator's
  decision, which makes its clause target. What has neither is not written, and not marked
  either.
- **A7 Negative statements.** "Never does X" is written only where a function exists that
  could do X. Where one exists, the case is made impossible by a type if it can be, and
  otherwise the rule is stated in the positive: what the result is used for, what stays.
- **A8 A model file follows the thing,** not the code's modules.
- **A9 Names.** A name that no longer says what the thing is, is renamed, and what cites it
  is changed in the same change.
