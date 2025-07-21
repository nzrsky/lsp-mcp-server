const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create modules that can be shared
    const config_module = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
    });
    const lsp_client_module = b.createModule(.{
        .root_source_file = b.path("src/lsp_client.zig"),
    });
    lsp_client_module.addImport("config", config_module);
    
    const mcp_module = b.createModule(.{
        .root_source_file = b.path("src/mcp.zig"),
    });
    mcp_module.addImport("lsp_client", lsp_client_module);

    const exe = b.addExecutable(.{
        .name = "lsp-mcp-server",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("config", config_module);
    exe.root_module.addImport("lsp_client", lsp_client_module);
    exe.root_module.addImport("mcp", mcp_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the MCP server");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // BDD integration tests
    const bdd_tests = b.addExecutable(.{
        .name = "bdd-tests",
        .root_source_file = b.path("tests/test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    bdd_tests.root_module.addImport("config", config_module);
    bdd_tests.root_module.addImport("lsp_client", lsp_client_module);
    
    b.installArtifact(bdd_tests);
    
    const bdd_run_cmd = b.addRunArtifact(bdd_tests);
    bdd_run_cmd.step.dependOn(b.getInstallStep());
    
    const bdd_test_step = b.step("test-bdd", "Run BDD integration tests");
    bdd_test_step.dependOn(&bdd_run_cmd.step);
}