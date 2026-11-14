package WstxContext {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;
    private import WstxArchitecture::Station;
    private import WstxRadioProperties::Radio;
    private import WstxOperatorInteraction::OperatorInteractionPort;
    private import WstxOperatorInteraction::OperatorInteraction;
    private import WstxMcpInterface::McpPort;
    private import WstxMcpInterface::Mcp;
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
    private import WstxClubLog::ClubLogPort;
    private import WstxClubLog::ClubLog;
    private import WstxTimeSource::TimeSourcePort;
    private import WstxTimeSource::TimeSource;

    enum def OutsideThing {
        doc /* The outside things the server opens a socket, device or file to. None is a
             part or has a port. The function that owns each carries its information and
             state on the ports it offers to other functions; the wire protocol is that
             function's inside. */
        enum catRadio {
            doc /* The transceiver's CAT serial link, a COM port found by device enumeration. */
            @FollowsSource {
                reference = "Icom IC-7300 Full Manual A7292-4EX-12a, CI-V command table";
            }
        }
        enum flexRadio {
            doc /* A FlexRadio through its native API: a TCP command channel and UDP VITA-49
                 streams. */
            @FollowsSource {
                reference = "SmartSDR TCP/IP API and FlexLib, as "
                    + "WstxProductScope::NativeFlexWireSubset pins them";
            }
        }
        enum soundDevice {
            doc /* The sound-card capture and playback endpoints. */
            @FollowsSource { reference = "Windows Core Audio WASAPI, shared event-driven mode"; }
        }
        enum browser {
            doc /* The operator's browser, over HTTPS and WebSocket on the station listener.
                 WstxStationProtocol is the product's own protocol over them. */
            @FollowsSource {
                reference = "RFC 9110 HTTP, RFC 6455 WebSocket, TLS 1.2 and 1.3 "
                    + "(RFC 5246, RFC 8446)";
            }
        }
        enum mcpClient {
            doc /* MCP clients, POST /mcp on the same listener. A client reaches one station's
                 McpAdapter over that station's own HTTPS listener with its own auth-v1 grant
                 (WstxMcpInterface::McpEndpoint, McpCredential); it may run on any authorized
                 computer. */
            @FollowsSource {
                reference = "Model Context Protocol, Streamable HTTP, "
                    + "the eras WstxMcp::ProtocolEras names";
            }
        }
        enum udpPeer {
            doc /* The configured WSJT-X UDP targets, send-only. */
            @FollowsSource {
                reference = "WSJT-X Network/NetworkMessage.hpp, the version WstxUdp names";
            }
        }
        enum pskReporter {
            doc /* The PSK Reporter MQTT broker, subscribe-only over TLS. */
            @FollowsSource { reference = "MQTT 3.1.1 (OASIS), PSK Reporter MQTT feed"; }
        }
        enum clubLog {
            doc /* The Club Log Most Wanted download, on request. */
            @FollowsSource { reference = "Club Log mostwanted.php API, JSON"; }
        }
        enum timeServer {
            doc /* The SNTP servers. */
            @FollowsSource { reference = "RFC 4330 SNTP client, RFC 5905 packet"; }
        }
        enum windowsTime {
            doc /* The Windows Time service, its state read only. */
            @FollowsSource { reference = "Win32 Service Control Manager API"; }
        }
        enum profileFiles {
            doc /* The profile directory and its files. */
            @FollowsSource {
                reference = "ADIF 3.1.8 ADI (contacts.adi); RIFF WAVE PCM (recordings); "
                    + "AD1C cty.dat; the other files are the product's own formats "
                    + "of their owning packages";
            }
        }
        enum tlsFiles {
            doc /* The TLS certificate and key files named at launch. */
            @FollowsSource { reference = "RFC 7468 PEM, X.509 certificate, PKCS#8 key"; }
        }
        enum resourceLocks {
            doc /* The radio identity lock files under %LOCALAPPDATA%. */
            @FollowsSource { reference = "Windows file locking through std::fs::File::try_lock"; }
        }
    }

    part def StationContext {
        doc /* The station and the outside things around it. An outside thing is a black box:
             it has no inner structure and no requirement names it as its subject. The
             function that owns it is the one its port is joined to; for the five without a
             port, the function its doc names. */
        part station : Station;

        part operator {
            doc /* The licensed person who operates the station through the browser. */
            port link : ~OperatorInteractionPort;
        }
        part mcpClient {
            doc /* An MCP client, a program that operates the station with the operator's
                 rights. */
            port link : ~McpPort;
        }
        part catRadio : Radio {
            doc /* The transceiver reached through its CAT serial link. */
            port link : ~CatPort;
        }
        part flexRadio : Radio {
            doc /* A FlexRadio reached through its native API. */
            port link : ~FlexApiPort;
        }
        part soundDevice {
            doc /* The sound-card capture and playback endpoints. */
            port link : ~SoundDevicePort;
        }
        part udpPeer {
            doc /* The configured WSJT-X UDP targets, send-only. */
            port link : ~UdpPort;
        }
        part pskReporter {
            doc /* The PSK Reporter MQTT broker, subscribe-only. */
            port link : ~PskReporterPort;
        }
        part clubLog {
            doc /* The Club Log most-wanted download. */
            port link : ~ClubLogPort;
        }
        part timeServer {
            doc /* The SNTP time servers. */
            port link : ~TimeSourcePort;
        }
        part browser {
            doc /* The operator's browser program, over HTTPS and WebSocket on the station
                 listener. Its owner is the web function. */
        }
        part windowsTime {
            doc /* The Windows Time service, its state read only. Its owner is the transmit
                 function. */
        }
        part profileFiles {
            doc /* The profile directory and its files. Its owner is the profile function. */
        }
        part tlsFiles {
            doc /* The TLS certificate and key files named at launch. Its owner is the web
                 function. */
        }
        part resourceLocks {
            doc /* The radio identity lock files. Its owner is the radio authority. */
        }

        interface operatorInteractionLink : OperatorInteraction
            connect station.frontend.browsers.operator to operator.link;
        interface mcpLink : Mcp connect station.backend.stations.mcp.agent to mcpClient.link;
        interface catLink : Cat connect station.backend.stations.catAdapter.radio to catRadio.link;
        interface soundDeviceLink : SoundDevice
            connect station.backend.stations.audioAdapter.device to soundDevice.link;
        interface flexApiLink : FlexApi
            connect station.backend.stations.flexAdapter.radio to flexRadio.link;
        interface udpLink : Udp connect station.backend.stations.udp.peers to udpPeer.link;
        interface pskReporterLink : PskReporter
            connect station.backend.stations.spots.pskReporter to pskReporter.link;
        interface clubLogLink : ClubLog
            connect station.backend.stations.ranking.clubLog to clubLog.link;
        interface timeSourceLink : TimeSource
            connect station.backend.stations.clock.timeSource to timeServer.link;
    }

    part context : StationContext;

    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose context::station::*;
    }
}
