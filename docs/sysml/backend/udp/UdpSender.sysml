package WstxUdpSender {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-012';
    private import WstxUdpPart::UdpService;
    private import WstxUdpControl::*;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* The UDP sender's own functions: the list of its targets and the instance name
         of the station. The messages and their fields are the exchange's
         (WstxUdp). */

    requirement 'CL-040-02' {
        subject udp : UdpService;
        doc /* The station MUST send to every target of the list the operator configures,
             and follow a changed list at once (TargetList). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-040-02'; }

    attribute def TargetList {
        doc /* How the UDP sender follows UdpConfiguration.
             It takes the list at station start and whenever the shack's settings
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
        doc /* The list of targets. */
        subject udp : UdpService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-040-02'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }

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
        doc /* The instance name. */
        subject udp : UdpService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-112-01'; }
        @TestedBy { test = "server/src/log/udp_tests.rs"; }
    }
}
