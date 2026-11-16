**Duplicate check**
Searched in all issues, open and closed: "settings", "settings store", "station config", "settings page", "Advanced Diagnostics", "profile.json", "qso-settings", "tx-level", "pskr.json", "udp.json", "receive-startup", "watchdog", "browser storage", "localStorage". Main has no commit that sorts the stores (the last commits are model conversions and the binding; `docs/sysmlV2` is not on main).

- #110 (closed) saved Auto Seq and Call 1st in a file of their own, `qso-settings.json`. This issue replaces that file; it is not the same change.
- #37 (closed) made the Settings drawer with General, Radio, Logging & Reporting and Expert. This issue regroups it.
- #209 (open) makes the RF power one stored value in a new file `rf-power.json` in place of `power_limit_pct`. It names a store, not the sorting; see Sequence.
- #195 (open) adds one setting (the PSK Reporter broker). One setting, not the sorting; see Sequence.
- #226 (open) removes the authorization and with it `authorization.json`. Another file, another reason.
- #124, #125 (open) are about the content of the wanted and ignore lists, which stay definition files.

None asks for this change.

**Problem**
A station keeps what the operator sets in many places, each made by the function that needed it: `profile.json` holds the name, call, locator, audio devices, radio control, AGC and power limit; seven more files in the profile's folder hold the rest (table under Model and code); the two limits of the Tx watchdog are kept nowhere and start at 6 and 90 with every station start. Records the software keeps for itself lie beside them as further files, and one file (`receive-startup.json`) holds a setting and a record together. Each of these files has its own route, its own revision or none, and its own refusals. The Settings page follows the same history: General, Radio, Logging & Reporting, Expert.

The operator decided on 2026-11-15:

- **Three stores.** One config for each station holds everything the operator sets. One hidden store of the station holds what the software keeps across sessions; no menu shows it. Each frontend has a config of its own for its display.
- **Files of their own stay.** Definition files (strategies, lists, the country file) and data files (the logbook, the recording) are not settings.
- **A setting belongs to the part that uses it.** The profile only stores. A change of a setting takes one way.
- **Where a setting shows and where it is stored are two things.** The Settings page groups by object and has a menu Advanced with a group Diagnostics.

Goal: the code stores and shows the settings as decided.

Value: the operator finds a setting by the thing it belongs to and finds every value as it was left after a restart, the Tx watchdog limits included, instead of setting the limits again at every start and looking for a setting in the section where it happened to be built.

WSJT-X keeps everything in one settings file (`Configuration.cpp`, `QSettings`), display and window state included, and saves both watchdog limits (`TxWatchdog`, default 6; `TuneWatchdogTime`, default 90).

**Functionality**

Already covered: the profile's own values, the audio devices, the radio control and the AGC are saved in `profile.json` through one save with a revision, by `server/src/profile.rs` and `PUT /profile` (CL-005-02, TC-022-001 to -003).
Already covered: definition files and data files are files of their own in the profile's folder: `strategy.json` (`server/src/strategy.rs`), `most_wanted.json` (`most_wanted.rs`), `cty.dat` (`dxcc.rs`), `contacts.adi` (`logbook.rs`), the stored recording (`recording.rs`).
Already covered: the display choices are kept by each browser, in its storage (`client/recording.js`, `client/contact.js`).

**Model impact**

The contract was written first. The rebuilt model under `docs/sysmlV2` states the stores for the parts that are built; `docs/sysmlV2/_work/settings.csv` names the model home of each of the 53 settings. The rows below are what the model does not state yet.

