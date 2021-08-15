# ZLS MCP Server

A Model Context Protocol (MCP) server that provides LLMs with access to Zig Language Server (ZLS) capabilities.

## Features

This MCP server exposes three main tools:

1. **hover** - Get hover information at a specific position in a Zig file
2. **definition** - Go to definition of symbol at a specific position  
3. **completions** - Get code completions at a specific position

## Building

```bash
zig build
```

## Running

The server communicates via stdin/stdout using the MCP protocol:

```bash
./zig-out/bin/zls-mcp-server
```

## Tools

### hover
Get hover information for a symbol at a specific position.

Parameters:
- `uri` (string): File URI (e.g., `file:///path/to/file.zig`)
- `line` (integer): Line number (0-indexed)  
- `character` (integer): Character position in the line (0-indexed)

### definition  
Go to the definition of a symbol at a specific position.

Parameters: Same as hover

### completions
Get code completions at a specific position.

Parameters: Same as hover

## Requirements

- ZLS must be available in your PATH at `/Users/nazaroff/bin/zls`
- Zig files must be accessible to both the MCP server and ZLS

## Architecture

The server consists of:
- `main.zig` - Entry point
- `mcp.zig` - MCP protocol implementation with JSON-RPC handling
- `zls_client.zig` - LSP client that communicates with ZLS over stdio

The server starts ZLS as a subprocess and proxies requests from MCP clients to ZLS, translating between the two protocols.