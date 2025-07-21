Name:           lsp-mcp-server
Version:        0.1.0
Release:        1%{?dist}
Summary:        Language Server Protocol to Model Context Protocol bridge

License:        MIT
URL:            https://github.com/username/lsp-mcp-server
Source0:        https://github.com/username/lsp-mcp-server/archive/v%{version}.tar.gz

BuildRequires:  zig >= 0.13.0
BuildRequires:  curl
BuildRequires:  ca-certificates
BuildRequires:  systemd-rpm-macros

Requires:       ca-certificates
Recommends:     zls
Recommends:     rust-analyzer
Recommends:     golang-x-tools-gopls
Suggests:       nodejs
Suggests:       npm
Suggests:       python3-pip

%description
lsp-mcp-server is a bridge server written in Zig that connects Language
Server Protocol (LSP) servers to Model Context Protocol (MCP) clients.
This enables AI coding assistants like Claude Code, Claude Desktop,
Gemini CLI, and GitHub Copilot to interact with any LSP-compatible
language server.

Features:
- Generic LSP client supporting any language server
- MCP server implementation for AI assistant integration  
- Support for Zig, Rust, Go, TypeScript, Python, and more
- Configurable server selection and settings
- Built-in timeout handling and graceful fallbacks

%prep
%setup -q

%build
zig build -Doptimize=ReleaseSafe

%install
# Install binary
install -D -m 755 zig-out/bin/lsp-mcp-server %{buildroot}%{_bindir}/lsp-mcp-server

# Install configuration directory
install -d %{buildroot}%{_sysconfdir}/lsp-mcp-server

# Install example configuration
install -D -m 644 config/lsp-mcp-server.json.example \
    %{buildroot}%{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json.example

# Install systemd service
install -D -m 644 packaging/lsp-mcp-server.service \
    %{buildroot}%{_unitdir}/lsp-mcp-server.service

# Install documentation
install -D -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md

# Create runtime directories
install -d %{buildroot}%{_sharedstatedir}/lsp-mcp-server
install -d %{buildroot}%{_localstatedir}/log/lsp-mcp-server

%pre
getent group lsp-mcp >/dev/null || groupadd -r lsp-mcp
getent passwd lsp-mcp >/dev/null || \
    useradd -r -g lsp-mcp -d %{_sharedstatedir}/lsp-mcp-server \
            -s /sbin/nologin -c "LSP-MCP Server" lsp-mcp
exit 0

%post
# Create default config if it doesn't exist
if [ ! -f %{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json ]; then
    cp %{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json.example \
       %{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json
    chown root:lsp-mcp %{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json
    chmod 640 %{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json
fi

%systemd_post lsp-mcp-server.service

%preun
%systemd_preun lsp-mcp-server.service

%postun
%systemd_postun_with_restart lsp-mcp-server.service

if [ $1 -eq 0 ] ; then
    # Package removal, not upgrade
    getent passwd lsp-mcp >/dev/null && userdel lsp-mcp
    getent group lsp-mcp >/dev/null && groupdel lsp-mcp
    rm -rf %{_sharedstatedir}/lsp-mcp-server
    rm -rf %{_localstatedir}/log/lsp-mcp-server
fi

%check
# Basic functionality test
%{buildroot}%{_bindir}/lsp-mcp-server --help

%files
%license LICENSE
%doc README.md
%{_bindir}/lsp-mcp-server
%{_unitdir}/lsp-mcp-server.service
%dir %{_sysconfdir}/lsp-mcp-server
%config(noreplace) %{_sysconfdir}/lsp-mcp-server/lsp-mcp-server.json.example
%attr(750,lsp-mcp,lsp-mcp) %{_sharedstatedir}/lsp-mcp-server
%attr(750,lsp-mcp,lsp-mcp) %{_localstatedir}/log/lsp-mcp-server
%{_docdir}/%{name}/README.md

%changelog
* Mon Jul 21 2025 Claude AI Assistant <noreply@anthropic.com> - 0.1.0-1
- Initial RPM release
- Generic LSP to MCP bridge server written in Zig
- Support for multiple language servers (ZLS, rust-analyzer, gopls, etc.)
- Integration with AI coding assistants (Claude Code, Claude Desktop, etc.)
- Comprehensive BDD test suite
- Docker and container support
- Configurable timeout handling and graceful fallbacks