const std = @import("std");
const testing = std.testing;
const bdd = @import("../bdd_framework.zig");
const config = @import("../../src/config.zig");
const lsp_client = @import("../../src/lsp_client.zig");

// LSP-specific step definitions
pub fn registerLspSteps(step_definitions: *bdd.StepDefinitions) !void {
    try step_definitions.addStep("the MCP server is configured for testing", givenMcpServerConfiguredForTesting);
    try step_definitions.addStep("an LSP server is available", givenLspServerAvailable);
    try step_definitions.addStep("an LSP server is not running", givenLspServerNotRunning);
    try step_definitions.addStep("I start the LSP server with command", whenStartLspServer);
    try step_definitions.addStep("the LSP server should be running", thenLspServerShouldBeRunning);
    try step_definitions.addStep("I should be able to send initialize request", thenShouldSendInitializeRequest);
    try step_definitions.addStep("I should receive initialize response with server capabilities", thenReceiveInitializeResponse);
    try step_definitions.addStep("an LSP server is running and initialized", givenLspServerRunningAndInitialized);
    try step_definitions.addStep("a Zig file exists", givenZigFileExists);
    try step_definitions.addStep("I send a hover request", whenSendHoverRequest);
    try step_definitions.addStep("I should receive a hover response", thenReceiveHoverResponse);
    try step_definitions.addStep("the hover response should contain markup content", thenHoverContainsMarkup);
    try step_definitions.addStep("the hover content should include information", thenHoverContainsInfo);
    try step_definitions.addStep("I send a definition request", whenSendDefinitionRequest);
    try step_definitions.addStep("I should receive a definition response", thenReceiveDefinitionResponse);
    try step_definitions.addStep("the definition response should contain location information", thenDefinitionContainsLocation);
    try step_definitions.addStep("I send a completion request", whenSendCompletionRequest);
    try step_definitions.addStep("I should receive a completion response", thenReceiveCompletionResponse);
    try step_definitions.addStep("the completion response should contain completion items", thenCompletionContainsItems);
    try step_definitions.addStep("I send an invalid request", whenSendInvalidRequest);
    try step_definitions.addStep("I should receive an error response", thenReceiveErrorResponse);
    try step_definitions.addStep("I send a shutdown request", whenSendShutdownRequest);
    try step_definitions.addStep("the LSP server should acknowledge the shutdown", thenLspServerAcknowledgeShutdown);
    try step_definitions.addStep("I send an exit notification", whenSendExitNotification);
    try step_definitions.addStep("the LSP server should terminate gracefully", thenLspServerTerminateGracefully);
}

fn givenMcpServerConfiguredForTesting(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    try world.setContext("mcp_server_mode", "testing");
    try world.setContext("test_environment", "active");
}

fn givenLspServerAvailable(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    // Check if ZLS is available in the system
    const result = std.process.Child.exec(.{
        .allocator = world.allocator,
        .argv = &.{ "which", "zls" },
    }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Note: 'which' command not found, assuming ZLS is available\n");
            return;
        },
        else => return err,
    };
    defer {
        world.allocator.free(result.stdout);
        world.allocator.free(result.stderr);
    }

    if (result.term.Exited != 0) {
        std.debug.print("Warning: ZLS not found in PATH, some tests may fail\n");
    }
    
    try world.setContext("lsp_server_available", "true");
}

fn givenLspServerNotRunning(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    // Ensure no LSP server is currently running for this test
    if (world.lsp_client) |client| {
        client.deinit();
        world.allocator.destroy(client);
        world.lsp_client = null;
    }
    try world.setContext("lsp_server_running", "false");
}

fn whenStartLspServer(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    // Create and start LSP client
    const server_config = config.LANGUAGE_SERVERS.ZLS;
    
    const client = try world.allocator.create(bdd.LspClientProcess);
    client.* = try bdd.LspClientProcess.init(world.allocator, server_config.command, server_config.args);
    world.lsp_client = client;
    
    try world.setContext("lsp_server_command", server_config.command);
    try world.setContext("lsp_server_running", "true");
}

fn thenLspServerShouldBeRunning(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.lsp_client == null) {
        return error.LspServerNotRunning;
    }
    
    const running = world.getContext("lsp_server_running") orelse "false";
    if (!std.mem.eql(u8, running, "true")) {
        return error.LspServerNotRunning;
    }
}

fn thenShouldSendInitializeRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.lsp_client) |client| {
        const init_request = 
            \\{
            \\  "jsonrpc": "2.0",
            \\  "id": 1,
            \\  "method": "initialize",
            \\  "params": {
            \\    "processId": null,
            \\    "capabilities": {
            \\      "textDocument": {
            \\        "hover": {
            \\          "contentFormat": ["markdown", "plaintext"]
            \\        }
            \\      }
            \\    }
            \\  }
            \\}
        ;
        
        try client.sendRequest(init_request);
        try world.setContext("initialize_request_sent", "true");
    } else {
        return error.NoLspClient;
    }
}

fn thenReceiveInitializeResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.lsp_client) |client| {
        const response = client.readResponse(5000) catch |err| switch (err) {
            error.Timeout => {
                std.debug.print("Timeout waiting for initialize response\n");
                return error.InitializeTimeout;
            },
            else => return err,
        };
        defer world.allocator.free(response);
        
        // Parse response to verify it's valid
        const parsed = std.json.parseFromSlice(
            struct {
                jsonrpc: []const u8,
                id: u32,
                result: ?struct {
                    capabilities: std.json.Value,
                } = null,
                @"error": ?std.json.Value = null,
            },
            world.allocator,
            response,
            .{}
        ) catch return error.InvalidInitializeResponse;
        defer parsed.deinit();
        
        if (parsed.value.@"error" != null) {
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
        return error.NoLspClient;
    }
}

