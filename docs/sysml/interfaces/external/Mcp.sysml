package WstxMcp {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    doc /* The exchange between an agent and the MCP function of one station: the endpoint,
         the protocol versions, the tools and their results. */

    port def McpPort {
        doc /* Written from the station's side; the agent uses the conjugate. */
        in item request : McpRequest;
        out item response : McpResponse;
    }
    item def McpRequest { doc /* One JSON-RPC request or notification of the agent. */ }
    item def McpResponse { doc /* The answer to one request. */ }
    interface def Mcp {
        doc /* An agent and the MCP function of one station. */
        end mcp : McpPort;
        end agent : ~McpPort;
    }

    attribute def McpEndpoint {
        doc /* mcp serves MCP's Streamable HTTP as the POST of /mcp on the station's listener
             (WstxListener::ListenRule), stateless and with JSON answers only: no session
             (Mcp-Session-Id is never issued and is ignored), no event stream. A request with
             an Origin other than the station's is refused with 403; one without Origin
             passes. A body above bodyBytesMax is refused with 413, one of another type than
             application/json with 415. One JSON-RPC object per request; a batch is refused.
             The GET and the DELETE of /mcp are refused with 405. Everything else of the
             exchange is as the protocol version says. */
        @FollowsSource {
            reference = "Model Context Protocol, Streamable HTTP transport and its security "
                + "warning on Origin; JSON-RPC 2.0";
        }
        attribute bodyBytesMax : Integer = 8192;
    }
    attribute def ProtocolVersions {
        doc /* The versions mcp speaks, in this order: modern, then legacy. A request in the
             modern version names it in its _meta; a legacy client begins with initialize.
             A request of another version is refused as the protocol says. */
        @FollowsSource { reference = "Model Context Protocol 2026-07-28, 2025-11-25, 2025-06-18"; }
        attribute modern : String = "2026-07-28";
        attribute legacy : String[2] = ("2025-11-25", "2025-06-18");
    }

    attribute def ToolRule {
        doc /* The tools are the second form of WstxStationCommands::StationOperations; their
             names and keys follow WstxStationLink::WireNames.
             wstxRead, read-only: its argument name is a view or a read, by the feature's
             name; arguments holds a read's attributes. Its result is the view or the read's
             answer.
             One tool per function that has commands, wstx_ and the function's name: its
             argument command names the command by its feature's name; its other arguments
             are profileId, bootId and commandId of the StationRequest and the attributes
             of the command's item, exactly those. The bytes of a file go as base64.
             Each tool's input schema lists exactly these arguments per command, with no
             other property.
             The requester of every command is agent. An argument that is missing, unknown or
             of the wrong type is a tool error with status 400 and invalidRequest with the
             field, and reaches no function.
             The server names the station: its title and its instructions carry the
             station's displayName and profile id, so that an agent given the addresses of
             several stations tells them apart. */
        @FollowsSource { reference = "Model Context Protocol, tools/list and tools/call"; }
    }
    attribute def ToolResult {
        doc /* The result of a tool: structuredContent exactly {v, tool, status, result},
             status the HTTP status the same request has on the station link and result its
             JSON body (the answer, the view or WstxStationLink::ErrorBody); one text content
             with the same JSON; isError when status is 400 or more. A refusal of the station
             is a tool error, never a JSON-RPC error. */
    }
}
