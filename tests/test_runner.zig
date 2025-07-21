const std = @import("std");
const bdd = @import("bdd_framework.zig");

// Define test scenarios directly in code (in a real implementation, these would be parsed from .feature files)
const test_scenarios = [_]bdd.Scenario{
    // Basic MCP server initialization test
    .{
        .name = "MCP server initialization",
        .description = "Test that the MCP server can be initialized properly",
        .steps = @constCast(&[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "the MCP server is available" },
            .{ .kind = .when, .text = "I send an initialize request" },
            .{ .kind = .then, .text = "I should receive an initialize response" },
            .{ .kind = .@"and", .text = "the response should contain server capabilities" },
        }),
        .tags = @constCast(&[_][]const u8{ "mcp", "initialization" }),
    },
    
    // Tools list test
    .{
        .name = "List available tools",
        .description = "Test that the MCP server returns available tools",
        .steps = @constCast(&[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "the MCP server is initialized" },
            .{ .kind = .when, .text = "I send a tools/list request" },
            .{ .kind = .then, .text = "I should receive a list of available tools" },
            .{ .kind = .@"and", .text = "the tool list should include" },
            .{ .kind = .@"and", .text = "each tool should have a name, description, and input schema" },
        }),
        .tags = @constCast(&[_][]const u8{ "mcp", "tools" }),
    },
    
    // LSP server basic test
    .{
        .name = "Initialize LSP connection",
        .description = "Test that we can initialize an LSP server",
        .steps = @constCast(&[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "the MCP server is configured for testing" },
            .{ .kind = .@"and", .text = "an LSP server is available" },
            .{ .kind = .when, .text = "I start the LSP server with command" },
            .{ .kind = .then, .text = "the LSP server should be running" },
            .{ .kind = .@"and", .text = "I should be able to send initialize request" },
            .{ .kind = .@"and", .text = "I should receive initialize response with server capabilities" },
        }),
        .tags = @constCast(&[_][]const u8{ "lsp", "initialization" }),
    },
    
    // Hover functionality test
    .{
        .name = "Send hover request",
        .description = "Test hover functionality through LSP",
        .steps = @constCast(&[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "an LSP server is running and initialized" },
            .{ .kind = .@"and", .text = "a Zig file exists" },
            .{ .kind = .when, .text = "I send a hover request" },
            .{ .kind = .then, .text = "I should receive a hover response" },
            .{ .kind = .@"and", .text = "the hover response should contain markup content" },
        }),
        .tags = @constCast(&[_][]const u8{ "lsp", "hover" }),
        .pending = false, // This test should work
    },
};

const test_feature = bdd.Feature{
    .name = "LSP-MCP Bridge Testing",
    .description = "Comprehensive testing of LSP and MCP protocol integration",
    .scenarios = @constCast(&test_scenarios),
    .tags = @constCast(&[_][]const u8{ "integration", "protocol" }),
};

// MCP Server step implementations
fn givenMcpServerIsAvailable(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    // Build our MCP server first
    var child = std.process.Child.init(&.{ "zig", "build" }, world.allocator);
    child.stdout_behavior = .Ignore; // Don't capture stdout for build
    child.stderr_behavior = .Ignore; // Don't capture stderr for build
    
    try child.spawn();
    const term = try child.wait();
    
    if (term.Exited != 0) {
        std.debug.print("MCP server build failed with exit code: {}\n", .{term.Exited});
        return error.McpServerBuildFailed;
    }
    
    // Start the MCP server process with ZLS
    const server = try bdd.McpServerProcess.init(
        world.allocator,
        "./zig-out/bin/lsp-mcp-server", 
        @constCast(&[_][]const u8{ "--server", "zls" })
    );
    world.mcp_server = server;
    
    // Give it a moment to start
    std.time.sleep(500 * std.time.ns_per_ms); // Increased startup time
    
    std.debug.print("MCP server started, waiting for it to be ready...\n", .{});
}

fn whenISendInitializeRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.mcp_server == null) {
        return error.NoMcpServer;
    }
    
    const init_request = 
        \\{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"capabilities": {}, "clientInfo": {"name": "test-client", "version": "1.0.0"}}}
    ;
    
    std.debug.print("Sending initialize request: {s}\n", .{init_request});
    try world.mcp_server.?.sendRequest(init_request);
    try world.setContext("last_request", "initialize");
}

fn thenIShouldReceiveInitializeResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.mcp_server == null) {
        return error.NoMcpServer;
    }
    
    const response = world.mcp_server.?.readResponse(1000) catch |err| switch (err) {
        error.Timeout => {
            std.debug.print("Timeout waiting for initialize response (1s)\n", .{});
            return error.InitializeTimeout;
        },
        else => {
            std.debug.print("Error reading initialize response: {}\n", .{err});
            return err;
        }
    };
    defer world.allocator.free(response);
    
    // Store response for further verification
    if (world.last_response) |old| {
        world.allocator.free(old);
    }
    world.last_response = try world.allocator.dupe(u8, response);
}

