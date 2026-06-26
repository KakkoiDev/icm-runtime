#!/bin/sh
# Regenerate diagram SVGs from the .mmd sources. Run after editing a .mmd.
# Prefers a local mmdc (@mermaid-js/mermaid-cli); otherwise falls back to the
# Kroki API, which sends the diagram source to kroki.io (fine for these public
# architecture diagrams; do not use it for anything sensitive).
set -eu
cd "$(dirname "$0")"
# KROKI_URL lets you self-host Kroki and keep everything offline:
#   docker run -d -p 8000:8000 yuzutech/kroki
#   KROKI_URL=http://localhost:8000 sh render.sh
KROKI_URL="${KROKI_URL:-https://kroki.io}"
for mmd in *.mmd; do
    svg="${mmd%.mmd}.svg"
    if command -v mmdc >/dev/null 2>&1; then
        mmdc -i "$mmd" -o "$svg" -b transparent
    else
        curl -sf -X POST "$KROKI_URL/mermaid/svg" --data-binary @"$mmd" -o "$svg"
    fi
    echo "rendered $svg"
done
