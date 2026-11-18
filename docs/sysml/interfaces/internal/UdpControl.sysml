package WstxUdpControl {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    private import WstxStationCommands::ProcessEnds;

    doc /* The configuration of the UDP sender, the state of the station it reports in
         Status, and what it reports back: the control interface between the supervisor
         and udp. */

    enum def OutboundMessage {
        doc /* The messages a target can select, by the names of the configuration. */
        enum heartbeat;
        enum status;
        enum decode;
        enum clear;
        enum qsoLogged;
        enum close;
        enum loggedAdif;
    }
    attribute def UdpTarget {
        doc /* One program the station sends to. Its address is its identity: no two
             targets of a list have the same one. */
        attribute address : String {
            doc /* An IPv4 or IPv6 address written in numbers, with a port from 1 to
                 65535. The unspecified address and 255.255.255.255 are not admitted. */ }
        attribute enabled : Boolean { doc /* A target that is not enabled is not sent to. */ }
        attribute multicastTtl : Integer {
            doc /* The TTL of the datagrams to an IPv4 multicast address, and the hop
                 limit of those to an IPv6 multicast address. Every target names one. */ }
        attribute multicastInterface : String[0..1] {
            doc /* The interface the datagrams to a multicast address leave through. For
                 an IPv6 multicast address see Ipv6Multicast; for every other address it
                 is an IPv4 address. Absent: the system chooses. */ }
        attribute messages : OutboundMessage[0..7] {
            doc /* The messages the target selects, each at most once. An empty selection
                 sends nothing. */ }
        assert constraint ttlRange { multicastTtl >= 1 and multicastTtl <= 255 }
    }
    attribute def UdpConfiguration {
        doc /* The configuration of the UDP sender: the list of the targets with the
             messages each gets.
             Until the operator sets a list it is one target: 127.0.0.1:2237, enabled,
             every message selected, TTL 1, no interface.
             The UDP sender follows it as TargetList (WstxUdpSender) says. */
        attribute targets : UdpTarget[0..*] ordered {
            doc /* The programs the station sends to: at most targetsMax, in the order
                 the operator gave them. An empty list sends nothing. */ }
        attribute targetsMax : Integer = 16;
    }
    item def UdpConfigured {
        doc /* The configuration of udp, one of the shack's settings. The supervisor
             gives it at station start and whenever they change. */
        attribute config : UdpConfiguration;
    }

    item def UdpStationState {
        doc /* What udp reports of the station in Status (WstxUdp::StatusFields). The
             supervisor gives it at station start and whenever a value changes. Each
             value is the fact of the part named, as the supervisor holds it. */
        attribute stationName : String {
            doc /* The station's name, WstxProfileAccess::ProfileConfig::displayName. */ }
        attribute callsign : String[0..1] { doc /* The profile's call; absent without one. */ }
        attribute locator : String[0..1] { doc /* The profile's locator; absent without one. */ }
        attribute mode : Mode[0..1] { doc /* The station's operating mode. */ }
        attribute dialHz : Integer[0..1] {
            doc /* The dial frequency radio control confirms; absent without one. */ }
        attribute selectionBand : String[0..1] {
            doc /* The band of the operating selection; absent while it names none. */ }
        attribute selectionHz : Integer[0..1] {
            doc /* The nominal frequency of the operating selection. */ }
        attribute dxCall : String[0..1] { doc /* The contact's partner call. */ }
        attribute dxGrid : String[0..1] { doc /* The contact's partner grid. */ }
        attribute contactReport : Integer[0..1] { doc /* The report of the contact. */ }
        attribute stationReport : Integer { doc /* The report set for the station. */ }
        attribute rxOffsetHz : Integer { doc /* The receive offset of the contact settings. */ }
        attribute txOffsetHz : Integer { doc /* The transmit offset of the contact settings. */ }
        attribute activity : String[0..1] {
            doc /* The activity of the contact settings, by its name; absent for none. */ }
        attribute txMessage : String[0..1] { doc /* The contact's next message. */ }
        attribute txEnabled : Boolean { doc /* The transmit state is on. */ }
        attribute transmitting : Boolean { doc /* The station transmits. */ }
        attribute txWatchdogExpired : Boolean {
            doc /* The contact's Tx watchdog has stopped it, until the next start. */ }
        attribute decoding : Boolean { doc /* Receive decodes a window now. */ }
        attribute decodeWindows : Integer {
            doc /* How many decode windows receive has begun since station start. */ }
    }

    enum def TargetError {
        doc /* socketUnavailable: the socket of an enabled target could not be opened with
             its settings.
             sendFailed: the last datagram could not be sent; the next one that is sent
             clears it. */
        enum socketUnavailable;
        enum sendFailed;
    }
    attribute def TargetStatus {
        doc /* The state of one target, in the order of the list. It lasts as long as the
             target's socket. */
        attribute address : String;
        attribute active : Boolean { doc /* The target has an open socket. */ }
        attribute schema : Integer { doc /* The header schema of the datagrams to it. */ }
        attribute lastSendMs : Integer[0..1] {
            doc /* The time of the last datagram sent, in milliseconds of UTC since 1970.
                 Absent until one is sent. */ }
        attribute error : TargetError[0..1] { doc /* Absent while none holds. */ }
    }
    item def UdpSnapshot {
        doc /* What the supervisor reads of the UDP sender. */
        attribute instanceName : String { doc /* WstxUdpSender::InstanceName. */ }
        attribute configuration : UdpConfiguration;
        attribute status : TargetStatus[0..*] ordered {
            doc /* One for each target of the configuration. */ }
    }

    port def UdpControlPort {
        doc /* Written from the supervisor's side; udp uses the conjugate.
             UdpConfigured, UdpStationState and ProcessEnds have no answer; udp gives
             UdpSnapshot at every change of it. ProcessEnds starts the Close of
             WstxUdp::CloseRule. */
        out item configuration : UdpConfigured;
        out item 'state' : UdpStationState;
        out item processEnds : ProcessEnds;
        in item report : UdpSnapshot;
    }
    interface def UdpControl {
        doc /* The supervisor gives udp its configuration and the station's state;
             udp reports its targets. */
        end station : UdpControlPort;
        end udp : ~UdpControlPort;
    }
}