| Element | Today | Change | Why |
|---|---|---|---|
| `interfaces/internal/ProfileAccess.sysml` `StationConfig`, `StationMemory`, `SaveProfile`, `SaveMemory`, `MemorySnapshot` | state the two stores and the one way of a change | none | already the contract |
| `backend/profile/Profile.sysml` `CL-005-02`, `CL-005-06`, `KeepMemory`, `SaveSettings` | CL-005-02 partial, CL-005-06 target | change: the status of both when the code follows | a status follows the code |
| `backend/profile/Profile.sysml` `TC-022-002` (k) | "Planned, no test yet" | change: (k) gets its conditions and its tests | the proof of both stores |
| `interfaces/internal/ProfileAccess.sysml` `ProfileDocument` (marker) | the keys of five configurations in the file, their names in `SaveRefused::field` and their place in the order of refusals are not stated | change: stated; the marker goes | open question 3 |
| `backend/profile/Profile.sysml` `KeepMemory` (marker) | the file and form of the hidden store, and what an unreadable one means, are not stated | change: stated; the marker goes | open question 2 |
| `backend/profile/Profile.sysml` `SaveSettings` (marker) | whether a save the station makes itself counts the revision is not stated | change: stated; the marker goes | open question 4 |
| `backend/transmit/TxLevel.sysml` `TxLevel` (marker) | who refuses a level set by hand while the radio reports its ALC or a Set level run goes | change: stated; the marker goes | open question 5 |
| `interfaces/internal/QsoControl.sysml` (taken over, not rebuilt) | no configuration of qso; `ContactAction` has `set_auto_seq`, `set_call_first`, `set_watchdogs`; `TxWatchdog` tells the limits as qso's | add: qso's configuration (Auto Seq, Call 1st, special activity, Rx and Tx offset), collected in `StationConfig`. Remove: the three set actions and the limits (they are `TransmitConfig::txCalls` and `::tuneSeconds`) | a setting is defined with the part that uses it; one way for a change |
| the station service's startup function (`backend/station/`, not built; the tree names no file for it here) | not written | add: "Monitor off at startup" as its configuration in `StationConfig`; the receive choice to resume as its record in `StationMemory` | today one file holds both |
| `frontend/Settings.sysml` (in the tree, not built) | not written | add: the groups of the Settings page, Advanced with Diagnostics, and the config of one frontend | the screen owns where a setting shows |
| `interfaces/internal/StationLink.sysml` (taken over, not rebuilt) | names the routes of the functions' own files | change when the station link is rebuilt: one save route carries the station config | one way for a change |

- **Tree:** no new file is certain. Where the station service's startup configuration and the config of a frontend are written is not named by `Foundation/1-Finished-Model.md` beyond `frontend/Settings`; see open questions 1 and 7.
- **Identities:** CL-005-06 exists (new on 2026-11-15, no test case yet); it gets one from the series TC-022 (TC-022-007 is free in the ledger). TC-022-002 (k) is filled. CL-110-01 with TC-110-001 to -004 (handed over to qso) is reworded when qso is built: the saving is the profile's (CL-005-02). CL-045-01 (handed over to the station service) likewise. TC-007-009 (the four sections of the drawer) is reworded for the new groups. The identities the part reports already changed (CL-040-02, CL-039-26, CL-044-12, TC-012-004, TC-039-020, TC-039-048, TC-044-014, TC-052-001, TC-039-005) stand as the model has them; their tests follow.
- **Other parts:** the station service gives each part its configuration and its records from the profile's snapshots at station start and after every change, and brings the saves (`ProfileAccess`). Transmit gives a level it has found as `LevelFound`; radio control and audio hand over their records as `RadioMemory` and `AudioMemory`.
- **Model and code:** the model states the change for profile, audio, radio control, transmit, receive, spots, udp and ranking. The code differs as follows; this is the work.

