# Ledger of identities

Source: docs/sysml on master bbab58190. One row per FR, clause and test case. "Arrived" is filled when the identity stands in docs/sysmlV2 in a part that is rebuilt and checked. A file taken over from the old model is a starting point, not an arrival.

| Identity | Kind | Old file | Target file | Arrived |
|---|---|---|---|---|
| FR-001 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-002 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-003 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-004 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-005 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-006 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-007 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-008 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-009 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-010 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-011 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-012 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-013 | requirement | Requirements.sysml | retired: taken from the feature list of WSJT-X; no clause, code or test | - |
| FR-014 | requirement | Requirements.sysml | retired: taken from the feature list of WSJT-X; no clause, code or test | - |
| FR-015 | requirement | Requirements.sysml | retired: taken from the feature list of WSJT-X; no clause, code or test | - |
| FR-016 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-017 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-018 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-019 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-020 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-021 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-022 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-023 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-024 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-025 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-026 | requirement | Requirements.sysml | Requirements.sysml | yes |
| FR-027 | requirement | new: the reception reports, split from FR-012 (operator 2026-11-15); no clause, code or test yet | Requirements.sysml | yes |
| CL-044-07 | requirement | backend/audio/Endpoints.sysml | backend/audio/Endpoints.sysml | yes |
| TC-044-006 | verification | backend/audio/Endpoints.sysml | backend/audio/Endpoints.sysml | yes |
| CL-008-08 | requirement | new: the sound device half of CL-008-03 and CL-008-05 | backend/audio/AudioDevice.sysml | yes |
| CL-007-11 | requirement | new: the capture clock, from CL-007-05 and CL-043-03 | backend/audio/Capture.sysml | yes |
| TC-007-011 | verification | new: the capture steps of TC-004-004 and TC-092-003 | backend/audio/Capture.sysml | yes |
| CL-009-06 | requirement | new: the playback half of CL-009-03 | backend/audio/Playback.sysml | yes |
| CL-009-07 | requirement | new: the tone of a split operation (WSJT-X comparison, operator 2026-11-17) | backend/transmit/TransmitState.sysml | yes |
| TC-008-004 | verification | new: the playback steps of TC-008-003 | backend/audio/Playback.sysml | yes |
| CL-043-02 | requirement | backend/clock/StationClock.sysml | backend/clock/StationClock.sysml | yes |
| TC-043-001 | verification | backend/clock/StationClock.sysml | backend/clock/StationClock.sysml | yes |
| TC-092-001 | verification | backend/clock/StationClock.sysml | backend/clock/StationClock.sysml | yes |
| CL-013-01 | requirement | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| CL-013-02 | requirement | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| CL-013-03 | requirement | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| CL-013-04 | requirement | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| CL-013-05 | requirement | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| CL-013-06 | requirement | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| CL-013-07 | requirement | new: the tuning of the slice, from NativeFlexWireSubset (no number in the old model) | backend/flexAdapter/FlexSession.sysml | yes |
| TC-023-001 | verification | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| TC-023-002 | verification | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| TC-023-003 | verification | backend/flexAdapter/FlexSession.sysml | backend/flexAdapter/FlexSession.sysml | yes |
| TC-023-004 | verification | backend/flexAdapter/FlexSession.sysml | not carried: planned, live on a FlexRadio, no test exists | - |
| TC-023-005 | verification | backend/flexAdapter/FlexSession.sysml | not carried: planned, live on a FlexRadio, no test exists | - |
| TC-023-006 | verification | backend/flexAdapter/FlexSession.sysml | not carried: planned, a transmission on a FlexRadio, no test exists | - |
| CL-010-04 | requirement | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| CL-010-18 | requirement | new: the update from another program's file, the export and the history, from CL-010-04 | backend/log/Logbook.sysml | yes |
| CL-010-19 | requirement | new: Log QSO gives the newest record again to the logging programs (operator 2026-11-16; from CL-010-04) | backend/log/Logbook.sysml | yes |
| CL-010-20 | requirement | new: ALL.TXT, every decode and sent message (WSJT-X comparison, operator 2026-11-17) | backend/log/Logbook.sysml | yes |
| CL-010-21 | requirement | new: the Cabrillo export of a contest's period (WSJT-X comparison, operator 2026-11-17) | backend/log/Logbook.sysml | yes |
| CL-011-03 | requirement | backend/log/Logbook.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-085-01 | requirement | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| CL-110-01 | requirement | backend/log/Logbook.sysml | retired: qso's settings are in the station config, no qso-settings.json (handover row 192); work for the code | - |
| TC-007-008 | verification | backend/log/Logbook.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-011-001 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-011-002 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-001 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-002 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-003 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-005 | verification | backend/log/Logbook.sysml | frontend/QsoPane.sysml | yes |
| TC-085-006 | verification | backend/log/Logbook.sysml | not carried: planned, no test exists | - |
| TC-110-001 | verification | backend/log/Logbook.sysml | retired: qso's settings are in the station config, no qso-settings.json (handover row 192); work for the code | - |
| TC-110-002 | verification | backend/log/Logbook.sysml | retired: qso's settings are in the station config, no qso-settings.json (handover row 192); work for the code | - |
| TC-110-003 | verification | backend/log/Logbook.sysml | retired: qso's settings are in the station config, no qso-settings.json (handover row 192); work for the code | - |
| TC-110-004 | verification | backend/log/Logbook.sysml | retired: qso's settings are in the station config, no qso-settings.json (handover row 192); work for the code | - |
| TC-110-005 | verification | backend/log/Logbook.sysml | frontend/Settings.sysml | yes |
| TC-110-006 | verification | backend/log/Logbook.sysml | not carried: planned, no test exists | - |
| CL-012-01 | requirement | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml | yes |
| CL-012-02 | requirement | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml (the tools by WstxMcp::ToolRule) | yes |
| CL-012-03 | requirement | backend/mcp/McpEndpoint.sysml | retired: MCP's token, principal and audit go (operator 2026-11-17, #226 question 1; MCP and the UI behave the same); the Origin rule stands in WstxMcp::McpEndpoint | - |
| CL-012-04 | requirement | backend/mcp/McpEndpoint.sysml | retired: the MCP policy run goes (#122); Auto is auto's | - |
| TC-020-001 | verification | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml | yes |
| TC-020-002 | verification | backend/mcp/McpEndpoint.sysml | not carried: its test asserts the token refusals, which go; a test of the endpoint's checks without them is work for the code | - |
| TC-020-003 | verification | backend/mcp/McpEndpoint.sysml | retired: the MCP policy run goes (#122) | - |
| TC-020-004 | verification | backend/mcp/McpEndpoint.sysml | retired: MCP's token goes (operator 2026-11-17) | - |
| CL-007-03 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-007-04 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-007-06 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-007-07 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-007-08 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-007-10 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-057-02 | requirement | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| TC-004-001 | verification | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| TC-004-002 | verification | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| TC-004-003 | verification | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| TC-057-002 | verification | backend/modes/Decode.sysml | backend/modes/Decode.sysml | yes |
| CL-009-01 | requirement | backend/modes/MessageEncode.sysml | backend/modes/MessageEncode.sysml | yes |
| CL-011-01 | requirement | backend/modes/MessageEncode.sysml | backend/modes/MessageEncode.sysml | yes |
| TC-005-001 | verification | backend/modes/MessageEncode.sysml | backend/modes/MessageEncode.sysml | yes |
| TC-005-002 | verification | backend/modes/MessageEncode.sysml | backend/modes/MessageEncode.sysml | yes |
| TC-006-002 | verification | backend/modes/MessageEncode.sysml | backend/transmit/Schedule.sysml | yes |
| CL-007-09 | requirement | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| CL-024-01 | requirement | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| TC-004-005 | verification | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| TC-024-001 | verification | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| TC-024-002 | verification | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| TC-024-003 | verification | backend/modes/MessagePayload.sysml | backend/operating/qso/MessageChoice.sysml | yes |
| TC-024-004 | verification | backend/modes/MessagePayload.sysml | frontend/BandActivityPane.sysml | yes |
| TC-024-010 | verification | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| CL-010-03 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-010-10 | requirement | backend/operating/qso/QsoData.sysml | retired: its repetition half into CL-039-06; the Tune limit is transmit's (TransmitConfig::tuneSeconds) | - |
| CL-010-11 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| CL-010-13 | requirement | backend/operating/qso/QsoData.sysml | backend/log/Logbook.sysml | yes |
| CL-010-14 | requirement | backend/operating/qso/QsoData.sysml | frontend/OperatingScreen.sysml | yes |
| CL-010-17 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-011-02 | requirement | backend/operating/qso/QsoData.sysml | backend/supervisor/OperatingSelection.sysml | yes |
| CL-011-04 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-039-01 | requirement | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-039-05 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/auto/TargetChoice.sysml | yes |
| CL-039-07 | requirement | backend/operating/qso/QsoData.sysml | retired: the outstanding slices are not offered; no promise, no code, no test | - |
| CL-039-08 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| CL-039-09 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| CL-039-11 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| CL-039-20 | requirement | backend/operating/qso/QsoData.sysml | backend/spots/HearingFeed.sysml | yes |
| CL-039-26 | requirement | new: the switches and the status of CL-039-20 | backend/spots/HearingFeed.sysml | yes |
| CL-039-27 | requirement | new: the session with the broker of CL-039-20 | interfaces/external/PskReporter.sysml | yes |
| CL-039-28 | requirement | new: the reception reports to PSK Reporter, for FR-027 (operator 2026-11-16); status target, no code or test yet | backend/spots/SpotsReporting.sysml | yes |
| CL-039-29 | requirement | new: the rule "too close to the partner's Tx" (qso decisions 1, 2, 6, 8, 9) | backend/operating/qso/HoldTx.sysml | yes |
| CL-039-21 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-039-22 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| CL-039-23 | requirement | backend/operating/qso/QsoData.sysml | retired: into CL-097-04 (leaving and the retry pause) and CL-119-04 (nothing else ends the contact); the caller exception goes (issue 119) | - |
| CL-039-24 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-039-25 | requirement | backend/operating/qso/QsoData.sysml | frontend/Settings.sysml | yes |
| CL-042-03 | requirement | backend/operating/qso/QsoData.sysml | retired: pounce removed (issue 123) | - |
| CL-042-05 | requirement | backend/operating/qso/QsoData.sysml | retired: merged into CL-097-12 (WstxSettings::StrategyEditor) | - |
| CL-042-06 | requirement | backend/operating/qso/QsoData.sysml | frontend/BandActivityPane.sysml | yes |
| CL-042-07 | requirement | backend/operating/qso/QsoData.sysml | frontend/Settings.sysml | yes |
| CL-042-08 | requirement | new: the ring of a station calling (WSJT-X comparison, operator 2026-11-17) | frontend/Settings.sysml | yes |
| CL-050-04 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-050-06 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-055-01 | requirement | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| CL-055-02 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-055-03 | requirement | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| CL-063-01 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| CL-063-03 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| CL-063-05 | requirement | backend/operating/qso/QsoData.sysml | retired: into CL-039-05; a contest is a strategy of class contest that Auto applies as any (issue 119) | - |
| CL-063-06 | requirement | backend/operating/qso/QsoData.sysml | retired: into CL-119-05 (what switches Auto off) | - |
| CL-063-07 | requirement | backend/operating/qso/QsoData.sysml | retired: into CL-039-24 (the activity's own CQ word) | - |
| CL-063-08 | requirement | backend/operating/qso/QsoData.sysml | frontend/BandActivityPane.sysml | yes |
| CL-065-01 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| CL-081-01 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| CL-097-01 | requirement | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-097-04 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/auto/Leave.sysml | yes |
| CL-097-05 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/auto/TxSlot.sysml | yes |
| CL-097-06 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-097-07 | requirement | backend/operating/qso/QsoData.sysml | retired, its four pieces elsewhere: the form of a contest strategy in WstxStrategies::StrategyForm (CL-097-01, TC-097-001 (e)); the contest built-ins in BuiltinStrategies (CL-039-11, TC-097-003 (a)); the selection without an operation choice in SelectionRule and ConfigurationKeys (CL-063-03, TC-063-007 (b), (d)), the prompt the frontend's; the contest's ranking rules in ranking's CL-063-04 (operator 2026-11-16, operating line 6) | - |
| CL-097-08 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/auto/CqWhenIdle.sysml | yes |
| CL-097-09 | requirement | backend/operating/qso/QsoData.sysml | retired: the warning into CL-039-24; the mark handed over to the frontend | - |
| CL-097-10 | requirement | new: operating gives ranking, Auto and the contact each its share of the active strategy (operator 2026-11-15, the part operating; from CL-097-01) | backend/operating/StrategySelection.sysml | yes |
| CL-124-02 | requirement | new: a wanted station ranks first (issue 124, operator 2026-11-16: Q1 as WSJT-X, the list managed by settings) | backend/operating/ranking/WantedList.sysml | yes |
| CL-124-03 | requirement | new: an exact wanted entry leaves the list once worked; a pattern stays (issue 124 Q2 (a), operator 2026-11-16) | backend/operating/ranking/WantedList.sysml | yes |
| CL-119-04 | requirement | new: Auto's contact ends only by its completion, a leaving, a stop, Halt QSO or a change (issue 119) | backend/operating/auto/Leave.sysml | yes |
| CL-119-05 | requirement | new: what switches Auto off, and nothing else (issue 119, operator 2026-11-16 decisions 2 to 4) | backend/operating/auto/AutoMode.sysml | yes |
| CL-119-06 | requirement | new: Halt QSO leaves Auto on and skips the dropped station once (issue 119) | backend/operating/auto/TargetChoice.sysml | yes |
| CL-119-08 | requirement | new: a start of Auto that cannot go out (issue 119) | backend/operating/auto/TargetChoice.sysml | yes |
| CL-097-11 | requirement | new: the CQ pause after a CQ nobody answered (operator 2026-11-16, decision 2) | backend/operating/auto/CqWhenIdle.sysml | yes |
| CL-111-07 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-008-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-010-008 | verification | backend/operating/qso/QsoData.sysml | frontend/SignalArea.sysml | yes |
| TC-010-009 | verification | backend/operating/qso/QsoData.sysml | frontend/OperatingScreen.sysml | yes |
| TC-010-010 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-011-003 | verification | backend/operating/qso/QsoData.sysml | backend/log/Logbook.sysml | yes |
| TC-039-001 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-039-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-039-003 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-039-004 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/TargetChoice.sysml | yes |
| TC-039-006 | verification | backend/operating/qso/QsoData.sysml | frontend/BandActivityPane.sysml | yes |
| TC-039-007 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, live, no test exists | - |
| TC-039-008 | verification | backend/operating/qso/QsoData.sysml | retired: with CL-039-07 | - |
| TC-039-009 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-039-010 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-039-020 | verification | backend/operating/qso/QsoData.sysml | backend/spots/HearingFeed.sysml | yes |
| TC-039-052 | verification | new: the session steps of TC-039-020 | interfaces/external/PskReporter.sysml | yes |
| TC-039-021 | verification | backend/operating/qso/QsoData.sysml | frontend/Settings.sysml | yes |
| TC-039-022 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/TxSlot.sysml | yes |
| TC-039-030 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-039-032 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-039-033 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-039-042 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-039-043 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/Leave.sysml | yes |
| TC-039-044 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/Leave.sysml | yes |
| TC-039-045 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/CqWhenIdle.sysml | yes |
| TC-039-047 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, live, no test exists | - |
| TC-039-048 | verification | backend/operating/qso/QsoData.sysml | backend/spots/HearingFeed.sysml | yes |
| TC-039-049 | verification | backend/operating/qso/QsoData.sysml | retired: Hold Tx has no effect while Auto is on (issue 119, CL-119-02); its slot conditions stand in TC-039-010 | - |
| TC-039-050 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-039-051 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, no test | - |
| TC-042-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-042-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/IgnoreLists.sysml | yes |
| TC-042-003 | verification | backend/operating/qso/QsoData.sysml | not carried: its test asserts the two Settings ignore lists; the one list is CL-042-06's | - |
| TC-042-004 | verification | backend/operating/qso/QsoData.sysml | retired: pounce removed (issue 123) | - |
| TC-042-005 | verification | backend/operating/qso/QsoData.sysml | retired: pounce removed (issue 123) | - |
| TC-042-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/Alert.sysml | yes |
| TC-042-007 | verification | backend/operating/qso/QsoData.sysml | frontend/Settings.sysml | yes |
| TC-050-004 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-050-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-055-001 | verification | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| TC-055-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-055-003 | verification | backend/operating/qso/QsoData.sysml | not carried: its test uploads a file; the settings function downloads the file instead (operator 2026-11-16); work for the code | - |
| TC-055-004 | verification | backend/operating/qso/QsoData.sysml | frontend/BandActivityPane.sysml | yes |
| TC-055-005 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, live, no test exists | - |
| TC-063-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-003 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-004 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| TC-063-005 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| TC-063-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| TC-063-007 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-008 | verification | backend/operating/qso/QsoData.sysml | frontend/BandActivityPane.sysml | yes |
| TC-063-009 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/TargetChoice.sysml | yes |
| TC-063-010 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/CqWhenIdle.sysml | yes |
| TC-063-011 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-063-012 | verification | backend/operating/qso/QsoData.sysml | not carried: its test asserts the MCP run's automation view, which goes (#122) | - |
| TC-065-001 | verification | backend/operating/qso/QsoData.sysml | retired: replaced by TC-082-001 (the test says so) | - |
| TC-065-002 | verification | backend/operating/qso/QsoData.sysml | retired: replaced by TC-082-003 (the test says so) | - |
| TC-065-004 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, no test | - |
| TC-066-001 | verification | backend/operating/qso/QsoData.sysml | not carried: as TC-082-002 | - |
| TC-066-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-066-003 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, live, no test exists | - |
| TC-081-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-081-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-081-003 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-081-004 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-081-005 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/AutoMode.sysml | yes |
| TC-081-006 | verification | backend/operating/qso/QsoData.sysml | frontend/QsoPane.sysml | yes |
| TC-081-007 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, no test | - |
| TC-082-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-082-002 | verification | backend/operating/qso/QsoData.sysml | not carried: its tests assert the free offsets from 300 Hz, which qso decision 4b removes (qso report); work for the code | - |
| TC-082-003 | verification | backend/operating/qso/QsoData.sysml | backend/web/Listener.sysml (openSlots as a view and events; CL-003-08) | yes |
| TC-082-005 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, no test | - |
| TC-082-006 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, no test | - |
| TC-089-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-089-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/HoldTx.sysml | yes |
| TC-089-003 | verification | backend/operating/qso/QsoData.sysml | not carried: as TC-082-002 | - |
| TC-089-004 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/CqWhenIdle.sysml | yes |
| TC-089-005 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, no test | - |
| TC-097-001 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-097-002 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-097-003 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-097-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-097-009 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/Leave.sysml | yes |
| TC-097-010 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/TxSlot.sysml | yes |
| TC-097-011 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-097-012 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-097-013 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/Leave.sysml | yes |
| TC-097-014 | verification | backend/operating/qso/QsoData.sysml | not carried: its test asserts the whole-configuration save of the editor, which goes | - |
| TC-097-015 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/CqWhenIdle.sysml | yes |
| TC-097-016 | verification | backend/operating/qso/QsoData.sysml | not carried: planned, live, no test exists | - |
| TC-097-017 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-097-018 | verification | backend/operating/qso/QsoData.sysml | backend/operating/auto/CqWhenIdle.sysml | yes |
| TC-097-019 | verification | backend/operating/qso/QsoData.sysml | not carried: its test reads the wording of the old model; work for the code | - |
| TC-111-011 | verification | backend/operating/qso/QsoData.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-125-002 | verification | backend/operating/qso/QsoData.sysml | not carried: its test asserts the Settings ignore lists; the one list is CL-042-06's | - |
| CL-111-02 | requirement | backend/operating/qso/QsoTransmit.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-111-05 | requirement | backend/operating/qso/QsoTransmit.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-111-08 | requirement | backend/operating/qso/QsoTransmit.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-111-003 | verification | backend/operating/qso/QsoTransmit.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-111-004 | verification | backend/operating/qso/QsoTransmit.sysml | not carried: planned, no test exists | - |
| TC-111-006 | verification | backend/operating/qso/QsoTransmit.sysml | not carried: their tests reach completed through Log QSO; work for the code | - |
| TC-111-008 | verification | backend/operating/qso/QsoTransmit.sysml | not carried: planned, no test exists | - |
| TC-111-012 | verification | backend/operating/qso/QsoTransmit.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-010-15 | requirement | backend/operating/qso/QsoWire.sysml | retired: merged into CL-003-08; the contact's wire is the wire derived from the boundary (operator 2026-11-17, WstxStationLink::WireRule) | - |
| TC-007-005 | verification | backend/operating/qso/QsoWire.sysml | backend/web/Listener.sysml (the views as events; CL-003-08) | yes |
| CL-024-02 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| CL-024-03 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| CL-024-04 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| CL-085-03 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| CL-085-04 | requirement | new: the confirmation of logging by hand (WSJT-X comparison, operator 2026-11-17) | backend/operating/qso/StandardQso.sysml | yes |
| CL-099-01 | requirement | backend/operating/qso/SpecialActivities.sysml | retired: into CL-009-01 (WstxMessageEncode::PackMessage) | - |
| CL-099-02 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| CL-111-10 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-024-005 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-024-006 | verification | backend/operating/qso/SpecialActivities.sysml | frontend/QsoPane.sysml | yes |
| TC-024-007 | verification | backend/operating/qso/SpecialActivities.sysml | retired: into TC-005-001 and TC-005-002 of modes, whose bound test files hold its tests (CL-009-01) | - |
| TC-024-008 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-024-009 | verification | backend/operating/qso/SpecialActivities.sysml | frontend/QsoPane.sysml | yes |
| TC-024-011 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-024-012 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-024-013 | verification | backend/operating/qso/SpecialActivities.sysml | frontend/QsoPane.sysml | yes |
| TC-024-014 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-085-004 | verification | backend/operating/qso/SpecialActivities.sysml | not carried: its test reaches the serial through Log QSO, which hands nothing over (log, 2026-11-16); work for the code | - |
| TC-099-001 | verification | backend/operating/qso/SpecialActivities.sysml | retired: into TC-005-001 and TC-005-002 of modes, whose bound test files hold its tests (CL-009-01) | - |
| TC-099-002 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| TC-099-003 | verification | backend/operating/qso/SpecialActivities.sysml | frontend/QsoPane.sysml | yes |
| TC-099-004 | verification | backend/operating/qso/SpecialActivities.sysml | not carried: planned, live, no test exists | - |
| TC-111-016 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml | yes |
| CL-010-01 | requirement | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-010-02 | requirement | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-010-12 | requirement | backend/operating/qso/StandardQso.sysml | backend/operating/qso/MessageChoice.sysml | yes |
| TC-007-001 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml | yes |
| TC-007-003 | verification | backend/operating/qso/StandardQso.sysml | frontend/QsoPane.sysml | yes |
| TC-007-004 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-007-007 | verification | backend/operating/qso/StandardQso.sysml | not carried: planned, live, no test exists | - |
| TC-007-010 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-042-04 | requirement | backend/operating/ranking/Alert.sysml | backend/operating/ranking/Alert.sysml | yes |
| CL-063-02 | requirement | backend/operating/ranking/ContestRanking.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| CL-063-04 | requirement | backend/operating/ranking/ContestRanking.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| CL-063-09 | requirement | new: the count and the tally of a contest period, from CL-063-03 and ContestLog | backend/operating/ranking/ContestRanking.sysml | yes |
| CL-042-02 | requirement | backend/operating/ranking/IgnoreLists.sysml | backend/operating/ranking/IgnoreLists.sysml | yes |
| TC-125-001 | verification | backend/operating/ranking/IgnoreLists.sysml | backend/operating/ranking/IgnoreLists.sysml | yes |
| CL-039-10 | requirement | backend/operating/ranking/MostWanted.sysml | backend/operating/ranking/MostWanted.sysml | yes |
| TC-039-031 | verification | backend/operating/ranking/MostWanted.sysml | backend/operating/ranking/MostWanted.sysml | yes |
| CL-039-02 | requirement | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-039-03 | requirement | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-042-01 | requirement | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-097-02 | requirement | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-097-03 | requirement | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-039-040 | verification | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-097-004 | verification | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-097-005 | verification | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-097-007 | verification | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-097-008 | verification | backend/operating/ranking/ValueOrder.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-005-01 | requirement | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-005-02 | requirement | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-005-04 | requirement | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-005-05 | requirement | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-005-06 | requirement | new: the hidden store of the station (the records of the parts kept across sessions; operator 2026-11-15, the three stores) | backend/profile/ProfileDocument.sysml | yes |
| CL-005-07 | requirement | new: the shack's folder and settings, shared by the shack's stations (operator 2026-11-16; from CL-005-02) | backend/profile/ProfileDocument.sysml | yes |
| CL-008-01 | requirement | backend/profile/Profile.sysml | retired: the same promise as CL-005-05 (the audio devices and the radio control stored each by itself, claiming no device); its control half is radio control's ControlSelection | - |
| CL-044-05 | requirement | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-002-001 | verification | backend/profile/Profile.sysml | backend/audio/Capture.sysml | yes |
| TC-009-001 | verification | backend/profile/Profile.sysml | backend/radioControl/CatControl.sysml | yes |
| TC-022-001 | verification | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-022-002 | verification | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-022-003 | verification | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-022-011 | verification | new: the shack's settings (operator 2026-11-16; callsign and locator conditions from TC-022-001) | backend/profile/ProfileDocument.sysml | yes |
| TC-022-005 | verification | backend/profile/Profile.sysml | not carried: its fixture is the grants of the authorization (#226) | - |
| CL-006-01 | requirement | backend/profile/Recordings.sysml | backend/profile/Recordings.sysml | yes |
| TC-018-001 | verification | backend/profile/Recordings.sysml | backend/profile/Recordings.sysml | yes |
| TC-018-002 | verification | backend/profile/Recordings.sysml | backend/profile/Recordings.sysml | yes |
| CL-006-05 | requirement | new: the import half of CL-006-02 (a recording takes the place of the stored one only by a whole and valid import) | backend/profile/Recordings.sysml | yes |
| CL-006-06 | requirement | new: the import half of CL-006-04 (one import at a time, every refusal with its reason) | backend/profile/Recordings.sysml | yes |
| CL-013-08 | requirement | new: the profile's half of CL-013-03 (the stored native intent) | backend/profile/ProfileDocument.sysml | yes |
| TC-023-007 | verification | new: the two tests of profile_tests.rs that were tagged TC-023-002 | backend/profile/ProfileDocument.sysml | yes |
| CL-008-04 | requirement | backend/radioControl/CatControl.sysml | backend/radioControl/CatControl.sysml | yes |
| CL-008-05 | requirement | backend/radioControl/CatControl.sysml | backend/radioControl/RadioFacts.sysml | yes |
| CL-008-06 | requirement | backend/radioControl/CatControl.sysml | backend/radioControl/CatControl.sysml | yes |
| CL-022-03 | requirement | backend/radioControl/CatControl.sysml | backend/radioControl/CatLifecycle.sysml | yes |
| CL-044-11 | requirement | backend/radioControl/CatControl.sysml | backend/radioControl/RadioSetup.sysml | yes |
| TC-009-003 | verification | backend/radioControl/CatControl.sysml | backend/radioControl/CatControl.sysml | yes |
| TC-022-009 | verification | backend/radioControl/CatControl.sysml | backend/radioControl/CatLifecycle.sysml | yes |
| TC-044-010 | verification | backend/radioControl/CatControl.sysml | frontend/Settings.sysml | yes |
| CL-022-04 | requirement | backend/radioControl/CatLifecycle.sysml | backend/radioControl/CatLifecycle.sysml | yes |
| CL-044-01 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-02 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-03 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-04 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-09 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/CatControl.sysml | yes |
| CL-044-10 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-15 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-001-01 | requirement | new: the settings check (use case SettingsCheck, operator 2026-11-17) | backend/supervisor/SettingsCheck.sysml | yes |
| CL-001-02 | requirement | new: the settings check on the screen (use case SettingsCheck, operator 2026-11-17) | frontend/Settings.sysml | yes |
| CL-044-18 | requirement | new: the output power set on the radio (operator 2026-11-17, option A) | backend/radioControl/RadioSetup.sysml | yes |
| TC-044-001 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| TC-044-002 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| TC-044-003 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| TC-044-004 | verification | backend/radioControl/RadioSetup.sysml | not carried: planned, live on the station's radio, no test exists | - |
| TC-044-008 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/CatControl.sysml | yes |
| TC-044-009 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| TC-044-011 | verification | backend/radioControl/RadioSetup.sysml | not carried: planned, live on the station's radio, no test exists | - |
| TC-044-012 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/CatControl.sysml | yes |
| TC-044-020 | verification | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| TC-044-021 | verification | backend/radioControl/RadioSetup.sysml | not carried: planned, live on the station's radio, no test exists | - |
| TC-044-022 | verification | backend/radioControl/RadioSetup.sysml | frontend/Settings.sysml | yes |
| CL-007-01 | requirement | backend/receive/LiveReceive.sysml | backend/receive/LiveReceive.sysml | yes |
| CL-007-05 | requirement | backend/receive/LiveReceive.sysml | backend/receive/LiveReceive.sysml | yes |
| CL-008-02 | requirement | backend/receive/LiveReceive.sysml | backend/audio/Capture.sysml | yes |
| TC-002-003 | verification | backend/receive/LiveReceive.sysml | backend/audio/AudioDevice.sysml | yes |
| TC-004-004 | verification | backend/receive/LiveReceive.sysml | backend/receive/LiveReceive.sysml | yes |
| TC-009-002 | verification | backend/receive/LiveReceive.sysml | backend/radioControl/CatControl.sysml | yes |
| CL-008-09 | requirement | new: the keying of the radio, the old action PttControl without a clause | backend/radioControl/CatControl.sysml | yes |
| TC-009-006 | verification | new: the facts of the radio, from the tests of TC-009-003 and TC-009-005 | backend/radioControl/RadioFacts.sysml | yes |
| TC-009-007 | verification | new: keying on a scripted radio, three tests of TC-008-003 and one of TC-044-013 | backend/radioControl/CatControl.sysml | yes |
| CL-006-02 | requirement | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| CL-006-03 | requirement | backend/receive/ReceiveJob.sysml | backend/receive/Spectrum.sysml | yes |
| CL-006-04 | requirement | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| CL-008-03 | requirement | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| CL-052-01 | requirement | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| TC-009-004 | verification | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| TC-010-001 | verification | backend/receive/ReceiveJob.sysml | backend/receive/Spectrum.sysml | yes |
| TC-010-002 | verification | backend/receive/ReceiveJob.sysml | backend/web/Listener.sysml (the rows to the sockets; CL-003-02) | yes |
| TC-010-003 | verification | backend/receive/ReceiveJob.sysml | frontend/SignalArea.sysml | yes |
| TC-010-004 | verification | backend/receive/ReceiveJob.sysml | backend/receive/Spectrum.sysml | yes |
| TC-010-005 | verification | backend/receive/ReceiveJob.sysml | backend/web/Listener.sysml (the detailed rows on the wire; CL-003-02) | yes |
| TC-010-006 | verification | backend/receive/ReceiveJob.sysml | frontend/SignalArea.sysml | yes |
| TC-010-007 | verification | backend/receive/ReceiveJob.sysml | frontend/SignalArea.sysml | yes |
| TC-018-003 | verification | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| TC-052-001 | verification | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| CL-045-01 | requirement | backend/receive/Startup.sysml | backend/supervisor/Startup.sysml | yes |
| CL-045-02 | requirement | backend/receive/Startup.sysml | backend/supervisor/Startup.sysml | yes |
| CL-045-03 | requirement | backend/receive/Startup.sysml | backend/supervisor/Startup.sysml | yes |
| TC-045-001 | verification | backend/receive/Startup.sysml | backend/supervisor/Startup.sysml | yes |
| TC-045-002 | verification | backend/receive/Startup.sysml | not carried: planned, live on the station's radio, no test exists | - |
| CL-008-07 | requirement | backend/supervisor/OperatingSelection.sysml | backend/supervisor/OperatingSelection.sysml | yes |
| CL-044-16 | requirement | backend/supervisor/OperatingSelection.sysml | backend/supervisor/OperatingSelection.sysml | yes |
| CL-008-10 | requirement | new: the cancel of a selection (from CL-008-07) | backend/supervisor/OperatingSelection.sysml | yes |
| CL-008-11 | requirement | new: the station's band (handover rows of transmit, ranking, spots) | backend/supervisor/OperatingSelection.sysml | yes |
| CL-008-12 | requirement | new: the dial taken as the selection (handover row of radio control; from CL-008-07) | backend/supervisor/OperatingSelection.sysml | yes |
| CL-008-13 | requirement | new: the transmit frequency of a split operation (WSJT-X comparison, operator 2026-11-17) | backend/radioControl/CatControl.sysml | yes |
| TC-009-008 | verification | new: the dial taken as the selection, two tests of cat_lifecycle_tests.rs | backend/supervisor/OperatingSelection.sysml | yes |
| TC-011-004 | verification | new: the operating mode, three tests of contact_http_tests.rs (handover row of qso) | backend/supervisor/OperatingSelection.sysml | yes |
| CL-006-07 | requirement | new: the gate of the supervisor (handover rows of receive, profile, operating; from CL-006-04) | backend/supervisor/StationAuthority.sysml | yes |
| TC-006-004 | verification | new: the identity of a command and the halt | backend/supervisor/StationAuthority.sysml | yes |
| CL-119-09 | requirement | new: the refusal auto_on while Auto is on (issue 119, CL-119-06's list; handover row of auto) | backend/supervisor/StationAuthority.sysml | yes |
| CL-044-17 | requirement | new: the SWR barrier (handover row of transmit; from CL-044-14) | backend/supervisor/StationAuthority.sysml | yes |
| CL-005-08 | requirement | new: the contexts and the one way of a setting change (handover rows; from CL-005-02) | backend/supervisor/StationAuthority.sysml | yes |
| CL-005-09 | requirement | new: the start and end of the station process (handover row of the profile; from CL-005-04) | backend/supervisor/Startup.sysml | yes |
| TC-044-023 | verification | backend/supervisor/OperatingSelection.sysml | backend/supervisor/OperatingSelection.sysml | yes |
| CL-009-02 | requirement | backend/transmit/Schedule.sysml | backend/transmit/Schedule.sysml | yes |
| TC-006-001 | verification | backend/transmit/Schedule.sysml | backend/transmit/Schedule.sysml | yes |
| CL-009-03 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-009-04 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-009-05 | requirement | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| CL-039-06 | requirement | backend/transmit/TransmitState.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-043-01 | requirement | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| CL-043-03 | requirement | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| CL-044-13 | requirement | backend/transmit/TransmitState.sysml | retired: merged into CL-003-08; the Tx level is the view txLevel and its event (WstxStationLink::WireRule) | - |
| CL-044-14 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TxLevel.sysml | yes |
| CL-061-04 | requirement | backend/transmit/TransmitState.sysml | backend/receive/LiveReceive.sysml | yes |
| CL-111-01 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-111-03 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-111-06 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-006-003 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-008-002 | verification | backend/transmit/TransmitState.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| TC-008-003 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-008-005 | verification | new: Halt, the failures and the releases of TC-008-003 | backend/transmit/TransmitState.sysml | yes |
| TC-039-005 | verification | backend/transmit/TransmitState.sysml | not carried: its tests assert the operator barrier (issue 122) and transmit's count; work for the code | - |
| TC-043-002 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-043-003 | verification | backend/transmit/TransmitState.sysml | frontend/Settings.sysml | yes |
| TC-043-004 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-044-015 | verification | backend/transmit/TransmitState.sysml | not carried: its test asserts the Set level button, which goes | - |
| TC-044-017 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-018 | verification | backend/transmit/TransmitState.sysml | frontend/LowerPanel.sysml | yes |
| TC-044-019 | verification | backend/transmit/TransmitState.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| TC-061-005 | verification | backend/transmit/TransmitState.sysml | backend/receive/LiveReceive.sysml | yes |
| TC-007-012 | verification | new: the receive half of TC-007-006 and the window tests bound to TC-002-001 | backend/receive/LiveReceive.sysml | yes |
| TC-061-006 | verification | backend/transmit/TransmitState.sysml | frontend/SignalArea.sysml | yes |
| TC-061-007 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-002 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-092-003 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-092-004 | verification | backend/transmit/TransmitState.sysml | not carried: it asserts only negatives, no clock source setting and no POST /clock (the rule on negatives) | - |
| TC-092-005 | verification | backend/transmit/TransmitState.sysml | frontend/LowerPanel.sysml | yes |
| TC-092-006 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-007 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-008 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-009 | verification | backend/transmit/TransmitState.sysml | backend/web/Listener.sysml (the clock's view as events; CL-003-08) | yes |
| TC-111-001 | verification | backend/transmit/TransmitState.sysml | not carried: its tests assert the stop when the partner works another station (qso decision 2); work for the code | - |
| TC-111-002 | verification | backend/transmit/TransmitState.sysml | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-111-007 | verification | backend/transmit/TransmitState.sysml | backend/web/Listener.sysml (the causes as wire names; CL-003-08) | yes |
| TC-111-009 | verification | backend/transmit/TransmitState.sysml | not carried: their tests reach completed through Log QSO; work for the code | - |
| TC-111-010 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-111-013 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-111-017 | verification | new: the contact's answers to the Tune tone, from TC-111-010 (d), (e), (g) (operator 2026-11-15) | not carried: its test asserts the radio grant, the safety revision (issue 226) and the agent barrier (issue 122); work for the code | - |
| TC-111-018 | verification | new: a stop against a start in one step, from TC-111-013 (a), (b) (operator 2026-11-15) | backend/operating/qso/QsoTransmit.sysml | yes |
| TC-111-015 | verification | backend/transmit/TransmitState.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| CL-044-12 | requirement | backend/transmit/TxLevel.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-013 | verification | backend/transmit/TxLevel.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-014 | verification | backend/transmit/TxLevel.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-016 | verification | backend/transmit/TxLevel.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| CL-003-01 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-003-02 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-003-03 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-003-05 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-003-06 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-003-07 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml (TLS and the origin; the token goes, operator 2026-11-17) | yes |
| CL-003-08 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml (the views by GET and as events, WstxStationLink::WireRule) | yes |
| CL-005-03 | requirement | backend/web/StationProtocol.sysml | retired: the sessions and their cookies go (operator 2026-11-17, #226 question 2); that profiles are independent is the profile's (CL-005-04) | - |
| CL-022-02 | requirement | backend/web/StationProtocol.sysml | retired: the radio authorization goes (#226) | - |
| CL-022-05 | requirement | backend/web/StationProtocol.sysml | retired: merged into CL-010-07 (WstxOperatingScreen::HealthRule); the session part goes with the authorization (#226) | - |
| CL-033-01 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-051-01 | requirement | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| TC-009-005 | verification | backend/web/StationProtocol.sysml | backend/supervisor/OperatingSelection.sysml (the selection and the cancel; its other clauses are those of web, radio control and the frontend) | yes |
| TC-021-005 | verification | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| TC-021-006 | verification | backend/web/StationProtocol.sysml | not carried: its test asserts the old status's radio text, which goes; the layout at two widths is TC-007-002's | - |
| TC-021-008 | verification | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| TC-021-009 | verification | backend/web/StationProtocol.sysml | not carried: its test asserts the token login, which goes (operator 2026-11-17); a test of TLS and the origin is work for the code | - |
| TC-022-004 | verification | backend/web/StationProtocol.sysml | retired: the sessions and their cookies go (operator 2026-11-17, #226) | - |
| TC-022-008 | verification | backend/web/StationProtocol.sysml | retired: the authorization's status route goes (#226) | - |
| TC-033-001 | verification | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| TC-051-001 | verification | backend/web/StationProtocol.sysml | backend/web/Listener.sysml (CL-051-01; CL-051-02 is the frontend's) | yes |
| TC-051-003 | verification | backend/web/StationProtocol.sysml | not carried: planned, live, no test | - |
| TC-080-001 | verification | backend/web/StationProtocol.sysml | backend/web/Listener.sysml | yes |
| CL-003-09 | requirement | new: the content coding of the answers (old WstxHttpContentCoding, unnumbered) | backend/web/ContentCoding.sysml | yes |
| CL-006-08 | requirement | new: the display half of CL-006-03 (handover row of receive) | frontend/SignalArea.sysml | yes |
| CL-103-01 | requirement | new: the app window (#103, #118 Q6/Q7, #149; operator 2026-11-17) | frontend/OperatingScreen.sysml | yes |
| CL-017-01 | requirement | new: the help, version, license and notice (FR-017 had no clause) | frontend/OperatingScreen.sysml | yes |
| CL-039-31 | requirement | new: Auto and PSK on the screen (handover rows of auto and spots) | frontend/QsoPane.sysml | yes |
| CL-037-06 | requirement | new: the QSO pane's direct buttons (from CL-037-03) | frontend/QsoPane.sysml | yes |
| CL-097-12 | requirement | new: the strategy editor's screen (handover row of operating) | frontend/Settings.sysml | yes |
| CL-227-01 | requirement | new: the settings drawer of the two levels (#227) | frontend/Settings.sysml | yes |
| CL-003-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-007-02 | requirement | frontend/OperatingScreen.sysml | retired: merged into CL-010-09 (WstxBandActivityPane::RowFields) | - |
| CL-010-05 | requirement | frontend/OperatingScreen.sysml | retired: merged into CL-010-16 (the screen's layout) | - |
| CL-010-06 | requirement | frontend/OperatingScreen.sysml | retired: merged into CL-037-04 (WstxQsoPane::PaneLayout) | - |
| CL-010-07 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-010-08 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-010-09 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-010-16 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-022-01 | requirement | frontend/OperatingScreen.sysml | retired: the radio authorization goes (#226) | - |
| CL-037-01 | requirement | frontend/OperatingScreen.sysml | frontend/LowerPanel.sysml | yes |
| CL-037-02 | requirement | frontend/OperatingScreen.sysml | frontend/LowerPanel.sysml | yes |
| CL-037-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-037-04 | requirement | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| CL-037-05 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-039-04 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-044-06 | requirement | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| CL-044-08 | requirement | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| CL-050-01 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-050-02 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-050-03 | requirement | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| CL-050-05 | requirement | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| CL-050-07 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-050-08 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-051-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-051-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-054-01 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-054-02 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-055-04 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-055-05 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-057-01 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-057-03 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-060-01 | requirement | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| CL-061-01 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-061-02 | requirement | frontend/OperatingScreen.sysml | retired: the commands carry no contact revision, so nothing is retried for one | - |
| CL-061-03 | requirement | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| CL-061-05 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-065-02 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-068-01 | requirement | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| CL-073-01 | requirement | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| CL-074-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-096-01 | requirement | frontend/OperatingScreen.sysml | retired: the full-screen button goes; the screen is an app window (CL-103-01, #103) | - |
| CL-111-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| CL-111-09 | requirement | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| TC-007-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| TC-007-006 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-007-009 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| TC-021-007 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| TC-022-006 | verification | frontend/OperatingScreen.sysml | retired: the radio authorization goes (#226) | - |
| TC-022-010 | verification | frontend/OperatingScreen.sysml | retired: the radio authorization goes (#226) | - |
| TC-037-001 | verification | frontend/OperatingScreen.sysml | frontend/LowerPanel.sysml | yes |
| TC-037-002 | verification | frontend/OperatingScreen.sysml | frontend/LowerPanel.sysml | yes |
| TC-037-003 | verification | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| TC-037-004 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-039-046 | verification | frontend/OperatingScreen.sysml | not carried: its test asserts the whole-configuration save, which goes (one member at a time) | - |
| TC-044-005 | verification | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| TC-044-007 | verification | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| TC-050-001 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-050-002 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-050-003 | verification | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| TC-050-005 | verification | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| TC-050-007 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-050-008 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-051-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| TC-054-001 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-054-002 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-054-003 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-055-006 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-055-007 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-057-001 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-057-003 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-057-004 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-060-001 | verification | frontend/OperatingScreen.sysml | frontend/QsoPane.sysml | yes |
| TC-061-001 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-061-002 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-061-003 | verification | frontend/OperatingScreen.sysml | retired: with CL-061-02 | - |
| TC-061-004 | verification | frontend/OperatingScreen.sysml | frontend/BandActivityPane.sysml | yes |
| TC-061-008 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-061-009 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-065-003 | verification | frontend/OperatingScreen.sysml | not carried: its test asserts the Settings checkbox the marks no longer have; TC-082-004 shows the marks | - |
| TC-068-001 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-068-002 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-073-001 | verification | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| TC-073-002 | verification | frontend/OperatingScreen.sysml | frontend/Settings.sysml | yes |
| TC-073-003 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-074-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| TC-074-002 | verification | frontend/OperatingScreen.sysml | not carried: its test asserts the MCP run's automation line, which goes (#122) | - |
| TC-074-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml | yes |
| TC-074-004 | verification | frontend/OperatingScreen.sysml | not carried: planned, live, no test | - |
| TC-082-004 | verification | frontend/OperatingScreen.sysml | frontend/SignalArea.sysml | yes |
| TC-096-001 | verification | frontend/OperatingScreen.sysml | retired: the full-screen button goes (#103) | - |
| TC-096-002 | verification | frontend/OperatingScreen.sysml | retired: the full-screen button goes (#103) | - |
| TC-111-005 | verification | frontend/OperatingScreen.sysml | not carried: planned, no test | - |
| TC-111-014 | verification | frontend/OperatingScreen.sysml | not carried: planned, no test | - |
| CL-040-01 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-040-02 | requirement | interfaces/external/Udp.sysml | backend/udp/UdpSender.sysml | yes |
| CL-040-03 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-040-04 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-040-06 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-040-07 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-112-01 | requirement | interfaces/external/Udp.sysml | backend/udp/UdpSender.sysml | yes |
| CL-112-02 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-112-03 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-112-04 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-112-05 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-112-06 | requirement | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-012-001 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-012-002 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-012-003 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-012-004 | verification | interfaces/external/Udp.sysml | backend/udp/UdpSender.sysml | yes |
| TC-012-006 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-012-007 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-112-001 | verification | interfaces/external/Udp.sysml | backend/udp/UdpSender.sysml | yes |
| TC-112-002 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-112-003 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-112-004 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-112-005 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| TC-112-006 | verification | interfaces/external/Udp.sysml | interfaces/external/Udp.sysml | yes |
| CL-085-02 | requirement | interfaces/internal/OperatingChain.sysml | backend/operating/qso/StandardQso.sysml | yes |
| CL-109-01 | requirement | new: a completed contact taken up again (issue 109) | backend/operating/qso/StandardQso.sysml | yes |
| CL-024-05 | requirement | new: contacts with a nonstandard or compound call (handover row 37) | backend/operating/qso/MessageChoice.sysml | yes |
| TC-039-053 | verification | new: the activity's own CQ word needs no confirmation | backend/operating/qso/StandardQso.sysml | yes |
| TC-039-054 | verification | new: Auto's contact past the repetition limit | backend/operating/qso/QsoTransmit.sysml | yes |
| CL-039-30 | requirement | new: the fetch and the keeping of the Most Wanted list, cut from CL-039-10 (operator 2026-11-16, settings) | backend/profile/ProfileDocument.sysml | yes |
| TC-039-055 | verification | new: the list and the answer of the service, cut from TC-039-031 | backend/profile/ProfileDocument.sysml | yes |
| CL-055-06 | requirement | new: the download of the country file by the settings function, as WSJT-X (operator 2026-11-16) | backend/profile/ProfileDocument.sysml | yes |
