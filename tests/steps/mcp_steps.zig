const std = @import("std");
const testing = std.testing;
const bdd = @import("../bdd_framework.zig");

// MCP-specific step definitions
pub fn registerMcpSteps(step_definitions: *bdd.StepDefinitions) !void {
    try step_definitions.addStep("the MCP server is available", givenMcpServerAvailable);
    try step_definitions.addStep("the MCP server supports LSP integration", givenMcpServerSupportsLsp);
    try step_definitions.addStep("the MCP server is not initialized", givenMcpServerNotInitialized);
    try step_definitions.addStep("I send an initialize request", whenSendInitializeRequest);
    try step_definitions.addStep("I should receive an initialize response", thenReceiveInitializeResponse);
    try step_definitions.addStep("the response should contain server capabilities", thenResponseContainsCapabilities);
    try step_definitions.addStep("the response should indicate tool support", thenResponseIndicatesToolSupport);
    try step_definitions.addStep("the server should be marked as initialized", thenServerMarkedInitialized);
    try step_definitions.addStep("the MCP server is initialized", givenMcpServerInitialized);
    try step_definitions.addStep("I send a tools/list request", whenSendToolsListRequest);
    try step_definitions.addStep("I should receive a list of available tools", thenReceiveToolsList);
    try step_definitions.addStep("the tool list should include", thenToolListIncludes);
    try step_definitions.addStep("each tool should have a name, description, and input schema", thenToolsHaveRequiredFields);
    try step_definitions.addStep("an LSP server is configured", givenLspServerConfigured);
    try step_definitions.addStep("I call the tool with parameters", whenCallToolWithParameters);
    try step_definitions.addStep("I should receive a successful tool response", thenReceiveSuccessfulToolResponse);
    try step_definitions.addStep("the response should contain hover information", thenResponseContainsHoverInfo);
    try step_definitions.addStep("the hover information should have content", thenHoverInfoHasContent);
    try step_definitions.addStep("the content should be properly formatted", thenContentProperlyFormatted);
    try step_definitions.addStep("the response should contain definition locations", thenResponseContainsDefinitionLocations);
    try step_definitions.addStep("each location should have a URI and range", thenLocationHasUriAndRange);
    try step_definitions.addStep("the response should contain completion items", thenResponseContainsCompletionItems);
    try step_definitions.addStep("each completion item should have a label", thenCompletionItemHasLabel);
    try step_definitions.addStep("completion items should have appropriate kinds", thenCompletionItemsHaveKinds);
    try step_definitions.addStep("I call the tool with invalid parameters", whenCallToolWithInvalidParameters);
    try step_definitions.addStep("the error should indicate invalid parameters", thenErrorIndicatesInvalidParams);
    try step_definitions.addStep("the error code should be", thenErrorCodeShouldBe);
    try step_definitions.addStep("I call the tool with missing parameters", whenCallToolWithMissingParameters);
    try step_definitions.addStep("the error should indicate missing required parameters", thenErrorIndicatesMissingParams);
    try step_definitions.addStep("I call an unknown tool", whenCallUnknownTool);
    try step_definitions.addStep("the error should indicate unknown tool", thenErrorIndicatesUnknownTool);
    try step_definitions.addStep("I send a malformed JSON request", whenSendMalformedJson);
    try step_definitions.addStep("I send a request for unknown method", whenSendUnknownMethod);
}

fn givenMcpServerAvailable(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    // Start the MCP server process
    const server = try bdd.McpServerProcess.init(world.allocator, "./zig-out/bin/zls-mcp-server", &.{});
    world.mcp_server = server;

    // Give the server a moment to start
    std.time.sleep(100 * std.time.ns_per_ms);

    try world.setContext("mcp_server_available", "true");
}

fn givenMcpServerSupportsLsp(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    try world.setContext("mcp_lsp_support", "true");
}

fn givenMcpServerNotInitialized(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    try world.setContext("mcp_server_initialized", "false");
}

