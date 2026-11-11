#!/usr/bin/env bash
# MODE: NORMAL
# DESC: 互動式查詢 GCP VM 執行個體 (List/Describe)

set -euo pipefail

# 1. 載入共用工具 (根據現有專案結構)
# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

check_command "fzf"
check_command "gcloud"

# 2. 選擇 GCP Project
info "正在取得 Project 列表..."
projects=$(gcloud projects list --filter="lifecycleState=ACTIVE" --format="value(name,projectId)")
selected_project_line=$(echo "$projects" | awk '{print $1 " - " $2}' | fzf --prompt="Select GCP Project > ")
[[ -z "$selected_project_line" ]] && { warn "未選擇 Project，退出。"; exit 0; }

PROJECT_ID=$(echo "$selected_project_line" | awk -F ' - ' '{print $2}')

# 3. 選擇動作 (List 或 Describe)
ACTION=$(printf "List (列出所有 VM)\nDescribe (查看 VM 詳細資訊)" | fzf --prompt="選擇操作 > ")
[[ -z "$ACTION" ]] && exit 0

case "$ACTION" in
    "List"*)
        info "正在列出 Project [$PROJECT_ID] 中的 VM 執行個體..."
        gcloud compute instances list --project "$PROJECT_ID"
        ;;

    "Describe"*)
        info "正在取得 VM 列表..."
        # 取得格式：NAME ZONE
        instances=$(gcloud compute instances list --project "$PROJECT_ID" --format="value(name,zone)")
        
        if [[ -z "$instances" ]]; then
            warn "在專案 $PROJECT_ID 中找不到任何 VM。"
            exit 0
        fi

        selected_instance_line=$(echo "$instances" | fzf --prompt="選擇要查看的 VM > ")
        [[ -z "$selected_instance_line" ]] && { warn "未選擇 VM，退出。"; exit 0; }

        VM_NAME=$(echo "$selected_instance_line" | awk '{print $1}')
        VM_ZONE=$(echo "$selected_instance_line" | awk '{print $2}')

        info "正在執行：gcloud compute instances describe $VM_NAME --project $PROJECT_ID --zone $VM_ZONE"
        echo "--------------------------------------------------------------------------------"
        gcloud compute instances describe "$VM_NAME" --project "$PROJECT_ID" --zone "$VM_ZONE"
        ;;
esac