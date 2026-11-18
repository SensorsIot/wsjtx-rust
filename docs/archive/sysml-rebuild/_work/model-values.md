# Model values against the code, 2026-11-18 (read only)

347 values: held by product code 271 (named constant 132, inline 75, setting default 35, wire 8,
CSS 3, other unit 5, mismatch 1, plus code and a model-reading test 11), held only by tests or
fixtures 39, held nowhere 37 (not built 24, absent though implemented 4, judged 6, source 3,
unshown 1). Proposed rule: V1 code constant named after the feature; V2 a contract test reading the
value by qualified name (M6.8) for values the product meets by design; V3 not built: a carrying
clause at target or partial, computed through model references across files; V4 `@CodeDiffers`
where an implemented clause's code differs (displayName, ignoreListMax, alcLimit/alcHigh,
ShackDocument, region, levelMode, sortDescending?); V5 judged values need a clause
(ThinLinkBudget). Possible A4/A5 removals: safeIntegerMax and the i3 range (source), FT8/FT4
Period (protocol), DialRange (one rig), checkpointMaxMs (a limit of the code). Questions: V2;
carrying clause across files; source values; tolerances; ThinLinkBudget; three mismatches; CSS.

## Table

### CONST (132)
- WstxCapture::CaptureStream::{glitchToleranceMs=2} | CONTIGUOUS_QPC_TOLERANCE_100NS = 20_000 (100 ns) server/src/audio.rs:88
- WstxCapture::CaptureClock::{reanchorMs=50} | RESCHEDULE_TICKS = 500_000.0 (100 ns) server/src/recording.rs:3143 (a receive module)
- WstxCapture::CaptureClock::{stepMs=200} | STEP_TICKS = 2_000_000.0 (100 ns) server/src/recording.rs:3144
- WstxCapture::CaptureClock::{driftWarnPpm=1000} | CAPTURE_DRIFT_WARN_PPM = 1000.0 server/src/recording.rs:3146
- WstxEndpoints::EndpointNaming::{maxEndpoints=64} | MAX_ENDPOINTS = 64 server/src/radio_setup.rs:713
- WstxPlayback::ProgramPlayback::{sampleRateHz=48000} | SAMPLE_RATE_HZ = 48_000 server/src/transmit/service.rs:25; also inline modes/playback/windows.rs:228
- WstxPlayback::ProgramPlayback::{renderBufferMs=100} | RENDER_BUFFER_MS = 100 server/src/transmit/playback.rs:127
- WstxPlayback::ProgramPlayback::{silencePrefillMs=20} | SILENCE_FRAMES = 960 (frames at 48 kHz) server/src/transmit/playback.rs:130
- WstxPlayback::ProgramPlayback::{stallMs=500} | STALL_MS = 500 server/src/transmit/playback.rs:160
- WstxStationClock::AirClock::{minSnrDb=-20} | MIN_SNR_DB = -20.0 server/src/transmit/air.rs:18
- WstxStationClock::AirClock::{maxDtMs=3000} | MAX_DT_MS = 3000 air.rs:20
- WstxStationClock::AirClock::{windowSeconds=120} | WINDOW_MS = 120_000 air.rs:22
- WstxStationClock::AirClock::{sideMarginMs=100} | SIDE_MARGIN_MS = 100 air.rs:28
- WstxStationClock::AirClock::{minStations=4} | MIN_STATIONS = 4 air.rs:24
- WstxStationClock::AirClock::{sameSidePct=80} | SAME_SIDE_PCT = 80 air.rs:26
- WstxStationClock::AirClock::{maxAgeSeconds=60} | MAX_AGE_MS = 60_000 air.rs:32
- WstxStationClock::Correction::{maxSlewPerPeriodMs=1000} | MAX_SLEW_PER_PERIOD_MS = 1000 air.rs:30
- WstxStationClock::Correction::{txBoundMs=1000} | TX_BOUND_MS = 1000 air.rs:34
- WstxStationClock::Correction::{maxStepMs=100} | MAX_STEP_MS = 100 server/src/transmit/clock.rs:54
- WstxStationClock::Correction::{maxStepRestartMs=3000} | MAX_STEP_RESTART_MS = 3000 air.rs:36
- WstxStationClock::TimeServerCheck::{maxOffsetMs=500} | MAX_OFFSET_MS = 500 clock.rs:49
- WstxStationClock::TimeServerCheck::{maxAgeSeconds=600} | MAX_AGE = from_secs(600) clock.rs:51
- WstxStationClock::WarningRule::{stationsOffMs=500} | STATIONS_OFF_MS = 500 air.rs:38
- WstxFlexSession::SessionLifecycle::{stepSeconds=5} | STEP = from_secs(5) server/src/flexAdapter/session.rs:67
- WstxFlexSession::SessionLifecycle::{maxRetryMs=4000} | BACKOFF_MAX_MS = 4000 session.rs:69
- WstxFlexSession::RadioChoice::{listenSeconds=3} | DISCOVERY_WAIT = from_secs(3) session.rs:68
- WstxFlexSession::RadioChoice::{keepAliveSeconds=5} | REGISTER_EVERY = from_secs(5) session.rs:74
- WstxFlexSession::StreamIntake::{outputRateHz=48000} | NativeInput::FORMAT.rate = 48_000 session.rs:1492 (field of a const)
- WstxFlexSession::StreamIntake::{reorderPackets=5} | REORDER_DEPTH = 5 session.rs:73
- WstxFlexSession::StreamIntake::{unknownGapMs=200} | UNKNOWN_GAP_100NS = 2_000_000 session.rs:75
- WstxFlexSession::StreamIntake::{groupMs=10} | GROUP_FRAMES = 480 (frames at 48 kHz) session.rs:78
- WstxLogbook::UpdateLogbook::{idleSeconds=60} | IMPORT_IDLE = from_secs(60) server/src/logbook.rs:56
- WstxLogbook::UpdateLogbook::{consolidationSeconds=120} | CONSOLIDATION_SECONDS = 120 logbook.rs:52
- WstxDecode::APrioriHypotheses::{nearHz=50} | AP_WIDTH_HZ = 50. server/src/modes/decoder/apriori.rs:38
- WstxDecode::APrioriHypotheses::{minConfidence=0.17} | LOW_CONFIDENCE_QUALITY = 0.17 apriori.rs:151
- WstxMessageEncode::Ft8WaveformContract::{minTone0Hz=200.0} | MIN_TONE0_HZ = 200. server/src/modes/transmit/waveform.rs:17
- WstxMessageEncode::Ft8WaveformContract::{maxTone0Hz=2950.0} | MAX_TONE0_HZ = 2950. waveform.rs:18
- WstxMessageEncode::Ft4WaveformContract::{minTone0Hz=200.0} | FT4_MIN_TONE0_HZ = 200. waveform.rs:20
- WstxMessageEncode::Ft4WaveformContract::{maxTone0Hz=2916.666667} | FT4_MAX_TONE0_HZ = 3000. - 4. * 12000. / 576. (expression = 2916.666...) waveform.rs:21 | **model 2916.666667 is a rounding of the expression**
- WstxMessagePayload::HashResolution::{maxHash22=1000} | MAX_HASH22 = 1000 server/src/modes/decoder/hashes.rs:9
- WstxHoldTx::SlotLimits::{clearanceHz=50} | CLEARANCE_HZ = 50 server/src/operating/qso/freeslot.rs:19
- WstxHoldTx::SlotLimits::{candidateLowHz=500} | CANDIDATE_LOW_HZ = 500 freeslot.rs:60
- WstxHoldTx::SlotLimits::{upperEdgeHz=2400} | UPPER_EDGE_HZ = 2400 freeslot.rs:62 | **value equal; behaviour differs (archive verdict; CL-039-09 partial)**
- WstxHoldTx::SlotLimits::{periodsPerParity=4} | PERIODS_PER_PARITY = 4 freeslot.rs:24
- WstxHoldTx::OffsetRule::{rxMaxHz=3000} | RX_MAX_HZ = 3000 server/src/contact.rs:20
- WstxHoldTx::OffsetRule::{txMinHz=200} | TX_MIN_HZ = 200 contact.rs:21
- WstxMessageChoice::ReportRange::{minimumDb=-50} | REPORT_MIN = -50 contact.rs:16; client/contact.js:56 min="-50"
- WstxMessageChoice::ReportRange::{maximumDb=49} | REPORT_MAX = 49 contact.rs:17; client max="49"
- WstxMessageChoice::ReportRange::{startDb=-15} | REPORT_DEFAULT = -15 contact.rs:18
- WstxSpecialActivities::HoundLimits::{callingMs=300000} | HOUND_WATCHDOG_MS = 300_000 contact.rs:1075
- WstxCatControl::ControlExchange::{exchangeMaxBytes=4096} | MAX_BYTES = 4096 server/src/transmit/codec.rs:6
- WstxCatControl::ControlExchange::{exchangeMaxFrames=64} | MAX_FRAMES = 64 codec.rs:7
- WstxCatLifecycle::RetryCadence::{firstRetrySeconds=1, maxRetrySeconds=8} | DELAYS = [1, 2, 4, 8] server/src/radioControl/cat_lifecycle.rs:52 (array: first/last element)
- WstxRadioSetup::ManagedAgc::{retrySeconds=2} | RETRY = from_secs(2) server/src/radioControl/radio_agc.rs:19
- WstxLiveReceive::WindowSchedule::{ft8PromptEndMs=13800, ft8LateEndMs=15700, ft4PromptEndMs=6500, ft4LateEndMs=7900} | LIVE_WINDOWS (array of (completion, length), 100 ns) server/src/recording.rs:3093-3101: 138_000_000, 157_000_000, 65_000_000, 79_000_000
- WstxReceiveJob::WindowDiagnostics::{keptWindows=20} | WINDOWS = 20 server/src/receive/receive_diagnostics.rs:19
- WstxReceiveJob::WindowDiagnostics::{dumpKeep=20} | DUMP_KEEP = 20 receive_diagnostics.rs:16
- WstxReceiveJob::WindowDiagnostics::{dumpMiB=16} | DUMP_BYTES = 16 * 1024 * 1024 receive_diagnostics.rs:17
- WstxReceiveJob::WindowDiagnostics::{earlyFrames=141696} | EARLY_FRAMES = 41 * 3456 receive_diagnostics.rs:21 (also EARLY in modes/decoder/snr.rs:21)
- WstxSpectrum::ThinSpectrum::{size=2048} | SIZE = 2048 server/src/spectrum.rs:4
- WstxSpectrum::ThinSpectrum::{hop=256} | HOP = 256 spectrum.rs:5
- WstxHearingFeed::HearingFeed::{heardWindowSeconds=600} | HEARD_WINDOW_S = 600 server/src/operating/qso/pskr.rs:35
- WstxTransmitState::Transmission::{releaseMarginMs=1000} | RELEASE_MARGIN_MS = 1000 server/src/transmit/service.rs:43
- WstxTransmitState::Transmission::{keptOutcomes=32} | OUTCOMES = 32 service.rs:53
- WstxTransmitState::HaltTransmit::{haltBoundMs=250} | HALT_BOUND_MS = 250 service.rs:27
- WstxTxLevel::TxLevel::{levelMinDb=-40} | LEVEL_MIN_DB = -40 service.rs:31
- WstxTxLevel::TxLevel::{levelMaxDb=0} | LEVEL_MAX_DB = 0 service.rs:32
- WstxTxLevel::TxLevel::{playbackScale=0.5} | PLAYBACK_SCALE = 0.5 service.rs:29
- WstxTxLevel::TxLevel::{tuneReadMs=1000} | TUNE_READ_EVERY = from_secs(1) server/src/radio_level.rs:32
- WstxTxLevel::TxLevel::{meterReadMaxMs=400} | METER_READ = from_millis(400) radio_level.rs:30
- WstxTxLevel::LevelFinding::{startDb=-30} | ASSISTANT_START_DB = -30 radio_level.rs:23
- WstxTxLevel::LevelFinding::{settleMs=400} | SETTLE = from_millis(400) radio_level.rs:26 (5 ms under cfg(test))
- WstxTxLevel::LevelMonitor::{meterMinRemainingMs=2000} | METER_MIN_REMAINING_MS = 2_000 service.rs:34
- WstxTxLevel::LevelMonitor::{persistentReadings=3} | PERSISTENT = 3 radio_level.rs:91
- WstxUdpSender::InstanceName::{base="WSTX-Rust"} | INSTANCE_BASE = "WSTX-Rust" server/src/operating/qso/udp.rs:24
- WstxListener::LinkTrafficLog::{fileName="link-traffic.log"} | FILE = "link-traffic.log" server/src/web/link_log.rs:31
- WstxListener::LinkTrafficLog::{rotateBytes=4194304} | ROTATE_BYTES = 4_194_304 link_log.rs:32
- WstxListener::LinkTrafficLog::{segmentBytesMax=512} | SEGMENT_BYTES_MAX = 512 link_log.rs:36
- WstxListener::LinkTrafficLog::{headerBytesPerSegment=80} | HEADER_BYTES_PER_SEGMENT = 80 link_log.rs:37
- WstxListener::LinkTrafficLog::{reverseAckBytesPerSegment=80} | REVERSE_ACK_BYTES_PER_SEGMENT = 80 link_log.rs:38
- WstxListener::LinkTrafficLog::{tlsRecordOverheadBytes=29} | TLS_RECORD_OVERHEAD_BYTES = 29 link_log.rs:33
- WstxListener::LinkTrafficLog::{tlsRecordPayloadMax=16384} | TLS_RECORD_PAYLOAD_MAX = 16_384 link_log.rs:34
- WstxQsoPane::CallingMe::{callingLines=8} | OTHER_LINES = 8 client/contact.js:808
- WstxQsoPane::MessageLines::{loggedSeconds=8} | LOGGED_NOTICE_MS = 8000 client/contact.js:319
- WstxCat::CivFrame::{maxFrameBytes=32} | MAX_FRAME = 32 server/src/transmit/codec.rs:4
- WstxClubLog::MostWantedQuery::{sourceUrl="https://clublog.org/mostwanted.php?api=1"} | SOURCE_URL server/src/most_wanted.rs:12
- WstxClubLog::MostWantedDownload::{entriesMax=1000} | ENTRIES_MAX = 1000 most_wanted.rs:11
- WstxClubLog::MostWantedDownload::{attribution="Club Log Most Wanted list, Club Log (c) Michael Wells G7VJR, clublog.org"} | ATTRIBUTION most_wanted.rs:18-19
- WstxCountryFiles::CtyDownload::{bytesMax=1048576} | FILE_BYTES_MAX = 1_048_576 server/src/dxcc.rs:20 (limit of an uploaded file; the download is target)
- WstxFlexApi::ProtocolVersion::{admitted="1.4.0.0"} | SUPPORTED_PROTOCOL = ProtocolVersion{1,4,0,0} server/src/flexAdapter/wire.rs:13 (struct)
- WstxMcp::McpEndpoint::{bodyBytesMax=8192} | BODY_MAX = 8192 server/src/mcp.rs:17
- WstxMcp::ProtocolVersions::{modern="2026-07-28"} | MODERN = "2026-07-28" mcp.rs:18
- WstxMcp::ProtocolVersions::{legacy=("2025-11-25", "2025-06-18")} | LEGACY = ["2025-11-25", "2025-06-18"] mcp.rs:19
- WstxPskReporter::FeedSession::{keepAliveSeconds=60, firstRetrySeconds=5, maxRetrySeconds=300, stableSessionSeconds=60} | Timing::BROKER fields keep_alive_s 60, backoff_first 5 s, backoff_max 300 s, stable 60 s server/src/operating/qso/pskr.rs:68-77
- WstxPskReporter::FeedSession::{maxPacketBytes=4096} | PACKET_MAX = 4096 pskr.rs:43
- WstxPskReporter::FeedSession::{maxFieldLength=16} | FIELD_MAX = 16 pskr.rs:45
- WstxUdp::UdpWire::{schemaOut=2} | SCHEMA_OUT = 2 server/src/network_message.rs:8
- WstxUdp::UdpWire::{schemaMax=3} | SCHEMA_MAX = 3 network_message.rs:10
- WstxUdp::UdpWire::{inboundMaxBytes=4096} | INBOUND_BYTES_MAX = 4096 network_message.rs:11
- WstxAudioStreams::NativePacket::{maxNativePacketFrames=8192} | MAX_NATIVE_PACKET = 8192 server/src/audio.rs:21
- WstxHearing::SpotsConfig::{feedBroker="mqtts://mqtt.pskreporter.info:1884"} | HOST = "mqtt.pskreporter.info" + TLS_PORT = 1884 pskr.rs:25,27 (not configurable; split) | **form: URL vs host+port consts; not a setting**
- WstxLogControl::LogLimits::{importBytesMax=67108864} | IMPORT_BYTES_MAX = 67_108_864 server/src/logbook.rs:21
- WstxLogControl::LogLimits::{importRecordsMax=100000} | IMPORT_RECORDS_MAX = 100_000 logbook.rs:22
- WstxLogControl::LogLimits::{importChunkBytesMax=16384} | IMPORT_CHUNK_BYTES_MAX = 16_384 logbook.rs:25
- WstxLogControl::LogLimits::{fieldCharactersMax=1024} | FIELD_CHARACTERS_MAX = 1024 logbook.rs:23
- WstxLogControl::LogLimits::{fieldNameCharactersMax=64} | FIELD_NAME_CHARACTERS_MAX = 64 logbook.rs:24
- WstxLogControl::LogLimits::{historyPageRecordsMax=10} | HISTORY_PAGE_RECORDS_MAX = 10 logbook.rs:26
- WstxLogControl::LogLimits::{historyPageBytesMax=16384} | HISTORY_PAGE_BYTES_MAX = 16_384 logbook.rs:27
- WstxLogControl::LogLimits::{exportChunkRecords=128} | EXPORT_CHUNK_RECORDS = 128 logbook.rs:1120
- WstxOperatingChain::BusyPartner::{freeTextHz=10} | BUSY_FREE_TEXT_HZ = 10.0 server/src/contact.rs:757
- WstxRankingControl::RankingLimits::{orderMax=16} | ORDER_MAX = 16 server/src/strategy.rs:133
- WstxRankingControl::RankingLimits::{bandsMax=32} | BANDS_MAX = 32 strategy.rs:220
- WstxRankingControl::RankingLimits::{countriesMax=64} | COUNTRIES_MAX = 64 strategy.rs:218
- WstxRankingControl::RankingLimits::{cqTargetsMax=32} | CQ_TARGETS_MAX = 32 strategy.rs:219
- WstxRankingControl::RankingLimits::{evaluateMax=2048} | EVALUATE_MAX = 2048 strategy.rs:24
- WstxRankingControl::RankingLimits::{alertHistoryMax=100} | ALERT_HISTORY_MAX = 100 strategy.rs:30
- WstxRankingControl::RankingLimits::{alertDedupeMinutes=10} | ALERT_DEDUPE_MS = 10 * 60_000 strategy.rs:31 (expression, ms)
- WstxStationLink::JsonValues::{safeIntegerMax=900719925 * 10000000 + 4740991} | MAX_SAFE = 9_007_199_254_740_991 in automation.rs:17, contact_http.rs:22, operating/qso/udp.rs:36, strategy.rs:33, transmit/service.rs:52; MAX_REVISION profile.rs:14; MAX_COUNTER source.rs:8; MAX_SAFE_SEQUENCE history.rs:5 (8 constants) | **model is an expression 900719925 * 10000000 + 4740991**
- WstxStationLink::Limits::{recordBytes=8192} | SAVE_BODY_MAX = 8192 server/src/logbook_http.rs:16
- WstxStationLink::Limits::{settingsBytes=32768} | BODY_MAX = 32_768 server/src/strategy.rs:22 (PUT /strategy only)
- WstxStationLink::Limits::{logChunkBytes=16384} | IMPORT_CHUNK_BYTES_MAX = 16_384 logbook.rs:25
- WstxStationLink::DisplayRows::{detailRecentRows=25} | DETAIL_RECENT = 25 server/src/recording.rs:3396
- WstxStrategies::StrategyConfiguration::{strategiesMax=16} | STRATEGIES_MAX = 16 strategy.rs:23
- WstxStrategies::ContestSelection::{periodDaysMax=31} | PERIOD_MAX_MS = 31 * DAY_MS server/src/contest.rs:527 (ms expression)
- WstxUdpControl::UdpConfiguration::{targetsMax=16} | TARGETS_MAX = 16 server/src/operating/qso/udp.rs:20

