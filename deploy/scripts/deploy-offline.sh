#!/bin/bash
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DEPLOY_DIR")"
CONFIG_FILE="$DEPLOY_DIR/config/deploy.conf"
LOG_FILE="$DEPLOY_DIR/logs/deploy.log"
GENERATED_COMPOSE_FILE="$DEPLOY_DIR/docker-compose-deployed.yml"

# Load Config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Initialize Log
mkdir -p "$(dirname "$LOG_FILE")"
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] [$$] $*" | tee -a "$LOG_FILE"
}

# Check Docker
if ! command -v docker &> /dev/null; then
    log "ERROR" "Docker is not installed."
    exit 1
fi

# Determine docker compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# 1. Load Images
log "INFO" "Checking and loading images..."
if [ -d "$DEPLOY_DIR/archives" ]; then
    count=0
    for TAR_FILE in "$DEPLOY_DIR/archives"/*.tar; do
        [ -e "$TAR_FILE" ] || continue
        count=$((count+1))
        log "INFO" "Loading $TAR_FILE..."
        docker load -i "$TAR_FILE"
    done
    if [ $count -eq 0 ]; then
        log "WARN" "No .tar files found in archives/."
    fi
else
    log "WARN" "No archives directory found at $DEPLOY_DIR/archives."
fi

# 2. Generate Docker Compose File
log "INFO" "Generating deployment configuration..."
cd "$PROJECT_ROOT"

# Ensure .env exists (create empty if not)
if [ ! -f .env ]; then
    log "WARN" ".env not found, creating empty .env"
    touch .env
fi

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
log "INFO" "Using compose file: $COMPOSE_FILE"

# Dump config
# This resolves variables and extends files, producing a single valid YAML
if ! $DOCKER_COMPOSE -f "$COMPOSE_FILE" config > "$GENERATED_COMPOSE_FILE"; then
    log "ERROR" "Failed to generate docker compose config."
    exit 1
fi

# 3. Modify Configuration (Container Names, Ports, Networks)
log "INFO" "Applying configuration overrides..."
# We use awk to inject/modify the configuration
# Strategy:
# - Prepend PREFIX to container_name
# - Add PORT_OFFSET to published ports
# - Modify network driver if needed (not implemented fully for 'driver:', assuming default or bridge is fine, 
#   but user asked for NETWORK_DRIVER injection. We can try to replace 'driver: bridge' with 'driver: $NETWORK_DRIVER')

awk -v offset="${PORT_OFFSET:-0}" -v prefix="${CONTAINER_PREFIX:-yuxi}" -v net_driver="${NETWORK_DRIVER:-bridge}" '
{
    # Replace container_name
    if ($0 ~ /container_name:/) {
        match($0, /container_name: (.*)/, arr)
        original_name = arr[1]
        gsub(/["\047]/, "", original_name)
        # Avoid double prefixing if run multiple times
        if (index(original_name, prefix) != 1) {
             sub(/container_name: .*/, "container_name: " prefix "-" original_name)
        }
    }
    
    # Port Offset
    if ($0 ~ /published:/) {
        match($0, /published: "?([0-9]+)"?/, arr)
        port = arr[1]
        if (port != "") {
            new_port = port + offset
            sub(/published: "?[0-9]+"?/, "published: " new_port)
        }
    }
    
    # Network Driver (Simple replacement for "driver: bridge")
    if ($0 ~ /driver: bridge/) {
        sub(/driver: bridge/, "driver: " net_driver)
    }

    print $0
}' "$GENERATED_COMPOSE_FILE" > "${GENERATED_COMPOSE_FILE}.tmp" && mv "${GENERATED_COMPOSE_FILE}.tmp" "$GENERATED_COMPOSE_FILE"

log "INFO" "Generated deployment compose file at $GENERATED_COMPOSE_FILE"

# 4. Start Services
log "INFO" "Starting stack '$STACK_NAME'..."
$DOCKER_COMPOSE -p "$STACK_NAME" -f "$GENERATED_COMPOSE_FILE" up -d

# 5. Health Check
log "INFO" "Waiting for health checks..."
MAX_RETRIES=30
for ((i=1; i<=MAX_RETRIES; i++)); do
    # Check status
    OUTPUT=$($DOCKER_COMPOSE -p "$STACK_NAME" -f "$GENERATED_COMPOSE_FILE" ps)
    
    if echo "$OUTPUT" | grep -q "(unhealthy)"; then
        log "WARN" "Some services are unhealthy. Retrying ($i/$MAX_RETRIES)..."
    elif ! echo "$OUTPUT" | grep -q "Up"; then
        log "WARN" "Services not up yet. Retrying ($i/$MAX_RETRIES)..."
    else
        # Success condition: All services that should be up are up
        log "INFO" "Services seem stable."
        break
    fi
    
    if [ $i -eq $MAX_RETRIES ]; then
        log "ERROR" "Health check timeout. Initiating rollback..."
        # 6. Rollback
        $DOCKER_COMPOSE -p "$STACK_NAME" -f "$GENERATED_COMPOSE_FILE" down
        log "INFO" "Rollback completed."
        exit 1
    fi
    sleep 5
done

# Output Info
log "INFO" "Deployment successful."
$DOCKER_COMPOSE -p "$STACK_NAME" -f "$GENERATED_COMPOSE_FILE" ps
log "INFO" "Logs available at $LOG_FILE"