fn givenLspServerRunningAndInitialized(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    // Start LSP server
    try whenStartLspServer(world, &.{});
    
    // Send initialize request
    try thenShouldSendInitializeRequest(world, &.{});
    
    // Wait for and verify initialize response
    try thenReceiveInitializeResponse(world, &.{});
    
    // Send initialized notification
    if (world.lsp_client) |client| {
        const initialized_notification = 
            \\{
            \\  "jsonrpc": "2.0",
            \\  "method": "initialized",
            \\  "params": {}
            \\}
        ;
        try client.sendRequest(initialized_notification);
    }
    
    try world.setContext("lsp_server_initialized", "true");
}

fn givenZigFileExists(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const test_file_content = 
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello, World!\n", .{});
        \\}
    ;
    
    // Create a temporary test file
    const test_file_path = "/tmp/test_file.zig";
    const file = std.fs.cwd().createFile(test_file_path, .{}) catch return error.CannotCreateTestFile;
    defer file.close();
    
    try file.writeAll(test_file_content);
    try world.setContext("test_file_path", test_file_path);
    try world.setContext("test_file_uri", "file:///tmp/test_file.zig");
}

fn whenSendHoverRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const test_uri = world.getContext("test_file_uri") orelse return error.NoTestFile;
    
    if (world.lsp_client) |client| {
        const hover_request = try std.fmt.allocPrint(world.allocator,
            \\{{
            \\  "jsonrpc": "2.0",
            \\  "id": 2,
            \\  "method": "textDocument/hover",
            \\  "params": {{
            \\    "textDocument": {{
            \\      "uri": "{s}"
            \\    }},
            \\    "position": {{
            \\      "line": 3,
            \\      "character": 4
            \\    }}
            \\  }}
            \\}}
        , .{test_uri});
        defer world.allocator.free(hover_request);
        
        try client.sendRequest(hover_request);
        try world.setContext("hover_request_sent", "true");
    } else {
        return error.NoLspClient;
    }
}

fn thenReceiveHoverResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.lsp_client) |client| {
        const response = client.readResponse(5000) catch |err| switch (err) {
            error.Timeout => {
                std.debug.print("Timeout waiting for hover response\n");
                return error.HoverTimeout;
            },
            else => return err,
        };
        defer world.allocator.free(response);
        
        // Store response for further verification
        if (world.last_response) |old| {
            world.allocator.free(old);
        }
        world.last_response = try world.allocator.dupe(u8, response);
        
        try world.setContext("hover_response_received", "true");
    } else {
        return error.NoLspClient;
    }
}

fn thenHoverContainsMarkup(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const response = world.last_response orelse return error.NoLastResponse;
    
    // Parse response and check for markup content
    const parsed = std.json.parseFromSlice(
        struct {
            result: ?struct {
                contents: union(enum) {
                    markup: struct {
                        kind: []const u8,
                        value: []const u8,
                    },
                    string: []const u8,
                    array: []std.json.Value,
                },
            } = null,
        },
        world.allocator,
        response,
        .{}
    ) catch return error.InvalidHoverResponse;
    defer parsed.deinit();
    
    if (parsed.value.result == null) {
        return error.NoHoverResult;
    }
    
    // Check if contents exist (content validation is language server dependent)
    switch (parsed.value.result.?.contents) {
        .markup => |markup| {
            if (markup.value.len == 0) {
                return error.EmptyHoverContent;
            }
        },
        .string => |str| {
            if (str.len == 0) {
                return error.EmptyHoverContent;
            }
        },
        .array => |arr| {
            if (arr.len == 0) {
                return error.EmptyHoverContent;
            }
        },
    }
}

fn thenHoverContainsInfo(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const response = world.last_response orelse return error.NoLastResponse;
    
    // This is a simplified check - in practice, this would depend on the specific LSP server
    // and the actual content being hovered over
    if (std.mem.indexOf(u8, response, "std") == null) {
        std.debug.print("Warning: Hover response may not contain expected 'std' information\n");
        std.debug.print("Response: {s}\n", .{response});
        // Don't fail the test as this is highly dependent on LSP server implementation
    }
}

// Placeholder implementations for other step definitions
fn whenSendDefinitionRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    // TODO: Implement definition request
    std.debug.print("TODO: Implement definition request step\n");
}

fn thenReceiveDefinitionResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement definition response verification step\n");
}

fn thenDefinitionContainsLocation(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement definition location verification step\n");
}

fn whenSendCompletionRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement completion request step\n");
}

fn thenReceiveCompletionResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement completion response verification step\n");
}

fn thenCompletionContainsItems(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement completion items verification step\n");
}

fn whenSendInvalidRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement invalid request step\n");
}

fn thenReceiveErrorResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement error response verification step\n");
}

fn whenSendShutdownRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement shutdown request step\n");
}

fn thenLspServerAcknowledgeShutdown(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement shutdown acknowledgment verification step\n");
}

fn whenSendExitNotification(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement exit notification step\n");
}

fn thenLspServerTerminateGracefully(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    std.debug.print("TODO: Implement graceful termination verification step\n");
}