### CONST-OTHERUNIT (5)
- WstxTxLevel::LevelFinding::{swrFaultX10=30} | SWR_FAULT_RAW = 120 (IC-7300 meter count) radio_level.rs:34; swr_x10(120)=30 | **equal effect, other quantity**
- WstxTxLevel::LevelMonitor::{alcLimit=8} | ALC_LIMIT_RAW = 10 (meter count; 10/120 = 8 %) radio_level.rs:84 | **other quantity**
- WstxTxLevel::LevelMonitor::{alcHigh=50} | ALC_HIGH_RAW = 60 (meter count; 50 %) radio_level.rs:87 | **other quantity**
- WstxTxLevel::LevelMonitor::{swrHighX10=20} | SWR_HIGH_RAW = 80 (meter count; swr_x10 = 20) radio_level.rs:89 | **other quantity**
- WstxSignalArea::SwrValue::{redAboveSwr=2.0} | SWR_RED_ABOVE_X10 = 20 client/recording.js:1208 | **x10 form**

### CONST-DIFF (1)
- WstxRankingControl::RankingLimits::{ignoreListMax=20} | IGNORE_CALLS_MAX = 100 (saved) strategy.rs:26; SESSION_IGNORE_MAX = 64 strategy.rs:27 | **MISMATCH: model 20**

