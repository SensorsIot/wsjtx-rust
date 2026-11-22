package WstxMcpPart {
    private import ScalarValues::*;
    private import WstxStationCommands::AgentOperations;
    private import WstxMcp::McpPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;

    part def McpAdapter {
        doc /* The station's door for agents: it speaks MCP and carries the features of the
             station boundary between an agent and the supervisor as the tools say
             (WstxMcp::ToolRule). It decides nothing of the station's state. */
        @ImplementedIn {
            module = "server/src/mcp/endpoint.rs";
        }
        @DetailTests {
            tests = "server/src/mcp/endpoint_tests.rs";
            covers = "the refusal of the MCP principal on the routes no tool reaches and its "
                + "commands that reset no watchdog";
        }
        port agent : McpPort { doc /* The agents of the station. */ }
        port supervisor : AgentOperations {
            doc /* The agents' commands and reads to the supervisor, its answers and views
                 back. */ }
    }
}
