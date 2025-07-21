const std = @import("std");
const json = std.json;
const config = @import("config");

// Generic LSP protocol types
pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

pub const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

pub const MarkupContent = struct {
    kind: []const u8, // "plaintext" or "markdown"
    value: []const u8,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: ?u32 = null,
    detail: ?[]const u8 = null,
    documentation: ?MarkupContent = null,
    insertText: ?[]const u8 = null,
};

pub const CompletionList = struct {
    isIncomplete: bool,
    items: []CompletionItem,
};

pub const Diagnostic = struct {
    range: Range,
    severity: ?u32 = null,
    code: ?json.Value = null,
    source: ?[]const u8 = null,
    message: []const u8,
    relatedInformation: ?[]DiagnosticRelatedInformation = null,
};

pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: []const u8,
};

pub const CodeAction = struct {
    title: []const u8,
    kind: ?[]const u8 = null,
    diagnostics: ?[]Diagnostic = null,
    isPreferred: ?bool = null,
    edit: ?WorkspaceEdit = null,
    command: ?Command = null,
};

pub const Command = struct {
    title: []const u8,
    command: []const u8,
    arguments: ?[]json.Value = null,
};

pub const WorkspaceEdit = struct {
    changes: ?std.StringHashMap([]TextEdit) = null,
    documentChanges: ?[]DocumentChange = null,
};

pub const TextEdit = struct {
    range: Range,
    newText: []const u8,
};

pub const DocumentChange = union(enum) {
    textDocumentEdit: struct {
        textDocument: VersionedTextDocumentIdentifier,
        edits: []TextEdit,
    },
    createFile: struct {
        uri: []const u8,
        options: ?CreateFileOptions = null,
    },
    renameFile: struct {
        oldUri: []const u8,
        newUri: []const u8,
        options: ?RenameFileOptions = null,
    },
    deleteFile: struct {
        uri: []const u8,
        options: ?DeleteFileOptions = null,
    },
};

pub const VersionedTextDocumentIdentifier = struct {
    uri: []const u8,
    version: ?i32,
};

pub const CreateFileOptions = struct {
    overwrite: ?bool = null,
    ignoreIfExists: ?bool = null,
};

pub const RenameFileOptions = struct {
    overwrite: ?bool = null,
    ignoreIfExists: ?bool = null,
};

pub const DeleteFileOptions = struct {
    recursive: ?bool = null,
    ignoreIfNotExists: ?bool = null,
};

pub const DocumentSymbol = struct {
    name: []const u8,
    detail: ?[]const u8 = null,
    kind: u32,
    deprecated: ?bool = null,
    range: Range,
    selectionRange: Range,
    children: ?[]DocumentSymbol = null,
};

pub const SymbolInformation = struct {
    name: []const u8,
    kind: u32,
    deprecated: ?bool = null,
    location: Location,
    containerName: ?[]const u8 = null,
};

// LSP method names
pub const LSP_METHODS = struct {
    pub const INITIALIZE = "initialize";
    pub const INITIALIZED = "initialized";
    pub const SHUTDOWN = "shutdown";
    pub const EXIT = "exit";
    pub const TEXT_DOCUMENT_HOVER = "textDocument/hover";
    pub const TEXT_DOCUMENT_DEFINITION = "textDocument/definition";
    pub const TEXT_DOCUMENT_COMPLETION = "textDocument/completion";
    pub const TEXT_DOCUMENT_CODE_ACTION = "textDocument/codeAction";
    pub const TEXT_DOCUMENT_DOCUMENT_SYMBOL = "textDocument/documentSymbol";
    pub const TEXT_DOCUMENT_FORMATTING = "textDocument/formatting";
    pub const TEXT_DOCUMENT_RANGE_FORMATTING = "textDocument/rangeFormatting";
    pub const TEXT_DOCUMENT_REFERENCES = "textDocument/references";
    pub const TEXT_DOCUMENT_RENAME = "textDocument/rename";
    pub const TEXT_DOCUMENT_DID_OPEN = "textDocument/didOpen";
    pub const TEXT_DOCUMENT_DID_CHANGE = "textDocument/didChange";
    pub const TEXT_DOCUMENT_DID_SAVE = "textDocument/didSave";
    pub const TEXT_DOCUMENT_DID_CLOSE = "textDocument/didClose";
    pub const WORKSPACE_SYMBOL = "workspace/symbol";
    pub const WORKSPACE_EXECUTE_COMMAND = "workspace/executeCommand";
};

