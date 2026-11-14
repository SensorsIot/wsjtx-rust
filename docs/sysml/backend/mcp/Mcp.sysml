package WstxMcpPart {
    private import ScalarValues::*;
    private import WstxStationCommands::StationOperations;
    private import WstxMcpInterface::McpPort;
    part def McpAdapter {
        doc /* Own protocol validation/caller context and configured station-selection/automation requests. No independent station state, backend access or separate transmit permission; same station operations and safety policy as browser. Delivered (#12) as the station's Streamable HTTP endpoint mapping each tool onto one existing station route in-process (WstxMcpInterface::ToolCatalog); the configured automation run is owned with the contact engine (WstxMcp::OperatingAutomation) and reaches it only through ContactCommand. */
        port station : StationOperations;
        port agent : McpPort;
    }
}
