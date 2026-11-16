# Log

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the three files of `backend/log/`,
`interfaces/internal/LogControl.sysml`, of `interfaces/internal/OperatingChain.sysml` the
elements of the three connections of the log, and of `Station.sysml`, `Context.sysml` and
`interfaces/internal/ProfileAccess.sysml` only the lines that attach the log. Not read: the
code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Logbook | the QSOs of the operator, kept as the file `contacts.adi` in the operator's folder, shared by up to six stations | `Logbook` |
| Record | one QSO of the logbook, as its ADIF fields | `LogRecord` |
| Finished contact | a contact that qso hands to the log at its completion | `FinishedContact`, `DirectLog` |
| Waiting record | a record of a finished contact that is not stored yet | `DirectLog` |
| Newest QSO | the record that began to wait last, otherwise the last record of the logbook | `SameStationAgain` |
| Effective band | the band of a record; without one the band that contains its frequency; otherwise unknown | `LogRecord::band` |
| Effective mode | the submode when the mode is MFSK, otherwise the mode | `LogRecord::submode` |
| Confirmed | a record whose LoTW, QSL card or eQSL status is Y or V | `LogRecord::lotwQslRcvd` |
| Update | taking the QSOs of another logging program's ADIF file into the logbook | `UpdateLogbook` |
| Present | a record of an update that the logbook already holds | `UpdateLogbook` |
| Worked set | what the logbook holds per call, grid, entity, continent, zone and prefix | `WorkedSet`, `WorkedBeforeQuery` |
| Standing | worked or not, confirmed or not, for one key in one scope | `Standing` |
| Scope | ever, on a band in any mode, on a band in a mode | `WorkedSet` |
| Entity | the DXCC entity a call resolves to | `CallEntity`, `EntityOfCall` |
| Country file | the file that maps calls to entities: the bundled one, or the operator's | `CountryFile`, `ProfileCountryFile` |

"Source" has two meanings: the program a record came from (`LogRecord::source`) and
whether the country file is bundled or uploaded (`CountryFileSource`).

## 2. Place in the system

Position: `Station` > `Backend` > `StationProcess` > `log : LogService`. `Station.sysml`
gives FR-011 to the log.

| Port of the log | Type | Other end | Interface | What crosses |
|---|---|---|---|---|
| `control` | `~LogControlPort` | station service, `log` | `LogControl` | in: `LogContext`, `SaveRecord`, `ReserveImport`, `ImportChunk`, `ReadImport`, `ExportLog`, `ReadHistory`, `ReadCountryFile`, `ReplaceCountryFile`, `EntityRequest`, `ResendLast`; out: `SaveAnswer`, `Resent`, `ImportView`, `ExportChunk`, `HistoryPage`, `CountryFileState`, `EntityAnswer`, `LogRefused`, `LogAttempt` |
| `completed` | `~CompletedContactPort` | qso, `completed` | `CompletedContact` | in: `FinishedContact`; out: `LogAnswer` |
| `logged` | `LoggedContactPort` | udp, `logged` | `Station.sysml` types this connection `CompletedContact` | out: `LoggedContact` (each new record once, and the newest again on `ResendLast`) |
| `workedBefore` | `WorkedBeforePort` | ranking, `workedBefore` | `WorkedBefore` | in: `WorkedWindow`, `EntityRequest`, `ContestPeriod`; out: `WorkedSet`, `EntityAnswer`, `PeriodQsos` |

Not connected: receive, the modes part, transmit, auto, spots, audio, radio control, the
clock, web and mcp. The log therefore learns the operator's callsign and locator, the dial
of the radio and the dupe rule of a contest from the station service alone
(`LogContext`), and it takes a finished contact from qso alone.

Limit: `FinishedContact` has no feature; the two items of `ProfileAccess` are empty;
the connection to udp is typed in `Station.sysml` by an interface whose port is not the
log's.

## 3. Purpose and requirements

The log keeps the operator's logbook, stores every finished contact in it once, takes
in the log of another program, gives the newest record again on Log QSO, and tells what
has been worked and to which entity a call belongs. All seven clauses derive from FR-011.

