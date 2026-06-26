#!/bin/sh
# Rebuild the presentation in one step: render the diagram SVGs from their .mmd
# sources, then build the standalone HTML deck from deck.md.
#
# Diagrams use a local mmdc if installed, else the Kroki API. To keep everything
# offline, self-host Kroki and export KROKI_URL:
#   docker run -d -p 8000:8000 yuzutech/kroki
#   KROKI_URL=http://localhost:8000 sh build.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

sh "$here/diagrams/render.sh"

if command -v marp >/dev/null 2>&1; then
    marp "$here/deck.md" -o "$here/deck.html"
else
    npx --yes @marp-team/marp-cli "$here/deck.md" -o "$here/deck.html"
fi
echo "built $here/deck.html"
