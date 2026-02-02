#!/bin/bash
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DEPLOY_DIR")"
CONFIG_FILE="$DEPLOY_DIR/config/save.conf"
LOG_FILE="$DEPLOY_DIR/logs/save.log"
MANIFEST_FILE="$DEPLOY_DIR/archives/images_manifest.json"

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

# Auto-detect Project Name
if [ -z "${PROJECT_NAME:-}" ]; then
    PROJECT_NAME=$(basename "$PROJECT_ROOT")
    # Update config file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^PROJECT_NAME=\"\"/PROJECT_NAME=\"$PROJECT_NAME\"/" "$CONFIG_FILE"
    else
        sed -i "s/^PROJECT_NAME=\"\"/PROJECT_NAME=\"$PROJECT_NAME\"/" "$CONFIG_FILE"
    fi
    log "INFO" "Auto-detected PROJECT_NAME: $PROJECT_NAME"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    log "ERROR" "Docker is not installed."
    exit 1
fi

# Get Images from docker-compose
log "INFO" "Reading images from docker-compose..."
cd "$PROJECT_ROOT"

# Try docker compose or docker-compose
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# Check if .env exists, if not create empty to avoid config error
if [ ! -f .env ]; then
    log "WARN" ".env file not found in $PROJECT_ROOT. Creating an empty one to satisfy docker-compose."
    touch .env
fi

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
log "INFO" "Using compose file: $COMPOSE_FILE"

# Use docker compose config to resolve variables and get images
IMAGES=$($DOCKER_COMPOSE -f "$COMPOSE_FILE" config | grep 'image:' | awk '{print $2}' | sort | uniq) || {
    log "ERROR" "Failed to extract images from docker-compose config."
    exit 1
}

if [ -z "$IMAGES" ]; then
    log "ERROR" "No images found."
    exit 1
fi

log "INFO" "Found images: $(echo "$IMAGES" | tr '\n' ' ')"

# Prepare Archives Directory
mkdir -p "$EXPORT_ROOT"

# Check Disk Space (Simple check: need at least 5GB or warn)
# Handle Windows paths in df if needed (Git Bash usually maps /c/...)
if command -v df &> /dev/null; then
    AVAILABLE_SPACE=$(df -k "$EXPORT_ROOT" | awk 'NR==2 {print $4}' || echo "0")
    if [ "$AVAILABLE_SPACE" -gt 0 ] && [ "$AVAILABLE_SPACE" -lt 5242880 ]; then # 5GB in KB
        log "WARN" "Low disk space detected (< 5GB). Export might fail."
    fi
fi

# Initialize Manifest
echo "[]" > "$MANIFEST_FILE"

