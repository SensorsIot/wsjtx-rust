package WstxRequirementsRadioControl {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    requirement 'CL-008-06' {
        doc /* Separate a versioned factual radio catalogue, compiled typed operations and bounded protocol execution. Catalogue data cannot authorize raw or transmit commands. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_06_to_FR_009 from 'CL-008-06' to 'FR-009';
    dependency CL_008_06_verified_by_TC_009_001 from 'CL-008-06' to 'TC-009-001';
    dependency CL_008_06_verified_by_TC_009_003 from 'CL-008-06' to 'TC-009-003';
    requirement 'CL-022-04' {
        doc /* Selected target cadence: after confirmed released failed attempt wait
             1,2,4,8seconds on successive failures, then8seconds capped. Use one timer
             and one in-flight task under existing station authority; no catch-up or
             backlog. Delays use monotonic time, start after attempt completion and
             confirmed release; reset only after actual fresh successful readback.
             Startup/explicit enable/new valid selected configuration gets one immediate
             attempt; disable/identity change/revocation/invalid commissioning cancels
             timer and current attempt. Re-enable starts a fresh series only after
             release confirmation. Simultaneous browsers do not create extra attempts.
             Preserve setup<=5s, exchange<=1s, cancellation checkpoint<=50ms and ordinary
             RF-context release<=250ms. Bounds are not permissions to assume release.
             Real close failure quarantines the resource; no timed reopen until an
             explicit recovery proves release. Stop/Halt invalidates relevant receive/
             RF-operation tokens and pending resume; CAT housekeeping may not restart
             audio or setters. Late results are identity/generation fenced. Existing
             shared native owner/resource arbitration with RF work stays authoritative.
             Delivered: one station-wide50ms lifecycle tick (one timer, at most one
             tick and one actor in flight) evaluates the grant/commissioning gate under
             the profile store and authority locks, then the policy. A delay starts at
             the first tick observing the confirmed released failure (<=one tick
             after release). Explicit recovery from a failed-close quarantine is a
             station restart; no in-process action clears it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/cat_lifecycle.rs; server/src/recording.rs; server/src/authorization_http.rs; server/src/main.rs";
    }
    dependency CL_022_04_to_FR_008 from 'CL-022-04' to 'FR-008';
    dependency CL_022_04_to_FR_009 from 'CL-022-04' to 'FR-009';
    dependency CL_022_04_to_FR_021 from 'CL-022-04' to 'FR-021';
    dependency CL_022_04_verified_by_TC_022_009 from 'CL-022-04' to 'TC-022-009';
    dependency CL_022_04_verified_by_TC_022_010 from 'CL-022-04' to 'TC-022-010';

    // #44 Automatic radio detection and setup (operator decision 2026-11-01 on issue #44:
    // IC-7300 settings may be written via CI-V, each read back, old values kept for undo).
    // IC-7300 1A 05 item numbers: Icom IC-7300 Full Manual, section 19 "Control command",
    // command table pages 19-4/19-5.
    requirement 'CL-044-01' {
        doc /* POST /radio/detect {v 1, profile_id, boot_id, keying_inhibit_confirmed} (operating access and Origin as POST /receive/stop, exact keys, empty query) enumerates the present COM ports (port, friendly name, USB VID/PID, device instance), at most one detection at a time (a second is refused busy). Opening a port can pulse DTR/RTS before they are disabled (RadioIO: no guarantee of no initial USB-line glitch; USB SEND/CW/RTTY OFF or an independent inhibit before open), so detection is refused confirmation_required unless keying_inhibit_confirmed is true, the operator's confirmation that USB SEND and USB keying are OFF or the radio is on a dummy load; and only ports of a known radio USB bridge (Silicon Labs CP210x, VID 10C4 PID EA60) are opened, others are reported not_radio_bridge and never opened. Each such port is probed read-only: it is opened exclusively under the same per-device ownership claim as the CAT owner, with DTR and RTS disabled before the first byte and kept disabled, at 9600, 19200, 38400 and 115200 baud; at each rate it sends the CI-V broadcast "read transceiver ID" FE FE 00 E0 19 00 FD and, when no reply arrives, the same command addressed to each address of the model table. A reply FE FE E0 <address> 19 00 <id> FD identifies the address, the model and the rate; the station's own echo, collision (FC) frames, other traffic, garbage and timeouts are not replies. Probing never writes any other frame than these ID reads and the menu reads of CL-044-03: never a transmit, frequency, mode or setting command. Model table: 94h IC-7300 (station CAT supported), A4h IC-705, A2h IC-9700, 98h IC-7610 (identified, configured manually); Yaesu, Kenwood and Elecraft text CAT is not probed (listed as manual). A port held by another program or station reports in_use; the port of this station's running CAT owner (CL-022-03/04) is never opened a second time: it is reported from that owner, whose ID and menu reads go through the owner's single I/O lease. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_control/windows.rs; server/src/radio_control/executor.rs; server/src/radio_control/actor.rs; server/src/radio_setup.rs; server/src/main.rs";
    }
    dependency CL_044_01_to_FR_009 from 'CL-044-01' to 'FR-009';
    dependency CL_044_01_to_FR_001 from 'CL-044-01' to 'FR-001';
    dependency CL_044_01_to_FR_008 from 'CL-044-01' to 'FR-008';
    requirement 'CL-044-02' {
        doc /* For each identified radio the detection matches the USB audio endpoints to its serial port by the shared USB parent: an active capture or render endpoint matches when its device has the same Windows container ID as the serial device (not the null container), or when the nearest USB device of both has the same parent hub and that parent is not a root hub. Exactly one matching capture and one matching render endpoint are proposed by their WASAPI endpoint IDs with their friendly names for display; none or several leave that side unproposed (state none or ambiguous). The response holds the proposal of the single supported radio found (none or several: proposal null): {port COMn, model, civ_address, baud, control {mode cat, endpoint icom7300://COMn?baud=<rate>&radio=<address>&controller=e0, ptt cat}, audio {input_device, output_device}}. Applying it is the operator's PUT /profile and the existing receive-only confirmation (CL-022-03); detection writes nothing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_control/windows.rs; server/src/audio/windows.rs; server/src/radio_setup.rs";
    }
    dependency CL_044_02_to_FR_002 from 'CL-044-02' to 'FR-002';
    dependency CL_044_02_to_FR_001 from 'CL-044-02' to 'FR-001';
    requirement 'CL-044-03' {
        doc /* For an identified IC-7300 the detection reads (1A 05, never written while detecting) DATA OFF MOD 0066, DATA MOD 0067, USB MOD level 0065, CI-V transceive 0071, USB SEND 0078, USB keying CW 0079 and USB keying RTTY 0080, and reports each value with guidance: USB SEND, CW and RTTY keying not OFF are blocking (a DTR/RTS line can key the transmitter; this station keys by CI-V 1C 00); DATA MOD other than USB is blocking (MIC/USB is advice); USB MOD level 0 is blocking; CI-V transceive ON is advice; DATA OFF MOD is information. The CI-V baud rate is not readable by CI-V and is reported as the rate the radio answered at. A refused (FA) read is reported unreadable. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_setup.rs";
    }
    dependency CL_044_03_to_FR_009 from 'CL-044-03' to 'FR-009';
    dependency CL_044_03_to_FR_008 from 'CL-044-03' to 'FR-008';
    requirement 'CL-044-04' {
        doc /* "Apply recommended radio settings" is a separate operator action, never part of detection: POST /radio/settings/apply {v 1, profile_id, boot_id, connection_generation} (same access rules) requires this station's CAT owner ready on an IC-7300 (ID read 94h), the transmitter disarmed and the radio reporting RX. It reads the items, plans USB SEND OFF, USB keying CW OFF, USB keying RTTY OFF, DATA MOD USB and CI-V transceive OFF for each item that differs, saves the undo record radio-settings-undo.json in the profile directory {schema_version 1, profile_id, civ_address, items [{item, old, new}]} before the first write (an item already recorded keeps its first old value), then writes each item through the owner's lease and reads it back; a refused write, a mismatching readback or an exchange failure stops the remaining writes and is reported with the items done, and the record then keeps only items that may have changed (recorded before, written in this run, or the failed item unless it was refused FA or refused before its frame), so that undo restores them; an empty record is removed. POST /radio/settings/undo (same body and rules) writes each recorded old value back in reverse order with readback and removes the record only when all succeeded; without a record it is refused nothing_to_undo. Apply and undo never key the transmitter and never change frequency, mode or the profile. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_control/executor.rs; server/src/radio_control/actor.rs; server/src/radio_setup.rs; server/src/profile.rs";
    }
    dependency CL_044_04_to_FR_009 from 'CL-044-04' to 'FR-009';
    dependency CL_044_04_to_FR_008 from 'CL-044-04' to 'FR-008';
    verification 'TC-044-001' {
        doc /* TC-044-001 — Read-only probe on scripted serial ports
             CL-044-01, CL-044-03
             Setup: the probe and the IC-7300 menu reader driven over scripted fake serial transports that record every configure, write and line state, independent hand-written CI-V byte scripts.
             Steps: (a) IC-7300 at 94h answering the broadcast only at 19200, with echo of every frame; (b) IC-705 answering only the addressed read at A4h at 115200; (c) collision frames FE FE FC FC FC FD and garbage bytes before the reply; (d) a silent port; (e) a port whose reads time out; (f) an unknown ID 99h; (g) the IC-7300 menu read with values 0078=01, 0079=00, 0080=02, 0066=00, 0067=03, 0065 0128, 0071=01, and a FA refusal of 0065; (h) a station whose CAT owner holds COM3, other CP210x ports and an FTDI port.
             Expected (hand table): (a) IC-7300, 94h, 19200; (b) IC-705, A4h, 115200, manual; (c) identified as (a); (d) and (e) no_reply after all four rates; (f) unknown_model with ID 99h; every written frame is FE FE 00 E0 19 00 FD, FE FE <table address> E0 19 00 FD or FE FE 94 E0 1A 05 00 <item> FD, the lines are disabled before the first write and never raised; (g) values and guidance: usb_send DTR blocking, rtty RTS blocking, data_mod USB ok, level 128 ok, transceive advice, FA unreadable; (h) COM3 is never opened, reported station_cat from the owner, the CP210x ports probed, the FTDI port not_radio_bridge and never opened.
             2 — Isolated automated tests; Windows development PC, no serial port, radio or RF. */
        // Partial: the line state (lines disabled before the first write, never raised) is not asserted: the fake records configure and write only.
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-044-01';
            verify 'CL-044-03';
        }
        attribute executable : String = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs";
    }
    dependency CL_044_01_verified_by_TC_044_001 from 'CL-044-01' to 'TC-044-001';
    dependency CL_044_03_verified_by_TC_044_001 from 'CL-044-03' to 'TC-044-001';
    dependency CL_044_01_verified_by_TC_044_002 from 'CL-044-01' to 'TC-044-002';
    dependency CL_044_02_verified_by_TC_044_002 from 'CL-044-02' to 'TC-044-002';
    verification 'TC-044-003' {
        doc /* TC-044-003 — Apply recommended radio settings and undo
             CL-044-04
             Setup: the actual Recording owner and CAT actor on a scripted IC-7300 transport holding menu values 0078=01, 0079=00, 0080=02, 0067=00, 0071=01; the actual router on a disposable profile.
             Steps: apply; read the undo record; apply again; undo; undo again; apply with the radio reporting TX; apply with the transmitter armed; apply with a radio that answers FA to 0080; apply with a radio whose readback of 0067 stays 00; apply against an IC-705 ID; HTTP refusals as TC-044-002 (e).
             Expected: writes FE FE 94 E0 1A 05 00 78 00 FD, 00 80 00, 00 67 03, 00 71 00 each acknowledged and read back, never 0079; the record holds {0078 1→0, 0080 2→0, 0067 0→3, 0071 1→0} before the first write; the second apply writes nothing and keeps the record; undo writes 0071=01, 0067=00, 0080=02, 0078=01 in that order and removes the record; the second undo nothing_to_undo; TX and armed refused with no write; FA stops after 0078 with the failed item named and the record reduced to 0078 1→0, a following undo writes 0078=01 and removes the record; TX leaves no record; mismatch reported readback_mismatch; IC-705 refused unsupported_radio; no 1C 00 01, frequency or mode frame in any case.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        // Partial: the undo record is read only after apply returns, not before the first write; no test checks for 1C 00 01, frequency or mode frames in the TX, FA and readback-mismatch cases.
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-044-04';
        }
        attribute executable : String = "server/src/radio_setup_tests.rs";
    }
    dependency CL_044_04_verified_by_TC_044_003 from 'CL-044-04' to 'TC-044-003';
    dependency CL_044_01_verified_by_TC_044_004 from 'CL-044-01' to 'TC-044-004';
    dependency CL_044_02_verified_by_TC_044_004 from 'CL-044-02' to 'TC-044-004';
    dependency CL_044_03_verified_by_TC_044_004 from 'CL-044-03' to 'TC-044-004';
    dependency CL_044_04_verified_by_TC_044_004 from 'CL-044-04' to 'TC-044-004';

    // #44 AGC as a station-managed radio setting (operator decision 2026-11-04 on #44,
    // comment 6626074726: AGC SLOW removed the IC-7300 AGC recovery line between FT8
    // periods, #54) and the operator rule of 2026-11-04: CI-V reads first and changes a
    // setting only when it does not fit. IC-7300 AGC: Icom IC-7300 Full Manual section 19,
    // command table "16 12 AGC" (01 FAST, 02 MID, 03 SLOW; read: the command without data).
    requirement 'CL-044-09' {
        doc /* Every CI-V change of a radio setting by the station is read, compare, write, verify: the station first reads the setting's current value; when it already equals the wanted value no write frame is sent and the read is the confirmation; otherwise it sends the write with the radio in RX (1C 00 00, checked as stated at the end of this clause), requires its ACK (FB; FA is refused radio_rejected) and reads the setting back, a different value being readback_mismatch and a failed readback indeterminate. No write is sent while this station's transmit hold is taken (the CAT owner's single lease excludes it). The transmit switch 1C 00 is a keying action, not a setting, and is not subject to this rule (CL-009 PTT readback). The rule holds for every setter path of the station: the AGC (16 12, CL-044-10); the receive setup of a mode or band selection, where mode (06), DATA mode (1A 06) and frequency (05) are each read first and written only when they differ, and the final state is read again only after a write (with nothing written the three reads are the confirmation); the CAT owner's single setter operations SetFrequency, SetMode and SetData, which answer from the read without a write when the value fits (POST /radio/operation itself refuses these three with selection_unavailable and sends no frame); and the IC-7300 menu writes of Apply recommended radio settings and Undo (1A 05, CL-044-04), where an item already at its value is not written again. A setter whose read is refused (FA) is refused radio_rejected without a write. The RX check of a write is per write for 16 12 and 1A 05; the 05, 06 and 1A 06 setters of a selection's receive setup rely on the selection's single RX read (1C 00) inside its CAT reservation, before the first of them. With all three differing a receive setup is twelve exchanges inside the 5 s composite bound (TC-009-005 proves it at 360 ms per exchange, down from 470 ms for the nine exchanges without the reads); the CAT owner's single setter operations have no RX check of their own, and no route reaches them. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/executor.rs; server/src/radio_control/actor.rs";
    }
    verification 'TC-044-012' {
        doc /* TC-044-012 — Existing CI-V setters read first
             CL-044-09
             Setup: the actual executor on the scripted CI-V transport of TC-009-001 (hand-written replies, every written frame recorded).
             Steps: (a) the CAT owner's SetFrequency 14.074 MHz, SetMode USB FIL2 and SetData ON FIL2 with the radio already there, then each with its read answered FA; (b) SetFrequency with the radio at 7.074 MHz; (c) the receive setup 14.074 MHz USB-D FIL2 with the radio already there; (d) with the radio at USB FIL1, DATA OFF, 7.074 MHz; (e) a 1A 05 write of USB SEND OFF with the item already OFF, and with it at DTR.
             Expected: (a) one read frame each (03, 04, 1A 06) and no setter frame; with FA radio_rejected, the same single frame and the connection open; (b) 03, 05 00 40 07 14 00, 03, the frequency fact unconfirmed when the setter frame is sent and confirmed by the read-back; (c) 04, 1A 06, 03 and nothing else; (d) 04, 06 01 02, 04, 1A 06, 1A 06 01 02, 1A 06, 03, 05 00 40 07 14 00, 03, then the final 04, 1A 06, 03; (e) only FE FE 94 E0 1A 05 00 78 FD, then 1A 05 00 78, 1C 00, 1A 05 00 78 00, 1A 05 00 78; a read answered FA is refused with no further frame.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-09';
        }
        attribute executable : String = "server/tests/radio_control.rs; server/src/radio_control/executor.rs";
    }
    dependency CL_044_09_verified_by_TC_044_012 from 'CL-044-09' to 'TC-044-012';
    dependency CL_044_09_to_FR_009 from 'CL-044-09' to 'FR-009';
    requirement 'CL-044-10' {
        doc /* The radio profile holds the radio settings the station manages: settings.radio {agc FAST|MID|SLOW}, present exactly when settings.control is CAT with an endpoint that is a supported IC-7300 CI-V configuration (the only radio with a known CI-V AGC command; every other control has no settings.radio key and the setting is hidden). GET /profile and the PUT response carry it; PUT /profile refuses settings.radio for an unmanaged control (400 invalid_settings, field radio) and settings.radio.agc outside FAST/MID/SLOW (400 invalid_settings, field settings.radio.agc); a PUT without settings.radio keeps the saved value, or takes SLOW for a newly managed radio. settings.radio is not part of settings.control, so changing it never changes the receive-only CAT confirmation's checked control (CL-022-03); like every profile save it advances the revision, which reconnects CAT. Migration: a profile saved without radio whose control is IC-7300 CAT is read with agc SLOW (the FT8/FT4 default); other profiles stay without it; the file is rewritten only by a later save. The station applies the saved AGC with one read-compare-write-verify exchange (CL-044-09; CI-V read FE FE <address> E0 16 12 FD, write FE FE <address> E0 16 12 <01|02|03> FD) through its CAT owner: once per ready connection (a refusal busy, e.g. the lease held or the radio reporting TX, is tried again after 2 s; any other outcome ends the attempt for that connection) and on each FT8 or FT4 mode selection inside the selection's CAT reservation, after its receive setup and before receive restarts. Nothing is sent while the transmitter is armed, tuning or transmitting (the connection attempt waits for disarm). An AGC failure never fails the selection. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; server/src/main.rs; server/src/radio_agc.rs; server/src/radio_control/setup.rs; server/src/radio_control/executor.rs; server/src/radio_control/actor.rs; server/src/recording.rs; server/src/authorization_http.rs";
    }
    dependency CL_044_10_to_FR_009 from 'CL-044-10' to 'FR-009';
    dependency CL_044_10_to_FR_001 from 'CL-044-10' to 'FR-001';
    verification 'TC-044-008' {
        doc /* TC-044-008 — AGC CI-V read, compare, write, verify on the scripted IC-7300
             CL-044-09, CL-044-10
             Setup: the actual CAT actor and executor on a scripted IC-7300 transport (echo of each frame, hand-written replies) holding AGC 01, 02 or 03; independent byte expectations from the IC-7300 command table.
             Steps: (a) EnsureAgc SLOW with the radio at SLOW; (b) with the radio at MID; (c) with the radio reporting TX and MID; (d) a radio that answers FA to the write; (e) a radio that acknowledges but stays MID; (f) a radio that answers FA to the read; (h) the codec: frames and decoding of 16 12 replies, an unknown code 04.
             Expected: (a) exactly one written frame FE FE 94 E0 16 12 FD, reply SLOW, written false; (b) frames FE FE 94 E0 16 12 FD, FE FE 94 E0 1C 00 FD, FE FE 94 E0 16 12 03 FD, FE FE 94 E0 16 12 FD in this order, written true; (c) busy after the read and the RX check, no 16 12 03 frame; (d) radio_rejected; (e) readback_mismatch; (f) radio_rejected and no write; (h) FAST 01, MID 02, SLOW 03; 04 is no AGC. CAT stays ready in (a)-(f).
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-09';
            verify 'CL-044-10';
        }
        attribute executable : String = "server/src/radio_agc_tests.rs";
    }
    dependency CL_044_09_verified_by_TC_044_008 from 'CL-044-09' to 'TC-044-008';
    dependency CL_044_10_verified_by_TC_044_008 from 'CL-044-10' to 'TC-044-008';
    dependency CL_044_10_verified_by_TC_044_009 from 'CL-044-10' to 'TC-044-009';
    // Operator requirement 2026-11-06 (#44 comment 6679345317, from #22): pragmatic discovery.
    requirement 'CL-044-15' {
        doc /* Coordinator default pending the operator (#44 comment 6682191117): the keying risk of an open is not accepted, so nothing opens automatically without the persisted confirmation. Discovery opens no port at all until the operator has confirmed keying inhibit once: the tick and press of Detect radio (CL-044-01) stores it in radio-keying-confirmed.json of the profile, and Settings > Radio says so until then (radio.tx_level data keying_confirmed). A commissioned saved radio still opens under CL-022-03 through the CAT lifecycle regardless. With the confirmation, on start, before the CAT lifecycle first runs, the station discovers its radio read-only: the same port opening as Detect radio (the per-device ownership claim, DTR and RTS low) and the same probe (CI-V 19 00 only, CL-044-01). A profile with control cat whose saved endpoint's port is present and answers with a radio this station has CAT for keeps its radio, and no other port is opened. Otherwise (the port is held by another station process or another program, is absent or silent), and on a profile never saved (revision 0, control disabled), the ports on a known radio USB bridge are tried in port order, without the saved one and within the budget: a port that cannot be opened is passed over, which is how a radio another station process holds is recognised, and a radio discovery chose or kept is also reserved for the life of the process (a lock per port under radio-reservation), so a station waiting for its confirmation holds it too; a port reserved by another process is passed over, so each process takes the next free radio and more than one transceiver on one PC works. The first that answers with such a radio is saved as the profile's control (icom7300://COMn?baud=b&radio=aa&controller=e0, ptt kept from a CAT control, otherwise cat), with the capture and render endpoints that match it and none otherwise (never the old radio's audio); settings.radio stays or takes the default; its stored Tx level (CL-044-12) and settings undo (CL-044-03) are removed, they belonged to the other radio. This is a profile save, so the revision advances and the receive-only confirmation (CL-022-03) binds to the new control: CAT opens only after the operator confirmed this radio. Nothing is found: nothing changes and the lifecycle keeps retrying the saved endpoint. A control of an operator's saved Disabled, or an endpoint that does not parse, is left alone and no port is opened. Discovery runs once per process start, before the station listens and before anything loads the Tx level or the audio names, so a port that does not answer delays listening by its probe; all of discovery, saved port included, ends within 40 s (each probe is cut at that bound). It does not write a radio setting. WSTX_RADIO_DISCOVERY=off turns it off, for the test stations. Limit: a saved radio reserved by another process with no other radio free changes nothing, and the lifecycle retries it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_setup.rs; server/src/radio_level.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_044_15_to_FR_009 from 'CL-044-15' to 'FR-009';
    verification 'TC-044-020' {
        doc /* TC-044-020 — Discovery on start
             CL-044-15
             Setup: the actual profile store and authorization owner, a detection hardware double of ports, held ports, radios and audio endpoints, recording every frame.
             Steps: (a) saved COM3 answers, COM5 too; (b) saved COM3 held, COM4 held, COM5 silent, COM6 an IC-7300 with matching audio; (c) saved silent, the other held; (d) an operator's saved Disabled with a radio present; (e) a profile never saved with an FTDI board, an IC-705 and an IC-7300; (f) three stations in turn on two free radios, the third with a saved one already reserved; (g) no confirmation with a radio present, never saved and saved, then Detect radio without and with the tick; (h) three silent ports with a 200 ms budget.
             Expected: (a) nothing saved, only COM3 opened; (b) control COM6 with the probed rate and address, a disabled ptt kept, the matching endpoints, settings.radio kept, the Tx level and undo files gone, revision +1, ports opened 3, 4, 5, 6; on the actual authorization owner, a commissioned control moved this way gives CommissioningRequired, no commissioning, safety revision +1 and the new checked control; (c) nothing saved; (d) no port opened; (e) COM6, ptt cat, the FTDI board never opened; (f) COM3, then COM6, and the third keeps its saved control; (g) no port opened, keying_confirmed false; no file after the refused Detect, the file and keying_confirmed true after the other, and only then the saved port is opened; (h) only the first opened, over in under 2 s; in all of them only 19 00 frames are written.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-15';
        }
        attribute executable : String = "server/src/radio_setup_tests.rs; server/src/auth_tests.rs";
    }
    dependency CL_044_15_verified_by_TC_044_020 from 'CL-044-15' to 'TC-044-020';
    verification 'TC-044-022' {
        doc /* TC-044-022 — The one-time confirmation in Settings
             CL-044-15
             Setup: candidate server and Chromium; radio.tx_level events injected.
             Steps: inject keying_confirmed false, then true.
             Expected: the Detect radio section says discovery is off until confirmed once, then that it is on.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-15';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_15_verified_by_TC_044_022 from 'CL-044-15' to 'TC-044-022';
    verification 'TC-044-021' {
        doc /* TC-044-021 — Discovery on HB9BLA
             CL-044-15
             Setup: the gated candidate on HB9BLA, the IC-7300 on COM3, keying inhibit confirmed through Detect radio on both profiles; a second station process on its own profile; the operator's consent.
             Steps: start the station with COM3 saved; start a second process with COM3 saved while the first holds it; start it with a second transceiver connected, if one is available; with two transceivers, start two processes on unconfirmed CAT, so one holds its radio only by reservation. The second-transceiver steps can't run on this station, which has only one radio.
             Expected: the first keeps COM3; the second reports port_in_use with nothing changed when no other radio is free, and takes the second transceiver when one is; a radio reserved but not yet held is passed over.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-15';
        }
    }
    dependency CL_044_15_verified_by_TC_044_021 from 'CL-044-15' to 'TC-044-021';
    dependency CL_044_09_verified_by_TC_044_011 from 'CL-044-09' to 'TC-044-011';
    dependency CL_044_10_verified_by_TC_044_011 from 'CL-044-10' to 'TC-044-011';
}