| Clause | Promise | Element | Status |
|---|---|---|---|
| CL-010-04 | store every finished contact as one record, call it saved only when durable, keep a record it cannot store for a later attempt | `Logbook`, `DirectLog`, `SaveContact` | partial |
| CL-010-19 | give the newest record again as `LoggedContact` when the operator asks (Log QSO) | `ResendRule` | target |
| CL-085-01 | refuse a finished contact when the newest QSO is with the same station on the same band in the same mode | `SameStationAgain` | implemented |
| CL-010-18 | take the QSOs of another program's ADIF file in so that each stands once; give the logbook out whole and page by page | `UpdateLogbook`, `ExportAdi`, `ContactHistory` | implemented |
| CL-010-13 | tell ranking what has been worked and what is confirmed | `WorkedBeforeQuery` | implemented |
| CL-055-01 | resolve a call to its DXCC entity with continent, zones and position, as WSJT-X does | `EntityOfCall`, `CountryFile` | implemented |
| CL-055-03 | use the operator's country file in the place of the bundled one once it reads without a fault; return to the bundled one on request | `ProfileCountryFile` | implemented |

The status is the model's declaration.

## 4. Data and rules

### The record (`LogRecord`)

ADIF names follow from the feature names (rstSent is RST_SENT); the exceptions are FREQ,
COMMENT, CLASS, STATE and the three application fields. An absent feature is not written.

| Field | What the log stores for a finished contact and a saved record |
|---|---|
| contact id (APP_WSTXRUST_CONTACT_ID) | a UUID |
| CALL | 3 to 13 characters of A to Z, 0 to 9 and "/", at least one digit |
| GRIDSQUARE | a locator of 4 or 6 characters; absent when not known |
| MODE, SUBMODE | FT8; or MFSK with FT4 |
| RST_SENT, RST_RCVD | a signed report from -50 to +49, an RST 5n9 (n 2 to 9), or an RS 52 to 59 |
| QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF | UTC, YYYYMMDD and HHMMSS; the end not before the start |
| BAND | of the ADIF enumeration, lower case |
| FREQ | MHz with six decimals, inside the band |
| STATION_CALLSIGN, MY_GRIDSQUARE | the profile's callsign and locator |
| TX_PWR | a positive decimal of at most 16 characters |
| COMMENT | one line of 1 to 1024 printable ASCII characters without "<" and ">" |
| STX, SRX | 1 to 4 digits |
| STX_STRING, CONTEST_ID, SRX_STRING, CLASS, ARRL_SECT, STATE | 1 to 32 printable ASCII characters without "<" and ">" |
| LOTW_QSL_RCVD, QSL_RCVD, EQSL_QSL_RCVD | Y, N, R, I or V, either case |
| LOTW_QSLRDATE, QSLRDATE, EQSL_QSLRDATE | a date |
| QSL_RCVD_VIA | B, D, E or M |
| source (APP_WSTXRUST_SOURCE) | 1 to 32 letters, digits and "-"; absent on the station's own records |
| activity (APP_WSTXRUST_ACTIVITY) | field_day, rtty, eu_vhf, na_vhf, ww_digi, arrl_digi, hound; absent for none |

A record taken from another program's file keeps what the file says, within the wider
limits of the update (below).

### Limits (`LogLimits`, `DirectLog`, `UpdateLogbook`)

A value at a limit is taken, one over is refused.

| Limit | Value |
|---|---|
| file of an update | 67,108,864 bytes |
| records in the file of an update | 100,000 |
| one part of that file | 16,384 bytes |
| value of a field | 1024 characters |
| name of a field | 64 characters |
| records in a page of the history | 10 |
| a page of the history as the station link sends it | 16,384 bytes |
| records in one part of an export | 128 |
| country file given by the operator | 1,048,576 bytes |
| records that wait to be stored | 64 |
| time to the next attempt to store | 5 s |
| an update without a part blocks the next one | for 60 s |
| two starts count as one QSO in an update | at most 120 s apart |
| reasons listed for skipped records, and for dropped fields | 16 each |

