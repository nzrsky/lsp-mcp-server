const std = @import("std");
const bdd = @import("bdd_framework.zig");
const lsp_steps = @import("steps/lsp_steps.zig");
const mcp_steps = @import("steps/mcp_steps.zig");

// Define test scenarios directly in code (in a real implementation, these would be parsed from .feature files)
const test_scenarios = [_]bdd.Scenario{
    // Basic MCP server initialization test
    .{
        .name = "MCP server initialization",
        .description = "Test that the MCP server can be initialized properly",
        .steps = &[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "the MCP server is available" },
            .{ .kind = .when, .text = "I send an initialize request" },
            .{ .kind = .then, .text = "I should receive an initialize response" },
            .{ .kind = .and, .text = "the response should contain server capabilities" },
        },
        .tags = &.{ "mcp", "initialization" },
    },
    
    // Tools list test
    .{
        .name = "List available tools",
        .description = "Test that the MCP server returns available tools",
        .steps = &[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "the MCP server is initialized" },
            .{ .kind = .when, .text = "I send a tools/list request" },
            .{ .kind = .then, .text = "I should receive a list of available tools" },
            .{ .kind = .and, .text = "the tool list should include" },
            .{ .kind = .and, .text = "each tool should have a name, description, and input schema" },
        },
        .tags = &.{ "mcp", "tools" },
    },
    
    // LSP server basic test
    .{
        .name = "Initialize LSP connection",
        .description = "Test that we can initialize an LSP server",
        .steps = &[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "the MCP server is configured for testing" },
            .{ .kind = .and, .text = "an LSP server is available" },
            .{ .kind = .when, .text = "I start the LSP server with command" },
            .{ .kind = .then, .text = "the LSP server should be running" },
            .{ .kind = .and, .text = "I should be able to send initialize request" },
            .{ .kind = .and, .text = "I should receive initialize response with server capabilities" },
        },
        .tags = &.{ "lsp", "initialization" },
    },
    
    // Hover functionality test
    .{
        .name = "Send hover request",
        .description = "Test hover functionality through LSP",
        .steps = &[_]bdd.Scenario.Step{
            .{ .kind = .given, .text = "an LSP server is running and initialized" },
            .{ .kind = .and, .text = "a Zig file exists" },
            .{ .kind = .when, .text = "I send a hover request" },
            .{ .kind = .then, .text = "I should receive a hover response" },
            .{ .kind = .and, .text = "the hover response should contain markup content" },
        },
        .tags = &.{ "lsp", "hover" },
        .pending = false, // This test should work
    },
};

const test_feature = bdd.Feature{
    .name = "LSP-MCP Bridge Testing",
    .description = "Comprehensive testing of LSP and MCP protocol integration",
    .scenarios = &test_scenarios,
    .tags = &.{ "integration", "protocol" },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runner = bdd.Runner.init(allocator);
    defer runner.deinit();

    // Register step definitions
    try lsp_steps.registerLspSteps(&runner.step_definitions);
    try mcp_steps.registerMcpSteps(&runner.step_definitions);

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
        .steps = &[_]bdd.Scenario.Step{test_step},
    };
    
    const test_feature_local = bdd.Feature{
        .name = "Test Feature",
        .description = "A test feature",
        .scenarios = &[_]bdd.Scenario{test_scenario},
    };
    
    try std.testing.expectEqualStrings("Test Feature", test_feature_local.name);
    try std.testing.expectEqualStrings("Test Scenario", test_feature_local.scenarios[0].name);
    try std.testing.expectEqualStrings("a test condition", test_feature_local.scenarios[0].steps[0].text);
}