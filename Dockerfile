ARG PYTHON_VERSION=3.12
# Build version to invalidate cache when code changes
ARG BUILD_VERSION=20260126-v17

FROM python:$PYTHON_VERSION-slim AS build

ENV PYTHONUNBUFFERED=1

WORKDIR /code

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential curl unzip gcc python3-dev libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Xray from official XTLS repository
ARG XRAY_VERSION=latest
RUN set -ex \
    && if [ "$XRAY_VERSION" = "latest" ]; then \
        XRAY_VERSION=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4); \
    fi \
    && echo "Xray version: ${XRAY_VERSION}" \
    && test -n "$XRAY_VERSION" && echo "$XRAY_VERSION" | grep -qE '^v[0-9]' || { echo "ERROR: Failed to detect Xray version (got: $XRAY_VERSION)"; exit 1; } \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) XRAY_ARCH="64" ;; \
        aarch64) XRAY_ARCH="arm64-v8a" ;; \
        armv7l) XRAY_ARCH="arm32-v7a" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" \
    && unzip /tmp/xray.zip -d /tmp/xray \
    && mv /tmp/xray/xray /usr/local/bin/xray \
    && chmod +x /usr/local/bin/xray \
    && mkdir -p /usr/local/share/xray \
    && mv /tmp/xray/*.dat /usr/local/share/xray/ \
    && rm -rf /tmp/xray /tmp/xray.zip \
    && echo "Xray ${XRAY_VERSION} installed"

# Install Hysteria2
ARG HYSTERIA_VERSION=latest
RUN set -ex \
    && if [ "$HYSTERIA_VERSION" = "latest" ]; then \
        HYSTERIA_VERSION=$(curl -sL https://api.github.com/repos/apernet/hysteria/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4); \
    fi \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) HY_ARCH="amd64" ;; \
        aarch64) HY_ARCH="arm64" ;; \
        armv7l) HY_ARCH="armv7" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -L -o /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/hysteria-linux-${HY_ARCH}" \
    && chmod +x /usr/local/bin/hysteria \
    && echo "Hysteria2 ${HYSTERIA_VERSION} installed"

# Install TUIC server
ARG TUIC_VERSION=latest
RUN set -ex \
    && if [ "$TUIC_VERSION" = "latest" ]; then \
        TUIC_VERSION=$(curl -sL https://api.github.com/repos/Itsusinn/tuic/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4); \
    fi \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) TUIC_ARCH="x86_64" ;; \
        aarch64) TUIC_ARCH="aarch64" ;; \
        armv7l) TUIC_ARCH="armv7" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -L -o /usr/local/bin/tuic-server "https://github.com/Itsusinn/tuic/releases/download/${TUIC_VERSION}/tuic-server-${TUIC_ARCH}-linux" \
    && chmod +x /usr/local/bin/tuic-server \
    && echo "TUIC ${TUIC_VERSION} installed"

# Install Juicity server
ARG JUICITY_VERSION=latest
RUN set -ex \
    && if [ "$JUICITY_VERSION" = "latest" ]; then \
        JUICITY_VERSION=$(curl -sL https://api.github.com/repos/juicity/juicity/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4); \
    fi \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) JUICITY_ARCH="x86_64" ;; \
        aarch64) JUICITY_ARCH="arm64" ;; \
        armv7l) JUICITY_ARCH="armv7" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -L -o /tmp/juicity.zip "https://github.com/juicity/juicity/releases/download/${JUICITY_VERSION}/juicity-linux-${JUICITY_ARCH}.zip" \
    && unzip -j /tmp/juicity.zip juicity-server -d /usr/local/bin \
    && chmod +x /usr/local/bin/juicity-server \
    && rm /tmp/juicity.zip \
    && echo "Juicity ${JUICITY_VERSION} installed"

COPY ./requirements.txt /code/
RUN pip install --no-cache-dir --upgrade pip setuptools \
    && pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Save the actual site-packages path for the next stage
RUN python -c "import site; print(site.getsitepackages()[0])" > /tmp/site_packages_path

FROM python:$PYTHON_VERSION-slim

WORKDIR /code

