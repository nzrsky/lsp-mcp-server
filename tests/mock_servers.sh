#!/bin/bash
# Mock Language Servers for Testing
# Provides lightweight alternatives to real LSP servers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mock_lsp_server() {
    echo "Starting Mock LSP Server..." >&2
    exec python3 "${SCRIPT_DIR}/mock_lsp_server.py"
}

mock_zls() {
    echo "Mock ZLS (Zig Language Server)" >&2
    mock_lsp_server
}

mock_rust_analyzer() {
    echo "Mock rust-analyzer" >&2
    mock_lsp_server  
}

mock_gopls() {
    echo "Mock gopls (Go Language Server)" >&2
    mock_lsp_server
}

mock_typescript_language_server() {
    echo "Mock TypeScript Language Server" >&2
    mock_lsp_server
}

mock_pylsp() {
    echo "Mock Python Language Server" >&2
    mock_lsp_server
}

# Main dispatch
case "${1:-zls}" in
    zls)
        mock_zls
        ;;
    rust-analyzer)
        mock_rust_analyzer
        ;;
    gopls)
        mock_gopls
        ;;
    typescript-language-server)
        mock_typescript_language_server
        ;;
    pylsp)
        mock_pylsp
        ;;
    *)
        echo "Usage: $0 [server_name]" >&2
        echo "Available mock servers: zls, rust-analyzer, gopls, typescript-language-server, pylsp" >&2
        exit 1
        ;;
esac