FROM node:22-slim

# Install system dependencies including sudo
RUN apt-get update && apt-get install -y \
    curl \
    sudo \
    jq \
    git \
    procps \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Install qwen-code globally and verify
RUN npm install -g @qwen-code/qwen-code && \
    which qwen && \
    echo "✓ qwen command installed at: $(which qwen)"

# Create qwen user with passwordless sudo
RUN groupadd -g 1001 qwen && \
    useradd -m -s /bin/bash -u 1001 -g 1001 qwen && \
    echo "qwen ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/qwen && \
    chown -R qwen:qwen /home/qwen && \
    # Verify user was created successfully
    id qwen && \
    echo "✓ qwen user created successfully"

# Copy bridge
COPY src/bridge /bridge
WORKDIR /bridge
RUN npm install

# Setup workspace
WORKDIR /workspace

# Copy scripts
COPY scripts/entrypoint/docker-entrypoint.sh /usr/local/bin/
COPY scripts/entrypoint/docker-healthcheck.sh /usr/local/bin/
COPY scripts/entrypoint/qwen-wrapper.sh /usr/local/bin/
COPY scripts/bridge/bridge-health-check.sh /workspace/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    /usr/local/bin/docker-healthcheck.sh \
    /usr/local/bin/qwen-wrapper.sh \
    /workspace/bridge-health-check.sh

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD /usr/local/bin/docker-healthcheck.sh

# Don't switch user here - let entrypoint run as root for setup

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]