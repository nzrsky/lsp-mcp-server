const std = @import("std");
const mcp = @import("mcp.zig");
const zls_client = @import("zls_client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ZLS client
    var zls = try zls_client.ZlsClient.init(allocator, "/Users/nazaroff/bin/zls");
    defer zls.deinit();

    // Start ZLS
    try zls.start();
    defer zls.stop();

    // Initialize and start MCP server
    var server = mcp.Server.init(allocator, &zls);
    defer server.deinit();

    try server.run();
}

test "basic test" {
    try std.testing.expect(true);
}