### INLINE (75)
- WstxAudioDevice::DeviceLifecycle::{firstRetryMs=1000, maxRetryMs=8000} | server/src/audio.rs:1000 `1000_u64 << self.attempt.min(3)` (1000..8000)
- WstxAudioDevice::DeviceLifecycle::{closeMaxMs=250} | server/src/audio/windows.rs:242 from_millis(250)
- WstxCapture::CaptureStream::{queueMs=500} | server/src/audio.rs:297 `capacity: format.rate as usize / 2`
- WstxCapture::CaptureStream::{queuePackets=64} | server/src/audio.rs:279-281 sync_channel(64), 0..64
- WstxCapture::CaptureClock::{bracketMaxMs=2} | server/src/audio.rs:621 `uncertainty_ns <= 2_000_000`
- WstxCapture::CaptureClock::{clockJumpMs=20} | server/src/audio.rs:640 `> 200_000` (100 ns)
- WstxCapture::CaptureClock::{rateKnownSeconds=60} | server/src/recording.rs:3172 `seconds >= 60.0`
- WstxEndpoints::EndpointNaming::{maxTextBytes=256} | server/src/radio_setup.rs:794 `len() > 256`
- WstxPlayback::ProgramPlayback::{openMaxMs=1000} | server/src/modes/playback/windows.rs:92 from_secs(1)
- WstxPlayback::ProgramPlayback::{closeMaxMs=250} | server/src/modes/playback/windows.rs:174 from_millis(250)
- WstxStationClock::TimeBase::{startCorrectionMs=0} | server/src/transmit/air.rs:328 AirClock::default() (derived 0)
- WstxFlexSession::SessionLifecycle::{firstRetryMs=1000} | session.rs:549,573 `backoff = 1000`
- WstxDecode::DecodeBudgets::{recordCap=2048, recordMaxBytes=1024} | server/src/modes/decoder/history.rs:522 `>= 2048 || bytes > 1024`
- WstxDecode::DecodeThreads::{sparedProcessors=1} | server/src/modes/decoder/parallel.rs:13 `saturating_sub(1)`
- WstxMessagePayload::HashResolution::{minCallLength=3} | hashes.rs:82 `call.len() < 3`
- WstxHoldTx::OffsetRule::{txMaxFt8Hz=2950, txMaxFt4Hz=2916} | contact.rs:22-25 fn tx_max_hz (2950 / 2916)
- WstxSpecialActivities::HoundLimits::{replyPeriods=11} | contact.rs:3066 `11 * period_ms(mode)`
- WstxValueOrder::ValueOrder::{snrBucketUpperDb=0, snrBucketLowerDb=-10} | server/src/strategy.rs:1685-1686 `snr > 0.0`, `snr >= -10.0`
- WstxCatControl::RadioConnection::{pollSeconds=1} | server/src/radio_control/actor.rs:257 from_secs(1); executor.rs:126
- WstxCatControl::KeyingRules::{closingUnkeyMaxMs=250} | server/src/radio_control/actor.rs:276 from_millis(250)
- WstxRadioSetup::RadioDetection::{maxPorts=64} | server/src/radio_setup.rs:254,469 `.take(64)`
- WstxLiveReceive::TransmitPeriods::{keptPeriods=16} | server/src/recording.rs:376 `self.starts.len() > 16`
- WstxLiveReceive::RxLevel::{maxDb=90} | recording.rs:422 `.clamp(0.0, 90.0)`
- WstxReceiveJob::LiveResults::{keptRecords=2048} | recording.rs:1597 `len() >= 2048`
- WstxReceiveJob::LiveResults::{keptMiB=2} | recording.rs:1597 `2 * 1024 * 1024`
- WstxReceiveJob::LiveResults::{recordMaxBytes=2048} | recording.rs:1594 `size > 2048`
- WstxReceiveJob::LiveResults::{snrLimitDb=60} | recording.rs:1543 `-60.0..=60.0`
- WstxSpectrum::DetailedSpectrum::{detailSize=4096} | spectrum.rs:20 with_size(.., 4096); recording.rs:3485
- WstxSpectrum::DetailedSpectrum::{detailHop=480} | recording.rs:3503 `+= 480`
- WstxSpectrum::DetailedSpectrum::{rowFrames=2400} | recording.rs:2807,3442 `2400`
- WstxTransmitState::Transmission::{releaseBoundFt8Ms=14500, releaseBoundFt4Ms=7000} | service.rs:46-50 const fn release_bound_ms (14_500 / 7_000)
- WstxTransmitState::Failures::{keyExchangeMaxMs=1000} | server/src/transmit_http.rs:123,125 from_secs(1)
- WstxTransmitState::SafetyReleases::{exitReleaseMaxMs=500} | transmit_http.rs:279 from_millis(500)
- WstxTransmitState::TuneTone::{offsetMinHz=200, offsetMaxHz=2950} | service.rs:931 `(200..=2950)`
- WstxTxLevel::LevelMonitor::{stepUpBelowPct=80} | radio_level.rs:124 `p * 5 < l * 4`
- WstxTxLevel::LevelMonitor::{poLowPct=50} | radio_level.rs:125 `p * 2 < l`
- WstxListener::ClientBuild::{hexDigits=16} | server/src/main.rs:983 `[..8]` bytes as hex = 16 digits
- WstxOperatingScreen::KeyRule::{txStepFt8Hz=60, txStepFt4Hz=90} | client/contact.js:714 `sign*(ft4?90:60)`
- WstxOperatingScreen::LinkRule::{silenceMs=12000} | client/app.js:154 `> (deferredDownloads ? 30000 : 12000)`; tests/communication.test.cjs:372
- WstxOperatingScreen::LinkRule::{retryMs=1000} | client/app.js:25 `let retry = 1000`
- WstxOperatingScreen::LinkRule::{retryMaxMs=4000} | client/app.js:39 Math.min(retry * 2, 4000); :69,:196 setTimeout(connect, 4000)
- WstxOperatingScreen::LinkRule::{connectMs=5000} | client/app.js:92 setTimeout(.., 5000)
- WstxQsoPane::CallingMe::{crowdingHz=50} | client/contact.js:821 `f>=o-50&&f<=o+50`
- WstxSignalArea::DisplayLevels::{referenceDbfs=-85} | client/recording.js:190 displayBlack=-85
- WstxSignalArea::DisplayLevels::{speedStep=0.5} | client/recording.js:136 step="0.5"
- WstxSignalArea::RxTxStrip::{stepHz=1, shiftStepHz=10} | client/contact.js:876,877,882 `(event.shiftKey?10:1)`
- WstxRadioProperties::DialRange::{lowestHz=30000, highestHz=74800000} | server/src/radio_control/mod.rs:271; server/src/transmit/codec.rs:10,35 `(30000..=74800000)`
- WstxModeProcessing::Period::{ft8PeriodMs=15000, ft4PeriodMs=7500} | server/src/contact.rs:46-50 fn period_ms; server/src/transmit/schedule.rs:17-18; server/src/operating/qso/freeslot.rs:47-48; recording.rs:3077-3078 (100 ns)
- WstxModeProcessing::Period::{ft8NominalStartMs=500, ft4NominalStartMs=452, ft8FrameMs=12640, ft4FrameMs=5040} | server/src/recording.rs:3077-3078 period_parameters (5_000_000/4_520_000, 126_400_000/50_400_000 in 100 ns)
- WstxModeProcessing::DecodeBand::{decodeBandLowHz=200, decodeBandHighHz=3500} | server/src/decoder/search.rs:801-802,810,844 `.max(200.)`, `.min(3500.)`
- WstxProfileAccess::ProfileLimits::{displayNameMaxBytes=64} | profile.rs:194 `text(&self.display_name, 64)`
- WstxRecordingTransfer::RecordingLimits::{reservationMs=30000, uploadIdleMs=15000} | recording.rs:3919 `if reserved { 30 } else { 15 }` seconds
- WstxRecordingTransfer::RecordingLimits::{uploadTotalMs=1800000} | recording.rs:3923 from_secs(1800)
- WstxStationLink::Limits::{controlBytes=1024} | server/src/main.rs:536-560 DefaultBodyLimit::max(1024) (many routes); main.rs:952 max_message_size(1024)
- WstxStationLink::Limits::{recordingChunkBytes=2048} | server/src/recording_http.rs:197 `2048`
- WstxStationLink::SocketProtocol::{heartbeatMs=5000} | server/src/main.rs:1179 interval(from_secs(5))
- WstxStationLink::SocketProtocol::{eventDelayMs=1000} | main.rs:1189,1199,1230 from_secs(1)
- WstxTransmitControl::StartWindow::{ft8AudioDelayMs=500, ft4AudioDelayMs=300} | server/src/transmit/schedule.rs:17-18; server/src/transmit/service.rs:400-404 fn audio_delay_ms (500/300)
- WstxTransmitControl::StartWindow::{latestStartPct=75} | schedule.rs:23 `period_ms * 3 / 4`

