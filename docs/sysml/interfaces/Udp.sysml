package WstxUdp {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import ModelNotes::*;
    doc /* The WSJT-X-compatible UDP interface of the station: the datagrams it sends to logging
         and companion programs, what it reads from them, its targets and their configuration.
         The message formats are WSJT-X's and are referred to (WsjtxMessages); the
         configuration, its file and its HTTP routes are the product's and are defined here:
         in udp.json and in the bodies of both routes a feature's key is its name in
         snake_case, every key is required, null stands for an absent value, and an object
         with a missing or an unknown key is refused.
         Declared coverage and a verification case are not an execution result. */

    // ------------------------------------------------------------ the interface and its host
    part def ListeningProgram {
        doc /* A program outside the product that receives the station's datagrams at one
             target address, such as a logger or a map; for a multicast target, every program
             joined to the group. */
        port station : ~WsjtxMessages;
    }
    port def WsjtxMessages {
        doc /* The exchange with one target, written from the station's side; the program uses
             the conjugate. Each item is one UDP datagram in the format of the source: the
             header, the message type numbers, the field order and the wire type of every
             field are the source's. The station is a client in the source's terms. An item
             below has one feature per field of the source, named after it, in the source's
             order, and states only how the station fills it. The header id is
             UdpConfiguration::instanceName and the header schema is TargetStatus::schema.
             Messages of the source that are not listed are never sent, among them Decode
             with New false, WSPRDecode and InhibitStatus. */
        @FollowsSource { reference = "WSJT-X v3.3.0-beta6: Network/NetworkMessage.hpp " +
            "(formats), Network/MessageClient.cpp (the client side), " +
            "widgets/mainwindow.cpp (when a message is sent and its field values)"; }
        @NotStated { what = "the port of this type on WstxArchitecture::StationService and " +
            "its connection to the listening programs; the architecture declares neither"; }
        out item heartbeat : Heartbeat;
        out item status : Status;
        out item decode : Decode;
        out item clear : Clear;
        out item qsoLogged : QsoLogged;
        out item loggedAdif : LoggedAdif;
        out item close : Close;
        in item peerHeartbeat : PeerHeartbeat;
    }
    metadata sourceRelease : Conflict about WsjtxMessages, WstxProductScope::BehaviorBaseline {
        what = "v3.3.0-beta6 in WsjtxMessages; network_message.rs and the vectors of " +
            "TC-012-001 were written from v3.3.0-beta5; v3.3.0-beta4 in BehaviorBaseline";
    }
    attribute def UdpWire {
        doc /* The station's choices within the source's protocol. */
        attribute startSchema : Integer = 2 {
            doc /* The header schema of a target's datagrams until PeerHeartbeat raises it. */
        }
        attribute maximumSchema : Integer = 3 {
            doc /* The highest schema the station offers and accepts. For every field type
                 the station sends, schema 2 and 3 serialize alike. */
        }
        attribute pulseSeconds : Integer = 15 {
            doc /* The source's NetworkMessage::pulse. */
        }
        attribute inboundDatagramBytesMax : Integer = 4096;
    }
    attribute udpWire : UdpWire;
    enum def OutboundMessage {
        enum heartbeat; enum status; enum decode; enum clear; enum qso_logged; enum close;
        enum logged_adif;
        doc /* The messages a target can select, in the order a selection is stored. Each
             stands for the item of WsjtxMessages of the same name; a literal is spelt as on
             the configuration wire. */
    }

    // ------------------------------------------------------------ the messages
    item def Heartbeat {
        attribute maximumSchemaNumber : Integer = udpWire.maximumSchema;
        attribute version : String { doc /* The version of the station program. */ }
        attribute revision : String = "";
    }
    item def Status {
        attribute dialFrequencyHz : Integer {
            doc /* The dial frequency the radio confirmed over CAT; 0 without one. */
            @Conflict { what = "0 without a confirmed CAT dial here and in udp.rs " +
                "status_of; WSJT-X always sends its operating frequency " +
                "(MainWindow::statusUpdate)"; }
        }
        attribute mode : String {
            doc /* "FT8" or "FT4", the WstxContact::StationOperatingMode. */
        }
        attribute dxCall : String { doc /* The contact's DX call; empty without one. */ }
        attribute report : String {
            doc /* The contact's report, else the station's current report, as a sign and
                 two digits ("-09", "+03"). */
            @Conflict { what = "sign and two digits here and in udp.rs (\"-09\", \"+03\"); " +
                "WSJT-X sends the plain number (\"-9\", \"3\"; MainWindow::statusUpdate)"; }
        }
        attribute txMode : String { doc /* As mode. */ }
        attribute txEnabled : Boolean { doc /* Enable Tx is on (the station is armed). */ }
        attribute transmitting : Boolean { doc /* The transmit owner is keying. */ }
        attribute decoding : Boolean {
            doc /* True from the start of the live decoder's work on an analysis window
                 until that decode returns, whether completed, abandoned, failed or
                 cancelled. */
        }
        attribute rxDf : Integer { doc /* The Rx offset in Hz (WstxContact::FrequencyControls). */ }
        attribute txDf : Integer { doc /* The Tx offset in Hz. */ }
        attribute deCall : String { doc /* The profile's callsign. */ }
        attribute deGrid : String { doc /* The profile's locator. */ }
        attribute dxGrid : String { doc /* The contact's DX grid; empty without one. */ }
        attribute txWatchdog : Boolean { doc /* WstxContact::TxWatchdog has expired. */ }
        attribute subMode : String = "";
        attribute fastMode : Boolean = false;
        attribute specialOperationMode : WstxContact::SpecialActivity {
            doc /* The activity of the contact settings, sent as the source's value of the
                 activity of the same name; rtty is its RTTY RU. The source's Fox value is
                 never sent. */
        }
        attribute frequencyTolerance : Integer {
            doc /* Always the source's value for not applicable. */
        }
        attribute trPeriod : Integer { doc /* 15 in FT8, 7 in FT4. */ }
        attribute configurationName : String { doc /* The profile's display name. */ }
        attribute txMessage : String {
            doc /* The contact's next message; empty without one. */
        }
    }
    item def Decode {
        doc /* One decoded record of the current live FT8 or FT4 job, taken from the
             published live record (period_start_utc, snr_db, dt_seconds, frequency_hz,
             text). A record without a period start gives no Decode. */
        attribute isNew : Boolean = true;
        attribute time : Integer {
            doc /* The record's period start, in ms since UTC midnight. */
        }
        attribute snr : Integer {
            doc /* snr_db rounded to a whole dB, half away from zero; 0 when unknown. */
        }
        attribute deltaTime : Real { doc /* dt_seconds, not rounded; 0 when unknown. */ }
        attribute deltaFrequency : Integer { doc /* frequency_hz rounded to a whole Hz. */ }
        attribute mode : String {
            doc /* The source's decoded-line marker of the job's mode. */
        }
        attribute messageText : String {
            doc /* The record's text in the form WSJT-X prints: a standard message with R
                 and a signal report reads "R-09" or "R+03" with no space after R. Every
                 other text is unchanged, a hashed call as the record gives it
                 (WstxOfflineDecode::HashResolution). */
        }
        attribute lowConfidence : Boolean = false;
        attribute offAir : Boolean = false;
        @Conflict { what = "decodes of a played recording are never sent here and in " +
            "udp.rs; WSJT-X sends them with Off air true (MainWindow::postDecode)"; }
        @Conflict { what = "Delta time unrounded here and in udp.rs decode_of; WSJT-X " +
            "sends the value of its decode line, one decimal (MainWindow::postDecode)"; }
    }
    item def Clear;
    item def QsoLogged {
        doc /* One stored contact; each feature names the WstxContact::LogRecord field it
             is taken from, empty or 0 when the record lacks it. */
        attribute dateTimeOff : String { doc /* QSO_DATE_OFF and TIME_OFF, UTC. */ }
        attribute dxCall : String { doc /* CALL. */ }
        attribute dxGrid : String { doc /* GRIDSQUARE. */ }
        attribute txFrequencyHz : Integer { doc /* FREQ in Hz. */ }
        attribute mode : String { doc /* "FT8" or "FT4": SUBMODE where MODE is MFSK. */ }
        attribute reportSent : String { doc /* RST_SENT. */ }
        attribute reportReceived : String { doc /* RST_RCVD. */ }
        attribute txPower : String { doc /* TX_PWR. */ }
        attribute comments : String { doc /* COMMENT. */ }
        attribute name : String = "";
        attribute dateTimeOn : String { doc /* QSO_DATE and TIME_ON, UTC. */ }
        attribute operatorCall : String = "";
        attribute myCall : String { doc /* STATION_CALLSIGN. */ }
        attribute myGrid : String { doc /* MY_GRIDSQUARE. */ }
        attribute exchangeSent : String = "" {
            @Conflict { what = "exchange sent and received always empty here and in " +
                "udp.rs logged_of, also for a contest contact " +
                "(WstxContact::ContestExchange); WSJT-X sends the contest exchanges " +
                "(MainWindow::acceptQSO)"; }
        }
        attribute exchangeReceived : String = "";
        attribute adifPropagationMode : String = "";
        attribute afterDocumented : String = "" {
            doc /* The three fields MessageClient::qso_logged writes after the documented
                 ones (satellite, satellite mode, Rx frequency): each empty. */
        }
    }
    item def LoggedAdif {
        attribute adifText : String {
            doc /* The source's ADIF text with the header line "<programid:9>WSTX-Rust" and
                 the stored record's ADI fields as its one record. */
            @DiffersFromSource { what = "programid names this product, not WSJT-X"; }
        }
    }
    item def Close;
    item def PeerHeartbeat {
        doc /* A Heartbeat a target sends back. Only its header is read; whatever follows
             the header is not. Accepted is a datagram of at most
             UdpWire::inboundDatagramBytesMax bytes, sent from the target's own address
             and port, with the source's magic, a schema from UdpWire::startSchema to
             UdpWire::maximumSchema, the Heartbeat type and a non-empty valid UTF-8 id
             equal to UdpConfiguration::instanceName. */
        attribute schema : Integer;
        attribute id : String;
    }

    // ------------------------------------------------------------ targets and configuration
    attribute def SocketAddressText :> String {
        doc /* "a.b.c.d:port" or "[v6]:port", port 1..65535. */
    }
    attribute def UdpTarget {
        doc /* One destination; its address is its identity within the list. */
        attribute address : SocketAddressText {
            doc /* Unicast, an IPv4 multicast group or an IPv6 multicast group. Refused: an
                 unspecified address, 255.255.255.255, and an IPv6 group of scope 0 or 15. */
        }
        attribute enabled : Boolean;
        attribute multicastTtl : Integer {
            doc /* The TTL of an IPv4 group and the hop limit of an IPv6 group; unused for
                 a unicast address. */
        }
        attribute multicastInterface : String[0..1] {
            doc /* Absent: the system's default interface. For an IPv6 group an interface
                 index as decimal text 1..4294967295 without sign or leading zero, never
                 an interface name; an IPv6 group of scope 1 or 2 requires it. For every
                 other address an IPv4 address, unused for a unicast address. */
        }
        attribute messages : OutboundMessage[0..7] {
            doc /* Each literal at most once, accepted in any order and stored in the order
                 of OutboundMessage; empty sends nothing. */
        }
        assert constraint ttlRange { multicastTtl >= 1 and multicastTtl <= 255 }
    }
    attribute def UdpConfiguration {
        attribute instanceName : String {
            doc /* 1..64 UTF-8 bytes, no control character, no leading or trailing space. */
        }
        attribute targets : UdpTarget[0..16] ordered {
            doc /* No two targets share an address. */
        }
    }
    attribute defaultConfiguration : UdpConfiguration {
        doc /* instanceName "WSTX-Rust" and one target: 127.0.0.1:2237, enabled,
             multicastTtl 1, no interface, all of OutboundMessage. */
    }
    attribute def UdpFile :> UdpConfiguration {
        doc /* udp.json in the selected profile's directory, written atomically under the
             profile's lock like the profile's other files (WstxProfiles). A missing file
             is defaultConfiguration at revision 0. An unreadable or invalid file and a file
             of another profile leave the station without a configuration
             (ConfigurationError). A target's key accept_commands is ignored when the file
             is read and is not written. */
        attribute schemaVersion : Integer = 1;
        attribute profileId : String;
        attribute revision : Integer {
            doc /* 0..WstxProfiles::maxRevision; each accepted PutUdp adds one. */
        }
    }
    enum def ConfigurationError { enum invalid_configuration; }
    enum def TargetError {
        enum socket_unavailable; enum send_failed;
        doc /* socket_unavailable: the target's socket could not be opened or set up.
             send_failed: the last send failed; the next successful send clears it. */
    }
    attribute def TargetStatus {
        doc /* The volatile state of one configured target. */
        attribute address : SocketAddressText;
        attribute active : Boolean { doc /* The target's socket is open. */ }
        attribute schema : Integer = udpWire.startSchema;
        attribute lastSendUtcMs : Integer[0..1] {
            doc /* The time of the last successful send; absent before the first. */
        }
        attribute error : TargetError[0..1] { doc /* Absent: no error. */ }
    }
    item def UdpSnapshot {
        doc /* The reply to GetUdp and to an accepted PutUdp. profileId and bootId are those
             of the selected profile and of the running station process; revision is that
             of UdpFile. */
        attribute v : Integer = 1;
        attribute profileId : String;
        attribute bootId : String;
        attribute revision : Integer;
        attribute configuration : UdpConfiguration[0..1] {
            doc /* Absent exactly when configurationError is present. */
        }
        attribute configurationError : ConfigurationError[0..1];
        attribute status : TargetStatus[0..16] ordered {
            doc /* One per target, in the order of configuration.targets. */
        }
    }
    item def GetUdp {
        doc /* GET /udp without query or body, under the access rules of the station's
             reading routes (WstxProfiles). Answered by UdpSnapshot. */
    }
    item def PutUdp {
        doc /* PUT /udp without query, as application/json of at most bodyBytesMax bytes,
             under the access rules of the station's changing routes (WstxProfiles).
             Answered by UdpSnapshot when accepted, else by a refusal in the form of
             WstxProfiles::HttpProfileError with one PutRefusal and the refused field. */
        attribute bodyBytesMax : Integer = 8192;
        attribute v : Integer = 1;
        attribute profileId : String;
        attribute bootId : String;
        attribute expectedRevision : Integer;
        attribute configuration : UdpConfiguration;
    }
    enum def PutRefusal {
        enum request_too_large; enum unsupported_media_type; enum invalid_request;
        enum unsupported_version; enum wrong_profile; enum state_conflict;
        enum stale_revision; enum counter_exhausted; enum storage_unavailable;
        doc /* With HTTP status and cause, in the order checked: invalid_request 400 for a
             query; unsupported_media_type 415; request_too_large 413 above
             PutUdp::bodyBytesMax; invalid_request 400 for a body that is not the JSON
             object of PutUdp or holds a value outside its type, with the field (v,
             profile_id, boot_id, expected_revision, configuration, instance_name, targets,
             targets[i] or targets[i].<key>); unsupported_version 400 for another v;
             wrong_profile 403; state_conflict 409 for another boot_id; stale_revision 409
             for another expected_revision; counter_exhausted 409 at
             WstxProfiles::maxRevision; storage_unavailable 503 when the file cannot be
             written. A refusal changes nothing. */
        @Conflict { what = "every invalid_request before unsupported_version here; " +
            "udp.rs Owner::put answers unsupported_version for another v before it " +
            "checks profile_id, boot_id, expected_revision and configuration"; }
    }

    // ------------------------------------------------------------ the function
    action def ReportToPrograms {
        doc /* The function of WstxArchitecture::StationService that this package describes;
             the part performs it as its action reportToPrograms. It observes station state
             and results and sends them; it enters no command into the station and holds no
             station state and no modem or transmit authority. It works on each station
             step, whether or not a browser is connected.
             A datagram goes to a target only while the target is enabled, its socket is
             open and its messages select the type. In every other case nothing is sent to
             that target and nothing is kept for it for later.
             All its tests are the bound contract tests in server/src/udp_tests.rs and
             server/tests/udp_vectors.rs; it has no detail tests of its own. */
        attribute implementation : String = "server/src/udp.rs; server/src/network_message.rs";
        attribute configuration : UdpConfiguration[0..1];
        attribute targetStatus : TargetStatus[0..16] ordered;
        action openTarget : OpenTarget;
        action pulse : Pulse;
        action sendStatus : SendStatus;
        action sendDecodes : SendDecodes;
        action sendLoggedContact : SendLoggedContact;
        action readFromTarget : ReadFromTarget;
        action serveConfiguration : ServeConfiguration;
    }
    action def OpenTarget {
        in opened : UdpTarget;
        out result : TargetStatus;
        doc /* Activates an enabled target: at station start for each target of a valid
             configuration, and when ServeConfiguration adds or changes one.
             - The target gets a socket of its own with a source port the system chooses,
               bound to the loopback address for a loopback target.
             - A multicast target sends with multicastTtl, through multicastInterface when
               given, and with multicast loopback on.
             - A socket that cannot be opened or set up leaves the target inactive with
               socket_unavailable until its address, enabled, TTL or interface changes; an
               interface index that no interface has is such a case.
             - The first station step after activation is a Pulse and sends a Status.
             With WSTX_UDP=off in the station's environment no target is activated; the
             configuration and its routes work unchanged. */
    }
    action def Pulse {
        out sent : Heartbeat;
        doc /* Sends a Heartbeat to a target at its activation and whenever
             UdpWire::pulseSeconds have passed since its previous pulse (MessageClient
             heartbeat). A pulse occurs for every active target, also one that does not
             select heartbeat. */
    }
    action def SendStatus {
        out sent : Status;
        doc /* Sends the Status to a target:
             - at its activation;
             - whenever its content differs from the Status last sent to that target;
             - once for each live decoder window begun since the last Status, also when
               that window began and ended between two station steps;
             - at each Pulse, also when nothing changed. */
        @Conflict { what = "Status is sent again at each pulse here and in udp.rs " +
            "Owner::step; WSJT-X sends Status only on a change " +
            "(MainWindow::statusUpdate)"; }
    }
    action def SendDecodes {
        out sent : Decode[0..*];
        out cleared : Clear[0..1];
        doc /* Sends one Decode for each decoded record of the current live job, once, in
             the order of the record sequence. A record published while no target could
             receive it is not sent later.
             Sends Clear when the current live job changes or ends after at least one of
             its records gave a Decode. */
        @Conflict { what = "Clear at a change or end of the live job here and in udp.rs " +
            "Owner::step; WSJT-X sends Clear when the operator erases Band Activity " +
            "(MainWindow::band_activity_cleared)"; }
    }
    action def SendLoggedContact {
        in stored : WstxContact::LogRecord;
        out logged : QsoLogged;
        out adif : LoggedAdif;
        doc /* Sends QsoLogged and then LoggedAdif when WstxContact::DirectLog stores a
             contact's record for the first time and when WstxContact::SaveContact stores a
             record with outcome saved. A replaced, unchanged or already saved record
             sends nothing. */
    }
    action def ReadFromTarget {
        in received : PeerHeartbeat[0..1];
        doc /* On each station step reads what arrived at each target's socket. An accepted
             PeerHeartbeat raises TargetStatus::schema of its target to its schema and never
             lowers it. Every other datagram, from a target or from anyone else, whatever
             its type and size, is dropped: it has no effect on the station, changes no
             state, is not counted and is not answered. A datagram too large to read does
             not hold back the datagrams behind it. A multicast target is never the sender
             of a datagram, so its schema stays UdpWire::startSchema. */
        @Conflict { what = "no inbound message acts here and in udp.rs negotiate; WSJT-X " +
            "acts on Reply, Clear, Close, Replay, Halt Tx, Free Text, Location, " +
            "Highlight Callsign, Switch Configuration, Configure, AnnotationInfo and " +
            "TxInhibit while Accept UDP requests is on (MessageClient parse_message)"; }
        @Conflict { what = "only a Heartbeat from the target's address with the " +
            "station's id raises the schema here and in udp.rs; MessageClient takes a " +
            "higher schema from any readable datagram, whatever its type, id and sender"; }
    }
    metadata haltOverUdp : Conflict about ReadFromTarget, WstxTransmit::TransmitHaltUse,
        WstxMcp::OperatingAutomation {
        what = "TransmitHaltUse and OperatingAutomation name UDP Halt Tx as a remote " +
            "emergency stop; ReadFromTarget drops it";
    }
    action def ServeConfiguration {
        in get : GetUdp[0..1];
        in put : PutUdp[0..1];
        out reply : UdpSnapshot[0..1];
        out refusal : PutRefusal[0..1];
        doc /* Exactly one of get and put arrives; a put gives exactly one of reply and
             refusal. Answers GetUdp with the UdpSnapshot. An accepted PutUdp is saved as
             UdpFile with the next revision and answered with the UdpSnapshot after the
             change; the running targets follow it at once:
             - A target whose address, enabled, TTL and interface are unchanged keeps its
               socket, schema and status; a change of its messages alone applies from the
               next datagram.
             - A target that was removed, disabled or changed in address, TTL or interface
               gets a Close on its old socket, when it selected close, before that socket
               is given up.
             - An added target and the changed ones are activated (OpenTarget).
             While the station has no configuration no target exists; the first accepted
             PutUdp provides one. */
        @NotStated { what = "what a change of instanceName does to the targets that are " +
            "otherwise unchanged (udp.rs Owner::reconcile sends them Close under the old " +
            "name and activates them again)"; }
        @Conflict { what = "no Close when the station process ends, here and in udp.rs; " +
            "WSJT-X sends Close when it shuts down (MessageClient closedown)"; }
    }
    dependency fileStoredBy from UdpFile to WstxArchitecture::PersistedProfile;

    // ------------------------------------------------------------ requirements
    // CL-040-05, CL-040-08, TC-012-005 and TC-012-008 are retired and are not used again.
    requirement 'CL-040-01' {
        doc /* The station MUST send each enabled target the messages it selects, in the
             format of WsjtxMessages and at the occasions ReportToPrograms states. */
        subject station : WstxArchitecture::StationService;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/network_message.rs; server/src/udp.rs; server/src/logbook_http.rs";
    }
    requirement 'CL-040-02' {
        doc /* The station MUST keep the UdpConfiguration of the selected profile as UdpFile,
             serve and change it by GetUdp and PutUdp, and report the TargetStatus of each
             target. */
        subject station : WstxArchitecture::StationService;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/udp.rs; server/src/profile.rs; server/src/main.rs";
    }
    requirement 'CL-040-03' {
        doc /* The station MUST NOT act on any datagram it receives over this interface;
             only an accepted PeerHeartbeat raises its target's schema (ReadFromTarget). */
        subject station : WstxArchitecture::StationService;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/network_message.rs";
    }
    requirement 'CL-040-04' {
        doc /* The text of a Decode MUST have the form Decode::messageText states. */
        subject station : WstxArchitecture::StationService;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    requirement 'CL-040-06' {
        doc /* The station MUST admit an IPv6 multicast group as a UdpTarget and send to it
             with its hop limit and through its interface (OpenTarget). */
        subject station : WstxArchitecture::StationService;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    requirement 'CL-040-07' {
        doc /* The station MUST send the Status at every occasion SendStatus states, so that
             a program sees at least one Status in each T/R period with a decoder window. */
        subject station : WstxArchitecture::StationService;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/recording.rs";
    }
    satisfy 'CL-040-01' by WstxArchitecture::physicalStation.backend.stations.station;
    satisfy 'CL-040-02' by WstxArchitecture::physicalStation.backend.stations.station;
    satisfy 'CL-040-03' by WstxArchitecture::physicalStation.backend.stations.station;
    satisfy 'CL-040-04' by WstxArchitecture::physicalStation.backend.stations.station;
    satisfy 'CL-040-06' by WstxArchitecture::physicalStation.backend.stations.station;
    satisfy 'CL-040-07' by WstxArchitecture::physicalStation.backend.stations.station;
    dependency CL_040_01_to_FR_012 from 'CL-040-01' to 'FR-012';
    dependency CL_040_02_to_FR_012 from 'CL-040-02' to 'FR-012';
    dependency CL_040_02_to_FR_001 from 'CL-040-02' to 'FR-001';
    dependency CL_040_03_to_FR_012 from 'CL-040-03' to 'FR-012';
    dependency CL_040_03_to_FR_008 from 'CL-040-03' to 'FR-008';
    dependency CL_040_04_to_FR_012 from 'CL-040-04' to 'FR-012';
    dependency CL_040_06_to_FR_012 from 'CL-040-06' to 'FR-012';
    dependency CL_040_07_to_FR_012 from 'CL-040-07' to 'FR-012';

    // ------------------------------------------------------------ verification cases
    verification 'TC-012-001' {
        doc /* The encoded datagrams and the reading of a Heartbeat, against byte vectors.
             Setup: hand-constructed byte vectors in server/tests/vectors/udp/, each written
             field by field from the source's NetworkMessage.hpp with the construction
             recorded in the file, independent of the encoder; no network.
             (a) Heartbeat, Status, Decode, Clear, QSO Logged, Close and Logged ADIF
                 encoded from a vector's inputs: the bytes equal the vector.
             (b) A Heartbeat of schema 3 with its fields, of schema 2 without them, and
                 with trailing bytes: read with the vector's schema and id.
             (c) Clear, Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight
                 Callsign, Switch Configuration, Configure and type 18; a Heartbeat with
                 a wrong magic, schema 1, schema 4, a truncated id, an invalid UTF-8 id,
                 a null id, and of 4097 bytes: each reads as nothing.
             (d) Arbitrary bytes and every truncation of a vector: read as nothing,
                 without a failure.
             (e) The decoder text "K1ABC W9XYZ R -09" gives "K1ABC W9XYZ R-09" and
                 "R +03" gives "R+03"; other texts are unchanged. */
        subject station : WstxArchitecture::StationService;
        objective {
            verify 'CL-040-01';
            verify 'CL-040-03';
            verify 'CL-040-04';
        }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no network";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "server/tests/udp_vectors.rs; server/src/udp_tests.rs";
    }
    verification 'TC-012-002' {
        doc /* The outbound messages to several targets.
             Setup: the station's router, UDP function, contact engine and transmit owner
             on the recording hardware double; profile HB9BLA JN47AA; an injected FT8 live
             job; hand-authored rows "CQ K1ABC FN42" (1234.6 Hz, -12.4 dB) and "HB9BLA
             W9XYZ R-09" (decoder text "HB9BLA W9XYZ R -09", 900.0 Hz, -3.0 dB); loopback
             peers on ephemeral ports set as targets by PutUdp: A all messages, B decode
             only.
             (a) One station step: A receives Heartbeat (id WSTX-Rust, maximum schema 3)
                 and Status (mode FT8, DE HB9BLA JN47AA, Tx enabled false).
             (b) The rows are published, one step: A and B receive Decode with New true,
                 Time the period start in ms since midnight, Mode "~": snr -12, df 1235,
                 "CQ K1ABC FN42"; then snr -3, df 900, "HB9BLA W9XYZ R-09".
             (c) The operating report changes, one step: A receives a changed Status.
             (d) A second live job starts, one step: A receives Clear.
             (e) A contact is saved through POST /contacts: A receives QSO Logged (DX
                 call K1ABC, mode FT8, its times) and then Logged ADIF that begins with
                 the ADIF header, contains "<call:5>K1ABC" and ends " <EOR>". The same
                 command repeated and the same contact under another command_id
                 (already_saved): nothing.
             (f) A is disabled by PutUdp: A receives Close; B keeps its socket.
             (g) Over the whole case B received exactly the two Decode datagrams, and
                 UdpSnapshot shows a last send and no error for both.
             (h) Planned, no test yet: a decoded row without a period start gives no
                 Decode. */
        subject station : WstxArchitecture::StationService;
        objective {
            verify 'CL-040-01';
            verify 'CL-040-02';
            verify 'CL-040-04';
        }
        attribute level : Integer = 2;
        attribute location : String =
            "Windows development PC, isolated, loopback UDP on ephemeral ports, no RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "server/src/udp_tests.rs::tc_012_002_outbound_messages_to_several_targets";
    }
    verification 'TC-012-003' {
        doc /* No inbound message acts; a Heartbeat negotiates the schema.
             Setup: as TC-012-002 with one target A and another socket X; a published CQ
             row; the browser has armed the station with Enable Tx.
             (a) From A and from X to A's socket: Halt Tx, Clear, a Reply matching the
                 row, Close, Replay, Free Text, Location "JN36AB", Highlight Callsign,
                 Switch Configuration and Configure, then one step: the station is still
                 armed with its last disarm cause unchanged, no contact is prepared, the
                 profile grid and the Status DE grid are unchanged, and A received no
                 Decode with New false.
             (b) UdpSnapshot has exactly the keys v, profile_id, boot_id, revision,
                 configuration, configuration_error and status, and a status entry exactly
                 active, address, error, last_send_utc_ms and schema.
             (c) One step each: a schema-3 Heartbeat from X; from A a schema-3 Heartbeat
                 with another id, a schema-4 Heartbeat, a schema-3 Replay and a schema-3
                 Halt Tx: A's schema stays 2.
             (d) From A a 5000-byte datagram followed by a schema-3 Heartbeat, one step:
                 A's schema is 3.
             (e) From A a schema-2 Heartbeat, one step: A's schema stays 3; a further
                 decode is published, one step: the datagrams at A carry header schema 3. */
        subject station : WstxArchitecture::StationService;
        objective {
            verify 'CL-040-03';
        }
        attribute level : Integer = 2;
        attribute location : String =
            "Windows development PC, isolated, loopback UDP, transmit and radio doubles";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "server/src/udp_tests.rs::tc_012_003_no_inbound_message_acts_on_the_station";
    }
    verification 'TC-012-004' {
        doc /* Target configuration and persistence.
             Setup: the station's router on a disposable profile directory without
             udp.json; a second profile with an invalid udp.json.
             (a) GetUdp: defaultConfiguration at revision 0.
             (b) PutUdp of A (unicast, decode only) and B (239.255.0.1:2237, TTL 2,
                 interface 127.0.0.1): revision 1, the messages in the order of
                 OutboundMessage; unchanged after the station opens the profile again.
             (c) PutUdp, each alone, is refused with its PutRefusal, status and field and
                 saves nothing: a stale revision, another profile, another boot, an
                 unknown key, 17 targets, a duplicate address, port 0, 0.0.0.0, ff02::1
                 without an interface, TTL 0 and 256, an interface that is not IPv4, a
                 duplicated and an unknown message name, accept_commands on a target, an
                 empty and a 65-byte instance name, v 2, text/plain, 8193 bytes, a query.
             (d) GetUdp on the invalid profile: no configuration, invalid_configuration,
                 no status entry and no socket.
             (e) A row published in that state and then a valid PutUdp: the target
                 receives Heartbeat and Status only.
             (f) A udp.json whose target also names accept_commands true: read without
                 an error, the target otherwise unchanged and active; the next PutUdp
                 writes a file without that key.
             (g) Planned, no test yet: a PutUdp whose file cannot be written is refused
                 storage_unavailable, and revision, configuration and sockets are
                 unchanged. */
        subject station : WstxArchitecture::StationService;
        objective {
            verify 'CL-040-02';
        }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, loopback only";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "server/src/udp_tests.rs";
    }
    verification 'TC-012-006' {
        doc /* IPv6 multicast targets.
             Setup: the station's router and UDP function on a disposable profile; a peer
             socket joined to the link-local group ff12::5754:5358 on the Windows loopback
             pseudo-interface (index 1).
             (a) PutUdp, each alone, is refused invalid_request with its field and saves
                 nothing: ff00::1, ff0f::1 and ff1f::1 (address); the group and ff01::1
                 without an interface (multicast_interface); hop limit 0 and 256
                 (multicast_ttl); an IPv4 group with interface "1"; the interfaces "0",
                 "01", "-1", "+1", " 1", "4294967296", "Ethernet", "127.0.0.1", "::1", ""
                 and the number 1 (multicast_interface).
             (b) One PutUdp of the group at the peer's port with hop limit 2 and interface
                 "1", [ff05::5754:5358]:2237 with hop limit 255 and interface "1",
                 [ff15::5754:5358]:2238 with interface "4000000000", and a disabled
                 [ff08::5754:5358]:2239 without an interface: saved as given, and
                 unchanged after the station opens the profile again.
             (c) The list plus a disabled [::1]:2240 with interface "127.0.0.1" is
                 admitted; with interface "1" it is refused, field
                 targets[4].multicast_interface.
             (d) The group's socket has hop limit 2, interface 1 and loopback on; the
                 site-local one hop limit 255; the target with index 4000000000 shows
                 active false and socket_unavailable.
             (e) One station step: the joined peer receives Heartbeat and then Status,
                 header schema 2, id WSTX-Rust. */
        subject station : WstxArchitecture::StationService;
        objective {
            verify 'CL-040-06';
        }
        attribute level : Integer = 2;
        attribute location : String =
            "Windows development PC, isolated, loopback IPv6 multicast only";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "server/src/udp_tests.rs::tc_012_006_ipv6_multicast_targets";
    }
    verification 'TC-012-007' {
        doc /* The occasions of a Status, with decoder windows and the pulse.
             Setup: the station's UDP function, contact engine and transmit owner on the
             recording hardware double; profile HB9BLA JN47AA; loopback peers A (all
             messages), B (status only) and C (heartbeat and decode); time is set, not
             waited for.
             (a) First step: A receives Heartbeat and then Status with decoding false, B
                 the Status, C the Heartbeat. A further step: nothing.
             (b) Twice: a window decode begins, two steps, it ends, one step: at the
                 begin one Status with decoding true to A and B and none while it lasts;
                 at the end one Status with decoding false.
             (c) A window begins and ends between two steps: one Status with decoding
                 false to A and B.
             (d) 14 s after the pulse, one step: nothing. At 15 s: A receives Heartbeat
                 and then a Status equal byte for byte to the last one, B that Status, C
                 the Heartbeat. A further step: nothing. C never receives a Status.
             (e) The live worker on the recording fixture analyses one window with a
                 late window waiting, and one with a replacing window: the decoder
                 activity reads (false, 0) before, decoding true with the window count 1
                 and then 2 while it works, and (false, 2) after, in both. */
        subject station : WstxArchitecture::StationService;
        objective {
            verify 'CL-040-07';
        }
        attribute level : Integer = 2;
        attribute location : String =
            "Windows development PC, isolated, loopback UDP on ephemeral ports, no RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "server/src/udp_tests.rs; server/src/recording_tests.rs";
    }
    dependency CL_040_01_verified_by_TC_012_001 from 'CL-040-01' to 'TC-012-001';
    dependency CL_040_01_verified_by_TC_012_002 from 'CL-040-01' to 'TC-012-002';
    dependency CL_040_02_verified_by_TC_012_002 from 'CL-040-02' to 'TC-012-002';
    dependency CL_040_02_verified_by_TC_012_004 from 'CL-040-02' to 'TC-012-004';
    dependency CL_040_03_verified_by_TC_012_001 from 'CL-040-03' to 'TC-012-001';
    dependency CL_040_03_verified_by_TC_012_003 from 'CL-040-03' to 'TC-012-003';
    dependency CL_040_04_verified_by_TC_012_001 from 'CL-040-04' to 'TC-012-001';
    dependency CL_040_04_verified_by_TC_012_002 from 'CL-040-04' to 'TC-012-002';
    dependency CL_040_06_verified_by_TC_012_006 from 'CL-040-06' to 'TC-012-006';
    dependency CL_040_07_verified_by_TC_012_007 from 'CL-040-07' to 'TC-012-007';
}
