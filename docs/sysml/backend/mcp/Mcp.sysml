package WstxMcpPart {
    private import ScalarValues::*;
    private import WstxStationCommands::StationOperations;
    private import WstxMcp::McpPort;
    private import WstxModelBindings::ImplementedIn;

    part def McpAdapter {
        doc /* The station's door for agents: it speaks MCP and carries the features of the
             station boundary between an agent and the supervisor as the tools say
             (WstxMcp::ToolRule). It decides nothing of the station's state. */
        @ImplementedIn { module = "server/src/mcp.rs"; }
        port agent : McpPort { doc /* The agents of the station. */ }
        port supervisor : StationOperations {
            doc /* The agents' commands and reads to the supervisor, its answers and views
                 back. */ }
    }
}
