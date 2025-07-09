#!/bin/bash

# Configuration
SERVER_URL="${SERVER_URL:-http://localhost:8000}"
ENDPOINT="${SERVER_URL}/ai-chat"
DELAY_SECONDS="${DELAY_SECONDS:-3600}"  # Default 1 hour (3600 seconds) between requests
NUM_REQUESTS="${NUM_REQUESTS:-0}"    # 0 means infinite
TIMEOUT="${TIMEOUT:-30}"              # Request timeout in seconds

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Array of sample messages
MESSAGES=(
    "What is the weather like today?"
    "Tell me a joke"
    "How do I make a cup of coffee?"
    "What are the benefits of exercise?"
    "Explain quantum computing in simple terms"
    "What's the capital of France?"
    "How do I learn programming?"
    "What are some healthy breakfast ideas?"
    "Tell me about artificial intelligence"
    "How can I improve my productivity?"
    "What's the difference between a list and a tuple in Python?"
    "Explain the concept of microservices"
    "What are some best practices for API design?"
    "How does machine learning work?"
    "What's the purpose of unit testing?"
)

# Function to send a request
send_request() {
    local message="$1"
    local request_num="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${YELLOW}[$timestamp] Request #$request_num${NC}"
    echo "Message: \"$message\""
    
    # Use environment variables or defaults for headers
    local trace_id_header="${TRACE_ID:-Root=1-5759e988-bd862e3fe1be46a994272793;Parent=53995c3f42cd8ad8;Sampled=1}"
    
    echo "Using Trace ID: $trace_id_header"
    
    # Send request with timeout
    response=$(curl -s -X POST "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -H "X-Amzn-Trace-Id: $trace_id_header" \
        -d "{\"message\": \"$message\"}" \
        -m "$TIMEOUT" \
        -w "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}")
    
    # Extract HTTP status and response time
    http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    time_total=$(echo "$response" | grep "TIME_TOTAL:" | cut -d: -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS:/d' | sed '/TIME_TOTAL:/d')
    
    if [ "$http_status" = "200" ]; then
        echo -e "${GREEN}✓ Success${NC} (${time_total}s)"
        echo "Response: $body"
    else
        echo -e "${RED}✗ Error: HTTP $http_status${NC}"
        if [ -n "$body" ]; then
            echo "Response: $body"
        fi
    fi
    echo "---"
}

# Trap Ctrl+C to exit gracefully
trap 'echo -e "\n${YELLOW}Traffic generation stopped by user${NC}"; exit 0' INT

# Main execution
echo -e "${GREEN}Starting traffic generation to $ENDPOINT${NC}"
echo "Configuration:"
echo "  - Delay between requests: ${DELAY_SECONDS}s"
echo "  - Request timeout: ${TIMEOUT}s"
echo "  - Number of requests: ${NUM_REQUESTS} (0 = infinite)"
echo "  - Requests per minute: ~$((60 / DELAY_SECONDS))"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo "=================================="

# Check if server is reachable
echo "Checking server health..."
health_check=$(curl -s -o /dev/null -w "%{http_code}" "$SERVER_URL/health" -m 5)
if [ "$health_check" != "200" ]; then
    echo -e "${RED}Warning: Server health check failed (HTTP $health_check)${NC}"
    echo "Make sure the server is running at $SERVER_URL"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

count=0
start_time=$(date +%s)

while true; do
    # Select a random message
    random_index=$((RANDOM % ${#MESSAGES[@]}))
    message="${MESSAGES[$random_index]}"
    
    # Increment counter
    count=$((count + 1))
    
    # Send the request
    send_request "$message" "$count"
    
    # Check if we've reached the limit
    if [ "$NUM_REQUESTS" -gt 0 ] && [ "$count" -ge "$NUM_REQUESTS" ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo -e "${GREEN}Completed $count requests in ${duration}s${NC}"
        break
    fi
    
    # Show progress every 10 requests
    if [ $((count % 10)) -eq 0 ]; then
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        rate=$(echo "scale=2; $count / $elapsed * 60" | bc 2>/dev/null || echo "N/A")
        echo -e "${YELLOW}Progress: $count requests sent, Rate: ${rate} req/min${NC}"
    fi
    
    # Wait before next request
    sleep "$DELAY_SECONDS"
done