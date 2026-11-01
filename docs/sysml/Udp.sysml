package WstxUdp {
    private import ScalarValues::*;
    doc /* Canonical contract of the WSJT-X-compatible UDP interface with multiple targets
         (issue #40, CL-040-01..04 in WstxRequirements; verification TC-012-001..004).
         Nothing here is an execution result.

         Normative reference: WSJT-X v3.3.0-beta5 source Network/NetworkMessage.hpp
         (SHA-256 b640a632f38b218f97b9c9cf5b5a09b183e1629c613c33d90f39635f9b3fdb3d) and
         Network/MessageClient.cpp (SHA-256
         8cfa89debc2b916b39151975437619e7f9b28aefa698f05231fbdf2247cb9f35) on HB9BLA; the
         message types used here are unchanged from the v3.3.0-beta4 behaviour baseline.

         Decisions (issue #40 comments "Defaults chosen for implementation" and "R-09",
         2026-11-01; operator not asked, standing instruction):
         D1 Protocol: NetworkMessage, outbound header schema 2 until a target's own
            datagram carries schema 3 (MessageClient negotiation), Heartbeat maximum
            schema 3. For every field type used here schema 2 (Qt_5_2) and 3 (Qt_5_4)
            serialize identically.
         D2 Targets: any number up to targetsMax, each its own UDP socket, unicast or IPv4
            multicast with TTL and an optional interface address; per-target message
            selection (default all) and accept_commands (default off). Default list: one
            target 127.0.0.1:2237, enabled, all messages, accept_commands off.
         D3 Safety: Halt Tx always acts, from any source, whether or not accept_commands
            is on. No inbound command keys the transmitter: Reply and Free Text use the
            ContactCommand path without transmit authority, are refused while Enable Tx
            is on, and never send enable_tx or tune.
         D4 Text form: Decode and log texts use the WSJT-X form "R-09" / "R+03".
         D5 Location (11) sets a session-only grid (CL-040-05): it replaces the profile
            locator for Status, generated messages and the log's my_gridsquare until the
            process restarts and is never saved to the profile.
         D6 Scope of this slice: IPv6 multicast targets are refused (CL-040-06, target,
            issue #46); the
            Settings UI is #37's; Close is sent when a target is disabled or removed (the
            station has no graceful-shutdown path). */

    attribute def UdpWire {
        attribute magic : String = "0xADBCCBDA";
        attribute outboundSchema : Integer = 2;
        attribute maximumSchema : Integer = 3;
        attribute inboundDatagramBytesMax : Integer = 4096;
        attribute heartbeatSeconds : Integer = 15;
        doc /* magic is 0xADBCCBDA. Every datagram: quint32 magic, quint32 schema, quint32
             type, utf8 id, then the type's fields, all big-endian (Qt QDataStream).
             quint8/quint32/qint32/quint64/qint64 as fixed width; bool one byte 0/1;
             float fields (Delta time) are written as an IEEE double of the single-precision
             value; utf8 is quint32 byte length then the bytes (0xFFFFFFFF = null, read as
             empty); QTime quint32 ms since midnight; QDateTime qint64 Julian day, quint32
             ms since midnight, quint8 timespec 1 (UTC); QColor qint8 spec (0 = invalid,
             1 = RGB), quint16 alpha, red, green, blue, pad (component c of 0..255 is
             c * 257). id is the configured instance_name.
             Inbound: a datagram larger than inboundDatagramBytesMax (also when the socket
             reports it as too large for the receive buffer; reading continues behind it), with another magic, a
             schema other than 2 or 3, a truncated or malformed known field, or an id other
             than instance_name is ignored and counted; unknown types and trailing bytes
             after the known fields are ignored (protocol rule 1 and 2). A Heartbeat
             without its maximum-schema field means schema 2. */
    }
    enum def OutboundMessage {
        enum heartbeat; enum status; enum decode; enum clear; enum qso_logged; enum close;
        enum logged_adif;
    }
    attribute def UdpTarget {
        attribute address : String;
        attribute enabled : Boolean;
        attribute multicastTtl : Integer;
        attribute multicastInterface : String[0..1];
        attribute messages : OutboundMessage[0..7];
        attribute acceptCommands : Boolean;
        assert constraint ttlRange { multicastTtl >= 1 and multicastTtl <= 255 }
        doc /* Wire keys exactly address, enabled, multicast_ttl, multicast_interface,
             messages, accept_commands, all required. address: "a.b.c.d:port" or
             "[v6]:port", port 1..65535; unspecified, 255.255.255.255 and IPv6 multicast
             are refused; an address is unique in the list (it is the target's identity).
             multicast_ttl 1..255 and multicast_interface (null or an IPv4 address) apply
             only to an IPv4 multicast address (224.0.0.0/4); accept_commands true is
             refused for a multicast address (a command's source is a host, never the
             group, so it could never act). messages: unique names of
             OutboundMessage, any order, stored in the enum order; empty sends nothing. */
    }
    attribute def UdpConfiguration {
        attribute instanceName : String = "WSTX-Rust";
        attribute targets : UdpTarget[0..16];
        attribute targetsMax : Integer = 16;
        attribute revision : Integer;
        doc /* Persisted in the selected profile directory as udp.json {schema_version 1,
             profile_id, revision, instance_name, targets}, written atomically (temporary
             file, flush, replace) under the profile's own lock (WstxProfiles). A missing
             file is the default configuration at revision 0 (D2). An unreadable, invalid
             or other-profile file leaves the configuration null with configuration_error
             invalid_configuration; then no socket is opened until a valid PUT replaces it.
             WSTX_UDP=off in the station's environment opens no socket (every target
             inactive; configuration and HTTP unchanged): isolated tests of the executable
             set it so they never reach port 2237 of the machine.
             instance_name: 1..64 UTF-8 bytes, no control character, no leading or trailing
             space. Each saved change advances revision by one (at most 9007199254740991). */
    }
    attribute def TargetStatus {
        doc /* Per configured target, volatile, in configuration order: {address, active
             (an open socket), schema (2 or 3), last_send_utc_ms (null or the last
             successful send), error (null, socket_unavailable or send_failed; a later
             successful send clears send_failed), last_command (null or {type, utc_ms,
             outcome applied|refused|not_accepted|ignored, code})}. type is the inbound
             name: clear, reply, close, replay, halt_tx, free_text, location, highlight,
             switch_configuration, configure. */
    }
    attribute def OutboundRules {
        doc /* Each enabled target has its own UDP socket, bound to the loopback address of
             the target's family for a loopback target and to the unspecified address
             otherwise, ephemeral port; an IPv4 multicast target sets multicast_ttl and,
             when given, multicast_interface. A message type is sent to a target only when
             selected. The station step runs every 50 ms whether or not a browser is
             connected.
             Heartbeat (0): id, maximum schema 3, version (the station version), revision
             "" at activation and every heartbeatSeconds.
             Status (1) at activation, whenever its encoded content changes and after a
             Replay: dial frequency (confirmed CAT dial Hz, else 0), mode and Tx mode FT8 or
             FT4 (station operating mode), DX call, report (the contact's report, else the
             station's, as "-09"), Tx enabled (armed), transmitting, decoding (the latest
             receive publication is incomplete), Rx DF and Tx DF (Hz), DE call and DE grid
             (profile), DX grid, Tx watchdog (expired), sub-mode "", fast mode false,
             special operation 0, frequency tolerance 4294967295, T/R period 15 (FT8) or 7
             (FT4), configuration name (profile display name), Tx message (the contact's
             next message, else "").
             Decode (2), New true, once per decoded record (decoded status with text and a
             period start) of the current live FT8/FT4 job, in sequence order: Time = ms
             since UTC midnight of period_start_utc, snr = snr_db rounded half away from
             zero (unknown: 0), Delta time = dt_seconds (unknown: 0) as single precision,
             Delta frequency = frequency_hz rounded, Mode "~" (FT8) or "+" (FT4), Message =
             the WSJT-X text form (D4: a standard message with R and a signal report
             renders "R-09"), Low confidence false, Off air false.
             Clear (3): when the current live job changes or ends after at least one of its
             records produced a Decode.
             QSO Logged (5) then Logged ADIF (12): when SaveContact stores a new record
             (outcome saved, not already_saved). QSO Logged: Date & Time Off and On from
             qso_date_off/time_off and qso_date/time_on (UTC), DX call, DX grid, Tx
             frequency = freq in Hz (else 0), mode FT8 or FT4, report sent/received, Tx
             power, comments, name "", operator call "", my call, my grid, exchange sent
             and received "", propagation mode "", then satellite, satellite mode and Rx
             frequency "" (MessageClient fields after the documented ones; protocol rule 2).
             Logged ADIF text: "\n<adif_ver:5>3.1.8\n<programid:9>WSTX-Rust\n<EOH>\n" plus
             the stored record's ADI fields plus " <EOR>".
             Close (6): to a target that is disabled or removed by a configuration change,
             and before its socket is reopened when its address, TTL or interface changes.
             WSPRDecode (10) is not applicable. */
    }
    attribute def InboundRules {
        attribute replayPerStep : Integer = 32;
        attribute highlightsMax : Integer = 100;
        doc /* Datagrams are read from every active target socket. Any valid datagram whose
             source equals the target address raises that target's schema to the
             datagram's schema (never lowers it; a new socket starts at 2).
             Halt Tx (8) from any source, whether or not accept_commands is on and whatever
             Auto Tx Only says (also when that field is missing): HaltTransmit, the same as
             the HALT button (outcome applied).
             Clear (3), Reply (4), Replay (7), Free Text (9), Location (11) and Highlight
             Callsign (13) act only when the target's accept_commands is on and the datagram's source equals
             the target address; otherwise outcome not_accepted and no effect.
             Heartbeat (0), Close (6), Switch Configuration (14) and Configure (15) have no
             effect (Heartbeat is not recorded as a command; the
             others outcome ignored).
             Reply: refused tx_enabled while Enable Tx is on; else it must match a decode of
             the current live job retained after the last inbound Clear of window 0 or 2
             (Time, snr, Delta frequency and Mode exactly, Delta time within 0.05 s, the
             Message after trimming spaces, against this station's Decode rendering; Low
             confidence and Modifiers ignored), else refused no_match; then ContactCommand
             select_row {row, replace false} without transmit authority (engine refusals
             such as contact_active or row_not_standard are outcome refused with that code).
             Location (WSJT-X MainWindow::locationChange): the trimmed text, when longer
             than 6 characters only after a case-insensitive "GRID:" prefix, upper-cased,
             must be a 4- or 6-character Maidenhead locator, else refused invalid_grid; it
             becomes the session grid (D5), the same for every target; a later Location
             replaces it.
             Free Text: refused tx_enabled while Enable Tx is on; an empty text is ignored;
             else ContactCommand edit_message {slot tx5, text}, as the browser's Tx5 edit:
             without a prepared contact it is refused no_contact, and a text that does not
             pack as a standard message is refused invalid_message; the Send flag is
             ignored.
             Replay: the retained decodes (as for Reply) are sent to that target only, New
             false, in sequence order, at most replayPerStep per station step, then Status.
             Clear: window 0 (also when missing) or 2 sets the Reply/Replay floor to the
             current next sequence; window 1 has no decode effect; each applied Clear
             advances clear.sequence and records clear.window for the browser (#37); window
             above 2 is malformed.
             Highlight Callsign: "CLEARALL!" removes every highlight; an invalid background
             or foreground removes that call's highlight; else it is set or replaced
             {call, background, foreground as "#rrggbb", last_only}; at most highlightsMax
             (the oldest is dropped); volatile. Calls are 1..32 bytes without control
             characters. */
    }
    attribute def UdpHttp {
        attribute bodyBytesMax : Integer = 8192;
        doc /* GET /udp (UdpSnapshot), existing auth and Origin rules of GET routes; no
             query or body: exactly {v:1, profile_id, boot_id, revision, configuration (null
             or {instance_name, targets}), configuration_error (null or
             invalid_configuration), status [TargetStatus], highlights [{call, background,
             foreground, last_only}], clear {sequence, window (null or 0..2)}, received,
             ignored}.
             PUT /udp: Origin, session, no query, application/json, at most bodyBytesMax
             (413), JSON; exactly {v, profile_id, boot_id, expected_revision,
             configuration {instance_name, targets}}; refusals in this order 400
             invalid_request (field), 400 unsupported_version (v), 403 wrong_profile, 409
             state_conflict boot_id, 409 stale_revision expected_revision, 409
             counter_exhausted, 503 storage_unavailable (nothing changes). Field names:
             instance_name, targets, targets[i].<key>. Accepted: 200 with the new
             UdpSnapshot; the running sockets follow the saved configuration at once
             (Close to a removed, disabled or socket-changed target, activation of a new or
             changed one;
             an unchanged target keeps its socket, schema and status). */
    }

    dependency servicePlacement from OutboundRules to WstxArchitecture::StationService;
    dependency profilePlacement from UdpConfiguration to WstxArchitecture::PersistedProfile;
    dependency replyPath from InboundRules to WstxContact::ContactCommand;
    dependency haltPath from InboundRules to WstxTransmit::HaltTransmit;
    dependency logPath from OutboundRules to WstxContact::SaveContact;
    dependency wireClause from UdpWire to WstxRequirements::'CL-040-01';
    dependency outboundClause from OutboundRules to WstxRequirements::'CL-040-01';
    dependency targetClause from UdpConfiguration to WstxRequirements::'CL-040-02';
    dependency httpClause from UdpHttp to WstxRequirements::'CL-040-02';
    dependency inboundClause from InboundRules to WstxRequirements::'CL-040-03';
    dependency textClause from OutboundRules to WstxRequirements::'CL-040-04';
}
