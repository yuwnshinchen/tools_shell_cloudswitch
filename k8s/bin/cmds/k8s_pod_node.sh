#!/usr/bin/env bash
# DESC:查詢工具-支援單一Pod反查或全局Node標籤概覽 

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "kubectl"
check_command "fzf"

# --- 內部函式：處理 Node Label 選擇邏輯 ---
select_node_labels() {
  local MODE
  MODE=$(printf "None\ngroup,node-pool-GCP\ngroup,node-pool-AWS\nALL\nCustom (input)" | \
    fzf --prompt="Select Node Label Mode (Display for all nodes) > ")

  case "$MODE" in
    "None") echo "" ;;
    "group,node-pool-GCP") echo "group,cloud.google.com/gke-nodepool" ;;
    "group,node-pool-AWS") echo "group,eks.amazonaws.com/nodegroup" ;;
    "ALL") echo "__ALL__" ;;
    "Custom (input)")
      read -r -p "Enter label keys (comma separated): " custom_tags
      echo "$custom_tags"
      ;;
  esac
}

# ==========================================
# 主程式開始
# ==========================================

QUERY_MODE=$(printf "1. 查詢指定 Pod (反查 Node)\n2. 查詢全部 Node (標籤概覽)" | \
  fzf --prompt="Select Query Mode > ")

case "$QUERY_MODE" in
  "1. 查詢指定 Pod"*)
    # ... (此部分保留您原本的 Pod 查詢邏輯，最後呼叫單一 Node 顯示)
    NAMESPACE=$(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | fzf --prompt="Select Namespace > ")
    [[ -z "$NAMESPACE" ]] && exit 0
    
    POD=$(kubectl get pod -n "$NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name | fzf --prompt="Select Pod > ")
    [[ -z "$POD" ]] && exit 0

    NODE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
    LABEL_TAGS=$(select_node_labels)

    info "--- Result ---"
    info "Pod: $POD | Node: $NODE"
    if [[ "$LABEL_TAGS" == "__ALL__" ]]; then
      kubectl get node "$NODE" --show-labels
    else
      kubectl get node "$NODE" -L "$LABEL_TAGS"
    fi
    ;;

  "2. 查詢全部 Node"*)
    # 直接選擇標籤模式，然後顯示「所有」Node 的該標籤狀態
    LABEL_TAGS=$(select_node_labels)

    info "--- 正在獲取所有 Node 資訊 ---"
    if [[ -z "$LABEL_TAGS" ]]; then
      kubectl get nodes
    elif [[ "$LABEL_TAGS" == "__ALL__" ]]; then
      kubectl get nodes --show-labels
    else
      # 使用 -L 參數可以將 Label 轉化為獨立的 Column 顯示，非常適合對比全部 Node
      kubectl get nodes -L "$LABEL_TAGS"
    fi
    ;;

  *)
    exit 0
    ;;
esac