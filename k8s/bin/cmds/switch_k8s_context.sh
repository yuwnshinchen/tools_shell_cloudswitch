#!/bin/bash

set -euo pipefail

# MODE: NORMAL
# DESC: 通用切換 K8S Context (支援 GKE & EKS)

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "aws"
check_command "kubectl"
check_command "fzf"

# 選擇 context
selected_context=$(kubectl config get-contexts -o name | fzf --prompt="Select kube context > ")
[[ -z "$selected_context" ]] && { yellow "[WARN] 已取消。"; exit 0; }

kubectl config use-context "$selected_context"

# 取得 cluster 與 user
cluster_server=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$selected_context')].context.cluster}")
user_name=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$selected_context')].context.user}")

# 判斷平台並解析 region/account/project
region="N/A"
account_project="N/A"
cluster_name="$cluster_server"

if [[ "$cluster_server" =~ arn:aws:eks:([^:]+):([^:]+):cluster/(.+) ]]; then
    # AWS EKS
    region="${BASH_REMATCH[1]}"
    account_project="${BASH_REMATCH[2]}"
    cluster_name="${BASH_REMATCH[3]}"
elif [[ "$cluster_server" =~ gke_([^_]+)_([^_]+)_(.+) ]]; then
    # GCP GKE
    account_project="${BASH_REMATCH[1]}"
    region="${BASH_REMATCH[2]}"
    cluster_name="${BASH_REMATCH[3]}"
fi

green "✅ Switched to context: $selected_context"
echo "Cluster: $cluster_name"
echo "User: $user_name"
echo "Region: $region"
echo "Account/Project: $account_project"