fn thenResponseShouldContainServerCapabilities(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const response = world.last_response orelse return error.NoLastResponse;
    
    std.debug.print("Parsing initialize response: {s}\n", .{response});
    
    // Parse response and verify it contains capabilities  
    const parsed = std.json.parseFromSlice(
        struct {
            jsonrpc: []const u8,
            id: u32,
            result: ?struct {
                protocolVersion: []const u8,
                capabilities: struct {
                    tools: std.json.Value,
                },
                serverInfo: struct {
                    name: []const u8,
                    version: []const u8,
                },
            } = null,
            @"error": ?std.json.Value = null,
        },
        world.allocator,
        response,
        .{}
    ) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        return error.InvalidInitializeResponse;
    };
    defer parsed.deinit();
    
    if (parsed.value.result == null) {
        return error.NoInitializeResult;
    }
}

fn givenMcpServerIsInitialized(world: *bdd.World, matches: [][]const u8) !void {
    try givenMcpServerIsAvailable(world, matches);
    try whenISendInitializeRequest(world, matches);
    try thenIShouldReceiveInitializeResponse(world, matches);
    try thenResponseShouldContainServerCapabilities(world, matches);
}

fn whenISendToolsListRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.mcp_server == null) {
        return error.NoMcpServer;
    }
    
    const tools_request = 
        \\{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
    ;
    
    try world.mcp_server.?.sendRequest(tools_request);
    try world.setContext("last_request", "tools/list");
}

fn thenIShouldReceiveListOfTools(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    if (world.mcp_server == null) {
        return error.NoMcpServer;
    }
    
    const response = world.mcp_server.?.readResponse(5000) catch |err| switch (err) {
        error.Timeout => {
            std.debug.print("Timeout waiting for tools/list response\n", .{});
            return error.ToolsListTimeout;
        },
        else => return err,
    };
    defer world.allocator.free(response);
    
    if (world.last_response) |old| {
        world.allocator.free(old);
    }
    world.last_response = try world.allocator.dupe(u8, response);
}

fn thenToolListShouldInclude(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const response = world.last_response orelse return error.NoLastResponse;
    
    std.debug.print("Tools list response: {s}\n", .{response});
    
    // Check that response contains result array with tools
    if (std.mem.indexOf(u8, response, "result")) |_| {
        std.debug.print("Found 'result' in response\n", .{});
        // Check for specific tool names
        if (std.mem.indexOf(u8, response, "hover") != null and 
            std.mem.indexOf(u8, response, "definition") != null and 
            std.mem.indexOf(u8, response, "completions") != null) {
            std.debug.print("Found all expected tools: hover, definition, completions\n", .{});
        } else {
            std.debug.print("Missing some expected tools\n", .{});
            return error.MissingExpectedTools;
        }
    } else {
        std.debug.print("No 'result' found in response\n", .{});
        return error.NoToolsInResponse;
    }
}

fn thenEachToolShouldHaveSchema(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    const response = world.last_response orelse return error.NoLastResponse;
    
    // Basic check for tool schema fields
    const required_fields = [_][]const u8{ "name", "description", "inputSchema" };
    for (required_fields) |field| {
        if (std.mem.indexOf(u8, response, field) == null) {
            std.debug.print("Missing required field: {s}\n", .{field});
            return error.MissingToolSchemaField;
        }
    }
}

// LSP step implementations (these will definitely fail initially)
fn givenMcpServerConfiguredForTesting(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    try world.setContext("test_mode", "active");
}

fn givenLspServerIsAvailable(world: *bdd.World, matches: [][]const u8) !void {
    _ = matches;
    
    // Check if ZLS is available at the known path
    var which_child = std.process.Child.init(&.{ "/Users/nazaroff/bin/zls", "--version" }, world.allocator);
    which_child.stdout_behavior = .Ignore;
    which_child.stderr_behavior = .Ignore;
    
    which_child.spawn() catch |err| switch (err) {
        error.FileNotFound => {
            // Try fallback with which command
            var fallback_child = std.process.Child.init(&.{ "which", "zls" }, world.allocator);
            fallback_child.stdout_behavior = .Ignore;
            fallback_child.stderr_behavior = .Ignore;
            fallback_child.spawn() catch {
                return error.ZlsNotAvailable;
            };
            const fallback_result = fallback_child.wait() catch {
                return error.ZlsNotAvailable;
            };
            if (fallback_result.Exited != 0) {
                return error.ZlsNotAvailable;
            }
            return;
        },
        else => return err,
    };
    
    const which_result = which_child.wait() catch {
        return error.ZlsNotAvailable;
    };
    
    if (which_result.Exited != 0) {
        return error.ZlsNotAvailable;
    }
}

