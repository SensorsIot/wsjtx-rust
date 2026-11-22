package WstxReceivePart {
    private import ScalarValues::*;
    private import WstxReceiveControl::ReceiveControlPort;
    private import WstxReceiveControl::ReceiveConfig;
    private import WstxAudioStreams::ReceiveSamples;
    private import WstxRecordingTransfer::RecordedSamples;
    private import WstxModeProcessing::ReceiveProcessing;
    private import WstxDecodes::DecodesPort;
    private import WstxDisplayData::DisplayDataPort;
    private import WstxStationTime::StationTimePort;
    private import WstxStationTime::StationsHeardPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def ReceiveService {
        doc /* The receive function of the station. It runs one job at a time. A live job
             takes the receive stream from audio, makes spectrum rows of it and, in the
             mode FT4 or FT8, cuts it into windows, has the modes part decode them and
             publishes the decoded frames of each period. A replay makes spectrum rows
             of the stored recording. */
        @ImplementedIn {
            module = "server/src/receive/recording.rs; server/src/receive/receive.rs; "
                + "server/src/receive/spectrum.rs; server/src/receive/receive_diagnostics.rs; "
                + "server/src/receive/receive_http.rs";
        }
        @DetailTests {
            tests = "server/src/receive/recording_tests.rs; server/tests/receive_integration.rs; "
                + "server/src/operating/qso/contact_http_tests.rs";
            covers = "the conversion of a time to UTC text; the limits of a block the "
                + "window buffer takes; the call hash table shared with transmit";
        }
        attribute config : ReceiveConfig {
            doc /* Its configuration, as the last ReceiveConfiguration gave it. */ }
        port jobs : ~ReceiveControlPort;
        port audio : ~ReceiveSamples;
        port recorded : ~RecordedSamples;
        port processing : ReceiveProcessing;
        port decodes : DecodesPort;
        port display : DisplayDataPort;
        port time : ~StationTimePort;
        port heard : StationsHeardPort;
    }
}