### The logbook's file (`Logbook`)

| Rule | |
|---|---|
| place | `contacts.adi` in the operator's folder: a header, then one line for each record in the order of adding; every station of the operator logs to it |
| order of fields | CALL to EQSL_QSLRDATE as declared, then contact id, source, activity, then the fields the record does not name, as they were read |
| header | ADIF 3.1.8, the time the logbook was opened, WSTXRUST and its version |
| identity | one record for each contact id; a record is added at the end and keeps its index; a stored record is not changed and not removed, but for a confirmation the update adds |
| a change | only while the log holds the file's lock, which another station's log waits for; a new record appended and made durable; a confirmation's change writes the whole file anew beside the old one, made durable, put in place in one step; a failed change leaves file and logbook as they were and no other file behind |
| other stations | before the log uses the logbook it takes in the records another station has added since it last read the file |
| a missing file | an empty logbook |
| reading at station start | each record within the update's limits for a file, the contest fields taken as they are; a confirmation field given twice or outside the limits is kept as an unnamed field |
| unavailable | file not readable; not a well-formed ADIF file; a record with another fault, without CALL, QSO_DATE, TIME_ON or MODE, or without contact id; two records with one contact id. Every command is then refused with `storageUnavailable` and the file is left as it is |

### What the station service gives (`LogContext`)

Callsign and locator of the profile (upper case, absent while the profile has none), the
dial frequency (absent while radio control has not confirmed one), the dupe rule of the
contest in force (absent while the active strategy is not a contest strategy). Given at
station start and whenever a value changes.

### Commands and answers (`LogControlPort`)

| Command | Carries | Answered by |
|---|---|---|
| `SaveRecord` | a record | `SaveAnswer` (saved, alreadySaved, conflict) or `LogRefused` |
| `ReserveImport` | id, size (1 to the file limit), SHA-256 | `ImportView` or `LogRefused` |
| `ImportChunk` | id, start byte, size of the file, the bytes | `ImportView` or `LogRefused` |
| `ReadImport` | id | `ImportView` or `LogRefused` |
| `ExportLog` | | `ExportChunk`, as many as needed, or `LogRefused` |
| `ReadHistory` | cursor (0 to the number of records), limit (1 to 10) | `HistoryPage` or `LogRefused` |
| `ReadCountryFile` | | `CountryFileState` |
| `ReplaceCountryFile` | the text, or none to return to the bundled file | `CountryFileState` or `LogRefused` |
| `EntityRequest` | a call | `EntityAnswer` |
| `ResendLast` | | `Resent` (the contact id given again, none for an empty logbook) or `LogRefused` |

A command and its answer are one exchange. `LogRefused` names one of `LogRefusal`: storageUnavailable, profileIncomplete,
logInvalidField, stateConflict, busy, notFound, invalidRequest, tooLarge, importFailed,
outOfRange, invalidCty; with the field refused, or the line of a country file. A refused
command changes nothing.

`ImportView`: id, state (receiving, completed, failed), bytes received and expected,
added, present, confirmed, skipped, up to 16 reasons and up to 16 groups of dropped
fields (`ReasonGroup`: `AdiError`, field, count, first record), and the fault of a file
refused as a whole (`AdiFault`: `AdiError`, record from 0, field).

`LogAttempt`, reported without a command: what became of the finished contact dealt with
last: contact id, call, saved or not, and why not (`LogError`: storageUnavailable,
logInvalidField, sameStationAgain).

### What has been worked (`WorkedSet`, `WorkedCategory`, `Standing`, `WorkedStatus`)

| Category | Key |
|---|---|
| call | the call, upper case |
| grid | the first four characters of the grid; none without them |
| dxcc | the name of the call's entity as the country file writes it |
| continent, cqZone, ituZone | those of the entity; a call without an entity counts for none of the four |
| prefix | the prefix by the rules of the CQ WPX contest |

