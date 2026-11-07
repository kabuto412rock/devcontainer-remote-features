#!/bin/sh
set -eu
EXPECT_CODEX=true EXPECT_CLAUDE_CODE=true exec sh "$(dirname "$0")/test.sh"
