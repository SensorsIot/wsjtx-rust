# Report: the top files

2026-11-15. The files above the parts, checked against the foundation.

## The files

| File | Lines | State |
|---|---|---|
| `Context.sysml` | 83 (was 200) | **rewritten**, see below |
| `Station.sysml` | 229 (was 266) | **rewritten**, see below |
| `Requirements.sysml` | 139 (was 586) | **rewritten**, see below |
| `shared/Units.sysml` | 17 | in order |
| `shared/ModelBindings.sysml` | 17 | in order |
| `shared/ModelNotes.sysml` | 22 | in order |
| `shared/Quantities.sysml` | – | named by the tree, does not exist, and nothing asks for it |

## Context.sysml, rewritten

| Change | Rule |
|---|---|
| The enumeration `OutsideThing` is gone. It listed the same thirteen things as the parts below it, and its text contradicted them (two `@Conflict` markers). | One fact, one place (M1.4). The parts stay (M4.1). |
| The source of each outside format stands once, on the interface that stands for the format: `Cat`, `FlexApi`, `SoundDevice`, `Mcp`, `Udp`, `PskReporter`. `ClubLog` and `TimeSource` had theirs. | Authoring, data and formats, rule 1. |
| The part `mcpClient` is named `agent`. | M5.10. |
| The Windows time service is the clock's, not transmit's. | From the code (`windows_time.rs` is read by the clock). |
| References to packages that no longer exist are removed from the texts. | M7.4, M1.4. |
| The package of `Station.sysml` is `WstxStation` (was `WstxArchitecture`); of the Mcp interface `WstxMcp` (was `WstxMcpInterface`). | The package rule. |

The package rule is refined: a part's own file adds `Part` (`WstxClockPart`), because four
parts share their file name with an interface: Station, Udp, Mcp, RadioControl.

Not validated: the file names every part through `Station.sysml`, so the validator can run
on it only when the tree is complete.

## Outside things without a connection (decided, operator 2026-11-15)

Five entries of the old context had no port and no connection: the browser program, the
Windows time service, the profile files, the TLS files and the lock files. Checked in the
old model and in the code: each is a file or a service that one function reads or writes
by itself, and none is something the station exchanges messages with. Three of the five
rows were wrong: the time service was given to transmit (the clock reads it), the lock
files were one entry for two different locks with an owner that uses neither, and the
profile files were one thing where three functions each own their own files.

They leave the context. Each fact is on the handover list for the function that uses it;
the browser program is dropped, because nothing uses it as a thing. M4.1 now says the
context holds what the station exchanges messages with.

## Station.sysml, rewritten

It holds the parts, their connections and the allocation of the FRs, as M4.3 asks.

**The allocation of FRs, corrected**

| FR | Old | New | Why |
|---|---|---|---|
| FR-001 station setup | station service | profile | the settings are the profile's |
| FR-006 time and sequencing | transmit, receive | clock, transmit, receive | the clock holds station time |
| FR-011 logging | qso | log | log is its own part |
| FR-012 integrations | station service | udp, spots | they speak the outside protocols |
| FR-019 browser operator interface | web | the browser clients | web is the link, not the interface |
| FR-021 station server and remote operation | the browser attachments | web | web serves the link |
| FR-023 FlexRadio | not allocated | flexAdapter | |
| FR-024 contest and special activities | not allocated | qso | |
| FR-026 strategies and ranking | ranking, station service | ranking | one owner |
| FR-013, FR-014, FR-015 | modes, receive, modes | – | retired |

The others are unchanged.

**Other changes**

| Change | Rule |
|---|---|
| Two part types are renamed: `QsoAndLogging` to `QsoService`, `RustRadioDriver` to `CatAdapter`. | A name does not claim what the thing is not. |
| The profile's package is `WstxProfilePart`. | The package rule. |
| 44 imports are gone, 17 of them of radio properties that the file never used. | M3.2 |
| The package text, three text blocks on `Backend` and two trailing ones are replaced by one sentence each. They named packages that no longer exist, phases, and what the model is not. | M7.4; the rule on negatives |
| A connection gives station time to audio. | The decision on the capture clock. |
| The connections are grouped by what flows over them. | Readable in slices. |

