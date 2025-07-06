#!/bin/bash

# Configuration
TOTAL_REQUESTS=5000
URL="http://localhost:8080/health"
CONCURRENT_REQUESTS=10

echo "Starting load test with $TOTAL_REQUESTS requests..."
echo "Target URL: $URL"

# Function to make a single request and capture response time
make_request() {
    curl -s -w "%{time_total}\n" -o /dev/null "$URL"
}

# Initialize counters
completed=0
start_time=$(date +%s)

# Create a temporary file to store response times
temp_file=$(mktemp)

# Make requests in batches
for ((i=1; i<=$TOTAL_REQUESTS; i+=CONCURRENT_REQUESTS)); do
    # Launch concurrent requests
    for ((j=0; j<CONCURRENT_REQUESTS && i+j<=$TOTAL_REQUESTS; j++)); do
        make_request >> "$temp_file" &
    done
    
    # Wait for this batch to complete
    wait
    
    # Update completed count
    completed=$((completed + CONCURRENT_REQUESTS))
    if [ $completed -gt $TOTAL_REQUESTS ]; then
        completed=$TOTAL_REQUESTS
    fi
    
    # Show progress
    echo -ne "\rCompleted: $completed/$TOTAL_REQUESTS requests"
done

end_time=$(date +%s)
duration=$((end_time - start_time))

echo -e "\n\nLoad test completed!"
echo "Total time: $duration seconds"

# Calculate statistics
if [ -f "$temp_file" ]; then
    echo -e "\nResponse time statistics (seconds):"
    echo "Average: $(awk '{ total += $1 } END { print total/NR }' "$temp_file")"
    echo "Min: $(sort -n "$temp_file" | head -n1)"
    echo "Max: $(sort -n "$temp_file" | tail -n1)"
    rm "$temp_file"
fi 