A set is made for a window (`WorkedWindow`: every QSO, or a first and a last UTC date).
For a key it gives a `Standing` ever, on a band in any mode, and on a band in a mode. A
key is new where it is not worked, and needed where it is not worked or not confirmed.
For a call it also gives the `WorkedStatus` (notWorked, workedOtherBandOrMode,
workedThisBandAndMode), whether a QSO with it has no grid, and the US state of its latest
QSO that names one, a confirmed QSO first, read from every QSO whatever the window.

`PeriodQsos` answers a `ContestPeriod` (first instant, first instant after): call, grid,
effective band, effective mode and start of each QSO that started in it.

### The entity (`CallEntity`)

Name as the file writes it, shown name (1 to 40 printable ASCII characters), primary
prefix, continent (AF, AN, AS, EU, NA, OC, SA), CQ zone (0 to 40), ITU zone (0 to 90),
latitude north, longitude east.

## 5. Behaviour

**Default: whatever is not listed changes nothing; a refused command changes nothing.**

### A finished contact (`DirectLog`)

| Occasion | Result |
|---|---|
| any finished contact | one `LogAnswer`; the record takes callsign and locator from `LogContext`, BAND as the band of the dial, FREQ as dial plus the contact's Tx offset, neither without a dial; no TX_PWR, COMMENT, source or confirmation |
| the same station again | refused (below) |
| a record outside what `LogRecord` allows | not stored, `logInvalidField`; answered accepted |
| every other record | waits, in the place of a waiting record of the same contact |
| storing, oldest first, at once | new contact id: added and given once as `LoggedContact`; a contact id already held: nothing changes |
| a record cannot be stored | it and those behind it wait (`storageUnavailable`); tried again a few times within a short time, then given up: not in the logbook, not given |

### Log QSO (`ResendRule`)

The operator's Log QSO, for a logging program that was not running when the QSO was
logged: the log gives the last record of the logbook, whatever wrote it, again as
`LoggedContact` and answers `Resent` with its contact id; the logbook is not written. An
empty logbook gives nothing; an unavailable one refuses with `storageUnavailable`.

### The same station again (`SameStationAgain`)

A finished contact is the same station again when its call equals the newest QSO's
without regard to letter case, and effective band and effective mode are equal. K1ABC/P
is another station than K1ABC; an unknown band equals only an unknown band. A record of
the contact itself is not the newest QSO. Under the dupe rule `band_grid`, two grids
that are both known and differ in their first four characters make it another QSO. A
refused contact writes nothing, is not given as `LoggedContact`, shows as
`sameStationAgain` and is answered refused. Time plays no part. `SaveRecord` and an
update are not judged, and their records can be the newest QSO.

### A saved record (`SaveContact`)

| Occasion | Result |
|---|---|
| no callsign in `LogContext` | `profileIncomplete` |
| a record outside what `LogRecord` allows | `logInvalidField` with a field that is outside |
| a contact id the logbook does not hold | added, saved, given once as `LoggedContact` |
| a contact id it holds | alreadySaved when the stored record has the same fields and no unnamed one; otherwise conflict; nothing written |
| it cannot be stored | `storageUnavailable`; the same record can be given again |

### An update (`UpdateLogbook`)

