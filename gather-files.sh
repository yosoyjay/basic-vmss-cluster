#!/bin/bash
# Generic script to collect files from across multiple hosts

# Check for required arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <hostfile> <input-file> <output-file> [options]"
    echo "Options:"
    echo "  -n <num>   Number of lines to get from each host (default: 1)"
    echo "  -a         Get entire file instead of just the last lines"
    exit 1
fi

HOSTFILE="$1"
INPUT_FILE="$2"
OUTPUT_FILE="$3"
shift 3

# Default: get only the last line
LINE_COUNT=1
GET_ALL=false

# Parse additional options
while getopts "n:a" opt; do
    case $opt in
        n) LINE_COUNT="$OPTARG" ;;
        a) GET_ALL=true ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
done

# Check if hostfile exists
if [ ! -f "$HOSTFILE" ]; then
    echo "Error: Hostfile '$HOSTFILE' not found"
    exit 1
fi

# Clear the output file if it exists
> "$OUTPUT_FILE"

# Read each host from the hostfile
while read -r host; do
    # Skip empty lines and comments
    [[ -z "$host" || "$host" =~ ^# ]] && continue

    echo "Processing host: $host"

    # Get either the entire file or just the last N lines
    if [ "$GET_ALL" = true ]; then
        ssh "$host" "cat /var/log/node-health.log.status | sed \"s/^/$host /\"" >> "$OUTPUT_FILE" < /dev/null
    else
        ssh "$host" "tail -n $LINE_COUNT /var/log/node-health.log.status | sed \"s/^/$host /\"" >> "$OUTPUT_FILE" < /dev/null
    fi

done < "$HOSTFILE"

echo "Consolidated $INPUT_FILE collected across the cluster in $OUTPUT_FILE"