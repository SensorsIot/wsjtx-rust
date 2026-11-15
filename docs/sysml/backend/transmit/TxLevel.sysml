package WstxTxLevel {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-009';
    private import WstxTransmit::'CL-044-13';
    private import WstxTransmit::'CL-044-14';
    private import WstxTransmitPart::TransmitService;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    private import RequirementDerivation::*;
    attribute def TxLevel {
        @FollowsSource {
            reference = "Icom IC-7300 Full Manual A7292-4EX-12a section 19, command table: "
                + "15 11 Po (0000 0 %, 0143 50 %, 0213 100 %), 15 12 SWR (0000 1.0, 0048 1.5, "
                + "0080 2.0, 0120 3.0), 15 13 ALC (0000..0120 the ALC zone); data two BCD bytes "
                + "0000..0255";
        }
        doc /* The Tx level of the station's Tx audio, set by Set level, by a manual level or by
             the correction of the meter reads, and pushed as radio.tx_level. */
    }
    attribute txLevel : TxLevel;
    satisfy 'CL-044-12' by txLevel;
    satisfy 'CL-044-13' by txLevel;
    satisfy 'CL-044-14' by txLevel;

    requirement 'CL-044-12' {
        subject transmit : TransmitService;
        doc /* The Tx level MUST be a digital attenuation of the station's Tx audio, -40..0 dB in
             whole dB below the playback scale (WstxTransmit TransmitTiming playbackScale),
             stored per radio profile in tx-level.json of the profile directory
             {schema_version 1, level_db}; storing it does not advance the profile revision and
             so does not reconnect CAT. */
        doc /* Without a stored level, or with an invalid file, it is 0 dB. */
        doc /* Set level is the default way to set it: POST /radio/tx-level {v, profile_id,
             boot_id, command_id, action set_level, tx_offset_hz} (transmit authority as Tune: a
             current CL-022 grant, otherwise 401 unauthorized; malformed 400 invalid_request;
             reply 200 {v, profile_id, boot_id, command_id, accepted, refusal}, refused busy
             while a transmission, a pending request, a Tune or another run is active, otherwise
             with the transmit refusal). */
        doc /* Set level arms when disarmed and disarms again at its end, starts Tune at -30 dB
             and, every 400 ms, reads the meters and decides: ALC above 0 or Po above the
             profile power settings.radio.power_limit_pct (1..100; absent: no limit but the
             radio's own RF power setting) stores one step below the current level, never below
             -40 dB (result stored); 0 dB reached without either stores 0 dB (result
             max_without_alc); otherwise one step up. */
        doc /* SWR at or above 3.0 (raw 0120) stops it without storing (result high_swr); an ALC
             read refused FA stops it without storing (result no_alc). */
        doc /* It always ends with Tune stopped. */
        doc /* HALT, the Tune limit or any other loss of Tune aborts it without storing (result
             aborted), and every failure leaves the prior level. */
        doc /* A manual level (action manual, level_db -40..0) exists only after the radio
             refused the ALC read (otherwise refused alc_available). */
        doc /* A transmission takes the level at its audio start and keeps it to its end; a
             running Tune follows a level change at once. */
        doc /* A meter read is one burst of reads FE FE <address> E0 15 13 FD, 15 11, 15 12 (one
             reply each; FA: that meter is missing), bounded at 400 ms in total, admitted only
             while this station holds the transmit hold (otherwise Busy with no byte). It takes
             no lease, so no operation or poll can start through it and it cannot delay a key; a
             PTT exchange cancels it at once, so the 250 ms halt bound holds; a timeout or cancel
             leaves the connection open. While Tune runs outside Set level the station reads the
             meters once per second on its own thread. Reads only: this slice writes no radio
             setting. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/radio_level.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/setup.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/transmit/playback.rs; server/src/profile.rs";
        }
    }
    #derivation connection {
        end #original ::> 'FR-009';
        end #derive ::> 'CL-044-12';
    }
    verification 'TC-044-013' {
        doc /* Meter burst under the transmit hold; level timing
             Setup: the actual CAT actor and executor on a scripted IC-7300 transport (echo of
             each frame, hand-written replies); the actual transmit core on a virtual clock. No
             radio or RF.
             (a) A read without the hold, then with it: Busy and no byte, then exactly the
             frames 15 13, 15 11, 15 12, and the release still works.
             (b) ALC refused FA: ALC missing, Po read.
             (c) A timeout, then a stalled read released by PTT off: the connection stays Ready,
             the release returns within 250 ms and the read returns Cancelled.
             (d) Raw values through the scales: Po 0143 50 %, 0213 100 %, SWR 0048 1.5, 0080
             2.0, 0120 3.0.
             (e) A level set before and during a transmission and during Tune: the level reaches
             the hardware immediately before the play, not during the transmission, and at once
             during Tune; 0 dB is the playback scale, -20 dB a tenth of it. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-12';
        }
        @TestedBy { test = "server/src/radio_level_tests.rs; server/tests/transmit_service.rs"; }
    }
    verification 'TC-044-014' {
        doc /* Set level, manual level, push and route
             Setup: the actual router, Recording owner and transmit owner on a recording
             hardware double, the CAT actor on a scripted IC-7300 whose ALC follows the double's
             level. No radio or RF.
             (a) The decision table: up, stored one below, -40 floor, power limit 49/50 % at Po
             50 %, max_without_alc, no_alc, high_swr.
             (b) A run with the ALC rising at -27 dB: levels -30, -29, -28, -27, -28 stored, Tune
             off, disarmed, the profile revision unchanged, the next Tune at -28, no setter
             frame.
             (c) HALT during a run: aborted, no file, prior level, Tune off, disarmed.
             (d) A radio refusing the ALC read, then the manual level, also during Tune: no_alc,
             alc unavailable, the slider action refused alc_available before, range refused,
             -10 stored, Tune follows.
             (e) Stored and invalid level files at startup: -17 applied, invalid files ignored.
             (f) Ticks with and without Tune: no read without Tune, one burst per second with it,
             exact event keys and values.
             (g) Malformed requests and a request without a grant: 400 and 401, Tune stays off.
             (h) The profile field: absent by default, saved, 0 and 101 refused. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-12';
            verify 'CL-044-13';
        }
        @TestedBy { test = "server/src/radio_level_tests.rs"; }
    }
    verification 'TC-044-016' {
        doc /* Set level on HB9BLA
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's
             consent, a dummy load or the station antenna, RF power set low by the test before
             the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it
             holds COM3; read back; the operator's value is restored afterwards only if the
             radio still reads what the test set, otherwise it is left alone and reported). The
             evidence is the CI-V readback and the radio.tx_level frames, not the radio's
             display. Not run by the automated gate.
             (a) Read 15 13, 15 11, 15 12 during Tune over CI-V: the values read back agree with
             the radio.tx_level frames and the manual's scales.
             (b) Press Set level: the run ends with the ALC just below rising, the level stored
             and Tune off.
             (c) Press HALT during a second run: it stops at once and keeps the stored level. */
        @TestLevel { cost = 5; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; method = "manual"; }
        objective {
            verify 'CL-044-12';
            verify 'CL-044-13';
        }
    }
}
