#!/bin/sh
# Eval: tools/check-sources fails a page that states a claim (date, deadline,
# owner, status, spec) or names a ticket/PR without a link + verbatim quote of
# its source, and passes the same page once sourced or marked unverified.
# Runs from the skill dir (icm.sh eval cwd's here). Exit 0 = pass.
set -eu

tmp=$(mktemp -d)
page="$tmp/page.md"

pass() { printf '%s\n' "$1" > "$page"; tools/check-sources "$page" >/dev/null || { echo "FAIL: expected pass: $2"; exit 1; }; }
fail() { printf '%s\n' "$1" > "$page"; if tools/check-sources "$page" >/dev/null; then echo "FAIL: expected fail: $2"; exit 1; fi; }

# The trigger case: a claim with no source.
fail '- Review due 2026-11-30, which is also the spec deadline.' 'unsourced deadline claim'
# Link alone is not enough: the source must be quoted.
fail '- Review due 2026-11-30 ([spec](https://www.notion.so/abc)).' 'linked but unquoted claim'
# Quote alone is not enough: the source must be linked.
fail '- Review due 2026-11-30: "spec freeze 11/30".' 'quoted but unlinked claim'
# Sourced inline: the link sits on the claim words, the verbatim quote follows them.
pass '- Review due [2026-11-30 per the spec](https://www.notion.so/abc) "spec freeze 11/30".' 'inline linked + quoted claim'
pass '- 期限は[仕様書では11月30日](https://www.notion.so/abc)「仕様締切 11/30」' 'JA inline linked + quoted claim'
# A separate source line is the old form: the link belongs on the claim words.
fail '- Source: [spec](https://www.notion.so/abc) "spec freeze 11/30"' 'separate Source line'
fail '  - 出典：[仕様書](https://www.notion.so/abc)「仕様締切 11/30」' 'separate JA source line'
fail '   - Source (item 2): [reply](https://www.notion.so/abc) 「B で進めます」' 'labelled Source line'
fail '出典（項目3）：[回答](https://www.notion.so/abc)「その場所を開ける」' 'labelled JA source line'
fail '**Sources**: [spec](https://www.notion.so/abc)' 'bold Sources line'
# A source parked in a trailing parenthetical is the old form too.
fail '- Review due 2026-11-30 ([spec](https://www.notion.so/abc): "spec freeze 11/30").' 'parenthetical source'
fail '- 期限は11月30日（[仕様書](https://www.notion.so/abc)：「仕様締切 11/30」）' 'JA parenthetical source'
# The word source inside a sentence is not a source line.
pass '- The source of truth is [the wiki](https://www.notion.so/abc).' 'source as a word'
pass '- Plan in [the wiki](https://www.notion.so/abc) (see the [list](https://www.notion.so/def)).' 'plain link in parentheses'
# Explicitly marked unverified passes (the reader is warned).
pass '- Review due 2026-11-30 (unverified).' 'claim marked unverified'
# Named ticket / PR without a link fails; linked passes.
fail '- Fix lands in AILAB-123.' 'bare ticket id'
fail '- See PR #26513.' 'bare PR number'
pass '- Fix lands in [AILAB-123](https://www.notion.so/abc).' 'linked ticket id'
# HTML attribute quotes are not a source quote.
fail '<callout icon="x" color="gray_bg">Owner: Ann</callout>' 'attribute quotes do not count'
# Code fences and inline code are not claims.
pass '```
status: 2026-11-30 AILAB-1
```' 'code fence ignored'
pass '- Field `status` is set by the job.' 'inline code ignored'
# A table row is one unit: a source cell sources the row.
pass '<table>
	<tr>
		<td>Deadline</td>
		<td>2026-11-30</td>
		<td>[spec](https://www.notion.so/abc) "freeze 11/30"</td>
	</tr>
</table>' 'table row sourced by its source cell'
fail '<table>
	<tr>
		<td>Deadline</td>
		<td>2026-11-30</td>
	</tr>
</table>' 'table row without source'
# Empty or missing page fails closed.
: > "$page"
if tools/check-sources "$page" >/dev/null; then echo "FAIL: empty page passed"; exit 1; fi
if tools/check-sources "$tmp/missing.md" >/dev/null 2>&1; then echo "FAIL: missing page passed"; exit 1; fi

# Stage 02 must block the Notion write on this check.
grep -q 'ICM-GATE .*run="tools/check-sources ../01-render/output/page.md"' stages/02-publish.md \
    || { echo "FAIL: stage 02 gate does not run tools/check-sources"; exit 1; }

echo "ok"
