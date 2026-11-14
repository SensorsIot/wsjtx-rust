package WstxUdpPart {
    private import ScalarValues::*;
    private import WstxStationCommands::StationStatusPort;
    private import WstxDecodes::DecodesPort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxUdp::UdpPort;
    part def UdpService {
        doc /* The WSJT-X UDP sender, send-only. */
        port status : ~StationStatusPort;
        port decodes : ~DecodesPort;
        port logged : ~CompletedContactPort;
        port peers : UdpPort;
    }
}
