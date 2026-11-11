#!/bin/bash

set -euo pipefail

# MODE: NORMAL
# DESC: 互動式切換 GCP Project


# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

check_command "fzf"
check_command "gcloud"

info "選擇 GCP Project..."

# 取得 project id 與名稱
projects=$(gcloud projects list --filter="lifecycleState=ACTIVE" --format="value(name,projectId)")

# 利用 fzf 互動式選擇
selected=$(echo "$projects" | awk '{print $1 " - " $2}' | fzf --prompt="Select GCP Project > ")

# 從選項中擷取 projectId
project_id=$(echo "$selected" | awk -F ' - ' '{print $2}')

if [[ -n "$project_id" ]]; then
    gcloud config set project "$project_id"
    echo -e "${GREEN}✅ Switched to project: $project_id ${WHITE}"
    else
    echo -e "${RED}❌ No project selected. ${WHITE}"
fi
