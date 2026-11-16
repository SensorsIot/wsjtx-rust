package WstxUdpPart {
    private import ScalarValues::*;
    private import WstxUdpControl::UdpControlPort;
    private import WstxUdpControl::UdpConfiguration;
    private import WstxDecodes::DecodesPort;
    private import WstxOperatingChain::LoggedContactPort;
    private import WstxUdp::UdpPort;
    private import ModelBindings::ImplementedIn;

    part def UdpService {
        doc /* Tells other programs what the station does, in the messages of the WSJT-X
             UDP protocol: its state, its decodes and its logged contacts, to every target
             the operator configures. It takes no command from them. */
        @ImplementedIn {
            module = "server/src/operating/qso/udp.rs; server/src/network_message.rs";
        }
        port control : ~UdpControlPort {
            doc /* The station service: the configuration and the station's state in,
                 the snapshot of the targets out. */
        }
        attribute configuration : UdpConfiguration {
            doc /* Its configuration, as the station service last gave it. */ }
        port decodes : ~DecodesPort {
            doc /* A record with the sequence 0 begins a new job, and PeriodView::job names
                 the job. A replay of a recording gives no record. */
        }
        port logged : ~LoggedContactPort;
        port peers : UdpPort;
    }
}