fn whenSendInitializeRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    if (world.mcp_server) |server| {
        const init_request =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "id": 1,
            \\  "method": "initialize",
            \\  "params": {
            \\    "protocolVersion": "0.1.0",
            \\    "capabilities": {
            \\      "tools": {}
            \\    },
            \\    "clientInfo": {
            \\      "name": "test-client",
            \\      "version": "1.0.0"
            \\    }
            \\  }
            \\}
        ;

        try server.sendRequest(init_request);
        try world.setContext("initialize_request_sent", "true");
    } else {
        return error.NoMcpServer;
    }
}

fn thenReceiveInitializeResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    if (world.mcp_server) |server| {
        const response = server.readResponse(5000) catch |err| switch (err) {
            error.Timeout => {
                std.debug.print("Timeout waiting for MCP initialize response\n");
                return error.InitializeTimeout;
            },
            else => return err,
        };
        defer world.allocator.free(response);

        // Parse response to verify it's valid
        const parsed = std.json.parseFromSlice(struct {
            jsonrpc: []const u8,
            id: u32,
            result: ?struct {
                protocolVersion: []const u8,
                capabilities: std.json.Value,
                serverInfo: struct {
                    name: []const u8,
                    version: []const u8,
                },
            } = null,
            @"error": ?std.json.Value = null,
        }, world.allocator, response, .{}) catch return error.InvalidInitializeResponse;
        defer parsed.deinit();

        if (parsed.value.@"error" != null) {
            std.debug.print("Initialize error: {}\n", .{parsed.value.@"error".?});
            return error.InitializeError;
        }

        if (parsed.value.result == null) {
            return error.NoInitializeResult;
        }

        try world.setContext("initialize_response_received", "true");
        if (world.last_response) |old| {
            world.allocator.free(old);
        }
        world.last_response = try world.allocator.dupe(u8, response);
    } else {
        return error.NoMcpServer;
    }
}

fn thenResponseContainsCapabilities(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    const response = world.last_response orelse return error.NoLastResponse;

    if (std.mem.indexOf(u8, response, "capabilities") == null) {
        return error.NoCapsInResponse;
    }
}

fn thenResponseIndicatesToolSupport(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    const response = world.last_response orelse return error.NoLastResponse;

    if (std.mem.indexOf(u8, response, "tools") == null) {
        return error.NoToolSupportInResponse;
    }
}

fn thenServerMarkedInitialized(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    try world.setContext("mcp_server_initialized", "true");
}

fn givenMcpServerInitialized(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    // Start server if not already started
    if (world.mcp_server == null) {
        try givenMcpServerAvailable(world, &.{});
    }

    // Send initialize request
    try whenSendInitializeRequest(world, &.{});

    // Wait for and verify initialize response
    try thenReceiveInitializeResponse(world, &.{});

    try world.setContext("mcp_server_initialized", "true");
}

fn whenSendToolsListRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    if (world.mcp_server) |server| {
        const tools_request =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "id": 2,
            \\  "method": "tools/list"
            \\}
        ;

        try server.sendRequest(tools_request);
        try world.setContext("tools_list_request_sent", "true");
    } else {
        return error.NoMcpServer;
    }
}

fn thenReceiveToolsList(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    if (world.mcp_server) |server| {
        const response = server.readResponse(5000) catch |err| switch (err) {
            error.Timeout => {
                std.debug.print("Timeout waiting for tools list response\n");
                return error.ToolsListTimeout;
            },
            else => return err,
        };
        defer world.allocator.free(response);

        // Store response for further verification
        if (world.last_response) |old| {
            world.allocator.free(old);
        }
        world.last_response = try world.allocator.dupe(u8, response);

        // Verify it's a valid tools list response
        const parsed = std.json.parseFromSlice(struct {
            result: ?[]struct {
                name: []const u8,
                description: []const u8,
                inputSchema: std.json.Value,
            } = null,
        }, world.allocator, response, .{}) catch return error.InvalidToolsListResponse;
        defer parsed.deinit();

        if (parsed.value.result == null) {
            return error.NoToolsListResult;
        }

        try world.setContext("tools_list_received", "true");
    } else {
        return error.NoMcpServer;
    }
}

