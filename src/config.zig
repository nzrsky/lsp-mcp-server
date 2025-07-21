const std = @import("std");
const json = std.json;

pub const LspServerConfig = struct {
    name: []const u8,
    command: []const u8,
    args: []const []const u8,
    file_extensions: []const []const u8,
    language_id: []const u8,
    root_uri: ?[]const u8 = null,
    working_directory: ?[]const u8 = null,
    initialization_options: ?json.Value = null,
    client_capabilities: ClientCapabilities,

    pub const ClientCapabilities = struct {
        textDocument: ?TextDocumentCapabilities = null,
        workspace: ?WorkspaceCapabilities = null,

        pub const TextDocumentCapabilities = struct {
            hover: ?struct {
                contentFormat: []const []const u8,
            } = null,
            completion: ?struct {
                completionItem: ?struct {
                    documentationFormat: []const []const u8,
                } = null,
            } = null,
            definition: ?struct {
                linkSupport: bool = false,
            } = null,
            codeAction: ?struct {
                codeActionLiteralSupport: ?struct {
                    codeActionKind: struct {
                        valueSet: []const []const u8,
                    },
                } = null,
            } = null,
            documentSymbol: ?struct {
                hierarchicalDocumentSymbolSupport: bool = true,
            } = null,
            formatting: ?struct {} = null,
            rangeFormatting: ?struct {} = null,
            references: ?struct {} = null,
            rename: ?struct {
                prepareSupport: bool = false,
            } = null,
        };

        pub const WorkspaceCapabilities = struct {
            workspaceEdit: ?struct {
                documentChanges: bool = true,
                resourceOperations: []const []const u8 = &.{ "create", "rename", "delete" },
            } = null,
            symbol: ?struct {} = null,
            executeCommand: ?struct {} = null,
        };
    };
};

