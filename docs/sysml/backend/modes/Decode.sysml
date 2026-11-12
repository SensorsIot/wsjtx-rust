package WstxModemDecode {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-004';
    private import WstxRequirements::'FR-018';
    private import WstxRequirements::'CL-007-01';
    private import WstxRequirements::'CL-007-02';
    private import WstxRequirements::'TC-004-004';
    private import WstxOfflineDecode::Mode;
    private import WstxOfflineDecode::ResultRecord;
    private import WstxOfflineDecode::DecodeBand;
    private import WstxOfflineDecode::'CL-007-09';
    private import WstxRecordingReceive::DecodeJob;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::DetailTests;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    doc /* The decode function of the modes part (WstxArchitecture::ModeFunctions). A window
         of canonical 12 kHz samples with its mode and a-priori context goes in; the records
         of the frames decoded in it come out. The payload, channel code and waveform are
         those of the published protocol; this package states the product's choices over
         it and its promises at the boundary. The payload function and the data the part
         shares are in WstxOfflineDecode. */

    attribute def DecodeQuality {
        doc /* The share of frames the modem decodes, per mode, and the accuracy of what it
             reports. A level is signalsPerLevel independent signals of one mode at one SNR
             on the WSJT-X 2500 Hz scale; strongDecodedMin and weakDecodedMin of them decode
             at the strong and the weak level. Of overlapPairs pairs of frames at each of two
             frequency spacings, overlapDecodedMin decode both; at one spacing with
             oneSpacingDifferenceDb between them, the stronger decodes in
             oneSpacingStrongDecodedMin pairs and the weaker in oneSpacingWeakDecodedMin.
             Of the pinned official recording of each mode, at least the official minimum
             of its messages decode. A decoded start lies within the start tolerance of the
             injected start, a decoded lowest-tone frequency within the frequency
             tolerance. A reported SNR is a whole dB, within jt9SnrToleranceDb of the
             pinned jt9 report where one exists, at least the floor of its mode and at most
             snrCeilingDb. For an isolated signal of the strong level in white Gaussian
             noise, it lies within strongAwgnSnrToleranceDb of the injected SNR. Carriers
             decode at any lowest-tone offset within DecodeBand, not only at multiples of
             6.25 Hz. */
        attribute signalsPerLevel : Integer = 40;
        attribute strongDecodedMin : Integer = 36;
        attribute weakDecodedMin : Integer = 20;
        attribute ft8StrongSnrDb : Integer = -15;
        attribute ft8WeakSnrDb : Integer = -18;
        attribute ft4StrongSnrDb : Integer = -10;
        attribute ft4WeakSnrDb : Integer = -13;
        attribute overlapPairs : Integer = 20;
        attribute overlapDecodedMin : Integer = 18;
        attribute oneSpacingDifferenceDb : Integer = 6;
        attribute oneSpacingStrongDecodedMin : Integer = 18;
        attribute oneSpacingWeakDecodedMin : Integer = 10;
        attribute ft8OfficialMessages : Integer = 14;
        attribute ft8OfficialDecodedMin : Integer = 12;
        attribute ft4OfficialMessages : Integer = 19;
        attribute ft4OfficialDecodedMin : Integer = 16;
        attribute ft8StartToleranceFrames : Integer = 240;
        attribute ft4StartToleranceFrames : Integer = 144;
        attribute ft8FrequencyToleranceHz : Integer = 1;
        attribute ft4FrequencyToleranceHz : Integer = 3;
        attribute jt9SnrToleranceDb : Integer = 1;
        attribute strongAwgnSnrToleranceDb : Integer = 3;
        attribute ft8SnrFloorDb : Integer = -25;
        attribute ft4SnrFloorDb : Integer = -21;
        attribute snrCeilingDb : Integer = 60;
    }

    attribute def DecodeBudgets {
        doc /* The resources of decoding, measured on the reference PC HB9BLA (AMD Ryzen 9
             3900X, 32 GB, Windows 11) with one CPU worker per station. A 15 s FT8 window
             decodes in at most ft8WindowMaxSeconds, a 7.5 s FT4 window in at most
             ft4WindowMaxSeconds and a 120 s recording in at most recordingMaxSeconds; a
             cold start adds at most coldStartMaxSeconds. Four profiles decoding at once
             take at most fourProfileRuntimeFactor times the single runtime. A worker uses
             at most workerMemoryMaxMiB, and the station process grows by at most
             processDeltaMaxMiB of private commit over idle. Decoding reaches a
             cancellation checkpoint at least every checkpointMaxMs and releases its worker
             at most releaseMaxMs after Stop. At most candidateCap qualified candidates are
             searched in a window. */
        attribute ft8WindowMaxSeconds : Integer = 5;
        attribute ft4WindowMaxSeconds : Integer = 3;
        attribute recordingMaxSeconds : Integer = 40;
        attribute coldStartMaxSeconds : Integer = 2;
        attribute fourProfileRuntimeFactor : Integer = 2;
        attribute workerMemoryMaxMiB : Integer = 64;
        attribute processDeltaMaxMiB : Integer = 96;
        attribute checkpointMaxMs : Integer = 50;
        attribute releaseMaxMs : Integer = 250;
        attribute candidateCap : Integer = 256;
    }

    item def APrioriContext {
        doc /* The station's a-priori context of one decode window, set before the window,
             so that the records of a window depend only on the window and this context.
             myCall and dxCall are the call bits of the standard message
             "MyCall DxCall RRR" packed from the profile callsign and the current contact's
             DX call; without an exact round trip neither is set, and without a DX call only
             myCall is. qsoProgress is WSJT-X's nQSOProgress of the current contact state
             (WstxContact): calling, idle and cancelled 0, replying 1, report 2,
             roger_report 3, rogers 4, signoff and completed 5. rxHz and txHz are the
             contact's Rx and Tx audio frequencies. cqOnly holds from start until a contact
             tick sees the station transmitting, tuning or with Enable Tx on, and again
             cqOnlyAfterSeconds after the last such tick. A window without a station has no
             myCall and no dxCall. */
        @FollowsSource {
            reference = "WSJT-X 3.3.0-beta5 ft8apset, nQSOProgress, m_dateTimeLastTX";
        }
        @DiffersFromSource {
            what = "A compound MyCall, which ft8apset packs hashed, gives no myCall.";
        }
        attribute myCall : Integer[0..29];
        attribute dxCall : Integer[0..29];
        attribute qsoProgress : Integer;
        attribute rxHz : Real;
        attribute txHz : Real;
        attribute cqOnly : Boolean;
        attribute cqOnlyAfterSeconds : Integer = 300;
    }

    action def AdvanceDecode {
        in block : WstxRecordingReceive::SampleBlock;
        in job : DecodeJob;
        in context : APrioriContext;
        out records : ResultRecord[0..2048];
        @ImplementedIn {
            module = "server/src/decoder/mod.rs; server/src/decoder/apriori.rs; server/src/decoder/baseband.rs; server/src/decoder/bitmetrics.rs; server/src/decoder/channel.rs; server/src/decoder/coarse_ft4.rs; server/src/decoder/fit.rs; server/src/decoder/history.rs; server/src/decoder/parallel.rs; server/src/decoder/physical_ft4.rs; server/src/decoder/physical_sync.rs; server/src/decoder/search.rs; server/src/decoder/snr.rs; server/src/decoder/subtraction.rs; server/src/decoder/synchronization.rs; server/src/decoder/waveform.rs";
        }
        @DetailTests {
            tests = "server/src/decoder/baseband_test.rs; server/src/decoder/bitmetrics_test.rs; server/src/decoder/coarse_ft4_test.rs; server/src/decoder/physical_ft4_test.rs; server/src/decoder/subtraction_test.rs; server/src/decoder/channel_resource_test.rs; server/src/decoder/snr_test.rs; server/src/decoder/search_test.rs; server/src/decoder/apriori_test.rs; server/tests/decoder_live.rs";
            covers = "band limit, baseband and symbol transforms, bit metrics and their "
                + "a-priori fixed bits, coarse FT4 search, qualified-support geometry, "
                + "subtraction kernels, channel decoding, SNR measurement, ranked grid "
                + "refinement and the modem history; the contract tests of these files are "
                + "those bound to TC-004-001..003";
        }
        @FollowsSource {
            reference = "QEX FT4/FT8 sections 2 to 5 and appendix A; WSJT-X 3.3.0-beta5 sync8, "
                + "getcandidates4, ft8b, ft4_decode, decode174_91, osd174_91";
        }
        doc /* The shared receive owner assembles the window from canonical sample blocks: up
             to 30 s for FT8 and 15 s for FT4. The modem reads no device, file, network or
             clock. */
        doc /* The modem decodes no SuperFox or legacy 2019 FT4 frame. It decodes FT8 with its
             own decoder only and does not run WSJT-X's optional FT8var decoder. */
        @DiffersFromSource {
            what = "SuperFox: WSJT-X 3.3.0-beta5 decodes SuperFox frames in Hound mode; the modem "
                + "does not.";
        }
        @DiffersFromSource {
            what = "FT8var: WSJT-X 3.3.0-beta5 runs lib/ft8var (my_ft8var%decodevar in "
                + "ft8_engine_kernel.f90) when the option Use multithreaded FT8 decoder is on "
                + "(lmultift8, MultithreadedFT8decoder, default off, mainwindow_settings.cpp); "
                + "the modem runs neither that decoder nor its hint passes.";
        }
        doc /* A record larger than the modem record cap that
             WstxRecordingReceive::LiveTimedResultRecord states is not published; the window
             ends with decode_limit (WstxRecordingReceive::ErrorCode), keeping the records
             already published. */
        doc /* A frame that starts before the window or runs past its end is subtracted and
             never published, so that a weaker frame under it decodes; a frame that starts
             at most half a symbol before the window is published at start 0. */
        doc /* A payload repeated within half a symbol of an earlier one of the window is
             published once; a copy on a carrier more than 50 Hz away is also subtracted. */
        doc /* A word that fails at its fine point is tried once more at the nearby data point
             of greatest energy. */
        @DiffersFromSource { what = "The retry at the data point: ft8b has no such step."; }
        doc /* An FT8 candidate that yields no word and that a frame subtracted in the same
             pass overlaps (carriers within 50 Hz, starts less than one frame apart) is
             qualified again on the next pass. */
        doc /* The weak-word guard rejects an FT8 word whose final point has at most 10 of 21
             Costas hits and whose measured SNR is below -25 dB; the rejected word is
             neither published nor subtracted. */
        @FollowsSource { reference = "WSJT-X 3.3.0-beta5 ft8b, nsync<=10 and xsnr<-25"; }
        @DiffersFromSource {
            what = "The weak-word guard: ft8b subtracts the rejected word, the modem does not.";
        }
        doc /* Every published word passes the parity check and the CRC, and an ordered
             statistics word with zero disagreements is accepted. */
        @DiffersFromSource {
            what = "decode174_91 checks only the CRC and requires more than zero OSD "
                + "disagreements.";
        }
        doc /* The window's qualified candidates count against DecodeBudgets::candidateCap;
             the next one ends the window with search_limited, keeping the records already
             published. */
    }

    action def MeasureFrame {
        in block : WstxRecordingReceive::SampleBlock;
        out record : ResultRecord;
        doc /* The start is the canonical frame of the first ramp or sync symbol, never a
             native or UTC time; the frequency is the audio frequency of the lowest tone. */
        doc /* The SNR is on the WSJT-X 2500 Hz scale as WSJT-X first reports it, rounded to a
             whole dB, at least the floor of its mode (DecodeQuality) and at most
             DecodeQuality::snrCeilingDb; it is null without a baseline. */
        @FollowsSource { reference = "WSJT-X 3.3.0-beta5 ft8b xsnr2 and ft4_decode"; }
    }

    action def APrioriHypotheses {
        in context : APrioriContext;
        doc /* With the station's a-priori context, a candidate whose unassisted decoding
             failed is decoded again under WSJT-X's a-priori types of the QSO state, within
             50 Hz of the Rx frequency (FT8 also of the Tx frequency); a type needing MyCall
             or DxCall is skipped without it. A word found so is published only with a
             payload that decodes, at WSJT-X's confidence qual >= 0.17 (except FT8 type 1),
             and carries its type as a_priori. */
        @FollowsSource {
            reference = "WSJT-X 3.3.0-beta5 ft8b and ft4_decode with ncontest=0: naptypes, "
                + "lapcqonly";
        }
        @DiffersFromSource {
            what = "A low-confidence a-priori word, which WSJT-X publishes marked '?', is not "
                + "published.";
        }
        @DiffersFromSource {
            what = "The a7 and a8 passes: WSJT-X 3.3.0-beta5 ft8_decode.f90 runs, after the last "
                + "FT8 pass of a period with AP on, ft8_a7d over the messages decoded in the "
                + "previous period (iaptype 7) and ft8_a8d at the Rx frequency with the DX "
                + "call and grid (iaptype 8); the modem tries only the a-priori types 1 to 6.";
        }
    }

    action advanceDecode : AdvanceDecode;
    action measureFrame : MeasureFrame;
    action aprioriHypotheses : APrioriHypotheses;
    satisfy 'CL-007-03' by measureFrame;
    satisfy 'CL-007-04' by advanceDecode;
    satisfy 'CL-007-06' by measureFrame;
    satisfy 'CL-007-07' by advanceDecode;
    satisfy 'CL-007-08' by advanceDecode;
    satisfy 'CL-007-10' by aprioriHypotheses;
    dependency calculationOwner from advanceDecode
        to WstxArchitecture::physicalStation::backend::stations::modes;
    dependency measurementOwner from measureFrame
        to WstxArchitecture::physicalStation::backend::stations::modes;
    dependency aprioriOwner from aprioriHypotheses
        to WstxArchitecture::physicalStation::backend::stations::modes;

    requirement 'CL-007-03' {
        doc /* The modem MUST decode FT8 and FT4 frames as the published protocol defines their
             payload, channel code and waveform. */
        @FollowsSource {
            reference = "QEX FT4/FT8 sections 2 to 5 and appendix A; WSJT-X 3.3.0-beta5 for the "
                + "current message families and the section (86) and RTTY exchange (171) tables";
        }
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_007_03_to_FR_003 from 'CL-007-03' to 'FR-003';
    dependency CL_007_03_to_FR_004 from 'CL-007-03' to 'FR-004';
    dependency CL_007_03_to_FR_018 from 'CL-007-03' to 'FR-018';
    requirement 'CL-007-04' {
        doc /* Decoding MUST run on the CPU within DecodeBudgets and MUST end a window whose
             qualified candidates exceed the candidate cap with an explicit search-limited
             result. */
        @Status { build = ImplementationState::partial; }
    }
    dependency CL_007_04_to_FR_003 from 'CL-007-04' to 'FR-003';
    dependency CL_007_04_to_FR_004 from 'CL-007-04' to 'FR-004';
    requirement 'CL-007-06' {
        doc /* The modem MUST decode at least the share of frames that DecodeQuality states for
             each mode, within DecodeBand, at the stated start, frequency and SNR accuracy. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_007_06_to_FR_003 from 'CL-007-06' to 'FR-003';
    dependency CL_007_06_to_FR_004 from 'CL-007-06' to 'FR-004';
    dependency CL_007_06_to_FR_018 from 'CL-007-06' to 'FR-018';
    requirement 'CL-007-07' {
        doc /* The modem MUST publish no frame from noise, silence, a wrong-mode signal or a
             word whose CRC fails, and never the all-zero codeword. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_007_07_to_FR_003 from 'CL-007-07' to 'FR-003';
    dependency CL_007_07_to_FR_004 from 'CL-007-07' to 'FR-004';
    requirement 'CL-007-08' {
        doc /* The modem MUST publish the same records in the same order for the same window,
             mode and a-priori context: the same payloads, each start within 1 frame and each
             frequency within 0.2 Hz (FT8) or 0.5 Hz (FT4) of the other run. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_007_08_to_FR_003 from 'CL-007-08' to 'FR-003';
    dependency CL_007_08_to_FR_004 from 'CL-007-08' to 'FR-004';
    requirement 'CL-007-10' {
        doc /* With the station's a-priori context, the modem MUST try WSJT-X's a-priori
             hypotheses for a candidate whose unassisted decoding failed, and MUST publish an
             a-priori word only with a decoded payload at WSJT-X's confidence, marked with
             its type. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_007_10_to_FR_003 from 'CL-007-10' to 'FR-003';
    dependency CL_007_10_to_FR_004 from 'CL-007-10' to 'FR-004';

    verification 'TC-004-001' {
        doc /* TC-004-001 — Offline FT4
             Setup: independent FT4 waveforms from a separate encoder, the pinned modern FT4
             recording with its jt9 report, and the SIM18 FT4 fixtures; the station modem
             offline. Every test bound to this case selects FT4 and is named path::test; at
             least one loads an independent FT4 fixture. Mode-independent evidence is traced
             by its Proves tags, not bound here.
             (a) Every supported family and field boundary decodes to the injected text;
                 start within DecodeQuality::ft4StartToleranceFrames, frequency within
                 ft4FrequencyToleranceHz.
             (b) The quality counts of DecodeQuality for FT4; on each strong isolated signal
                 an SNR within strongAwgnSnrToleranceDb of the injected one.
             (c) At least ft4OfficialDecodedMin of the ft4OfficialMessages official
                 messages; every SNR a whole dB, within jt9SnrToleranceDb of jt9 and at
                 least ft4SnrFloorDb.
             (d) A weak CQ decodes through type 1 without context; a weak
                 "HB9BLA K1ABC RR73" decodes through type 6 only with MyCall HB9BLA and
                 DxCall K1ABC.
             (e) SIM18-FT4-CLEAN decodes exactly "CQ K1ABC FN42". Open: no bound test
                 shows (e).
             Oracle: the injected payloads; jt9 is a lower bound, not exhaustive truth.
             2 — Isolated automated tests; Windows PC, offline fixtures. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'CL-007-06';
            verify 'CL-007-10';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::official_modern_recording_baselines; server/src/decoder/search_test.rs::ft4_a_priori_recovers_weak_cq_and_qso_words";
        }
    }
    verification 'TC-004-002' {
        doc /* TC-004-002 — Offline FT8
             Setup: independent FT8 waveforms from a separate encoder, the pinned official
             FT8 recording with its jt9 report, the recorded corpus with its jt9-deep
             reference, and the SIM18 FT8 fixtures; the station modem offline. Every test
             bound to this case selects FT8 and is named path::test; at least one loads an
             independent FT8 fixture. Mode-independent evidence is traced by its Proves
             tags, not bound here.
             (a) Carriers at exactly both ends of DecodeBand
                 (fixtures/decoder/quality-cases.json) and at 200.5, 1000.3 and 3499 Hz
                 decode; start within
                 DecodeQuality::ft8StartToleranceFrames, frequency within
                 ft8FrequencyToleranceHz.
             (b) The quality counts of DecodeQuality for FT8; on each strong isolated signal
                 an SNR within strongAwgnSnrToleranceDb of the injected one; a second station
                 80 dB below a stronger one keeps both messages. Open: no bound test shows
                 the 80 dB station.
             (c) At least ft8OfficialDecodedMin of the ft8OfficialMessages official
                 messages; SNR within jt9SnrToleranceDb of jt9 and at least ft8SnrFloorDb.
             (d) At least the pinned count of jt9-deep's 409 decodes.
             (e) Partial frames before or past the window are subtracted, never published,
                 and the weak frame under them decodes; a frame starting at most 960 frames
                 before the window publishes at start 0, an earlier one does not.
             (f) One word on a carrier more than 50 Hz away publishes once, and the weak
                 frame under its copy decodes.
             (g) CRC-valid unsupported and invalid payloads are retained with status
                 unsupported or invalid_payload (WstxOfflineDecode::FrameStatus), exact
                 payload77, and null text and fields.
             (h) Weak "HB9BLA K1ABC FN42" (report) and "HB9BLA K1ABC RR73" (rogers) decode
                 only with the right calls, state and Rx/Tx, with a_priori 3 and 6; a wrong
                 DxCall in every state and mode never yields another word, and noise none.
             (i) Through the live worker, the SNR of a UTC-aligned period equals the file
                 decode of the same audio.
             (j) SIM18-FT8-CLEAN decodes exactly. Open: no bound test shows (j).
             (k) The weak-word guard rejects an FT8 word with at most 10 Costas hits and a
                 measured SNR below -25 dB; it rejects no word with 11 hits or with an SNR of
                 -25 dB or none, and no FT4 word.
             (l) A weak word that fails at its fine point decodes at the nearby data point.
             Oracle: the injected payloads; jt9 is a lower bound, not exhaustive truth.
             2 — Isolated automated tests; Windows PC, offline fixtures. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'CL-007-06';
            verify 'CL-007-09';
            verify 'CL-007-10';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::official_modern_recording_baselines; server/src/recording_tests.rs::live_ft8_snr_measures_from_the_utc_period_start; server/tests/decoder_signal.rs::recorded_corpus_reaches_jt9_deep_decodes; server/src/decoder/search_test.rs::partial_frame_interferer_is_subtracted_not_published; server/src/decoder/search_test.rs::frame_past_the_window_end_is_subtracted_not_published; server/src/decoder/search_test.rs::half_symbol_publication_boundary; server/src/decoder/search_test.rs::duplicate_on_a_distant_carrier_is_subtracted_and_published_once; server/src/decoder/search_test.rs::weak_word_guard_boundaries; server/src/decoder/search_test.rs::failed_fine_point_retries_at_the_data_point; server/src/decoder/apriori_test.rs::a_priori_types_follow_the_wsjtx_state_table; server/src/decoder/bitmetrics_test.rs::a_priori_words_need_a_decoded_payload_and_confidence; server/src/decoder/search_test.rs::weak_qso_words_decode_only_with_the_right_calls; server/src/decoder/search_test.rs::wrong_dx_call_never_yields_a_false_word; server/tests/audio_receive.rs::live_native_provider_decodes_independent_ft8_callsign";
        }
    }
    verification 'TC-004-003' {
        doc /* TC-004-003 — Invalid input, rejection and resources
             Setup: noise, silence, wrong-mode and bad-CRC inputs; a release build on the
             reference PC for the budgets.
             (a) 1,000 noise windows per mode publish nothing.
             (b) Silence, and an FT8 signal decoded as FT4, publish nothing and raise no
                 search error.
             (c) A good-FEC bad-CRC word and the all-zero codeword never publish.
             (d) DecodeBudgets::candidateCap qualified candidates stay within the cap and
                 one more gives search_limited.
             (e) The runtime and memory of DecodeBudgets, with release at most
                 DecodeBudgets::releaseMaxMs after Stop.
             (f) A second run of the same window gives the same payloads in the same order,
                 each start within 1 frame and each frequency within 0.2 Hz (FT8) or 0.5 Hz
                 (FT4) of the first run.
             2 — Isolated automated tests; Windows PC with disposable recordings, no radio
             or live service. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'CL-007-07';
            verify 'CL-007-08';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::unmodulated_sources_are_not_frames; server/tests/decoder_signal.rs::physical_noise_reproduction_has_no_frame; server/tests/decoder_signal.rs::physical_wrong_mode_reproduction_has_no_frame_or_search_error; server/tests/decoder_signal.rs::release_runtime_and_overlapping_window_history; server/src/receive_http_tests.rs::resource_station_process_delta_and_owner_release; server/src/decoder/physical_ft4_test.rs::qualified_support_count_keeps_the_256_257_barrier";
        }
    }
    dependency CL_007_03_verified_by_TC_004_001 from 'CL-007-03' to 'TC-004-001';
    dependency CL_007_03_verified_by_TC_004_002 from 'CL-007-03' to 'TC-004-002';
    dependency CL_007_03_verified_by_TC_004_003 from 'CL-007-03' to 'TC-004-003';
    dependency CL_007_04_verified_by_TC_004_001 from 'CL-007-04' to 'TC-004-001';
    dependency CL_007_04_verified_by_TC_004_002 from 'CL-007-04' to 'TC-004-002';
    dependency CL_007_04_verified_by_TC_004_003 from 'CL-007-04' to 'TC-004-003';
    dependency CL_007_04_verified_by_TC_004_004 from 'CL-007-04' to 'TC-004-004';
    dependency CL_007_06_verified_by_TC_004_001 from 'CL-007-06' to 'TC-004-001';
    dependency CL_007_06_verified_by_TC_004_002 from 'CL-007-06' to 'TC-004-002';
    dependency CL_007_07_verified_by_TC_004_003 from 'CL-007-07' to 'TC-004-003';
    dependency CL_007_08_verified_by_TC_004_003 from 'CL-007-08' to 'TC-004-003';
    dependency CL_007_10_verified_by_TC_004_001 from 'CL-007-10' to 'TC-004-001';
    dependency CL_007_10_verified_by_TC_004_002 from 'CL-007-10' to 'TC-004-002';
}
