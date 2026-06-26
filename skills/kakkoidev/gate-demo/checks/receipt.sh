#!/bin/sh
# Gate checker for gate-demo's 01-publish stage. Runs with cwd = the run's stage
# dir. Exit 0 = precondition holds (gate PASSES), non-zero = gate DENIES.
# Precondition: a non-empty output/receipt.md marker exists.
test -s output/receipt.md
