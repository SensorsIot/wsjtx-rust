package WstxUdp {
    private import ScalarValues::*;
    private import ModelNotes::DiffersFromSource;
    private import WstxOperatingLayout::'TC-007-009';
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-012';
    private import WstxRequirements::'FR-001';
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::AutomationState;
    doc /* Canonical contract of the WSJT-X-compatible UDP interface with multiple targets
         (CL-040-01..04, CL-040-06, CL-040-07 and CL-112-01..06 in WstxRequirements;
         verification TC-012-001..004, 006, 007 and TC-112-001..006).
         Nothing here is an execution result.

         Normative reference: WSJT-X 3.3.0-beta6 source Network/NetworkMessage.hpp,
         Network/MessageClient.cpp, widgets/mainwindow.cpp (statusUpdate, postDecode,
         band_activity_cleared), widgets/mainwindow_qso.cpp (captureLogQso),
         widgets/logqso.cpp and main.cpp (instance name and lock). The wire vectors were
         constructed from v3.3.0-beta5 NetworkMessage.hpp (SHA-256
         b640a632f38b218f97b9c9cf5b5a09b183e1629c613c33d90f39635f9b3fdb3d) and
         MessageClient.cpp (SHA-256
         8cfa89debc2b916b39151975437619e7f9b28aefa698f05231fbdf2247cb9f35); the message
         types used here are the same in beta6. The deliberate differences are marked
         DiffersFromSource on OutboundRules and InboundRules.

         Operator decision 2026-11-06 (issue #40): "GridTracker just listens. We only react
         to the front end or to the MCP." and "The UI has to be able to halt the station in
         emergency halt. Also other commands can come from the UI." The interface is send-only:
         all control comes from the browser and MCP, and no inbound UDP command exists (Clear,
         Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, accept_commands
         and the udp.display event of CL-040-08 are removed). This supersedes D3, D5 and the
         earlier decision that UDP Halt stays (#39). Emergency off: the browser's HALT and MCP's
         halt tool.

         Decisions (issue #40 comments "Defaults chosen for implementation" and "R-09",
         2026-11-01; operator not asked, standing instruction):
         D1 Protocol: NetworkMessage, outbound header schema 2 until a target's own
            Heartbeat carries schema 3 (MessageClient negotiation), Heartbeat maximum
            schema 3. For every field type used here schema 2 (Qt_5_2) and 3 (Qt_5_4)
            serialize identically.
         D2 Targets: any number up to targetsMax, each its own UDP socket, unicast, IPv4
            multicast with TTL and an optional interface address, or IPv6 multicast (D6);
            per-target message
            selection (default all). Default list: one
            target 127.0.0.1:2237, enabled, all messages.
         D3 Retired 2026-11-06 (send-only, above).
         D4 Text form: Decode and log texts use the WSJT-X form "R-09" / "R+03".
         D5 Retired 2026-11-06 (send-only): no Location, no session grid; the profile locator
            is the station's grid.
         D6 IPv6 multicast (CL-040-06, issue #46 defaults, 2026-11-02; operator not asked,
            standing instruction): a group of ff00::/8 with a hop limit (multicast_ttl,
            1..255) and an interface given by its index (multicast_interface, decimal
            text). Interface names are refused: resolving a name to an index on Windows
            needs native FFI outside the permitted unsafe boundaries (Project-Specifics),
            and getaddrinfo does not resolve scope names. Scope 0 and 15 (reserved,
            RFC 4291 2.7) are refused; interface-local (1) and link-local (2) groups exist
            on one interface only and need the index; wider scopes may leave it null (the
            system's default interface). An index no interface has is admitted and shows the target
            socket_unavailable.
         D7 The Settings UI is #37's; Close is sent when a target is disabled or removed,
            and at shutdown (CL-112-06). */

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
             value; utf8 is quint32 byte length then the bytes; QTime quint32 ms since
             midnight; QDateTime qint64 Julian day, quint32 ms since midnight, quint8
             timespec 1 (UTC). id is the server's InstanceName. Inbound: InboundRules. */
    }
    attribute def InstanceName {
        attribute base : String = "WSTX-Rust";
        attribute lockFolder : String = "%LOCALAPPDATA%/WstxRust/udp-instance";
        doc /* The id of every datagram (CL-112-01), fixed once per process and no setting.
             Base form: "WSTX-Rust - <model>" for a CAT control (every CAT endpoint is an
             IC-7300: icom7300:// or a plain COMn), "WSTX-Rust - <model> <slice letter>" for
             a native Flex profile (model and slice letter as the session reports them at
             its first ready), base otherwise (control disabled, or an endpoint the CAT
             cannot parse). A server takes the first of base, "base 2", "base 3", ... whose
             lock file in lockFolder no live process holds, and holds that lock until its
             process ends (WSJT-X main.cpp QLockFile named after the application name); a
             killed process frees it. Up to 99 numbers are tried; beyond, and when the lock
             folder cannot be created or opened, the base form is taken unchecked. With
             WSTX_UDP=off no lock is taken and the name is the base form. GET /udp shows it
             as instance_name (null while a Flex profile's session was never ready). A Flex
             session that is ready without a model or a slice letter does not fix the name:
             the server waits until both are known. */
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
        assert constraint ttlRange { multicastTtl >= 1 and multicastTtl <= 255 }
        doc /* Wire keys exactly address, enabled, multicast_ttl, multicast_interface,
             messages, all required; an unknown key, accept_commands among them, is refused. address: "a.b.c.d:port" or
             "[v6]:port", port 1..65535; unspecified, 255.255.255.255 and an IPv6
             multicast group of scope 0 or 15 are refused; an address is unique in the
             list (it is the target's identity). multicast_ttl 1..255 is the TTL of an
             IPv4 multicast address (224.0.0.0/4) and the hop limit of an IPv6 multicast
             address (ff00::/8). multicast_interface is null or, for an IPv6 multicast
             address, an interface index as decimal text 1..4294967295 without sign or
             leading zero (D6); for any other address, an IPv4 address (unchanged from
             #40, so a saved file keeps loading); an IPv6 multicast group of
             scope 1 or 2 requires it. Both apply only to a multicast address.
             messages: unique names of
             OutboundMessage, any order, stored in the enum order; empty sends nothing. */
    }
    attribute def UdpConfiguration {
        attribute targets : UdpTarget[0..16];
        attribute targetsMax : Integer = 16;
        attribute revision : Integer;
        doc /* The target list. Persisted in the selected profile directory as udp.json
             {schema_version 1, profile_id, revision, targets}, written atomically (temporary
             file, flush, replace) under the profile's own lock (WstxProfiles). A missing
             file is the default configuration at revision 0 (D2). An unreadable, invalid
             or other-profile file leaves the configuration null with configuration_error
             invalid_configuration; then no socket is opened until a valid PUT replaces it.
             A file that names accept_commands on its targets or a top-level instance_name
             keeps loading: the key is dropped when the file loads (otherwise unchanged) and
             is gone after the next save.
             WSTX_UDP=off in the station's environment opens no socket (every target
             inactive; configuration and HTTP unchanged): isolated tests of the executable
             set it so they never reach port 2237 of the machine.
             Each saved change advances revision by one (at most 9007199254740991). */
    }
    attribute def TargetStatus {
        doc /* Per configured target, volatile, in configuration order: {address, active
             (an open socket), schema (2 or 3), last_send_utc_ms (null or the last
             successful send), error (null, socket_unavailable or send_failed; a later
             successful send clears send_failed)}. */
    }
    attribute def OutboundRules {
        @DiffersFromSource {
            what = "Status is resent unchanged at each 15 s pulse (CL-040-07); WSJT-X sends it "
                + "only on a change.";
        }
        @DiffersFromSource {
            what = "The Logged ADIF header names this product, programid WSTX-Rust, not WSJT-X.";
        }
        @DiffersFromSource {
            what = "A played recording sends no Decode; WSJT-X sends its decodes with Off air "
                + "true.";
        }
        @DiffersFromSource {
            what = "Logged ADIF carries the stored record's app fields APP_WSTXRUST_CONTACT_ID, "
                + "APP_WSTXRUST_SOURCE and APP_WSTXRUST_ACTIVITY.";
        }
        doc /* Each enabled target has its own UDP socket, bound to the loopback address of
             the target's family for a loopback target and to the unspecified address
             otherwise, ephemeral port; an IPv4 multicast target sets multicast_ttl and,
             when given, multicast_interface (IP_MULTICAST_TTL, IP_MULTICAST_IF); an IPv6
             multicast target sets the hop limit and, when given, the interface index
             (IPV6_MULTICAST_HOPS, IPV6_MULTICAST_IF); multicast loopback is on. A socket
             option the system refuses leaves the target inactive with socket_unavailable.
             A message type is sent to a target only when
             selected. The station step runs every 50 ms whether or not a browser is
             connected.
             Heartbeat (0): id, maximum schema 3, version (the station version), revision
             "" at each pulse: at activation and every heartbeatSeconds after the previous
             one (MessageClient heartbeat_timer_, NetworkMessage::pulse).
             Status (1) (CL-040-07) at activation, whenever its encoded content changes, once
             for each live decoder window begun since the last Status (also when that window
             began and ended between two station steps), at each pulse even when unchanged
             (also to a target that selects status but not heartbeat).
             WSJT-X sends Status from MainWindow::statusUpdate, which beginDecode and
             endDecode reach through updateDecodeControls, so its decoding field toggles at
             least once per T/R period; the resend at each pulse is this station's choice
             (issue #40 live acceptance, 2026-11-02) so a tool started later learns the
             state within heartbeatSeconds. Fields: dial frequency (CL-112-02: the confirmed
             CAT dial Hz, else the operating selection's nominal_hz, else 0), mode and Tx mode
             FT8 or FT4 (station operating mode), DX call, report (the contact's report, else
             the station's, as QString::number writes it: "-9", "3", "0"), Tx enabled
             (armed), transmitting, decoding (the live
             decoder is processing an analysis window: true from the start of a window's
             decode until it returns, completed, abandoned, failed or cancelled), Rx DF and Tx DF (Hz), DE call and DE grid
             (profile), DX grid, Tx watchdog (expired), sub-mode "", fast mode false,
             special operation the WSJT-X value of the contact settings' activity (none 0,
             na_vhf 1, eu_vhf 2, field_day 3, rtty 4, ww_digi 5, hound 7, arrl_digi 8, WstxSpecialActivities::GridExchangeContest, EuVhfExchange, HoundOperation), frequency tolerance 4294967295, T/R period 15 (FT8) or 7
             (FT4), configuration name (profile display name), Tx message (the contact's
             next message, else "").
             Decode (2), New true, once per decoded record (decoded status with text and a
             period start) of the current live FT8/FT4 job, in sequence order: Time = ms
             since UTC midnight of period_start_utc, snr = snr_db rounded half away from
             zero (unknown: 0), Delta time = dt_seconds rounded to one decimal as CL-112-03
             (unknown: 0) as single precision,
             Delta frequency = frequency_hz rounded, Mode "~" (FT8) or "+" (FT4), Message =
             the WSJT-X text form (D4: a standard message with R and a signal report
             renders "R-09"; a hashed call as the record gives it, <CALL> once
             WstxOfflineDecode::HashResolution filled it in, else <...>), Low confidence
             false, Off air false. A record without a period start gives no Decode and is
             passed, so it is never sent later.
             Clear (3): CL-112-04.
             QSO Logged (5) then Logged ADIF (12): when SaveContact stores a new record
             (outcome saved, not already_saved) and when WstxLogbook::DirectLog first stores
             a contact's record (not for a replacement or an unchanged record). QSO Logged:
             Date & Time Off and On from qso_date_off/time_off and qso_date/time_on (UTC), DX
             call, DX grid, Tx frequency = freq in Hz (else 0), mode FT8 or FT4, report
             sent/received, Tx power, comments, name "", operator call "", my call, my grid,
             exchange sent and received (CL-112-05, built from the stored record), propagation
             mode "", then satellite, satellite mode and Rx frequency "" (MessageClient
             fields after the documented ones; protocol rule 2).
             Logged ADIF text: "\n<adif_ver:5>3.1.8\n<programid:9>WSTX-Rust\n<EOH>\n" plus
             the stored record's ADI fields plus " <EOR>".
             Close (6): to a target that is disabled or removed by a configuration change,
             before its socket is reopened when its address, TTL or interface changes, and
             at shutdown (CL-112-06).
             No datagram is sent while the server has no instance name (a native Flex
             profile before its first ready session).
             WSPRDecode (10) is not applicable. */
    }
    attribute def InboundRules {
        @DiffersFromSource {
            what = "Send-only (CL-040-03): no inbound message acts; WSJT-X acts on Reply, Clear, "
                + "Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch "
                + "Configuration, Configure, Annotation Info and Tx Inhibit.";
        }
        @DiffersFromSource {
            what = "Only a Heartbeat from the target's own address with the station's id raises "
                + "the header schema; WSJT-X takes a higher schema from any readable datagram.";
        }
        doc /* Send-only (operator decision 2026-11-06, CL-040-03): the station reacts to the
             browser and MCP only. The one thing read from a target is its Heartbeat, because
             the WSJT-X protocol negotiates the header schema through it: each station step
             reads at most 64 datagrams per active target socket; a Heartbeat (0) whose source
             equals the target address, with magic, schema 2 or 3, a non-empty valid utf8 id equal to
             the InstanceName and at most inboundDatagramBytesMax bytes, raises that target's
             schema to the datagram's schema (never lowers it; a new socket starts at 2). Fields
             after the Heartbeat's header are not read (protocol rule 2). Every other datagram is
             read and dropped with no effect, no state and no count: Clear (3), Reply (4), Close
             (6), Replay (7), Halt Tx (8), Free Text (9), Location (11), Highlight Callsign (13),
             Switch Configuration (14), Configure (15), unknown types, a datagram too large for
             the receive buffer (reading continues behind it), a Heartbeat from any other source or with another
             id. A Heartbeat arriving at a multicast target's socket never matches the group
             address. */
    }
    attribute def UdpHttp {
        attribute bodyBytesMax : Integer = 8192;
        doc /* GET /udp (UdpSnapshot), existing auth and Origin rules of GET routes; no
             query or body: exactly {v:1, profile_id, boot_id, instance_name (InstanceName,
             read-only; null while not fixed), revision, configuration (null or {targets}),
             configuration_error (null or invalid_configuration), status [TargetStatus]}.
             PUT /udp: Origin, session, no query, application/json, at most bodyBytesMax
             (413), JSON; exactly {v, profile_id, boot_id, expected_revision,
             configuration {targets}}; refusals in this order: 1. 400 invalid_request for
             the envelope (not an object; a missing key, named as its field; an extra key,
             without a field); 2. 400 invalid_request field v when v is not a non-negative
             integer; 3. 400 unsupported_version (v) for any other integer than 1; 4. 400
             invalid_request for profile_id, boot_id, expected_revision, then the
             configuration's field (configuration for a configuration without exactly the key
             targets, instance_name among them; targets; targets[i].<key>); 5. 403
             wrong_profile, 409 state_conflict boot_id, 409 stale_revision
             expected_revision, 409 counter_exhausted, 503 storage_unavailable (nothing
             changes: revision, file, sockets and target status). Accepted: 200 with the new
             UdpSnapshot; the running sockets follow the saved configuration at once (Close
             to a removed, disabled or socket-changed target, activation of a new or changed
             one; an unchanged target always keeps its socket, schema and status). */
    }

    dependency servicePlacement from OutboundRules to WstxArchitecture::StationService;
    dependency profilePlacement from UdpConfiguration to WstxArchitecture::PersistedProfile;
    dependency logPath from OutboundRules to WstxLogbook::SaveContact;
    dependency directLogPath from OutboundRules to WstxLogbook::DirectLog;
    dependency wireClause from UdpWire to WstxUdp::'CL-040-01';
    dependency outboundClause from OutboundRules to WstxUdp::'CL-040-01';
    dependency targetClause from UdpConfiguration to WstxUdp::'CL-040-02';
    dependency httpClause from UdpHttp to WstxUdp::'CL-040-02';
    dependency inboundClause from InboundRules to WstxUdp::'CL-040-03';
    dependency textClause from OutboundRules to WstxUdp::'CL-040-04';
    dependency statusCadenceClause from OutboundRules to WstxUdp::'CL-040-07';
    dependency instanceClause from InstanceName to WstxUdp::'CL-112-01';
    dependency statusClause from OutboundRules to WstxUdp::'CL-112-02';
    dependency decodeClause from OutboundRules to WstxUdp::'CL-112-03';
    dependency clearClause from OutboundRules to WstxUdp::'CL-112-04';
    dependency exchangeClause from OutboundRules to WstxUdp::'CL-112-05';
    dependency closeClause from OutboundRules to WstxUdp::'CL-112-06';
    dependency CL_040_02_verified_by_TC_007_009 from 'CL-040-02' to 'TC-007-009';
    dependency CL_112_01_verified_by_TC_007_009 from 'CL-112-01' to 'TC-007-009';

    // #40 WSJT-X-compatible UDP interface with multiple targets (decisions recorded in
    // WstxUdp and on issue #40, 2026-11-01); detailed contract in WstxUdp.
    requirement 'CL-040-01' {
        doc /* Speak the WSJT-X NetworkMessage protocol (magic 0xADBCCBDA, schema 2 negotiated up to 3, Qt QDataStream big-endian) with id = the server's instance name (CL-112-01), and send to each enabled target its selected outbound messages: Heartbeat every 15 s, Status on change, on each live decoder window and with each Heartbeat pulse (CL-040-07), Decode for each new live FT8/FT4 decode, Clear when the operating band changes (CL-112-04), QSO Logged and Logged ADIF when a contact is saved, Close when a target is disabled or removed and at shutdown (CL-112-06). Details: WstxUdp::UdpWire, OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/network_message.rs; server/src/udp.rs; server/src/logbook_http.rs";
    }
    dependency CL_040_01_to_FR_012 from 'CL-040-01' to 'FR-012';
    requirement 'CL-040-02' {
        doc /* Any number of targets up to 16, each address:port (unicast, IPv4 multicast with TTL and interface, or IPv6 multicast per CL-040-06), enabled, a per-type outbound message selection (default all), with per-target status (last send, error). The configuration is the target list only, persisted in the selected profile directory and served by GET /udp and PUT /udp; the default is one target 127.0.0.1:2237, enabled, all messages. Details: WstxUdp::UdpTarget, UdpConfiguration, TargetStatus, UdpHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/profile.rs; server/src/main.rs";
    }
    dependency CL_040_02_to_FR_012 from 'CL-040-02' to 'FR-012';
    dependency CL_040_02_to_FR_001 from 'CL-040-02' to 'FR-001';
    requirement 'CL-040-03' {
        doc /* Send-only (operator decision 2026-11-06: "GridTracker just listens. We only react to the front end or to the MCP."; "The UI has to be able to halt the station in emergency halt."). No inbound UDP message acts on the station: Clear, Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch Configuration, Configure and unknown types from any source have no effect, change no state and are not answered. All control comes from the browser and MCP; the emergency off is the browser's HALT and MCP's halt. Only a Heartbeat from a target's own address with the configured id raises that target's header schema (2 to 3, never lowered), as the WSJT-X protocol negotiates it. A datagram too large for the receive buffer never holds back the datagrams behind it. Details: WstxUdp::InboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/network_message.rs";
    }
    dependency CL_040_03_to_FR_012 from 'CL-040-03' to 'FR-012';
    dependency CL_040_03_to_FR_008 from 'CL-040-03' to 'FR-008';
    requirement 'CL-040-04' {
        doc /* Decode texts use the WSJT-X form: a standard message with R before a signal report is "R-09" / "R+03", never the decoder's separated "R -09". Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_040_04_to_FR_012 from 'CL-040-04' to 'FR-012';
    // CL-040-05 and TC-012-005 (Location session grid) retired by the operator decision
    // 2026-11-06 recorded in CL-040-03 and WstxUdp; the identities are not reused.
    requirement 'CL-040-06' {
        doc /* Issue #46: an IPv6 multicast group target (ff00::/8) with a hop limit 1..255 (multicast_ttl) and an interface index (multicast_interface as decimal text, required for interface-local and link-local scope, optional above) is admitted by PUT /udp, saved, and receives its selected outbound messages through a socket with IPV6_MULTICAST_HOPS and IPV6_MULTICAST_IF set. Reserved scopes 0 and 15 and interface names are refused. Details: WstxUdp D6, UdpTarget, OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_040_06_to_FR_012 from 'CL-040-06' to 'FR-012';
    verification 'TC-012-006' {
        doc /* TC-012-006 — IPv6 multicast targets
             CL-040-06
             Setup: actual candidate router and UDP owner on a disposable profile; a peer socket joined to the transient link-local group ff12::5754:5358 on the Windows loopback pseudo-interface (index 1);
             Steps: PUT, each alone: scope 0 ff00::1, scope 15 ff0f::1 and ff1f::1, the group without an interface, ff01::1 without an interface, hop limit 0 and 256, an IPv4 group with interface "1", interfaces "0", "01", "-1", "+1", " 1", "4294967296", "Ethernet", "127.0.0.1", "::1", "" and the number 1; then one PUT of the group at the peer's port with hop limit 2 and interface "1", [ff05::5754:5358]:2237 hop limit 255 interface "1", [ff15::5754:5358]:2238 interface "4000000000", and a disabled [ff08::5754:5358]:2239 without an interface; open a new owner; PUT the list plus a disabled [::1]:2240 with interface "127.0.0.1", then with "1"; read the socket options; one station step.
             Expected: each refusal 400 invalid_request with its field (address for the scopes, otherwise the named field) and nothing saved; the PUT admitted with the targets saved as given and unchanged after the reopen; the IPv6 unicast target with "127.0.0.1" admitted and with "1" refused targets[4].multicast_interface; the group socket has hop limit 2, interface 1 and loopback on, the site-local one hop limit 255; the unknown index shows active false, socket_unavailable; the joined peer receives Heartbeat then Status (schema 2, id WSTX-Rust).
             2 — Isolated automated functional tests; Windows development PC, loopback IPv6 multicast only, nothing leaves the machine. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-06';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_06_verified_by_TC_012_006 from 'CL-040-06' to 'TC-012-006';
    requirement 'CL-040-07' {
        doc /* Issue #40 live acceptance (GridTracker, 2026-11-02): Status is sent as WSJT-X sends it, so a tool that waits for a Status sees the station within one T/R period. Its decoding field is true while the live decoder processes an analysis window and false once that decode returns (completed, abandoned, failed or cancelled); every toggle sends a Status, and a window that begins and ends between two station steps still sends one, so at least one Status goes out per decoded window and therefore per T/R period (WSJT-X v3.3.0-beta5 widgets/mainwindow.cpp MainWindow::beginDecode and endDecode call updateDecodeControls, which calls statusUpdate; MessageClient::status_update sends unconditionally). In addition, the Status is resent unchanged at each pulse, together with the Heartbeat every 15 s (MessageClient heartbeat_timer_, NetworkMessage::pulse), also to a target that selects status without heartbeat, so a tool started later learns the state within 15 s; the resend is this station's choice, WSJT-X has none. A target that does not select status receives none of these. Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/recording.rs";
    }
    dependency CL_040_07_to_FR_012 from 'CL-040-07' to 'FR-012';
    verification 'TC-012-007' {
        doc /* TC-012-007 — Status cadence with decoder windows and the pulse
             CL-040-07
             Setup: (a) actual candidate UDP owner, contact engine and #9 transmit owner on the recording hardware double (profile HB9BLA, JN47AA); loopback peers A (all messages), B (status only) and C (heartbeat and decode); (b) the actual live worker on the recording fixture with zero-sample FT8 windows and a capture poll that records the decoder activity while the decode in progress drives it.
             Steps: (a) step; step; twice: begin a window decode through the recording's decoder signal, step, step, end it, step; begin and end one window, step, step; back-date the stored pulse instant by 14 s, step; by 15 s, step; step. (b) analyze one window with a waiting late window, and with a replacing window (overrun).
             Expected (hand table): (a) activation A Heartbeat then Status decoding 0, B Status, C Heartbeat only; then nothing; each window begin one Status decoding 1 to A and B, no repeat while it decodes, its end one Status decoding 0; the window begun and ended between steps one Status decoding 0 to A and B; nothing at 14 s; at 15 s A Heartbeat then a Status byte-identical to the last one sent, B the Status, C the Heartbeat only; then nothing; C never receives a Status. (b) before: (false, 0); polled values all decoding true, first (true, 1), then (true, 2); after: (false, 2), in both cases.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP on ephemeral ports only, deterministic time (no sleep for the pulse), no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-07';
        }
        attribute executable : String = "server/src/udp_tests.rs; server/src/recording_tests.rs";
    }
    dependency CL_040_07_verified_by_TC_012_007 from 'CL-040-07' to 'TC-012-007';
    // CL-040-08 and TC-012-008 (udp.display: Highlight Callsign and Clear in the browser)
    // retired by the operator decision 2026-11-06 recorded in CL-040-03 and WstxUdp; the
    // identities are not reused.
    verification 'TC-012-001' {
        doc /* TC-012-001 — NetworkMessage wire vectors
             CL-040-01, CL-040-03, CL-040-04
             Setup: hand-constructed byte vectors in server/tests/vectors/udp/, each written field by field from WSJT-X v3.3.0-beta5 NetworkMessage.hpp (SHA-256 b640a632...) with the construction steps recorded in the file, independent of the encoder.
             Steps: encode Heartbeat, Status, Decode, Clear, QSO Logged (with exchange sent "1A EMA" and received "2B CT"), Close and Logged ADIF from the vector inputs; read the Heartbeat vectors (schema 3 with its fields, schema 2 without them, trailing bytes); read every refused vector (each former command and an unknown type: Clear, Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch Configuration, Configure, type 18; a Heartbeat with wrong magic, schema 1 and 4, truncated utf8, invalid utf8, null id, 4097 bytes).
             Expected: encoded bytes equal each vector exactly; the read header equals the vector's schema and id; refused vectors give nothing; arbitrary bytes and every truncation never panic; the decoder text "K1ABC W9XYZ R -09" renders "K1ABC W9XYZ R-09" and "R +03" renders "R+03", other texts unchanged.
             2 — Isolated automated tests; Windows development PC, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-01';
            verify 'CL-040-03';
            verify 'CL-040-04';
        }
        attribute executable : String = "server/tests/udp_vectors.rs; server/src/udp_tests.rs";
    }
    dependency CL_040_01_verified_by_TC_012_001 from 'CL-040-01' to 'TC-012-001';
    dependency CL_040_03_verified_by_TC_012_001 from 'CL-040-03' to 'TC-012-001';
    dependency CL_040_04_verified_by_TC_012_001 from 'CL-040-04' to 'TC-012-001';
    verification 'TC-012-002' {
        doc /* TC-012-002 — Outbound messages to several targets
             CL-040-01, CL-040-02, CL-040-04
             Setup: actual candidate router, UDP owner, contact engine and #9 transmit owner on the recording hardware double (profile HB9BLA, JN47AA), an injected FT8 live job, hand-authored codec-packed rows "CQ K1ABC FN42" 1234.6 Hz -12.4 dB and "HB9BLA W9XYZ R-09" (decoder text "HB9BLA W9XYZ R -09") 900.0 Hz -3.0 dB; two loopback UDP peers on ephemeral ports configured as targets by PUT /udp (A all messages, B only decode).
             Steps: one station step; publish the rows; step; change the operating report to -7; step; start a second live job on the same band; step; save a contact through POST /contacts, repeat it with the same and with a new command_id; disable target A by PUT /udp; step. Guard: an FT8 played-recording job with a decoded record, step, the job ends, step.
             Expected (hand table): A receives Heartbeat (id WSTX-Rust, max schema 3) and Status (mode FT8, DE HB9BLA JN47AA, Tx enabled false), then Decode New true Time = period ms since midnight, snr -12, df 1235, Mode "~", "CQ K1ABC FN42", and snr -3, df 900, "HB9BLA W9XYZ R-09"; a changed Status with report "-7"; no Clear after the second live job on the same band; QSO Logged (DX call, mode FT8, times) then Logged ADIF beginning with the ADIF header and containing <call:5>K1ABC and ending " <EOR>", nothing for the retained receipt or already_saved; Close after disable while B keeps its socket. B receives exactly the two Decode datagrams. GET /udp shows last_send_utc_ms for both and error null. Guard (green before and after): the played recording sends no Decode and no Clear to any target.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP on ephemeral ports only, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-01';
            verify 'CL-040-02';
            verify 'CL-040-04';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_01_verified_by_TC_012_002 from 'CL-040-01' to 'TC-012-002';
    dependency CL_040_02_verified_by_TC_012_002 from 'CL-040-02' to 'TC-012-002';
    dependency CL_040_04_verified_by_TC_012_002 from 'CL-040-04' to 'TC-012-002';
    verification 'TC-012-003' {
        doc /* TC-012-003 — No inbound message acts; Heartbeat negotiates the schema
             CL-040-03
             Setup: as TC-012-002 with one target A and another socket X; a published CQ row; the browser's enable_tx has armed the station; the PTT log of the hardware double.
             Steps: from A and from X to A's socket: Halt Tx, Clear, a Reply matching the row, Close, Replay, Free Text, Location "JN36AB", Highlight Callsign, Switch Configuration, Configure; one step; read arm state, last disarm cause, contact, profile grid, the datagrams at A, and GET-shape of the snapshot. Then, one step each: a schema-3 Heartbeat from X; from A a schema-3 Heartbeat with another id, a schema-4 Heartbeat, a schema-3 Replay and a schema-3 Halt Tx. Then from A a 5000-byte datagram followed by a schema-3 Heartbeat, one step; a schema-2 Heartbeat, one step; publish a further decode, one step.
             Expected: still armed with the disarm cause unchanged, no contact prepared, the grid and the Status DE grid the profile's, at A no Decode with New false (only Status); the snapshot keys exactly v, profile_id, boot_id, instance_name, revision, configuration, configuration_error, status and a status entry exactly active, address, error, last_send_utc_ms, schema; the schema stays 2 through each of the single steps, becomes 3 in the step of the oversize datagram and its Heartbeat, stays 3 after the schema-2 Heartbeat, and the next datagrams at A carry header schema 3.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-03';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_03_verified_by_TC_012_003 from 'CL-040-03' to 'TC-012-003';
    verification 'TC-012-004' {
        doc /* TC-012-004 — Target configuration and persistence
             CL-040-02
             Setup: actual candidate router on a disposable profile directory without udp.json; a second profile with an invalid udp.json; a third with one active loopback target A.
             Steps: GET /udp; PUT a list of A (unicast, decode only), B (239.255.0.1:2237 multicast, ttl 2, interface 127.0.0.1); open a new owner on the same profile; PUT with a stale revision, another profile, another boot, an unknown key, 17 targets, a duplicate address, port 0, 0.0.0.0, ff02::1 without an interface, ttl 0 and 256, an interface that is not IPv4, a duplicated or unknown message name, accept_commands on a target (a retired key), a configuration with instance_name, v 2, text/plain, 8193 bytes, a query; GET on the invalid profile; open an owner on a udp.json that names instance_name and whose target also names accept_commands true, then PUT. Refusal order: v 2 with an invalid target; v 2 with boot_id missing; v "1". A failed write of udp.json injected, PUT; the injection removed, the same PUT.
             Expected: the default {targets: one target 127.0.0.1:2237 enabled, all seven messages, multicast_ttl 1, interface null} at revision 0; the PUT returns revision 1 with the messages in enum order and survives the reopen unchanged; each refusal with its status, code and field (the configuration with instance_name: invalid_request field configuration) and nothing saved; the invalid profile shows configuration null and configuration_error invalid_configuration with no socket; a row published then is not sent after a valid PUT (only Heartbeat and Status); the file with instance_name and accept_commands loads without configuration error, its target unchanged but for that key and active, and the PUT writes a file without either key. Refusal order: unsupported_version field v; invalid_request field boot_id; invalid_request field v. The failed write: 503 storage_unavailable; revision, file bytes, socket and target status unchanged and nothing sent; the next PUT with the same expected_revision succeeds with revision 1.
             2 — Isolated automated functional tests; Windows development PC, loopback only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-02';
            verify 'CL-112-01';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_02_verified_by_TC_012_004 from 'CL-040-02' to 'TC-012-004';
    dependency CL_112_01_verified_by_TC_012_004 from 'CL-112-01' to 'TC-012-004';

    // The UDP interface as WSJT-X 3.3.0-beta6 sends it (WstxUdp).
    requirement 'CL-112-01' {
        doc /* Instance name. Each server has one instance name, fixed for the life of the process and used as the id of every datagram (Heartbeat, Status, Decode, Clear, QSO Logged, Close, Logged ADIF). Base form: CAT radio "WSTX-Rust - <model>", the model of the saved CAT control ("WSTX-Rust - IC-7300"; a plain COMn endpoint is an IC-7300); no radio (control disabled, or manual operation without CAT) plain "WSTX-Rust"; native Flex profile "WSTX-Rust - <model> <slice letter>" ("WSTX-Rust - FLEX-6600 A"). A number is added only on a clash: the server takes the first form that no live server holds, the base form, then the base form followed by " 2", " 3" and so on ("WSTX-Rust - IC-7300 2", "WSTX-Rust 2"). When the name is fixed: CAT and no-radio profiles at start, after radio discovery (CL-044-15) and before the server serves; if discovery moves the profile to another radio, the name takes that radio's model. Native Flex profile: the first time its radio session is ready; before that the server sends no UDP datagram at all and GET /udp shows instance_name null; the name is kept for the process, also after a reconnect with another slice letter. A server holds its name until its process ends; a killed or crashed process frees it; two servers fixing their name at the same moment never get the same one. The name is not a setting: the UDP configuration and PUT /udp have no instance_name; GET /udp shows it read-only as top-level instance_name; Logging & Reporting shows it as text. A radio change in Settings while running does not change the name; it takes effect at the next start. Listed defaults: when the server cannot check (the lock folder cannot be created or opened) it takes the base form without a number and runs normally (as CL-044-15 without a usable lock file); with WSTX_UDP=off no name is claimed, because nothing is sent; the check sees only servers of the same Windows user (lock under %LOCALAPPDATA%), as WSJT-X's instance lock in the user's temp folder; a saved udp.json that still names instance_name keeps loading, the key is dropped, and the next save writes the file without it. Details: WstxUdp::InstanceName. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_112_01_to_FR_012 from 'CL-112-01' to 'FR-012';
    requirement 'CL-112-02' {
        doc /* Status as WSJT-X sends it. Dial frequency: the confirmed CAT dial, else the operating selection's nominal frequency (selection.nominal_hz), else 0 (WSJT-X m_operatingFrequency, which follows the radio and, without CAT, the chosen band). Report: the contact's report, else the station's, written as WSJT-X's QString::number: "-9", "3", "0", "-24", never a "+" or a leading zero. Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_112_02_to_FR_012 from 'CL-112-02' to 'FR-012';
    requirement 'CL-112-03' {
        doc /* Decode delta time as WSJT-X sends it. Delta time is the record's dt_seconds rounded to one decimal: the value Band Activity shows (decimal rounding of the exact value, a tie away from zero; a magnitude below 0.05 is 0.0), sent as single precision. Unknown gives 0. This matches WSJT-X, which parses the time offset from its one-decimal decode line. A live record without a period start (uncorrelated) gives no Decode, and the cursor passes it, so it is never sent later. Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_112_03_to_FR_012 from 'CL-112-03' to 'FR-012';
    requirement 'CL-112-04' {
        doc /* Clear only on a band change, as WSJT-X. Clear is sent to each target that selects clear when the operating selection's band changes to another band. No Clear on: a mode change, a receive restart, a loss-only source epoch, a receive stop, a new live job on the same band, or any Erase of a browser list. Listed default (WSJT-X band_activity_cleared sends unconditionally): Clear is sent whether or not a Decode was sent since the last one. Listed default: a band change counts however it comes about: a band selection, or adoption of a CAT dial on another band (ReadbackSelectionAdoption); a frequency change within the same band is none. Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_112_04_to_FR_012 from 'CL-112-04' to 'FR-012';
    requirement 'CL-112-06' {
        doc /* Close at shutdown. On Ctrl+C, Ctrl+Break, console close, logoff and shutdown, the server sends one Close under its instance name to each active target that selects close. This runs after the ExitRelease transmit release and does not delay it: one non-blocking send per target, no wait. A killed process sends nothing, as WSJT-X when killed. A Flex server whose session was never ready has no name and sends nothing. Details: WstxUdp::OutboundRules, WstxTransmit::ExitRelease. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/main.rs";
    }
    dependency CL_112_06_to_FR_012 from 'CL-112-06' to 'FR-012';
    verification 'TC-112-001' {
        doc /* TC-112-001 — Instance name
             CL-112-01
             Setup: actual candidate UDP owner on the contact fixture (profile HB9BLA, JN47AA) with a fixture lock folder in the disposable profile directory, never the operator's; loopback peers on ephemeral ports; for (g) the native Flex session double.
             Steps: (a) owners on a profile without a radio, with icom7300://COM3?baud=9600&radio=94&controller=E0 saved, with a plain COM3. (b) second and third owners with the same radio while the first holds; two no-radio owners. (c) the first released: dropped, and a killed process (a child process holding the base form's lock, then killed); a new start each time. (d) an unusable lock folder (a file). (e) one owner with a target for all messages: steps, a decode, a band change, POST /contacts, the exit Close; GET /udp. (f) the radio changed while running. (g) native Flex: before the first ready, at ready with slice A, after a reconnect with letter B; a second Flex owner whose first ready also gives A. (h) WSTX_UDP=off.
             Expected (this table, from CL-112-01): (a) WSTX-Rust; WSTX-Rust - IC-7300; WSTX-Rust - IC-7300. (b) " 2", " 3"; WSTX-Rust, WSTX-Rust 2. (c) while the child lives a new owner gets WSTX-Rust - IC-7300 2; after either release the base form. (d) the base form, the start proceeds and Heartbeat and Status are sent with it. (e) Heartbeat, Status, Decode, Clear, QSO Logged, Close and Logged ADIF carry the name, and GET /udp instance_name equals it. (f) unchanged. (g) no datagram and instance_name null before; WSTX-Rust - FLEX-6600 A after; kept after the reconnect; the second WSTX-Rust - FLEX-6600 A 2. (h) no lock file created.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP on ephemeral ports only, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-01';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_01_verified_by_TC_112_001 from 'CL-112-01' to 'TC-112-001';
    verification 'TC-112-002' {
        doc /* TC-112-002 — Status dial and report
             CL-112-02
             Setup: actual candidate UDP owner and contact engine on the contact fixture; the CI-V radio double whose confirmed dial is 7074000.
             Steps: Status with neither a CAT dial nor a selection; with the selection 40m 7074000 and no CAT; with the selection 20m 14074000 and the radio double confirmed; the operating report set to -9, 3, 0, -24, 49, -50. The Status wire vector of TC-012-001 carries the report "-12", which is the same in this form.
             Expected (WSJT-X statusUpdate, QString::number, m_operatingFrequency.rx(); hand table): dial 0; 7074000; 7074000 (the CAT dial wins); report "-9", "3", "0", "-24", "49", "-50".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-02';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_02_verified_by_TC_112_002 from 'CL-112-02' to 'TC-112-002';
    verification 'TC-112-003' {
        doc /* TC-112-003 — Decode delta time
             CL-112-03
             Setup: actual candidate UDP owner on the contact fixture; an injected FT8 live job; a loopback peer selecting decode.
             Steps: the delta time of dt 0.04, -0.06, 0.25, -0.25, 1.349 and null; a record with dt 0.25 published and made uncorrelated (period_start_utc null), step; the same record correlated in the next period, step; step.
             Expected (Band Activity DT rule of client/recording.js; WSJT-X postDecode; hand table): 0.0, -0.1, 0.3, -0.3, 1.3, 0; no Decode for the uncorrelated record; one Decode for the correlated one, its float the single-precision value of the decimal text "0.3"; nothing after.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-03';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_03_verified_by_TC_112_003 from 'CL-112-03' to 'TC-112-003';
    verification 'TC-112-004' {
        doc /* TC-112-004 — Clear on a band change only
             CL-112-04
             Setup: actual candidate UDP owner on the contact fixture; peers A (all messages) and B (no clear); an injected FT8 live job; each step after a Decode was sent.
             Steps: band selection 20m -> 40m; the selection cleared and a CAT readback adoption onto 20m; a second band change to 40m with no Decode in between; then each alone: a mode change FT8 -> FT4 on the same band, a receive restart on the same band, a loss-only source epoch, a receive stop, a new live job on the same band, a frequency change within the band.
             Expected (CL-112-04; WSJT-X band_activity_cleared): exactly one Clear to A and none to B for each band change; no Clear for each of the others.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-04';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_04_verified_by_TC_112_004 from 'CL-112-04' to 'TC-112-004';
    verification 'TC-112-006' {
        doc /* TC-112-006 — Close at shutdown
             CL-112-06
             Setup: actual candidate UDP owner and #9 transmit owner on the recording hardware double; targets A (all messages), B (no close), C disabled, D an IPv6 group on an index no interface has (socket_unavailable); a native Flex fixture whose session double is never ready, with a peer.
             Steps: call the exit guard (the transmit release, then Close); the same on the Flex fixture.
             Expected (ExitRelease and CL-112-06): the release returns within 500 ms with nothing sent before it; A receives exactly one Close with id WSTX-Rust; B, C and D none; the Flex fixture sends nothing.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only, transmit double. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-06';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_06_verified_by_TC_112_006 from 'CL-112-06' to 'TC-112-006';
    requirement 'CL-112-05' {
        doc /* QSO Logged exchanges as WSJT-X. 1. The logged record carries its activity: when DirectLog stores a contact, the record gets the app field APP_WSTXRUST_ACTIVITY with the contact's activity at logging time, one of field_day, rtty, eu_vhf, na_vhf, ww_digi, arrl_digi, hound; it is absent for activity none, and a record without the field is activity none. In contacts.adi, the ADI export and the Logged ADIF datagram it is written after APP_WSTXRUST_CONTACT_ID and, when present, APP_WSTXRUST_SOURCE, and before any preserved unknown fields (WstxLogbook::LogRecord order). It is read back when the log loads. SaveContact accepts it; any other value is refused 400 log_invalid_field with field record.app_wstxrust_activity, as every other record field (WstxQsoControl::ContactWire), and nothing is stored. UpdateLogbook keeps a valid value and drops an invalid one, as it does for other contest values. Listed default (as for APP_WSTXRUST_SOURCE: the resave comparison covers the main field list only): a SaveContact resave of a stored contact id that differs only in the activity is 200 already_saved, with the stored record unchanged and no datagram; likewise a DirectLog store that differs only in the activity is already_saved and keeps the stored activity. Field name, values and these rules are listed defaults; the operator decided only that the activity is stored in the record. 2. Exchange sent and Exchange received are the exchange WSJT-X passes from its log dialog (widgets/mainwindow_qso.cpp captureLogQso, widgets/logqso.cpp xsent/xrcvd), chosen by the record's activity: na_vhf, ww_digi, arrl_digi: sent is the first 4 characters of MY_GRIDSQUARE, received the first 4 of GRIDSQUARE ("JN47" / "FN42"); a missing partner grid gives "", as WSJT-X with its default ZZ00 off. field_day, rtty, eu_vhf: the contact's exchange_sent / exchange_rcvd as ContestExchange / EuVhfExchange define them ("1A EMA" / "2B CT", "559 0003" / "579 MA", "550001 JN37VL" / "590003 IO91NP"), rebuilt from the stored record's contest fields, RST, grid and activity: the reverse of ContestExchange's and EuVhfExchange's log mapping. hound, none, or no field: "" / "". 3. DirectLog and SaveContact build them the same way, from the stored record, so the same record always gives the same exchanges; the explicit save exists to resend what a logging program missed. Details: WstxUdp::OutboundRules, WstxLogbook::LogRecord. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/logbook.rs; server/src/logbook_http.rs; server/src/contact_http.rs";
    }
    dependency CL_112_05_to_FR_012 from 'CL-112-05' to 'FR-012';
    verification 'TC-112-005' {
        doc /* TC-112-005 — QSO Logged exchanges
             CL-112-05
             Setup: actual candidate router, contact engine, logbook and UDP owner on the contact fixture (profile HB9BLA JN47AA); a loopback peer selecting qso_logged and logged_adif.
             Steps: each completed contact through DirectLog, then the same stored record through POST /contacts under a new contact id: field_day "1A EMA" / "2B CT"; rtty "559 MA" / "579 MA" and "559 0003" / "559 0013"; eu_vhf (profile JN37VL) "550001 JN37VL" / "590003 IO91NP"; na_vhf with partner FN42; ww_digi with partner FN42ab; arrl_digi without partner grid; hound; none. A record without app_wstxrust_activity (an older log); POST /contacts with app_wstxrust_activity "contest"; a resave of a stored contact id differing only in the activity; contacts.adi, the ADI export, a record with APP_WSTXRUST_SOURCE, and the export after a station restart.
             Expected (WSJT-X mainwindow_qso.cpp captureLogQso grids left 4, logqso.cpp; ContestExchange / EuVhfExchange; ContactWire refusal; CL-112-05 listed default), sent / received for both paths: "1A EMA" / "2B CT"; "559 MA" / "579 MA"; "559 0003" / "559 0013"; "550001 JN37VL" / "590003 IO91NP"; "JN47" / "FN42"; "JN47" / "FN42"; "JN47" / ""; "" / ""; "" / "". The older record "" / "". The Logged ADIF ends with the contact id then app_wstxrust_activity (absent for none); "contest" is refused 400 log_invalid_field field record.app_wstxrust_activity and nothing is stored; the resave is 200 already_saved, contacts.adi unchanged and no datagram; contacts.adi and the export carry <app_wstxrust_activity:6>na_vhf right after the contact id, after app_wstxrust_source on a record that has one, and it survives the restart.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-05';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_05_verified_by_TC_112_005 from 'CL-112-05' to 'TC-112-005';
}
