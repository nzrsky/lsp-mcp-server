const std = @import("std");
const lsp_client = @import("lsp_client");
const config = @import("config");

const json = std.json;

// MCP protocol types
const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?json.Value = null,
    id: json.Value,
};

const JsonRpcResponse = struct {
    jsonrpc: []const u8 = "2.0",
    result: ?json.Value = null,
    @"error": ?JsonRpcError = null,
    id: json.Value,
};

const JsonRpcError = struct {
    code: i32,
    message: []const u8,
    data: ?json.Value = null,
};

const InitializeParams = struct {
    protocolVersion: []const u8,
    capabilities: struct {
        tools: ?struct {} = null,
    },
    clientInfo: struct {
        name: []const u8,
        version: ?[]const u8 = null,
    },
};

const Tool = struct {
    name: []const u8,
    description: []const u8,
    inputSchema: json.Value,
};

const ServerCapabilities = struct {
    protocolVersion: []const u8 = "0.1.0",
    capabilities: struct {
        tools: struct {
            listChanged: ?bool = null,
        },
    },
    serverInfo: struct {
        name: []const u8 = "zls-mcp-server",
        version: []const u8 = "0.1.0",
    },
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    lsp: ?*lsp_client.LspClient,
    server_config: config.LspServerConfig,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    initialized: bool = false,
    stdio_mode: bool = false,
    once_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, lsp: ?*lsp_client.LspClient, server_config: config.LspServerConfig) Server {
        return .{
            .allocator = allocator,
            .lsp = lsp,
            .server_config = server_config,
            .stdin = std.io.getStdIn().reader(),
            .stdout = std.io.getStdOut().writer(),
        };
    }

    pub fn deinit(self: *Server) void {
        _ = self;
    }
    
    pub fn setStdioMode(self: *Server, stdio: bool) void {
        self.stdio_mode = stdio;
    }
    
    pub fn setOnceMode(self: *Server, once: bool) void {
        self.once_mode = once;
    }
    
    fn getLanguageName(self: *Server) []const u8 {
        // Map language IDs to human-readable names
        if (std.mem.eql(u8, self.server_config.language_id, "zig")) return "Zig";
        if (std.mem.eql(u8, self.server_config.language_id, "rust")) return "Rust";
        if (std.mem.eql(u8, self.server_config.language_id, "go")) return "Go";
        if (std.mem.eql(u8, self.server_config.language_id, "typescript")) return "TypeScript";
        if (std.mem.eql(u8, self.server_config.language_id, "javascript")) return "JavaScript";
        if (std.mem.eql(u8, self.server_config.language_id, "python")) return "Python";
        if (std.mem.eql(u8, self.server_config.language_id, "cpp")) return "C/C++";
        if (std.mem.eql(u8, self.server_config.language_id, "c")) return "C";
        if (std.mem.eql(u8, self.server_config.language_id, "java")) return "Java";
        
        // Fallback to language_id with first letter capitalized
        return self.server_config.language_id;
    }

    pub fn run(self: *Server) !void {
        var buf: [65536]u8 = undefined;
        
        std.debug.print("MCP server ready, waiting for requests...\n", .{});
        
        if (self.stdio_mode) {
            // Stdio mode - read raw JSON lines
            while (true) {
                const line = try self.stdin.readUntilDelimiterOrEof(&buf, '\n') orelse break;
                if (line.len == 0) continue;
                
                std.debug.print("Received JSON: '{s}'\n", .{line});
                
                // In stdio mode, auto-initialize if needed
                if (!self.initialized) {
                    self.initialized = true;
                }
                
                // Parse and handle request
                try self.handleRequest(line);
                
                // Exit after one request if in once mode
                if (self.once_mode) break;
            }
        } else {
            // LSP-style Content-Length mode
            while (true) {
                // Read Content-Length header
                const header = try self.stdin.readUntilDelimiterOrEof(&buf, '\n') orelse break;
                std.debug.print("Received header: '{s}'\n", .{header});
                if (!std.mem.startsWith(u8, header, "Content-Length: ")) continue;
                
                const len_str = header["Content-Length: ".len..];
                const content_length = try std.fmt.parseInt(usize, std.mem.trim(u8, len_str, "\r"), 10);
                
                // Skip empty line
                _ = try self.stdin.readUntilDelimiterOrEof(&buf, '\n');
                
                // Read JSON content
                if (content_length > buf.len) return error.MessageTooLarge;
                try self.stdin.readNoEof(buf[0..content_length]);
                
                std.debug.print("Received JSON: '{s}'\n", .{buf[0..content_length]});
                
                // Parse and handle request
                try self.handleRequest(buf[0..content_length]);
                
                // Exit after one request if in once mode
                if (self.once_mode) break;
            }
        }
    }

    fn handleRequest(self: *Server, data: []const u8) !void {
        var parsed = try json.parseFromSlice(JsonRpcRequest, self.allocator, data, .{});
        defer parsed.deinit();
        
        const request = parsed.value;
        
        if (std.mem.eql(u8, request.method, "initialize")) {
            try self.handleInitialize(request);
        } else if (std.mem.eql(u8, request.method, "tools/list")) {
            try self.handleToolsList(request);
        } else if (std.mem.eql(u8, request.method, "tools/call")) {
            try self.handleToolsCall(request);
        } else {
            try self.sendError(request.id, -32601, "Method not found");
        }
    }

    fn handleInitialize(self: *Server, request: JsonRpcRequest) !void {
        self.initialized = true;
        
        const result = ServerCapabilities{
            .capabilities = .{
                .tools = .{},
            },
            .serverInfo = .{
                .name = "zls-mcp-server",
                .version = "0.1.0",
            },
        };
        var string = std.ArrayList(u8).init(self.allocator);
        defer string.deinit();
        try json.stringify(result, .{}, string.writer());
        
        const result_value = try json.parseFromSlice(json.Value, self.allocator, string.items, .{});
        defer result_value.deinit();
        
        const response = JsonRpcResponse{
            .id = request.id,
            .result = result_value.value,
        };
        
        try self.sendResponse(response);
    }

    fn handleToolsList(self: *Server, request: JsonRpcRequest) !void {
        if (!self.initialized) {
            try self.sendError(request.id, -32002, "Server not initialized");
            return;
        }

        var tools = std.ArrayList(Tool).init(self.allocator);
        defer tools.deinit();

        // Get language name for descriptions
        const language_name = self.getLanguageName();
        const file_extension = if (self.server_config.file_extensions.len > 0) 
            self.server_config.file_extensions[0] 
        else 
            "source";

        // Hover tool
        var hover_desc = std.ArrayList(u8).init(self.allocator);
        defer hover_desc.deinit();
        try hover_desc.writer().print("Get hover information at a specific position in a {s} file", .{language_name});
        
        try tools.append(.{
            .name = "hover",
            .description = try self.allocator.dupe(u8, hover_desc.items),
            .inputSchema = try self.createHoverSchema(file_extension),
        });

        // Go to definition tool
        var def_desc = std.ArrayList(u8).init(self.allocator);
        defer def_desc.deinit();
        try def_desc.writer().print("Go to definition of symbol at a specific position in {s} code", .{language_name});
        
        try tools.append(.{
            .name = "definition",
            .description = try self.allocator.dupe(u8, def_desc.items),
            .inputSchema = try self.createDefinitionSchema(file_extension),
        });

        // Code completions tool
        var comp_desc = std.ArrayList(u8).init(self.allocator);
        defer comp_desc.deinit();
        try comp_desc.writer().print("Get code completions at a specific position in {s} code", .{language_name});
        
        try tools.append(.{
            .name = "completions",
            .description = try self.allocator.dupe(u8, comp_desc.items),
            .inputSchema = try self.createCompletionsSchema(file_extension),
        });

        var tools_string = std.ArrayList(u8).init(self.allocator);
        defer tools_string.deinit();
        try json.stringify(tools.items, .{}, tools_string.writer());
        
        const tools_value = try json.parseFromSlice(json.Value, self.allocator, tools_string.items, .{});
        defer tools_value.deinit();
        
        const response = JsonRpcResponse{
            .id = request.id,
            .result = tools_value.value,
        };
        
        try self.sendResponse(response);
    }

    fn handleToolsCall(self: *Server, request: JsonRpcRequest) !void {
        if (!self.initialized) {
            try self.sendError(request.id, -32002, "Server not initialized");
            return;
        }

        const params = request.params orelse {
            try self.sendError(request.id, -32602, "Invalid params");
            return;
        };

        const tool_name = params.object.get("name") orelse {
            try self.sendError(request.id, -32602, "Missing tool name");
            return;
        };

        const args = params.object.get("arguments") orelse {
            try self.sendError(request.id, -32602, "Missing arguments");
            return;
        };

        if (std.mem.eql(u8, tool_name.string, "hover")) {
            try self.handleHover(request.id, args);
        } else if (std.mem.eql(u8, tool_name.string, "definition")) {
            try self.handleDefinition(request.id, args);
        } else if (std.mem.eql(u8, tool_name.string, "completions")) {
            try self.handleCompletions(request.id, args);
        } else {
            try self.sendError(request.id, -32602, "Unknown tool");
        }
    }

    fn handleHover(self: *Server, id: json.Value, args: json.Value) !void {
        const uri = args.object.get("uri") orelse {
            try self.sendError(id, -32602, "Missing uri");
            return;
        };
        const line = args.object.get("line") orelse {
            try self.sendError(id, -32602, "Missing line");
            return;
        };
        const character = args.object.get("character") orelse {
            try self.sendError(id, -32602, "Missing character");
            return;
        };

        const result = if (self.lsp) |lsp|
            try lsp.hover(
                uri.string,
                @intCast(line.integer),
                @intCast(character.integer),
            )
        else
            null;

        var result_string = std.ArrayList(u8).init(self.allocator);
        defer result_string.deinit();
        try json.stringify(result, .{}, result_string.writer());
        
        const result_value = try json.parseFromSlice(json.Value, self.allocator, result_string.items, .{});
        defer result_value.deinit();
        
        const response = JsonRpcResponse{
            .id = id,
            .result = result_value.value,
        };
        
        try self.sendResponse(response);
    }

    fn handleDefinition(self: *Server, id: json.Value, args: json.Value) !void {
        const uri = args.object.get("uri") orelse {
            try self.sendError(id, -32602, "Missing uri");
            return;
        };
        const line = args.object.get("line") orelse {
            try self.sendError(id, -32602, "Missing line");
            return;
        };
        const character = args.object.get("character") orelse {
            try self.sendError(id, -32602, "Missing character");
            return;
        };

        const result = if (self.lsp) |lsp|
            try lsp.definition(
                uri.string,
                @intCast(line.integer),
                @intCast(character.integer),
            )
        else
            null;

        var result_string = std.ArrayList(u8).init(self.allocator);
        defer result_string.deinit();
        try json.stringify(result, .{}, result_string.writer());
        
        const result_value = try json.parseFromSlice(json.Value, self.allocator, result_string.items, .{});
        defer result_value.deinit();
        
        const response = JsonRpcResponse{
            .id = id,
            .result = result_value.value,
        };
        
        try self.sendResponse(response);
    }

    fn handleCompletions(self: *Server, id: json.Value, args: json.Value) !void {
        const uri = args.object.get("uri") orelse {
            try self.sendError(id, -32602, "Missing uri");
            return;
        };
        const line = args.object.get("line") orelse {
            try self.sendError(id, -32602, "Missing line");
            return;
        };
        const character = args.object.get("character") orelse {
            try self.sendError(id, -32602, "Missing character");
            return;
        };

        const result = if (self.lsp) |lsp|
            try lsp.completion(
                uri.string,
                @intCast(line.integer),
                @intCast(character.integer),
            )
        else
            null;

        var result_string = std.ArrayList(u8).init(self.allocator);
        defer result_string.deinit();
        try json.stringify(result, .{}, result_string.writer());
        
        const result_value = try json.parseFromSlice(json.Value, self.allocator, result_string.items, .{});
        defer result_value.deinit();
        
        const response = JsonRpcResponse{
            .id = id,
            .result = result_value.value,
        };
        
        try self.sendResponse(response);
    }

    fn createHoverSchema(self: *Server, file_extension: []const u8) !json.Value {
        // Create URI description with the appropriate file extension
        var uri_desc = std.ArrayList(u8).init(self.allocator);
        defer uri_desc.deinit();
        try uri_desc.writer().print("File URI (e.g., file:///path/to/file{s})", .{file_extension});
        
        const schema = .{
            .type = "object",
            .properties = .{
                .uri = .{
                    .type = "string",
                    .description = try self.allocator.dupe(u8, uri_desc.items),
                },
                .line = .{
                    .type = "integer",
                    .description = "Line number (0-indexed)",
                },
                .character = .{
                    .type = "integer",
                    .description = "Character position in the line (0-indexed)",
                },
            },
            .required = .{ "uri", "line", "character" },
        };
        var schema_string = std.ArrayList(u8).init(self.allocator);
        defer schema_string.deinit();
        try json.stringify(schema, .{}, schema_string.writer());
        
        const schema_value = try json.parseFromSlice(json.Value, self.allocator, schema_string.items, .{});
        return schema_value.value;
    }

    fn createDefinitionSchema(self: *Server, file_extension: []const u8) !json.Value {
        return self.createHoverSchema(file_extension); // Same schema
    }

    fn createCompletionsSchema(self: *Server, file_extension: []const u8) !json.Value {
        return self.createHoverSchema(file_extension); // Same schema
    }

    fn sendResponse(self: *Server, response: JsonRpcResponse) !void {
        var string = std.ArrayList(u8).init(self.allocator);
        defer string.deinit();
        
        try json.stringify(response, .{}, string.writer());
        
        if (self.stdio_mode) {
            // Stdio mode - just output JSON
            try self.stdout.writeAll(string.items);
            try self.stdout.writeAll("\n");
        } else {
            // LSP-style Content-Length mode
            try self.stdout.print("Content-Length: {d}\r\n\r\n", .{string.items.len});
            try self.stdout.writeAll(string.items);
        }
    }

    fn sendError(self: *Server, id: json.Value, code: i32, message: []const u8) !void {
        const response = JsonRpcResponse{
            .id = id,
            .@"error" = .{
                .code = code,
                .message = message,
            },
        };
        try self.sendResponse(response);
    }
};