**One marker.** Five connections on the radio's control path have no interface: the path
from radio control to the common authority, to the CAT adapter and to the Flex adapter.
M5.8 asks that every connection is typed by an interface. They are marked `@NotStated` and
are settled when radio control is built.

**Checks.** The script finds nothing. The validator reports no syntax error; it cannot
resolve the parts, because their own files are not built yet. The names this file expects
from them:

- the ports `time` on receive, transmit, qso and audio;
- the part types `QsoService` and `CatAdapter`;
- the package `WstxProfilePart`.

## Work for the tools, when the new tree goes to main (Station)

The architecture tests and the oracle file name `QsoAndLogging`, `RustRadioDriver` and
`PersistedProfile`; one code test names `QsoAndLogging`.

## Requirements.sysml, rewritten

It holds 23 FRs, each a number, a title and one sentence, and the behaviour baseline.
It imports nothing but the notes.

| What the old file held | Result | Rule |
|---|---|---|
| 26 FRs with a hand-written status and a list of code files | The 26 FRs, one sentence each. No status, no code list. | M4.2, M6.1 |
| Phase and issue wording in titles and texts ("phase 1 target", "#8 must settle", "issue #40", dates) | removed | M7.4 |
| `subject station : StationProcess` on FR-025 and FR-026, with a `@Conflict` because the validator could not match it | No FR names a subject. The marker is resolved. | M0.2, M3.2: the subject would be the same on all 26 and would make this file import `Station` |
| The status enumerations | moved to `shared/ModelBindings`, which uses them | data follows its users |
| An index of aliases to every package of the model | removed | M3.2: through it every file depended on every other |
| Five requirements about the model's own structure, with one tool-tested and two planned review cases | Not carried. The structure itself, the finished model and the tool checks state them; two of their sentences are false by now. The planned cases have no test. | M1.4; no evidence, no statement |
| `ProductCapabilities`, `QualityAndVerification` | not carried: the first repeats the FR list, the second is test policy | M1.4; outside the product model |
| `ModeCapability`, `BaselineMode`, `AccelerationPolicy`, `ReleasePolicy`, `FixtureProvenance` | not carried: plans with no evidence in the code, or facts about test data | no evidence, no statement |
| `SharedDataOwnership`, `ProcessingAndHaltOwnership`, `RemoteDeliveryPolicy`, `RadioModelReferenceSeparation` | Their real promises are on the handover list for transmit, the station service, the station link and radio control. | a promise belongs to one part |
| `BehaviorBaseline` | kept, with its three values checked against `fixtures/decoder/reference-manifest.json` | the definer needs it |

**FR wording changed where the target record or today's decisions say so:** FR-006 now
names station time; FR-007 is "QSO sequencing" with the target's text; FR-025 and FR-026
have the target's text.

**One marker:** the baseline says v3.3.0-beta4, which is what the fixtures pin. 36 texts of
the old model cite beta5 and two cite beta6 as the reference of their own function.

Validated together with the shared files and the clock: no error in these files.

## Work for the tools, when the new tree goes to main

- `tools/sysml.py` requires the packages `WstxRequirements` and `WstxArchitecture`; the
  second is `WstxStation` now.
- It reads the status enumerations by name; they now stand in `ModelBindings`.

## FRs retired (operator 2026-11-15)

FR-013 (EME), FR-014 (wideband reception) and FR-015 (utilities) came from the feature list
of WSJT-X. They have no clause, no code and no test, and they are retired. Their numbers
are not used again.

Two other FRs have no clause in the old model and stay: FR-017 (help and notices), for
which the browser shows the version, and FR-025 (automatic operation), whose clauses still
derive from FR-007 in the old model.

## Found while checking

- The clock's values use the suffixes `S` and `Pct` (`windowS`, `sameSidePct`).
  `shared/Units` knows `Seconds` and no percent. The clock's names need to follow it.
