package WstxUdpSender {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-012';
    private import WstxUdpPart::UdpService;
    private import WstxUdpControl::*;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* The UDP sender's own functions: the list of its targets and the instance name
         of the station. The messages and their fields are the exchange's
         (WstxUdp). */

    // ---- The targets ----------------------------------------------------------------------

    requirement 'CL-040-02' {
        subject udp : UdpService;
        doc /* The station MUST send to every target of the list the operator configures,
             and follow a changed list at once (TargetList). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-02'; }

    attribute def TargetList {
        doc /* How the UDP sender follows UdpConfiguration.
             It takes the list at station start and whenever the operator's settings
             change (UdpConfigured), and its sockets follow a changed list at once. A target
             whose address, enabled, TTL and interface are unchanged keeps its socket,
             its schema and its status. Every other target is closed
             (WstxUdp::CloseRule) and opened again.
             A multicast target is sent to with its TTL or hop limit, through its
             interface, and with multicast loopback on.
             With the environment variable WSTX_UDP set to off the station opens no
             socket; the list is shown as before. */
    }

    verification 'TC-012-004' {
        doc /* The list of targets.
             Setup: the station on throw-away profiles, with WSTX_UDP off where no socket
             is wanted; targets on the loopback address.
             (a) A configuration that was never set: the one target 127.0.0.1:2237 with
             all seven messages, TTL 1 and no interface.
             (b) A list of 127.0.0.1:52001 with decode, and 239.255.0.1:2237, not
             enabled, TTL 2, interface 127.0.0.1, with logged_adif, heartbeat and
             status: the messages in the order heartbeat, status, logged_adif.
             (c) No list of UdpConfiguration, each alone: 17 targets; one address twice;
             port 0; 0.0.0.0; 255.255.255.255; a host name; [ff02::1] without an
             interface; TTL 0 and 256; the interface ::1 on an IPv4 target; a message
             twice; an unknown message; enabled "yes"; a target with one more key.
             (d) 16 targets: a list.
             (e) A record published while the station has no target, then a list with
             one target: the target gets Heartbeat and Status only.
             (f) Planned, no test yet: one target created, changed and deleted by its
             address (WstxProfileAccess::CreateEntry, UpdateEntry, DeleteEntry): the
             sender follows each at once; the other targets keep their sockets. */
        subject udp : UdpService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-02'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

    // ---- The id of every datagram ------------------------------------------------------

    requirement 'CL-112-01' {
        subject udp : UdpService;
        doc /* The station MUST give every datagram one instance name that no other
             running station of the same Windows account carries (InstanceName). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-112-01'; }

    attribute def InstanceName {
        doc /* The name is the base, " - " and the station's name
             (UdpStationState::stationName), as WSJT-X's
             "WSJT-X - <rig name>". It is fixed at station start for the life of the
             station process. It is unique because the station's name is unique among
             the stations of the PC. */
        attribute base : String = "WSTX-Rust";
    }

    verification 'TC-112-001' {
        doc /* The instance name.
             Setup: stations on throw-away profiles; targets on the loopback address.
             (e) Heartbeat, Status, Decode, Clear, QSO Logged, Close and Logged ADIF all
             carry the name, and the view shows it.
             (f) Radio control switched off in the profile while the station runs: the
             name stays.
             (i) Planned, no test yet: a station named IC-7300: WSTX-Rust - IC-7300; one
             named FLEX-6600 A: WSTX-Rust - FLEX-6600 A, from station start on; the
             configuration name of Status is the station's name. */
        subject udp : UdpService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-01'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }
}
