const std = @import("std");
const json = std.json;

// LSP types
const Position = struct {
    line: u32,
    character: u32,
};

const Range = struct {
    start: Position,
    end: Position,
};

const Location = struct {
    uri: []const u8,
    range: Range,
};

const TextDocumentIdentifier = struct {
    uri: []const u8,
};

const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

const MarkupContent = struct {
    kind: []const u8, // "plaintext" or "markdown"
    value: []const u8,
};

const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

const CompletionItem = struct {
    label: []const u8,
    kind: ?u32 = null,
    detail: ?[]const u8 = null,
    documentation: ?MarkupContent = null,
    insertText: ?[]const u8 = null,
};

pub const ZlsClient = struct {
    allocator: std.mem.Allocator,
    zls_path: []const u8,
    process: ?std.process.Child = null,
    stdin: ?std.fs.File.Writer = null,
    stdout: ?std.fs.File.Reader = null,
    next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    responses: std.StringHashMap([]u8),
    response_mutex: std.Thread.Mutex = .{},
    reader_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, zls_path: []const u8) !ZlsClient {
        return .{
            .allocator = allocator,
            .zls_path = zls_path,
            .responses = std.StringHashMap([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *ZlsClient) void {
        self.stop();
        self.responses.deinit();
    }

    pub fn start(self: *ZlsClient) !void {
        var process = std.process.Child.init(&.{self.zls_path}, self.allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Ignore;

        try process.spawn();
        self.process = process;
        self.stdin = process.stdin.?.writer();
        self.stdout = process.stdout.?.reader();

        // Start reader thread
        self.reader_thread = try std.Thread.spawn(.{}, readerThreadFn, .{self});

        // Initialize ZLS
        try self.initialize();
    }

    pub fn stop(self: *ZlsClient) void {
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

    fn readerThreadFn(self: *ZlsClient) void {
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

    fn handleResponse(self: *ZlsClient, data: []const u8) !void {
        const parsed = try json.parseFromSlice(struct {
            id: ?json.Value = null,
            result: ?json.Value = null,
            @"error": ?json.Value = null,
        }, self.allocator, data, .{});
        defer parsed.deinit();

        if (parsed.value.id) |id| {
            var id_buf: [32]u8 = undefined;
            const id_str = try std.fmt.bufPrint(&id_buf, "{}", .{id});

            const data_copy = try self.allocator.dupe(u8, data);

            self.response_mutex.lock();
            defer self.response_mutex.unlock();

            try self.responses.put(id_str, data_copy);
        }
    }

    fn sendRequest(self: *ZlsClient, method: []const u8, params: anytype) !u32 {
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

    fn waitForResponse(self: *ZlsClient, id: u32, timeout_ms: u64) ![]u8 {
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

    fn initialize(self: *ZlsClient) !void {
        const params = .{
            .processId = null,
            .capabilities = .{
                .textDocument = .{
                    .hover = .{
                        .contentFormat = .{ "markdown", "plaintext" },
                    },
                    .completion = .{
                        .completionItem = .{
                            .documentationFormat = .{ "markdown", "plaintext" },
                        },
                    },
                },
            },
            .trace = "off",
            .workspaceFolders = null,
        };

        const id = try self.sendRequest("initialize", params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        // Send initialized notification
        _ = try self.sendRequest("initialized", .{});
    }

    pub fn hover(self: *ZlsClient, uri: []const u8, line: u32, character: u32) !?Hover {
        const params = TextDocumentPositionParams{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        };

        const id = try self.sendRequest("textDocument/hover", params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?Hover = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        return parsed.value.result;
    }

    pub fn definition(self: *ZlsClient, uri: []const u8, line: u32, character: u32) !?[]const Location {
        const params = TextDocumentPositionParams{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        };

        const id = try self.sendRequest("textDocument/definition", params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?[]Location = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        return parsed.value.result;
    }

    pub fn completions(self: *ZlsClient, uri: []const u8, line: u32, character: u32) !?[]const CompletionItem {
        const params = TextDocumentPositionParams{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        };

        const id = try self.sendRequest("textDocument/completion", params);
        const response = try self.waitForResponse(id, 5000);
        defer self.allocator.free(response);

        const parsed = try json.parseFromSlice(struct {
            result: ?struct {
                items: []CompletionItem,
            } = null,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        if (parsed.value.result) |result| {
            return result.items;
        }
        return null;
    }
};
