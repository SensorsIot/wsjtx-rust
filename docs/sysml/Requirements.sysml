// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
    private import ModelNotes::Conflict;

    doc /* What the station is required to do. Each functional requirement is about the
         station as a whole; Shack.sysml gives each to the part that carries it, and its
         status follows from the clauses derived from it. */

    attribute def BehaviorBaseline {
        doc /* The WSJT-X release whose observable behaviour the decoder is compared with. */
        @Conflict {
            what = "The pinned reference is v3.3.0-beta4; 36 texts of the old model cite "
                + "v3.3.0-beta5 and two cite beta6 as the reference of their own function.";
        }
        attribute suite : String = "WSJT-X";
        attribute release : String = "v3.3.0-beta4";
        attribute sourceCommit : String = "0f7d5928449ec747c3d1f6da1306f8c94404c3a9";
    }

    requirement 'FR-001' {
        doc /* Station setup
             Configure and persist the station's identity, locator, devices, radio settings
             and operating preferences, validating each value. */
    }
    requirement 'FR-002' {
        doc /* Audio
             Capture receive audio from the selected device and play transmit audio to it,
             with the timing and sample handling each mode needs. */
    }
    requirement 'FR-003' {
        doc /* Receive processing
             Process live audio and saved recordings into spectrum and decode results. */
    }
    requirement 'FR-004' {
        doc /* Decoding
             Decode the supported modes and message variants, reporting callsigns, locators,
             signal measurements, timing and frequency. */
    }
    requirement 'FR-005' {
        doc /* Encoding
             Produce protocol-compatible messages, channel symbols and waveforms for the
             supported transmit modes. */
    }
    requirement 'FR-006' {
        doc /* Time and sequencing
             Keep station time, schedule receive and transmit periods against it by each
             mode's timing rules, and report clock or device problems that prevent reliable
             operation. */
    }
    requirement 'FR-007' {
        doc /* QSO sequencing
             Run a contact message by message: choose and send the next message of the
             running QSO from the messages received, and complete or abort it,
             automatically or as the operator or an agent chooses. */
    }
    requirement 'FR-008' {
        doc /* Transmit control
             Show the transmit state, keep the transmit drive level, set by the operator or
             found from the radio's ALC, halt at once on request, and unkey the
             transmitter on a PTT, radio or device fault. */
    }
    requirement 'FR-009' {
        doc /* Radio control
             Control the radio's frequency, mode, PTT and split for the rigs Hamlib
             supports, the rig chosen by the operator as in WSJT-X. */
    }
    requirement 'FR-010' {
        doc /* Displays
             Show spectrum, waterfall, decodes, frequency and operating state sufficient for
             the operating workflows. */
    }
    requirement 'FR-011' {
        doc /* Logging
             Record completed contacts, read and write the supported log formats, and
             indicate duplicate and earlier contacts. */
    }
    requirement 'FR-012' {
        doc /* Integrations
             Send the WSJT-X UDP messages to the programs the operator names, and read
             from the PSK Reporter feed which stations hear the station. */
    }
    requirement 'FR-016' {
        doc /* Settings and migration
             Persist the application's settings reliably and migrate existing WSJT-X
             profiles. */
    }
    requirement 'FR-017' {
        doc /* Help and notices
             Provide operating guidance, version information, attribution, license access
             and the notice that this is an independent port. */
    }
    requirement 'FR-018' {
        doc /* Recorded audio input
             Load and validate recorded receive audio for repeatable processing, keeping the
             source data unchanged. */
    }
    requirement 'FR-019' {
        doc /* Browser operator interface
             Present the station to the operator in a browser and send the operator's
             requests to the station. */
    }
    requirement 'FR-020' {
        doc /* MCP automation
             Offer the station's operations to agents through MCP. */
    }
    requirement 'FR-021' {
        doc /* Station server and remote operation
             Serve the browser over a defined link that works on the same machine and over
             a limited-bandwidth connection, with the station holding the authoritative
             state. */
    }
    requirement 'FR-022' {
        doc /* Concurrent persisted station profiles
             Run any number of independent stations on one PC, each with its own port,
             browser window and persisted configuration. */
    }
    requirement 'FR-023' {
        doc /* Optional direct FlexRadio integration
             Operate a FlexRadio through its native network API, as an alternative to the
             audio device and CAT path. */
    }
    requirement 'FR-024' {
        doc /* Contest, special-activity and DXpedition operation
             Offer the special operating activities of WSJT-X: the contest exchanges, the
             Hound role and the nonstandard message types, each with its decode, encode,
             sequencing and logging. */
    }
    requirement 'FR-025' {
        doc /* Automatic operation
             Select the next station to call, or call CQ, and choose the transmit slot, from
             the ranking of the active strategy and without operator action. */
    }
    requirement 'FR-026' {
        doc /* Strategies and ranking
             Define and select strategies and contests, and order the decoded stations by
             the rules of the active one, presenting that order. */
    }
    requirement 'FR-027' {
        doc /* Reception reports
             Report the stations the station receives to PSK Reporter. */
    }
}
