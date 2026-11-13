package WstxStationCommands {
    private import ScalarValues::*;
    private import WstxArchitecture::StationOutcome;
    private import WstxArchitecture::StationRequest;

    port def StationOperations {
        out item request : StationRequest;
        in item outcome : StationOutcome;
    }
}
