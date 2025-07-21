# Installation Guide

This guide covers multiple ways to install and run `lsp-mcp-server` on different platforms and package managers.

## Quick Start

### Docker (Recommended for Testing)

```bash
# Pull and run the latest image
docker run --rm -it ghcr.io/username/lsp-mcp-server:latest --help

# With docker-compose for development
git clone https://github.com/username/lsp-mcp-server.git
cd lsp-mcp-server
docker-compose up lsp-mcp-dev
```

### Pre-built Binaries

Download pre-built binaries from the [releases page](https://github.com/username/lsp-mcp-server/releases).

```bash
# Linux/macOS
curl -L https://github.com/username/lsp-mcp-server/releases/latest/download/lsp-mcp-server-$(uname -s)-$(uname -m).tar.gz | tar -xz
sudo mv lsp-mcp-server /usr/local/bin/
```

## Package Managers

### Homebrew (macOS/Linux)

```bash
# Add our tap
brew tap username/lsp-mcp-server

# Install the package
brew install lsp-mcp-server

# Install with language servers
brew install lsp-mcp-server zls rust-analyzer gopls
```

### Nix (NixOS/Nix Package Manager)

```bash
# Using nix profile
nix profile install github:username/lsp-mcp-server

# Using nix shell (temporary)
nix shell github:username/lsp-mcp-server

# Using nix run (one-time)
nix run github:username/lsp-mcp-server -- --help
```

#### NixOS Configuration

Add to your `configuration.nix`:

```nix
{
  imports = [
    (builtins.fetchTarball "https://github.com/username/lsp-mcp-server/archive/main.tar.gz" + "/flake.nix").nixosModules.lsp-mcp-server
  ];

  services.lsp-mcp-server = {
    enable = true;
    server = "zls";  # or "rust-analyzer", "gopls", etc.
  };
}
```

#### Home Manager Configuration

Add to your `home.nix`:

```nix
{
  imports = [
    (builtins.fetchTarball "https://github.com/username/lsp-mcp-server/archive/main.tar.gz" + "/flake.nix").homeManagerModules.lsp-mcp-server
  ];

  programs.lsp-mcp-server = {
    enable = true;
    settings = {
      servers.zls.command = "zls";
    };
  };
}
```

### APT (Ubuntu/Debian)

```bash
# Add our repository
curl -fsSL https://github.com/username/lsp-mcp-server/releases/latest/download/pubkey.gpg | sudo apt-key add -
echo "deb https://github.com/username/lsp-mcp-server/releases/latest/download/ stable main" | sudo tee /etc/apt/sources.list.d/lsp-mcp-server.list

# Update and install
sudo apt update
sudo apt install lsp-mcp-server

# Install with language servers
sudo apt install lsp-mcp-server zls rust-analyzer golang-golang-x-tools-gopls
```

### YUM/DNF (RHEL/Fedora/CentOS)

```bash
# Add our repository
sudo tee /etc/yum.repos.d/lsp-mcp-server.repo << EOF
[lsp-mcp-server]
name=LSP-MCP Server Repository
baseurl=https://github.com/username/lsp-mcp-server/releases/latest/download/rpm/
enabled=1
gpgcheck=1
gpgkey=https://github.com/username/lsp-mcp-server/releases/latest/download/pubkey.gpg
EOF

# Install
sudo dnf install lsp-mcp-server  # or yum

# Install with language servers
sudo dnf install lsp-mcp-server zls rust-analyzer golang-x-tools-gopls
```

### Smithery

```bash
# Install smithery if you haven't already
curl -sSf https://smithery.dev/install.sh | sh

# Install lsp-mcp-server
smithery install lsp-mcp-server

# Install with language servers
smithery install lsp-mcp-server zls rust-analyzer gopls
```

## Build from Source

### Prerequisites

- [Zig 0.13.0+](https://ziglang.org/download/)
- Git

### Building

```bash
git clone https://github.com/username/lsp-mcp-server.git
cd lsp-mcp-server
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/lsp-mcp-server /usr/local/bin/
```

### Running Tests

```bash
# Unit tests
zig build test

# BDD integration tests  
zig build test-bdd
```

## Language Server Installation

`lsp-mcp-server` works with any LSP-compatible language server. Here's how to install popular ones:

### Zig Language Server (ZLS)

```bash
# Homebrew
brew install zls

# From source
git clone https://github.com/zigtools/zls.git
cd zls
zig build -Doptimize=ReleaseSafe
```

### Rust Analyzer

```bash
# Homebrew
brew install rust-analyzer

# Cargo
cargo install rust-analyzer

# VS Code extension (includes binary)
```

### Go Language Server (gopls)

```bash
# Go
go install golang.org/x/tools/gopls@latest

# Homebrew
brew install gopls
```

### TypeScript Language Server

```bash
# npm
npm install -g typescript-language-server typescript

# Homebrew
brew install typescript-language-server
```

### Python Language Server

```bash
# pip
pip install python-lsp-server

# Homebrew
brew install python-lsp-server
```

## Configuration

### Basic Configuration

Create a configuration file at one of these locations:
- `~/.config/lsp-mcp-server/config.json`
- `/etc/lsp-mcp-server/config.json`
- Or specify with `--config /path/to/config.json`

Example configuration:

```json
{
  "servers": {
    "zls": {
      "command": "/usr/local/bin/zls",
      "args": [],
      "languages": ["zig"]
    }
  }
}
```

See [config/lsp-mcp-server.json.example](config/lsp-mcp-server.json.example) for a complete example.

### Environment Variables

- `LSP_MCP_CONFIG`: Path to configuration file
- `LSP_MCP_LOG_LEVEL`: Log level (debug, info, warn, error)
- `PATH`: Must include language server executables

## Integration with AI Assistants

### Claude Code

Add to your Claude Code configuration:

```json
{
  "mcpServers": {
    "lsp-bridge": {
      "command": "lsp-mcp-server",
      "args": ["--server", "zls"]
    }
  }
}
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS):

```json
{
  "mcpServers": {
    "lsp-bridge": {
      "command": "/usr/local/bin/lsp-mcp-server",
      "args": ["--server", "rust-analyzer"]
    }
  }
}
```

### Gemini CLI

```bash
# Configure Gemini CLI to use lsp-mcp-server
gemini config set mcp.servers.lsp-bridge.command "lsp-mcp-server"
gemini config set mcp.servers.lsp-bridge.args "--server,gopls"
```

## Docker Usage

### Basic Usage

```bash
# Run with ZLS
docker run --rm -v "$(pwd):/workspace" ghcr.io/username/lsp-mcp-server:latest --server zls

# Run with Rust Analyzer
docker run --rm -v "$(pwd):/workspace" ghcr.io/username/lsp-mcp-server:latest --server rust-analyzer
```

### Development Environment

```bash
git clone https://github.com/username/lsp-mcp-server.git
cd lsp-mcp-server

# Start development container
docker-compose up lsp-mcp-dev

# Connect to running container
docker-compose exec lsp-mcp-dev sh
```

### Custom Dockerfile

```dockerfile
FROM ghcr.io/username/lsp-mcp-server:latest

# Add your language servers
RUN npm install -g your-language-server

# Copy your configuration
COPY config.json /etc/lsp-mcp-server/config.json

ENTRYPOINT ["lsp-mcp-server"]
CMD ["--server", "your-language-server"]
```

## Systemd Service

For system-wide installation with systemd:

```bash
# Enable and start the service
sudo systemctl enable lsp-mcp-server
sudo systemctl start lsp-mcp-server

# Check status
sudo systemctl status lsp-mcp-server

# View logs
sudo journalctl -u lsp-mcp-server -f
```

## Troubleshooting

### Common Issues

1. **Language server not found**
   ```bash
   # Ensure language server is in PATH
   which zls
   
   # Or specify full path in config
   "command": "/usr/local/bin/zls"
   ```

2. **Permission denied**
   ```bash
   # Make binary executable
   chmod +x /usr/local/bin/lsp-mcp-server
   ```

3. **Connection timeout**
   ```bash
   # Increase timeout in config
   "timeout_ms": 10000
   
   # Or check language server logs
   lsp-mcp-server --server zls --debug
   ```

### Debug Mode

```bash
# Enable debug logging
lsp-mcp-server --server zls --debug

# Or set environment variable
LSP_MCP_LOG_LEVEL=debug lsp-mcp-server --server zls
```

### Health Check

```bash
# Test basic functionality
lsp-mcp-server --help

# Test with specific language server
lsp-mcp-server --server zls --test

# Test BDD suite
zig build test-bdd
```

## Uninstallation

### Homebrew
```bash
brew uninstall lsp-mcp-server
```

### APT
```bash
sudo apt remove lsp-mcp-server
```

### YUM/DNF
```bash
sudo dnf remove lsp-mcp-server
```

### Manual
```bash
sudo rm /usr/local/bin/lsp-mcp-server
sudo rm -rf /etc/lsp-mcp-server
```

## Support

- [GitHub Issues](https://github.com/username/lsp-mcp-server/issues)
- [Documentation](https://github.com/username/lsp-mcp-server/wiki)
- [Discussions](https://github.com/username/lsp-mcp-server/discussions)