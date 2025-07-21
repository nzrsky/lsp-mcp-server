# MCP Protocol Compliance Tests

Feature: MCP Protocol Compliance
  As an LLM client
  I want to communicate with the MCP server using the MCP protocol
  So that I can access language server capabilities through standardized tools

  Background:
    Given the MCP server is available
    And the MCP server supports LSP integration

  Scenario: MCP server initialization
    Given the MCP server is not initialized
    When I send an initialize request with:
      """
      {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
          "protocolVersion": "0.1.0",
          "capabilities": {
            "tools": {}
          },
          "clientInfo": {
            "name": "test-client",
            "version": "1.0.0"
          }
        }
      }
      """
    Then I should receive an initialize response
    And the response should contain server capabilities
    And the response should indicate tool support
    And the server should be marked as initialized

  Scenario: List available tools
    Given the MCP server is initialized
    When I send a tools/list request
    Then I should receive a list of available tools
    And the tool list should include "hover"
    And the tool list should include "definition"
    And the tool list should include "completions"
    And each tool should have a name, description, and input schema

  Scenario: Call hover tool
    Given the MCP server is initialized
    And an LSP server "zls" is configured
    When I call the "hover" tool with parameters:
      """
      {
        "uri": "file:///path/to/test.zig",
        "line": 2,
        "character": 10
      }
      """
    Then I should receive a successful tool response
    And the response should contain hover information
    And the hover information should have content
    And the content should be properly formatted

  Scenario: Call definition tool
    Given the MCP server is initialized
    And an LSP server is configured and running
    When I call the "definition" tool with parameters:
      """
      {
        "uri": "file:///path/to/test.zig",
        "line": 5,
        "character": 15
      }
      """
    Then I should receive a successful tool response
    And the response should contain definition locations
    And each location should have a URI and range

  Scenario: Call completions tool
    Given the MCP server is initialized
    And an LSP server is configured and running
    When I call the "completions" tool with parameters:
      """
      {
        "uri": "file:///path/to/test.zig",
        "line": 3,
        "character": 8
      }
      """
    Then I should receive a successful tool response
    And the response should contain completion items
    And each completion item should have a label
    And completion items should have appropriate kinds

  Scenario: Tool parameter validation
    Given the MCP server is initialized
    When I call the "hover" tool with invalid parameters:
      """
      {
        "uri": "invalid-uri",
        "line": "not-a-number",
        "character": -1
      }
      """
    Then I should receive an error response
    And the error should indicate invalid parameters
    And the error code should be -32602

  Scenario: Missing tool parameters
    Given the MCP server is initialized
    When I call the "hover" tool with missing parameters:
      """
      {
        "uri": "file:///path/to/test.zig"
      }
      """
    Then I should receive an error response
    And the error should indicate missing required parameters
    And the error code should be -32602

  Scenario: Unknown tool call
    Given the MCP server is initialized
    When I call an unknown tool "unknown-tool" with parameters:
      """
      {
        "param1": "value1"
      }
      """
    Then I should receive an error response
    And the error should indicate unknown tool
    And the error code should be -32602

  Scenario: JSON-RPC error handling
    Given the MCP server is initialized
    When I send a malformed JSON request:
      """
      {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
          "name": "hover",
          "arguments": invalid-json
        }
      }
      """
    Then I should receive an error response
    And the error code should be -32700 (Parse error)

  Scenario: Method not found
    Given the MCP server is initialized
    When I send a request for unknown method:
      """
      {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "unknown/method",
        "params": {}
      }
      """
    Then I should receive an error response
    And the error code should be -32601 (Method not found)

  Scenario: Server not initialized error
    Given the MCP server is not initialized
    When I send a tools/list request
    Then I should receive an error response
    And the error should indicate server not initialized
    And the error code should be -32002

  Scenario Outline: MCP tool integration with different LSP servers
    Given the MCP server is initialized
    And LSP server "<server>" is configured
    When I call the "<tool>" tool for a "<language>" file
    Then I should receive a successful response
    And the response should contain appropriate "<language>" language information

    Examples:
      | server                    | tool        | language   |
      | zls                       | hover       | zig        |
      | zls                       | definition  | zig        |
      | zls                       | completions | zig        |
      | rust-analyzer             | hover       | rust       |
      | rust-analyzer             | definition  | rust       |
      | rust-analyzer             | completions | rust       |
      | gopls                     | hover       | go         |
      | gopls                     | definition  | go         |
      | gopls                     | completions | go         |

  @claude-code-integration
  Scenario: Claude Code MCP integration
    Given the MCP server is running
    And Claude Code is configured to use this MCP server
    When Claude Code requests available tools
    Then the MCP server should respond with language intelligence tools
    And Claude Code should be able to use hover functionality
    And Claude Code should be able to use definition lookup
    And Claude Code should be able to use code completions

  @claude-desktop-integration
  Scenario: Claude Desktop MCP integration
    Given the MCP server is running
    And Claude Desktop is configured with this MCP server
    When Claude Desktop makes a request through MCP
    Then the MCP server should handle the request properly
    And responses should be formatted for Claude Desktop consumption

  @gemini-cli-integration
  Scenario: Gemini CLI MCP integration
    Given the MCP server is running
    And Gemini CLI supports MCP protocol
    When Gemini CLI connects to the MCP server
    Then the server should handle Gemini CLI requests
    And responses should be compatible with Gemini CLI format

  @streaming-support
  Scenario: Streaming response support (future)
    Given the MCP server is initialized
    And streaming is supported
    When I call a tool that returns large results
    Then I should receive streaming responses
    And each response chunk should be properly formatted
    And the stream should terminate with a completion marker

  @progress-reporting
  Scenario: Progress reporting for long operations
    Given the MCP server is initialized
    When I call a tool that takes significant time
    Then I should receive progress notifications
    And the progress should indicate completion percentage
    And the final response should include the complete result

  @cancellation-support
  Scenario: Request cancellation support
    Given the MCP server is initialized
    And I have sent a long-running request with ID 123
    When I send a cancel request for ID 123
    Then the long-running request should be cancelled
    And I should receive a cancelled error response for ID 123

  @resource-management
  Scenario: Resource and memory management
    Given the MCP server is initialized
    When I make multiple tool calls in sequence
    Then the server should not leak memory
    And response times should remain consistent
    And the server should handle resource cleanup properly

  @configuration-management
  Scenario: Dynamic server configuration
    Given the MCP server is initialized
    When I update the LSP server configuration
    Then the MCP server should reload the configuration
    And subsequent tool calls should use the new configuration
    And existing connections should be handled gracefully

  @logging-and-debugging
  Scenario: Logging and debugging support
    Given the MCP server is running with debug logging
    When I make tool calls and encounter errors
    Then appropriate log messages should be generated
    And the logs should help with troubleshooting
    And sensitive information should not be logged

  @security-considerations
  Scenario: Security and input validation
    Given the MCP server is initialized
    When I send requests with potentially malicious input
    Then the server should sanitize the input
    And the server should not execute arbitrary code
    And the server should not access unauthorized files
    And error messages should not reveal system information