fn thenToolListIncludes(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    const response = world.last_response orelse return error.NoLastResponse;

    // Check for presence of expected tools
    const expected_tools = &.{ "hover", "definition", "completions" };
    for (expected_tools) |tool| {
        if (std.mem.indexOf(u8, response, tool) == null) {
            std.debug.print("Missing tool: {s}\n", .{tool});
            return error.MissingExpectedTool;
        }
    }
}

fn thenToolsHaveRequiredFields(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    const response = world.last_response orelse return error.NoLastResponse;

    // Check for required fields in tools
    const required_fields = &.{ "name", "description", "inputSchema" };
    for (required_fields) |field| {
        if (std.mem.indexOf(u8, response, field) == null) {
            std.debug.print("Missing required field: {s}\n", .{field});
            return error.MissingRequiredField;
        }
    }
}

fn givenLspServerConfigured(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    try world.setContext("lsp_server_configured", "zls");
}

fn whenCallToolWithParameters(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    if (world.mcp_server) |server| {
        const tool_call_request =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "id": 3,
            \\  "method": "tools/call",
            \\  "params": {
            \\    "name": "hover",
            \\    "arguments": {
            \\      "uri": "file:///tmp/test.zig",
            \\      "line": 2,
            \\      "character": 10
            \\    }
            \\  }
            \\}
        ;

        try server.sendRequest(tool_call_request);
        try world.setContext("tool_call_request_sent", "true");
    } else {
        return error.NoMcpServer;
    }
}

fn thenReceiveSuccessfulToolResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;

    if (world.mcp_server) |server| {
        const response = server.readResponse(10000) catch |err| switch (err) {
            error.Timeout => {
                std.debug.print("Timeout waiting for tool response\n");
                return error.ToolResponseTimeout;
            },
            else => return err,
        };
        defer world.allocator.free(response);

        // Store response for further verification
        if (world.last_response) |old| {
            world.allocator.free(old);
        }
        world.last_response = try world.allocator.dupe(u8, response);

        // Check that it's not an error response
        if (std.mem.indexOf(u8, response, "\"error\"") != null) {
            std.debug.print("Received error response: {s}\n", .{response});
            return error.ToolCallError;
        }

        try world.setContext("tool_response_received", "true");
    } else {
        return error.NoMcpServer;
    }
}

// Placeholder implementations for other step definitions
fn thenResponseContainsHoverInfo(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement hover info verification\n");
}

fn thenHoverInfoHasContent(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement hover content verification\n");
}

fn thenContentProperlyFormatted(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement content formatting verification\n");
}

fn thenResponseContainsDefinitionLocations(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement definition locations verification\n");
}

fn thenLocationHasUriAndRange(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement location URI and range verification\n");
}

fn thenResponseContainsCompletionItems(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement completion items verification\n");
}

fn thenCompletionItemHasLabel(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement completion item label verification\n");
}

fn thenCompletionItemsHaveKinds(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement completion item kinds verification\n");
}

fn whenCallToolWithInvalidParameters(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement invalid parameters test\n");
}

fn thenErrorIndicatesInvalidParams(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement invalid params error verification\n");
}

fn thenErrorCodeShouldBe(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement error code verification\n");
}

fn whenCallToolWithMissingParameters(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement missing parameters test\n");
}

fn thenErrorIndicatesMissingParams(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement missing params error verification\n");
}

fn whenCallUnknownTool(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement unknown tool test\n");
}

fn thenErrorIndicatesUnknownTool(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement unknown tool error verification\n");
}

fn whenSendMalformedJson(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement malformed JSON test\n");
}

fn whenSendUnknownMethod(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement unknown method test\n");
}
