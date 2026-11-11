#!/bin/bash

set -euo pipefail

# MODE: NORMAL
# DESC: 刪除 kubeconfig 中指定 Cluster 的所有相關設定（cluster/user/context）

# 引入共用工具
# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "kubectl"
check_command "fzf"
check_command "jq"

# 選擇要刪除的 K8S Context
CLUSTER_NAME=$(kubectl config get-contexts -o name | fzf --prompt="Select kube context > ")

if [ -z "$CLUSTER_NAME" ]; then
  warn "No context selected. Exit."
  exit 1
fi

# 找出所有匹配的 entries
CLUSTERS=$(kubectl config view -o json | jq -r ".clusters[]?.name | select(contains(\"${CLUSTER_NAME}\"))")
USERS=$(kubectl config view -o json | jq -r ".users[]?.name | select(contains(\"${CLUSTER_NAME}\"))")
CONTEXTS=$(kubectl config view -o json | jq -r ".contexts[]?.name | select(contains(\"${CLUSTER_NAME}\"))")

info "====================================="
info "The following kubeconfig entries will be deleted:"
info "-------------------------------------"

blue "[Clusters]"
echo "$CLUSTERS"

echo
blue "[Users]"
echo "$USERS"

echo
blue "[Contexts]"
echo "$CONTEXTS"

info "====================================="

read -p "Are you sure you want to delete ALL of these? (y/N): " confirm

case "$confirm" in
  y|Y|yes|YES)
    info "Deleting..."

    # delete clusters
    for c in $CLUSTERS; do
      yellow "Deleting cluster: $c"
      kubectl config delete-cluster "$c"
    done

    # delete users
    for u in $USERS; do
      yellow "Deleting user: $u"
      kubectl config delete-user "$u"
    done

    # delete contexts
    for ctx in $CONTEXTS; do
      yellow "Deleting context: $ctx"
      kubectl config delete-context "$ctx"
    done

    success "Done."
    ;;
  *)
    warn "Cancelled."
    exit 0
    ;;
esac
