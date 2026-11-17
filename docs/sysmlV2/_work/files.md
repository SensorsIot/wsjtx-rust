# Target files

| Target file | State |
|---|---|
| Context.sysml | taken over |
| Requirements.sysml | to build (old file of this name is pending) |
| Shack.sysml | taken over |
| interfaces/internal/StationLink.sysml | built (the wire, derived from the boundary) |
| interfaces/internal/WebControl.sysml | built (web's control interface) |
| interfaces/internal/StationCommands.sysml | built (the supervisor's control interface) |
| interfaces/internal/Strategies.sysml | built |
| interfaces/internal/RankingControl.sysml | built |
| interfaces/internal/AutoControl.sysml | built |
| interfaces/internal/QsoControl.sysml | built |
| interfaces/internal/LogControl.sysml | built |
| interfaces/internal/ReceiveControl.sysml | built |
| interfaces/internal/TransmitControl.sysml | built |
| interfaces/internal/AudioControl.sysml | built |
| interfaces/internal/RadioControl.sysml | built |
| interfaces/internal/Decodes.sysml | built |
| interfaces/internal/DisplayData.sysml | built |
| interfaces/internal/OperatingChain.sysml | taken over |
| interfaces/internal/Hearing.sysml | built |
| interfaces/internal/AudioStreams.sysml | built |
| interfaces/internal/ModeProcessing.sysml | built |
| interfaces/internal/ProfileAccess.sysml | built |
| interfaces/internal/RecordingTransfer.sysml | built |
| interfaces/external/OperatorInteraction.sysml | taken over |
| interfaces/external/Mcp.sysml | taken over |
| interfaces/external/Cat.sysml | built |
| interfaces/external/RadioProperties.sysml | built |
| interfaces/external/FlexApi.sysml | built |
| interfaces/external/SoundDevice.sysml | built |
| interfaces/external/Udp.sysml | built |
| interfaces/external/PskReporter.sysml | built |
| interfaces/external/ClubLog.sysml | built |
| interfaces/external/CountryFiles.sysml | built |
| interfaces/external/TimeSource.sysml | taken over |
| backend/supervisor/Supervisor.sysml | built |
| backend/supervisor/OperatingSelection.sysml | built |
| backend/supervisor/StationAuthority.sysml | built |
| backend/supervisor/Startup.sysml | built |
| backend/web/Web.sysml | built |
| backend/web/Listener.sysml | built |
| backend/web/ContentCoding.sysml | built |
| backend/mcp/Mcp.sysml | to build (old file of this name is pending) |
| backend/mcp/McpEndpoint.sysml | to build (old file of this name is pending) |
| backend/profile/Profile.sysml | built |
| backend/profile/ProfileDocument.sysml | built |
| backend/profile/Recordings.sysml | built |
| backend/receive/Receive.sysml | built |
| backend/receive/ReceiveJob.sysml | built |
| backend/receive/Spectrum.sysml | built |
| backend/receive/LiveReceive.sysml | built |
| backend/modes/Modes.sysml | built |
| backend/modes/Decode.sysml | built |
| backend/modes/MessageEncode.sysml | built |
| backend/modes/MessagePayload.sysml | built |
| backend/clock/Clock.sysml | built |
| backend/clock/StationClock.sysml | built |
| backend/transmit/Transmit.sysml | built |
| backend/transmit/TransmitState.sysml | built |
| backend/transmit/Schedule.sysml | built |
| backend/transmit/TxLevel.sysml | built |
| backend/operating/Operating.sysml | built |
| backend/operating/StrategySelection.sysml | built |
| backend/operating/ranking/Ranking.sysml | built |
| backend/operating/ranking/ValueOrder.sysml | built |
| backend/operating/ranking/ContestRanking.sysml | built |
| backend/operating/ranking/IgnoreLists.sysml | built |
| backend/operating/ranking/WantedList.sysml | built |
| backend/operating/ranking/MostWanted.sysml | built |
| backend/operating/ranking/Alert.sysml | built |
| backend/operating/auto/Auto.sysml | built |
| backend/operating/auto/TargetChoice.sysml | built |
| backend/operating/auto/CqWhenIdle.sysml | built |
| backend/operating/auto/TxSlot.sysml | built |
| backend/operating/auto/Leave.sysml | built |
| backend/operating/auto/AutoMode.sysml | built |
| backend/operating/qso/Qso.sysml | built |
| backend/operating/qso/StandardQso.sysml | built |
| backend/operating/qso/SpecialActivities.sysml | built |
| backend/operating/qso/MessageChoice.sysml | built |
| backend/operating/qso/QsoTransmit.sysml | built (Qso* of M2.1) |
| backend/operating/qso/HoldTx.sysml | built |
| backend/log/Log.sysml | built |
| backend/log/Logbook.sysml | built |
| backend/log/CountryFile.sysml | built |
| backend/spots/Spots.sysml | built |
| backend/spots/HearingFeed.sysml | built |
| backend/spots/SpotsReporting.sysml | built |
| backend/udp/Udp.sysml | built |
| backend/udp/UdpSender.sysml | built |
| interfaces/internal/UdpControl.sysml | built |
| interfaces/internal/Keying.sysml | built |
| interfaces/internal/StationTime.sysml | built |
| backend/audio/Audio.sysml | built |
| backend/audio/AudioDevice.sysml | built |
| backend/audio/Capture.sysml | built |
| backend/audio/Endpoints.sysml | built |
| backend/audio/Playback.sysml | built |
| backend/radioControl/RadioControl.sysml | built |
| backend/radioControl/CatControl.sysml | built |
| backend/radioControl/CatLifecycle.sysml | built |
| backend/radioControl/RadioFacts.sysml | built |
| backend/radioControl/RadioSetup.sysml | built |
| backend/flexAdapter/FlexAdapter.sysml | built |
| backend/flexAdapter/FlexSession.sysml | built |
| frontend/BrowserClient.sysml | to build (old file of this name is pending) |
| frontend/OperatingScreen.sysml | to build (old file of this name is pending) |
| frontend/BandActivityPane.sysml | to build (old file of this name is pending) |
| frontend/SignalArea.sysml | to build (old file of this name is pending) |
| frontend/QsoPane.sysml | to build (old file of this name is pending) |
| frontend/LowerPanel.sysml | to build (old file of this name is pending) |
| frontend/Settings.sysml | to build (old file of this name is pending) |
| shared/Units.sysml | taken over |
| shared/Quantities.sysml | to build (new file) |
| shared/ModelBindings.sysml | taken over |
| shared/ModelNotes.sysml | taken over |

# Old files with no place in the target

| Old file | Lines | Identities |
|---|---|---|
| backend/clock/StationClock.sysml | 224 | 3 |
| backend/log/Contest.sysml | 86 | 0 |
| backend/operating/auto/Automation.sysml | 221 | 0 |
| backend/operating/auto/Strategy.sysml | 608 | 0 |
| backend/operating/qso/QsoData.sysml | 2038 | 140 |
| backend/operating/qso/QsoTransmit.sysml | 303 | 8 |
| backend/operating/qso/QsoWire.sysml | 94 | 2 |
| backend/web/StationProtocol.sysml | 1271 | 23 |
| interfaces/internal/Keying.sysml | 18 | 0 |
