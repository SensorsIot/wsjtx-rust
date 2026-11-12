package WstxRequirementsTransmit {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    requirement 'CL-009-02' {
        doc /* Plan an FT8 transmission start for a named even/odd 15 s UTC period from a
             virtual clock: 500 ms audio delay, late start up to 75 % of the period by
             skipping the elapsed prefix, refusal for an unsynchronized/unknown clock,
             an unaligned period or a stale request, and no catch-up or replay of a
             missed period. Details: WstxTransmit::Ft8Schedule, PlanTransmitStart. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/schedule.rs";
    }
    dependency CL_009_02_to_FR_006 from 'CL-009-02' to 'FR-006';
    dependency CL_009_02_to_FR_005 from 'CL-009-02' to 'FR-005';
    requirement 'CL-009-03' {
        doc /* Manage PTT and transmit audio through the station's one transmit owner and
             its explicit transmit authority: arm only by an explicit operator request
             with a current CL-022 grant and the current safety revision on a profile
             with CAT PTT and an exact output device (receive-only commissioning is not
             authority); disarmed at every start; admit, replace (until audio start) or
             refuse TransmitRequests; key CI-V PTT with readback before audio, play the
             48 kHz waveform from its planned sample, release PTT with readback after the
             last sample; Tune and the Tx watchdog; report every TransmitOutcome. The
             automatic CAT lifecycle never emits PTT. Details: WstxTransmit::
             TransmitAuthority, TransmitArming, TransmitRequest, TransmitOutcome,
             TransmitTiming, TransmitClock, PttControl, AudioPlayback, SetTune,
             TransmitWatchdog, TransmitWire. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/playback.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/codec.rs";
    }
    dependency CL_009_03_to_FR_008 from 'CL-009-03' to 'FR-008';
    dependency CL_009_03_to_FR_009 from 'CL-009-03' to 'FR-009';
    dependency CL_009_03_to_FR_002 from 'CL-009-03' to 'FR-002';
    requirement 'CL-009-04' {
        doc /* Provide an immediate Halt that stops audio and releases PTT with readback
             within 250 ms while CAT answers, cancels pending requests and disarms; make
             audio device loss, CAT errors or timeouts, authority changes, an
             unsynchronized clock and late or stale requests release or never key PTT,
             report an unconfirmed release as indeterminate and recover it off-only, and
             never resume or replay a transmission after a restart or reconnect; after a
             boot, a radio found transmitting before the boot ever keyed gets exactly one
             off-only release with readback. Details: WstxTransmit::HaltTransmit,
             TransmitTiming, PttControl, StartupSafetyRelease, TransmitOutcome. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs";
    }
    dependency CL_009_04_to_FR_008 from 'CL-009-04' to 'FR-008';
    dependency CL_009_04_to_FR_006 from 'CL-009-04' to 'FR-006';
    verification 'TC-006-001' {
        doc /* TC-006-001 — FT8 transmit period scheduling
             CL-009-02
             Setup: virtual UTC clock values around period boundaries, both parities,
             12 kHz and 48 kHz, every clock state.
             Steps: select the next slot and plan starts before the period, at the audio
             delay, late, at the 75 % boundary, after it, in the wrong period, for
             unaligned periods and unsynchronized/unknown clocks.
             Oracles: WSJT-X values (Modulator.cpp delay_ms=500 and late-start m_ic,
             TxStartPolicy.hpp 0.75, mainwindow.cpp even/odd t mod 30 s): exact audio
             start and skipped-sample counts; 11249 ms admitted and 11250 ms stale;
             stale requests never move to a later period.
             2 — Isolated automated tests; Windows development PC, no clock, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-02';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs";
    }
    dependency CL_009_02_verified_by_TC_006_003 from 'CL-009-02' to 'TC-006-003';
    dependency CL_009_02_verified_by_TC_006_001 from 'CL-009-02' to 'TC-006-001';
    verification 'TC-008-003' {
        doc /* TC-008-003 — Transmit authority, halt and failure handling
             CL-009-03, CL-009-04
             (Planned on issue #9 as TC-008-001; that ID was taken by #10 for the Tx and
             Tune watchdogs, so the #9 halt/failure case is TC-008-003.)
             Setup: the actual transmit owner on a virtual UTC clock with a recording
             hardware double; the actual CI-V actor against an independent emulated
             IC-7300 peer; the actual station router, CL-022 lifecycle and scripted CI-V
             peer; the contact engine against the actual owner core on the virtual
             clock (contact_tests).
             Steps: request while disarmed; arm with unsupported/unavailable capability,
             a wrong safety revision and without a grant; FT8 request before the period,
             late, stale, misaligned, unsynchronized/unknown clock, bad text and offset,
             duplicate sequence; replacement before and after audio start; a request
             for another period while the pending one is keyed before its audio, also
             from the engine stepping between the key and the audio of a late start
             (#10); halt
             mid-audio on the virtual clock, through the owner thread and through the
             real actor; audio device loss, CAT loss, key timeout, output open failure,
             safety revision change; an end report 300/900 ms late and one seen only
             by an owner step after the deadline; a device that stops consuming half
             way (FT8, late FT8, FT4); the render fill decisions against a modelled
             10 ms engine with and without 40 ms render delays (#49); restart; Tx
             watchdog expiry and Tune limit;
             lifecycle polling with the transmit owner present; malformed and extra-key
             wire bodies, wrong Origin, stale boot, retained command_id.
             Oracles: no PTT or audio call/byte while disarmed or unauthorized or
             without an opened output; PTT bytes exactly FE FE 94 E0 1C 00 01 FD and
             1C 00 00 with 1C 00 readback; open before key at the period start, audio at
             period start + 500 ms with skip 0, late skip (t-500 ms)*48; replaced and
             audioStarted outcomes in order; a request for another period while keyed
             before audio is accepted as the next one, plays in its own period after
             the keyed one, never busy, still armed (#10); halt releases within 250 ms
             and disarms;
             every failure stops audio, attempts release and disarms with its cause; a
             late end report inside the bound completes, stays armed and the next
             request plays; a device that never reports the end is released at audio
             end + 1000 ms (FT8 P+14140 <= P+14500, FT4 P+6340 <= P+7000) as
             audioStalled, disarmed deviceLost; the 100 ms buffer starts the program
             within 30 ms and reports the end within 100 ms without underrun; an
             unconfirmed release is indeterminate and recovered off-only; restart is
             disarmed (startup) with nothing pending; watchdog expiry at the configured
             minute; no poll during the transmit hold; one off-only release on close of
             a keyed connection; exact wire shapes and refusals; a radio in TX at boot
             gets exactly one 1C 00 00 then a 1C 00 readback, a radio in RX at boot sees
             zero setter bytes.
             2 — Isolated automated tests; Windows development PC, no audio device,
             radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
        attribute executable : String = "server/tests/transmit_service.rs; server/src/transmit_http_tests.rs; server/src/contact_tests.rs";
    }
    verification 'TC-008-002' {
        doc /* TC-008-002 — Physical controlled FT8 transmit
             CL-009-03, CL-009-04
             Setup: separately approved operation on the HB9BLA IC-7300 (COM3, USB Audio
             CODEC) into a dummy load or the station antenna, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), profile
             with control.ptt cat and the IC-7300 USB output, system clock
             synchronized by the station's SNTP measurement (CL-009-05), the radio's own transmit time-out timer set
             (mandatory, e.g. 3 min) and read back before any keying.
             Steps: arm, transmit FT8 messages in both parities, replace before audio
             start, halt mid-transmission, Tune and its limit, pull the USB audio or CAT
             cable during a transmission, restart the station.
             Oracles: PSK Reporter spots of HB9BLA for the transmitted CQ by
             independent receivers (frequency, time); the radio's TX indication, power
             meter and ALC follow PTT; halt and
             each failure end RF within the settled bound; restart does not transmit.
             5 — Tests with external effects and explicit operator consent; HB9BLA radio
             PC, physical IC-7300. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
    }
    dependency CL_009_03_verified_by_TC_008_003 from 'CL-009-03' to 'TC-008-003';
    dependency CL_009_04_verified_by_TC_008_003 from 'CL-009-04' to 'TC-008-003';
    dependency CL_009_03_verified_by_TC_008_002 from 'CL-009-03' to 'TC-008-002';
    dependency CL_009_04_verified_by_TC_008_002 from 'CL-009-04' to 'TC-008-002';
    requirement 'CL-043-02' {
        doc /* The station estimates its clock offset from the decodes of its live receive
             (WstxTransmit::AirClock): every published decode whose message names a
             concrete sending call (the from call of the standard, field day, RTTY and VHF
             families, the full call of a nonstandard CQ) with a known SNR of at least
             -20 dB and |raw DT| at most 3000 ms is an observation; raw DT is the DT
             against the uncorrected system clock (the capture drift of CL-007-05
             included, the station clock correction of CL-043-03 not). Decodes of the
             profile's own call (any case: the station's own echo) never count. The
             observations of the last 120 s of system time form the estimate (#92,
             operator 2026-11-09: "Our station should always be in the middle"): one
             vote per distinct station, the median of its raw DT plus the current
             correction (its DT against station UTC); no estimate without a vote;
             stations = the votes, median_dt_ms = the median of all votes (no trimming),
             plus = the votes above +100 ms, minus = the votes below -100 ms. The
             estimate is evidence when stations is at least 4 and plus or minus is at
             least 80 % of stations (5 x count >= 4 x stations): the stations differ in
             one direction. Medians of an even count are the floor of the mean of the
             middle pair. A system clock step of more than 100 ms between observations
             (system time elapsed minus monotonic time elapsed) discards all observations
             and the estimate and is subtracted from a nonzero correction, so station UTC
             stays continuous (a step that corrected the system clock leaves 0); a
             correction beyond 3000 ms after that restarts at 0; a correction of 0 stays
             0 (the accepted time is the system clock). */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/air.rs; server/src/recording.rs; server/src/transmit_http.rs";
    }
    dependency CL_043_02_to_FR_006 from 'CL-043-02' to 'FR-006';
    dependency CL_043_02_to_FR_004 from 'CL-043-02' to 'FR-004';
    dependency CL_043_02_verified_by_TC_043_001 from 'CL-043-02' to 'TC-043-001';
    dependency CL_043_02_verified_by_TC_043_004 from 'CL-043-02' to 'TC-043-004';
    dependency CL_043_02_verified_by_TC_092_001 from 'CL-043-02' to 'TC-092-001';
}
