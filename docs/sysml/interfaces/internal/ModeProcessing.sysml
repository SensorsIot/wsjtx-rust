package WstxModeProcessing {
    private import ScalarValues::*;
    private import WstxArchitecture::ProcessingRequest;
    private import WstxArchitecture::ProcessingResult;
    private import WstxArchitecture::EncodeRequest;
    private import WstxArchitecture::Waveform;
    port def ReceiveProcessing {
        out item request : ProcessingRequest;
        in item result : ProcessingResult;
    }
    port def EncodeProcessing {
        out item request : EncodeRequest;
        in item waveform : Waveform;
    }
}
