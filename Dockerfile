# Neovim + Netshoot Debug Container
# Ubuntu-based for full plugin compatibility (blink.cmp, Treesitter, Mason LSPs)
#
# Build locally: docker build -t netshoot-nvim:latest .
# Build via GitHub Actions: Trigger workflow manually
# Run: docker run -it --rm netshoot-nvim:latest

FROM ubuntu:22.04

LABEL maintainer="Shah Islam"
LABEL description="Debug container with Neovim, networking tools, and DevOps LSPs"

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Core utilities + netshoot networking tools
# Retry logic for apt update to handle transient mirror sync issues
RUN for i in 1 2 3; do apt-get update && break || { echo "apt-get update failed, retry $i/3..."; sleep 15; }; done && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl wget git unzip sudo coreutils file locales ca-certificates \
    build-essential \
    tcpdump net-tools dnsutils iputils-ping traceroute \
    nmap netcat-openbsd socat iperf3 mtr-tiny \
    iproute2 iptables conntrack ethtool bridge-utils \
    httpie jq openssh-client openssl \
    tshark ngrep iftop iptraf-ng \
    strace ltrace \
    fping ipset nftables tcptraceroute \
    python3 python3-scapy \
    zsh bash-completion \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install fzf from GitHub releases (Ubuntu's version is too old for fzf-lua)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then FZF_ARCH="linux_amd64"; else FZF_ARCH="linux_arm64"; fi && \
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v0.56.3/fzf-0.56.3-${FZF_ARCH}.tar.gz" -o /tmp/fzf.tar.gz && \
    tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin && \
    rm /tmp/fzf.tar.gz

# Install zoxide from GitHub releases (not in Ubuntu repos, required for fzf-lua zoxide picker)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then ZOXIDE_ARCH="x86_64"; else ZOXIDE_ARCH="aarch64"; fi && \
    curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.8/zoxide-0.9.8-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz" -o /tmp/zoxide.tar.gz && \
    tar -xzf /tmp/zoxide.tar.gz -C /usr/local/bin zoxide && \
    rm /tmp/zoxide.tar.gz

# Install grpcurl (gRPC testing)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then GRPC_ARCH="x86_64"; else GRPC_ARCH="arm64"; fi && \
    curl -fsSL "https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_${GRPC_ARCH}.tar.gz" -o /tmp/grpcurl.tar.gz && \
    tar -xzf /tmp/grpcurl.tar.gz -C /usr/local/bin grpcurl && \
    rm /tmp/grpcurl.tar.gz

# Install fortio (load testing)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/fortio/fortio/releases/download/v1.68.0/fortio-linux_${ARCH}-1.68.0.tgz" -o /tmp/fortio.tar.gz && \
    tar -xzf /tmp/fortio.tar.gz -C /usr/local/bin --strip-components=2 usr/bin/fortio && \
    rm /tmp/fortio.tar.gz

# Install ctop (container top)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then CTOP_ARCH="amd64"; else CTOP_ARCH="arm64"; fi && \
    curl -fsSL "https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-${CTOP_ARCH}" -o /usr/local/bin/ctop && \
    chmod +x /usr/local/bin/ctop

# Install calicoctl (Calico CNI)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then CALICO_ARCH="amd64"; else CALICO_ARCH="arm64"; fi && \
    curl -fsSL "https://github.com/projectcalico/calico/releases/download/v3.29.1/calicoctl-linux-${CALICO_ARCH}" -o /usr/local/bin/calicoctl && \
    chmod +x /usr/local/bin/calicoctl

# Install termshark (TUI for wireshark)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then TS_ARCH="x64"; else TS_ARCH="arm64"; fi && \
    curl -fsSL "https://github.com/gcla/termshark/releases/download/v2.4.0/termshark_2.4.0_linux_${TS_ARCH}.tar.gz" -o /tmp/termshark.tar.gz && \
    tar -xzf /tmp/termshark.tar.gz --strip-components=1 -C /usr/local/bin termshark_2.4.0_linux_${TS_ARCH}/termshark && \
    rm /tmp/termshark.tar.gz

# Install fd-find and create symlink
RUN for i in 1 2 3; do apt-get update && break || { echo "apt-get update failed, retry $i/3..."; sleep 15; }; done && \
    apt-get install -y --no-install-recommends fd-find \
    && ln -s $(which fdfind) /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (LTS) for LSPs and plugins
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install yq (not in Ubuntu repos, install from binary)
# Detect architecture for correct binary
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Install Neovim (latest stable from GitHub releases)
# PPA version is too old, doesn't support statuscolumn (Neovim 0.9+)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then NVIM_ARCH="linux-x86_64"; else NVIM_ARCH="linux-arm64"; fi && \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/stable/nvim-${NVIM_ARCH}.tar.gz" -o /tmp/nvim.tar.gz && \
    tar -xzf /tmp/nvim.tar.gz -C /opt && \
    ln -s /opt/nvim-${NVIM_ARCH}/bin/nvim /usr/local/bin/nvim && \
    rm /tmp/nvim.tar.gz

# Configure locales
RUN locale-gen en_US.UTF-8 && dpkg-reconfigure locales
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Setup Neovim directories
RUN mkdir -p /root/.config/nvim /root/.local/share/nvim /root/.cache/nvim

# Copy Neovim config (from build context - repo root)
COPY --chown=root:root . /root/.config/nvim

# Set environment variables
ENV TERM=xterm-256color
ENV EDITOR=nvim
ENV VISUAL=nvim

# Bootstrap lazy.nvim and install all plugins
RUN nvim --headless "+Lazy! sync" +qa 2>&1 || echo "Plugin sync completed"

# Fix blink.cmp/blink.pairs binaries for correct architecture
# Lazy sync may download wrong arch when cross-compiling (e.g., building on Mac for amd64)
# We remove any auto-downloaded binaries and checksums, then download correct ones
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then RUST_ARCH="x86_64-unknown-linux-gnu"; else RUST_ARCH="aarch64-unknown-linux-gnu"; fi && \
    # Remove any auto-downloaded binaries and checksums from Lazy sync
    rm -rf /root/.local/share/nvim/lazy/blink.pairs/target 2>/dev/null || true && \
    rm -rf /root/.local/share/nvim/lazy/blink.cmp/target 2>/dev/null || true && \
    # Download correct architecture binaries
    mkdir -p /root/.local/share/nvim/lazy/blink.pairs/target/release && \
    curl -fsSL "https://github.com/saghen/blink.pairs/releases/download/v0.4.1/${RUST_ARCH}.so" \
        -o /root/.local/share/nvim/lazy/blink.pairs/target/release/libblink_pairs.so && \
    mkdir -p /root/.local/share/nvim/lazy/blink.cmp/target/release && \
    curl -fsSL "https://github.com/saghen/blink.cmp/releases/download/v1.8.0/${RUST_ARCH}.so" \
        -o /root/.local/share/nvim/lazy/blink.cmp/target/release/libblink_cmp_fuzzy.so && \
    echo "Blink binaries downloaded for ${ARCH}"

# Install Treesitter parsers for DevOps languages
# Use timeout to prevent hanging, parsers will install on first use if this fails
RUN timeout 120 nvim --headless "+TSInstall yaml json dockerfile bash lua markdown toml" "+sleep 60" +qa 2>&1 || echo "TSInstall timed out, parsers will install on first use"

# Install LSPs via Mason (DevOps focused)
# Note: This requires Mason to be configured in the Neovim config
# Use timeout to prevent hanging, LSPs will install on first use if this fails
RUN timeout 180 nvim --headless \
    -c "MasonInstall yaml-language-server json-lsp dockerfile-language-server-nodejs bash-language-server lua-language-server" \
    -c "sleep 60" \
    -c "qall" 2>&1 || echo "MasonInstall timed out, LSPs will install on first use"

# Verify installation
RUN nvim --version && echo "Neovim installed successfully"

# Set working directory
WORKDIR /root

# Default shell
CMD ["/bin/bash"]
