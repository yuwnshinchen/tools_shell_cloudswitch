#!/usr/bin/env bash
# MODE: NORMAL
# DESC: 診斷 K8s KSA 與 GKE Workload Identity 綁定狀態 (雙向檢查)

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

check_command "kubectl"
check_command "gcloud"
check_command "fzf"
check_command "jq"

echo "🔍 GKE Workload Identity 雙向綁定診斷工具"
echo "=================================================="

# 顯示當前 Context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ -z "$CURRENT_CONTEXT" ]]; then
    error "未設定或找不到目前的 Kubernetes Context，請先設定 kubectl context。"
    exit 1
fi
info "Current K8s Context: $CURRENT_CONTEXT"

# 嘗試解析 GKE 叢集專案 (若 context 是標準 gke_PROJECT_ZONE_CLUSTER 格式)
CLUSTER_PROJECT=""
cluster_server=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$CURRENT_CONTEXT')].context.cluster}" 2>/dev/null || echo "")
if [[ "$cluster_server" =~ gke_([^_]+)_([^_]+)_(.+) ]]; then
    CLUSTER_PROJECT="${BASH_REMATCH[1]}"
elif [[ "$CURRENT_CONTEXT" =~ gke_([^_]+)_([^_]+)_(.+) ]]; then
    CLUSTER_PROJECT="${BASH_REMATCH[1]}"
fi

# 1. 選擇 Namespace
info "正在取得 Namespace 列表..."
NAMESPACE=$(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | fzf --prompt="1. 選擇 Namespace > " --height=15 --border)
[[ -z "$NAMESPACE" ]] && { warn "未選擇 Namespace，已取消。"; exit 0; }

