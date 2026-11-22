package WstxUdp {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-012';
    private import WstxDecodes::ResultRecord;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelBindings::ImplementedIn;

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

    requirement 'CL-040-01' {
        subject udp : Udp;
        doc /* The station MUST send every enabled target the messages of the WSJT-X UDP
             protocol that the target selects, each on its occasion (OutboundRules,
             UdpWire). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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
             qsoLogged and then loggedAdif: for each LoggedContact of the log
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

    requirement 'CL-040-06' {
        subject udp : Udp;
        doc /* The station MUST take an IPv6 multicast group as a target and send to it
             with the hop limit and through the interface the target names
             (Ipv6Multicast). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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

    requirement 'CL-040-03' {
        subject udp : Udp;
        doc /* The station MUST take from its targets only the header schema that a
             target's Heartbeat names, and drop every other datagram without an effect
             (InboundRules). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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

    requirement 'CL-040-07' {
        subject udp : Udp;
        doc /* The station MUST send Status so that a target learns of every decode
             window of receive and, within one pulse, the state of the station
             (StatusCadence). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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
             Configuration name: the station's name (ProfileConfig::displayName).
             Tx message: the next message of the contact, else empty.
             Sub-mode is empty, Fast mode is false, and Frequency tolerance has the value
             the source reads as not applicable. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow.cpp, "
                + "statusUpdate";
        }
    }

    requirement 'CL-040-04' {
        subject udp : Udp;
        doc /* The station MUST send each message decoded by the live receive job once, in
             the text form WSJT-X gives it (DecodeFields). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-04'; }

    attribute def DecodeFields {
        doc /* How a Decode is made from a ResultRecord.
             A record gives a Decode when its status is decoded and it carries the start
             of its period (ResultRecord::periodStartUtc). Every other record gives
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
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-03'; }

    attribute def DeltaTime {
        doc /* The DT of the record (ResultRecord::dtSeconds), rounded to one decimal, a
             tie away from zero, and sent in single precision. A magnitude below 0.05
             gives 0. A record without a DT gives 0. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow.cpp, "
                + "postDecode";
        }
    }

    requirement 'CL-112-04' {
        subject udp : Udp;
        doc /* The station MUST send Clear when the operating selection changes to another
             band, and only then (ClearRule). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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

    requirement 'CL-112-05' {
        subject udp : Udp;
        doc /* The station MUST send a logged contact from its stored record, with the
             exchanges WSJT-X sends for the record's activity (LoggedFields). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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
             naVhf, wwDigi and arrlDigi: the first four characters of MY_GRIDSQUARE and
             of GRIDSQUARE.
             fieldDay and rtty: STX_STRING and SRX_STRING; without them RST_SENT with
             STX, and RST_RCVD with SRX or else STATE, joined by a blank.
             euVhf: RST_SENT, STX, a blank and the first six characters of
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

    requirement 'CL-112-06' {
        subject udp : Udp;
        doc /* The station MUST tell a target with Close that it stops sending to it
             (CloseRule). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/udp/udp.rs; server/src/udp/network_message.rs";
        }
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

    verification 'TC-012-001' {
        doc /* The datagrams, byte for byte. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-01'; verify 'CL-040-03'; verify 'CL-040-04'; }
        @TestedBy { test = "server/tests/udp_vectors.rs; server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-012-002' {
        doc /* The messages to two targets. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-01'; verify 'CL-040-04'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-012-003' {
        doc /* Nothing a target sends acts on the station. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-03'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-012-006' {
        doc /* IPv6 multicast targets. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-06'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-012-007' {
        doc /* Status with the decode windows and the pulse. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-07'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs; server/src/receive/recording_tests.rs"; }
    }

    verification 'TC-112-002' {
        doc /* The dial frequency and the report of Status. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-02'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-112-003' {
        doc /* The delta time of a Decode. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-03'; verify 'CL-040-04'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-012-009' {
        doc /* A played recording sends no Decode. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-04'; }
        @TestedBy {
            test = "server/src/udp/udp_tests.rs::played_recording_sends_no_decode_and_no_clear";
        }
    }

    verification 'TC-112-004' {
        doc /* Clear on a change of band only. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-04'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-112-005' {
        doc /* The exchanges of QSO Logged. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-05'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }

    verification 'TC-112-006' {
        doc /* Close when the station ends. */
        subject udp : Udp;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-06'; }
        @TestedBy { test = "server/src/udp/udp_tests.rs"; }
    }
}
