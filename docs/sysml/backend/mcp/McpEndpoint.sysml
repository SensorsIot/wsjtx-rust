package WstxMcpEndpoint {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-020';
    private import WstxMcpPart::McpAdapter;
    private import WstxMcp::*;
    private import WstxStationCommands::AgentRefusal;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* mcp's functions: the endpoint and the tools. */

    requirement 'CL-012-01' {
        subject mcp : McpAdapter;
        doc /* mcp MUST serve MCP as EndpointRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-020'; end #derive ::> 'CL-012-01'; }

    attribute def EndpointRule {
        doc /* mcp serves the endpoint of WstxMcp::McpEndpoint in the versions of
             WstxMcp::ProtocolVersions, and keeps nothing between two requests. */
    }

    requirement 'CL-012-02' {
        subject mcp : McpAdapter;
        doc /* mcp MUST offer an agent the station's operations as ToolUse says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-020'; end #derive ::> 'CL-012-02'; }

    attribute def ToolUse {
        doc /* mcp offers every feature of WstxStationCommands::AgentOperations as
             WstxMcp::ToolRule says and answers as WstxMcp::ToolResult says: an agent reads
             the views the browser reads, gives the commands the browser gives but those
             AgentRefusal names, and gets the same answers and refusals, with the
             operator's rights. mcp passes each command and read to the supervisor and
             holds no state of the station. */
        attribute agentRefusal : AgentRefusal[0..*] {
            doc /* The commands mcp offers no tool for. */ }
    }

    verification 'TC-020-001' {
        doc /* An agent reads what the browser reads, in both protocol eras. */
        subject mcp : McpAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-012-01'; verify 'CL-012-02'; }
        @TestedBy {
            test = "server/src/mcp/endpoint_tests.rs::"
                + "tc_020_001_mcp_observes_the_browser_state_in_both_protocol_eras; "
                + "tests/mcp/mcp.test.cjs::"
                + "an MCP client with its own MCP client token observes the browser state "
                + "of the actual executable";
        }
    }
    verification 'TC-020-005' {
        doc /*
    Endpoint refusals, and argument errors and station refusals as tool errors, before any effect.
        */
        subject mcp : McpAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-012-01'; verify 'CL-012-02'; }
        @TestedBy {
            test = "server/src/mcp/endpoint_tests.rs::"
        + "tc_020_002_invalid_unauthorized_and_wrong_station_requests_are_refused_before_effects";
        }
    }
}