| Setting or record | In the code today | Goes to | Model home |
|---|---|---|---|
| Transmit audio level | `tx-level.json`, `server/src/radio_level.rs` (`store_level`, `startup`, `set_manual`) | station config | `TransmitConfig::levelDb` |
| Power limit | `settings.radio.power_limit_pct` in `profile.json`, only for a managed radio | station config, transmit's value | `TransmitConfig::powerLimitPct` |
| Tx watchdog calls, Tune limit | no file: `Core::new` in `server/src/transmit/service.rs` sets 6 and 90; `set_watchdogs` changes the running process only | station config | `TransmitConfig::txCalls`, `::tuneSeconds` |
| Save FT8 decode windows | `receive-diagnostics.json`, `server/src/receive/receive_diagnostics.rs` (`load`, `set_window_dump`); `/receive/diagnostics` | station config | `ReceiveConfig::window_dump` |
| PSK Reporter: read the feed, runs use it | `pskr.json`, `server/src/operating/qso/pskr.rs` (`start`, `set_enabled`, `set_use`); `/pskr`, `/pskr/use` | station config | `SpotsConfig::enabled`, `::'use'` |
| UDP targets | `udp.json` with a revision of its own, `server/src/operating/qso/udp.rs` (`Owner::open`, `Owner::put`); `PUT /udp` | station config | `UdpConfiguration::targets` |
| Session minutes of the session ignore list | inside `strategy.json`, `server/src/strategy.rs` (`Configuration`) | station config | `RankingConfig::sessionIgnoreMinutes` |
| Auto Seq, Call 1st | `qso-settings.json`, `server/src/contact_http.rs` (`saved_settings`, `save_settings`) | station config | qso's configuration (not written) |
| Monitor off at startup | `receive-startup.json`, `server/src/receive/receive_startup.rs` (`set_monitor_off`); `/receive/startup` | station config | the startup configuration (not written) |
| Receive choice to resume | the same file (`load`) | hidden store | the startup record (not written) |
| Keying inhibit confirmed | `radio-keying-confirmed.json`, `server/src/radio_setup.rs` | hidden store | `RadioRecords::keyingConfirmed` |
| Undo record of the radio menu settings | `radio-settings-undo.json`, `server/src/radio_setup.rs` (`read_undo`, refusal `invalid_undo_record`) | hidden store | `RadioRecords::settingsUndo` |
| Last known names of the endpoints | `audio-endpoint-names.json`, `server/src/radio_setup.rs` (`remember`) | hidden store | `AudioRecords::lastNames` |
| A file for each record | `Store::read_document_file`, `write_document_file`, `remove_document_file` in `server/src/profile.rs`, called by each function | one hidden store kept by the profile | `KeepMemory` |
| Theme, band colours, waterfall speed, zero, range, flatten, spectrum line, display choice, alerts | nine keys in the browser's storage (`wstx.theme.v1`, `wstx.band-colours.v1`, `wstx.waterfall-*.v1`, `wstx.spectrum-line.v1`, `wstx.display-profile.v1:<id>`, `wstx.alerts.v1:<id>`), `client/recording.js`, `client/contact.js` | one frontend config | the frontend's config (not written) |
| The Settings page | four sections, `client/index.html`; `drawerItems` in `tests/ui-operating.test.cjs` | groups by object | `frontend/Settings` (not written) |

Not found in any file: the special activity and the Rx and Tx audio offset (`qso-settings.json` holds `auto_seq` and `call_first` only). Whether they are kept elsewhere was not read; `settings.csv` marks both "not checked". WSJT-X saves both.

Promises:

1. The station MUST keep every value the operator sets in the one station config of its profile, and MUST keep none of them in a file of a function's own.
2. A change of a setting MUST take one way: the save of the station config, answered when the new config is durable; each part then gets its new configuration. No function has a set command or a save route of its own for a config value.
3. The station MUST keep the two limits of the Tx watchdog across a restart (1 to 99 calls, 6 until set; 1 to 300 s, 90 until set).
4. The station MUST keep what its parts want kept across sessions in the one hidden store, and no menu and no page shows it (CL-005-06).
5. A station that was updated MUST start with the values its old files held (open question 3 says how).
6. Each frontend MUST keep its display choices in one config of its own; the station stores none of them.
7. The Settings page MUST group the settings by object: Station, Radio, Flex (only on a station of the native connection), Operating, Strategies and contests, Files, Destinations, Display and Advanced.
8. Advanced MUST hold the group Diagnostics with the switch "Save FT8 decode windows" and the import of the recording, and MUST show the station's address, origin and connection type without a way to change them.
9. A definition file MUST be opened from the Settings page and MAY be edited there or in an external editor.

