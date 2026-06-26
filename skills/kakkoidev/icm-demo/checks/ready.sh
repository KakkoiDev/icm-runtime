#!/bin/sh
# Example ICM gate checker (the "file-checker" form of a gate's run= command).
#
# The stage-02 gate declares:
#   <!-- ICM-GATE tools="demo_publish" run="checks/ready.sh" -->
# icm.sh freezes this file into the run, lists it in the run's .manifest, and (when
# a tool matching `demo_publish` is about to run while stage 02 is active) executes
# it with cwd = the run's 02-enforcement stage dir.
#
# Exit 0 = the precondition holds, the gate PASSES. Exit 1 = the gate DENIES.
# A gate is the deterministic half of a contract: prose says "do not publish before
# you are ready", this turns it into something the harness can enforce.
#
# The precondition here: a non-empty output/ready.md marker exists in the stage dir.
test -s output/ready.md
