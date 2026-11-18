#!/bin/bash
set -e

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

check_feature true false

reportResults