| Step | Rule |
|---|---|
| reserve | one update at a time: another id is `busy` while the last reservation or part is less than 60 s old; the same id with the same size and SHA-256 gives the update as it stands; with other values `stateConflict` |
| parts | each begins where the last ended; the completing part ends the update; an ended update is kept until the next reservation or the station's stop |
| the file | UTF-8, a byte order mark skipped; a header up to EOH when it does not begin with a tag; tags `NAME:LENGTH` or `NAME:LENGTH:TYPE`, either case, the length in characters; records end with EOR; white space only between fields; PROGRAMID of 1 to 32 letters, digits and "-" names the program, otherwise ADIF |
| refused as a whole | SHA-256 not as reserved (checked first); bytes not UTF-8 or a control character outside a value; a broken tag, a missing EOH or EOR; a length beyond the file; a name over 64; more than 100,000 records. The fault names the record |
| a value is faulty | longer than 1024; not printable ASCII; followed by other text than white space; outside the limits for a file |
| limits for a file | CALL, STATION_CALLSIGN: 1 to 32 letters, digits, "/"; grids of 2, 4, 6 or 8 characters; MODE, SUBMODE: 1 to 32 letters, digits, "-"; reports up to 16 characters; dates from 1930; times HHMM or HHMMSS; BAND in either case; FREQ, TX_PWR positive decimals; the rest as the record says |
| skipped | CALL, QSO_DATE, TIME_ON or MODE missing or faulty; a field of the record twice |
| dropped | any other faulty field; its record is taken without it |
| present | the contact id is in the logbook or was added before from this file; or the same call, effective band and effective mode with starts at most 120 s apart (a time without seconds starts at second 0) |
| a present record | stays as it is, but takes, for each of LoTW, QSL card and eQSL that the file confirms and it does not, the status and, where given, date and via; nothing is taken away or lowered |
| added | at the end, in the order of the file, with a new contact id when it has none and the file's program as source when it names none |
| writing | everything in one change of the file; when that fails nothing is written and the update has failed |
| `LoggedContact` | none for an update |

### Export and history (`ExportAdi`, `ContactHistory`)

The export is the logbook as it is when asked for: a header with the time of the export
and every record as the file holds it, in parts of 128 records in the order of the file,
the header with the first. A page of the history holds the records from the cursor on, at most the limit and
fewer when the page would exceed 16,384 bytes, but at least one; a cursor at the number of
records gives an empty page; a cursor beyond it or a limit out of range is `outOfRange`.

### Making a worked set (`WorkedBeforeQuery`)

A set counts the records of its window (both dates included). A record counts ever, on
its effective band when it has one, and on that band in its effective mode. A key is
confirmed where a confirmed record counts for it. The status of a call ignores letter
case; a record without a band is never on this band. After a change of the logbook or of
the country file a set is made anew; ranking gets the set made last at once and the new
one when it is made. An unavailable logbook gives no set.

### Resolving a call (`EntityOfCall`)

| Step | Rule |
|---|---|
| no entity | an empty call, a character outside ASCII, an ending /MM or /AM |
| effective prefix | endings after "/" taken off from the right while they are a digit, A, M, P, Q, R, QRP, FD, FF, AM, MM, LH, LT or LGT; then the shorter side of a remaining "/", the left one when equal |
| exact entry | decides when the effective prefix is not the whole call and the file has one for the whole call |
| otherwise | the longest entry that begins the effective prefix; an exact entry only when as long as the whole call |
| KG4 | with neither three nor five characters: the entity whose primary prefix is K |
| answer | the entity with the entry's own CQ zone, ITU zone, continent and position; the shown name shortened, a WAE-only entity shown as its DXCC entity |

### The country file (`CountryFile`, `ProfileCountryFile`)

Reading: a line with fewer than seven ":" is skipped; each other line begins an entity
whose entries follow up to ";"; an entry given twice keeps its first entity; an exact
entry VER and eight digits is the version. Refused with the entity's line: an unreadable
number, a CQ zone above 40 or ITU zone above 90, an unknown continent, a shown name not
of 1 to 40 printable ASCII characters, no primary prefix, entries without ";"; a file
without an entity with line 1.

| Occasion | Result |
|---|---|
| a text that reads | stored as `cty.dat` in the operator's folder under the file's lock, in one step; in use from then on, also after a station start |
| a text that does not read | `invalidCty` with the line |
| a text over 1,048,576 bytes | `invalidRequest` |
| it cannot be stored | `storageUnavailable` |
| no text | the stored file is taken away; the bundled file is in use |
| at station start, a stored file that cannot be used | left as it is; bundled in use; `uploadUnreadable` |

## 6. Implemented in and tested by

| Element | Module |
|---|---|
| `LogService` | `server/src/logbook.rs`, `server/src/dxcc.rs` |
| CL-010-04, CL-085-01 | also `server/src/contact_http.rs` |

The model names no detail tests for the log.

## 7. What it relies on from outside

