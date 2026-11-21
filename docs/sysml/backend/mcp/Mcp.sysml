package WstxMcpPart {
    private import ScalarValues::*;
    private import WstxStationCommands::AgentOperations;
    private import WstxMcp::McpPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def McpAdapter {
        doc /* The station's door for agents: it speaks MCP and carries the features of the
             station boundary between an agent and the supervisor as the tools say
             (WstxMcp::ToolRule). It decides nothing of the station's state. */
        @ImplementedIn {
            module = "server/src/mcp.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/mcp.rs, outside server/src/mcp/ and "
                + "client/src/mcp/.";
        }
        @DetailTests {
            tests = "server/src/mcp_tests.rs";
            covers = "the refusal of the MCP principal on the routes no tool reaches and its "
                + "commands that reset no watchdog";
        }
        port agent : McpPort { doc /* The agents of the station. */ }
        port supervisor : AgentOperations {
            doc /* The agents' commands and reads to the supervisor, its answers and views
                 back. */ }
    }
}
