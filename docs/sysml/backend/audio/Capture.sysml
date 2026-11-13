package WstxAudioCapture {
    private import ScalarValues::*;
    private import WstxAudio::DeviceIntent;
    private import WstxAudioStreams::NativePacket;
    action def CaptureAudio {
        in intent : DeviceIntent;
        out packet : NativePacket;
        doc /* WASAPIshared/event-driven, exact inputID, no fallback. Bounded preallocated
             I/O pump releases packets before heavy work. NativeFIFO500ms; no disk spool.
             1/2/4/8s same-endpoint reopen only while capture desired; new epoch each open.
             Actual close before readiness/release; independent CAT remains responsive. */
    }
    action capture : CaptureAudio;
    satisfy WstxProfiles::'CL-008-01' by capture;
    satisfy WstxRadioIO::'CL-008-05' by capture;
    dependency captureOwner from capture to WstxArchitecture::physicalStation::backend::stations::audio;
}