Used and not defined here: FR-011; `FinishedContact` and `CompletedContactPort` (qso);
`DupeRule` (the strategies); `ProfileAccess` (the profile); the band of the dial and the
profile's callsign and locator, through the station service.

Outside sources: ADIF 3.1.8 (fields, enumerations, the ADI file format); AD1C cty.dat;
the rules of the CQ WPX contest for a prefix.

## 8. Differences from a named reference

The reference is WSJT-X at the behaviour baseline.

| Topic | WSJT-X | The log | Recorded as |
|---|---|---|---|
| GRIDSQUARE without a value | written empty | not written | deliberate |
| Log QSO | appends the QSO to the log again | gives the newest record again to the logging programs; the logbook is not written | deliberate |
| NAME, OPERATOR, PROP_MODE, SAT_NAME, SAT_MODE, FREQ_RX | written when it has them | no such field | deliberate |
| "<", ">" and characters outside printable ASCII in a value | taken out, or written as "?" | the value is refused; none is changed | deliberate |
| the same station twice in a row | every logged QSO is added | the second is refused | deliberate |

Followed: the field set and its order, the resolution of a call, the shortening of names,
and the scope "on a band in any mode" of the worked set.

## 9. Verification

| Case | Shows | Verifies | Level | Test |
|---|---|---|---|---|
| TC-011-001 | a finished contact logged once, the logbook kept whole, Log QSO resends (planned); 12 conditions | CL-010-04, CL-010-19 | 2, development PC | 11 named tests in `udp_tests.rs`, `contact_http_tests.rs`, `logbook_tests.rs` |
| TC-085-001 | the same station in a row logged once; 4 conditions | CL-085-01 | 2, development PC | 3 named tests in `contact_http_tests.rs` |
| TC-085-002 | what counts as the same station; 8 conditions | CL-085-01 | 2, development PC | 4 named tests in `logbook_tests.rs`, `contact_http_tests.rs` |
| TC-085-003 | the newest QSO after a restart, while a record waits, from outside; 5 conditions | CL-085-01 | 2, development PC | 2 named tests in `contact_http_tests.rs` |
| TC-011-002 | the update, the export, the history; 13 conditions | CL-010-18 | 2, development PC | 14 named tests in `logbook_tests.rs`, `logbook_http_tests.rs`, `udp_tests.rs` |
| TC-011-003 | what has been worked; 8 conditions and 1 planned | CL-010-13 | 2, development PC | 9 named tests in `logbook_tests.rs`, `dxcc_tests.rs` |
| TC-055-001 | calls resolved against known answers; 4 conditions | CL-055-01 | 2, development PC | 3 named tests in `dxcc_tests.rs` |
| TC-055-003 | the operator's country file; 6 conditions | CL-055-03 | 2, development PC | 1 named test in `logbook_http_tests.rs` |

Every clause has a case. One condition is written as planned, with no test yet: the US
state of a call and the QSOs of a contest period (TC-011-003 i).

## 10. Open points, gaps and disagreements

Marked by the model:

1. `DirectLog`, not stated: `FinishedContact` has no feature. The record needs from it the
   identity of the contact, the partner's call and grid, the mode, the two reports, start and end, the contest fields,
   the activity and the Tx offset.
2. `PeriodQsos`, not stated: which part holds the rules by which a contest counts these
   QSOs (dupes, points, multipliers, score).
3. (Answered 2026-11-15: the log has no connection to the profile; `LogContext::folder`
   gives the folder.)

Gaps found while writing this view: four, all repaired in the model (the order of the
parts of an export, the matching of an answer to its command, the source of the prefix
rule, and a field order that the model had promised without stating it); the fifth is
marker 3.

Disagreements and observations:

1. `Station.sysml` types the connection from `log.logged` to `udp.logged` by
   `CompletedContact`, whose ports carry `FinishedContact` and `LogAnswer`; the log's port
   is `LoggedContactPort` and carries `LoggedContact`.
2. `LogAnswer` names `LogError::sameStationAgain` in text only.
3. `Continent` exists twice: in `WstxLogControl` and in `WstxRankingControl`.
