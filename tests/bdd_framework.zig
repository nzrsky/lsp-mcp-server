const std = @import("std");
const testing = std.testing;

// BDD framework types and utilities
pub const Scenario = struct {
    name: []const u8,
    description: []const u8,
    steps: []Step,
    tags: [][]const u8 = &.{},
    pending: bool = false,

    pub const Step = struct {
        kind: Kind,
        text: []const u8,
        data: ?StepData = null,

        pub const Kind = enum {
            given,
            when,
            then,
            @"and",
            but,
        };

        pub const StepData = union(enum) {
            table: [][]const u8,
            doc_string: []const u8,
            examples: struct {
                headers: [][]const u8,
                rows: [][][]const u8,
            },
        };
    };
};

pub const Feature = struct {
    name: []const u8,
    description: []const u8,
    scenarios: []Scenario,
    background: ?Background = null,
    tags: [][]const u8 = &.{},

    pub const Background = struct {
        steps: []Scenario.Step,
    };
};

pub const World = struct {
    allocator: std.mem.Allocator,
    context: std.StringHashMap([]const u8),
    variables: std.StringHashMap(std.json.Value),
    mcp_server: ?*McpServerProcess = null,
    lsp_client: ?*@import("lsp_client").LspClient = null,
    last_response: ?[]const u8 = null,
    last_error: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .context = std.StringHashMap([]const u8).init(allocator),
            .variables = std.StringHashMap(std.json.Value).init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        if (self.mcp_server) |server| {
            server.deinit();
            self.allocator.destroy(server);
        }
        if (self.lsp_client) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        if (self.last_response) |resp| {
            self.allocator.free(resp);
        }
        if (self.last_error) |err| {
            self.allocator.free(err);
        }

        var ctx_iter = self.context.iterator();
        while (ctx_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.context.deinit();

        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.variables.deinit();
    }

    pub fn setContext(self: *World, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.context.put(key_copy, value_copy);
    }

    pub fn getContext(self: *World, key: []const u8) ?[]const u8 {
        return self.context.get(key);
    }

    pub fn setVariable(self: *World, key: []const u8, value: std.json.Value) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        try self.variables.put(key_copy, value);
    }

    pub fn getVariable(self: *World, key: []const u8) ?std.json.Value {
        return self.variables.get(key);
    }
};

pub const McpServerProcess = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,
    stdin: std.fs.File.Writer,
    stdout: std.fs.File.Reader,
    stderr: std.fs.File.Reader,

    pub fn init(allocator: std.mem.Allocator, command: []const u8, args: [][]const u8) !*McpServerProcess {
        const self = try allocator.create(McpServerProcess);

        var argv = std.ArrayList([]const u8).init(allocator);
        defer argv.deinit();
        try argv.append(command);
        for (args) |arg| {
            try argv.append(arg);
        }

        var process = std.process.Child.init(argv.items, allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        try process.spawn();

        self.* = .{
            .allocator = allocator,
            .process = process,
            .stdin = process.stdin.?.writer(),
            .stdout = process.stdout.?.reader(),
            .stderr = process.stderr.?.reader(),
        };

        return self;
    }

    pub fn deinit(self: *McpServerProcess) void {
        _ = self.process.kill() catch {};
        _ = self.process.wait() catch {};
    }

    pub fn sendRequest(self: *McpServerProcess, request: []const u8) !void {
        try self.stdin.print("Content-Length: {d}\r\n\r\n", .{request.len});
        try self.stdin.writeAll(request);
    }

    pub fn readResponse(self: *McpServerProcess, timeout_ms: u64) ![]u8 {
        var buf: [65536]u8 = undefined;

        const start_time = std.time.milliTimestamp();

        // Read Content-Length header
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            if (self.stdout.readUntilDelimiterOrEof(&buf, '\n')) |header_opt| {
                if (header_opt) |header| {
                    if (std.mem.startsWith(u8, header, "Content-Length: ")) {
                        const len_str = header["Content-Length: ".len..];
                        const content_length = try std.fmt.parseInt(usize, std.mem.trim(u8, len_str, "\r"), 10);

                        // Skip empty line
                        _ = try self.stdout.readUntilDelimiterOrEof(&buf, '\n');

                        // Read JSON content
                        if (content_length <= buf.len) {
                            try self.stdout.readNoEof(buf[0..content_length]);
                            return self.allocator.dupe(u8, buf[0..content_length]);
                        }
                    }
                }
            } else |_| {
                break;
            }
        }

        return error.Timeout;
    }
};

