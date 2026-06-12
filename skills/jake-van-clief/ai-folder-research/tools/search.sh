#!/bin/sh
# ICM tool: search for research topics via web search
# Usage: search.sh "<query>"
# Output: structured JSON with results on stdout
set -eu
query="$1"
# This script is called by the AI via the search_web tool.
# It exists as a placeholder for the contract to reference;
# the actual search is done by the AI calling search_web.
# Output format expected by downstream stages:
echo "{\"query\": \"$query\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
echo "TOOL: call search_web with query=\"$query\", capture results to output/search-results.md"
