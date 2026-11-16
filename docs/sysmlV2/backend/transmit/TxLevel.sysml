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

    // ---- The level and how it is set ----------------------------------------------------------

    requirement 'CL-044-12' {
        subject transmit : TransmitService;
        doc /* Transmit MUST play its audio at the Tx level of the station's band, set by
             the operator in manual and found with the Tune tone in automatic (TxLevel,
             LevelFinding). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-044-12'; }

    attribute def TxLevel {
        doc /* The Tx level: how far the audio of the station is turned down, in whole
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
             An ALC above 0, or an output power above TransmitConfig::powerLimitPct:
             the level one step below the present one, and not below
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
        doc /* The level in a transmission and in a tone.
             Setup: the transmit function on a given clock with a scripted radio and an
             output that records every scale it is given; no sound device, no radio.
             (a) The level -12 set while nothing plays: the output is given nothing. A
             transmission: the output is given -12 once, directly before its program.
             The level -13 set during the transmission: the output is given nothing
             more.
             (b) The level -99 set, then the tone: the tone starts at -40. The level 5
             set during the tone: the output is given 0 at once.
             (c) The scale of the level 0 is 0.5, that of -20 is 0.05, and that of -99
             is the scale of -40. */
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
        doc /* Finding the level with the Tune tone, and the stored level.
             Setup: the transmit function of a station on a disposable profile folder,
             LevelMode automatic, with an output that records every scale and radio
             control on a scripted IC-7300 that is keyed and reports an output power of
             50 %; no sound device, no radio.
             (a) The decision of a finding. At -30 with an ALC of 0: -29. At -20 with an
             ALC of 1: -21 is found. At -40 with an ALC of 1: -40 is found. At -10 with
             an ALC of 0 and a profile power of 49: -11 is found; with a profile power
             of 50: -9. At 0 with an ALC of 0: 0 is found, max_without_alc. No ALC
             value: no_alc. An SWR of 3.0: high_swr.
             (b) A radio whose ALC rises from -27 on, the tone switched on: it plays at
             -30, -29, -28 and -27; the result is stored, and the level found and taken
             is -28; the next tone plays at -28; the radio has received readings and no
             setting. At every reading of the finding TxLevelStatus::level_db is the
             level the tone plays at.
             (c) Halt during a finding: aborted, no level found, the level 0, the tone
             off.
             (d) A radio that refuses the ALC reading: the finding ends with no_alc, alc
             is unavailable and no level is found. With LevelMode manual, a
             configuration with the level -12 for the band given during a tone: the
             tone plays at -12 at once.
             (e) At station start without a level for the band in the configuration:
             the level 0, and a tone plays at 0. With the level -17: -17, and a tone
             plays at -17.
             (f) The ALC rises from -27 on and the level found does not come back as
             saved: the result is storage_unavailable, the level 0, stored false, and
             the next tone plays at 0.
             (g) levelManaged true and no tone: no reading. The tone on outside a
             finding, the radio with an ALC of 6: one reading, and meters holds alc 6,
             po_pct 50 and swr_x10 10. 900 ms after that reading: no further one. 1000
             ms after it: one more.
             (h) Planned, no test yet: after a finding the tone goes on at the level
             found, and at the level before after a finding without one, until it is
             switched off or reaches its limit; the transmit state and its causes do not
             change; a finding ended by the limit of the tone; with LevelMode manual a
             tone finds nothing; a StationBand of a band with an entry plays at its
             level, of a band without one at the level before; a level found is given
             for the station's band. */
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

    // ---- The supervision of the level in normal operation -----------------------------------

    requirement 'CL-044-14' {
        subject transmit : TransmitService;
        doc /* Transmit MUST read the radio's meters once in every transmission, correct
             the Tx level in automatic by at most one step for the next one, report
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
             Down, and not below TxLevel::levelMinDb: the ALC is above alcLimit, or
             the output power is above TransmitConfig::powerLimitPct.
             Up, and not above TxLevel::levelMaxDb: the ALC is 0, the output power is
             below stepUpBelowPct percent of the profile power, and the level above is
             below the ceiling.
             Without a profile power the output power is neither above nor below it,
             and the level does not go up.
             A level that is lowered by the reading directly after the one that raised
             it is the ceiling: the level does not go up to it again. The ceiling ends
             with a level found with the Tune tone, with another profile power and with
             a station start.
             The changed level is stored for the station's band and taken as TxLevel
             says; the transmission that plays keeps its level.
             In both modes a LevelWarning is shown from the reading that makes
             persistentReadings readings in a row with its condition, until the first
             reading without it: alc_high for an ALC of alcHigh or more, po_low for an
             output power below poLowPct percent of the profile power, swr_high for an
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
        doc /* The reading of a transmission and the correction of the level.
             Setup: the decision alone for (a) and (h) to (k); the transmit function on
             a given clock with a scripted radio for (b); the station of TC-044-014 for
             the others. LevelMode automatic unless said otherwise. The output power
             reads 50 % unless said otherwise; no sound device, no radio.
             (a) At -10 with a profile power of 50: an ALC of 8 leaves -10; 9 and 50
             give -11. At -40 an ALC of 50 leaves -40. An ALC of 0 with a profile power
             of 63: -9; with 62: -10; at 0 with 100: 0. An ALC of 1, no profile power,
             and no ALC value: no step up. A profile power of 49: -11. An SWR of 3.0 is
             a fault; the meter count below it is none. An SWR of 2.0 three times:
             swr_high from the third reading, gone with a reading of 1.0. An ALC of 50
             three times: alc_high from the third; of 49 three times: no warning. A
             profile power of 101 three times: po_low from the third.
             (b) An FT8 transmission whose audio starts 500 ms after the period start P:
             the reading is asked for at P + 6820 ms, once. The next one, in P + 30 s:
             at P + 36820 ms. A tone: none. A transmission started 11200 ms after P:
             none.
             (c) An ALC of 50 at the level -10. The radio not keyed: nothing is read and
             the level stays. Keyed: one reading of the three meters and nothing else,
             the level -11 found and taken, nothing given to the output, no warning. A
             second reading: no warning. A third: alc_high, and the level is -13. Then
             an ALC of 8: no warning, and the level stays -13.
             (d) The transmit state on; a reading with an SWR of
             3.0: one Halt, disarmed with the cause halt, swr_fault. A
             reading without an SWR value: swr_fault stays. An Arm with the cause
             operator and a reading with a low SWR: no swr_fault, still armed.
             (e) While the level is found: nothing is read.
             (f) After a station start the request of a transmission for its reading
             leads to one reading of the three meters.
             (g) An ALC of 50 at -10 and the level found does not come back as saved:
             the level stays -10, stored false, and the next tone plays at -10.
             (h) A radio that reads an ALC of 0 up to -10 and 9 from -9 on, with a
             profile power of 100. From -10: -9 after one transmission, -10 after two
             and after 40. From -9: -10, -9, -10, and -10 after 40.
             (i) A profile power of 100. At -12 an ALC of 11: -13. Then 0: -12. Then 0:
             -11. Then 4: -11. Then 11: -12. Then 0: -11.
             (j) An ALC of 26 at -9 that falls by 5 for each dB: -10, -11, -12, -13, and
             -13 after 40 transmissions, without a warning.
             (k) A radio that reads an ALC of 0 up to -9 and 6 at -8, rising by 5 for
             each dB: a finding goes up at -9 and finds -9 at -8. The supervision goes
             from -9 to -8 and stays; from -7 it goes to -8 and stays.
             (l) A profile power of 100, the level -10. An ALC of 0: -9. Then 9: -10.
             Then 0: -10. The same profile power given again, an ALC of 0: -10. A
             profile power of 90: -9 with an ALC of 0 and -10 with 9. A finding that
             finds -9, then an ALC of 0: -8.
             (m) Planned, no test yet: with LevelMode manual, an ALC of 50 three times
             leaves the level and shows alc_high from the third reading, and an SWR of
             3.0 halts as in (d). */
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
