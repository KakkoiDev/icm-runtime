#!/bin/sh
# Regenerate diagram SVGs from the .mmd sources. Run after editing a .mmd.
# Prefers a local mmdc (@mermaid-js/mermaid-cli); otherwise falls back to the
# Kroki API, which sends the diagram source to kroki.io (fine for these public
# architecture diagrams; do not use it for anything sensitive).
set -eu
cd "$(dirname "$0")"
for mmd in *.mmd; do
    svg="${mmd%.mmd}.svg"
    if command -v mmdc >/dev/null 2>&1; then
        mmdc -i "$mmd" -o "$svg" -b transparent
    else
        curl -sf -X POST https://kroki.io/mermaid/svg --data-binary @"$mmd" -o "$svg"
    fi
    echo "rendered $svg"
done
