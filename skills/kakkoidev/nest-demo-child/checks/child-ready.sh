#!/bin/sh
# Child publish gate: the child may publish only once it has produced evidence.
# Runs from the child stage dir, so output/ is this stage's output.
test -f output/child-evidence.md