fn whenIStartLspServer(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn thenLspServerShouldBeRunning(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn thenIShouldSendInitializeToLsp(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn thenIShouldReceiveLspInitializeResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn givenLspServerRunningAndInitialized(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn givenZigFileExists(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn whenISendHoverRequest(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn thenIShouldReceiveHoverResponse(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

fn thenHoverResponseShouldContainMarkup(world: *bdd.World, matches: [][]const u8) !void {
    _ = world;
    _ = matches;
    return error.LspServerNotImplemented;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runner = bdd.Runner.init(allocator);
    defer runner.deinit();

    // Register real step definitions that will actually test functionality
    try runner.addStepDefinition("the MCP server is available", givenMcpServerIsAvailable);
    try runner.addStepDefinition("I send an initialize request", whenISendInitializeRequest);
    try runner.addStepDefinition("I should receive an initialize response", thenIShouldReceiveInitializeResponse);
    try runner.addStepDefinition("the response should contain server capabilities", thenResponseShouldContainServerCapabilities);
    try runner.addStepDefinition("the MCP server is initialized", givenMcpServerIsInitialized);
    try runner.addStepDefinition("I send a tools/list request", whenISendToolsListRequest);
    try runner.addStepDefinition("I should receive a list of available tools", thenIShouldReceiveListOfTools);
    try runner.addStepDefinition("the tool list should include", thenToolListShouldInclude);
    try runner.addStepDefinition("each tool should have a name, description, and input schema", thenEachToolShouldHaveSchema);
    try runner.addStepDefinition("the MCP server is configured for testing", givenMcpServerConfiguredForTesting);
    try runner.addStepDefinition("an LSP server is available", givenLspServerIsAvailable);
    try runner.addStepDefinition("I start the LSP server with command", whenIStartLspServer);
    try runner.addStepDefinition("the LSP server should be running", thenLspServerShouldBeRunning);
    try runner.addStepDefinition("I should be able to send initialize request", thenIShouldSendInitializeToLsp);
    try runner.addStepDefinition("I should receive initialize response with server capabilities", thenIShouldReceiveLspInitializeResponse);
    try runner.addStepDefinition("an LSP server is running and initialized", givenLspServerRunningAndInitialized);
    try runner.addStepDefinition("a Zig file exists", givenZigFileExists);
    try runner.addStepDefinition("I send a hover request", whenISendHoverRequest);
    try runner.addStepDefinition("I should receive a hover response", thenIShouldReceiveHoverResponse);
    try runner.addStepDefinition("the hover response should contain markup content", thenHoverResponseShouldContainMarkup);

    // Add our test feature
    try runner.addFeature(test_feature);

    // Run all tests
    try runner.runAll();

    // Exit with appropriate code
    if (runner.results.failed_scenarios > 0) {
        std.process.exit(1);
    }
}

// Unit tests for the BDD framework itself
test "BDD framework basic functionality" {
    const allocator = std.testing.allocator;
    
    var world = bdd.World.init(allocator);
    defer world.deinit();
    
    try world.setContext("test_key", "test_value");
    try std.testing.expectEqualStrings("test_value", world.getContext("test_key").?);
    
    const json_value = std.json.Value{ .string = "test_json" };
    try world.setVariable("json_key", json_value);
    const retrieved = world.getVariable("json_key").?;
    try std.testing.expectEqualStrings("test_json", retrieved.string);
}

test "Step definitions registry" {
    const allocator = std.testing.allocator;
    
    var step_defs = bdd.StepDefinitions.init(allocator);
    defer step_defs.deinit();
    
    const test_func: bdd.StepDefinitions.StepFunction = struct {
        fn testStep(world: *bdd.World, matches: [][]const u8) !void {
            _ = world;
            _ = matches;
        }
    }.testStep;
    
    try step_defs.addStep("test step pattern", test_func);
    const found = step_defs.findStep("test step pattern");
    try std.testing.expect(found != null);
}

test "Scenario and Feature structures" {
    const test_step = bdd.Scenario.Step{
        .kind = .given,
        .text = "a test condition",
    };
    
    const test_scenario = bdd.Scenario{
        .name = "Test Scenario",
        .description = "A test scenario for testing",
        .steps = @constCast(&[_]bdd.Scenario.Step{test_step}),
    };
    
    const test_feature_local = bdd.Feature{
        .name = "Test Feature",
        .description = "A test feature",
        .scenarios = @constCast(&[_]bdd.Scenario{test_scenario}),
    };
    
    try std.testing.expectEqualStrings("Test Feature", test_feature_local.name);
    try std.testing.expectEqualStrings("Test Scenario", test_feature_local.scenarios[0].name);
    try std.testing.expectEqualStrings("a test condition", test_feature_local.scenarios[0].steps[0].text);
}