#!/bin/sh
# Parent publish gate: the parent may publish only once it has produced its own
# evidence. Runs from the parent stage dir, so output/ is this stage's output.
test -f output/parent-evidence.md