// Generic LSP client interface
pub const LspClient = struct {
    allocator: std.mem.Allocator,
    config: config.LspServerConfig,
    process: ?std.process.Child = null,
    stdin: ?std.fs.File.Writer = null,
    stdout: ?std.fs.File.Reader = null,
    next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    responses: std.StringHashMap([]u8),
    response_mutex: std.Thread.Mutex = .{},
    reader_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, server_config: config.LspServerConfig) !LspClient {
        return .{
            .allocator = allocator,
            .config = server_config,
            .responses = std.StringHashMap([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *LspClient) void {
        self.stop();
        
        // Clear all stored responses
        var iterator = self.responses.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.responses.deinit();
    }

    pub fn start(self: *LspClient) !void {
        // Build command with arguments
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();
        
        try argv.append(self.config.command);
        for (self.config.args) |arg| {
            try argv.append(arg);
        }

        var process = std.process.Child.init(argv.items, self.allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Ignore;

        // Set working directory if specified
        if (self.config.working_directory) |wd| {
            process.cwd = wd;
        }

        try process.spawn();
        self.process = process;
        self.stdin = process.stdin.?.writer();
        self.stdout = process.stdout.?.reader();

        // Start reader thread
        self.reader_thread = try std.Thread.spawn(.{}, readerThreadFn, .{self});

        // Initialize LSP server
        try self.initialize();
    }

    pub fn stop(self: *LspClient) void {
        self.should_stop.store(true, .monotonic);
        
        if (self.reader_thread) |thread| {
            thread.join();
            self.reader_thread = null;
        }

        if (self.process) |*proc| {
            _ = proc.kill() catch {};
            _ = proc.wait() catch {};
            self.process = null;
        }
    }

    fn readerThreadFn(self: *LspClient) void {
        var buf: [65536]u8 = undefined;
        
        while (!self.should_stop.load(.monotonic)) {
            // Read Content-Length header
            const header = self.stdout.?.readUntilDelimiterOrEof(&buf, '\n') catch break orelse break;
            if (!std.mem.startsWith(u8, header, "Content-Length: ")) continue;
            
            const len_str = header["Content-Length: ".len..];
            const content_length = std.fmt.parseInt(usize, std.mem.trim(u8, len_str, "\r"), 10) catch continue;
            
            // Skip empty line
            _ = self.stdout.?.readUntilDelimiterOrEof(&buf, '\n') catch break;
            
            // Read JSON content
            if (content_length > buf.len) continue;
            self.stdout.?.readNoEof(buf[0..content_length]) catch break;
            
            // Parse response and store it
            self.handleResponse(buf[0..content_length]) catch {};
        }
    }

    fn handleResponse(self: *LspClient, data: []const u8) !void {
        const parsed = try json.parseFromSlice(struct {
            id: ?json.Value = null,
            result: ?json.Value = null,
            @"error": ?json.Value = null,
            method: ?[]const u8 = null,
        }, self.allocator, data, .{});
        defer parsed.deinit();

        if (parsed.value.id) |id| {
            var id_buf: [32]u8 = undefined;
            const id_str = try std.fmt.bufPrint(&id_buf, "{}", .{id});
            
            const data_copy = try self.allocator.dupe(u8, data);
            
            self.response_mutex.lock();
            defer self.response_mutex.unlock();
            
            try self.responses.put(try self.allocator.dupe(u8, id_str), data_copy);
        }
    }

    fn sendRequest(self: *LspClient, method: []const u8, params: anytype) !u32 {
        const id = self.next_id.fetchAdd(1, .monotonic);
        
        const request = .{
            .jsonrpc = "2.0",
            .id = id,
            .method = method,
            .params = params,
        };

        var string = std.ArrayList(u8).init(self.allocator);
        defer string.deinit();
        
        try json.stringify(request, .{}, string.writer());
        
        try self.stdin.?.print("Content-Length: {d}\r\n\r\n", .{string.items.len});
        try self.stdin.?.writeAll(string.items);
        
        return id;
    }

    fn sendNotification(self: *LspClient, method: []const u8, params: anytype) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = method,
            .params = params,
        };

        var string = std.ArrayList(u8).init(self.allocator);
        defer string.deinit();
        
        try json.stringify(notification, .{}, string.writer());
        
        try self.stdin.?.print("Content-Length: {d}\r\n\r\n", .{string.items.len});
        try self.stdin.?.writeAll(string.items);
    }

    fn waitForResponse(self: *LspClient, id: u32, timeout_ms: u64) ![]u8 {
        var id_buf: [32]u8 = undefined;
        const id_str = try std.fmt.bufPrint(&id_buf, "{}", .{id});
        
        const start_time = std.time.milliTimestamp();
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            self.response_mutex.lock();
            if (self.responses.get(id_str)) |response| {
                _ = self.responses.remove(id_str);
                self.response_mutex.unlock();
                return response;
            }
            self.response_mutex.unlock();
            
            std.time.sleep(10 * std.time.ns_per_ms);
        }
        
        return error.Timeout;
    }

    fn initialize(self: *LspClient) !void {
        std.debug.print("LSP Client: Initializing LSP server...\n", .{});
        const init_options = if (self.config.initialization_options) |opts| opts else json.Value{ .null = {} };
        
        const params = .{
            .processId = null,
            .rootUri = self.config.root_uri,
            .initializationOptions = init_options,
            .capabilities = self.config.client_capabilities,
            .trace = "off",
            .workspaceFolders = null,
        };

        const id = try self.sendRequest(LSP_METHODS.INITIALIZE, params);
        std.debug.print("LSP Client: Sent initialize request, waiting for response...\n", .{});
        const response = self.waitForResponse(id, 3000) catch |err| {
            std.debug.print("LSP Client: Initialize failed after 3s: {}\n", .{err});
            return err;
        };
        defer self.allocator.free(response);
        std.debug.print("LSP Client: Initialize successful!\n", .{});

        // Send initialized notification
        try self.sendNotification(LSP_METHODS.INITIALIZED, .{});
    }

    // Generic LSP method implementations
    pub fn hover(self: *LspClient, uri: []const u8, line: u32, character: u32) !?Hover {
        const params = TextDocumentPositionParams{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        };

        const id = try self.sendRequest(LSP_METHODS.TEXT_DOCUMENT_HOVER, params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?Hover = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        return parsed.value.result;
    }

    pub fn definition(self: *LspClient, uri: []const u8, line: u32, character: u32) !?[]const Location {
        const params = TextDocumentPositionParams{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        };

        const id = try self.sendRequest(LSP_METHODS.TEXT_DOCUMENT_DEFINITION, params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?[]Location = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        return parsed.value.result;
    }

    pub fn completion(self: *LspClient, uri: []const u8, line: u32, character: u32) !?CompletionList {
        const params = TextDocumentPositionParams{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        };

        const id = try self.sendRequest(LSP_METHODS.TEXT_DOCUMENT_COMPLETION, params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?union(enum) {
                list: CompletionList,
                items: []CompletionItem,
            } = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        if (parsed.value.result) |result| {
            return switch (result) {
                .list => |list| list,
                .items => |items| CompletionList{
                    .isIncomplete = false,
                    .items = items,
                },
            };
        }
        return null;
    }

    pub fn codeAction(self: *LspClient, uri: []const u8, range: Range, context: struct {
        diagnostics: []Diagnostic,
        only: ?[][]const u8 = null,
    }) !?[]CodeAction {
        const params = .{
            .textDocument = TextDocumentIdentifier{ .uri = uri },
            .range = range,
            .context = context,
        };

        const id = try self.sendRequest(LSP_METHODS.TEXT_DOCUMENT_CODE_ACTION, params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?[]CodeAction = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        return parsed.value.result;
    }

    pub fn documentSymbol(self: *LspClient, uri: []const u8) !?union(enum) {
        document_symbols: []DocumentSymbol,
        symbol_information: []SymbolInformation,
    } {
        const params = .{
            .textDocument = TextDocumentIdentifier{ .uri = uri },
        };

        const id = try self.sendRequest(LSP_METHODS.TEXT_DOCUMENT_DOCUMENT_SYMBOL, params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        // Try to parse as DocumentSymbol first, then SymbolInformation
        if (json.parseFromSlice(struct {
            result: ?[]DocumentSymbol = null,
        }, self.allocator, response, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value.result) |result| {
                return .{ .document_symbols = result };
            }
        } else |_| {}

        const parsed = try json.parseFromSlice(struct {
            result: ?[]SymbolInformation = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        if (parsed.value.result) |result| {
            return .{ .symbol_information = result };
        }

        return null;
    }

    // Document lifecycle management
    pub fn didOpen(self: *LspClient, uri: []const u8, language_id: []const u8, version: i32, text: []const u8) !void {
        const params = .{
            .textDocument = .{
                .uri = uri,
                .languageId = language_id,
                .version = version,
                .text = text,
            },
        };

        try self.sendNotification(LSP_METHODS.TEXT_DOCUMENT_DID_OPEN, params);
    }

    pub fn didChange(self: *LspClient, uri: []const u8, version: i32, changes: []const struct {
        range: ?Range = null,
        rangeLength: ?u32 = null,
        text: []const u8,
    }) !void {
        const params = .{
            .textDocument = .{
                .uri = uri,
                .version = version,
            },
            .contentChanges = changes,
        };

        try self.sendNotification(LSP_METHODS.TEXT_DOCUMENT_DID_CHANGE, params);
    }

    pub fn didSave(self: *LspClient, uri: []const u8, text: ?[]const u8) !void {
        const params = .{
            .textDocument = TextDocumentIdentifier{ .uri = uri },
            .text = text,
        };

        try self.sendNotification(LSP_METHODS.TEXT_DOCUMENT_DID_SAVE, params);
    }

    pub fn didClose(self: *LspClient, uri: []const u8) !void {
        const params = .{
            .textDocument = TextDocumentIdentifier{ .uri = uri },
        };

        try self.sendNotification(LSP_METHODS.TEXT_DOCUMENT_DID_CLOSE, params);
    }
};