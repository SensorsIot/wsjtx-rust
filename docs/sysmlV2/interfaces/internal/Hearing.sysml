package WstxHearing {
    private import ScalarValues::*;
    private import WstxModeProcessing::PeriodParity;
    private import WstxModeProcessing::Mode;
    private import WstxPskReporter::FeedError;

    doc /* What spots tells ranking and auto: which stations hear us (HeardByReport), and
         what the station being called hears (TargetReport).
         Everything in a report is about the station's band and mode: the band of the dial
         that radio control confirms, else the band of the operating selection, and the
         station's operating mode. */

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
            doc /* The audio offset: the frequency of the spot less the confirmed dial. */ }
        attribute parity : PeriodParity {
            doc /* The period in which the sender of the spot transmitted. */ }
    }
    attribute def DecodedOffsets {
        doc /* The frequencies the target decodes, the newest first, each pair of offset
             and parity once. An empty list means that the target has no such spot. */
        attribute offsets : DecodedOffset[0..32] ordered;
    }
    attribute def TargetHearing {
        doc /* What the feed says about the target of a run. */
        attribute call : String;
        attribute 'state' : HearingState;
        attribute spotSeconds : Integer[0..1] {
            doc /* The time of the newest spot of the profile's call at the target, in
                 seconds of UTC since 1970. Present in the state heard. */ }
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
        doc /* What the station being called hears: whether it hears us and how strong,
             and the frequencies it already decodes in each period, for the automatic
             choice of the transmit frequency. Given at once from what the feed has
             delivered so far. */
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
        doc /* Written from the side of spots; auto has the conjugate. */
        out item report : TargetReport;
    }
    interface def TargetHearingLink {
        doc /* What the station being called hears, from spots to auto. */
        end spots : TargetHearingPort;
        end auto : ~TargetHearingPort;
    }

    // ---- The station service and spots --------------------------------------------------

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
                 admitted. */ }
        attribute report : Boolean = false {
            doc /* The station reports the stations it decodes to PSK Reporter
                 (WstxSpotsReporting::ReceptionReports). */ }
        attribute reportCollector : String = "udp://report.pskreporter.info:4739" {
            doc /* Where the reports go: udp://host:port or tcp://host:port, with the
                 host and the port as for feedBroker. */ }
    }
    attribute def FeedStatus {
        doc /* The switches and the state of the feed at the moment they are read. */
        attribute enabled : Boolean { doc /* SpotsConfig::enabled. */ }
        attribute 'use' : Boolean { doc /* SpotsConfig::'use'. */ }
        attribute 'state' : FeedState;
        attribute error : FeedError[0..1] { doc /* Present in the state error. */ }
        attribute lastSpotSeconds : Integer[0..1] {
            doc /* The time of the newest Spot used, in seconds of UTC since 1970.
                 Absent until one arrives after the feed was switched on. */ }
    }
    item def SpotsConfiguration {
        doc /* The configuration of spots, one of the operator's settings. The station
             service gives it at station start and whenever they change. */
        attribute config : SpotsConfig;
    }
    item def FeedContext {
        doc /* What spots needs to know of the station. The station service gives it at
             station start and whenever one of its values changes. */
        attribute call : String[0..1] {
            doc /* The profile's call. Absent while the profile has none. */ }
        attribute locator : String[0..1] {
            doc /* The profile's locator. Absent while the profile has none. */ }
        attribute target : String[0..1] {
            doc /* The call of the station a run's own contact is with. Absent while no
                 such contact is active. */ }
        attribute band : String[0..1] {
            doc /* The station's band: that of the dial radio control confirms, else
                 that of the operating selection. Absent without either. */ }
        attribute mode : Mode { doc /* The station's operating mode. */ }
        attribute dialHz : Integer[0..1] {
            doc /* The dial radio control confirms. Absent while none is confirmed. */ }
    }
    item def FeedReport {
        doc /* The state of the feed, given whenever it changes. */
        attribute status : FeedStatus;
    }
    port def SpotsControlPort {
        doc /* Written from the station service's side; spots uses the conjugate.
             SpotsConfiguration and FeedContext have no answer. */
        out item configuration : SpotsConfiguration;
        out item context : FeedContext;
        in item report : FeedReport;
    }
    interface def SpotsControl {
        doc /* The station service commands spots; spots reports the state of the feed. */
        end station : SpotsControlPort;
        end spots : ~SpotsControlPort;
    }
}
