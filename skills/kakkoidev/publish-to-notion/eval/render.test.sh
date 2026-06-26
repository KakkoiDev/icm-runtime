#!/bin/sh
# Eval: tools/render converts GitHub pipe tables to Notion <table> blocks, leaves
# other Markdown alone, and never rewrites a pipe-line inside a fenced code block.
# Runs from the skill dir (icm.sh eval cwd's here). Exit 0 = pass.
set -eu

out=$(printf '| Name | Role |\n| --- | --- |\n| Ann | PM |\n' | tools/render)
echo "$out" | grep -q '<table'        || { echo "FAIL: pipe table not converted"; exit 1; }
echo "$out" | grep -q '<td>Name</td>' || { echo "FAIL: header cell missing"; exit 1; }
echo "$out" | grep -q '<td>Ann</td>'  || { echo "FAIL: body cell missing"; exit 1; }

# A heading + bold passes through unchanged (already valid Notion-flavored MD).
pt=$(printf '# Title\n\n**bold** text.\n' | tools/render)
echo "$pt" | grep -q '^# Title$'      || { echo "FAIL: heading mangled"; exit 1; }
echo "$pt" | grep -q '\*\*bold\*\*'   || { echo "FAIL: bold mangled"; exit 1; }

# A pipe-line inside a code fence must stay literal (not become a <table>).
fenced=$(printf '```\n| x | y |\n| --- | --- |\n```\n' | tools/render)
if echo "$fenced" | grep -q '<table'; then echo "FAIL: converted table inside code fence"; exit 1; fi

echo "ok"
