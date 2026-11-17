package WstxContext {
    private import ScalarValues::*;
    private import WstxShack::Shack;
    private import WstxRadioProperties::Radio;
    private import WstxOperatorInteraction::OperatorInteractionPort;
    private import WstxOperatorInteraction::OperatorInteraction;
    private import WstxMcp::McpPort;
    private import WstxMcp::Mcp;
    private import WstxCat::CatPort;
    private import WstxCat::Cat;
    private import WstxSoundDevice::SoundDevicePort;
    private import WstxSoundDevice::SoundDevice;
    private import WstxFlexApi::FlexApiPort;
    private import WstxFlexApi::FlexApi;
    private import WstxUdp::UdpPort;
    private import WstxUdp::Udp;
    private import WstxPskReporter::PskReporterPort;
    private import WstxPskReporter::PskReporter;
    private import WstxPskReporter::ReportCollectorPort;
    private import WstxPskReporter::ReportCollector;
    private import WstxClubLog::ClubLogPort;
    private import WstxClubLog::ClubLog;
    private import WstxCountryFiles::CountryFilesPort;
    private import WstxCountryFiles::CountryFiles;
    private import WstxTimeSource::TimeSourcePort;
    private import WstxTimeSource::TimeSource;

    part def ShackContext {
        doc /* The shack and what it exchanges messages with. An outside thing is a black
             box. The function that owns it is the one its port is joined to. */
        part shack : Shack;

        part operator {
            doc /* The licensed person who operates the shack's stations through their
                 browsers. */
            port link : ~OperatorInteractionPort;
        }
        part agent {
            doc /* A program that operates a station through its MCP, with the rights of the
                 operator. */
            port link : ~McpPort;
        }
        part catRadio : Radio {
            doc /* A transceiver reached through its CAT serial link. */
            port link : ~CatPort;
        }
        part flexRadio : Radio {
            doc /* A FlexRadio reached through its native API. */
            port link : ~FlexApiPort;
        }
        part soundDevice {
            doc /* The capture and playback endpoints of a sound card. */
            port link : ~SoundDevicePort;
        }
        part udpPeer {
            doc /* A configured target of the WSJT-X UDP messages. */
            port link : ~UdpPort;
        }
        part pskReporter {
            doc /* PSK Reporter: the broker of the feed and the collector of reception
                 reports. */
            port link : ~PskReporterPort;
            port collector : ~ReportCollectorPort;
        }
        part clubLog {
            doc /* The Club Log service that gives the most-wanted list. */
            port link : ~ClubLogPort;
        }
        part countryFiles {
            doc /* country-files.com, which gives the newest country file of AD1C. */
            port link : ~CountryFilesPort;
        }
        part timeServer {
            doc /* An SNTP time server. */
            port link : ~TimeSourcePort;
        }

        interface operatorLink : OperatorInteraction
            connect shack.stations.frontend.browsers.operator to operator.link;
        interface agentLink : Mcp connect shack.stations.backend.mcp.agent to agent.link;
        interface catLink : Cat connect shack.stations.backend.catAdapter.radio to catRadio.link;
        interface soundDeviceLink : SoundDevice
            connect shack.stations.backend.audioAdapter.device to soundDevice.link;
        interface flexApiLink : FlexApi
            connect shack.stations.backend.flexAdapter.radio to flexRadio.link;
        interface udpLink : Udp connect shack.stations.backend.udp.peers to udpPeer.link;
        interface pskReporterLink : PskReporter
            connect shack.stations.backend.spots.pskReporter to pskReporter.link;
        interface reportCollectorLink : ReportCollector
            connect shack.stations.backend.spots.collector to pskReporter.collector;
        interface clubLogLink : ClubLog
            connect shack.stations.backend.profile.clubLog to clubLog.link;
        interface countryFilesLink : CountryFiles
            connect shack.stations.backend.profile.countryFiles to countryFiles.link;
        interface timeSourceLink : TimeSource
            connect shack.stations.backend.clock.timeSource to timeServer.link;

    }

    part context : ShackContext;

    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose context::shack::*;
    }
}
