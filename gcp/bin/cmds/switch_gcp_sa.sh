#!/bin/bash

set -euo pipefail

# MODE: NORMAL
# DESC: 切換已註冊的 GCP Service Account (gcloud configuration)

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "gcloud"
check_command "fzf"

echo "🔧 選擇要切換的 GCP Service Account (gcloud configuration)"
echo ""

# 用於 fzf 顯示：name | account | project
configurate=$(gcloud config configurations list \
    --format="table(name,account,project)" | \
    tail -n +2 | \
    fzf --header="選擇 SA (gcloud configuration)" --prompt="SA > ")

if [[ -z "$configurate" ]]; then
    warn "未選擇 SA，已取消。"
    exit 0
fi

config_name=$(echo "$configurate" | awk '{print $1}')
config_account=$(echo "$configurate" | awk '{print $2}')
config_project=$(echo "$configurate" | awk '{print $3}')

info "切換至 SA：$config_account (config=$config_name, project=$config_project)"
echo "-----------------------------------------"

# 啟動 configuration
if gcloud config configurations activate "$config_name" >/dev/null 2>&1; then
    success "成功切換至：$config_account"
else
    error "切換失敗，請檢查 configuration 是否存在：$config_name"
    exit 1
fi

echo ""
info "目前 gcloud 設定："
gcloud config list