### WIRE (8)
- WstxModeProcessing::FreeTextFields::{'type'="free_text"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant FreeText
- WstxModeProcessing::TelemetryFields::{'type'="telemetry"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant Telemetry
- WstxModeProcessing::StandardFields::{'type'="standard"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant Standard
- WstxModeProcessing::RttyFields::{'type'="rtty"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant Rtty
- WstxModeProcessing::DxpeditionFields::{'type'="dxpedition"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant Dxpedition
- WstxModeProcessing::FieldDayFields::{'type'="field_day"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant FieldDay
- WstxModeProcessing::NonstandardFields::{'type'="nonstandard"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant Nonstandard
- WstxModeProcessing::VhfFields::{'type'="vhf"} | server/src/decoder/payload.rs:65 #[serde(tag = "type", rename_all = "snake_case")] enum Fields variant Vhf

### DEFAULT (35)
- WstxBrowserClientPart::FrontendConfig::{theme=Theme::dark} | client/recording.js:1333 dataset.theme='dark'; client/contact.js:1120 themeSettings ..:'dark'
- WstxBrowserClientPart::FrontendConfig::{themeSwitch=ThemeSwitch::manual} | client/contact.js:1120 mode ..:'manual'
- WstxBrowserClientPart::FrontendConfig::{display=DisplayProfile::detail} | client/recording.js:178 defaultDisplayProfile=()=>'detail'
- WstxBrowserClientPart::FrontendConfig::{sensitivityDb=0} | client/recording.js:136 slider value="0"; :190 sensitivity=0
- WstxBrowserClientPart::FrontendConfig::{rangeDb=50} | client/recording.js:136 value="50"; :190 displayRange=50
- WstxBrowserClientPart::FrontendConfig::{speed=1.0} | client/recording.js:136 value="1"; :190 speed=1
- WstxBrowserClientPart::FrontendConfig::{flatten=false} | client/recording.js:190 flatten=false
- WstxBrowserClientPart::FrontendConfig::{spectrumLine=false} | client/recording.js:190 spectrumLine=false
- WstxBrowserClientPart::FrontendConfig::{sortField=SortField::'value'} | client/recording.js:538 activitySortField='value'
- WstxBrowserClientPart::FrontendConfig::{alertSound=false, alertNotify=false} | client/contact.js:1471 alertPrefs {sound:false, notify:false}
- WstxAudioControl::AudioConfig::{inputDevice=null, outputDevice=null} | server/src/profile.rs:338-340 Document::defaults audio None
- WstxHearing::SpotsConfig::{enabled=true} | server/src/operating/qso/pskr.rs:666-670 `((true, true), ..)` when no file
- WstxHearing::SpotsConfig::{'use'=true} | pskr.rs:630,666-670 (true)
- WstxProfileAccess::Endpoint::{'bind'="127.0.0.1:8080"} | profile.rs:333 bind: "127.0.0.1:8080"; tests/profiles.test.cjs:46 reads Endpoint::'bind'
- WstxProfileAccess::Endpoint::{origin=null} | profile.rs:334 origin: None; profiles.test.cjs:46 reads it
- WstxProfileAccess::ProfileConfig::{displayName="No radio"} | profile.rs:330 display_name: "New station"; profiles.test.cjs:46 reads Settings::display_name (old name) | **MISMATCH: model "No radio", code "New station" (old model had "New station")**
- WstxProfileAccess::ProfileConfig::{connectionType=ConnectionType::'standard'} | profile.rs:337 connection_type: "standard"
- WstxProfileAccess::ShackConfig::{callsign="", locator=""} | profile.rs:331-332 String::new() (in profile.json; code has no shack document)
- WstxProfileAccess::ProfileDocument::{schemaVersion=1} | profile.rs:327 schema_version: 1 (+ revision: 0)
- WstxQsoControl::QsoConfig::{autoSeq=true} | server/src/contact.rs:690 auto_seq: true
- WstxQsoControl::QsoConfig::{callFirst=true} | contact.rs:692 call_first: true
- WstxQsoControl::QsoConfig::{repetitionLimit=6} | server/src/transmit/service.rs:458 tx_calls: 6 (transmit, not saved) | **held by another part, not persisted (archive verdict)**
- WstxQsoControl::QsoConfig::{activity=Activity::none} | contact.rs:701 activity: Activity::None
- WstxQsoControl::QsoConfig::{rxHz=1500, txHz=1500} | contact.rs:694-695 rx_hz/tx_hz 1500
- WstxQsoControl::SelectRow::{directiveConfirmed=false} | server/src/contact_http.rs:1240-1245 optional; :1395 `body["directive_confirmed"] != true`
- WstxQsoControl::Reply::{directiveConfirmed=false} | contact_http.rs:1243,1395 (absent = false)
- WstxRadioControl::ControlSelection::{mode=ControlMode::disabled, ptt=PttMode::disabled} | profile.rs:341-344 mode/ptt "disabled"
- WstxRadioControl::RadioRecords::{keyingConfirmed=false} | server/src/radio_setup.rs:386-393 is_some_and(..) (absent = false)
- WstxReceiveControl::ReceiveConfig::{windowDump=false} | server/src/receive/receive_diagnostics.rs:42 window_dump: false
- WstxTransmitControl::TransmitConfig::{tuneSeconds=90} | transmit/service.rs:459 tune_seconds: 90 (not saved) | **not persisted (archive verdict)**

### DEFAULT? (1)
- WstxBrowserClientPart::FrontendConfig::{sortDescending=false} | client/recording.js:538 activitySortDirection='desc' (value order ignores the direction, :636; aria shows descending) | **reads opposite: code desc, model false**

### CSS (3)
- WstxQsoPane::PaneLayout::{qsoRows=12} | client/recording.css:496 calc(13 * var(--ct-row)) (header + 12); test ui-operating.test.cjs:4987
- WstxQsoPane::PaneLayout::{narrowQsoRows=6} | client/recording.css:531 calc(7 * var(--ct-row)) inside @container (max-width:48em)
- WstxQsoPane::PaneLayout::{callingRows=5} | client/recording.css:497,532 calc(6 * var(--ct-row)) (header + 5)

### CONST+TEST-READ (1)
- WstxRecordingTransfer::RecordingLimits::{fileBytes=3145728} | FILE_LIMIT = 3_145_728 recording.rs:36; read by recording_tests.rs:1247, recording.test.cjs:143, recording-fixtures.test.cjs:40

### CONST+TEST-READ* (2)
- WstxProfileAccess::ProfileLimits::{profileFileMaxBytes=16384} | MAX_FILE = 16_384 server/src/profile.rs:15; tests/profiles.test.cjs:2021 reads WstxProfiles::profileFileMaxBytes (old)
- WstxProfileAccess::ProfileLimits::{profileHttpMaxBytes=8192} | MAX_RESPONSE = 8192 profile.rs:16; tests/profiles.test.cjs:1963,2253 reads WstxProfiles::profileHttpMaxBytes (old)

### INLINE+TEST-READ (4)
- WstxRecordingTransfer::RecordingLimits::{rateHz=12000} | server/src/recording.rs:122,166 `12000`; read by recording_tests.rs:1177, tests/recording.test.cjs:260, tests/profile/recording-fixtures.test.cjs:40 (same name in rebuilt model)
- WstxRecordingTransfer::RecordingLimits::{importMaxFrames=1440000} | recording.rs:146 `frames > 1_440_000`; read by recording_tests.rs:1178, recording.test.cjs:268
- WstxRecordingTransfer::RecordingLimits::{importMaxRiffChunks=64} | recording.rs:98 `chunks > 64`; read by recording_tests.rs:1248
- WstxRecordingTransfer::RecordingLimits::{rawChunkBytes=2048} | server/src/recording_http.rs:197 `2048`; read by tests/recording.test.cjs:143

### INLINE+TEST-READ* (4)
- WstxDecode::DecodeQuality::{ft8SnrFloorDb=-25, snrCeilingDb=60} | server/src/modes/decoder/snr.rs:162 `db.clamp(-25., 60.)` (also WEAK_SNR_DB = -25. decoder/search.rs:94); read by decoder_signal.rs:264,268 as WstxModemDecode::DecodeQuality (old)
- WstxDecode::DecodeQuality::{ft4SnrFloorDb=-21} | server/src/modes/decoder/coarse_ft4.rs:167,169 `db.clamp(-21., 60.)`; read by decoder_signal.rs:266 (old package)
- WstxDecode::DecodeBudgets::{candidateCap=256} | search.rs:309, synchronization.rs:372, physical_ft4.rs:59 `== 256`; read by physical_ft4_test.rs:37 (WstxModemDecode, old)

### TEST-READ* (20)
- WstxDecode::DecodeQuality::{strongDecodedPct=90, weakDecodedPct=50, overlapDecodedPct=90, oneSpacingStrongDecodedPct=90, oneSpacingWeakDecodedPct=50} | decoder_signal.rs:345-370 reads counts WstxModemDecode::DecodeQuality::{strong,weak,overlap,oneSpacingStrong,oneSpacingWeak}DecodedMin + signalsPerLevel/overlapPairs (old model; absent from rebuilt); fixtures/decoder/quality-cases.json minimum_exact 36/40, 20/40, 18/20, 18/20, 10/20 | **form: model share (%), test reads counts by old names**
- WstxDecode::DecodeQuality::{ft8StartToleranceFrames=240, ft4StartToleranceFrames=144, ft8FrequencyToleranceHz=1, ft4FrequencyToleranceHz=3, jt9SnrToleranceDb=1, strongAwgnSnrToleranceDb=3} | server/tests/decoder_signal.rs:40-57,264-313,764 via model_value("WstxModemDecode::DecodeQuality::<same feature>") (old package; rebuilt: WstxDecode)
- WstxDecode::DecodeBudgets::{ft8WindowMaxSeconds=5, ft4WindowMaxSeconds=3, recordingMaxSeconds=40, coldStartMaxSeconds=2, fourProfileRuntimeFactor=2, workerMemoryMaxMiB=64, checkpointMaxMs=50, releaseMaxMs=250} | server/tests/decoder_signal.rs:62 budget("..") -> WstxModemDecode::DecodeBudgets (old package); releaseMaxMs also receive_http_tests.rs:1010
- WstxDecode::DecodeBudgets::{processDeltaMaxMiB=96} | server/src/receive_http_tests.rs:16,1020 WstxModemDecode::DecodeBudgets (old package)

### TEST-INLINE (13)
- WstxCapture::CaptureStream::{passbandHighHz=3500, passbandRippleDb=0.1, stopbandLowHz=5500} | server/tests/audio_contract.rs:34-47, 433-444 (3500, 0.1 dB, 5500); product: FILTER_TAPS=257 only
- WstxCapture::CaptureStream::{stopbandDb=60} | server/tests/audio_contract.rs:49,446 `gain <= 0.001` (= -60 dB, written as amplitude)
- WstxDecode::Repeatability::{startToleranceFrames=1, ft8RepeatToleranceHz=0.2, ft4RepeatToleranceHz=0.5} | server/tests/decoder_signal.rs:456,459,468 (`<= 1`, `0.2`/`0.5`)
- WstxCatControl::RadioConnection::{closeMaxMs=250} | no product limit (executor withdrawal steps of 50 ms, actor.rs:359); tests assert 250 ms (server/tests/radio_control.rs, cat_lifecycle_tests.rs) | **code holds no such bound**
- WstxLiveReceive::WindowSchedule::{ft8PublishedByMs=15000} | server/src/receive_http_tests.rs:829 `published <= start + 15_000.0`
- WstxBandActivityPane::Promptness::{paintMs=300} | server/src/receive_http_tests.rs:823 `painted - published <= 300.0`; no product code (client paints on arrival)
- WstxOperatingScreen::ScreenLayout::{minWidthPx=1366, minHeightPx=768} | tests/ui-operating.test.cjs:330,363,4987 viewport 1366x768; client/recording.css comments only (layout by flex/grid)
- WstxOperatingScreen::ScreenLayout::{phoneWidthPx=360} | tests/ui-operating.test.cjs:220,240-264 width 360; no CSS literal 360

### FIXTURE (5)
- WstxDecode::DecodeQuality::{ft8StrongSnrDb=-15, ft8WeakSnrDb=-18, ft4StrongSnrDb=-10, ft4WeakSnrDb=-13, oneSpacingDifferenceDb=6} | fixtures/decoder/quality-cases.json snr2500_db -15/-18/-10/-13; group one-spacing-6db (generator independent-vector-tool/generate.py)

### NONE-UNSHOWN (1)
- WstxLiveReceive::WindowSchedule::{ft4PublishedByMs=7500} | no code, no test (archive: "nothing shows 7.5 s for FT4") | **CL-007-05 implemented without a test of the FT4 bound**

### NONE-TARGET (24)
- WstxSpotsReporting::ReceptionReports::{repeatSeconds=300, sendSeconds=120, pendingMax=2048} | no code: CL-039-28 target (values from WSJT-X PSKReporter.cpp)
- WstxBrowserClientPart::FrontendConfig::{distanceInMiles=false} | client has no miles option (no "miles" in client/); carried by CL-010-09 partial (frontend/BandActivityPane.sysml, another file)
- WstxBrowserClientPart::FrontendConfig::{callSound=AlertSound::oldPhone} | no call sound in client; CL-042-08 target (frontend/Settings.sysml, another file)
- WstxCountryFiles::CtyQuery::{sourceUrl="http://www.country-files.com/bigcty/cty.dat"} | no download in code (client/logbook.js:131 "nothing is downloaded automatically"); CL-055-06 target in backend/profile/ProfileDocument.sysml (another file)
- WstxAutoControl::AutoConfig::{forbiddenContests=false} | code keeps no acknowledgement; asks a confirmation per switch (server/src/strategy.rs:2689); CL-039-22/CL-119-05 partial in backend/operating/auto/AutoMode.sysml (another file)
- WstxHearing::SpotsConfig::{report=false, reportCollector="udp://report.pskreporter.info:4739"} | no reception reports in code; CL-039-28 target (backend/spots/SpotsReporting.sysml)
- WstxKeying::KeyRequest::{split=SplitOperation::none, shiftHz=0} | no split operation in code (archive: target); clause in another file
- WstxLogControl::CabrilloHeader::{location="", categoryOperator="", categoryTransmitter="", categoryPower="", categoryAssisted="", categoryBand="", operators="", club="", name=""} | no Cabrillo export in code; CL-010-21 target (backend/log/Logbook.sysml, another file)
- WstxQsoControl::QsoShared::{logAutomatically=true} | no such setting in code; carried by CL-085-04 target (LogConfirmRule, backend/operating/qso/StandardQso.sysml, another file)
- WstxRankingControl::RankingLimits::{wantedListMax=100} | no wanted list in code (issue 124 not built)
- WstxStationCommands::CheckSettings::{withTune=false} | no settings check in code; CL-001-01 target (backend/supervisor/SettingsCheck.sysml)
- WstxTransmitControl::TransmitConfig::{split=WstxKeying::SplitOperation::none} | no split operation in code

### NONE-ABSENT (4)
- WstxProfileAccess::ShackDocument::{schemaVersion=1, revision=0} | code has no shack.json (archive verdict: difference in the code) | **structure differs**
- WstxStationCommands::WorkingFrequencies::{region=IaruRegion::'all'} | code has no region filter (fixed table server/src/station/selection.rs:9-13) | **acts as all; no setting**
- WstxTransmitControl::TransmitConfig::{levelMode=LevelMode::automatic} | code has no level mode setting (radio_level.rs:644-656 actions set_level/manual only); carried by TxLevel clauses (CL-044-12 implemented)

### NONE-JUDGED (6)
- WstxStationLink::ThinLinkBudget::{bitsPerSecond=32000, roundTripMs=300, measurementSeconds=60, thinBytesPerSecond=3000, idleBytesPerSecond=1000, statusShownMs=2000} | no code, no test; judged by the operator from link-traffic.log (archive: operator 2026-11-09) | **no clause names ThinLinkBudget**

### NONE-SOURCE (3)
- WstxRequirements::BehaviorBaseline::{suite="WSJT-X", release="v3.3.0-beta4", sourceCommit="0f7d5928449ec747c3d1f6da1306f8c94404c3a9"} | code comments "Reference: WSJTX/wsjtx 0f7d5928..." in 7 decoder modules; tools/wsjtx_reference.py REVISION (a tool); release/suite in no code
