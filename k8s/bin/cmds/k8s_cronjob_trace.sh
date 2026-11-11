#!/usr/bin/env bash
# DESC: K8s Pod 溯源工具 (Pod -> Job -> CronJob) 支援個別或批次 Describe

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "kubectl"
check_command "fzf"

# 1. 選擇 Namespace
NAMESPACE=$(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | fzf --prompt="1. Select Namespace > ")
[[ -z "$NAMESPACE" ]] && exit 0

# 2. 選擇 Pod
POD=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status.phase | fzf --prompt="2. Select Pod > " | awk '{print $1}')
[[ -z "$POD" ]] && exit 0

# --- 開始溯源邏輯 ---

# 取得 Job 資訊
JOB_NAME=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Job")].name}' 2>/dev/null || echo "")

# 取得 CronJob 資訊 (如果 Job 存在)
CJ_NAME=""
if [[ -n "$JOB_NAME" ]]; then
    CJ_NAME=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="CronJob")].name}' 2>/dev/null || echo "")
fi

# --- 顯示層級關係 ---
echo -e "\n${BLUE}🔍 Resource Hierarchy:${WHITE}"
if [[ -n "$CJ_NAME" ]]; then
    echo -e "${GREEN}CronJob/${CJ_NAME}${WHITE}"
    echo -e "  └─ ${YELLOW}Job/${JOB_NAME}${WHITE}"
    echo -e "      └─ ${RED}Pod/${POD}${WHITE}"
elif [[ -n "$JOB_NAME" ]]; then
    echo -e "${YELLOW}Job/${JOB_NAME}${WHITE}"
    echo -e "  └─ ${RED}Pod/${POD}${WHITE}"
else
    echo -e "${RED}Pod/${POD}${WHITE} (Independent Pod)"
fi
echo "--------------------------------"

# --- 建立動態選單 ---
OPTIONS=""
[[ -n "$CJ_NAME" || -n "$JOB_NAME" ]] && OPTIONS+="Describe ALL (Hierarchy)\n"
[[ -n "$CJ_NAME" ]]  && OPTIONS+="CronJob: $CJ_NAME\n"
[[ -n "$JOB_NAME" ]] && OPTIONS+="Job: $JOB_NAME\n"
OPTIONS+="Pod: $POD\n"
OPTIONS+="Exit"

SELECTED=$(printf "$OPTIONS" | fzf --prompt="Select action > ")
[[ -z "$SELECTED" || "$SELECTED" == "Exit" ]] && exit 0

# --- 執行 Describe 邏輯 ---

case "$SELECTED" in
    "Describe ALL (Hierarchy)")
        if [[ -n "$CJ_NAME" ]]; then
            info "=== DESCRIBE CRONJOB: $CJ_NAME ==="
            kubectl describe cronjob "$CJ_NAME" -n "$NAMESPACE"
            echo -e "\n"
        fi
        if [[ -n "$JOB_NAME" ]]; then
            info "=== DESCRIBE JOB: $JOB_NAME ==="
            kubectl describe job "$JOB_NAME" -n "$NAMESPACE"
            echo -e "\n"
        fi
        info "=== DESCRIBE POD: $POD ==="
        kubectl describe pod "$POD" -n "$NAMESPACE"
        ;;

    *)
        # 處理單一資源的 Describe
        TARGET_TYPE=$(echo "$SELECTED" | cut -d':' -f1 | tr '[:upper:]' '[:lower:]')
        TARGET_NAME=$(echo "$SELECTED" | awk '{print $2}')
        info "--- Executing: kubectl describe $TARGET_TYPE $TARGET_NAME -n $NAMESPACE ---"
        kubectl describe "$TARGET_TYPE" "$TARGET_NAME" -n "$NAMESPACE"
        ;;
esac