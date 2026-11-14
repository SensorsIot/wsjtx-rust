package WstxReceivePart {
    private import ScalarValues::*;
    private import WstxModeProcessing::ReceiveProcessing;
    private import WstxAudioStreams::ReceiveSamples;
    private import WstxReceiveControl::ReceiveControlPort;
    private import WstxDecodes::DecodesPort;
    private import WstxDisplayData::DisplayDataPort;
    private import WstxPeriodTiming::PeriodTimingPort;
    part def ReceivePipeline {
        doc /* Own sample-window handling, normalization/resampling and bounded jobs/spectrum; not file dialogs, HTTP, CAT or UI rendering. PCM-unit mapping is not gain control and native conversion has one owner. */
        doc /* One shared native-format/rate conversion owner feeds canonical samples;
             no source-specific modem resamplers. PCM unit mapping differs from AGC
             and modem normalization. WstxRecordingReceive owns recorded spectrum,
             shared RustFFT 6.4.1 ordering/scaling and buffer obligations;
             WstxModemDecode owns mode window/history/decoder quanta and independent
             vectors; WstxRadioIO owns live adapter/conversion semantics. */
        port jobs : ~ReceiveControlPort;
        port audio : ~ReceiveSamples;
        port processing : ReceiveProcessing;
        port decodes : DecodesPort;
        port display : DisplayDataPort;
        port timing : ~PeriodTimingPort;
    }
    dependency coordinatedReceivePromise from ReceivePipeline to WstxOperatingReceive::'CL-008-07';
}
