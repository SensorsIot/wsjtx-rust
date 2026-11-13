package WstxRadioControl {
    private import ScalarValues::*;
    private import WstxArchitecture::ControlOutcome;
    private import WstxArchitecture::ControlRequest;
    port def RadioControl {
        out item request : ControlRequest;
        in item outcome : ControlOutcome;
        binding replyContext bind outcome.request = request;
    }
}
