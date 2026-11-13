package WstxTxLevel {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-009';
    private import WstxRequirements::AutomationState;
    private import WstxTransmit::'CL-044-13';
    // Operator decisions 2026-11-04 (#44 comments 6627977497, 6628000054): Tx audio level.
    // IC-7300 meters: Icom IC-7300 Full Manual section 19, command table "15 11 Po" (0000 0 %,
    // 0143 50 %, 0213 100 %), "15 12 SWR" (0000 1.0, 0048 1.5, 0080 2.0, 0120 3.0), "15 13 ALC"
    // (0000..0120 the ALC zone); data two BCD bytes 0000..0255. The repository holds no copy of
    // that table beyond this citation; TC-044-015 confirms it on the radio.
    requirement 'CL-044-12' {
        doc /* Tx level and Set level. The Tx level is a digital attenuation of the station's Tx audio, -40..0 dB in whole dB below the playback scale (Transmit TransmitTiming playbackScale), stored per radio profile in tx-level.json of the profile directory {schema_version 1, level_db}; storing it does not advance the profile revision and so does not reconnect CAT. Without a stored level, or with an invalid file, it is 0 dB. Set level is the default way to set it: POST /radio/tx-level {v, profile_id, boot_id, command_id, action set_level, tx_offset_hz} (transmit authority as Tune: a current CL-022 grant, otherwise 401 unauthorized; malformed 400 invalid_request; reply 200 {v, profile_id, boot_id, command_id, accepted, refusal}, refused busy while a transmission, a pending request, a Tune or another run is active, otherwise with the transmit refusal). It arms when disarmed and disarms again at its end, starts Tune at -30 dB and, every 400 ms, reads the meters and decides: ALC above 0 or Po above the profile power settings.radio.power_limit_pct (1..100; absent: no limit but the radio's own RF power setting) stores one step below the current level, never below -40 dB (result stored); 0 dB reached without either stores 0 dB (result max_without_alc); otherwise one step up. SWR at or above 3.0 (raw 0120) stops without storing (result high_swr); an ALC read refused FA stops without storing (result no_alc). It always ends with Tune stopped. HALT, the Tune limit or any other loss of Tune aborts it without storing (result aborted), and every failure leaves the prior level. A manual level (action manual, level_db -40..0) exists only after the radio refused the ALC read (otherwise refused alc_available) and applies to a running Tune at once. A transmission takes the level at its audio start and keeps it to its end. A meter read is one burst of reads FE FE <address> E0 15 13 FD, 15 11, 15 12 (one reply each; FA: that meter is missing), bounded at 400 ms in total, admitted only while this station holds the transmit hold (otherwise Busy with no byte). It takes no lease, so no operation or poll can start through it and it cannot delay a key; a PTT exchange cancels it at once, so the 250 ms halt bound holds; a timeout or cancel leaves the connection open. While Tune runs outside Set level the station reads the meters once per second on its own thread. Reads only: this slice writes no radio setting. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_level.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/setup.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/playback.rs; server/src/profile.rs";
    }
    dependency CL_044_12_to_FR_009 from 'CL-044-12' to 'FR-009';
    verification 'TC-044-013' {
        doc /* TC-044-013 — Meter burst under the transmit hold; level timing
             CL-044-12
             Setup: the actual CAT actor and executor on a scripted IC-7300 transport (echo of each frame, hand-written replies); the actual transmit core on a virtual clock.
             Steps: (a) read without the hold, then with it; (b) ALC refused FA; (c) a timeout, then a stalled read released by PTT off; (d) raw values through the scales; (e) a level set before and during a transmission and during Tune.
             Expected: (a) Busy and no byte, then exactly the frames 15 13, 15 11, 15 12, and the release still works; (b) ALC missing, Po read; (c) the connection stays Ready, the release returns within 250 ms and the read returns Cancelled; (d) Po 0143 50 %, 0213 100 %, SWR 0048 1.5, 0080 2.0, 0120 3.0; (e) the level reaches the hardware immediately before the play, not during the transmission, at once during Tune; 0 dB is the playback scale, -20 dB a tenth of it.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-12';
        }
        attribute executable : String = "server/src/radio_level_tests.rs; server/tests/transmit_service.rs";
    }
    dependency CL_044_12_verified_by_TC_044_013 from 'CL-044-12' to 'TC-044-013';
    verification 'TC-044-014' {
        doc /* TC-044-014 — Set level, manual level, push and route
             CL-044-12, CL-044-13
             Setup: the actual router, Recording owner and transmit owner on a recording hardware double, the CAT actor on a scripted IC-7300 whose ALC follows the double's level.
             Steps: (a) the decision table; (b) a run with the ALC rising at -27 dB; (c) HALT during a run; (d) a radio refusing the ALC read, then the manual level, also during Tune; (e) stored and invalid level files at startup; (f) ticks with and without Tune; (g) malformed requests and a request without a grant; (h) the profile field.
             Expected: (a) up, stored one below, -40 floor, power limit 49/50 % at Po 50 %, max_without_alc, no_alc, high_swr; (b) levels -30, -29, -28, -27, -28 stored, Tune off, disarmed, the profile revision unchanged, the next Tune at -28, no setter frame; (c) aborted, no file, prior level, Tune off, disarmed; (d) no_alc, alc unavailable, the slider action refused alc_available before, range refused, -10 stored, Tune follows; (e) -17 applied, invalid files ignored; (f) no read without Tune, one burst per second with it, exact event keys and values; (g) 400 and 401, Tune stays off; (h) absent by default, saved, 0 and 101 refused.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-12';
            verify 'CL-044-13';
        }
        attribute executable : String = "server/src/radio_level_tests.rs";
    }
    dependency CL_044_12_verified_by_TC_044_014 from 'CL-044-12' to 'TC-044-014';
    verification 'TC-044-016' {
        doc /* TC-044-016 — Set level on HB9BLA
             CL-044-12, CL-044-13
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's consent, a dummy load or the station antenna, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported).
             Steps: read 15 13, 15 11, 15 12 during Tune over CI-V; press Set level; press HALT during a second run. The evidence is the CI-V readback and the radio.tx_level frames, not the radio's display (operator decision of 2026-11-08).
             Expected: the meter values read back agree with the radio.tx_level frames and the manual's scales; the run ends with the ALC just below rising, the level stored and Tune off; HALT stops it at once and keeps the stored level.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-12';
            verify 'CL-044-13';
        }
    }
    dependency CL_044_12_verified_by_TC_044_016 from 'CL-044-12' to 'TC-044-016';
}
