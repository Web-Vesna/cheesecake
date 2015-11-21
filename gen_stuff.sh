#!/bin/bash

set -x # make verbose

FNAME=$(basename "$0")

pod2markdown README.pod > README.md
git ls-tree --full-tree -r HEAD | awk '{print $4}' | egrep -v "^\.|README.md|$FNAME" > MANIFEST
