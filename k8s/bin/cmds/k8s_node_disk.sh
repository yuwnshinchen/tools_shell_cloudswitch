#!/usr/bin/env bash
# DESC: 查詢所有Node的Disk Usage並自選要顯示的Label

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "kubectl"
check_command "fzf"
check_command "jq"

# 1. 互動式選擇 Node Label 模式
# echo "--- 步驟 1: 選擇要顯示的 Node 標籤 ---"
LABEL_MODE=$(printf "None\ngroup,node-pool-GCP\ngroup,node-pool-AWS\nALL\nCustom (input)" | \
  fzf --prompt="Select Node Label Mode for Disk Usage Report > ")

LABEL_TAGS=""
case "$LABEL_MODE" in
  "None") LABEL_TAGS="" ;;
  "group,node-pool-GCP") LABEL_TAGS="group,cloud.google.com/gke-nodepool" ;;
  "group,node-pool-AWS") LABEL_TAGS="group,eks.amazonaws.com/nodegroup" ;;
  "ALL") LABEL_TAGS="__ALL__" ;;
  "Custom (input)")
    read -r -p "Enter label keys (comma separated): " LABEL_TAGS
    ;;
esac

# echo -e "\n--- 步驟 2: 正在收集 Node 資訊與磁碟狀態 (請稍候...) ---\n"

# 2. 準備產出報表
# 如果是 ALL 模式，我們用 --show-labels；否則用 -L 指定標籤
GET_NODES_CMD="kubectl get nodes --no-headers"
if [[ "$LABEL_TAGS" == "__ALL__" ]]; then
  GET_NODES_CMD="$GET_NODES_CMD --show-labels"
elif [[ -n "$LABEL_TAGS" ]]; then
  GET_NODES_CMD="$GET_NODES_CMD -L $LABEL_TAGS"
fi

# 執行並處理每一行 Node 資料
eval "$GET_NODES_CMD" | while read -r line; do
    # 第一欄永遠是 Node Name
    NODE_NAME=$(echo "$line" | awk '{print $1}')
    
    # 根據模式提取標籤資訊
    if [[ "$LABEL_TAGS" == "__ALL__" ]]; then
        # 抓取最後一欄 (labels)
        LABELS_INFO=$(echo "$line" | awk '{print $NF}')
    elif [[ -n "$LABEL_TAGS" ]]; then
        # 抓取從第 6 欄開始的所有自定義標籤欄位
        LABELS_INFO=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i}')
    else
        LABELS_INFO="N/A"
    fi

    # 取得 Disk Usage 資訊 (原有的 jq 邏輯)
    DISK_STATS=$(kubectl get --raw "/api/v1/nodes/$NODE_NAME/proxy/stats/summary" 2>/dev/null | \
      jq -r '.node.fs | "Used: \(.usedBytes / 1024 / 1024 / 1024 | tonumber | round)GB / Total: \(.capacityBytes / 1024 / 1024 / 1024 | tonumber | round)GB (\((.usedBytes / .capacityBytes * 100) | tonumber | round)%)"' || echo "Fetch Error")

    # 格式化輸出結果
    printf "Node: %-20s | Labels: [%-30s] | %s\n" "$NODE_NAME" "${LABELS_INFO:-None}" "$DISK_STATS"
done