# Export Loop
for IMAGE in $IMAGES; do
    # Parse Image Name and Tag
    if [[ "$IMAGE" == *":"* ]]; then
        IMG_NAME=$(echo "$IMAGE" | cut -d: -f1)
        IMG_TAG=$(echo "$IMAGE" | cut -d: -f2)
    else
        IMG_NAME="$IMAGE"
        IMG_TAG="latest"
    fi

    # Rename Logic: yuxi- -> graph-
    # You can customize this replacement logic
    ORIGINAL_IMAGE="$IMAGE"
    if [[ "$IMG_NAME" == yuxi-* ]]; then
        NEW_IMG_NAME="graph-${IMG_NAME#yuxi-}"
        NEW_IMAGE="${NEW_IMG_NAME}:${IMG_TAG}"
        log "INFO" "Renaming image: $IMAGE -> $NEW_IMAGE"
        
        # We need to ensure the original image exists before tagging
        # The pull logic below handles ORIGINAL_IMAGE
        # After pull/check, we will tag it.
    else
        NEW_IMG_NAME="$IMG_NAME"
        NEW_IMAGE="$IMAGE"
    fi
    
    # Sanitize for filename
    SAFE_IMG_NAME=$(echo "$NEW_IMG_NAME" | tr '/:' '_')
    SAFE_TAG=$(echo "$IMG_TAG" | tr '/:' '_')
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    
    # Format Filename
    FILENAME=$(echo "$IMAGE_PACKAGE_NAME_FMT" | sed \
        -e "s/{PROJECT_NAME}/$PROJECT_NAME/g" \
        -e "s/{IMAGE_NAME}/$SAFE_IMG_NAME/g" \
        -e "s/{TAG}/$SAFE_TAG/g" \
        -e "s/{TIMESTAMP}/$TIMESTAMP/g")
        
    # Check if already exported (skip if exists)
    SEARCH_PATTERN="${PROJECT_NAME}_${SAFE_IMG_NAME}_${SAFE_TAG}_*.tar"
    # Find existing file (handling spaces if any, though not expected)
    EXISTING_FILE=$(find "$EXPORT_ROOT" -name "$SEARCH_PATTERN" -print -quit)
    
    if [ -n "$EXISTING_FILE" ]; then
        log "INFO" "Archive for $IMAGE already exists: $EXISTING_FILE. Skipping."
        continue
    fi
        
    FILEPATH="$EXPORT_ROOT/$FILENAME"
    
    log "INFO" "Processing $IMAGE -> $NEW_IMAGE -> $FILENAME"
    
    # Pull Logic
    set +e
    ATTEMPTS=0
    MAX_ATTEMPTS=2
    SUCCESS=false
    
    # Check if image exists locally first
    if docker image inspect "$IMAGE" &> /dev/null; then
        log "INFO" "Image $IMAGE found locally."
        SUCCESS=true
    else
        # Try to pull
        while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
            ATTEMPTS=$((ATTEMPTS+1))
            log "INFO" "Pulling $IMAGE (Attempt $ATTEMPTS/$MAX_ATTEMPTS)..."
            if docker pull "$IMAGE"; then
                SUCCESS=true
                break
            else
                log "WARN" "Failed to pull $IMAGE."
                sleep 2
            fi
        done
    fi
    
    if [ "$SUCCESS" = false ]; then
        log "ERROR" "Could not find or pull image $IMAGE. Skipping."
        continue
    fi
    
    # Apply Rename (Tagging)
    if [ "$IMAGE" != "$NEW_IMAGE" ]; then
        log "INFO" "Tagging $IMAGE as $NEW_IMAGE..."
        if ! docker tag "$IMAGE" "$NEW_IMAGE"; then
            log "ERROR" "Failed to tag $IMAGE as $NEW_IMAGE"
            continue
        fi
    fi
    set -e
    
    # Export (Save the NEW_IMAGE)
    log "INFO" "Saving $NEW_IMAGE to $FILEPATH..."
    if docker save -o "$FILEPATH" "$NEW_IMAGE"; then
        log "INFO" "Saved successfully."
        
        # Calculate MD5 and Size
        if command -v md5sum &> /dev/null; then
            MD5=$(md5sum "$FILEPATH" | awk '{print $1}')
        elif command -v md5 &> /dev/null; then
            MD5=$(md5 -q "$FILEPATH")
        else
            MD5="unknown"
        fi
        
        SIZE=$(wc -c < "$FILEPATH" | tr -d ' ')
        
        # Update Manifest (Using python for valid JSON)
        TMP_MANIFEST=$(mktemp)
        MANIFEST_UPDATED=false
        
        if command -v python3 &> /dev/null; then
             if python3 -c "import json, sys; 
try:
    with open('$MANIFEST_FILE', 'r') as f: data = json.load(f)
except: data = []
data.append({'image': '$NEW_IMAGE', 'original_image': '$IMAGE', 'file': '$FILENAME', 'md5': '$MD5', 'size': $SIZE})
print(json.dumps(data, indent=2))" > "$TMP_MANIFEST" 2>/dev/null; then
                mv "$TMP_MANIFEST" "$MANIFEST_FILE"
                MANIFEST_UPDATED=true
             fi
        fi
        
        if [ "$MANIFEST_UPDATED" = false ] && command -v python &> /dev/null; then
             if python -c "import json, sys; 
try:
    with open('$MANIFEST_FILE', 'r') as f: data = json.load(f)
except: data = []
data.append({'image': '$NEW_IMAGE', 'original_image': '$IMAGE', 'file': '$FILENAME', 'md5': '$MD5', 'size': $SIZE})
print(json.dumps(data, indent=2))" > "$TMP_MANIFEST" 2>/dev/null; then
                mv "$TMP_MANIFEST" "$MANIFEST_FILE"
                MANIFEST_UPDATED=true
             fi
        fi

        if [ "$MANIFEST_UPDATED" = false ]; then
            log "WARN" "Python execution failed or not found. Skipping manifest update for $IMAGE."
            rm -f "$TMP_MANIFEST"
        fi
        
    else
        log "ERROR" "Failed to save $IMAGE."
    fi
done

log "INFO" "Export completed."
