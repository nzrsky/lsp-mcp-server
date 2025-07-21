# Multi-stage Docker build for lsp-mcp-server
FROM alpine:3.19 AS zig-builder

# Install dependencies for building
RUN apk add --no-cache \
    curl \
    xz \
    tar \
    build-base \
    linux-headers

# Install Zig
ARG ZIG_VERSION=0.14.1
RUN curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" | tar -xJ -C /opt && \
    ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig

# Copy source code
WORKDIR /build
COPY . .

# Build the application
RUN zig build -Doptimize=ReleaseSafe

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    git

# Install common language servers
RUN apk add --no-cache \
    go \
    rust \
    cargo \
    nodejs \
    npm \
    python3 \
    py3-pip

# Install language servers
RUN npm install -g typescript-language-server typescript && \
    pip3 install python-lsp-server && \
    go install golang.org/x/tools/gopls@latest && \
    cargo install rust-analyzer

# Install ZLS (Zig Language Server)
ARG ZLS_VERSION=0.14.0
RUN curl -L "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-x86_64-linux.tar.xz" | tar -xJ -C /usr/local/bin

# Copy the built binary
COPY --from=zig-builder /build/zig-out/bin/lsp-mcp-server /usr/local/bin/

# Create non-root user
RUN addgroup -g 1000 lspuser && \
    adduser -u 1000 -G lspuser -s /bin/sh -D lspuser

USER lspuser
WORKDIR /home/lspuser

# Expose MCP port (not really needed for stdio, but good for documentation)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD lsp-mcp-server --help || exit 1

ENTRYPOINT ["lsp-mcp-server"]
CMD ["--help"]