pub const LspClientProcess = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,
    stdin: std.fs.File.Writer,
    stdout: std.fs.File.Reader,

    pub fn init(allocator: std.mem.Allocator, command: []const u8, args: [][]const u8) !*LspClientProcess {
        const self = try allocator.create(LspClientProcess);

        var argv = std.ArrayList([]const u8).init(allocator);
        defer argv.deinit();
        try argv.append(command);
        for (args) |arg| {
            try argv.append(arg);
        }

        var process = std.process.Child.init(argv.items, allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Ignore;

        try process.spawn();

        self.* = .{
            .allocator = allocator,
            .process = process,
            .stdin = process.stdin.?.writer(),
            .stdout = process.stdout.?.reader(),
        };

        return self;
    }

    pub fn deinit(self: *LspClientProcess) void {
        _ = self.process.kill() catch {};
        _ = self.process.wait() catch {};
    }
};

// Step definition registry
pub const StepDefinitions = struct {
    steps: std.StringHashMap(StepFunction),

    pub const StepFunction = *const fn (world: *World, matches: [][]const u8) anyerror!void;

    pub fn init(allocator: std.mem.Allocator) StepDefinitions {
        return .{
            .steps = std.StringHashMap(StepFunction).init(allocator),
        };
    }

    pub fn deinit(self: *StepDefinitions) void {
        self.steps.deinit();
    }

    pub fn addStep(self: *StepDefinitions, pattern: []const u8, func: StepFunction) !void {
        try self.steps.put(pattern, func);
    }

    pub fn findStep(self: *StepDefinitions, step_text: []const u8) ?StepFunction {
        // Simple exact match for now - could be enhanced with regex
        return self.steps.get(step_text);
    }

    pub fn matchStep(self: *StepDefinitions, step_text: []const u8, allocator: std.mem.Allocator) ?struct {
        func: StepFunction,
        matches: [][]const u8,
    } {
        _ = allocator;
        // Simple pattern matching - could be enhanced with regex
        var iterator = self.steps.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.indexOf(u8, step_text, entry.key_ptr.*)) |_| {
                return .{
                    .func = entry.value_ptr.*,
                    .matches = &.{}, // No captures for now
                };
            }
        }
        return null;
    }
};

