#!/usr/bin/env python3
"""
Simple test script for the ZLS MCP server
"""
import json
import subprocess
import sys

def send_request(proc, method, params=None, request_id=1):
    """Send a JSON-RPC request to the MCP server"""
    request = {
        "jsonrpc": "2.0",
        "method": method,
        "id": request_id
    }
    if params:
        request["params"] = params
    
    request_str = json.dumps(request)
    content_length = len(request_str.encode('utf-8'))
    
    message = f"Content-Length: {content_length}\r\n\r\n{request_str}"
    
    print(f"→ {message.strip()}")
    proc.stdin.write(message.encode('utf-8'))
    proc.stdin.flush()

def read_response(proc):
    """Read a response from the MCP server"""
    # Read Content-Length header
    while True:
        line = proc.stdout.readline().decode('utf-8').strip()
        if line.startswith("Content-Length:"):
            content_length = int(line.split(":")[1].strip())
            break
        if not line:
            return None
    
    # Read empty line
    proc.stdout.readline()
    
    # Read JSON content
    response_data = proc.stdout.read(content_length).decode('utf-8')
    print(f"← Content-Length: {content_length}")
    print(f"← {response_data}")
    
    return json.loads(response_data)

def main():
    """Test the MCP server"""
    print("Starting ZLS MCP Server test...")
    
    # Start the server
    proc = subprocess.Popen(
        ['./zig-out/bin/zls-mcp-server'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    try:
        # Test initialize
        print("\n=== Testing initialize ===")
        send_request(proc, "initialize", {
            "protocolVersion": "0.1.0",
            "capabilities": {"tools": {}},
            "clientInfo": {"name": "test-client", "version": "1.0"}
        })
        response = read_response(proc)
        print(f"Initialize response: {response}")
        
        # Test tools/list
        print("\n=== Testing tools/list ===")
        send_request(proc, "tools/list", request_id=2)
        response = read_response(proc)
        print(f"Tools list response: {response}")
        
        # Test hover tool call
        print("\n=== Testing hover tool ===")
        send_request(proc, "tools/call", {
            "name": "hover",
            "arguments": {
                "uri": "file:///Users/nazaroff/tools/zls/src/main.zig",
                "line": 10,
                "character": 5
            }
        }, request_id=3)
        response = read_response(proc)
        print(f"Hover response: {response}")
        
    except Exception as e:
        print(f"Error: {e}")
        
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

if __name__ == "__main__":
    main()