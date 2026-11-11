#!/bin/bash

set -euo pipefail

# MODE: NORMAL
# DESC: 互動式重命名 K8S Context

# 引入共用工具
# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "kubectl"
check_command "fzf"

CONTEXTS=($(kubectl config get-contexts -o name))

if [[ ${#CONTEXTS[@]} -eq 0 ]]; then
    error "沒有可用的 K8S Context"
    exit 1
fi

selected_context=$(printf "%s\n" "${CONTEXTS[@]}" | fzf --prompt="Select context to rename > " --height=15 --border --ansi)

if [[ -z "$selected_context" ]]; then
    warn "已取消操作"
    exit 0
fi

echo
info "選擇的 context: $selected_context"
read -p "請輸入新的 context 名稱: " new_name

if [[ -z "$new_name" ]]; then
    error "新名稱不可為空，取消操作"
    exit 1
fi

echo
yellow "即將將 context [$selected_context] 重命名為 [$new_name]"
read -p "確認執行? (y/N): " confirm

case "$confirm" in
    y|Y|yes|YES)
        kubectl config rename-context "$selected_context" "$new_name"
        success "✅ 重命名成功: $selected_context -> $new_name"
        ;;
    *)
        warn "取消操作"
        exit 0
        ;;
esac
