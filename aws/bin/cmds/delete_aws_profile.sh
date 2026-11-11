#!/bin/bash

set -euo pipefail

# MODE: NORMAL
# DESC: 刪除 AWS Profile 及對應 SSO Session
# 注意：只有當沒有 profile 再使用 SSO Session 才會刪除 session

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "aws"
check_command "fzf"

CONFIG_FILE="$HOME/.aws/config"

# 確保 config 存在
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "找不到 AWS config: $CONFIG_FILE"
    exit 1
fi

# 取得所有 profile
PROFILES=($(grep '^\[profile ' "$CONFIG_FILE" | sed 's/\[profile \(.*\)\]/\1/'))

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    warn "沒有可用的 AWS Profile"
    exit 0
fi

# 選擇要刪除的 profile（可多選）
echo "請選擇要刪除的 AWS Profile (多選請用 TAB)："
SELECTED=$(printf "%s\n" "${PROFILES[@]}" | fzf --multi --prompt="Select profiles > " --height=15 --border --ansi)

if [[ -z "$SELECTED" ]]; then
    info "取消刪除"
    exit 0
fi

# 列出要刪除的 profile
echo
echo "====================================="
info "以下 AWS Profile 將被刪除："
echo "$SELECTED"
echo "====================================="

read -p "確認刪除全部選中的 profile? (y/N): " confirm
case "$confirm" in
    y|Y|yes|YES)
        info "開始刪除..."
        ;;
    *)
        warn "取消刪除"
        exit 0
        ;;
esac

# 刪除 profile
for PROFILE in $SELECTED; do
    info "刪除 Profile: $PROFILE"
    awk -v p="$PROFILE" 'BEGIN{skip=0} /^\[profile /{skip=($2==p"]")} !skip' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

    # 刪除對應 sso_session（若無其他 profile 使用）
    SESSION=$(awk -v p="$PROFILE" 'BEGIN{sess=""} /^\[profile /{skip=($2==p"]")} !skip && /^\s*sso_session =/ {sess=$3} END{print sess}' "$CONFIG_FILE")
    if [[ -n "$SESSION" ]]; then
        # 檢查 session 是否還有被其他 profile 使用
        in_use=$(grep -A2 "^\[profile " "$CONFIG_FILE" | grep -c "sso_session = $SESSION")
        if [[ $in_use -eq 0 ]]; then
            info "刪除未被使用的 SSO Session: $SESSION"
            awk -v s="$SESSION" 'BEGIN{skip=0} /^\[sso-session /{skip=($2==s"]")} !skip' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
            mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
    fi
done

success "完成刪除選中的 AWS Profile!"
