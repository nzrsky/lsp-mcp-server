#!/bin/bash

# Test script for LSP-MCP server
# Usage: ./test_mcp.sh [server_name]

SERVER=${1:-zls}
BINARY="./zig-out/bin/lsp-mcp-server"

# Make sure binary is built
if [ ! -f "$BINARY" ]; then
    echo "Building LSP-MCP server..."
    zig build
fi

# Add zls to PATH if needed
export PATH="/Users/nazaroff/bin:$PATH"

echo "Testing LSP-MCP server with $SERVER..."
echo

# Function to send MCP request
send_mcp_request() {
    local json="$1"
    local length=${#json}
    (echo "Content-Length: $length" && echo && echo "$json") | timeout 10s "$BINARY" --server "$SERVER" 2>/dev/null
}

echo "=== 1. Initialize MCP Server ==="
INIT_JSON='{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"0.1.0","capabilities":{"tools":{}},"clientInfo":{"name":"test-client","version":"1.0"}}}'
send_mcp_request "$INIT_JSON" | jq

echo
echo "=== 2. List Available Tools ==="
LIST_JSON='{"jsonrpc":"2.0","method":"tools/list","id":2}'
send_mcp_request "$LIST_JSON" | jq

echo
echo "=== 3. Get Tool Schema ==="
SCHEMA_JSON='{"jsonrpc":"2.0","method":"tools/call","id":3,"params":{"name":"hover","arguments":{"uri":"file:///tmp/test.zig","position":{"line":0,"character":0}}}}'
send_mcp_request "$SCHEMA_JSON" | jq

echo
echo "Test completed!"