#!/bin/sh
set -eu
EXPECT_CODEX=false EXPECT_CLAUDE_CODE=true exec sh "$(dirname "$0")/test.sh"
