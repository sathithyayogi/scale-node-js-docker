#!/bin/bash

# Configuration
SERVICE_NAME="app"
MIN_CPU=0.25        # Minimum CPU cores
MAX_CPU=2.0         # Maximum CPU cores
MIN_MEMORY=128      # Minimum memory in MB
MAX_MEMORY=1024     # Maximum memory in MB
CPU_STEP=0.25       # CPU increment/decrement step
MEMORY_STEP=128     # Memory increment/decrement step in MB
CHECK_INTERVAL=30   # Check interval in seconds

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${1}"
}

# Get container stats
get_container_stats() {
    local container_id=$1
    
    # Get CPU percentage (remove % sign and convert to number)
    CPU_USAGE=$(docker stats --no-stream --format "{{.CPUPerc}}" "$container_id" | sed 's/%//')
    
    # Get memory usage and limit
    MEMORY_STATS=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id")
    MEMORY_USAGE=$(echo "$MEMORY_STATS" | awk '{print $1}' | sed 's/MiB//')
    MEMORY_LIMIT=$(echo "$MEMORY_STATS" | awk '{print $3}' | sed 's/MiB//')
    
    # Calculate memory percentage
    MEMORY_PERCENT=$(awk "BEGIN {print ($MEMORY_USAGE/$MEMORY_LIMIT)*100}")
}

# Update container resources
update_resources() {
    local container_id=$1
    local new_cpu=$2
    local new_memory=$3
    
    log "${YELLOW}Updating container $container_id resources:${NC}"
    log "CPU: $current_cpu -> $new_cpu cores"
    log "Memory: $current_memory -> $new_memory MB"
    
    # Update container with new resources
    docker update --cpus="$new_cpu" --memory="${new_memory}m" "$container_id"
    
    if [ $? -eq 0 ]; then
        log "${GREEN}Successfully updated resources${NC}"
    else
        log "${RED}Failed to update resources${NC}"
    fi
}

# Main monitoring loop
while true; do
    # Get all container IDs for the service
    CONTAINER_IDS=$(docker compose ps -q $SERVICE_NAME)
    
    for CONTAINER_ID in $CONTAINER_IDS; do
        log "\nChecking container: $CONTAINER_ID"
        
        # Get current resource limits
        current_cpu=$(docker inspect --format '{{.HostConfig.NanoCpus}}' "$CONTAINER_ID")
        current_cpu=$(echo "scale=2; $current_cpu/1000000000" | bc)
        current_memory=$(docker inspect --format '{{.HostConfig.Memory}}' "$CONTAINER_ID")
        current_memory=$((current_memory/1024/1024)) # Convert to MB
        
        # Get current usage
        get_container_stats "$CONTAINER_ID"
        
        log "Current Usage - CPU: ${CPU_USAGE}%, Memory: ${MEMORY_PERCENT}%"
        log "Current Limits - CPU: ${current_cpu} cores, Memory: ${current_memory}MB"
        
        # Calculate new resources based on usage
        new_cpu=$current_cpu
        new_memory=$current_memory
        
        # CPU Scaling
        if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
            # Scale up CPU if usage is high
            new_cpu=$(echo "scale=2; $current_cpu + $CPU_STEP" | bc)
            if (( $(echo "$new_cpu > $MAX_CPU" | bc -l) )); then
                new_cpu=$MAX_CPU
            fi
        elif (( $(echo "$CPU_USAGE < 30" | bc -l) )); then
            # Scale down CPU if usage is low
            new_cpu=$(echo "scale=2; $current_cpu - $CPU_STEP" | bc)
            if (( $(echo "$new_cpu < $MIN_CPU" | bc -l) )); then
                new_cpu=$MIN_CPU
            fi
        fi
        
        # Memory Scaling
        if (( $(echo "$MEMORY_PERCENT > 80" | bc -l) )); then
            # Scale up memory if usage is high
            new_memory=$((current_memory + MEMORY_STEP))
            if [ $new_memory -gt $MAX_MEMORY ]; then
                new_memory=$MAX_MEMORY
            fi
        elif (( $(echo "$MEMORY_PERCENT < 30" | bc -l) )); then
            # Scale down memory if usage is low
            new_memory=$((current_memory - MEMORY_STEP))
            if [ $new_memory -lt $MIN_MEMORY ]; then
                new_memory=$MIN_MEMORY
            fi
        fi
        
        # Update resources if changes are needed
        if (( $(echo "$new_cpu != $current_cpu" | bc -l) )) || [ $new_memory -ne $current_memory ]; then
            update_resources "$CONTAINER_ID" "$new_cpu" "$new_memory"
        else
            log "${GREEN}No resource updates needed${NC}"
        fi
    done
    
    log "\nSleeping for $CHECK_INTERVAL seconds..."
    sleep $CHECK_INTERVAL
done 