package WstxStationLink {
    private import ScalarValues::*;
    private import WstxArchitecture::Recording;
    private import WstxStationCommands::StationOperations;
    port def BrowserExchange :> StationOperations {
        out item upload : Recording;
    }
}
