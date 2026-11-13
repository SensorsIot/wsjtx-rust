package WstxSpecialActivities {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-007';
    private import WstxArchitecture::'FR-008';
    private import WstxRequirements::AutomationState;
    private import WstxArchitecture::'FR-024';
    private import WstxArchitecture::'FR-004';
    private import WstxArchitecture::'FR-005';
    requirement 'CL-111-10' {
        doc /* Hound limits. While the Hound still calls with Tx1, the transmit state goes off (cause txWatchdog) when 300 s have passed since the last accepted start. Every accepted start restarts the 300 s, a run's start included. reset_repetitions does not restart it. The reply timeout ends at every accepted start and at completion; nothing else about WstxSpecialActivities::HoundOperation changes, "a Fox report never switches transmission on" included. Details: WstxSpecialActivities::HoundOperation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs";
    }
    dependency CL_111_10_to_FR_007 from 'CL-111-10' to 'FR-007';
    dependency CL_111_10_to_FR_008 from 'CL-111-10' to 'FR-008';
    verification 'TC-111-016' {
        doc /* TC-111-016 — Hound 300 s
             CL-111-10
             Setup: as TC-111-001, the activity hound, a Fox KH7Z, the repetition limit 99; the Hound calling with Tx1.
             Steps: the start; a second reply at 150 s; a run's start at 150 s; reset_repetitions at 150 s; the Fox's report before 300 s (Tx3 next).
             Expected (CL-111-10): off with txWatchdog at 300 s after the start, not at 299 s; the second reply moves it to 450 s; a run's start restarts it the same way; reset_repetitions does not move it; with Tx3 next nothing stops at 300 s.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-111-10';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_10_verified_by_TC_111_016 from 'CL-111-10' to 'TC-111-016';
    requirement 'CL-024-02' {
        doc /* #24 S2a. An operator-chosen special activity of none, WW Digi, ARRL Digi or NA VHF generates "CQ WW"/"CQ TEST" and the grid exchange (Tx2 grid, Tx3 "R grid"), sequences on the received grid and R+grid, logs on RRR/RR73/73 like any contact and shows dupes through the existing worked-before indication per band and mode; UDP Status carries the activity as WSJT-X's special operation value; station automation does not start in a contest activity (observe only). Details: WstxSpecialActivities::GridExchangeContest. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/udp.rs; client/contact.js";
    }
    dependency CL_024_02_to_FR_024 from 'CL-024-02' to 'FR-024';
    verification 'TC-024-005' {
        doc /* TC-024-005 — Grid-exchange contests through the contact engine
             CL-024-02
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); hand-authored standard rows; HB9BLA JN47AA; the station fixture over POST /contact/command and its UDP Status.
             Steps: (a) set_activity ww_digi, Enable Tx with no partner, select the caller "HB9BLA S52XYZ JN76", the partner sends "HB9BLA S52XYZ RR73"; (b) set_activity na_vhf, select "CQ TEST K1ABC FN42", Enable Tx, the CQer sends "HB9BLA K1ABC R FN42"; (c) arrl_digi with my call DL/HB9BLA; (e) during a running CQ with an edited Tx6 set ww_digi, then set_report; with an active contact switch none, ww_digi, none; start station automation with ww_digi set; (d) set_activity none, an unknown activity "q65_pileup" ("eu_vhf" until #99, TC-099-002), and the settings and UDP Status of each activity.
             Expected: (a) Tx6 "CQ WW HB9BLA JN47"; the caller's grid selects Tx3 "S52XYZ HB9BLA R JN47" (rogerReport) with Tx2 "S52XYZ HB9BLA JN47"; after RR73 Tx5 is sent, the contact completes and is logged with grid JN76 and no reports; (b) Tx6 "CQ TEST HB9BLA JN47", "K1ABC HB9BLA JN47" sent (as Tx2 since #24 S2b: Tx1 is disabled in contests), the R FN42 moves to Tx4 "K1ABC HB9BLA RRR", which completes after it is sent and the partner's 73; (c) Tx6 "CQ DL/HB9BLA" and Tx2 "K1ABC <DL/HB9BLA> JN47"; (d) none restores the report exchange (Tx2 "K1ABC HB9BLA -15"), q65_pileup is refused invalid_request field activity, settings.activity reads the choice and UDP Status special operation 0/1/5/8; (e) Tx6 becomes "CQ WW HB9BLA JN47" and a later set_report keeps it, the active contact's Tx2/Tx3 switch between "-NN"/"R-NN" and "JN47"/"R JN47", and automation start is refused not_ready activity.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_02_verified_by_TC_024_005 from 'CL-024-02' to 'TC-024-005';
    verification 'TC-024-006' {
        doc /* TC-024-006 — The Activity choice in the QSO fold-out
             CL-024-02
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out; read the Activity choice with settings.activity ww_digi; choose ARRL Digi.
             Expected: the choice offers None, NA VHF, WW Digi and ARRL Digi (since #24 S2b also Field Day and RTTY Roundup, TC-024-009, since #24 S4b also Hound, TC-024-013, since #99 also EU VHF after NA VHF, TC-099-003) and shows WW Digi; choosing sends set_activity {activity arrl_digi}; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_02_verified_by_TC_024_006 from 'CL-024-02' to 'TC-024-006';
    requirement 'CL-024-03' {
        doc /* #24 S2b. Field Day (i3=0 n3=3/4) and FT/RTTY Roundup (i3=3) exchanges come from the configured class/section and state/province or DX serial, with 5x9 reports, FT4 "TU;", and pack/unpack identical to ft8code. Contest exchange values go into ADIF CONTEST_ID/STX/SRX/STX_STRING/SRX_STRING/CLASS/ARRL_SECT/STATE as WSJT-X AdifQso writes them. Slice S2b1: the two packer families, exact against ft8code and ft4sim (WstxMessageEncode::PackMessage), so the transmit owner accepts such a message; the contact engine still refuses them in its slots; unpack and pack share the WSJT-X 3.3.0-beta5 section (86) and RTTY exchange (171) tables, which replace the QEX 2020 tables (fixtures/decoder/protocol-data/arrl_rac_sections.json and states_provinces.json). Slice S2b2: the field_day and rtty activities with their configured exchange and the contest serial, the 5x9 mapping, FT4 TU;, the Tx2 start of every contest activity, sequencing on the received exchange, the contact's exchange_sent/exchange_rcvd, the ADIF contest fields of the log (WstxSpecialActivities::ContestExchange, LogRecord), UDP Status special operation 3/4 and the Activity choice with its Exchange entry; station automation still does not start in a contest activity. Cabrillo is not offered (operator decision S2b-1). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/pack.rs; server/src/decoder/payload.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs; server/src/logbook_http.rs; client/contact.js";
    }
    dependency CL_024_03_to_FR_004 from 'CL-024-03' to 'FR-004';
    dependency CL_024_03_to_FR_024 from 'CL-024-03' to 'FR-024';
    dependency CL_024_03_to_FR_005 from 'CL-024-03' to 'FR-005';
    verification 'TC-024-007' {
        doc /* TC-024-007 — Field Day and RTTY Roundup messages pack exactly as WSJT-X
             CL-024-03
             Setup: fixtures/transmit/ft8code-vectors.json and fixtures/transmit/ft4/ft4sim-vectors.json regenerated by fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe (beta4 output identical) and ft4sim.exe, with 20 Field Day and RTTY Roundup messages WSJT-X encodes unaltered (counts 1, 10, 16, 17, 32; classes A-F; R; sections EMA, NB, WI, DX; TU;; serials 0001, 0013, 7999; multipliers MA, WI, ON, PEI, X99) and 19 contest shapes it alters or rejects (a nonstandard, /R or <CALL> call slot; counts 0, 06, 33; class G; Q-prefix call; serials 0000, 8000; reports 519; exchanges 13, DX; TU; without an exchange, a repeated TU;, a missing exchange).
             Steps: pack and encode every fixture message for FT8 and FT4; read the family, i3/n3 and refusal of named messages; unpack the fixed payload-boundary cases of fixtures/decoder/payload-boundary-cases.json (fixtures/decoder/independent-vector-tool/boundary_cases.py) for section 84/85/86/87 and exchange 8065/8066/8171/8172.
             Expected: for every message the oracle encodes unaltered as 0.3, 0.4 or 3., bits, CRC, parity and tones (FT8) and bits, codeword and tones (FT4) equal the oracle and the text equals its rendering; families fieldDay (n3 3 for counts 1-16, 4 for 17-32) and rttyRoundup; every altered or rejected contest shape is refused, a hashed contest call slot (PJ4/K1ABC, K1ABC/R) as notExact, "K1ABC RR73; W9XYZ <KH1/KH7Z> -08" still unsupportedFamily; sections 84 DX, 85 PE and 86 NB and exchanges 8065 DC, 8066 DR and 8171 X99 decode, 87 and 8172 are invalid_payload.
             2 — Isolated automated tests; Windows development PC, no radio, audio, RF or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs; server/tests/transmit_ft4_vectors.rs; server/tests/decoder_vectors.rs";
    }
    dependency CL_024_03_verified_by_TC_024_007 from 'CL-024-03' to 'TC-024-007';
    verification 'TC-024-008' {
        doc /* TC-024-008 — Field Day and RTTY Roundup through the contact engine and the log
             CL-024-03
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, unpack, row reader); HB9BLA JN47AA; the station fixture over POST /contact/command with its log and UDP Status; the logbook record validation.
             Steps: (a) set_activity field_day "1a  ema", Enable Tx with no partner, select the caller "HB9BLA K1ABC 2A WI", the partner answers my Tx3 with "HB9BLA K1ABC RR73"; (b) set_activity rtty "DX", select "CQ RU W9XYZ EN37" with SNR -3, Enable Tx, the CQer sends "TU; HB9BLA W9XYZ R 579 MA", then a second selection; (c) rtty "MA" in FT4: after my Tx3 and the partner's RR73, select the next caller 0.5 s after the RR73 was counted, and in a second run 3 s after it; (d) refusals: field_day without an exchange or with "0A EMA", "33A EMA", "1G EMA", "1A XX" or a non-ASCII character; rtty "DXX" or "8000" (a fixed "0013" is accepted); an exchange with ww_digi; a nonstandard DX call in field_day; a Field Day row while rtty is set; (e) settings and contact snapshot keys, UDP Status special operation; edit_message tx2 "K1ABC HB9BLA 3A WI"; (f) validate_record of the logged records, RST 519 and a contest field with '<'; history record keys.
             Expected: (a) exchange "1A EMA", Tx6 "CQ FD HB9BLA JN47", the caller's exchange selects Tx3 "K1ABC HB9BLA R 1A EMA" with exchange_rcvd "2A WI"; after their RR73 Tx5 is sent, the contact completes and is logged with STX_STRING "1A EMA", CONTEST_ID ARRL-FIELD-DAY, SRX_STRING "2A WI", CLASS 2A, ARRL_SECT WI and no RST; serial 2 afterwards; (b) Tx6 "CQ RU HB9BLA JN47", the selection starts with Tx2 "W9XYZ HB9BLA 559 0001" (Tx1 disabled), the R exchange moves to Tx4, exchange_rcvd "579 MA", the record has RST_SENT 559, RST_RCVD 579, STX 0001, STATE MA; the second selection's Tx2 carries 0002; (c) Tx3 "TU; W9XYZ HB9BLA R 559 MA" in the first run only; (d) invalid_request field exchange, invalid_call, the row is classified other; (e) settings activity/exchange/serial, contact exchange_sent/exchange_rcvd, special operation 3 and 4; the edited Field Day text is accepted unaltered; (f) the records are valid, RST 519 and '<' are refused, history records carry stx..state.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/logbook_tests.rs";
    }
    dependency CL_024_03_verified_by_TC_024_008 from 'CL-024-03' to 'TC-024-008';
    verification 'TC-024-009' {
        doc /* TC-024-009 — The Field Day / RTTY Roundup choice and its Exchange entry
             CL-024-03
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out with settings activity rtty, exchange DX, serial 7; enter "1A EMA" in the Exchange entry and choose Field Day; change the exchange to "2B WI".
             Expected: the choice offers None, NA VHF, WW Digi, ARRL Digi, Field Day and RTTY Roundup (since #99 also EU VHF, TC-099-003); it shows RTTY Roundup, the entry DX and the next serial 0007; choosing sends set_activity {activity field_day, exchange "1A EMA"}, the change sends {field_day, "2B WI"}; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_03_verified_by_TC_024_009 from 'CL-024-03' to 'TC-024-009';
    requirement 'CL-024-04' {
        doc /* #24 S4. Classic Hound follows HoundTransmissionPolicy: second-period only, Tx1/Tx3 only, random 1000-2998 Hz calling when the Tx offset is below 999 Hz, Tx3 on the Fox frequency after the Fox's report and Fox +-300 Hz on a repeat, completion and logging on the Fox's RR73 in standard or 0.1 form, the reply timeout and the Hound watchdog, and Fox selection limited to rows decoded at :00/:30 (not R+report rows of other Hounds). set_activity hound is FT8 only; UDP Status special operation 7; station automation does not start as a Hound. Slice S4a is the 0.1 hashdx10 rule (CL-024-01, TC-024-010); slice S4b is the Hound operation (WstxSpecialActivities::HoundOperation). SuperFox (S5) stays excluded. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_024_04_to_FR_024 from 'CL-024-04' to 'FR-024';
    verification 'TC-024-011' {
        doc /* TC-024-011 — Classic Hound through the contact engine
             CL-024-04
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, or 0.1 payloads built from their fields, unpack, HashTable fill-in with my call HB9BLA and the DX call, row reader); a deterministic random source; HB9BLA JN47AA; Fox KH7Z.
             Steps: (a) set_activity hound with parity even and Tx 800 Hz; select "CQ KH7Z BL01" at 812 Hz (:00) with SNR -9, Enable Tx; the Fox sends "HB9BLA KH7Z -12" at 812 Hz with SNR -7; my Tx3 is sent; the Fox is silent one period; it sends "HB9BLA KH7Z RR73"; (b) the same with the Fox at 450 Hz, its report inside "W9XYZ RR73; HB9BLA <KH7Z> -12" and its RR73 inside "HB9BLA RR73; K1ABC <KH7Z> -08"; a repeated Fox report after my first Tx3; (c) refusals: Enable Tx without a DX call, a row at :15, "KH7Z W9XYZ R-05" at :00, a 0.1 row, set_parity even, choose_next tx2/tx4/tx5/tx6, choose_next tx1 with Skip Tx1 on; a station mode change to FT4, then set_activity hound; (d) not counted: "HB9BLA K1ABC RR73" (not the DX call), a 0.1 RR73 and a 0.1 report to me with another hashed call, a Fox report while Tune is on (the transmit owner armed with Tune and no request); (e) the reply timeout 165 s after the Fox's report, and again with Enable Tx turned off and on 150 s after it, the Hound watchdog after 300 s of Tx1, and a station Tx watchdog of 1 unanswered call while Tx3 repeats (99 calls for the Hound watchdog case); (f) with Tx 1500 Hz Tx1 keeps its offset.
             Expected: (a) parity odd and Hold Tx on; the selection keeps Tx 800 Hz and gives Tx1 "KH7Z HB9BLA JN47"; Tx1 goes out in the odd period at the random offset within 1000..2998 Hz; the report gives report_rcvd -12, Tx3 "KH7Z HB9BLA R-07" at 812 Hz, the repeat at 512 Hz; the RR73 completes the contact with Enable Tx off (contactCompleted) and logs KH7Z with RST_SENT -07 and RST_RCVD -12; (b) Tx3 at 450 Hz, the repeat at 750 Hz, a repeated report back to 450 Hz, the 0.1 RR73 completes and logs; (c) no_contact for Enable Tx, row_not_standard for the 0.1 row, state_conflict for the others, Tx1 stays next with Skip Tx1, the activity reads none after the change to FT4 and hound is then state_conflict; (d) nothing changes; while Tune only the Fox frequency is recorded; (e) Enable Tx off with cause txWatchdog at each deadline, not before; the slot stays tx3 after the reply timeout, the re-armed station stays armed past 165 s, tx1 after the Hound watchdog (Tx watchdog not expired), and the expired Tx watchdog returns the slot to tx1; (f) 1500 Hz unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_011 from 'CL-024-04' to 'TC-024-011';
    verification 'TC-024-012' {
        doc /* TC-024-012 — Hound through the station: wire, UDP Status, automation and the 0.1 row reader
             CL-024-04
             Setup: the station fixture over POST /contact/command and GET /contact with its UDP Status; the station's row reader on published 0.1 records; station automation readiness.
             Steps: set_activity hound, then with an exchange; read settings and UDP Status; read a published "HB9BLA RR73; K1ABC <KH7Z> -08" record; start station automation with hound set.
             Expected: settings.activity hound, parity odd, hold_tx true; an exchange is refused invalid_request field exchange; UDP Status special operation 7; the row reader gives the 0.1 fields (RR73 to HB9BLA, report to K1ABC -08, hashed <KH7Z>) and no standard message; automation start not_ready activity.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_012 from 'CL-024-04' to 'TC-024-012';
    verification 'TC-024-013' {
        doc /* TC-024-013 — The Hound choice in the QSO fold-out
             CL-024-04
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out with settings activity hound; choose Hound from None.
             Expected: the choice offers Hound after RTTY Roundup and shows it; choosing sends set_activity {activity hound} without an exchange; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_04_verified_by_TC_024_013 from 'CL-024-04' to 'TC-024-013';
    verification 'TC-024-014' {
        doc /* TC-024-014 — Hound QSO with a scripted Fox over an audio loopback (no RF)
             CL-024-04
             Setup: the strongest automated equivalent of two station instances over an audio loopback: the Hound is the actual contact engine and #9 transmit owner core on a virtual UTC clock whose hardware double captures the 48 kHz waveform it plays (no PTT, audio device or radio); the scripted Fox synthesizes its FT8 frames (standard texts packed, its 0.1 frames built from their fields) with the station's waveform generator. Each 15 s period is the sum of the frames of that period plus noise at 12 kHz (the Hound's own audio decimated from 48 kHz), decoded by the station's FT8 decoder; the Hound's records pass the station's HashTable (my call, learned calls, the DX call) and row reader, the Fox decodes the Hound's audio with the same decoder. No second process, sound card or virtual cable.
             Steps: Fox "CQ KH7Z BL01" at 800 Hz; the operator selects it and enables Tx with Tx 700 Hz; the Fox answers the decoded Tx1 with "W9XYZ RR73; HB9BLA <KH7Z> -12"; it ignores the first decoded Tx3 for one period and answers the repeat with "HB9BLA RR73; K1ABC <KH7Z> -08".
             Expected: the Fox decodes "KH7Z HB9BLA JN47" in the odd period at a frequency within 1000..2998 Hz (+-3 Hz of the planned random offset); the Hound decodes the 0.1 report with <KH7Z> filled in; the Fox decodes the Hound's "KH7Z HB9BLA R-NN" at 800 Hz (+-3 Hz) and the repeat at 500 Hz; after the 0.1 RR73 the Hound's contact is completed, Enable Tx off and KH7Z logged with RST_RCVD -12; the Hound never transmitted in an even period.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. The level-4 acceptance (two station processes over a physical or virtual audio loopback) and the level-5 on-air QSO with a classic DXpedition are opportunistic and not part of this test. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_014 from 'CL-024-04' to 'TC-024-014';
    // #99 EU VHF contest message: send (#24 S3, operator 2026-11-09).
    requirement 'CL-099-01' {
        doc /* #99. The transmit packer accepts the WSJT-X EU VHF contest message (i3=5) "<CALL1> <CALL2> [R] 5nSSSS GRID6" exactly as WSJT-X 3.3.0-beta5 packs it (two hashed calls of 3-11 characters, report 52-59, serial 0001-2047, 6-character locator), with bits, CRC, parity and tones identical to ft8code and ft4sim, and refuses every shape WSJT-X rejects for this family. Details: WstxMessageEncode::PackMessage (family euVhf). */
        attribute implementation : String = "server/src/transmit/pack.rs";
        attribute coverage : ImplementationState = ImplementationState::implemented;
    }
    dependency CL_099_01_to_FR_024 from 'CL-099-01' to 'FR-024';
    dependency CL_099_01_to_FR_004 from 'CL-099-01' to 'FR-004';
    requirement 'CL-099-02' {
        doc /* #99. The operator-chosen activity eu_vhf (refused without a 6-character profile locator or with a profile callsign over 11 characters; no contact starts whose two calls exceed 16 characters together, the 37-character limit of Tx3) generates CQ TEST, Tx1 with the full calls, Tx2/Tx3 "<DX> <MYCALL> [R] 5nSSSS GRID6" from the report, the station contest serial and the profile locator's first six characters, sequences on the partner's EU VHF message counted by the hashes of my call and the DX call, makes EU VHF rows selectable, logs STX, SRX, the two-digit RS and the 6-character grid, carries UDP Status special operation 2, answers CQ TEST as its own directive and is offered in the Activity choice. Details: WstxSpecialActivities::EuVhfExchange. */
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs; server/src/mcp.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::implemented;
    }
    dependency CL_099_02_to_FR_024 from 'CL-099-02' to 'FR-024';
    dependency CL_099_02_to_FR_005 from 'CL-099-02' to 'FR-005';
    verification 'TC-099-001' {
        doc /* TC-099-001 — EU VHF messages pack exactly as WSJT-X
             CL-099-01
             Setup: fixtures/transmit/ft8code-vectors.json and fixtures/transmit/ft4/ft4sim-vectors.json extended by fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe and ft4sim.exe (the independent oracle; the station's code never produces a vector), with EU VHF messages WSJT-X encodes unaltered: "<K1ABC> <HB9BLA> 550001 JN37VL", "<HB9BLA> <K1ABC> R 590003 FN42AX", "<G4ABC/P> <HB9BLA> 522047 IO91NP" (lowest report, highest serial, a /P call), "<PJ4/K1ABC> <HB9BLA> 590123 FK52UD" (a compound call), "<ABC> <ABCDEFGHIJK> 570010 AA00AA" (3 and 11 characters, lowest grid), "<HB9BLA> <K1ABC> 590001 RR99XX" (highest grid) and the lower-case "<k1abc> <hb9bla> 550001 jn37vl"; and shapes it rejects or alters for this family: serials 0000 and 2048, reports 51 and 60 (510001, 600001), a five- and a seven-digit exchange, a 4-character grid, grid "SS00AA", one call without brackets, a call of 2 characters ("<AB> <HB9BLA> 550001 JN37VL") and one of 12 characters in brackets, "X" in place of R, a sixth word, and the 38-character "<K1ABCDEFGHI> <HB9BLA> R 550001 JN37VL" (11 + 6 call characters with R; a direct case against the contract limit, not an oracle vector, since ft8code takes at most 37 characters) beside the 37-character "<K1ABCDEFGH> <HB9BLA> R 550001 JN37VL" (10 + 6), which is encoded.
             Steps: pack and encode every fixture message for FT8 and FT4; read family, i3 and refusal; unpack each packed payload with a hash table that knows the two calls and with none.
             Expected: for every message the oracle encodes unaltered as i3=5 the family is euVhf, i3 5, and bits, CRC, parity and tones (FT8) and bits, codeword and tones (FT4) equal the oracle; the text equals its normalized rendering; the unpack with the table renders the same tokens and with none "<...> <...> R 590003 FN42AX"; every rejected shape is not packed as euVhf (it is refused, or packed in the family the oracle chose, with the oracle's bits); the 38-character message is refused tooLong.
             2 — Isolated automated tests; Windows development PC, no radio, audio, RF or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-099-01';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs; server/tests/transmit_ft4_vectors.rs";
    }
    dependency CL_099_01_verified_by_TC_099_001 from 'CL-099-01' to 'TC-099-001';
    verification 'TC-099-002' {
        doc /* TC-099-002 — EU VHF contacts through the contact engine and the log
             CL-099-02
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, unpack, HashTable fill-in with my call and learned calls, row reader); profile HB9BLA JN37VL; the station fixture over POST /contact/command with its log and UDP Status; the logbook record validation.
             Steps: (a) set_activity eu_vhf, Enable Tx with no partner; the caller "HB9BLA K1ABC FN42" with SNR -6 is answered; the partner sends "<HB9BLA> <K1ABC> R 590007 FN42AX", then "HB9BLA K1ABC 73"; (b) select "CQ TEST W9XYZ EN37" with SNR +3, Enable Tx; the CQer sends "<HB9BLA> <W9XYZ> 590003 EN37AB", then "HB9BLA W9XYZ RR73"; (c) the same as (a) in FT4; (d) not counted while in a contact with K1ABC: an EU VHF message to me from another call, one from K1ABC to another call, one with an unresolved 'from', and an EU VHF message to me while the activity is none; (e) refusals: set_activity eu_vhf with the profile locator JN37 and with an empty locator, with the 12-character profile callsign VP2E/HB9BLAX, and with an exchange; enter_dx of a 12-character DX call; a serial of 2048, then set_report; the profile locator changed to JN37 after the choice during a contact with K1ABC, then set_report -10; select an EU VHF row with an unresolved 'from', and one while the activity is ww_digi; (f) select the EU VHF row "<HB9BLA> <DL1ABC> 590012 JO62QM" addressed to me, and "<W9XYZ> <DL1ABC> R 570004 JO62QM" not addressed to me; edit_message tx2 "<K1ABC> <HB9BLA> 590001 JN37VL" and "<K1ABC> <HB9BLA> 590000 JN37VL"; (g) settings, contact snapshot, UDP Status, the directive of "CQ TEST K1ABC FN42"; validate_record of the logged records and of an RST "51" and "60"; (h) the 37-character limit with my call HB9BLA: enter_dx 3D2AG/K1AB (16 call characters together) and 3D2AG/K1ABC (17), then select a row "CQ 3D2AG/K1ABC" (i3=4); with the activity none, a contact with 3D2AG/K1ABC, then set_activity eu_vhf; (i) the profile locator JN37VL12, set_activity eu_vhf, select "CQ TEST K1ABC FN42" with SNR -6.
             Expected: (a) Tx6 "CQ TEST HB9BLA JN37"; the caller's grid gives Tx2 "<K1ABC> <HB9BLA> 550001 JN37VL" (report -06, n 5); the R exchange moves to Tx4 "K1ABC HB9BLA RRR", exchange_rcvd "590007 FN42AX", dx_grid FN42AX; after the 73 the contact completes and the record has GRIDSQUARE FN42AX, STX 0001, SRX 0007, RST_SENT 55, RST_RCVD 59, no STX_STRING/SRX_STRING; settings.serial 2; (b) the selection starts with Tx1 "W9XYZ HB9BLA JN37" (Tx1 enabled); the exchange moves to Tx3 "<W9XYZ> <HB9BLA> R 560002 JN37VL" (report +03, n 6); after RR73 Tx5 "W9XYZ HB9BLA 73" is sent, completed, STX 0002, SRX 0003; (c) the same texts with Tx4 RR73 and FT4 requests; (d) nothing changes; (e) profile_incomplete field locator (twice), invalid_call field callsign and invalid_request field exchange, the activity unchanged each time; invalid_call; out_of_range field serial for set_report, the report and messages unchanged; profile_incomplete field locator for set_report -10, the report and all six messages unchanged; row_not_standard (twice); (f) DL1ABC with dx_grid JO62QM, exchange_rcvd "590012 JO62QM" and first slot tx3; then DL1ABC from the second row with first slot tx1 and exchange_rcvd null; the valid edit is accepted unaltered, serial 0000 invalid_message; (g) settings.activity eu_vhf with exchange null and the serial, contact exchange_sent/exchange_rcvd, UDP Status special operation 2, the CQ TEST answerable without directive_confirmed; the records are valid, RST "51" and "60" are refused; (h) 3D2AG/K1AB is accepted and its Tx3 "<3D2AG/K1AB> <HB9BLA> R 530001 JN37VL" has 37 characters and packs; 3D2AG/K1ABC is refused invalid_call by enter_dx and by the selection, no contact starts and the previous one is unchanged; set_activity eu_vhf is refused invalid_call field dx_call and the activity stays none; (i) Tx6 "CQ TEST HB9BLA JN37", Tx1 "K1ABC HB9BLA JN37", Tx2 "<K1ABC> <HB9BLA> 550001 JN37VL".
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-099-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_099_02_verified_by_TC_099_002 from 'CL-099-02' to 'TC-099-002';
    verification 'TC-099-003' {
        doc /* TC-099-003 — The EU VHF choice in the QSO fold-out
             CL-099-02
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded; a recorded refusal reply.
             Steps: open the fold-out with settings activity eu_vhf, serial 12; choose EU VHF from None; answer the choice with the refusal profile_incomplete field locator.
             Expected: the choice offers EU VHF after NA VHF and shows it; the next serial 0012 is shown and the Exchange entry is not sent; choosing sends set_activity {activity eu_vhf} without an exchange; the refusal is shown in the error field and the choice returns to the station's setting; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-099-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_099_02_verified_by_TC_099_003 from 'CL-099-02' to 'TC-099-003';
    verification 'TC-099-004' {
        doc /* TC-099-004 — EU VHF QSO with a WSJT-X station on the air
             CL-099-01, CL-099-02
             Setup: HB9BLA IC-7300 at 1 W on 10, 15, 20 or 40 m (the antenna's bands), profile locator JN37VL, eu_vhf chosen, during a contest that uses EU VHF (SARL HF Digital, WIA Ross Hull) or a scheduled partner running WSJT-X in EU VHF Contest mode.
             Steps: call CQ TEST and complete a QSO with a caller; answer a CQ TEST and complete a QSO.
             Expected: the partner's WSJT-X decodes the station's Tx2/Tx3 with both calls resolved and moves on them; both QSOs complete and are logged with STX, SRX, RS and the partner's 6-character locator; the partner's log (or the contest's log check) shows my serial and JN37VL.
             5 — Tests with external effects and explicit operator consent; HB9BLA radio PC, physical IC-7300. Opportunistic, not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-099-01';
            verify 'CL-099-02';
        }
    }
    dependency CL_099_01_verified_by_TC_099_004 from 'CL-099-01' to 'TC-099-004';
    dependency CL_099_02_verified_by_TC_099_004 from 'CL-099-02' to 'TC-099-004';
    enum def SpecialActivity { enum none; enum na_vhf; enum eu_vhf; enum ww_digi; enum arrl_digi; enum field_day; enum rtty; enum hound; }
    attribute def GridExchangeContest {
        attribute activity : SpecialActivity;
        doc /* #24 S2a, CL-024-02 (WSJT-X 3.3.0-beta5 Settings > Advanced > Special operating
             activity; MW genCQMsg ~9610-9631, genStdMsgs ~9758-9760 sent=my_grid;
             DecodedMessageReaction.cpp ~533-547; make-qso.adoc Contest Messages). The
             operator chooses the station's activity with set_activity {activity}: none
             (default), na_vhf (NA VHF), ww_digi (WW Digi) or arrl_digi (ARRL Digi). It is
             a station setting of this boot (not saved; a restart starts with
             none) and applies to the next message generation; the current contact's
             Tx2-Tx4 and Tx6 are regenerated at once (a report or tx4 change still
             replaces only Tx2-Tx4). Station automation does not start while an activity
             other than none is set (WstxMcp, not_ready activity): it only observes. Like
             the auto_seq and call readiness, this is checked when a run starts; choosing
             an activity during a running automation run does not stop it (the operator
             chooses the contest before starting, and HALT or Stop ends a run). With an activity other than none:
             Tx6 is "CQ TEST MYCALL GRID4" (na_vhf, arrl_digi) or "CQ WW MYCALL GRID4"
             (ww_digi) when MYCALL is standard (a nonstandard MYCALL keeps "CQ MYCALL");
             the exchange is my grid instead of the report: Tx2 is the Tx1-Tx3 stem of
             StandardMessageSet plus GRID4 and Tx3 the stem plus "R GRID4" (e.g. "K1ABC
             HB9BLA JN47", "K1ABC HB9BLA R JN47"); Tx1, Tx4 and Tx5 are unchanged. A
             partner message to my call is classified (ContestReceivedKind): a grid
             without R as signalReport, a grid with R as rogerReport, everything else as
             in a standard QSO. So a caller's grid after my CQ selects Tx3 (rogerReport),
             a CQer's "R GRID" after my first message (Tx2 since Tx1 is disabled in contests, #24 S2b) moves to Tx4 (rogers), and RRR/RR73/73 end the
             contact as usual, which logs it (log on RRR/RR73/73, make-qso.adoc NIL
             guidance); report_sent and report_rcvd stay null and the received grid is the
             DX grid. Contest dupes are the existing worked-before indication of the
             call on this band and mode (WorkedBeforeQuery). The UDP Status special
             operation carries the WSJT-X SpecialOperatingActivity value: none 0, na_vhf 1,
             ww_digi 5, arrl_digi 8, field_day 3, rtty 4, hound 7 (HoundOperation), eu_vhf 2. Field Day and FT Roundup:
             ContestExchange (#24 S2b); EU VHF: EuVhfExchange (#99). In every contest activity
             (not none, not hound) except eu_vhf Tx1 is disabled
             as in WSJT-X (MW ~8190: "start QSO with Tx2"): a selection or entry that would
             start with Tx1 starts with Tx2, as with Skip Tx1. In eu_vhf Tx1 stays enabled
             (MW ~8203: "We're in EU_VHF mode: start QSO with Tx1"). */
    }
    attribute def ContestExchange {
        attribute exchange : String[0..1];
        attribute serial : Integer;
        doc /* #24 S2b2, CL-024-03 (WSJT-X 3.3.0-beta5 genCQMsg ~9620, genStdMsgs ~9741-9790,
             DecodedMessageReaction.cpp ~460-560, mainwindow guiUpdate ~8012-8017 and
             ~10542, logqso.cpp ~386-412, logbook.cpp ~92-110, AdifQso.cpp to_adif;
             Configuration.cpp Field_Day_Exchange / RTTY_Exchange). set_activity
             {activity:"field_day"|"rtty", exchange} chooses ARRL Field Day or FT/RTTY
             Roundup with the station's configured exchange; it is a boot setting like
             the activity (not saved). field_day: exchange "nC SECTION" (n 1-32 without
             a leading zero, C A-F, SECTION one of the 86 decoder sections, DX outside
             W/VE), e.g. "1A EMA". rtty: exchange a state/province/multiplier of the 171
             RTTY exchanges, e.g. "MA", a fixed four-digit number 0001-7999, or "DX" or "#"
             for a four-digit serial. Only ASCII is accepted. Upper case
             is folded and blank runs collapse; anything else, a missing exchange for these
             two, or an exchange for another activity is refused invalid_request field
             exchange. serial is the station's contest serial number: 1 at boot,
             incremented by one each time a contact is logged (DirectLog, completion or
             Log QSO of a contact not yet logged) while an activity other than none is set
             (MW ~10542), never reset by set_activity. set_activity also sets the activity of the
             current contact (its messages are regenerated and its log fields follow it).
             DIFFERENT from WSJT-X: a contest contact without exchange_sent or
             exchange_rcvd is still logged (logqso.cpp ~415 refuses it), and the RTTY RST of
             each side is replaced independently. UDP QSO Logged carries the exchanges as
             WstxUdp::'CL-112-05' rebuilds them from the stored record.
             Messages (both calls must be standard calls; otherwise generation fails
             invalid_call, since WSJT-X would hash and alter the call): Tx6 "CQ FD MYCALL
             GRID4" / "CQ RU MYCALL GRID4"; the sent exchange is the Field Day exchange,
             or for rtty "5n9 X" with n=(report+36)/6 truncated toward zero and clamped to
             2..9 and X the configured exchange or, for DX/#, the serial as four digits;
             Tx2 is the StandardMessageSet Tx1-Tx3 stem plus the sent exchange and Tx3 the
             stem plus "R " plus it (e.g. "K1ABC HB9BLA 1A EMA", "K1ABC HB9BLA R 559
             0003"); Tx1, Tx4, Tx5 unchanged. FT4 TU; (MW ~9783): in rtty and FT4, when the
             operator (not automation) selects a row while fewer than 15 whole seconds
             have passed since the start of the period of the station's last transmission
             and fewer than 3 whole seconds since the last partner RR73 was counted (Qt
             secsTo), Tx3 is prefixed "TU; ".
             Received (ContestReceivedKind): a Field Day message to my call in field_day,
             or an RTTY Roundup message to my call in rtty (TU; ignored), is a
             signalReport without R and a rogerReport with R; in another activity it is
             other. Its last two words (e.g. "6A WI", "579 MA", "559 0013") are the
             contact's exchange_rcvd; exchange_sent is the last two words of Tx2 once a
             Tx2 or Tx3 is transmitted. report_sent/report_rcvd stay null.
             Log (DirectLog, AdifQso::to_adif): rtty RST_SENT/RST_RCVD are the first words
             (5n9) of exchange_sent/exchange_rcvd. exchange_sent: a two-word value whose
             second word is a positive number gives STX (that word), otherwise
             STX_STRING (the value). exchange_rcvd: a positive number second word gives
             SRX; otherwise field_day gives CONTEST_ID ARRL-FIELD-DAY, SRX_STRING (the
             value), CLASS (first word) and ARRL_SECT (second word); rtty gives STATE
             (second word); another activity SRX_STRING. Fields are written in the
             LogRecord order. */
    }
    attribute def EuVhfExchange {
        attribute serialMinimum : Integer = 1;
        attribute serialMaximum : Integer = 2047;
        attribute gridLength : Integer = 6;
        doc /* #99, CL-099-02 (WSJT-X 3.3.0-beta5 genCQMsg ~9619, genStdMsgs ~9774-9779,
             guiUpdate ~8008-8011 and ~8203-8207, ~3431 and ~10280 (6-character locator),
             ~10542 and ~10669 (serial, eu_vhf_type5_serial_max), DecodedMessageReaction.cpp
             ~501-565 and ~772-776, AdifQso.cpp to_adif ~87-124; packjt77 type 5:
             WstxMessageEncode::PackMessage). The EU VHF contest message: report, serial and
             6-character locator, both calls hashed.
             Choosing. set_activity {activity:"eu_vhf"} without an exchange (an exchange is
             refused invalid_request field exchange), FT8 and FT4, a boot setting like the
             other activities (not saved). It is refused profile_incomplete with field
             locator, the activity unchanged, while the selected profile's locator
             (WstxProfiles::Settings) has fewer than 6 characters (empty or 4: WSJT-X only
             warns, "EU VHF Contest messages require a 6-character locator"), and refused
             invalid_call with field callsign while the profile callsign has more than 11
             characters (a hashed slot holds no more; the profile admits 12). The serial is
             ContestExchange serial, the one station contest serial (1 at boot, +1 for each
             logged contact while a contest activity is set, never reset by set_activity);
             #98 replaces its source by the log (highest STX of the contest + 1) for rtty and
             eu_vhf alike.
             Messages. Tx6 "CQ TEST MYCALL GRID4" (a nonstandard MYCALL keeps "CQ MYCALL");
             Tx1, Tx4 and Tx5 are StandardMessageSet's, including its nonstandard and
             compound rules (#24 S1b), and Tx1 stays enabled (GridExchangeContest); Tx2
             "<DX> <MYCALL> 5nSSSS GRID6" and Tx3 "<DX> <MYCALL> R 5nSSSS GRID6" (e.g.
             "<K1ABC> <HB9BLA> 550001 JN37VL", "<K1ABC> <HB9BLA> R 550001 JN37VL"), with n =
             (report+36)/6 truncated toward zero and clamped to 2..9 (the report of
             ReportRange, as ContestExchange's 5n9), SSSS the serial as four digits and GRID6
             the first six characters of the profile locator (an 8-character locator sends
             its first six, JN37VL12 sends JN37VL). Both calls are hashed whatever their
             form, so each is 3-11 characters, and the message limit of 37 characters
             (PackMessage tooLong; WSJT-X has no longer message) bounds the pair: Tx3 is
             len(DX) + len(MYCALL) + 21 characters, so the two calls together have at most 16
             characters (e.g. HB9BLA with a DX call of at most 10, HB9BLA/P with at most 8).
             The pair is checked before a contact starts, so no contact starts whose Tx3
             cannot be packed: while eu_vhf is set, a selection (SelectDecodedRow, also from
             Call 1st and automation) or entry (EnterDxStation) whose DX call has more than 11
             characters or more than 16 together with my call is refused invalid_call (no
             field, as the other DX-call refusals), nothing changes, and Call 1st goes on to
             the next caller. set_activity eu_vhf with an active contact whose pair is too
             long is refused invalid_call with field dx_call, the activity unchanged.
             Every command that regenerates the active contact's messages (set_activity,
             set_report, set_tx4, a selection or entry of the same partner) is refused, and
             changes nothing, when its Tx2/Tx3 cannot be generated: out_of_range with field
             serial when the serial is outside 1..2047 (WSJT-X's spin box maximum; a station
             that logged 2047 contacts), profile_incomplete with field locator when the
             profile locator was changed to fewer than 6 characters after the choice, and
             invalid_call with field callsign when the profile callsign was changed so that it
             has more than 11 characters or the pair more than 16. A profile change alone
             regenerates nothing: the messages already generated stay until such a command,
             and a new selection or entry is refused the same way. Every
             generated text packs unaltered (PackMessage, family euVhf for Tx2/Tx3). An
             operator-edited Tx2 or Tx3 is accepted when it packs unaltered in any family,
             including euVhf. The accepted request teaches the hash table both calls
             (WstxOfflineDecode::HashResolution). The partner can resolve my hashed call only
             from a message that carries it in full (my CQ or Tx1): that is why Tx1 stays.
             Received (ContestReceivedKind in eu_vhf). An EU VHF message (decoded fields type
             vhf) counts as the partner's message to me when its 'to' h12 equals the 12-bit
             hash of my profile callsign and its 'from' h22 equals the 22-bit hash of the
             contact's DX call, decoded in the partner's period in the contact's mode (the
             AutoSequence counting rules otherwise); without R it is signalReport (Tx3 next,
             rogerReport), with R rogerReport (Tx4 next, rogers). A standard grid message to my
             call stays grid (Tx2 next, report), as WSJT-X (DMR ~534 excludes EU VHF from the
             grid-as-report rule); a standard report or R+report to my call is classified as
             without an activity; RRR, RR73 and 73 end the contact as usual. In every other
             activity an EU VHF message is other. A counted EU VHF message sets the contact's
             exchange_rcvd to its last two words ("590003 IO91NP", WSJT-X right(13)) and its
             dxGrid to the 6-character locator; exchange_sent is the last two words of Tx2 once
             a Tx2 or Tx3 is transmitted. report_sent/report_rcvd stay null.
             Selection. While eu_vhf is set an EU VHF row whose 'from' is a filled-in hash is
             selectable (SelectDecodedRow): dx call its 'from' text, dx grid its locator;
             addressed to me (its 'to' is my call) the first slot is tx3 without R and tx4
             with R, and its last two words become exchange_rcvd, as a selected RTTY Roundup
             or Field Day row addressed to me does and as WSJT-X stores the received exchange
             of an EU VHF message to my call (DMR ~772-776); otherwise tx1 (replying) and
             exchange_rcvd stays null. An unresolved 'from' is refused
             row_not_standard, as WSJT-X refuses a contest message with <...>. In another
             activity such a row is refused row_not_standard as before. Call 1st, the
             strategies and contest verdicts keep reading standard messages only: a caller's
             Tx1 grid is answered with Tx2.
             Log (DirectLog, LogRecord). STX is the last four digits of the first word of
             exchange_sent ("0001"), SRX those of exchange_rcvd (AdifQso mid(2)); RST_SENT and
             RST_RCVD are the two-digit RS 52..59 of those words, the RS actually exchanged
             ("55", "59"; operator 2026-11-09 on #99: "Log the exchanged 55/59"); GRIDSQUARE is the
             partner's 6-character locator; no STX_STRING or SRX_STRING. UDP Status special
             operation 2. DIFFERENT from WSJT-X: (1) set_activity is refused without a
             6-character locator (WSJT-X warns and then sends a message type 5 cannot
             carry); (2) a partner message counts by the two hashes against my call and the
             DX call, never by whatever call the table fills in, as HoundOperation (2);
             (3) RST_SENT/RST_RCVD log the RS that was exchanged, not the dB report WSJT-X
             writes; (4) the contest hint WSJT-X shows for an EU VHF message in another
             activity is not offered. */
    }
    attribute def HoundOperation {
        attribute foxHz : Integer;
        doc /* #24 S4b, CL-024-04: classic Fox/Hound as the Hound (WSJT-X 3.3.0-beta5
             HoundTransmissionPolicy.cpp planFoxReportReply/planClassicTxStart; MW hound_reply
             ~14896, readFromStdout Hound block ~7380-7420, guiUpdate Tx start ~7726-7790,
             clearDX ~9951, special-op setup ~11352, processMessage ~9143, guiUpdate HWD
             ~8317, Tx watchdog ~14664, on_actionFT4_triggered; DecodedMessageReaction.cpp
             ~250 and ~304; controls-functions-left.adoc). SuperFox stays excluded
             (the SuperFox exclusion of WstxModemDecode::AdvanceDecode; #24 S5 moved to #77 (phase two)); the station is never
             the Fox (S6 dropped).
             Choosing. set_activity {activity:"hound"} (no exchange) is a boot setting like
             the other activities, FT8 only: it is refused state_conflict while the station
             operating mode is FT4, and a change of the station mode to FT4 sets the
             activity back to none (MW on_actionFT4_triggered). Choosing hound sets Tx
             parity odd (Tx even/1st forced off: I always transmit in the second period),
             Hold Tx on, and moves a current contact's next slot to tx1 unless it is tx3.
             While hound is set: set_parity even is refused state_conflict; choose_next
             accepts only tx1 and tx3 (others state_conflict); Tx1 is never skipped (MW
             elide_tx1_not_allowed), and every request carries Tx1 or Tx3 only (MW ~7783).
             UDP Status special operation 7. Station automation does not start
             (not_ready activity) and Call 1st never applies (a Hound never calls CQ):
             Enable Tx without a contact that has a DX call is refused no_contact.
             Selection (SelectDecodedRow) of a row decoded in a period starting at second
             15 or 45 of the minute is refused state_conflict ("select a Fox at :00 or
             :30", MW ~9143); a row whose exchange is R plus a report is refused
             state_conflict ("hound ignores other hounds", DMR ~304); the selection never
             sets the Tx offset from the row (DMR ~330); its first slot is tx3 for a report
             to my call and tx1 otherwise. 0.1 DXpedition rows stay unselectable
             (row_not_standard), as before.
             Received rows replace AutoSequence while hound is set (MW calls auto_sequence
             only outside FT8 Hound): of an active contact, counted once, decoded in the
             period of the parity opposite to mine, a row is (a) the Fox's report: a
             standard message to my call from the DX call with a report without R, or a
             0.1 DXpedition message "X RR73; MYCALL <FOX> rr" whose report slot is my call
             and whose hashed call is the DX call (HashResolution hashdx10); (b) the Fox's
             RR73: a standard RR73 to my call from the DX call, or a 0.1 message whose RR73
             slot is my call and whose hashed call is the DX call. (b) completes the contact
             at once (Enable Tx off with cause contactCompleted, handed to the log as any
             completion, MW stopTx + logQSO); the next selection starts a new contact. (a)
             is FoxReportReply: foxHz := the row frequency rounded; nothing else while Tune
             is on; otherwise report_rcvd := the Fox's report, the contact's report := the
             row SNR (ReportRange, MW m_rptSent from the decode), Tx3 regenerated and next,
             state rogerReport, the Tx offset := foxHz when it is a valid Tx offset, the
             reply becomes pending and the reply timeout is 11 T/R periods (165 s) from now.
             ClassicTxStart, once for each new period the engine plans a request for (the
             request's tx_offset_hz): a Tx1 with a Tx offset below 999 Hz moves to a
             uniformly random offset 1000..2998 Hz (QRandomGenerator bounded(1000,2999));
             a Tx3 after a sent reply moves to foxHz+300 when foxHz <= 600, else foxHz-300.
             A pending reply becomes sent when its transmission starts. So the first Tx3
             after a Fox report goes out on the Fox's frequency and a repeat without a new
             report on Fox +-300 Hz; a repeated Fox report returns it to the Fox's
             frequency.
             Timeouts: when the reply timeout passes Enable Tx is turned off (cause
             txWatchdog, the slot stays tx3; MW stopWRTimeout); the operator turning Enable
             Tx on or off ends the reply timeout (MW on_autoButton_clicked stopWRTimer.stop); while Tx1 is next and
             300 s have passed since the last accepted start (Enable Tx on, or a start action
             of StartActions, a run's own included; reset_repetitions does not restart the
             300 s: CL-111-10) the transmit state is
             turned off (cause txWatchdog; MW Hound watchdog HWD); after the station's Tx
             watchdog expires the next slot returns to tx1 (MW ~14664). A completed contact
             leaves the station ready to call the next Fox with Tx1.
             DIFFERENT from WSJT-X: (1) a Fox report never turns Enable Tx on (WSJT-X
             auto_tx_mode(true)): only the operator arms (CL-022, #10 safety rule); (2) the
             RR73 that completes must come from the DX call (standard) or carry the DX
             call's hash (0.1); WSJT-X completes on any RR73 to my call, so another station's
             RR73 would log my contact with the Fox; likewise a 0.1 report to my call is
             answered only when its hashed call is the DX call (WSJT-X answers it whatever
             the hashed call, also an unresolved <...>); (3) the decoder keeps the full 200-3000
             Hz range (WSJT-X decodes only below 1000 Hz unless Rx All is checked), so
             Band Activity also shows other Hounds; (4) the decision for a period is taken
             when its request is planned (after the previous own transmission started),
             not at its key-down; a Fox report decoded before key-down still sets the
             Fox's frequency for it, and no decision is taken while Tune is on; (5) the
             reply state and the reply timeout belong to one contact: a completion or a new
             contact ends them (WSJT-X's stopWRTimer keeps running and can turn off Enable
             Tx for the next Fox). */
    }
}
