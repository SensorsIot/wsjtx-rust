package WstxContext {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;
    private import WstxArchitecture::physicalStation;

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
    dependency catRadioOwner from OutsideThing::catRadio
        to physicalStation::backend::stations::radioControl;
    dependency flexRadioOwner from OutsideThing::flexRadio
        to physicalStation::backend::stations::receive;
    dependency soundDeviceOwner from OutsideThing::soundDevice
        to physicalStation::backend::stations::audio;
    dependency browserOwner from OutsideThing::browser
        to physicalStation::backend::stations::web;
    dependency mcpClientOwner from OutsideThing::mcpClient
        to physicalStation::backend::stations::mcp;
    dependency udpPeerOwner from OutsideThing::udpPeer
        to physicalStation::backend::stations::station;
    dependency pskReporterOwner from OutsideThing::pskReporter
        to physicalStation::backend::stations::qso;
    dependency clubLogOwner from OutsideThing::clubLog
        to physicalStation::backend::stations::qso;
    dependency timeServerOwner from OutsideThing::timeServer
        to physicalStation::backend::stations::transmit;
    dependency windowsTimeOwner from OutsideThing::windowsTime
        to physicalStation::backend::stations::transmit;
    dependency profileFilesOwner from OutsideThing::profileFiles
        to physicalStation::backend::stations::profile;
    dependency tlsFilesOwner from OutsideThing::tlsFiles
        to physicalStation::backend::stations::web;
    dependency resourceLocksOwner from OutsideThing::resourceLocks
        to physicalStation::backend::radioAuthority;
}
