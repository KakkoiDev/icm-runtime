#!/bin/sh
# ICM tool: synthesize research notes from sources
# Input:  expects output/search-results.md and output/fetched-pages/ to exist
# Output: writes synthesized notes to stdout
set -eu
stage_dir="$1"  # path to stage dir with output/
echo "TOOL: read $stage_dir/output/search-results.md and fetched pages"
echo "TOOL: synthesize into structured notes following the stage contract format"
echo "TOOL: write result to $stage_dir/output/research-notes.md"
