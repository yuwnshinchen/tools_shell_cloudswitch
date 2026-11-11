#!/usr/bin/env bash
# DESC: Helm Release 檢視與 Revision 差異比較 (Status/Resources/Values/Manifest/Diff)

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "helm"
check_command "kubectl"
check_command "fzf"

# 顯示當前 Context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ -z "$CURRENT_CONTEXT" ]]; then
    error "未設定或找不到目前的 Kubernetes Context"
    exit 1
fi
info "Current K8s Context: $CURRENT_CONTEXT"

# 1. 選擇 Namespace
NAMESPACE=$(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | fzf --prompt="1. Select Namespace > " --height=15 --border)
[[ -z "$NAMESPACE" ]] && exit 0

# 2. 列出該 Namespace 下的 Helm Releases
HELM_LIST=$(helm list -n "$NAMESPACE" 2>/dev/null || true)
if [[ -z "$HELM_LIST" || $(echo "$HELM_LIST" | wc -l) -le 1 ]]; then
    warn "在 Namespace [$NAMESPACE] 中未找到任何 Helm Release"
    exit 0
fi

RELEASE_LINE=$(echo "$HELM_LIST" | tail -n +2 | fzf --prompt="2. Select Helm Release ($NAMESPACE) > " --header="NAME | REVISION | UPDATED | STATUS | CHART | APP VERSION" --height=20 --border)
[[ -z "$RELEASE_LINE" ]] && exit 0

RELEASE=$(echo "$RELEASE_LINE" | awk '{print $1}')
info "已選擇 Release: $RELEASE (Namespace: $NAMESPACE)"

# 3. 選擇動作 (Action)
ACTION=$(printf "1. Status & Resources (即時狀態含關聯 Pod)\n2. Manifest Resources (即時狀態表格)\n3. Resource List & Describe (資源清單與詳細檢視)\n4. User Values (客製設定 values.yaml)\n5. Full Manifest (完整原始 YAML)\n6. Revision History (歷史版本紀錄)\n7. Diff Revisions (比較版本差異)" | fzf --prompt="3. Select Action for [$RELEASE] > " --height=15 --border)
[[ -z "$ACTION" ]] && exit 0

