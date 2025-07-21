#!/usr/bin/env python3
"""
Mock LSP Server for Testing
A minimal LSP server that responds to basic requests for testing purposes.
"""

import json
import sys
import threading
import time
from typing import Dict, Any, Optional

class MockLSPServer:
    def __init__(self):
        self.initialized = False
        self.client_capabilities = {}
        self.request_id = 0
        
    def read_message(self) -> Optional[Dict[str, Any]]:
        """Read a JSON-RPC message from stdin"""
        try:
            # Read headers
            headers = {}
            while True:
                line = sys.stdin.buffer.readline().decode('utf-8').strip()
                if not line:
                    break
                if ':' in line:
                    key, value = line.split(':', 1)
                    headers[key.strip().lower()] = value.strip()
            
            # Read content
            content_length = int(headers.get('content-length', 0))
            if content_length == 0:
                return None
                
            content = sys.stdin.buffer.read(content_length).decode('utf-8')
            return json.loads(content)
        except (EOFError, json.JSONDecodeError, ValueError):
            return None
    
    def send_message(self, message: Dict[str, Any]):
        """Send a JSON-RPC message to stdout"""
        content = json.dumps(message)
        response = f"Content-Length: {len(content)}\r\n\r\n{content}"
        sys.stdout.buffer.write(response.encode('utf-8'))
        sys.stdout.buffer.flush()
    
    def send_response(self, request_id: Any, result: Any):
        """Send a response to a request"""
        self.send_message({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": result
        })
    
    def send_error(self, request_id: Any, code: int, message: str):
        """Send an error response"""
        self.send_message({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {
                "code": code,
                "message": message
            }
        })
    
    def handle_initialize(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle initialize request"""
        self.client_capabilities = request.get("params", {}).get("capabilities", {})
        
        return {
            "capabilities": {
                "textDocumentSync": 1,  # Full document sync
                "hoverProvider": True,
                "completionProvider": {
                    "resolveProvider": False,
                    "triggerCharacters": ["."]
                },
                "definitionProvider": True,
                "referencesProvider": True,
                "documentSymbolProvider": True,
                "workspaceSymbolProvider": True,
                "codeActionProvider": True,
                "documentFormattingProvider": True,
                "documentRangeFormattingProvider": True,
                "documentOnTypeFormattingProvider": {
                    "firstTriggerCharacter": "}",
                    "moreTriggerCharacter": [";", "\n"]
                },
                "renameProvider": True,
                "documentHighlightProvider": True,
                "signatureHelpProvider": {
                    "triggerCharacters": ["(", ","]
                }
            },
            "serverInfo": {
                "name": "Mock LSP Server",
                "version": "1.0.0"
            }
        }
    
    def handle_hover(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle hover request"""
        return {
            "contents": {
                "kind": "markdown",
                "value": "**Mock Hover Information**\n\nThis is a test hover response from the mock LSP server."
            }
        }
    
    def handle_completion(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle completion request"""
        return {
            "isIncomplete": False,
            "items": [
                {
                    "label": "test_function",
                    "kind": 3,  # Function
                    "detail": "fn test_function() void",
                    "documentation": "A test function for completion"
                },
                {
                    "label": "test_variable",
                    "kind": 6,  # Variable
                    "detail": "var test_variable: i32",
                    "documentation": "A test variable for completion"
                }
            ]
        }
    
    def handle_definition(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle go to definition request"""
        return {
            "uri": "file:///test/mock_file.zig",
            "range": {
                "start": {"line": 0, "character": 0},
                "end": {"line": 0, "character": 10}
            }
        }
    
    def run(self):
        """Main server loop"""
        sys.stderr.write("Mock LSP Server starting...\n")
        sys.stderr.flush()
        
        while True:
            try:
                message = self.read_message()
                if message is None:
                    break
                
                method = message.get("method")
                request_id = message.get("id")
                
                if method == "initialize":
                    result = self.handle_initialize(message)
                    self.send_response(request_id, result)
                    
                elif method == "initialized":
                    # Notification - no response needed
                    self.initialized = True
                    
                elif method == "textDocument/hover":
                    result = self.handle_hover(message)
                    self.send_response(request_id, result)
                    
                elif method == "textDocument/completion":
                    result = self.handle_completion(message)
                    self.send_response(request_id, result)
                    
                elif method == "textDocument/definition":
                    result = self.handle_definition(message)
                    self.send_response(request_id, result)
                    
                elif method == "shutdown":
                    self.send_response(request_id, None)
                    
                elif method == "exit":
                    break
                    
                else:
                    # Unknown method
                    if request_id is not None:
                        self.send_error(request_id, -32601, f"Method not found: {method}")
                        
            except Exception as e:
                sys.stderr.write(f"Error handling message: {e}\n")
                sys.stderr.flush()
                if request_id is not None:
                    self.send_error(request_id, -32603, "Internal error")

if __name__ == "__main__":
    server = MockLSPServer()
    server.run()