// Predefined configurations for popular language servers
pub const LANGUAGE_SERVERS = struct {
    pub const ZLS = LspServerConfig{
        .name = "zls",
        .command = "zls",
        .args = &.{},
        .file_extensions = &.{ ".zig", ".zir" },
        .language_id = "zig",
        .client_capabilities = .{
            .textDocument = .{
                .hover = .{
                    .contentFormat = &.{ "markdown", "plaintext" },
                },
                .completion = .{
                    .completionItem = .{
                        .documentationFormat = &.{ "markdown", "plaintext" },
                    },
                },
                .definition = .{
                    .linkSupport = true,
                },
                .codeAction = .{
                    .codeActionLiteralSupport = .{
                        .codeActionKind = .{
                            .valueSet = &.{ "quickfix", "refactor", "source" },
                        },
                    },
                },
                .documentSymbol = .{
                    .hierarchicalDocumentSymbolSupport = true,
                },
                .formatting = .{},
                .references = .{},
            },
            .workspace = .{
                .workspaceEdit = .{
                    .documentChanges = true,
                    .resourceOperations = &.{ "create", "rename", "delete" },
                },
            },
        },
    };

    pub const RUST_ANALYZER = LspServerConfig{
        .name = "rust-analyzer",
        .command = "rust-analyzer",
        .args = &.{},
        .file_extensions = &.{ ".rs", ".toml" },
        .language_id = "rust",
        .initialization_options = null,
        .client_capabilities = .{
            .textDocument = .{
                .hover = .{
                    .contentFormat = &.{ "markdown", "plaintext" },
                },
                .completion = .{
                    .completionItem = .{
                        .documentationFormat = &.{ "markdown", "plaintext" },
                    },
                },
                .definition = .{
                    .linkSupport = true,
                },
                .codeAction = .{
                    .codeActionLiteralSupport = .{
                        .codeActionKind = .{
                            .valueSet = &.{ "quickfix", "refactor", "refactor.extract", "refactor.inline", "refactor.rewrite", "source", "source.organizeImports" },
                        },
                    },
                },
                .documentSymbol = .{
                    .hierarchicalDocumentSymbolSupport = true,
                },
                .formatting = .{},
                .rangeFormatting = .{},
                .references = .{},
                .rename = .{
                    .prepareSupport = true,
                },
            },
            .workspace = .{
                .workspaceEdit = .{
                    .documentChanges = true,
                    .resourceOperations = &.{ "create", "rename", "delete" },
                },
                .symbol = .{},
                .executeCommand = .{},
            },
        },
    };

    pub const GOPLS = LspServerConfig{
        .name = "gopls",
        .command = "gopls",
        .args = &.{},
        .file_extensions = &.{ ".go", ".mod", ".sum", ".work" },
        .language_id = "go",
        .initialization_options = null,
        .client_capabilities = .{
            .textDocument = .{
                .hover = .{
                    .contentFormat = &.{ "markdown", "plaintext" },
                },
                .completion = .{
                    .completionItem = .{
                        .documentationFormat = &.{ "markdown", "plaintext" },
                    },
                },
                .definition = .{
                    .linkSupport = true,
                },
                .codeAction = .{
                    .codeActionLiteralSupport = .{
                        .codeActionKind = .{
                            .valueSet = &.{ "quickfix", "refactor", "source", "source.organizeImports" },
                        },
                    },
                },
                .documentSymbol = .{
                    .hierarchicalDocumentSymbolSupport = true,
                },
                .formatting = .{},
                .rangeFormatting = .{},
                .references = .{},
                .rename = .{
                    .prepareSupport = true,
                },
            },
            .workspace = .{
                .workspaceEdit = .{
                    .documentChanges = true,
                    .resourceOperations = &.{ "create", "rename", "delete" },
                },
                .symbol = .{},
                .executeCommand = .{},
            },
        },
    };

    pub const TYPESCRIPT_LANGUAGE_SERVER = LspServerConfig{
        .name = "typescript-language-server",
        .command = "typescript-language-server",
        .args = &.{"--stdio"},
        .file_extensions = &.{ ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs" },
        .language_id = "typescript",
        .initialization_options = null,
        .client_capabilities = .{
            .textDocument = .{
                .hover = .{
                    .contentFormat = &.{ "markdown", "plaintext" },
                },
                .completion = .{
                    .completionItem = .{
                        .documentationFormat = &.{ "markdown", "plaintext" },
                    },
                },
                .definition = .{
                    .linkSupport = true,
                },
                .codeAction = .{
                    .codeActionLiteralSupport = .{
                        .codeActionKind = .{
                            .valueSet = &.{ "quickfix", "refactor", "source", "source.organizeImports", "source.fixAll" },
                        },
                    },
                },
                .documentSymbol = .{
                    .hierarchicalDocumentSymbolSupport = true,
                },
                .formatting = .{},
                .rangeFormatting = .{},
                .references = .{},
                .rename = .{
                    .prepareSupport = true,
                },
            },
            .workspace = .{
                .workspaceEdit = .{
                    .documentChanges = true,
                    .resourceOperations = &.{ "create", "rename", "delete" },
                },
                .symbol = .{},
                .executeCommand = .{},
            },
        },
    };

    pub const PYTHON_LSP_SERVER = LspServerConfig{
        .name = "pylsp",
        .command = "pylsp",
        .args = &.{},
        .file_extensions = &.{ ".py", ".pyi", ".pyx" },
        .language_id = "python",
        .initialization_options = null,
        .client_capabilities = .{
            .textDocument = .{
                .hover = .{
                    .contentFormat = &.{ "markdown", "plaintext" },
                },
                .completion = .{
                    .completionItem = .{
                        .documentationFormat = &.{ "markdown", "plaintext" },
                    },
                },
                .definition = .{
                    .linkSupport = true,
                },
                .codeAction = .{
                    .codeActionLiteralSupport = .{
                        .codeActionKind = .{
                            .valueSet = &.{ "quickfix", "refactor", "source", "source.organizeImports" },
                        },
                    },
                },
                .documentSymbol = .{
                    .hierarchicalDocumentSymbolSupport = true,
                },
                .formatting = .{},
                .rangeFormatting = .{},
                .references = .{},
                .rename = .{
                    .prepareSupport = true,
                },
            },
            .workspace = .{
                .workspaceEdit = .{
                    .documentChanges = true,
                    .resourceOperations = &.{ "create", "rename", "delete" },
                },
                .symbol = .{},
                .executeCommand = .{},
            },
        },
    };
};

pub const ServerConfigs = struct {
    configs: std.StringHashMap(LspServerConfig),

    pub fn init(allocator: std.mem.Allocator) ServerConfigs {
        const configs = std.StringHashMap(LspServerConfig).init(allocator);
        return .{ .configs = configs };
    }

    pub fn deinit(self: *ServerConfigs) void {
        self.configs.deinit();
    }

    pub fn registerDefaults(self: *ServerConfigs) !void {
        try self.configs.put("zls", LANGUAGE_SERVERS.ZLS);
        try self.configs.put("rust-analyzer", LANGUAGE_SERVERS.RUST_ANALYZER);
        try self.configs.put("gopls", LANGUAGE_SERVERS.GOPLS);
        try self.configs.put("typescript-language-server", LANGUAGE_SERVERS.TYPESCRIPT_LANGUAGE_SERVER);
        try self.configs.put("pylsp", LANGUAGE_SERVERS.PYTHON_LSP_SERVER);
    }

    pub fn get(self: *ServerConfigs, name: []const u8) ?LspServerConfig {
        return self.configs.get(name);
    }

    pub fn getByFileExtension(self: *ServerConfigs, extension: []const u8) ?LspServerConfig {
        var iterator = self.configs.valueIterator();
        while (iterator.next()) |config| {
            for (config.file_extensions) |ext| {
                if (std.mem.eql(u8, ext, extension)) {
                    return config.*;
                }
            }
        }
        return null;
    }

    pub fn loadFromFile(self: *ServerConfigs, allocator: std.mem.Allocator, path: []const u8) !void {
        // TODO: Implement config file loading when JSON parsing is fixed
        _ = self;
        _ = allocator;
        _ = path;
        std.debug.print("Config file loading not implemented yet\n", .{});
    }
};