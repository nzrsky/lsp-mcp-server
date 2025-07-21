{
  description = "LSP-MCP Bridge Server - Language Server Protocol to Model Context Protocol bridge";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, zig }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zigpkg = zig.packages.${system}."0.13.0";
      in
      {
        packages = {
          default = self.packages.${system}.lsp-mcp-server;
          
          lsp-mcp-server = pkgs.stdenv.mkDerivation rec {
            pname = "lsp-mcp-server";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [
              zigpkg
            ];

            buildInputs = with pkgs; [
              # Runtime dependencies for LSP servers
            ];

            buildPhase = ''
              runHook preBuild
              
              # Set cache directory
              export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/.zig-cache
              export ZIG_LOCAL_CACHE_DIR=$TMPDIR/.zig-cache
              
              zig build -Doptimize=ReleaseSafe --prefix $out
              
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              
              # Binary is already installed by zig build --prefix
              # Just ensure it's executable
              chmod +x $out/bin/lsp-mcp-server
              
              # Install configuration examples
              mkdir -p $out/share/lsp-mcp-server
              if [ -f config/lsp-mcp-server.json.example ]; then
                cp config/lsp-mcp-server.json.example $out/share/lsp-mcp-server/
              fi
              
              # Install documentation
              if [ -f README.md ]; then
                mkdir -p $out/share/doc/lsp-mcp-server
                cp README.md $out/share/doc/lsp-mcp-server/
              fi
              
              runHook postInstall
            '';

            checkPhase = ''
              runHook preCheck
              
              # Basic functionality test
              $out/bin/lsp-mcp-server --help
              
              runHook postCheck
            '';

            doCheck = true;

            meta = with pkgs.lib; {
              description = "Language Server Protocol to Model Context Protocol bridge server";
              longDescription = ''
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
              '';
              homepage = "https://github.com/username/lsp-mcp-server";
              license = licenses.mit;
              maintainers = [ maintainers.claude-ai ];
              platforms = platforms.all;
              mainProgram = "lsp-mcp-server";
            };
          };

          # Development environment with language servers
          lsp-mcp-server-dev = pkgs.buildEnv {
            name = "lsp-mcp-server-dev";
            paths = with pkgs; [
              self.packages.${system}.lsp-mcp-server
              # Language servers
              zls              # Zig Language Server
              rust-analyzer    # Rust Language Server
              gopls           # Go Language Server
              nodePackages.typescript-language-server  # TypeScript
              python3Packages.python-lsp-server        # Python
              # Development tools
              zigpkg
              git
              curl
              jq
            ];
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zigpkg
            
            # Language servers for testing
            zls
            rust-analyzer
            gopls
            nodePackages.typescript-language-server
            python3Packages.python-lsp-server
            
            # Development tools
            git
            curl
            jq
            docker
            docker-compose
            
            # Documentation tools
            mdbook
          ];

          shellHook = ''
            echo "🚀 LSP-MCP Server Development Environment"
            echo "Available commands:"
            echo "  zig build          - Build the project"
            echo "  zig build test     - Run tests"
            echo "  zig build test-bdd - Run BDD integration tests"
            echo "  docker-compose up  - Start containerized environment"
            echo ""
            echo "Language servers available:"
            echo "  zls, rust-analyzer, gopls, typescript-language-server, pylsp"
          '';
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.lsp-mcp-server;
        };

        # NixOS module
        nixosModules.lsp-mcp-server = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.lsp-mcp-server;
          in
          {
            options.services.lsp-mcp-server = {
              enable = mkEnableOption "LSP-MCP Bridge Server";

              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.system}.lsp-mcp-server;
                description = "The lsp-mcp-server package to use";
              };

              server = mkOption {
                type = types.str;
                default = "zls";
                description = "Language server to use (zls, rust-analyzer, gopls, etc.)";
              };

              configFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Configuration file path";
              };

              user = mkOption {
                type = types.str;
                default = "lsp-mcp";
                description = "User to run the service as";
              };

              group = mkOption {
                type = types.str;
                default = "lsp-mcp";
                description = "Group to run the service as";
              };

              extraArgs = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Additional command line arguments";
              };
            };

            config = mkIf cfg.enable {
              users.users.${cfg.user} = {
                isSystemUser = true;
                group = cfg.group;
                home = "/var/lib/lsp-mcp-server";
                createHome = true;
              };

              users.groups.${cfg.group} = {};

              systemd.services.lsp-mcp-server = {
                description = "LSP-MCP Bridge Server";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];

                serviceConfig = {
                  ExecStart = "${cfg.package}/bin/lsp-mcp-server --server ${cfg.server}"
                    + optionalString (cfg.configFile != null) " --config ${cfg.configFile}"
                    + " " + concatStringsSep " " cfg.extraArgs;
                  User = cfg.user;
                  Group = cfg.group;
                  Restart = "on-failure";
                  RestartSec = "5";
                  TimeoutStopSec = "10";

                  # Security settings
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  ReadWritePaths = [ "/var/lib/lsp-mcp-server" "/var/log/lsp-mcp-server" ];
                  ProtectKernelTunables = true;
                  ProtectKernelModules = true;
                  ProtectControlGroups = true;
                };

                environment = {
                  PATH = "/usr/local/bin:/usr/bin:/bin";
                } // optionalAttrs (cfg.configFile != null) {
                  LSP_MCP_CONFIG = cfg.configFile;
                };
              };

              # Create log directory
              systemd.tmpfiles.rules = [
                "d /var/log/lsp-mcp-server 0750 ${cfg.user} ${cfg.group} -"
              ];
            };
          };

        # Home Manager module
        homeManagerModules.lsp-mcp-server = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.programs.lsp-mcp-server;
          in
          {
            options.programs.lsp-mcp-server = {
              enable = mkEnableOption "LSP-MCP Bridge Server";

              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.system}.lsp-mcp-server;
                description = "The lsp-mcp-server package to use";
              };

              settings = mkOption {
                type = types.attrs;
                default = {};
                description = "Configuration for lsp-mcp-server";
              };
            };

            config = mkIf cfg.enable {
              home.packages = [ cfg.package ];

              xdg.configFile."lsp-mcp-server/config.json" = mkIf (cfg.settings != {}) {
                text = builtins.toJSON cfg.settings;
              };
            };
          };
      }
    );
}