# 2. 取得該 Namespace 下的所有 ServiceAccount
info "正在取得 Namespace [$NAMESPACE] 中的 ServiceAccount 列表..."
SA_JSON=$(kubectl get sa -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$SA_JSON" || $(echo "$SA_JSON" | jq '.items | length') -eq 0 ]]; then
    warn "在 Namespace [$NAMESPACE] 中未找到任何 ServiceAccount。"
    exit 0
fi

# 整理 SA 選項，標示是否有 GSA 標註
SA_OPTIONS=$(echo "$SA_JSON" | jq -r '
  .items[] | 
  .metadata.name as $name | 
  (.metadata.annotations["iam.gke.io/gcp-service-account"] // "(未設定 gcp-sa 標註)") as $gsa |
  "\($name) | \($gsa)"
')

SELECTED_LINE=$(printf "%s\n[手動輸入 KSA 名稱]" "$SA_OPTIONS" | fzf --prompt="2. 選擇 K8s ServiceAccount > " --header="KSA 名稱 | 關聯 GCP SA" --height=20 --border)
[[ -z "$SELECTED_LINE" ]] && { warn "未選擇 ServiceAccount，已取消。"; exit 0; }

if [[ "$SELECTED_LINE" == "[手動輸入 KSA 名稱]"* ]]; then
    read -r -p "請輸入 K8s ServiceAccount 名稱: " KSA_NAME
    [[ -z "$KSA_NAME" ]] && { warn "未輸入名稱，已取消。"; exit 0; }
else
    KSA_NAME=$(echo "$SELECTED_LINE" | awk -F ' \\| ' '{print $1}' | xargs)
fi

# 3. 取得 KSA 的 GSA 標註
GSA_ANNOTATION=$(kubectl get sa "$KSA_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || echo "")

GSA_EMAIL=""
if [[ -z "$GSA_ANNOTATION" ]]; then
    echo ""
    warn "K8s SA [$KSA_NAME] 尚未設定標註 'iam.gke.io/gcp-service-account'！"
    read -r -p "請手動輸入欲比對的 GCP Service Account Email (留空直接退出): " GSA_EMAIL
    if [[ -z "$GSA_EMAIL" ]]; then
        warn "未指定 GCP SA，已結束診斷。"
        exit 0
    fi
else
    GSA_EMAIL="$GSA_ANNOTATION"
fi

# 4. 解析 GSA 所屬 Project ID
GSA_PROJECT=""
if [[ "$GSA_EMAIL" =~ @([^.]+)\.iam\.gserviceaccount\.com ]]; then
    GSA_PROJECT="${BASH_REMATCH[1]}"
fi

if [[ -z "$GSA_PROJECT" ]]; then
    GSA_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$GSA_PROJECT" ]]; then
        read -r -p "無法自動判定 GSA Project，請輸入 GCP Project ID: " GSA_PROJECT
        [[ -z "$GSA_PROJECT" ]] && { error "未提供 GCP Project ID，退出。"; exit 1; }
    fi
fi

# 若未能從 context 獲取 cluster_project，預設為 GSA 所屬 project
if [[ -z "$CLUSTER_PROJECT" ]]; then
    CLUSTER_PROJECT="$GSA_PROJECT"
fi

EXPECTED_MEMBER="serviceAccount:${CLUSTER_PROJECT}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"

echo ""
echo "================================================================================"
echo "📊 Workload Identity 診斷報告"
echo "================================================================================"
echo -e "K8s Context       : ${BLUE}$CURRENT_CONTEXT${WHITE}"
echo -e "K8s Namespace     : ${BLUE}$NAMESPACE${WHITE}"
echo -e "K8s ServiceAccount: ${BLUE}$KSA_NAME${WHITE}"
echo -e "GCP ServiceAccount: ${BLUE}$GSA_EMAIL${WHITE}"
echo -e "GSA GCP Project   : ${BLUE}$GSA_PROJECT${WHITE}"
echo -e "預期身份識別池    : ${BLUE}${CLUSTER_PROJECT}.svc.id.goog${WHITE}"
echo -e "預期 Binding 成員 : ${BLUE}$EXPECTED_MEMBER${WHITE}"
echo "--------------------------------------------------------------------------------"

# 檢查第一端：K8s KSA 標註
if [[ -n "$GSA_ANNOTATION" && "$GSA_ANNOTATION" == "$GSA_EMAIL" ]]; then
    echo -e "${GREEN}✅ [第一端: K8s KSA 標註]${WHITE} 設定正確"
    echo -e "   iam.gke.io/gcp-service-account: $GSA_ANNOTATION"
else
    echo -e "${RED}❌ [第一端: K8s KSA 標註]${WHITE} 缺失或不符"
    echo -e "   ${YELLOW}💡 修復建議 (在 K8s 補上標註)：${WHITE}"
    echo -e "   ${BLUE}kubectl annotate serviceaccount $KSA_NAME -n $NAMESPACE iam.gke.io/gcp-service-account=$GSA_EMAIL --overwrite${WHITE}"
fi

echo ""

# 檢查第二端：GCP GSA IAM Policy
info "正在向 GCP 查詢 GSA IAM Policy ($GSA_EMAIL)..."

IAM_POLICY_JSON=""
if ! IAM_POLICY_JSON=$(gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" --project="$GSA_PROJECT" --format=json 2>&1); then
    echo -e "${RED}❌ [第二端: GCP GSA IAM Policy]${WHITE} 查詢失敗："
    echo "$IAM_POLICY_JSON"
    echo ""
    warn "請確認 gcloud 權限、專案 ID ($GSA_PROJECT) 或 Service Account ($GSA_EMAIL) 是否正確。"
    exit 1
fi

# 擷取所有綁定在 roles/iam.workloadIdentityUser 上的成員
WI_MEMBERS=$(echo "$IAM_POLICY_JSON" | jq -r '
    .bindings[]? 
    | select(.role == "roles/iam.workloadIdentityUser") 
    | .members[]?
' 2>/dev/null || true)

WI_MATCH=false
if echo "$WI_MEMBERS" | grep -Fxq "$EXPECTED_MEMBER"; then
    WI_MATCH=true
fi

if [[ "$WI_MATCH" == "true" ]]; then
    echo -e "${GREEN}✅ [第二端: GCP GSA IAM Policy]${WHITE} Workload Identity 綁定驗證成功！"
    echo -e "   找到成員：${GREEN}$EXPECTED_MEMBER${WHITE}"
else
    # 檢查是否有同 namespace/ksa 但 cluster pool 不一樣的 binding
    SIMILAR_MEMBERS=$(echo "$WI_MEMBERS" | grep "\[${NAMESPACE}/${KSA_NAME}\]" || true)
    if [[ -n "$SIMILAR_MEMBERS" ]]; then
        echo -e "${YELLOW}⚠️  [第二端: GCP GSA IAM Policy]${WHITE} 找到相似綁定，但專案或叢集 Pool 不符！"
        echo -e "   現有成員："
        echo "$SIMILAR_MEMBERS" | sed 's/^/     - /'
        echo -e "   預期成員：$EXPECTED_MEMBER"
    else
        echo -e "${RED}❌ [第二端: GCP GSA IAM Policy]${WHITE} 未找到 Workload Identity 綁定！"
        if [[ -n "$WI_MEMBERS" ]]; then
            echo -e "   目前綁定的其他成員："
            echo "$WI_MEMBERS" | sed 's/^/     - /'
        else
            echo -e "   (此 GSA 目前沒有任何 roles/iam.workloadIdentityUser 綁定)"
        fi
    fi

    echo ""
    echo -e "${YELLOW}💡 修復建議 (在 GCP 授權 KSA 調用此 GSA)：${WHITE}"
    echo -e "${BLUE}gcloud iam service-accounts add-iam-policy-binding $GSA_EMAIL \\"
    echo -e "  --project=$GSA_PROJECT \\"
    echo -e "  --role=\"roles/iam.workloadIdentityUser\" \\"
    echo -e "  --member=\"$EXPECTED_MEMBER\"${WHITE}"
fi

echo "================================================================================"

# 後續操作選單
ACTION=$(printf "1. 查看完整 IAM Policy (YAML)\n2. 查看完整 IAM Policy (JSON)\n3. 退出" | fzf --prompt="選擇後續動作 > " --height=10 --border)
[[ -z "$ACTION" ]] && exit 0

case "$ACTION" in
    "1. 查看完整 IAM Policy (YAML)"*)
        echo ""
        info "--- IAM Policy (YAML) for $GSA_EMAIL ---"
        gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" --project="$GSA_PROJECT" --format=yaml
        ;;
    "2. 查看完整 IAM Policy (JSON)"*)
        echo ""
        info "--- IAM Policy (JSON) for $GSA_EMAIL ---"
        echo "$IAM_POLICY_JSON" | jq .
        ;;
    *)
        exit 0
        ;;
esac
