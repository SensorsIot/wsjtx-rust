package WstxUdp {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-012';
    private import WstxDecodes::ResultRecord;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import WstxUdpControl::*;

    doc /* The messages of the WSJT-X UDP protocol that the station sends to the programs the
         operator names as targets. The layouts, the type numbers and the encodings are
         the source's; this file states what the station sends, when, and what it puts
         into each field. */

    item def Datagram {
        doc /* One message of the source. Its id is the station's instance name
             (WstxUdpSender::InstanceName); its header
             schema is the schema of the target it goes to (TargetStatus::schema). */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Network/NetworkMessage.hpp and "
                + "Network/MessageClient.cpp";
        }
    }
    item def PeerHeartbeat {
        doc /* A Heartbeat that a target sends back to the station (InboundRules). */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Network/NetworkMessage.hpp";
        }
    }
    port def UdpPort {
        doc /* Written from the station's side; a target uses the conjugate. */
        out item datagram : Datagram;
        in item heartbeat : PeerHeartbeat;
    }
    interface def Udp {
        doc /* The UDP sender and the targets the operator configures. */
        end udp : UdpPort;
        end peers : ~UdpPort;
    }

    // ---- What is sent, and when ---------------------------------------------------------

    requirement 'CL-040-01' {
        subject udp : Udp;
        doc /* The station MUST send every enabled target the messages of the WSJT-X UDP
             protocol that the target selects, each on its occasion (OutboundRules,
             UdpWire). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-01'; }

    attribute def OutboundRules {
        doc /* Which message is sent on which occasion. A message goes to a target only
             while the target is active (TargetStatus::active) and selects it
             (UdpTarget::messages).
             heartbeat: at each pulse of a target, which is when the target becomes active
             and then every pulse interval of the source. It names UdpWire::schemaMax,
             the station's version and an empty revision.
             status: StatusCadence, filled by StatusFields.
             decode: once for each decoded record of the live receive job (DecodeFields).
             clear: ClearRule.
             qso_logged and then logged_adif: for each LoggedContact of the log
             (LoggedFields).
             close: CloseRule.
             No other message of the source is sent. */
        @DiffersFromSource {
            what = "A played recording sends no Decode; WSJT-X sends the decodes of a "
                + "played file with Off air true.";
        }
    }
    attribute def UdpWire {
        doc /* The product's choices in the source's header. */
        attribute schemaOut : Integer = 2 {
            doc /* The header schema of the datagrams to a target until that target
                 names a higher one (InboundRules). */ }
        attribute schemaMax : Integer = 3 {
            doc /* The highest header schema the station takes and names. */ }
        attribute inboundMaxBytes : Integer = 4096 {
            doc /* A longer datagram from a target is not read. */ }
    }

    // ---- IPv6 multicast targets ----------------------------------------------------------

    requirement 'CL-040-06' {
        subject udp : Udp;
        doc /* The station MUST take an IPv6 multicast group as a target and send to it
             with the hop limit and through the interface the target names
             (Ipv6Multicast). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-06'; }

    attribute def Ipv6Multicast {
        doc /* A target whose address is an IPv6 multicast group.
             A group of the reserved scopes 0 and 15 is not admitted.
             UdpTarget::multicastTtl is the hop limit.
             UdpTarget::multicastInterface is the index of the interface, written as a
             decimal number from 1 to 4294967295 without a sign and without a leading
             zero. A group of the scopes 1 and 2, which exist on one interface only,
             names one; a group of a wider scope may leave it out.
             An index that no interface of the PC has is admitted; the target then
             shows TargetError::socketUnavailable. */
        @FollowsSource { reference = "RFC 4291, section 2.7: multicast scopes"; }
    }

    // ---- What the station takes from a target ----------------------------------------------

    requirement 'CL-040-03' {
        subject udp : Udp;
        doc /* The station MUST take from its targets only the header schema that a
             target's Heartbeat names, and drop every other datagram without an effect
             (InboundRules). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-03'; }

    attribute def InboundRules {
        doc /* What the station does with a datagram that arrives at the socket of an
             active target.
             A Heartbeat raises the schema of that target to its own header schema when
             it comes from the target's address, carries the source's magic number, a
             schema from UdpWire::schemaOut to UdpWire::schemaMax and the station's
             instance name as id, and is at most UdpWire::inboundMaxBytes long. The
             schema of a target is not lowered. A socket that is opened starts at
             UdpWire::schemaOut.
             The fields after the id are not read.
             A Heartbeat at the socket of a multicast target does not come from the
             group's address; such a target stays at UdpWire::schemaOut.
             Every other datagram is dropped: it changes nothing and is not answered. A
             datagram longer than UdpWire::inboundMaxBytes is dropped and the ones
             behind it are read. */
        @DiffersFromSource {
            what = "The station acts on no command; WSJT-X acts on Reply, Clear, Close, "
                + "Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch "
                + "Configuration and Configure.";
        }
        @DiffersFromSource {
            what = "Only a Heartbeat from the target's own address with the station's id "
                + "raises the schema; WSJT-X takes a higher schema from any datagram it "
                + "can read.";
        }
    }

    // ---- Status -----------------------------------------------------------------------------

    requirement 'CL-040-07' {
        subject udp : Udp;
        doc /* The station MUST send Status so that a target learns of every decode
             window of receive and, within one pulse, the state of the station
             (StatusCadence). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-07'; }

    attribute def StatusCadence {
        doc /* When Status is sent to a target.
             When the target becomes active.
             Whenever a field of the message has changed.
             Once for each decode window that receive has begun since the last Status
             to the target, also for a window that began and ended in between.
             At each pulse of the target, unchanged, also to a target that does not
             select the heartbeat.
             The field Decoding is true from the start of a window's decode until that
             decode returns, however it ends. Receive reports both in its status:
             whether a window is being decoded, and how many windows have begun. */
        @DiffersFromSource {
            what = "Status is sent again at each pulse although nothing changed; WSJT-X "
                + "sends it on a change only.";
        }
    }

    requirement 'CL-112-02' {
        subject udp : Udp;
        doc /* The station MUST fill the Status message from its own state with the
             meaning WSJT-X gives each field (StatusFields). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-02'; }

    attribute def StatusFields {
        doc /* What the station puts into each field of Status.
             Dial frequency: the dial that radio control confirms, else the nominal
             frequency of the operating selection, else 0.
             Mode and Tx mode: FT8 or FT4, the station's operating mode.
             DX call and DX grid: those of the contact, else empty.
             Report: the report of the contact, else the report set for the station,
             written as a plain number: "-9", "3", "0".
             Tx enabled: transmission is armed. Transmitting: the station transmits.
             Decoding: StatusCadence.
             Rx DF and Tx DF: the receive and the transmit offset of the contact
             settings.
             DE call and DE grid: the profile's call and locator.
             Tx watchdog: the watchdog has expired.
             Special operation: the source's number for the activity of the contact
             settings.
             T/R period: the value the source reads as not applicable.
             Configuration name: the station's name (ProfileConfig::display_name).
             Tx message: the next message of the contact, else empty.
             Sub-mode is empty, Fast mode is false, and Frequency tolerance has the value
             the source reads as not applicable. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow.cpp, "
                + "statusUpdate";
        }
    }

    // ---- Decode -----------------------------------------------------------------------------

    requirement 'CL-040-04' {
        subject udp : Udp;
        doc /* The station MUST send each message decoded by the live receive job once, in
             the text form WSJT-X gives it (DecodeFields). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-04'; }

    attribute def DecodeFields {
        doc /* How a Decode is made from a ResultRecord.
             A record gives a Decode when its status is decoded and it carries the start
             of its period (ResultRecord::period_start_utc). Every other record gives
             none.
             The records of the live receive job are taken in the order of their
             sequence, each once, when they are published. A record that gives no Decode
             and a record published while no target is active are not sent afterwards.
             A played recording is no live job.
             New is true. Time is the start of the record's period, as the time of day
             in UTC. SNR is the record's SNR rounded to a whole number, a half away
             from zero, and 0 without one. Delta time: DeltaTime. Delta frequency is
             the record's frequency rounded to a whole number of Hz. Mode is "~" for
             FT8 and "+" for FT4. Low confidence and Off air are false.
             Message is the record's text. A standard message that acknowledges with R
             and carries a signal report is written with the R joined to the report:
             "R-09", "R+03". A hashed call stands as the record gives it. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow.cpp, "
                + "postDecode";
        }
    }

    requirement 'CL-112-03' {
        subject udp : Udp;
        doc /* The station MUST send the delta time of a decode rounded to one decimal, the
             value WSJT-X sends (DeltaTime). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-03'; }

    attribute def DeltaTime {
        doc /* The DT of the record (ResultRecord::dt_seconds), rounded to one decimal, a
             tie away from zero, and sent in single precision. A magnitude below 0.05
             gives 0. A record without a DT gives 0. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow.cpp, "
                + "postDecode";
        }
    }

    // ---- Clear ----------------------------------------------------------------------------

    requirement 'CL-112-04' {
        subject udp : Udp;
        doc /* The station MUST send Clear when the operating selection changes to another
             band, and only then (ClearRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-04'; }

    attribute def ClearRule {
        doc /* Clear goes to every target that selects it when the band of the operating
             selection becomes another band than the last one it named, however the
             change comes about and whether or not a Decode was sent since the last
             Clear.
             While the operating selection names no band, the last band it named
             counts.
             Every other change sends none: of the mode, of the receive job, of the
             source's epoch, of the frequency within the band. */
        @DiffersFromSource {
            what = "WSJT-X sends Clear whenever its Band Activity window is erased, by "
                + "the operator as well; the station sends it on a band change only.";
        }
    }

    // ---- Logged contacts ------------------------------------------------------------------

    requirement 'CL-112-05' {
        subject udp : Udp;
        doc /* The station MUST send a logged contact from its stored record, with the
             exchanges WSJT-X sends for the record's activity (LoggedFields). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-05'; }

    attribute def LoggedFields {
        doc /* What the station puts into QSO Logged and Logged ADIF. Both are made from
             the record of a LoggedContact, so one record always gives the same two
             messages.
             Date and time off and on: the record's end and start, in UTC.
             DX call, DX grid, Report sent, Report received, Tx power, Comments, My call
             and My grid: the record's CALL, GRIDSQUARE, RST_SENT, RST_RCVD, TX_PWR,
             COMMENT, STATION_CALLSIGN and MY_GRIDSQUARE; an absent field is empty.
             Tx frequency: the record's FREQ in Hz, and 0 without one.
             Mode: the record's SUBMODE where its MODE is MFSK, else its MODE.
             Exchange sent and Exchange received, by the record's activity.
             na_vhf, ww_digi and arrl_digi: the first four characters of MY_GRIDSQUARE and
             of GRIDSQUARE.
             field_day and rtty: STX_STRING and SRX_STRING; without them RST_SENT with
             STX, and RST_RCVD with SRX or else STATE, joined by a blank.
             eu_vhf: RST_SENT, STX, a blank and the first six characters of
             MY_GRIDSQUARE; RST_RCVD, SRX, a blank and the first six of GRIDSQUARE.
             hound, none, and a record without an activity: both empty.
             An exchange whose parts are not all in the record is empty.
             Name, Operator call and every field the source defines after Exchange
             received are empty.
             Logged ADIF is the header "<adif_ver:5>3.1.8", "<programid:9>WSTX-Rust",
             "<EOH>", each on its own line after an empty one, then the record's fields
             as the log writes them, then " <EOR>". */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow_qso.cpp, "
                + "captureLogQso, and widgets/logqso.cpp";
        }
        @DiffersFromSource {
            what = "The header of Logged ADIF names this product as programid, not "
                + "WSJT-X, and the record carries the product's own fields "
                + "APP_WSTXRUST_CONTACT_ID, APP_WSTXRUST_SOURCE and "
                + "APP_WSTXRUST_ACTIVITY.";
        }
    }

    // ---- Close ----------------------------------------------------------------------------

    requirement 'CL-112-06' {
        subject udp : Udp;
        doc /* The station MUST tell a target with Close that it stops sending to it
             (CloseRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-06'; }

    attribute def CloseRule {
        doc /* Close goes once to an active target that selects it:
             when a changed list leaves the target out, disables it or changes its
             address, TTL or interface, before the socket is closed;
             when the station process ends on an interrupt or a close of its console,
             on a logoff or on a shutdown of Windows. Transmission is released first,
             and Close is given to the network without waiting. */
    }

    // ---- Test cases -------------------------------------------------------------------------

    verification 'TC-012-001' {
        doc /* The datagrams, byte for byte.
             Setup: vectors written by hand, field by field, from the source's header
             file, apart from the encoder; no network.
             (a) Heartbeat, Status, a Decode at schema 2 and one at schema 3, Clear,
             QSO Logged, Close and Logged ADIF made from the vectors' field values:
             equal to the vectors.
             (b) A Heartbeat at schema 3 with the id WSTX-Rust, one with bytes after
             its fields, and one at schema 2 with the id JTAlert and no field: read
             with their schema and id.
             (c) Clear, Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight
             Callsign, Switch Configuration, Configure and an unknown type; a
             Heartbeat with another magic number, at schema 1 and 4, with an id that is
             cut off, not UTF-8 or null, and one of 4097 bytes: not read.
             (d) Every shortening of every vector, 20000 made-up datagrams and an id
             that claims 4294967294 bytes: not read, without a fault.
             (e) The record text "K1ABC W9XYZ R -09": "K1ABC W9XYZ R-09"; with R +03:
             "R+03". "K1ABC W9XYZ -09", "K1ABC W9XYZ R FN42", "CQ K1ABC FN42" and
             "K1ABC W9XYZ RR73" stay as they are. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-01'; verify 'CL-040-03'; verify 'CL-040-04'; }
        @TestedBy { test = "server/tests/udp_vectors.rs; server/src/log/udp_tests.rs"; }
    }

    verification 'TC-012-002' {
        doc /* The messages to two targets.
             Setup: the station on a throw-away profile (HB9BLA, JN47AA) with scripted
             transmit hardware and a live FT8 job; targets A (every message) and B
             (decode only) on the loopback address; a reader of the datagrams written
             apart from the encoder.
             (a) First look: A gets Heartbeat (schema 2, id WSTX-Rust, highest schema 3,
             the station's version, an empty revision) and then Status (FT8, HB9BLA,
             JN47AA, Tx not enabled, tolerance 4294967295, the profile's
             display name); B gets nothing. Second look: nothing.
             (b) The records "CQ K1ABC FN42" at 1234.6 Hz and -12.4 dB and "HB9BLA W9XYZ
             R-09" at 900.0 Hz and -3.0 dB of the period 12:34:30: A and B each get two
             Decodes; the first new, time 45270000 ms, SNR -12, DT 0.1, 1235 Hz, "~",
             "CQ K1ABC FN42"; the second SNR -3, 900 Hz, "HB9BLA W9XYZ R-09". Next
             look: no Decode.
             (c) The station's report set to -7: one Status to A with the report "-7".
             (d) A second live job on the same band: no Clear.
             (e) A contact with K1ABC saved (FN42, FT8, 14.075500 MHz, reports -12 and
             -09, ended at 12:36:15): A gets QSO Logged and then Logged ADIF. QSO
             Logged carries the Julian day 2461346, 45375000 ms, UTC, K1ABC, FN42,
             14075500 Hz, FT8, "-12" and "-09". Logged ADIF begins with the header and
             "<call:5>K1ABC" and ends with the contact's identity field and " <EOR>".
             B gets nothing. The same save again, and a save of the stored contact:
             nothing is sent.
             (f) The view shows a last send for both targets and no error. A disabled
             by a new list: A gets Close and is not active; B stays active. Next look:
             nothing to A.
             (g) A played recording with a decoded record: no Decode and no Clear.
             (h) A contact that completes and logs itself: QSO Logged and Logged ADIF
             once; a repeated 73: nothing more.
             Two records added from an ADIF file: nothing is sent.
             (i) Planned, no test yet: the T/R period of Status as not applicable; the
             code and its test send 15 for FT8 and 7 for FT4.
             (j) Planned, no test yet: after (h), Log QSO (the log's ResendLast): QSO
             Logged and Logged ADIF of that contact once more. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-01'; verify 'CL-040-04'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-012-003' {
        doc /* Nothing a target sends acts on the station.
             Setup: as the messages to two targets, with one target A and another socket
             X; one published row; transmission armed from the browser.
             (a) From A and from X to the station's socket of A: Halt Tx, Clear, a Reply
             to the row, Close, Replay, Free Text, Location JN36AB, Highlight Callsign,
             Switch Configuration and Configure. Afterwards transmission is still armed
             with the same last cause of disarming, the contact is unchanged and names
             no station, the locator is the profile's, and A has got nothing but
             Status.
             (b) The view carries the instance name and the configuration, and for a
             target its address, active, schema, last send and error.
             (c) Each alone: a Heartbeat at schema 3 from X; from A a Heartbeat at
             schema 3 with the id OTHER, a Heartbeat at schema 4, a Replay and a Halt Tx
             at schema 3: the schema of A stays 2.
             (d) From A a datagram of 5000 bytes and then a Heartbeat at schema 3: the
             schema is 3. A Heartbeat at schema 2: it stays 3. The next Decode to A
             carries schema 3. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-03'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-012-006' {
        doc /* IPv6 multicast targets.
             Setup: the station on a throw-away profile; a socket joined to the group
             ff12::5754:5358 on the loopback interface of the PC, index 1; nothing
             leaves the PC.
             (a) No target of UdpTarget, each alone: the
             addresses [ff00::1], [ff0f::1] and [ff1f::1]; the group and [ff01::1]
             without an interface; hop limit 0 and 256; the IPv4 group 239.255.0.1
             with the interface "1"; the interfaces "0", "01", "-1", "+1", " 1",
             "4294967296", "Ethernet", "127.0.0.1", "::1", "" and the number 1.
             (b) Targets, in one list: the
             group with hop limit 2 and interface "1"; [ff05::5754:5358]:2237 with hop
             limit 255 and interface "1"; [ff15::5754:5358]:2238 with interface
             "4000000000"; [ff08::5754:5358]:2239, not enabled, without an interface.
             (c) [::1]:2240, not enabled, interface "127.0.0.1": a target. With the
             interface "1" on it: none.
             (d) The socket of the group has hop limit 2, interface 1 and loopback on;
             that of the second group hop limit 255. The third target is not active,
             with socketUnavailable.
             (e) The joined socket gets Heartbeat and then Status, at schema 2 with the
             id WSTX-Rust. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-06'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-012-007' {
        doc /* Status with the decode windows and the pulse.
             Setup: as the messages to two targets, with A (every message), B (status
             only) and C (heartbeat and decode); the pulse is reached by setting its
             time back, not by waiting. For (e) the live receive worker on windows of
             silence.
             (a) First look: A gets Heartbeat and then Status with Decoding false; B
             gets Status; C gets Heartbeat. Second look: nothing.
             (b) Twice: a window's decode begins: one Status with Decoding true to A and
             to B, and none at the next look; it ends: one Status with Decoding false.
             C gets none.
             (c) A window that begins and ends between two looks: one Status with
             Decoding false to A and to B; then nothing.
             (d) 14 s after the pulse: nothing. 15 s after it: A gets Heartbeat and a
             Status equal byte for byte to the last one, B the Status, C the Heartbeat.
             Then nothing.
             (e) Before a window: no decode runs and 0 windows have begun. While the
             first window decodes: a decode runs, 1 window; while the second decodes,
             also when it takes the place of one that ran over: 2 windows. Afterwards:
             no decode runs, 2 windows. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-07'; }
        @TestedBy { test = "server/src/log/udp_tests.rs; server/src/recording_tests.rs"; }
    }

    verification 'TC-112-002' {
        doc /* The dial frequency and the report of Status.
             Setup: the station on a throw-away profile; a scripted radio whose
             confirmed dial is 7074000 Hz.
             (a) No confirmed dial and no operating selection: 0. The selection 40m,
             7074000 Hz, without a radio: 7074000. The selection 20m, 14074000 Hz, with
             the radio's dial confirmed: 7074000.
             (b) The station's report set to -9, 3, 0, -24, 49 and -50: "-9", "3", "0",
             "-24", "49" and "-50". */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-02'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-112-003' {
        doc /* The delta time of a Decode.
             Setup: the station on a throw-away profile with a live FT8 job; a target
             that selects decode.
             (a) DT 0.04: 0.0; -0.06: -0.1; 0.25: 0.3; -0.25: -0.3; 1.349: 1.3; no
             DT: 0.
             (b) A record with DT 0.25 whose period start is not known: no Decode. The
             same message in the next period: one Decode with the single-precision
             value of 0.3 and the time 45285000 ms. Next look: nothing. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-03'; verify 'CL-040-04'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-112-004' {
        doc /* Clear on a change of band only.
             Setup: the station on a throw-away profile with a live FT8 job on 20m;
             targets A (every message) and B (without clear); a Decode is sent before
             each step but (c).
             (a) The operating selection changed to 40m: one Clear to A, none to B.
             (b) The selection without a band, then the dial read from the radio taken
             as the selection on 20m: one Clear.
             (c) Changed to 40m again with no Decode in between: one Clear.
             (d) No Clear for each of: a live job in FT4 on the same band, a new live
             job, a new epoch of the source after a loss, receive stopped, and the
             frequency changed within the band from 7074000 to 7047500 Hz. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-04'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-112-005' {
        doc /* The exchanges of QSO Logged.
             Setup: the station with its log on a throw-away profile (HB9BLA, JN47AA);
             a target that selects qso_logged and logged_adif. Each contact is logged
             at its completion and then saved again from its stored record under
             another identity; both give the same exchanges.
             (a) field_day with 1A EMA and 2B CT: "1A EMA" and "2B CT".
             (b) rtty with 559 MA and 579 MA: "559 MA" and "579 MA"; with 559 0003 and
             559 0013: "559 0003" and "559 0013".
             (c) eu_vhf from JN37VL with the partner at IO91NP: "550001 JN37VL" and
             "590003 IO91NP".
             (d) na_vhf with the partner at FN42, and ww_digi with the partner at
             FN42ab: "JN47" and "FN42". arrl_digi without a partner's grid: "JN47"
             and empty.
             (e) hound and none with the partner at FN42: both empty. A record without
             an activity that carries 1A EMA and 2B CT: both empty.
             (f) Logged ADIF ends with the contact's identity field, then the activity
             field, then " <EOR>"; for none it has no activity field.
             (g) A save of a stored contact that differs in the activity only: nothing
             is sent. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-05'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    verification 'TC-112-006' {
        doc /* Close when the station ends.
             Setup: the station with scripted transmit hardware; targets A (every
             message), B (without close), C (not enabled) and D (an IPv6 group on an
             interface index the PC does not have, socketUnavailable); a Flex station
             whose session is never ready, with one target.
             (a) The station is told to end: the release of transmission returns within
             500 ms and nothing is sent before it has returned. Then A gets one Close
             with the id WSTX-Rust; B, C and D get nothing.
             (b) The Flex station is told to end: nothing is sent. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-06'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }
}