What stays as it is: the rule and range of every value; `profile.json` as the file of the station config, its revision, its refusals, its locks and how it is written; `strategy.json` (without the session minutes), `most_wanted.json`, `cty.dat`, `contacts.adi`, the stored recording and the folder `diagnostic-windows` as files of their own; the active strategy, the selected contest and the session ignore list as state of the session, not stored; the status views of UDP, PSK Reporter and the Tx level; the Set level run. `authorization.json` is not touched here (#226).

**Test cases**

1. Station config across a restart (TC-022-002 (k)): on a profile of the sound device connection save the Tx level -28 dB, the power limit 50, 4 calls, 120 s, the window dump on, the PSK feed off and its use off, two UDP targets, 5 session minutes, Auto Seq off, Call 1st off, Monitor off at startup on. Stop and start the station: every value is as saved, `profile.json` holds them all, and the folder holds none of `tx-level.json`, `receive-diagnostics.json`, `pskr.json`, `udp.json`, `qso-settings.json`, `receive-startup.json`.
2. One way (promise 2): each value of case 1 changes by the save of the station config, with the revision one higher; a save from an older revision is refused with `revision_conflict` and no value changes. The former set commands and save routes are refused as unknown (`set_watchdogs`, `set_auto_seq`, `set_call_first`, the saving half of `/pskr`, `/pskr/use`, `/udp`, `/receive/startup`, `/receive/diagnostics`).
3. Values outside their rule: 0 and 100 calls, 0 and 301 s, the power limit 0 and 101, 0 and 721 session minutes, a UDP target outside `UdpTarget`: each refused with `invalid_settings` and its field, the file byte for byte as before.
4. Effect without a restart: 4 calls saved while the transmit state is on shows in the remaining calls at once; a Tune limit holds for the next tone; a changed target list is followed by the sockets at once; the window dump holds from the next window.
5. Hidden store (new case of TC-022 for CL-005-06): the keying confirmed, one undo record and the last names of two endpoints are kept, the station stopped and started: all three as kept; `profile.json` and its revision unchanged by keeping them; a store that cannot be kept is answered with the store of before; a store never kept gives every record as its definition gives it. No reply of a settings read and no element of the Settings page shows a record.
6. A level found (TC-044-014): a Set level run ends with -28 dB; after a restart the level is -28 dB; a level that does not come back as saved is not used.
7. Update (promise 5): a profile's folder as the current release writes it, with all old files and known values, is started with the new station: the values are those of the old files, and the old files are gone or left as open question 3 decides.
8. Frontend config: with a theme, band colours, speed 2, zero 5, range 40, flatten on, the spectrum line on, the display choice Thin and alerts with sound set, the page reloaded: all as set; the station's files are byte for byte as before; a second browser on the same station shows its own choices.
9. Settings page (TC-007-009 reworded): the groups are exactly those of promise 7, in that order; each control of `settings.csv` stands in the group its column "Menu: where it shows" names; Advanced > Diagnostics holds the switch and the import; the address, origin and connection type are shown and cannot be edited; no element shows the client identity of a Flex station, the endpoint names or the resume choice.
10. Files of their own: `strategy.json`, `most_wanted.json`, `cty.dat`, `contacts.adi` and the stored recording are byte for byte as before after cases 1 to 9.

**Reading list**

Model (`docs/sysmlV2`):
- `START-HERE.md`, "Open points that wait", the settings; `_work/settings.csv` (the 53 settings: who sets, where shown, kind, stored today, stored by decision, WSJT-X, model home).
- `interfaces/internal/ProfileAccess.sysml`: `StationConfig`, `StationMemory`, `ProfileConfig`, `ProfileDocument`, `SaveProfile`, `SaveMemory`, `MemorySnapshot`, `SaveRefusal`, `SaveRefused`.
- `backend/profile/Profile.sysml`: `PersistedProfile`, CL-005-02, `SaveSettings`, CL-005-06, `KeepMemory`, TC-022-001 to -003.
- The configurations and records: `TransmitControl.sysml` `TransmitConfig`, `LevelFound`; `ReceiveControl.sysml` `ReceiveConfig`; `Hearing.sysml` `SpotsConfig`; `external/Udp.sysml` `UdpConfiguration`; `RankingControl.sysml` `RankingConfig`; `RadioControl.sysml` `RadioConfig`, `RadioRecords`, `RadioMemory`; `AudioControl.sysml` `AudioConfig`, `AudioRecords`, `AudioMemory`.
- `backend/transmit/TransmitState.sysml` `TxWatchdog`; `backend/transmit/TxLevel.sysml` `TxLevel`; `backend/receive/ReceiveJob.sysml` `WindowDiagnostics`; `backend/spots/HearingFeed.sysml` `FeedSwitches`; `backend/radioControl/RadioSetup.sysml` `KeyingConfirmation`, `RecommendedSettings`; `backend/audio/Endpoints.sysml` `EndpointNaming`.
- `_work/*-report.md`, section "Changed after the report: the settings", of profile, transmit, receive, spots, udp, ranking, radioControl and audio: what left each part and the differences in the code.
- Not rebuilt and still telling the old way: `interfaces/internal/QsoControl.sysml` (`ContactAction`, `ContactCommand`, `TxWatchdog`), `interfaces/internal/StationLink.sysml`.

Code: `server/src/profile.rs`, `radio_level.rs`, `radio_setup.rs`, `contact_http.rs`, `strategy.rs`, `transmit/service.rs`, `receive/receive_diagnostics.rs`, `receive/receive_startup.rs`, `operating/qso/pskr.rs`, `operating/qso/udp.rs`, the routes in `main.rs` (548 to 598), `mcp.rs` (its `/profile` use); `client/index.html`, `client/contact.js`, `client/recording.js`.

Tests: `tests/profiles.test.cjs`, `tests/ui-operating.test.cjs` (`drawerItems`), and under `server/src`: `profile_tests.rs`, `radio_level_tests.rs`, `radio_setup_tests.rs`, `receive/*_tests.rs`, `contact_http_tests.rs`, `strategy_tests.rs`, `transmit_state_tests.rs`, the tests of `pskr.rs` and `udp.rs`.

**Open questions**

1. **Where is a frontend's config kept?** WSJT-X: in the one settings file on the PC of the program. Recommendation: in the browser's storage as one entry for each station, in place of the nine keys; the station stores nothing of a frontend, and each station is reached under its own origin.
2. **The file and form of the hidden store, and an unreadable one.** WSJT-X has no such store. Recommendation: one file in the profile's folder, written like `profile.json`; a store that cannot be read gives every record as its definition gives it (the keying is then not confirmed, no undo is offered) and is replaced by the next keep.
3. **The keys of the new configurations in `profile.json`, and the update of a station in use.** WSJT-X reads a missing key as its default. Today an absent key makes the file no valid profile. Recommendation: the keys are the names of `StationConfig` (`transmit`, `receive`, `spots`, `udp`, `ranking`, and qso's and the startup's when written); at the first start a document without them is completed once from the old files, saved with the revision one higher, and the old files are removed, as `EndpointIds` already changes a device name to its id at station start.
4. **Does a save the station makes itself (a level found) count the revision?** WSJT-X has no revision. Today the level's file leaves the revision alone, and radio control takes another revision as another radio connection. Recommendation: it counts, so that a settings form opened before cannot write an older level back; radio control then takes only a change of its own configuration as another connection.
5. **Who refuses a level set by hand while the radio reports its ALC, or during a Set level run?** Today transmit refuses (`alc_available`, `busy`). Recommendation: the Settings page offers the field only while the ALC is unavailable, as it does today, and transmit ignores a level of the configuration while a run goes.
6. **Do Auto Seq and Call 1st leave the QSO pane?** WSJT-X has both on the main window. `settings.csv` sorts them under Operating. Recommendation: they stay on the QSO pane as controls and are saved by the same one way; the group Operating holds the watchdog limits, the special activity and the offsets.
7. **Rows of `settings.csv` marked as proposals:** Monitor off at startup under Station; the Most Wanted list under Strategies and contests or Files; the country file under Files. Recommendation: as the column says, the Most Wanted list under Strategies and contests.
8. **What `settings.csv` does not hold:** the station's continent (`StrategyConfiguration::continent`, found by ranking's report), the clock view, the MCP section and "Update logbook from ADIF" of today's page. Recommendation: the continent is a value of `ProfileConfig` under Station; the clock view under Advanced; the logbook update under Files.
9. **One issue or two?** The stores (server) and the page with the frontend config (client) can land apart. Recommendation: two issues that name each other, the stores first; this body then keeps promises 1 to 5 and cases 1 to 7 and 10.

