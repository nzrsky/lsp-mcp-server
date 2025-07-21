const std = @import("std");
const mcp = @import("mcp.zig");
const lsp_client = @import("lsp_client.zig");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var server_name: []const u8 = "zls"; // default
    var config_file: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--server")) {
            i += 1;
            if (i < args.len) {
                server_name = args[i];
            }
        } else if (std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i < args.len) {
                config_file = args[i];
            }
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            try printUsage();
            return;
        }
    }

    // Initialize server configurations
    var server_configs = config.ServerConfigs.init(allocator);
    defer server_configs.deinit();
    
    try server_configs.registerDefaults();
    
    // Load additional configurations if provided
    if (config_file) |path| {
        server_configs.loadFromFile(allocator, path) catch |err| {
            std.debug.print("Warning: Could not load config file {s}: {}\n", .{ path, err });
        };
    }

    // Get server configuration
    const server_config = server_configs.get(server_name) orelse {
        std.debug.print("Error: Unknown server '{s}'. Available servers:\n", .{server_name});
        var iter = server_configs.configs.keyIterator();
        while (iter.next()) |name| {
            std.debug.print("  - {s}\n", .{name.*});
        }
        return;
    };

    // Update server configuration with actual command path
    var actual_config = server_config;
    actual_config.command = try findServerCommand(allocator, server_config.command) orelse {
        std.debug.print("Error: Server command '{s}' not found in PATH\n", .{server_config.command});
        return;
    };

    // Initialize LSP client
    var lsp = try lsp_client.LspClient.init(allocator, actual_config);
    defer lsp.deinit();

    // Start LSP server
    try lsp.start();
    defer lsp.stop();

    // Initialize and start MCP server
    var server = mcp.Server.init(allocator, &lsp);
    defer server.deinit();

    std.debug.print("Starting LSP-MCP bridge server for '{s}'...\n", .{server_name});
    try server.run();
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\LSP-MCP Bridge Server
        \\
        \\Usage: lsp-mcp-server [OPTIONS]
        \\
        \\Options:
        \\  --server NAME     Language server to use (default: zls)
        \\                    Available: zls, rust-analyzer, gopls, typescript-language-server, pylsp
        \\  --config PATH     Additional configuration file
        \\  -h, --help        Show this help message
        \\
        \\Examples:
        \\  lsp-mcp-server                           # Use ZLS (default)
        \\  lsp-mcp-server --server rust-analyzer   # Use Rust Analyzer
        \\  lsp-mcp-server --server gopls           # Use Go language server
        \\  lsp-mcp-server --config custom.json     # Use custom config
        \\
    , .{});
}

fn findServerCommand(allocator: std.mem.Allocator, command: []const u8) !?[]const u8 {
    var child = std.process.Child.init(&.{ "which", command }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Close;
    
    try child.spawn();
    
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);
    
    const term = try child.wait();
    
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                return try allocator.dupe(u8, std.mem.trim(u8, stdout, "\n\r"));
            }
        },
        else => {},
    }
    
    return null;
}

test "basic test" {
    try std.testing.expect(true);
}