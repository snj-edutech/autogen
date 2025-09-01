# ============================================================
# FROM python:3.10-slim
# WORKDIR /code
# RUN pip install -U gunicorn autogenstudio
# # Create a non-root user
# RUN useradd -m -u 1000 user
# USER user
# ENV HOME=/home/user \
#     PATH=/home/user/.local/bin:$PATH \
#     AUTOGENSTUDIO_APPDIR=/home/user/app
# WORKDIR $HOME/app
# COPY --chown=user . $HOME/app
# CMD gunicorn -w $((2 * $(getconf _NPROCESSORS_ONLN) + 1)) --timeout 12600 -k uvicorn.workers.UvicornWorker autogenstudio.web.app:app --bind "0.0.0.0:8081"
# ============================================================
# AutoGen Studio dev image (uvicorn + editable workspace + hot reload)
#
# PREREQUISITES (host):
#   cd /path/to/work/folder   # e.g., /home/soulloan/work
#   apt-get install git-lfs
#   git lfs install
#   git clone https://github.com/microsoft/autogen.git   # or: https://github.com/snj-edutech/autogen.git
#   git lfs fetch --all
#   git lfs install
#   git lfs checkout
#
# Build:
#   docker build --build-arg PORT=8080 -t THISDOCKERIMAGE:1.0 .
#
# Run (dind needs --privileged):
#   docker run --name autogen \
#     --privileged \
#     -p 14080:8080/tcp -d \
#     -v ~/.ssh:/root/.ssh \
#     -v /home/soulloan/work/auto-gen-app-data:/work/auto-gen-app-data \
#     -v /home/soulloan/work/auto-gen-app-data/var/lib/docker:/var/lib/docker \
#     -v /home/soulloan/work/autogen:/work/autogen \
#     --restart always \
#     -e AUTOGENSTUDIO_APPDIR=/work/auto-gen-app-data \
#     -e AUTOGENSTUDIO_DATABASE_URI=sqlite:////work/auto-gen-app-data/database.sqlite \
#     -e AUTOGENSTUDIO_HOST=0.0.0.0 \
#     -e PORT=8080 \
#     -e AUTOGENSTUDIO_PORT=8080 \
#     -e AUTOGENSTUDIO_AUTH_CONFIG=/work/.auth.yaml \
#     -e AUTOGENSTUDIO_API_DOCS=True \
#     -e AUTOGENSTUDIO_UPGRADE_DATABASE=1 \
#     # (optional) -e AUTOGENSTUDIO_WORKERS=4  # use multi-workers instead of reload
#     THISDOCKERIMAGE:1.0
# ============================================================

FROM python:3.12

# ---------- Build-time port (for EXPOSE metadata) ----------
ARG PORT=8080
ARG openai_api_key
ENV PORT=${PORT}

ENV DEBIAN_FRONTEND=noninteractive

# --- base tools ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release \
    git git-lfs openssh-client \
    build-essential rsync procps bash coreutils iproute2 iptables uidmap pigz apt-transport-https supervisor\
    && rm -rf /var/lib/apt/lists/*

# Workdir
WORKDIR /work/autogen

# Copy the repo contents
COPY . .

# ---------- App defaults (overridable at runtime) ----------
ENV AUTOGENSTUDIO_APPDIR=/work/auto-gen-app-data \
#    AUTOGENSTUDIO_DATABASE_URI=sqlite:////work/auto-gen-app-data/database.sqlite \
    AUTOGENSTUDIO_HOST=0.0.0.0 \
    AUTOGENSTUDIO_PORT=${PORT} \
#    AUTOGENSTUDIO_AUTH_CONFIG=/work/.auth.yaml \
    AUTOGENSTUDIO_API_DOCS=True \
    AUTOGENSTUDIO_UPGRADE_DATABASE=1 \
    OPENAI_API_KEY=${openai_api_key}

# ---------- DOCKER INSTALLATION ----------
# Add Docker's official GPG key
RUN install -m 0755 -d /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
RUN chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
RUN echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
RUN apt-get update && apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Configure supervisor
RUN mkdir -p /var/log/supervisor && \
    printf '%s\n' \
    '[supervisord]' \
    'nodaemon=false' \
    'logfile=/var/log/supervisor/supervisord.log' \
    'pidfile=/var/run/supervisord.pid' \
    '' \
    '[program:dockerd]' \
    'command=/usr/bin/dockerd --host=unix:///var/run/docker.sock --storage-driver=vfs' \
    'autostart=true' \
    'autorestart=true' \
    'stdout_logfile=/var/log/supervisor/dockerd.log' \
    'stderr_logfile=/var/log/supervisor/dockerd.err' \
    'startsecs=2' \
    'stopwaitsecs=10' \
    > /etc/supervisor/conf.d/dockerd.conf

# Install Python Docker SDK
RUN pip install docker

# Create entrypoint script with Autogen integration
RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    '' \
    '# Start supervisor in background' \
    'echo "Starting supervisor to manage Docker daemon..."' \
    '/usr/bin/supervisord -c /etc/supervisor/supervisord.conf' \
    '' \
    '# Wait for Docker daemon to be ready' \
    'echo "Waiting for Docker daemon to start..."' \
    'DOCKER_READY=false' \
    'for i in {1..30}; do' \
    '    if docker info >/dev/null 2>&1; then' \
    '        echo "✓ Docker daemon is ready!"' \
    '        docker version --format "Docker version: {{.Server.Version}}"' \
    '        docker info --format "Storage Driver: {{.Driver}}"' \
    '        DOCKER_READY=true' \
    '        break' \
    '    fi' \
    '    echo -n "."' \
    '    sleep 1' \
    'done' \
    'echo ""' \
    '' \
    '# Check if Docker started successfully' \
    'if [ "$DOCKER_READY" != "true" ]; then' \
    '    echo "✗ Docker daemon failed to start"' \
    '    echo "Checking supervisor status:"' \
    '    supervisorctl status' \
    '    echo "Docker daemon error log:"' \
    '    tail -50 /var/log/supervisor/dockerd.err' \
    '    exit 1' \
    'fi' \
    '' \
    'echo ""' \
    'echo "==============================================="' \
    'echo "Starting Autogen Studio..."' \
    'echo "==============================================="' \
    '' \
    '# Execute autogen entry point' \
    'exec /bin/bash -lc "/work/autogen/python/packages/autogen-studio/entrypoint.sh"' \
    > /entrypoint.sh && chmod +x /entrypoint.sh

# --- Node via NVM (for Gatsby UI build) ---
ENV NVM_DIR=/root/.nvm NODE_MAJOR=22
RUN bash -lc 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
# Preinstall Node & global CLIs (gatsby, yarn)
RUN bash -lc '. "$NVM_DIR/nvm.sh" && nvm install $NODE_MAJOR && nvm alias default $NODE_MAJOR && npm i -g gatsby-cli yarn'

# --- Install uv (fast Python package manager) ---
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# --- Python runtime niceties ---
ENV PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

# ---------- Expose build-time PORT (metadata) ----------
EXPOSE ${PORT}/tcp

# --- Docker Entrypoint ---
ENTRYPOINT ["/entrypoint.sh"]