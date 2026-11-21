package WstxHearing {
    private import ScalarValues::*;
    private import WstxModeProcessing::PeriodParity;
    private import WstxModeProcessing::Mode;
    private import WstxPskReporter::FeedError;
    private import WstxModelNotes::CodeDiffers;

    doc /* What spots tells ranking, auto, qso and the supervisor: which stations hear us
         (HeardByReport), and what the station of the contact in progress hears
         (TargetReport).
         Everything in a report is about the station's band
         (WstxOperatingSelection::StationBandRule) and the station's operating mode. */

    enum def HearingState {
        doc /* Whether the target hears the station.
             heard: a spot of the profile's call at the target counts.
             no: the feed is connected, the target's spots are subscribed and no such spot
             counts.
             unknown: every other case. */
        enum heard;
        enum no;
        enum unknown;
    }

    attribute def DecodedOffset {
        doc /* One frequency the target decodes. */
        attribute offsetHz : Integer {
            doc /* The audio offset: the frequency of the spot less the confirmed dial. */
            @CodeDiffers {
                what = "The code holds the offset as the first of a pair of offset and parity "
                    + "(Hearing::decoded in server/src/operating/qso/pskr.rs).";
            }
        }
        attribute parity : PeriodParity {
            doc /* The period in which the sender of the spot transmitted. */ }
    }
    attribute def DecodedOffsets {
        doc /* The frequencies the target decodes, the newest first, each pair of offset
             and parity once. An empty list means that the target has no such spot. */
        attribute offsets : DecodedOffset[0..32] ordered {
            @CodeDiffers {
                what = "The code gives the list by Feed::decoded_offsets and "
                    + "Feed::decoded_of_parity in server/src/operating/qso/pskr.rs.";
            }
        }
    }
    attribute def TargetHearing {
        doc /* What the feed says about the target. */
        attribute call : String;
        attribute 'state' : HearingState;
        attribute spotSeconds : Integer[0..1] {
            doc /* The time of the newest spot of the profile's call at the target, in
                 seconds of UTC since 1970. Present in the state heard. */
            @CodeDiffers {
                what = "The code names it spot_utc_s (HearingState::json in "
                    + "server/src/operating/qso/pskr.rs).";
            }
        }
        attribute snrDb : Integer[0..1] {
            doc /* The signal-to-noise ratio the target reported in that spot. Absent when
                 the spot names none, and outside the state heard. */ }
        attribute reports : Boolean {
            doc /* The target sends spots: a spot it received, from any sender, counts. */ }
        attribute decoded : DecodedOffsets[0..1] {
            doc /* Absent while they are unknown: without a band or a confirmed dial. */ }
    }
    item def HeardByReport {
        doc /* Which stations hear us: for ranking, which of the stations it orders have
             heard the station. Given at once from what the feed has delivered so far. */
        attribute inUse : Boolean {
            doc /* The operator's two switches of the feed are on. While this is false
                 heardBy is empty and means unknown. */ }
        attribute heardBy : String[0..*] {
            doc /* The calls of the stations at which a spot of the profile's call
                 counts. */ }
    }
    item def TargetReport {
        doc /* What the station of the contact in progress hears: whether it hears us and
             how strong, and the frequencies it already decodes in each period, for
             Auto's Tx moves, for qso's quiet space and for the screen. Given at once
             from what the feed has delivered so far. */
        attribute inUse : Boolean {
            doc /* The operator's two switches of the feed are on. While this is false
                 there is no target. */ }
        attribute target : TargetHearing[0..1] {
            doc /* Absent while spots follows no target. */ }
    }

    port def HeardByPort {
        doc /* Written from the side of spots; ranking has the conjugate. */
        out item report : HeardByReport;
    }
    interface def HeardByLink {
        doc /* Which stations hear us, from spots to ranking. */
        end spots : HeardByPort;
        end ranking : ~HeardByPort;
    }
    port def TargetHearingPort {
        doc /* Written from the side of spots; auto and qso have the conjugate. */
        out item report : TargetReport;
    }
    interface def TargetHearingLink {
        doc /* What the station being called hears, from spots to auto and to qso. */
        end spots : TargetHearingPort;
        end reader : ~TargetHearingPort;
    }

    enum def FeedState {
        doc /* The state of the connection to the broker.
             off: the feed is switched off, or no session has been tried since station
             start, or no connection is allowed.
             connecting: an attempt runs, or the station waits for its next attempt
             after a session it ended itself.
             connected: the broker has accepted the greeting.
             error: the last session ended with a FeedError and the station waits for
             its next attempt. */
        enum off;
        enum connecting;
        enum connected;
        enum error;
    }
    attribute def SpotsConfig {
        doc /* The configuration of spots: the operator's switches of the PSK Reporter
             feed and of the reception reports, and where each of them goes. The
             defaults are the official PSK Reporter; a test profile names a
             simulator's addresses. */
        attribute enabled : Boolean = true {
            doc /* The station reads the feed. Off: spots holds no session with the
                 broker and knows no Spot. */ }
        attribute 'use' : Boolean = true {
            doc /* Runs use what the feed says. It counts only while enabled is on.
                 Off: the two reports tell nothing. */ }
        attribute feedBroker : String = "mqtts://mqtt.pskreporter.info:1884" {
            doc /* Where the feed is read: mqtts://host:port, over TLS, or
                 mqtt://host:port, without it. The host is a name or an address, the
                 port 1 to 65535; a login name, a path, a query or a fragment is not
                 admitted. */
            @CodeDiffers {
                what = "The broker is fixed: HOST mqtt.pskreporter.info and TLS_PORT 1884 "
                    + "in server/src/operating/qso/pskr.rs; no setting names it. The environment "
                    + "variable WSTX_PSKR, read at station start in server/src/main.rs, decides "
                    + "instead while it is set (station_connector in "
                    + "server/src/operating/qso/pskr.rs): tcp: followed by a loopback "
                    + "address and a port, as address:port, names a broker the station speaks "
                    + "with without TLS; every other value, also off and the empty value, allows "
                    + "no session, and the feed's state stays off whatever its switches.";
            }
        }
        attribute report : Boolean = false {
            doc /* The station reports the stations it decodes to PSK Reporter
                 (WstxSpotsReporting::ReceptionReports). */
            @CodeDiffers {
                what = "The station sends no reception reports and has no such setting.";
            }
        }
        attribute reportCollector : String = "udp://report.pskreporter.info:4739" {
            doc /* Where the reports go: udp://host:port or tcp://host:port, with the
                 host and the port as for feedBroker. */
            @CodeDiffers {
                what = "The station sends no reception reports and names no collector.";
            }
        }
    }
    attribute def FeedStatus {
        doc /* The switches and the state of the feed at the moment they are read. */
        attribute enabled : Boolean { doc /* SpotsConfig::enabled. */ }
        attribute 'use' : Boolean { doc /* SpotsConfig::'use'. */ }
        attribute 'state' : FeedState;
        attribute error : FeedError[0..1] { doc /* Present in the state error. */ }
        attribute lastSpotSeconds : Integer[0..1] {
            doc /* The time of the newest Spot used, in seconds of UTC since 1970.
                 Absent until one arrives after the feed was switched on. */
            @CodeDiffers {
                what = "The code names it last_spot_utc_s (the state of Feed in "
                    + "server/src/operating/qso/pskr.rs).";
            }
        }
    }
    item def SpotsConfiguration {
        doc /* The configuration of spots, one of the shack's settings. The supervisor
             gives it at station start and whenever they change. */
        attribute config : SpotsConfig;
    }
    item def FeedContext {
        doc /* What spots needs to know of the station. The supervisor gives it at
             station start and whenever one of its values changes. */
        attribute call : String[0..1] {
            doc /* The profile's call. Absent while the profile has none. */ }
        attribute locator : String[0..1] {
            doc /* The profile's locator. Absent while the profile has none. */ }
        attribute target : String[0..1] {
            doc /* The call of the station of the contact in progress, made by hand or by
                 Auto. Absent while no contact is active. */ }
        attribute band : String[0..1] {
            doc /* The station's band (WstxOperatingSelection::StationBandRule). */ }
        attribute mode : Mode { doc /* The station's operating mode. */ }
        attribute dialHz : Integer[0..1] {
            doc /* The dial radio control confirms. Absent while none is confirmed. */ }
    }
    item def FeedReport {
        doc /* The state of the feed, given whenever it changes. */
        attribute status : FeedStatus;
    }
    port def SpotsControlPort {
        doc /* Written from the supervisor's side; spots uses the conjugate.
             SpotsConfiguration and FeedContext have no answer. FeedReport and
             TargetReport are given whenever they change. */
        out item configuration : SpotsConfiguration;
        out item context : FeedContext;
        in item report : FeedReport;
        in item target : TargetReport;
    }
    interface def SpotsControl {
        doc /* The supervisor commands spots; spots reports the state of the feed and
             what the station of the contact in progress hears. */
        end station : SpotsControlPort;
        end spots : ~SpotsControlPort;
    }
}