**Sequence**
- After the tree `docs/sysmlV2` is on main (as #225 and #226 wait).
- After the model of qso, of the station service's startup function and of `frontend/Settings` is written, or with those rows cut into a later issue.
- #209 defines `rf-power.json` in place of `power_limit_pct`: whichever lands second puts the value into the station config, not into a file. #129, #210, #213 hold stored values on the radio and read them from the configuration.
- #195: the broker address is a value of `SpotsConfig`.
- #226 removes the Access & grants section and `authorization.json`; #111, #120, #121 change commands of the contact, whose three set actions this issue removes.

**Acceptance** (product CR only; checked live after the deploy; each item names what is observed and how; at least one observes the value)
- [ ] 1. On the live station the Tx watchdog is set to 4 calls and 120 s in Settings, the station is restarted, and Settings shows 4 and 120 (today: 6 and 90).
- [ ] 2. The profile's folder of the live station holds `profile.json`, the one hidden store, the definition and data files, and none of `tx-level.json`, `receive-diagnostics.json`, `pskr.json`, `udp.json`, `qso-settings.json`, `receive-startup.json`, `radio-keying-confirmed.json`, `radio-settings-undo.json`, `audio-endpoint-names.json` (a directory listing).
- [ ] 3. After the update the live station shows the Tx level, the UDP targets, the PSK Reporter switches, Auto Seq and Call 1st as they were before it (read before and after in Settings).
- [ ] 4. The Settings page shows the groups Station, Radio, Operating, Strategies and contests, Files, Destinations, Display and Advanced, and Advanced > Diagnostics shows "Save FT8 decode windows", the recording import and, not editable, the address, origin and connection type (looked at in the browser).
- [ ] 5. A theme and a waterfall speed set in one browser are there after a reload and are not taken over by a second browser on the same station.

**Decisions:** operator, 2026-11-15, recorded in `docs/sysmlV2/START-HERE.md` ("The settings are being sorted with the operator") and `docs/sysmlV2/_work/settings.csv`; no decision comment on GitHub yet.

**Approval**
The operator decided the sorting on 2026-11-15 and asked for this issue. The go for the build waits for the open questions.

**Blast:** high, because the change moves the stored settings of every station in use into another file at the update, changes the operator's Settings page and removes save routes the page and MCP use.

<details><summary>Technical details</summary>

- Not verified for this draft: the bodies of the tests named in the reading list were not read; the routes were read from `main.rs` by name only; which routes MCP calls beyond `/profile` and `/strategy`; whether the special activity and the offsets are kept anywhere.
- The class is a product CR: the model impact has "add" and "change" rows.

</details>
