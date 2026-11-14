package WstxWebPart {
    private import ScalarValues::*;
    private import WstxStationLink::BrowserExchange;
    private import WstxRecordingTransfer::RecordingTransfer;
    private import WstxStationCommands::StationOperations;
    private import WstxDisplayData::DisplayDataPort;
    part def WebAdapter {
        attribute privateRuntimeInputs : WstxStationLink::RuntimeInputs;
        attribute effectiveEndpoint : WstxStationProtocol::EndpointPolicy;
        doc /* Runtime inputs and effective transport/authentication settings are distinct
             from saved endpoint intent. No credential values are instantiated here. */
        doc /* Own embedded client, HTTP/file transfer/versioned WebSocket, transport authentication and Origin checks; no second QSO/modem engine or direct radio writes. */
        doc /* WstxStationProtocol owns shared authentication, Origin and HTTP/WebSocket
             semantics. WstxHttpContentCoding::HttpContentCodingBoundary refines bounded
             GET coding after handler/auth/errors/caps, with one dispatch and unchanged
             JSON/WebSocket identity; it creates no second transport authority. */
        port client : ~BrowserExchange;
        port station : StationOperations;
        port recording : RecordingTransfer;
        port display : ~DisplayDataPort;
    }
    package ImplementedStatusSlice {
        doc /* Implemented status/TLS subset alongside WstxProfiles profile functionality.
             The target deployment does not assert full radio/modem or MCP delivery;
             detailed coverage remains in WstxRequirements and the owning packages. */
        part def StatusServer;
        dependency statusScope from StatusServer to WstxStationProtocol::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxStationProtocol::'CL-003-02';
    }
}
