package WstxDecode {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-004';
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::DetailTests;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModesPart::ModeFunctions;
    private import WstxModeProcessing::*;

    doc /* The decode function of the modes part: a window of samples goes in, the frames
         decoded in it come out. The payload, the channel code and the waveform are those
         of the published protocol; this file states the product's choices over it. */

    requirement 'CL-007-03' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST decode the FT8 and FT4 frames of a window as the published
             protocol defines their payload, channel code and waveform (DecodeWindow). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-03'; }

    action def DecodeWindow {
        in request : ProcessingRequest;
        out frames : ProcessingResult[0..2048];
        out ended : WindowEnd;
        doc /* How a window becomes frames.
             A window shorter than one frame of its mode gives no frame.
             An FT8 frame is returned when it lies inside the window, or reaches out of
             it by at most half a symbol at either end; one that starts before the window
             is returned with the window's first sample as its start.
             An FT4 frame is returned when it lies inside the window.
             A frame that reaches further out of the window is not returned.
             A payload is returned once: a frame with the payload of an earlier one,
             starting within half a symbol of it, is not returned again, in the same
             window or, in continuous receive, in a later one.
             Each returned word passes the parity check and the CRC of the channel code.
             Every other case ends as DecodeError states. */
        @ImplementedIn {
            module = "server/src/decoder/mod.rs; server/src/decoder/search.rs; "
                + "server/src/decoder/subtraction.rs; server/src/modes/decoder/apriori.rs; "
                + "server/src/modes/decoder/baseband.rs; "
                + "server/src/modes/decoder/bitmetrics.rs; "
                + "server/src/modes/decoder/channel.rs; "
                + "server/src/modes/decoder/coarse_ft4.rs; server/src/modes/decoder/fit.rs; "
                + "server/src/modes/decoder/history.rs; "
                + "server/src/modes/decoder/parallel.rs; "
                + "server/src/modes/decoder/physical_ft4.rs; "
                + "server/src/modes/decoder/physical_sync.rs; "
                + "server/src/modes/decoder/snr.rs; "
                + "server/src/modes/decoder/synchronization.rs; "
                + "server/src/modes/decoder/waveform.rs";
        }
        @DetailTests {
            tests = "server/src/modes/decoder/baseband_test.rs; "
                + "server/src/modes/decoder/bitmetrics_test.rs; "
                + "server/src/modes/decoder/coarse_ft4_test.rs; "
                + "server/src/modes/decoder/physical_ft4_test.rs; "
                + "server/src/modes/decoder/subtraction_test.rs; "
                + "server/src/modes/decoder/channel_resource_test.rs; "
                + "server/src/modes/decoder/snr_test.rs; "
                + "server/src/modes/decoder/search_test.rs; "
                + "server/src/modes/decoder/apriori_test.rs; "
                + "server/tests/modes/decoder_live.rs";
            covers = "the band limit, the baseband and symbol transforms, the bit metrics, "
                + "the coarse FT4 search, the subtraction of decoded frames, channel "
                + "decoding, the SNR measurement, the refinement of a candidate, the retry "
                + "of a failed word, the guard against weak false words and the history "
                + "of returned frames";
        }
        @FollowsSource {
            reference = "QEX, The FT4 and FT8 Communication Protocols, sections 2 to 5 and "
                + "appendix A; WSJT-X at the behaviour baseline: sync8, getcandidates4, "
                + "ft8b, ft4_decode, decode174_91, osd174_91";
        }
        @DiffersFromSource {
            what = "SuperFox: WSJT-X decodes SuperFox frames in Hound mode; the decoder "
                + "does not.";
        }
        @DiffersFromSource {
            what = "FT8var: WSJT-X runs a second FT8 decoder when its option for a "
                + "multithreaded FT8 decoder is on; the decoder has its own decoder only.";
        }
        @DiffersFromSource {
            what = "decode174_91 checks only the CRC of a word; the decoder checks the "
                + "parity as well.";
        }
    }

    requirement 'CL-007-06' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST decode at least the share of frames of each mode, with the
             accuracy of start, frequency and SNR, that DecodeQuality states. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-06'; }

    attribute def DecodeQuality {
        doc /* The share of frames that decode, and the accuracy of what is reported.
             A level is a set of independent signals of one mode at one SNR on the
             2500 Hz scale of WSJT-X, each alone in white noise.
             A frame decodes at any frequency of its lowest tone within DecodeBand. */
        attribute strongDecodedPct : Integer = 90 {
            doc /* At least this share of the signals of the strong level decodes. */ }
        attribute weakDecodedPct : Integer = 50 {
            doc /* At least this share of the signals of the weak level decodes. */ }
        attribute ft8StrongSnrDb : Integer = -15;
        attribute ft8WeakSnrDb : Integer = -18;
        attribute ft4StrongSnrDb : Integer = -10;
        attribute ft4WeakSnrDb : Integer = -13;
        attribute overlapDecodedPct : Integer = 90 {
            doc /* Of pairs of frames that overlap in time, two tone spacings apart,
                 both frames decode in at least this share. */ }
        attribute oneSpacingDifferenceDb : Integer = 6 {
            doc /* The weaker frame of a pair one tone spacing apart is this much
                 weaker. */ }
        attribute oneSpacingStrongDecodedPct : Integer = 90 {
            doc /* Of such pairs, the stronger frame decodes in at least this share. */ }
        attribute oneSpacingWeakDecodedPct : Integer = 50 {
            doc /* Of such pairs, the weaker frame decodes in at least this share. */ }
        attribute ft8StartToleranceFrames : Integer = 240 {
            doc /* A decoded FT8 start lies within this of the true start. */ }
        attribute ft4StartToleranceFrames : Integer = 144 {
            doc /* A decoded FT4 start lies within this of the true start. */ }
        attribute ft8FrequencyToleranceHz : Integer = 1 {
            doc /* A decoded FT8 frequency lies within this of the true frequency. */ }
        attribute ft4FrequencyToleranceHz : Integer = 3 {
            doc /* A decoded FT4 frequency lies within this of the true frequency. */ }
        attribute jt9SnrToleranceDb : Integer = 1 {
            doc /* A reported SNR lies within this of the SNR that the decoder of WSJT-X
                 reports for the same frame of a sample recording. */ }
        attribute strongAwgnSnrToleranceDb : Integer = 3 {
            doc /* The reported SNR of a signal of the strong level lies within this of
                 its true SNR. */ }
        attribute ft8SnrFloorDb : Integer = -25 {
            doc /* The lowest SNR reported for an FT8 frame. */ }
        attribute ft4SnrFloorDb : Integer = -21 {
            doc /* The lowest SNR reported for an FT4 frame. */ }
        attribute snrCeilingDb : Integer = 60 {
            doc /* The highest SNR reported. */ }
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the SNR as ft8b and ft4_decode "
                + "first report it";
        }
    }

    requirement 'CL-007-07' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST return no frame from noise, from silence, from a signal of
             the other mode or from a word whose CRC fails (FalseFrames). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-07'; }

    attribute def FalseFrames {
        doc /* Inputs that hold no frame.
             A word of zeros only is not a frame.
             A window that holds no frame ends without an error. */
    }

    requirement 'CL-007-08' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST return the same frames in the same order whenever it is
             given the same request (Repeatability). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-08'; }

    attribute def Repeatability {
        doc /* What "the same frames" means for two runs of one request: the same
             payloads in the same order, each start and each frequency within the
             tolerance below. */
        attribute startToleranceFrames : Integer = 1;
        attribute ft8RepeatToleranceHz : Real = 0.2;
        attribute ft4RepeatToleranceHz : Real = 0.5;
    }

    requirement 'CL-007-04' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST decode on the processor within the time and memory of
             DecodeBudgets, and end a window that exceeds a limit with the error that
             names the limit. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-04'; }

    attribute def DecodeBudgets {
        doc /* The resources of decoding. The times and the memory hold on the reference
             PC (AMD Ryzen 9 3900X, 32 GB, Windows 11) with one decode thread for each
             station. */
        attribute ft8WindowMaxSeconds : Integer = 5 {
            doc /* A window of 15 s of FT8 decodes within this. */ }
        attribute ft4WindowMaxSeconds : Integer = 3 {
            doc /* A window of 7.5 s of FT4 decodes within this. */ }
        attribute recordingMaxSeconds : Integer = 40 {
            doc /* A recording of 120 s decodes within this. */ }
        attribute coldStartMaxSeconds : Integer = 2 {
            doc /* The first decode after a start takes at most this much longer. */ }
        attribute fourProfileRuntimeFactor : Integer = 2 {
            doc /* Four stations that decode at once take at most this many times the
                 time of one. */ }
        attribute workerMemoryMaxMiB : Integer = 64 {
            doc /* One decode uses at most this much memory. */ }
        attribute processDeltaMaxMiB : Integer = 96 {
            doc /* The station process grows by at most this much over idle while it
                 decodes. */ }
        attribute checkpointMaxMs : Integer = 50 {
            doc /* The decoder looks for a Cancel at least this often. */ }
        attribute releaseMaxMs : Integer = 250 {
            doc /* A cancelled request ends at most this long after its Cancel. */ }
        attribute candidateCap : Integer = 256 {
            doc /* The candidates searched in one window. One more ends the window with
                 searchLimited. */ }
        attribute recordCap : Integer = 2048 {
            doc /* The frames one recording, or one stretch of continuous receive that
                 the decoder still holds for comparison, may return. One more ends the
                 window with decodeLimit. */ }
        attribute recordMaxBytes : Integer = 1024 {
            doc /* The size of one frame written as JSON. A larger one is not returned
                 and ends the window with decodeLimit. */ }
    }

    requirement 'CL-057-02' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST leave one logical processor to the other functions of the
             station and return the same frames in the same order on any number of
             threads (DecodeThreads). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-057-02'; }

    attribute def DecodeThreads {
        doc /* The threads of one decode.
             A decode uses as many threads as the PC has logical processors, less one,
             and at least one.
             The frames and their order are those of a decode on one thread. */
        attribute sparedProcessors : Integer = 1;
    }

    requirement 'CL-007-10' {
        subject modes : ModeFunctions;
        doc /* The decoder MUST try the messages the station expects, by its context, on
             a candidate that did not decode without help, and return such a frame only
             with a valid payload and enough confidence (APrioriHypotheses). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-10'; }

    action def APrioriHypotheses {
        in context : APrioriContext;
        out frames : ProcessingResult[0..*];
        doc /* The a-priori types of WSJT-X, tried by the progress of the contact.
             With cqOnly set, only the CQ type is tried.
             A type that names my call is tried only with a call that packs exactly as
             the call of a standard message; a type that names the DX call, only with
             such a DX call as well.
             A type that names the DX call is tried within nearHz of the receive
             frequency and, for FT8, of the transmit frequency.
             A frame found so is returned only when its payload has the status decoded
             and its confidence is at least minConfidence; an FT8 frame of the CQ type
             needs no confidence.
             The frame carries its type in aPriori. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: ft8b, ft4_decode and ft8apset "
                + "with ncontest=0: naptypes, lapcqonly, napwid, qual";
        }
        @DiffersFromSource {
            what = "WSJT-X shows an a-priori word of low confidence with a question mark; "
                + "the decoder does not return it.";
        }
        @DiffersFromSource {
            what = "WSJT-X tries two more a-priori types, 7 and 8, after the last FT8 "
                + "pass; the decoder tries the types 1 to 6.";
        }
        @DiffersFromSource {
            what = "WSJT-X packs a compound call of the station as a hash; the decoder "
                + "takes such a call as absent.";
        }
        attribute nearHz : Integer = 50;
        attribute minConfidence : Real = 0.17;
    }

    verification 'TC-004-001' {
        doc /* Decoding FT4. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-03'; verify 'CL-007-06'; verify 'CL-007-10'; }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::independent_waveforms_decode; "
                + "server/tests/decoder_signal.rs::quality_corpus; "
                + "server/tests/decoder_signal.rs::official_modern_recording_baselines; "
                + "server/src/modes/decoder/search_test.rs::"
                + "ft4_a_priori_recovers_weak_cq_and_qso_words";
        }
    }

    verification 'TC-004-002' {
        doc /* Decoding FT8. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-03'; verify 'CL-007-06'; verify 'CL-007-10'; }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::independent_waveforms_decode; "
                + "server/tests/decoder_signal.rs::quality_corpus; "
                + "server/tests/decoder_signal.rs::official_modern_recording_baselines; "
                + "server/tests/decoder_signal.rs::recorded_corpus_reaches_jt9_deep_decodes; "
                + "server/src/modes/decoder/search_test.rs::"
                + "partial_frame_interferer_is_subtracted_not_published; "
                + "server/src/modes/decoder/search_test.rs::"
                + "frame_past_the_window_end_is_subtracted_not_published; "
                + "server/src/modes/decoder/search_test.rs::half_symbol_publication_boundary; "
                + "server/src/modes/decoder/search_test.rs::"
                + "duplicate_on_a_distant_carrier_is_subtracted_and_published_once; "
                + "server/src/modes/decoder/search_test.rs::"
                + "weak_qso_words_decode_only_with_the_right_calls; "
                + "server/src/modes/decoder/search_test.rs::"
                + "wrong_dx_call_never_yields_a_false_word";
        }
    }

    verification 'TC-004-003' {
        doc /* No false frame, the limits and the resources. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-04'; verify 'CL-007-07'; verify 'CL-007-08'; }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::quality_corpus; "
                + "server/tests/decoder_signal.rs::unmodulated_sources_are_not_frames; "
                + "server/tests/decoder_signal.rs::physical_noise_reproduction_has_no_frame; "
                + "server/tests/decoder_signal.rs::"
                + "physical_wrong_mode_reproduction_has_no_frame_or_search_error; "
                + "server/tests/decoder_signal.rs::"
                + "release_runtime_and_overlapping_window_history; "
                + "server/tests/decoder_signal.rs::planned_scalar_and_gain_invariance; "
                + "server/src/receive_http_tests.rs::"
                + "resource_station_process_delta_and_owner_release; "
                + "server/src/modes/decoder/physical_ft4_test.rs::"
                + "qualified_support_count_keeps_the_256_257_barrier";
        }
    }

    verification 'TC-057-002' {
        doc /* The same frames on any number of threads. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-057-02'; }
        @TestedBy {
            test = "server/tests/decoder_signal.rs::"
                + "busy_period_decode_is_identical_and_faster_on_more_threads; "
                + "server/src/modes/decoder/parallel.rs";
        }
    }
}
