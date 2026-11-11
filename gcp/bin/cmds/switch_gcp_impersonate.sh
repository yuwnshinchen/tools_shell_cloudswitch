#!/bin/bash
# MODE: NORMAL
# DESC: 互動式設定/清除 GCP Service Account Impersonation

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

check_command "fzf"
check_command "gcloud"
check_command "curl"

# 驗證並顯示當前實際生效身份 (Effective Identity)
verify_effective_identity() {
    info "正在驗證實際生效身份 (Effective Identity)..."
    local token
    token=$(gcloud auth print-access-token 2>/dev/null || true)
    if [[ -z "$token" ]]; then
        warn "無法取得 Access Token，請確認已登入 gcloud 且具備冒充該 SA 的權限。"
        return 1
    fi

    local resp email
    resp=$(curl -s --max-time 5 "https://oauth2.googleapis.com/tokeninfo?access_token=${token}" 2>/dev/null || true)
    email=$(echo "$resp" | sed -n 's/.*"email"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [[ -n "$email" ]]; then
        green "目前實際生效身份: $email"
        return 0
    else
        warn "無法從 Token 解析出有效 Email (可能網路逾時或 Token 無效)。"
        return 1
    fi
}

# --- 自定義常用 Service Account 列表 ---
# 格式: "Email|描述"
COMMON_SAS=(
    # Sample Dev SA
    "dev-api-sa@sample-project-dev.iam.gserviceaccount.com|Sample Dev API SA"
    "qa-api-sa@sample-project-qa.iam.gserviceaccount.com|Sample QA API SA"
    # "sre-impersonator@$(gcloud config get-value project 2>/dev/null || echo 'project').iam.gserviceaccount.com|SRE Admin Impersonator"
    # 在此加入更多常用 SA
)
# --------------------------------------

# 取得目前設定
current_impersonation=$(gcloud config get-value auth/impersonate_service_account 2>/dev/null || true)
current_project=$(gcloud config get-value project 2>/dev/null || true)

echo "🔧 GCP Impersonation 管理"
echo "========================================="
if [[ -n "$current_impersonation" ]]; then
    green "目前正冒充 (Impersonating): $current_impersonation"
else
    blue "目前未設定冒充身份 (No impersonation set)"
fi
echo "目前專案: ${current_project:-未設定}"
echo "-----------------------------------------"

options=(
    "1. [常用] 從固定列表選擇"
    "2. [動態] 從目前專案選擇"
    "3. [手動] 輸入 Email"
    "4. [清除] 結束冒充身份 (Unset)"
    "5. [查看] 查詢當前實際生效身份 (Effective Identity)"
    "6. [取消]"
)

choice=$(printf "%s\n" "${options[@]}" | fzf --height=12 --border --prompt="請選擇操作 > ")

case "$choice" in
    *"1."*)
        selected=$(printf "%s\n" "${COMMON_SAS[@]}" | fzf --height=10 --border --prompt="選擇常用 SA > " --delimiter='|' --with-nth=1,2)
        [[ -z "$selected" ]] && { info "已取消"; exit 0; }
        selected_sa=$(echo "$selected" | cut -d'|' -f1)
        gcloud config set auth/impersonate_service_account "$selected_sa"
        success "已設定冒充身份為: $selected_sa"
        verify_effective_identity || true
        ;;
    *"2."*)
        if [[ -z "$current_project" ]]; then
            error "尚未設定 GCP Project，請先切換專案。"
            exit 1
        fi
        info "正在從專案 [$current_project] 取得 Service Accounts..."
        
        # 格式: email (displayName)
        sa_list=$(gcloud iam service-accounts list --project "$current_project" --format="value(email, displayName)")
        
        if [[ -z "$sa_list" ]]; then
            warn "在專案 [$current_project] 中找不到任何 Service Account。"
            exit 0
        fi

        selected_sa=$(echo "$sa_list" | fzf --height=15 --border --prompt="選擇要冒充的 SA > " | awk '{print $1}')
        
        if [[ -n "$selected_sa" ]]; then
            gcloud config set auth/impersonate_service_account "$selected_sa"
            success "已設定冒充身份為: $selected_sa"
            verify_effective_identity || true
        else
            warn "未選擇任何 Service Account。"
        fi
        ;;
    *"3."*)
        read -r -p "請輸入 Service Account Email: " manual_sa
        if [[ -n "$manual_sa" ]]; then
            gcloud config set auth/impersonate_service_account "$manual_sa"
            success "已設定冒充身份為: $manual_sa"
            verify_effective_identity || true
        else
            warn "未輸入 Email，已取消。"
        fi
        ;;
    *"4."*)
        gcloud config unset auth/impersonate_service_account
        success "已清除冒充身份。"
        verify_effective_identity || true
        ;;
    *"5."*)
        verify_effective_identity || true
        ;;
    *)
        info "操作已取消。"
        exit 0
        ;;
esac
