#!/usr/bin/env bash
# DESC: K8s Pod 快速查詢工具 (get/describe/logs)

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "kubectl"
check_command "fzf"

# 1. 透過 fzf 選擇動作 (Action)
ACTION=$(printf "get\ndescribe\nlogs" | fzf --prompt="1. Select Action > ")
[[ -z "$ACTION" ]] && exit 0

# 2. 選擇 Namespace
NAMESPACE=$(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | fzf --prompt="2. Select Namespace > ")
[[ -z "$NAMESPACE" ]] && exit 0

# 3. 選擇 Pod Name
POD=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name | fzf --prompt="3. Select Pod ($NAMESPACE) > ")
[[ -z "$POD" ]] && exit 0

# 4. 針對不同 Action 執行對應邏輯
case "$ACTION" in
  "get")
    info "--- Executing: kubectl get pod $POD -n $NAMESPACE -o wide ---"
    kubectl get pod "$POD" -n "$NAMESPACE" -o wide
    ;;
    
  "describe")
    info "--- Executing: kubectl describe pod $POD -n $NAMESPACE ---"
    kubectl describe pod "$POD" -n "$NAMESPACE"
    ;;
    
  "logs")
    # 針對 logs 多做一層判斷：是否要 follow
    LOG_MODE=$(printf "Tail (last 100 lines)\nFollow (tail -f)\nTail with Timestamp" | fzf --prompt="Select Log Mode > ")
    [[ -z "$LOG_MODE" ]] && exit 0
    
    case "$LOG_MODE" in
      "Tail (last 100 lines)")
        info "--- Executing: kubectl logs $POD -n $NAMESPACE --tail=100 ---"
        kubectl logs "$POD" -n "$NAMESPACE" --tail=100
        ;;
      "Follow (tail -f)")
        info "--- Executing: kubectl logs $POD -n $NAMESPACE -f ---"
        kubectl logs "$POD" -n "$NAMESPACE" -f
        ;;
      "Tail with Timestamp")
        info "--- Executing: kubectl logs $POD -n $NAMESPACE --tail=100 --timestamps ---"
        kubectl logs "$POD" -n "$NAMESPACE" --tail=100 --timestamps
        ;;
    esac
    ;;
    
  *)
    exit 0
    ;;
esac