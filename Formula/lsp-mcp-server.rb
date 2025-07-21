class LspMcpServer < Formula
  desc "Language Server Protocol to Model Context Protocol bridge server"
  homepage "https://github.com/username/lsp-mcp-server"
  url "https://github.com/username/lsp-mcp-server/archive/v0.1.0.tar.gz"
  sha256 "replace_with_actual_sha256_hash"
  license "MIT"
  head "https://github.com/username/lsp-mcp-server.git", branch: "main"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseSafe", "--prefix", prefix
    bin.install "zig-out/bin/lsp-mcp-server"
  end

  def post_install
    # Create config directory
    (etc/"lsp-mcp-server").mkpath
    
    # Install example configuration
    unless (etc/"lsp-mcp-server/config.json").exist?
      (etc/"lsp-mcp-server/config.json").write <<~EOS
        {
          "servers": {
            "zls": {
              "command": "zls",
              "args": [],
              "languages": ["zig"]
            },
            "rust-analyzer": {
              "command": "rust-analyzer",
              "args": [],
              "languages": ["rust"]
            },
            "gopls": {
              "command": "gopls",
              "args": [],
              "languages": ["go"]
            }
          }
        }
      EOS
    end
  end

  service do
    run [opt_bin/"lsp-mcp-server"]
    environment_variables PATH: std_service_path_env
    keep_alive false
    working_dir HOMEBREW_PREFIX
  end

  test do
    # Test that the binary can be executed and shows help
    assert_match "LSP-MCP Bridge Server", shell_output("#{bin}/lsp-mcp-server --help")
    
    # Test that it can find its own binary
    assert_match "lsp-mcp-server", shell_output("which #{bin}/lsp-mcp-server")
  end

  def caveats
    <<~EOS
      lsp-mcp-server has been installed successfully!
      
      To use with different language servers, install them separately:
        brew install zls                    # Zig Language Server
        brew install rust-analyzer          # Rust Language Server  
        brew install gopls                  # Go Language Server
        npm install -g typescript-language-server  # TypeScript
        pip install python-lsp-server      # Python
      
      Configuration file is located at:
        #{etc}/lsp-mcp-server/config.json
      
      Usage examples:
        lsp-mcp-server                      # Use ZLS (default)
        lsp-mcp-server --server rust-analyzer
        lsp-mcp-server --config /path/to/custom/config.json
      
      For use with Claude Code, Claude Desktop, or other MCP clients,
      configure them to run: #{bin}/lsp-mcp-server
    EOS
  end
end