# LSP Protocol Compliance Tests

Feature: LSP Protocol Compliance
  As an MCP server
  I want to communicate correctly with LSP servers
  So that I can provide accurate language intelligence to LLMs

  Background:
    Given the MCP server is configured for testing
    And an LSP server is available

  Scenario: Initialize LSP connection
    Given an LSP server is not running
    When I start the LSP server with command "zls"
    Then the LSP server should be running
    And I should be able to send initialize request
    And I should receive initialize response with server capabilities

  Scenario: Send hover request
    Given an LSP server is running and initialized
    And a Zig file exists at "test.zig" with content:
      """
      const std = @import("std");
      
      pub fn main() void {
          std.debug.print("Hello, World!\n", .{});
      }
      """
    When I send a hover request for "test.zig" at line 3, character 4
    Then I should receive a hover response
    And the hover response should contain markup content
    And the hover content should include information about "std"

  Scenario: Send definition request
    Given an LSP server is running and initialized
    And a Zig file exists with function definition
    When I send a definition request for the function call
    Then I should receive a definition response
    And the definition response should contain location information
    And the location should point to the function definition

  Scenario: Send completion request
    Given an LSP server is running and initialized
    And a Zig file exists with incomplete code
    When I send a completion request at the incomplete position
    Then I should receive a completion response
    And the completion response should contain completion items
    And the completion items should include relevant suggestions

  Scenario: Handle LSP server errors
    Given an LSP server is running and initialized
    When I send an invalid request to the LSP server
    Then I should receive an error response
    And the error response should have a valid error code
    And the error response should have an error message

  Scenario: LSP server shutdown
    Given an LSP server is running and initialized
    When I send a shutdown request to the LSP server
    Then the LSP server should acknowledge the shutdown
    When I send an exit notification
    Then the LSP server should terminate gracefully

  Scenario Outline: Multi-language LSP support
    Given an LSP server "<server>" is available
    When I start the LSP server with command "<command>"
    And I open a "<language>" file with extension "<extension>"
    Then the LSP server should support "<language>" language features
    And I should be able to get hover information
    And I should be able to get completion suggestions

    Examples:
      | server                    | command                    | language   | extension |
      | zls                       | zls                        | zig        | .zig      |
      | rust-analyzer             | rust-analyzer              | rust       | .rs       |
      | gopls                     | gopls                      | go         | .go       |
      | typescript-language-server| typescript-language-server | typescript | .ts       |
      | pylsp                     | pylsp                      | python     | .py       |

  Scenario: Document lifecycle management
    Given an LSP server is running and initialized
    When I send a "textDocument/didOpen" notification for a file
    Then the LSP server should track the document
    When I send a "textDocument/didChange" notification with changes
    Then the LSP server should update the document
    When I send a "textDocument/didSave" notification
    Then the LSP server should process the saved document
    When I send a "textDocument/didClose" notification
    Then the LSP server should stop tracking the document

  Scenario: Code actions and refactoring
    Given an LSP server is running and initialized
    And a file exists with code that has available code actions
    When I send a code action request for the problematic code
    Then I should receive a list of available code actions
    And the code actions should include quick fixes
    And the code actions should include refactoring options

  Scenario: Document symbols
    Given an LSP server is running and initialized
    And a file exists with functions, classes, and variables
    When I send a document symbol request
    Then I should receive a list of document symbols
    And the symbols should include functions with their ranges
    And the symbols should include classes with their ranges
    And the symbols should be hierarchically organized

  Scenario: Workspace symbols
    Given an LSP server is running and initialized
    And multiple files exist in the workspace
    When I send a workspace symbol request for "main"
    Then I should receive a list of matching symbols across the workspace
    And each symbol should have location information

  Scenario: Find references
    Given an LSP server is running and initialized
    And a file exists with a function definition and multiple calls
    When I send a references request for the function definition
    Then I should receive a list of all references
    And the references should include the definition location
    And the references should include all call sites

  Scenario: Rename symbol
    Given an LSP server is running and initialized
    And a file exists with a symbol to rename
    When I send a rename request for the symbol
    Then I should receive workspace edit information
    And the workspace edit should include all symbol occurrences
    And the workspace edit should preserve code structure

  Scenario: Formatting
    Given an LSP server is running and initialized
    And a file exists with poorly formatted code
    When I send a formatting request for the document
    Then I should receive text edits for formatting
    And applying the edits should improve code formatting

  Scenario: Range formatting
    Given an LSP server is running and initialized
    And a file exists with poorly formatted code
    When I send a range formatting request for specific lines
    Then I should receive text edits for the specified range
    And the formatting should only affect the requested range

  @timeout-handling
  Scenario: Request timeout handling
    Given an LSP server is running and initialized
    When I send a request that takes longer than the timeout
    Then I should receive a timeout error
    And the MCP server should remain responsive
    And subsequent requests should work normally

  @error-recovery
  Scenario: LSP server crash recovery
    Given an LSP server is running and initialized
    When the LSP server crashes unexpectedly
    Then the MCP server should detect the crash
    And the MCP server should attempt to restart the LSP server
    And normal functionality should resume after restart

  @performance
  Scenario: Large file handling
    Given an LSP server is running and initialized
    And a large file exists with thousands of lines
    When I send requests for the large file
    Then the responses should arrive within acceptable time limits
    And the LSP server should not run out of memory
    And the responses should be accurate for the large file

  @concurrency
  Scenario: Concurrent request handling
    Given an LSP server is running and initialized
    When I send multiple requests concurrently
    Then all requests should receive responses
    And the responses should correspond to the correct requests
    And the LSP server should handle the load gracefully