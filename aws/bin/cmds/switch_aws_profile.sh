#!/bin/bash

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

check_command "fzf"
check_command "aws"

# MODE: EXPORT
# DESC: 切換 AWS Profile

profiles=$(aws configure list-profiles)
selected=$(echo "$profiles" | fzf --prompt="Select AWS Profile > ")

if [[ -n "$selected" ]]; then
  echo "export AWS_PROFILE=\"$selected\""
  echo "echo '✅ Switched to AWS profile: $selected'"
  echo "aws sts get-caller-identity"
else
  echo "echo '❌ No profile selected.'"
fi

