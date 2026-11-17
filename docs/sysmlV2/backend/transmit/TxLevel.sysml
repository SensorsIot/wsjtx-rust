package WstxTxLevel {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-008';
    private import WstxTransmitPart::TransmitService;
    private import WstxTransmitControl::*;
    private import WstxAudioStreams::PlayProgram;
    private import WstxAudioStreams::SetScale;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-044-12' {
        subject transmit : TransmitService;
        doc /* Transmit MUST play its audio at the audio drive of the station's band, set by
             the operator in manual and found with the Tune tone in automatic (TxLevel,
             LevelFinding). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-044-12'; }

    attribute def TxLevel {
        doc /* The audio drive: how far the audio of the station is turned down, in whole
             dB from levelMinDb to levelMaxDb.
             The scale of a program (PlayProgram::scale) is playbackScale times 10 to
             the power of the level divided by 20.
             The level that counts is the entry of the station's band (StationBand) in
             TransmitConfig::levels, taken at station start, from every TransmitProfile
             and at every StationBand. While the band is unknown or has no entry, the
             level that counted before stays; at station start that is levelMaxDb.
             TxLevelStatus::stored is false for a band without an entry.
             A transmission takes the level at the start of its audio and keeps it to
             its end. The Tune tone follows a change of the level at once (SetScale).
             With LevelMode manual the level is the operator's: transmit finds none and
             corrects none. With automatic, transmit finds it with the Tune tone
             (LevelFinding) and corrects it in each transmission (LevelMonitor). While
             the radio does not report its ALC (TxLevelStatus::alc unavailable),
             transmit works as with manual.
             A level transmit finds is stored by giving it as LevelFound for the
             station's band. It counts only when it has come back in a
             TransmitProfile: one that does not come back is not taken, and the level
             before it stays.
             While the tone is on outside a finding and TransmitProfile::levelManaged is
             true, transmit asks radio control for the meters every tuneReadMs and
             shows them as TxLevelStatus::meters and TxLevelStatus::alc. */
        attribute levelMinDb : Integer = -40;
        attribute levelMaxDb : Integer = 0;
        attribute playbackScale : Real = 0.5 {
            doc /* The scale at the level 0 dB, for a waveform with a peak of 1. */ }
        attribute tuneReadMs : Integer = 1000;
        attribute meterReadMaxMs : Integer = 400 {
            doc /* Transmit waits this long for one reading of the meters. */ }
    }

    attribute def LevelFinding {
        doc /* Finding the level with the Tune tone.
             With LevelMode automatic and TransmitProfile::levelManaged true, a tone
             that is switched on (TuneTone) first finds the level of the station's band.
             The tone starts at startDb. Every settleMs transmit asks radio control for
             the meters and decides by the first of these that holds.
             No ALC value: the finding ends with no_alc.
             An SWR of swrFaultX10 or more: it ends with high_swr.
             An ALC above 0: the level one step below the present one, and not below
             TxLevel::levelMinDb, is found; the result is stored.
             The present level is TxLevel::levelMaxDb: that level is found; the result
             is max_without_alc.
             Otherwise the level goes one step up and the tone follows.
             A reading that fails ends the finding with the failure of the reading, and
             the end of the tone (TuneTone) ends it with aborted; neither finds a level.
             A level found is given as LevelFound, and the tone goes on at it; when it
             does not come back as saved, the result is storage_unavailable and the tone
             goes on at the level before. After a finding without a level found the
             tone goes on at the level that counted before it.
             A level found ends LevelWarning::swr_fault and the ceiling of
             LevelMonitor.
             While the level is found, TxLevelStatus::level_db is the level of the
             tone.
             The finding changes neither the transmit state nor its causes, and sends
             the radio no setting. */
        attribute startDb : Integer = -30;
        attribute settleMs : Integer = 400;
        attribute swrFaultX10 : Integer = 30;
    }

    verification 'TC-044-013' {
        doc /* The level in a transmission and in a tone. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-12'; }
        @TestedBy {
            test = "server/tests/transmit_service.rs::"
                + "tx_level_applies_at_audio_start_and_live_only_in_tune";
        }
    }

    verification 'TC-044-014' {
        doc /* Finding the level with the Tune tone, and the stored level. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-12'; }
        @TestedBy {
            test = "server/src/radio_level_tests.rs::"
                + "assistant_decides_from_alc_power_limit_and_swr; "
                + "server/src/radio_level_tests.rs::"
                + "set_level_steps_up_backs_off_one_step_stores_and_stops_tune; "
                + "server/src/radio_level_tests.rs::"
                + "set_level_pushes_the_level_it_is_playing_at_every_step; "
                + "server/src/radio_level_tests.rs::halt_aborts_set_level_without_storing; "
                + "server/src/radio_level_tests.rs::"
                + "a_radio_without_alc_stops_the_assistant_and_opens_the_manual_level; "
                + "server/src/radio_level_tests.rs::"
                + "stored_level_is_loaded_at_startup_and_bad_files_are_ignored; "
                + "server/src/radio_level_tests.rs::"
                + "set_level_that_cannot_be_stored_leaves_the_prior_level; "
                + "server/src/radio_level_tests.rs::"
                + "tune_meters_are_read_once_a_second_and_pushed_as_one_event";
        }
    }

    requirement 'CL-044-14' {
        subject transmit : TransmitService;
        doc /* Transmit MUST read the radio's meters once in every transmission, correct
             the audio drive in automatic by at most one step for the next one, report
             trouble that lasts, and halt on an SWR fault (LevelMonitor). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-044-14'; }

    attribute def LevelMonitor {
        doc /* What transmit does with the meters during a transmission.
             Transmit asks radio control for the meters once in each transmission, when
             half of the audio that was left at the start of the audio has played. It
             asks for none when less than meterMinRemainingMs was left, for a tone, and
             while the level is found.
             The transmission, its audio and its release do not wait for the reading,
             and a reading that fails changes nothing.
             With LevelMode automatic the level moves by one step at most from a
             reading; with manual, or while the radio does not report its ALC, it does
             not move.
             Down, and not below TxLevel::levelMinDb: the ALC is above alcLimit.
             Up, and not above TxLevel::levelMaxDb: the ALC is 0, the output power is
             below stepUpBelowPct percent of the band's output power
             (TransmitProfile::powerPct), and the level above is below the ceiling.
             Without an output power for the band the level does not go up.
             A level that is lowered by the reading directly after the one that raised
             it is the ceiling: the level does not go up to it again. The ceiling ends
             with a level found with the Tune tone, with another output power and with
             a station start.
             The changed level is stored for the station's band and taken as TxLevel
             says; the transmission that plays keeps its level.
             In both modes a LevelWarning is shown from the reading that makes
             persistentReadings readings in a row with its condition, until the first
             reading without it: alc_high for an ALC of alcHigh or more, po_low for an
             output power below poLowPct percent of the band's output power, swr_high for an
             SWR of swrHighX10 or more.
             In both modes an SWR of LevelFinding::swrFaultX10 or more is a fault:
             transmit halts as for a Halt, so that the cause is halt, and shows
             swr_fault until a reading with a lower SWR or a level found with the Tune
             tone; a reading without an SWR value leaves it. */
        attribute meterMinRemainingMs : Integer = 2000;
        attribute alcLimit : Integer = 8 {
            doc /* In percent of the radio's ALC zone (MeterView::alc), as alcHigh. */ }
        attribute alcHigh : Integer = 50;
        attribute stepUpBelowPct : Integer = 80;
        attribute poLowPct : Integer = 50;
        attribute swrHighX10 : Integer = 20;
        attribute persistentReadings : Integer = 3;
    }

    verification 'TC-044-017' {
        doc /* The reading of a transmission and the correction of the level. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-14'; }
        @TestedBy {
            test = "server/src/radio_level_tests.rs::"
                + "monitor_decides_one_bounded_step_and_warns_only_when_persistent; "
                + "server/tests/transmit_service.rs::"
                + "the_meter_read_is_due_once_in_the_middle_of_each_transmission; "
                + "server/tests/transmit_service.rs::"
                + "a_late_start_with_under_two_seconds_of_audio_has_no_meter_read; "
                + "server/src/radio_level_tests.rs::"
                + "one_burst_corrects_for_the_next_transmission_only_and_"
                + "warns_when_persistent; "
                + "server/src/radio_level_tests.rs::"
                + "a_clear_swr_fault_stops_transmitting_and_keeps_automation_off; "
                + "server/src/radio_level_tests.rs::a_reading_without_swr_keeps_the_fault_entry; "
                + "server/src/radio_level_tests.rs::"
                + "nothing_is_read_for_a_transmission_while_set_level_runs; "
                + "server/src/radio_level_tests.rs::"
                + "startup_connects_the_meter_call_to_one_burst; "
                + "server/src/transmit/transmit_http_tests.rs::"
                + "the_meter_call_of_the_transmit_step_reaches_the_sink; "
                + "server/src/radio_level_tests.rs::"
                + "a_correction_that_cannot_be_stored_leaves_the_level; "
                + "server/src/radio_level_tests.rs::"
                + "alc_zero_and_above_the_limit_on_neighbouring_levels_settle_on_the_lower; "
                + "server/src/radio_level_tests.rs::"
                + "a_lowering_without_a_step_up_before_it_keeps_the_step_up; "
                + "server/src/radio_level_tests.rs::"
                + "the_live_alc_comes_down_to_the_limit_without_a_warning_and_stays; "
                + "server/src/radio_level_tests.rs::set_levels_stop_and_the_correction_agree; "
                + "server/src/radio_level_tests.rs::"
                + "the_ceiling_ends_with_a_changed_profile_power_and_a_stored_set_level";
        }
    }
}
