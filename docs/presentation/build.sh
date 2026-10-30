#!/bin/sh
# Rebuild the presentation in one step: render the diagram SVGs from their .mmd
# sources, then build both HTML files - the slides (deck.md) and the talk notes
# (talk-track.md).
#
# Diagrams use a local mmdc if installed, else the Kroki API. To keep everything
# offline, self-host Kroki and export KROKI_URL:
#   docker run -d -p 8000:8000 yuzutech/kroki
#   KROKI_URL=http://localhost:8000 sh build.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

sh "$here/diagrams/render.sh"

render_html() {
    if command -v marp >/dev/null 2>&1; then
        marp "$1" -o "$2"
    else
        npx --yes @marp-team/marp-cli "$1" -o "$2"
    fi
    echo "built $2"
}

render_html "$here/deck.md" "$here/deck.html"            # the slides
render_html "$here/talk-track.md" "$here/talk-track.html" # the talk notes