# Install runtime dependencies (libpq for PostgreSQL, openssl for certs, certbot for Let's Encrypt)
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 openssl certbot cron \
    && rm -rf /var/lib/apt/lists/*

# Copy Python packages using the correct path
COPY --from=build /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=build /usr/local/bin /usr/local/bin
COPY --from=build /usr/local/share/xray /usr/local/share/xray
COPY --from=build /usr/local/bin/xray /usr/local/bin/xray

# Force cache invalidation for code changes
ARG BUILD_VERSION
RUN echo "Build: ${BUILD_VERSION}"

COPY . /code

# Expose ports: Uvicorn(8000), Xray(various), Hysteria2(4443/udp), TUIC(18443/udp), Juicity(23182/udp)
EXPOSE 3000/tcp \
    2053/tcp 2083/tcp 2087/tcp 2096/tcp \
    2082/tcp 2086/tcp 2084/tcp 2085/tcp \
    1080/tcp 1080/udp \
    4443/udp 18443/udp 23182/udp

# Create marzban-cli symlink
RUN ln -s /code/marzban-cli.py /usr/bin/marzban-cli \
    && chmod +x /usr/bin/marzban-cli

# Startup script that generates certs and Reality keys if needed
COPY <<'EOF' /code/entrypoint.sh
#!/bin/bash
set -e

CERT_DIR="/var/lib/marzban/certs"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"
XRAY_CONFIG="/code/xray_config.json"

mkdir -p "$CERT_DIR"

# Самоподписант нужен ТОЛЬКО Xray inbounds (файлы на диске).
# Для uvicorn/dashboard он НЕ используется — HTTPS терминирует Traefik снаружи.
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Generating self-signed TLS certificate for Xray inbounds..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=marzban" >/dev/null 2>&1
fi

# ВАЖНО: НЕ экспортируем UVICORN_SSL_CERTFILE/KEYFILE.
# Иначе uvicorn включает TLS внутри контейнера, а Traefik ходит по HTTP -> 502.
export UVICORN_HOST="${UVICORN_HOST:-0.0.0.0}"
export UVICORN_PORT="${UVICORN_PORT:-3000}"

echo "========================================"
echo "Marzban startup config:"
echo "  UVICORN_HOST=$UVICORN_HOST"
echo "  UVICORN_PORT=$UVICORN_PORT"
echo "  (backend = HTTP, TLS terminated by Traefik)"
echo "========================================"

# Reality ключи
SAVED_PRIVATE_KEY_FILE="$CERT_DIR/reality_private_key.txt"
SAVED_PUBLIC_KEY_FILE="$CERT_DIR/reality_public_key.txt"

if [ -f "$XRAY_CONFIG" ] && grep -q "YOUR_PRIVATE_KEY_HERE" "$XRAY_CONFIG"; then
    if [ -f "$SAVED_PRIVATE_KEY_FILE" ] && [ -f "$SAVED_PUBLIC_KEY_FILE" ]; then
        echo "Restoring saved Reality keys..."
        PRIVATE_KEY=$(cat "$SAVED_PRIVATE_KEY_FILE")
        PUBLIC_KEY=$(cat "$SAVED_PUBLIC_KEY_FILE")
        sed -i "s/YOUR_PRIVATE_KEY_HERE/$PRIVATE_KEY/g" "$XRAY_CONFIG"
        echo "Reality keys restored. Public key: $PUBLIC_KEY"
    else
        echo "Generating new Reality keys..."
        KEYS=$(xray x25519 2>&1) || true
        PRIVATE_KEY=$(echo "$KEYS" | grep -i "private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
        PUBLIC_KEY=$(echo "$KEYS" | sed -n '2p' | awk -F': ' '{print $2}' | tr -d '[:space:]')
        if [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ]; then
            sed -i "s/YOUR_PRIVATE_KEY_HERE/$PRIVATE_KEY/g" "$XRAY_CONFIG"
            echo "$PRIVATE_KEY" > "$SAVED_PRIVATE_KEY_FILE"
            echo "$PUBLIC_KEY" > "$SAVED_PUBLIC_KEY_FILE"
            echo "=========================================="
            echo "Reality Public Key (для клиентов): $PUBLIC_KEY"
            echo "=========================================="
        else
            echo "ERROR: Failed to generate Reality keys!"
        fi
    fi
fi

# Hysteria2 конфиг
if [ "${HYSTERIA2_ENABLED:-true}" = "true" ] && command -v hysteria >/dev/null 2>&1; then
    if [ -f /code/scripts/generate_hysteria2_config.py ]; then
        echo "Generating Hysteria2 config..."
        python /code/scripts/generate_hysteria2_config.py 2>&1 || echo "WARNING: Failed to generate Hysteria2 config"
    fi
fi

echo "Running alembic migrations..."
alembic upgrade head

# Запуск БЕЗ SSL-флагов и БЕЗ SSL-env -> чистый HTTP на 0.0.0.0
echo "Starting Uvicorn on http://$UVICORN_HOST:$UVICORN_PORT ..."
exec uvicorn main:app --host "$UVICORN_HOST" --port "$UVICORN_PORT"
EOF

RUN chmod +x /code/entrypoint.sh
CMD ["/code/entrypoint.sh"]
