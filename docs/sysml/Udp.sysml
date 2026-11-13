package WstxUdp {
    private import ScalarValues::*;
    private import ModelNotes::DiffersFromSource;
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
    dependency wireClause from UdpWire to WstxRequirements::'CL-040-01';
    dependency outboundClause from OutboundRules to WstxRequirements::'CL-040-01';
    dependency targetClause from UdpConfiguration to WstxRequirements::'CL-040-02';
    dependency httpClause from UdpHttp to WstxRequirements::'CL-040-02';
    dependency inboundClause from InboundRules to WstxRequirements::'CL-040-03';
    dependency textClause from OutboundRules to WstxRequirements::'CL-040-04';
    dependency statusCadenceClause from OutboundRules to WstxRequirements::'CL-040-07';
    dependency instanceClause from InstanceName to WstxRequirements::'CL-112-01';
    dependency statusClause from OutboundRules to WstxRequirements::'CL-112-02';
    dependency decodeClause from OutboundRules to WstxRequirements::'CL-112-03';
    dependency clearClause from OutboundRules to WstxRequirements::'CL-112-04';
    dependency exchangeClause from OutboundRules to WstxRequirements::'CL-112-05';
    dependency closeClause from OutboundRules to WstxRequirements::'CL-112-06';
}
