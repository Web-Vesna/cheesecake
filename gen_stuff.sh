#!/bin/bash

set -x # make verbose

pod2markdown README.pod > README.md
git ls-tree --full-tree -r HEAD | awk '{print $4}' | egrep -v "^\.|README.md|$0" > MANIFEST
