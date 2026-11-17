package WstxHoldTx {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-007';
    private import WstxQsoPart::QsoService;
    private import WstxQsoControl::TxChoice;
    private import WstxQsoControl::OpenRange;
    private import ModelNotes::FollowsSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* Where a contact transmits, made by hand or started by Auto: the best quiet space,
         the free offsets the screen shows, Hold Tx, and the rule that keeps Tx off the
         partner's signal. */

    attribute def SlotLimits {
        doc /* The bounds of the quiet space. */
        attribute clearanceHz : Integer = 50 {
            doc /* The gap the station's signal keeps from the partner's signal and from a
                 frequency the partner decodes: FT8 100 Hz, FT4 140 Hz between the lower
                 edges of the two signals. */ }
        attribute candidateLowHz : Integer = 500 { doc /* The lowest offset of the space. */ }
        attribute upperEdgeHz : Integer = 2400 {
            doc /* Up to here the receivers' filters are flat: a signal goes above it only
                 when no offset below is free. */ }
        attribute periodsPerParity : Integer = 4 {
            doc /* How many of the latest periods of the judged parity are counted. */ }
    }

    attribute def SlotLevel {
        doc /* How loud an offset is. Every offset f stands for the signal [f, f + width)
             of the mode (FT8 50 Hz, FT4 90 Hz).
             The judged parity is the parity of the periods the station receives in: while
             a contact is in progress the parity its partner transmits in, during a CQ the
             other of the parity the CQ is sent in, otherwise the parity of the period in
             progress.
             The counted periods are the received ones among the last
             SlotLimits::periodsPerParity periods of the judged parity that are due: a
             period is due once it has ended, or earlier, while in progress, once its
             complete publication is there, and never before it starts. A period the
             station transmitted in, or did not receive, leaves a gap that no older period
             fills. Only periods after the last change of the station's band, and of the
             live job's, count.
             In a counted period an offset reads the mean level of the detailed spectrum
             bins of its signal over the period's rows, less the mean of that period's
             passband floor over the same bins. Its level is the highest of these over the
             counted periods, in whole dB; a level below the floor is negative.
             Without a counted period an offset has no level.
             The passband floor of a period is the one WSJT-X's decoder fits to the
             period's levels from 300 to 2700 Hz; levels that do not reach 2700 Hz have
             none. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the decoder's baseline fit of the "
                + "passband";
        }
    }

    requirement 'CL-039-09' {
        subject qso : QsoService;
        doc /* qso MUST take every new Tx offset of a contact or a CQ from the best quiet
             space (QuietSpace). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-039-09'; }

    attribute def QuietSpace {
        doc /* The best quiet space: the one function that finds a free Tx offset.
             A new Tx offset is taken when TooCloseRule moves Tx, when Auto starts a
             contact or a CQ, and when Auto asks for a move (WstxOperatingChain::CallTarget);
             nothing else asks for one.
             The candidates are the offsets on a grid of 10 Hz from
             SlotLimits::candidateLowHz up to the top of the Tx range with the whole signal
             inside it, and the current Tx when it lies in that range, whose signal keeps
             SlotLimits::clearanceHz from the partner's signal.
             Of them, each step while one is left: the free offsets (an offset whose signal
             overlaps no station decoded in a counted period, an offset closer than the
             width to the station's frequency); those free at his end (each keeping
             clearanceHz from every frequency the partner decodes in the parity the station
             transmits in, WstxHearing::TargetReport); those whose signal stays at or below
             SlotLimits::upperEdgeHz.
             Of those left, the lowest level (SlotLevel) wins, also a level below the
             floor. Of equal levels the one
             nearest a frequency the partner decodes wins, then the current Tx, then the
             nearer to the current Tx, then the lower.
             Without a counted period the current Tx stays when it is a candidate, else the
             nearest candidate, the lower on a tie; the choice then has no level.
             Without what the partner decodes, the steps of his end are left out.
             For a move of Auto the candidates whose signal overlaps the current Tx are
             left out, and with none left Tx stays.
             Rx is not moved by it. qso's state names the last choice and its level
             (TxChoice). */
        attribute limits : SlotLimits;
        attribute level : SlotLevel;
        attribute choice : TxChoice;
    }

    verification 'TC-039-010' {
        doc /* The quietest offset. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-039-09'; }
        @TestedBy {
            test = "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_the_lowest_power_wins_and_a_tie_keeps_the_current_tx; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_whole_db_decides_the_tie; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_never_outside_the_tx_range; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_never_within_50_hz_of_the_called_station; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_his_end_excludes_and_is_ignored_when_it_leaves_nothing; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_no_power_keeps_the_current_tx; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_the_counted_periods_are_my_recent_rx_periods; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_010_a_slot_reads_its_bins_above_the_floor; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_010_the_run_calls_from_the_quietest_slot_of_its_rx_parity";
        }
    }

    verification 'TC-039-050' {
        doc /* The level and the floor. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-09'; }
        @TestedBy {
            test = "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_050_the_busiest_counted_period_counts; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_050_the_passband_floor_of_a_flat_period_and_its_coverage; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_039_050_the_roll_off_floor_matches_the_numpy_reference";
        }
    }

    verification 'TC-066-002' {
        doc /* The decoded stations, his end and the judged parity. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-09'; verify 'CL-065-01'; }
        @TestedBy {
            test = "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_066_002_a_candidate_on_a_decoded_station_is_left_out_while_one_is_free; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_066_002_only_my_rx_parity_is_judged; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_066_002_decodes_of_periods_that_do_not_count_leave_nothing_out; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_066_002_his_end_applies_among_the_candidates_left_by_decodes";
        }
    }

    verification 'TC-089-001' {
        doc /* The newest period counts once it is due. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-09'; verify 'CL-065-01'; }
        @TestedBy {
            test = "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_089_001_the_newest_rx_period_counts_once_its_complete_publication_is_there; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_089_001_the_newest_period_counts_by_its_rows_so_far; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_089_001_an_ended_period_and_ft4";
        }
    }

    verification 'TC-089-002' {
        doc /* A choice on the newest publication. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-09'; }
        @TestedBy {
            test = "server/src/operating/qso/newest_rx_tests.rs::"
                + "tc_089_002_a_selection_on_the_newest_publication_counts_its_stations";
        }
    }

    requirement 'CL-065-01' {
        subject qso : QsoService;
        doc /* qso MUST give the free offsets of the quiet space at each build, with or
             without a contact and with Auto on or off (OpenSlotRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-065-01'; }

    attribute def OpenSlotRule {
        doc /* The free offsets for the operator to see on the waterfall: the offsets of
             QuietSpace's grid whose level is 0 or less and that are free, without a partner's
             clearance, his end or a fallback.
             The open ranges (OpenRange) are the union of their signals: overlapping ones
             join, touching ones stay apart, so each is at least one width long, and they
             ascend without overlap.
             A build happens at each period start; when the decodes of a counted period are
             published, and the complete publication of the period in progress of the
             judged parity; at once when a contact or a CQ starts or ends; at once when the
             live job, its mode or the station's band changes. Each build gives
             WstxQsoControl::OpenSlots; without a live job of receive there is none. */
        attribute ranges : OpenRange;
    }

    verification 'TC-082-001' {
        doc /* Which offsets are open, and their ranges. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-065-01'; }
        @TestedBy {
            test = "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_082_001_touching_signals_stay_apart_and_overlapping_ones_join; "
                + "server/src/operating/qso/freeslot_tests.rs::"
                + "tc_082_001_whole_db_no_fallback_and_no_counted_period";
        }
    }

    requirement 'CL-039-08' {
        subject qso : QsoService;
        doc /* qso MUST keep Tx at a selection while Hold Tx is on and let Tx follow Rx while
             it is off (HoldTxRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-039-08'; }

    attribute def HoldTxRule {
        doc /* Hold Tx is on at station start and for the session; the operator switches it.
             A selection moves Rx onto the selected station. With Hold Tx on Tx stays where
             it is; with Hold Tx off Tx goes where Rx goes. A selection of a station that
             calls the profile's call keeps Tx in both. Auto's contact and CQ have no Hold
             Tx: their Tx comes from QuietSpace. */
    }

    requirement 'CL-010-11' {
        subject qso : QsoService;
        doc /* qso MUST set the Rx and Tx offsets as OffsetRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-010-11'; }

    attribute def OffsetRule {
        doc /* SetFrequency sets the Rx offset, the Tx offset or both; it switches nothing
             on. Rx lies from 0 to rxMaxHz, Tx from txMinHz to the top of the Tx range of
             the mode (FT8 txMaxFt8Hz, FT4 txMaxFt4Hz); a value outside is out_of_range. A
             change of the mode brings Tx into the range of the new mode. */
        attribute rxMaxHz : Integer = 3000;
        attribute txMinHz : Integer = 200;
        attribute txMaxFt8Hz : Integer = 2950;
        attribute txMaxFt4Hz : Integer = 2916;
    }

    verification 'TC-039-009' {
        doc /* Hold Tx is on by default. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-08'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "hold_tx_is_on_by_default_and_a_selection_keeps_tx";
        }
    }

    requirement 'CL-039-29' {
        subject qso : QsoService;
        doc /* qso MUST move Tx to the best quiet space whenever the station's signal is too
             close to the partner's, as TooCloseRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-039-29'; }

    attribute def TooCloseRule {
        doc /* The partner's signal is protected. The station's signal is too close when it
             keeps less than SlotLimits::clearanceHz from the partner's last decoded
             signal. Where WSJT-X stops because Tx is too close, the station moves Tx and
             goes on: when the partner sends a decoded message to another call while the
             station calls him (state replying, or report after a skipped Tx1), with Hold
             Tx on and off. Too close is also judged when a start is accepted, for Auto's
             contact and CQ and for a contact made by hand while Hold Tx is on; with Hold
             Tx off a start puts Tx where Rx is. Tx then moves to QuietSpace's offset
             before the station's next transmission whose audio has not started;
             transmission stays on and Rx stays on him. An explicit Tx setting of the
             operator after the start stands until the partner's next message to another
             call. A Hound's Tx follows the Hound's own rules; this rule does not apply
             to it. */
    }
}