case "$ACTION" in
  "1. Status & Resources (即時狀態含關聯 Pod)")
    info "--- Executing: helm status $RELEASE -n $NAMESPACE --show-resources ---"
    helm status "$RELEASE" -n "$NAMESPACE" --show-resources
    ;;

  "2. Manifest Resources (即時狀態表格)")
    VIEW_MODE=$(printf "1. Standard Table (標準表格)\n2. With Labels (含實際 Labels: --show-labels)\n3. Live Objects YAML (所有資源實體 YAML)" | fzf --prompt="Select Table View Mode > " --height=10 --border)
    [[ -z "$VIEW_MODE" ]] && exit 0

    case "$VIEW_MODE" in
      *"Standard Table"*)
        info "--- Executing: helm get manifest $RELEASE -n $NAMESPACE | kubectl get -f - -n $NAMESPACE ---"
        helm get manifest "$RELEASE" -n "$NAMESPACE" | kubectl get -f - -n "$NAMESPACE"
        ;;
      *"With Labels"*)
        info "--- Executing: helm get manifest $RELEASE -n $NAMESPACE | kubectl get -f - -n $NAMESPACE --show-labels ---"
        helm get manifest "$RELEASE" -n "$NAMESPACE" | kubectl get -f - -n "$NAMESPACE" --show-labels
        ;;
      *"Live Objects YAML"*)
        info "--- Executing: helm get manifest $RELEASE -n $NAMESPACE | kubectl get -f - -n $NAMESPACE -o yaml ---"
        helm get manifest "$RELEASE" -n "$NAMESPACE" | kubectl get -f - -n "$NAMESPACE" -o yaml
        ;;
    esac
    ;;

  "3. Resource List & Describe (資源清單與詳細檢視)")
    info "正在載入 Release [$RELEASE] 的資源清單..."
    RESOURCES=$(helm get manifest "$RELEASE" -n "$NAMESPACE" | kubectl get -f - -n "$NAMESPACE" -o name 2>/dev/null || true)
    if [[ -z "$RESOURCES" ]]; then
        warn "無法取得資源清單或 Release 中無資源"
        exit 0
    fi

    # 支援單選、Tab 多選、或直接選 [ALL Resources]
    SELECTED=$(printf "[ALL Resources]\n%s" "$RESOURCES" | fzf -m --prompt="Select Resource(s) (Tab to multi-select, or choose [ALL]) > " --header="提示: 可用 TAB 鍵勾選多個項目，或直接選擇 [ALL Resources]" --height=18 --border)
    [[ -z "$SELECTED" ]] && exit 0

    TARGET_LIST=()
    if echo "$SELECTED" | grep -q "\[ALL Resources\]"; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && TARGET_LIST+=("$line")
        done <<< "$RESOURCES"
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] && TARGET_LIST+=("$line")
        done <<< "$SELECTED"
    fi

    [[ ${#TARGET_LIST[@]} -eq 0 ]] && exit 0

    SUB_ACTION=$(printf "1. kubectl describe\n2. Labels & Annotations (檢視實際標籤與註解)\n3. kubectl get (yaml)\n4. kubectl get (json)" | fzf --prompt="Select Inspect Action for ${#TARGET_LIST[@]} resource(s) > " --height=12 --border)
    [[ -z "$SUB_ACTION" ]] && exit 0

    case "$SUB_ACTION" in
      *"kubectl describe"*)
        for res in "${TARGET_LIST[@]}"; do
            echo -e "\n${BLUE}==================== $res ====================${WHITE}"
            kubectl describe "$res" -n "$NAMESPACE"
        done
        ;;

      *"Labels & Annotations"*)
        for res in "${TARGET_LIST[@]}"; do
            echo -e "\n${GREEN}=== [$res] ===${WHITE}"
            echo -e "${YELLOW}Labels:${WHITE}"
            kubectl get "$res" -n "$NAMESPACE" -o jsonpath='{.metadata.labels}' | jq . 2>/dev/null || echo "None"
            echo -e "${YELLOW}Annotations:${WHITE}"
            kubectl get "$res" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || echo "None"
        done
        ;;

      *"kubectl get (yaml)"*)
        info "--- Executing: kubectl get ${TARGET_LIST[*]} -n $NAMESPACE -o yaml ---"
        kubectl get "${TARGET_LIST[@]}" -n "$NAMESPACE" -o yaml
        ;;

      *"kubectl get (json)"*)
        info "--- Executing: kubectl get ${TARGET_LIST[*]} -n $NAMESPACE -o json ---"
        kubectl get "${TARGET_LIST[@]}" -n "$NAMESPACE" -o json
        ;;
    esac
    ;;

  "4. User Values (客製設定 values.yaml)")
    info "--- Executing: helm get values $RELEASE -n $NAMESPACE ---"
    helm get values "$RELEASE" -n "$NAMESPACE"
    ;;

  "5. Full Manifest (完整原始 YAML)")
    info "--- Executing: helm get manifest $RELEASE -n $NAMESPACE ---"
    helm get manifest "$RELEASE" -n "$NAMESPACE"
    ;;

  "6. Revision History (歷史版本紀錄)")
    info "--- Executing: helm history $RELEASE -n $NAMESPACE ---"
    helm history "$RELEASE" -n "$NAMESPACE"
    ;;

  "7. Diff Revisions (比較版本差異)")
    HISTORY=$(helm history "$RELEASE" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ -z "$HISTORY" || $(echo "$HISTORY" | wc -l) -le 1 ]]; then
        warn "Release [$RELEASE] 沒有可用的歷史紀錄"
        exit 0
    fi

    REV_COUNT=$(echo "$HISTORY" | tail -n +2 | wc -l | xargs)
    if [[ "$REV_COUNT" -lt 2 ]]; then
        warn "Release [$RELEASE] 只有 1 個 revision，無法進行比對"
        exit 0
    fi

    echo -e "\n${BLUE}請選擇欲比對的兩個 Revision:${WHITE}"
    REV1_LINE=$(echo "$HISTORY" | tail -n +2 | fzf --prompt="Select Base Revision (基準版本, 通常較舊) > " --header="REVISION | UPDATED | STATUS | CHART | APP VERSION | DESCRIPTION" --height=15 --border)
    [[ -z "$REV1_LINE" ]] && exit 0
    REV1=$(echo "$REV1_LINE" | awk '{print $1}')

    REV2_LINE=$(echo "$HISTORY" | tail -n +2 | fzf --prompt="Select Target Revision (目標版本, 通常較新) > " --header="REVISION | UPDATED | STATUS | CHART | APP VERSION | DESCRIPTION" --height=15 --border)
    [[ -z "$REV2_LINE" ]] && exit 0
    REV2=$(echo "$REV2_LINE" | awk '{print $1}')

    if [[ "$REV1" == "$REV2" ]]; then
        warn "選取的兩個版本相同 (Revision $REV1)，無差異可比對"
        exit 0
    fi

    DIFF_MODE=$(printf "1. Manifest Diff (完整 K8s 資源差異)\n2. Values Diff (客製 values.yaml 參數差異)" | fzf --prompt="Select Diff Mode > " --height=10 --border)
    [[ -z "$DIFF_MODE" ]] && exit 0

    case "$DIFF_MODE" in
      *"Manifest Diff"*)
        info "--- Diffing Manifest: Revision $REV1 vs Revision $REV2 ---"
        if helm plugin list | grep -q "^diff[[:space:]]"; then
            helm diff revision "$RELEASE" "$REV1" "$REV2" -n "$NAMESPACE" --color || true
        else
            TMP1=$(mktemp)
            TMP2=$(mktemp)
            trap 'rm -f "$TMP1" "$TMP2"' EXIT
            helm get manifest "$RELEASE" -n "$NAMESPACE" --revision "$REV1" > "$TMP1"
            helm get manifest "$RELEASE" -n "$NAMESPACE" --revision "$REV2" > "$TMP2"
            if command -v git >/dev/null 2>&1; then
                git diff --no-index --color "$TMP1" "$TMP2" || true
            else
                diff -u "$TMP1" "$TMP2" || true
            fi
        fi
        ;;

      *"Values Diff"*)
        info "--- Diffing User Values: Revision $REV1 vs Revision $REV2 ---"
        TMP1=$(mktemp)
        TMP2=$(mktemp)
        trap 'rm -f "$TMP1" "$TMP2"' EXIT
        helm get values "$RELEASE" -n "$NAMESPACE" --revision "$REV1" > "$TMP1"
        helm get values "$RELEASE" -n "$NAMESPACE" --revision "$REV2" > "$TMP2"
        if command -v git >/dev/null 2>&1; then
            git diff --no-index --color "$TMP1" "$TMP2" || true
        else
            diff -u "$TMP1" "$TMP2" || true
        fi
        ;;
    esac
    ;;

  *)
    exit 0
    ;;
esac
