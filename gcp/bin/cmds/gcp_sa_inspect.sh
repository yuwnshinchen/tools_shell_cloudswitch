#!/usr/bin/env bash
# MODE: NORMAL
# DESC: 互動式查詢 GCP Service Account (IAM Policy/Roles/Details/Keys)

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

check_command "gcloud"
check_command "fzf"

echo "🔧 GCP Service Account 查詢工具"
echo "=================================================="

# 1. 選擇 GCP Project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")

PROJECT_CHOICES=""
if [[ -n "$CURRENT_PROJECT" ]]; then
    PROJECT_CHOICES+="使用目前專案 ($CURRENT_PROJECT)\n"
fi
PROJECT_CHOICES+="從 GCP 專案列表選擇\n手動輸入專案 ID"

PROJECT_CHOICE=$(printf "$PROJECT_CHOICES" | fzf --prompt="1. 選擇 GCP Project 來源 > " --height=10 --border)
[[ -z "$PROJECT_CHOICE" ]] && { warn "未選擇 Project 來源，退出。"; exit 0; }

PROJECT_ID=""
case "$PROJECT_CHOICE" in
    "使用目前專案"*)
        PROJECT_ID="$CURRENT_PROJECT"
        ;;
    "從 GCP 專案列表選擇"*)
        info "正在取得 Project 列表..."
        projects=$(gcloud projects list --filter="lifecycleState=ACTIVE" --format="value(name,projectId)" 2>/dev/null || true)
        if [[ -z "$projects" ]]; then
            warn "無法取得 Project 列表，請改用手動輸入。"
            read -r -p "請輸入 GCP Project ID: " PROJECT_ID
        else
            selected_line=$(echo "$projects" | awk '{print $1 " - " $2}' | fzf --prompt="選擇 GCP Project > " --height=15 --border)
            [[ -z "$selected_line" ]] && { warn "未選擇 Project，退出。"; exit 0; }
            PROJECT_ID=$(echo "$selected_line" | awk -F ' - ' '{print $2}')
        fi
        ;;
    "手動輸入專案 ID"*)
        read -r -p "請輸入 GCP Project ID: " PROJECT_ID
        ;;
esac

[[ -z "$PROJECT_ID" ]] && { error "Project ID 為空，退出。"; exit 1; }
info "目標 GCP Project: $PROJECT_ID"
echo ""

# 2. 選擇 Service Account
info "正在取得專案 [$PROJECT_ID] 中的 Service Account 列表..."
SA_LIST_RAW=$(gcloud iam service-accounts list --project "$PROJECT_ID" --format="value(email,displayName,disabled)" 2>/dev/null || true)

SA_OPTIONS=""
if [[ -n "$SA_LIST_RAW" ]]; then
    SA_OPTIONS=$(echo "$SA_LIST_RAW" | while read -r email dname dis; do
        status="啟用"
        [[ "$dis" == "True" ]] && status="停用"
        echo "$email | $dname ($status)"
    done)
fi

SELECTED_SA_LINE=""
if [[ -n "$SA_OPTIONS" ]]; then
    SELECTED_SA_LINE=$(printf "%s\n[手動輸入 Service Account Email]" "$SA_OPTIONS" | fzf --prompt="2. 選擇 Service Account > " --header="SA Email | 顯示名稱 (狀態)" --height=20 --border)
    [[ -z "$SELECTED_SA_LINE" ]] && { warn "未選擇 Service Account，退出。"; exit 0; }
else
    warn "在專案 [$PROJECT_ID] 中未列出任何 Service Account，或無權限 list。"
    SELECTED_SA_LINE="[手動輸入 Service Account Email]"
fi

SA_EMAIL=""
if [[ "$SELECTED_SA_LINE" == "[手動輸入 Service Account Email]"* ]]; then
    read -r -p "請輸入 Service Account Email: " SA_EMAIL
    [[ -z "$SA_EMAIL" ]] && { warn "未輸入 Email，退出。"; exit 0; }
else
    SA_EMAIL=$(echo "$SELECTED_SA_LINE" | awk -F ' \\| ' '{print $1}' | xargs)
fi

info "目標 Service Account: $SA_EMAIL"
echo ""

# 3. 選擇動作
ACTION=$(printf "1. Get IAM Policy (查看此 SA 綁定的成員，包含 Workload Identity)\n2. Project Roles (查詢此 SA 在專案中獲得的 IAM 角色)\n3. Describe (查看 SA 基本詳細資訊)\n4. List Keys (列出 SA 金鑰)\n5. 全部檢視 (依序執行上述所有查詢)" | fzf --prompt="3. 選擇操作 > " --height=15 --border)
[[ -z "$ACTION" ]] && exit 0

echo "================================================================================"

case "$ACTION" in
    "1. Get IAM Policy"*)
        info "正在查詢 SA IAM Policy: $SA_EMAIL"
        echo "--------------------------------------------------------------------------------"
        gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --project="$PROJECT_ID"
        ;;

    "2. Project Roles"*)
        info "正在查詢 SA 在專案 [$PROJECT_ID] 中的角色指派 (Project IAM Policy)..."
        echo "--------------------------------------------------------------------------------"
        ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
            --flatten="bindings[].members" \
            --filter="bindings.members:serviceAccount:$SA_EMAIL" \
            --format="table(bindings.role)" 2>/dev/null || true)

        if [[ -n "$ROLES" && $(echo "$ROLES" | wc -l) -gt 1 ]]; then
            echo "$ROLES"
        else
            warn "在專案 [$PROJECT_ID] 的 Project-level IAM 中找不到 $SA_EMAIL 的角色指派（可能為跨專案授權或無專案級權限）。"
        fi
        ;;

    "3. Describe"*)
        info "正在查詢 SA 基本詳細資訊: $SA_EMAIL"
        echo "--------------------------------------------------------------------------------"
        gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID"
        ;;

    "4. List Keys"*)
        info "正在查詢 SA 金鑰列表: $SA_EMAIL"
        echo "--------------------------------------------------------------------------------"
        gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$PROJECT_ID"
        ;;

    "5. 全部檢視"*)
        info "[1/4] Describe (基本資訊):"
        echo "--------------------------------------------------------------------------------"
        gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" || true

        echo ""
        info "[2/4] Get IAM Policy (SA 被調用權限 / Workload Identity):"
        echo "--------------------------------------------------------------------------------"
        gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --project="$PROJECT_ID" || true

        echo ""
        info "[3/4] Project Roles (此 SA 在專案中擁有的角色):"
        echo "--------------------------------------------------------------------------------"
        gcloud projects get-iam-policy "$PROJECT_ID" \
            --flatten="bindings[].members" \
            --filter="bindings.members:serviceAccount:$SA_EMAIL" \
            --format="table(bindings.role)" || true

        echo ""
        info "[4/4] List Keys (金鑰列表):"
        echo "--------------------------------------------------------------------------------"
        gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$PROJECT_ID" || true
        ;;
esac

echo "================================================================================"
