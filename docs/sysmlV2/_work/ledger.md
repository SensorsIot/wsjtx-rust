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
| CL-011-03 | requirement | backend/log/Logbook.sysml | handed over: qso (the FT4 contact; its log fields stand in LogRecord) |  |
| CL-085-01 | requirement | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| CL-110-01 | requirement | backend/log/Logbook.sysml | handed over: qso (the saved Auto Seq and Call 1st) |  |
| TC-007-008 | verification | backend/log/Logbook.sysml | handed over: qso |  |
| TC-011-001 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-011-002 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-001 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-002 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-003 | verification | backend/log/Logbook.sysml | backend/log/Logbook.sysml | yes |
| TC-085-005 | verification | backend/log/Logbook.sysml | handed over: frontend (its condition on the latest log attempt is TC-085-001 (a)) |  |
| TC-085-006 | verification | backend/log/Logbook.sysml | not carried: planned, no test exists | - |
| TC-110-001 | verification | backend/log/Logbook.sysml | handed over: qso |  |
| TC-110-002 | verification | backend/log/Logbook.sysml | handed over: qso |  |
| TC-110-003 | verification | backend/log/Logbook.sysml | handed over: qso |  |
| TC-110-004 | verification | backend/log/Logbook.sysml | handed over: qso |  |
| TC-110-005 | verification | backend/log/Logbook.sysml | handed over: frontend |  |
| TC-110-006 | verification | backend/log/Logbook.sysml | not carried: planned, no test exists | - |
| CL-012-01 | requirement | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| CL-012-02 | requirement | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| CL-012-03 | requirement | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| CL-012-04 | requirement | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| TC-020-001 | verification | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| TC-020-002 | verification | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| TC-020-003 | verification | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
| TC-020-004 | verification | backend/mcp/McpEndpoint.sysml | backend/mcp/McpEndpoint.sysml  (same name; rebuilt) |  |
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
| TC-024-003 | verification | backend/modes/MessagePayload.sysml | handed over: qso |  |
| TC-024-004 | verification | backend/modes/MessagePayload.sysml | handed over: frontend |  |
| TC-024-010 | verification | backend/modes/MessagePayload.sysml | backend/modes/MessagePayload.sysml | yes |
| CL-010-03 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-010-10 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-010-11 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-010-13 | requirement | backend/operating/qso/QsoData.sysml | backend/log/Logbook.sysml | yes |
| CL-010-14 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-010-17 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-011-02 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-011-04 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-01 | requirement | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-039-05 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-07 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-08 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-09 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-11 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| CL-039-20 | requirement | backend/operating/qso/QsoData.sysml | backend/spots/HearingFeed.sysml | yes |
| CL-039-26 | requirement | new: the switches and the status of CL-039-20 | backend/spots/HearingFeed.sysml | yes |
| CL-039-27 | requirement | new: the session with the broker of CL-039-20 | interfaces/external/PskReporter.sysml | yes |
| CL-039-28 | requirement | new: the reception reports to PSK Reporter, for FR-027 (operator 2026-11-16); status target, no code or test yet | backend/spots/SpotsReporting.sysml | yes |
| CL-039-21 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-22 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-23 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-24 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-039-25 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-042-03 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-042-05 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-042-06 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-042-07 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-050-04 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-050-06 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-055-01 | requirement | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| CL-055-02 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| CL-055-03 | requirement | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| CL-063-01 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| CL-063-03 | requirement | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| CL-063-05 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-063-06 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-063-07 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-063-08 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-065-01 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-081-01 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-097-01 | requirement | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| CL-097-04 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-097-05 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-097-06 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-097-07 | requirement | backend/operating/qso/QsoData.sysml | retired, its four pieces elsewhere: the form of a contest strategy in WstxStrategies::StrategyForm (CL-097-01, TC-097-001 (e)); the contest built-ins in BuiltinStrategies (CL-039-11, TC-097-003 (a)); the selection without an operation choice in SelectionRule and ConfigurationKeys (CL-063-03, TC-063-007 (b), (d)), the prompt the frontend's; the contest's ranking rules in ranking's CL-063-04 (operator 2026-11-16, operating line 6) | - |
| CL-097-08 | requirement | backend/operating/qso/QsoData.sysml | handed over: auto (when CQ is called after the CQ wait; the value, 1 to 20 and held in every strategy, stands in WstxStrategies::AutoKeys::cqWaitPeriods and is shown by TC-097-001 (b), (d) and TC-097-002 (g)) |  |
| CL-097-09 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-097-10 | requirement | new: operating gives ranking, Auto and the contact each its share of the active strategy (operator 2026-11-15, the part operating; from CL-097-01) | backend/operating/StrategySelection.sysml | yes |
| CL-124-02 | requirement | new: a wanted station ranks first (issue 124, operator 2026-11-16: Q1 as WSJT-X, the list managed by settings) | backend/operating/ranking/WantedList.sysml | yes |
| CL-124-03 | requirement | new: an exact wanted entry leaves the list once worked; a pattern stays (issue 124 Q2 (a), operator 2026-11-16) | backend/operating/ranking/WantedList.sysml | yes |
| CL-111-07 | requirement | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-008-001 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-010-008 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-010-009 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-010-010 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-011-003 | verification | backend/operating/qso/QsoData.sysml | backend/log/Logbook.sysml | yes |
| TC-039-001 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-039-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-039-003 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-039-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-006 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-007 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-008 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-009 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-010 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-020 | verification | backend/operating/qso/QsoData.sysml | backend/spots/HearingFeed.sysml | yes |
| TC-039-052 | verification | new: the session steps of TC-039-020 | interfaces/external/PskReporter.sysml | yes |
| TC-039-021 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-022 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-030 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-039-032 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-039-033 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-042 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-043 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-044 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-045 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-047 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-048 | verification | backend/operating/qso/QsoData.sysml | backend/spots/HearingFeed.sysml | yes |
| TC-039-049 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-050 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-039-051 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-042-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-042-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/IgnoreLists.sysml | yes |
| TC-042-003 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-042-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-042-005 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-042-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/Alert.sysml | yes |
| TC-042-007 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-050-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-050-006 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-055-001 | verification | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| TC-055-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-055-003 | verification | backend/operating/qso/QsoData.sysml | backend/log/CountryFile.sysml | yes |
| TC-055-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-055-005 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-063-001 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-002 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-003 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-004 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| TC-063-005 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| TC-063-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ContestRanking.sysml | yes |
| TC-063-007 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-063-008 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-063-009 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-063-010 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-063-011 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-063-012 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-065-001 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-065-002 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-065-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-066-001 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-066-002 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-066-003 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-001 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-002 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-003 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-005 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-006 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-081-007 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-082-001 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-082-002 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-082-003 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-082-005 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-082-006 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-089-001 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-089-002 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-089-003 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-089-004 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-089-005 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-001 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-097-002 | verification | backend/operating/qso/QsoData.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-097-003 | verification | backend/operating/qso/QsoData.sysml | backend/operating/StrategySelection.sysml | yes |
| TC-097-006 | verification | backend/operating/qso/QsoData.sysml | backend/operating/ranking/ValueOrder.sysml | yes |
| TC-097-009 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-010 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-011 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-012 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-013 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-014 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-015 | verification | backend/operating/qso/QsoData.sysml | handed over: auto (the run of a contest strategy, the body of its test), frontend (the contest prompt); its two refusals are TC-063-007 (b) and (d) |  |
| TC-097-016 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-017 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-018 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-097-019 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-111-011 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| TC-125-002 | verification | backend/operating/qso/QsoData.sysml | TO PLACE |  |
| CL-111-02 | requirement | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| CL-111-05 | requirement | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| CL-111-08 | requirement | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| TC-111-003 | verification | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| TC-111-004 | verification | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| TC-111-006 | verification | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| TC-111-008 | verification | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| TC-111-012 | verification | backend/operating/qso/QsoTransmit.sysml | TO PLACE |  |
| CL-010-15 | requirement | backend/operating/qso/QsoWire.sysml | TO PLACE |  |
| TC-007-005 | verification | backend/operating/qso/QsoWire.sysml | TO PLACE |  |
| CL-024-02 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-024-03 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-024-04 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-085-03 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-099-01 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-099-02 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-111-10 | requirement | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-005 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-006 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-007 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-008 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-009 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-011 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-012 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-013 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-024-014 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-085-004 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-099-001 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-099-002 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-099-003 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-099-004 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| TC-111-016 | verification | backend/operating/qso/SpecialActivities.sysml | backend/operating/qso/SpecialActivities.sysml  (same name; rebuilt) |  |
| CL-010-01 | requirement | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| CL-010-02 | requirement | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| CL-010-12 | requirement | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| TC-007-001 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| TC-007-003 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| TC-007-004 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| TC-007-007 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
| TC-007-010 | verification | backend/operating/qso/StandardQso.sysml | backend/operating/qso/StandardQso.sysml  (same name; rebuilt) |  |
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
| CL-005-07 | requirement | new: the operator's folder and settings, shared by the operator's stations (operator 2026-11-16; from CL-005-02) | backend/profile/ProfileDocument.sysml | yes |
| CL-008-01 | requirement | backend/profile/Profile.sysml | retired: the same promise as CL-005-05 (the audio devices and the radio control stored each by itself, claiming no device); its control half is radio control's ControlSelection | - |
| CL-044-05 | requirement | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-002-001 | verification | backend/profile/Profile.sysml | backend/audio/Capture.sysml | yes |
| TC-009-001 | verification | backend/profile/Profile.sysml | backend/radioControl/CatControl.sysml | yes |
| TC-022-001 | verification | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-022-002 | verification | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-022-003 | verification | backend/profile/Profile.sysml | backend/profile/ProfileDocument.sysml | yes |
| TC-022-011 | verification | new: the operator's settings (operator 2026-11-16; callsign and locator conditions from TC-022-001) | backend/profile/ProfileDocument.sysml | yes |
| TC-022-005 | verification | backend/profile/Profile.sysml | handed over: frontend, station link (the browser's status while a profile read is held; nothing of it is shown at the profile) |  |
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
| TC-044-010 | verification | backend/radioControl/CatControl.sysml | handed over: frontend (the AGC field and its line in Settings; a browser test) | - |
| CL-022-04 | requirement | backend/radioControl/CatLifecycle.sysml | backend/radioControl/CatLifecycle.sysml | yes |
| CL-044-01 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-02 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-03 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-04 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-09 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/CatControl.sysml | yes |
| CL-044-10 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
| CL-044-15 | requirement | backend/radioControl/RadioSetup.sysml | backend/radioControl/RadioSetup.sysml | yes |
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
| TC-044-022 | verification | backend/radioControl/RadioSetup.sysml | handed over: frontend (the line on the confirmation in Settings; a browser test) | - |
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
| TC-010-002 | verification | backend/receive/ReceiveJob.sysml | handed over: station link, frontend | - |
| TC-010-003 | verification | backend/receive/ReceiveJob.sysml | handed over: frontend | - |
| TC-010-004 | verification | backend/receive/ReceiveJob.sysml | backend/receive/Spectrum.sysml | yes |
| TC-010-005 | verification | backend/receive/ReceiveJob.sysml | handed over: station link, frontend | - |
| TC-010-006 | verification | backend/receive/ReceiveJob.sysml | handed over: frontend | - |
| TC-010-007 | verification | backend/receive/ReceiveJob.sysml | handed over: frontend | - |
| TC-018-003 | verification | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| TC-052-001 | verification | backend/receive/ReceiveJob.sysml | backend/receive/ReceiveJob.sysml | yes |
| CL-045-01 | requirement | backend/receive/Startup.sysml | handed over: station (backend/station/Startup.sysml) |  |
| CL-045-02 | requirement | backend/receive/Startup.sysml | handed over: station (backend/station/Startup.sysml) |  |
| CL-045-03 | requirement | backend/receive/Startup.sysml | handed over: station (backend/station/Startup.sysml) |  |
| TC-045-001 | verification | backend/receive/Startup.sysml | handed over: station (backend/station/Startup.sysml) |  |
| TC-045-002 | verification | backend/receive/Startup.sysml | handed over: station (backend/station/Startup.sysml) |  |
| CL-008-07 | requirement | backend/station/OperatingSelection.sysml | backend/station/OperatingSelection.sysml  (same name; rebuilt) |  |
| CL-044-16 | requirement | backend/station/OperatingSelection.sysml | backend/station/OperatingSelection.sysml  (same name; rebuilt) |  |
| TC-044-023 | verification | backend/station/OperatingSelection.sysml | backend/station/OperatingSelection.sysml  (same name; rebuilt) |  |
| CL-009-02 | requirement | backend/transmit/Schedule.sysml | backend/transmit/Schedule.sysml | yes |
| TC-006-001 | verification | backend/transmit/Schedule.sysml | backend/transmit/Schedule.sysml | yes |
| CL-009-03 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-009-04 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-009-05 | requirement | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| CL-039-06 | requirement | backend/transmit/TransmitState.sysml | handed over: qso (the Tx watchdog is the contact's; operator 2026-11-15) | - |
| CL-043-01 | requirement | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| CL-043-03 | requirement | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| CL-044-13 | requirement | backend/transmit/TransmitState.sysml | handed over: station link, frontend | - |
| CL-044-14 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TxLevel.sysml | yes |
| CL-061-04 | requirement | backend/transmit/TransmitState.sysml | backend/receive/LiveReceive.sysml | yes |
| CL-111-01 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-111-03 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| CL-111-06 | requirement | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-006-003 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-008-002 | verification | backend/transmit/TransmitState.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| TC-008-003 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-008-005 | verification | new: Halt, the failures and the releases of TC-008-003 | backend/transmit/TransmitState.sysml | yes |
| TC-039-005 | verification | backend/transmit/TransmitState.sysml | handed over: qso (its (c), (d) are TC-111-013 (h), (i); its (a) left with spent; operator 2026-11-15) | - |
| TC-043-002 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-043-003 | verification | backend/transmit/TransmitState.sysml | handed over: station link, frontend |  |
| TC-043-004 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-044-015 | verification | backend/transmit/TransmitState.sysml | handed over: frontend | - |
| TC-044-017 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-018 | verification | backend/transmit/TransmitState.sysml | handed over: frontend | - |
| TC-044-019 | verification | backend/transmit/TransmitState.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| TC-061-005 | verification | backend/transmit/TransmitState.sysml | backend/receive/LiveReceive.sysml | yes |
| TC-007-012 | verification | new: the receive half of TC-007-006 and the window tests bound to TC-002-001 | backend/receive/LiveReceive.sysml | yes |
| TC-061-006 | verification | backend/transmit/TransmitState.sysml | handed over: frontend | - |
| TC-061-007 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-002 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-092-003 | verification | backend/transmit/TransmitState.sysml | backend/clock/StationClock.sysml | yes |
| TC-092-004 | verification | backend/transmit/TransmitState.sysml | handed over: station link, profile |  |
| TC-092-005 | verification | backend/transmit/TransmitState.sysml | handed over: frontend |  |
| TC-092-006 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-007 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-008 | verification | backend/transmit/TransmitState.sysml | not carried: planned, no test exists | - |
| TC-092-009 | verification | backend/transmit/TransmitState.sysml | handed over: station link |  |
| TC-111-001 | verification | backend/transmit/TransmitState.sysml | handed over: qso | - |
| TC-111-002 | verification | backend/transmit/TransmitState.sysml | handed over: qso | - |
| TC-111-007 | verification | backend/transmit/TransmitState.sysml | handed over: station link | - |
| TC-111-009 | verification | backend/transmit/TransmitState.sysml | handed over: qso | - |
| TC-111-010 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-111-013 | verification | backend/transmit/TransmitState.sysml | backend/transmit/TransmitState.sysml | yes |
| TC-111-017 | verification | new: the contact's answers to the Tune tone, from TC-111-010 (d), (e), (g) (operator 2026-11-15) | handed over: qso | - |
| TC-111-018 | verification | new: a stop against a start in one step, from TC-111-013 (a), (b) (operator 2026-11-15) | handed over: qso | - |
| TC-111-015 | verification | backend/transmit/TransmitState.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| CL-044-12 | requirement | backend/transmit/TxLevel.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-013 | verification | backend/transmit/TxLevel.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-014 | verification | backend/transmit/TxLevel.sysml | backend/transmit/TxLevel.sysml | yes |
| TC-044-016 | verification | backend/transmit/TxLevel.sysml | retired: a planned live case on the radio without a test (operator 2026-11-15) | - |
| CL-003-01 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-02 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-03 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-05 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-06 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-07 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-08 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-005-03 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-022-02 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-022-05 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-033-01 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-051-01 | requirement | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-009-005 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-021-005 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-021-006 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-021-008 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-021-009 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-022-004 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-022-008 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-033-001 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-051-001 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-051-003 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| TC-080-001 | verification | backend/web/StationProtocol.sysml | TO PLACE |  |
| CL-003-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-007-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-010-05 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-010-06 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-010-07 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-010-08 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-010-09 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-010-16 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-022-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-037-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-037-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-037-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-037-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-037-05 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-039-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-044-06 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-044-08 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-050-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-050-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-050-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-050-05 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-050-07 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-050-08 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-051-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-051-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-054-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-054-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-055-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-055-05 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-057-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-057-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-060-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-061-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-061-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-061-03 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-061-05 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-065-02 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-068-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-073-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-074-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-096-01 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-111-04 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| CL-111-09 | requirement | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-007-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-007-006 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-007-009 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-021-007 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-022-006 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-022-010 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-037-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-037-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-037-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-037-004 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-039-046 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-044-005 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-044-007 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-050-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-050-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-050-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-050-005 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-050-007 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-050-008 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-051-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-054-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-054-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-054-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-055-006 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-055-007 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-057-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-057-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-057-004 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-060-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-061-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-061-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-061-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-061-004 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-061-008 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-061-009 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-065-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-068-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-068-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-073-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-073-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-073-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-074-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-074-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-074-003 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-074-004 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-082-004 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-096-001 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-096-002 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-111-005 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
| TC-111-014 | verification | frontend/OperatingScreen.sysml | frontend/OperatingScreen.sysml  (same name; rebuilt) |  |
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
| CL-085-02 | requirement | interfaces/internal/OperatingChain.sysml | interfaces/internal/OperatingChain.sysml |  |