// Test runner
pub const Runner = struct {
    allocator: std.mem.Allocator,
    step_definitions: StepDefinitions,
    features: std.ArrayList(Feature),
    results: TestResults,

    pub const TestResults = struct {
        total_scenarios: u32 = 0,
        passed_scenarios: u32 = 0,
        failed_scenarios: u32 = 0,
        pending_scenarios: u32 = 0,
        total_steps: u32 = 0,
        passed_steps: u32 = 0,
        failed_steps: u32 = 0,
        pending_steps: u32 = 0,
        failures: std.ArrayList(Failure),

        pub const Failure = struct {
            scenario_name: []const u8,
            step_text: []const u8,
            error_message: []const u8,
        };

        pub fn init(allocator: std.mem.Allocator) TestResults {
            return .{
                .failures = std.ArrayList(Failure).init(allocator),
            };
        }

        pub fn deinit(self: *TestResults) void {
            for (self.failures.items) |failure| {
                // Note: In a real implementation, we'd need to manage memory for these strings
                _ = failure;
            }
            self.failures.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) Runner {
        return .{
            .allocator = allocator,
            .step_definitions = StepDefinitions.init(allocator),
            .features = std.ArrayList(Feature).init(allocator),
            .results = TestResults.init(allocator),
        };
    }

    pub fn deinit(self: *Runner) void {
        self.step_definitions.deinit();
        self.features.deinit();
        self.results.deinit();
    }

    pub fn addFeature(self: *Runner, feature: Feature) !void {
        try self.features.append(feature);
    }

    pub fn addStepDefinition(self: *Runner, pattern: []const u8, func: StepDefinitions.StepFunction) !void {
        try self.step_definitions.addStep(pattern, func);
    }

    pub fn runFeature(self: *Runner, feature: Feature) !void {
        std.debug.print("Feature: {s}\n", .{feature.name});
        if (feature.description.len > 0) {
            std.debug.print("  {s}\n", .{feature.description});
        }

        for (feature.scenarios) |scenario| {
            try self.runScenario(scenario, feature.background);
        }
    }

    pub fn runScenario(self: *Runner, scenario: Scenario, background: ?Feature.Background) !void {
        self.results.total_scenarios += 1;

        if (scenario.pending) {
            self.results.pending_scenarios += 1;
            std.debug.print("  Scenario: {s} (PENDING)\n", .{scenario.name});
            return;
        }

        std.debug.print("  Scenario: {s}\n", .{scenario.name});

        var world = World.init(self.allocator);
        defer world.deinit();

        var scenario_failed = false;

        // Run background steps first
        if (background) |bg| {
            for (bg.steps) |step| {
                if (self.runStep(&world, step)) {
                    // Step passed
                } else |err| {
                    scenario_failed = true;
                    try self.results.failures.append(.{
                        .scenario_name = scenario.name,
                        .step_text = step.text,
                        .error_message = @errorName(err),
                    });
                    break;
                }
            }
        }

        // Run scenario steps
        if (!scenario_failed) {
            for (scenario.steps) |step| {
                if (self.runStep(&world, step)) {
                    // Step passed
                } else |err| {
                    scenario_failed = true;
                    try self.results.failures.append(.{
                        .scenario_name = scenario.name,
                        .step_text = step.text,
                        .error_message = @errorName(err),
                    });
                    break;
                }
            }
        }

        if (scenario_failed) {
            self.results.failed_scenarios += 1;
            std.debug.print("    FAILED\n", .{});
        } else {
            self.results.passed_scenarios += 1;
            std.debug.print("    PASSED\n", .{});
        }
    }

    pub fn runStep(self: *Runner, world: *World, step: Scenario.Step) !void {
        self.results.total_steps += 1;

        const step_kind_str = switch (step.kind) {
            .given => "Given",
            .when => "When",
            .then => "Then",
            .@"and" => "And",
            .but => "But",
        };

        std.debug.print("    {s} {s}\n", .{ step_kind_str, step.text });

        if (self.step_definitions.matchStep(step.text, self.allocator)) |match| {
            match.func(world, match.matches) catch |err| {
                self.results.failed_steps += 1;
                return err;
            };
            self.results.passed_steps += 1;
        } else {
            self.results.pending_steps += 1;
            std.debug.print("      (PENDING - no step definition found)\n", .{});
            return error.PendingStep;
        }
    }

    pub fn runAll(self: *Runner) !void {
        std.debug.print("Running BDD tests...\n\n", .{});

        for (self.features.items) |feature| {
            try self.runFeature(feature);
            std.debug.print("\n", .{});
        }

        // Print summary
        std.debug.print("Test Results:\n", .{});
        std.debug.print("=============\n", .{});
        std.debug.print("Scenarios: {d} total, {d} passed, {d} failed, {d} pending\n", .{
            self.results.total_scenarios,
            self.results.passed_scenarios,
            self.results.failed_scenarios,
            self.results.pending_scenarios,
        });
        std.debug.print("Steps: {d} total, {d} passed, {d} failed, {d} pending\n", .{
            self.results.total_steps,
            self.results.passed_steps,
            self.results.failed_steps,
            self.results.pending_steps,
        });

        if (self.results.failures.items.len > 0) {
            std.debug.print("\nFailures:\n", .{});
            for (self.results.failures.items) |failure| {
                std.debug.print("  Scenario: {s}\n", .{failure.scenario_name});
                std.debug.print("    Step: {s}\n", .{failure.step_text});
                std.debug.print("    Error: {s}\n", .{failure.error_message});
            }
        }
    }
};
