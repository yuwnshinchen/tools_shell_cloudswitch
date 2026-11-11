#!/bin/bash
# MODE: NORMAL
# DESC: 互動式查詢 AWS 常用資訊 (ALB IP / Security Group / Node Group)
# NOTE: 需安裝 aws-cli，可選安裝 fzf 提升互動性

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"
check_command "aws"
check_command "fzf"

# ================= 功能設定 =================
FUNCS=("ALB-IP" "Security-Group" "Node-Group")

# ================= 選單函數 =================
select_from_list() {
    local prompt="$1"
    shift
    local options=("$@")
    local PS3="$prompt "
    local selection
    select opt in "${options[@]}"; do
        if [[ -n "$opt" ]]; then
            selection="$opt"
            break
        else
            echo "無效選項，請重新選擇"
        fi
    done
    echo "$selection"
}

# ================= ALB IP =================
show_alb_ip() {
    # 選 AWS Profile
    if command -v fzf &>/dev/null; then
        profiles=$(aws configure list-profiles)
        selected_profile=$(echo "$profiles" | fzf --prompt="Select AWS Profile > ")
    else
        read -r -p "Enter AWS Profile: " selected_profile
    fi

    # 驗證 profile 是否存在
    if ! aws configure list-profiles | grep -qw "$selected_profile"; then
        echo "Error: Invalid AWS Profile"
        exit 1
    fi

    # 選 Region
    region_codes=("ap-northeast-1" "ap-southeast-1" "us-east-1" "us-west-2")
    region_names=("東京" "新加坡" "維吉尼亞" "奧勒岡")

    if command -v fzf &>/dev/null; then
        options=()
        for i in "${!region_codes[@]}"; do
            options+=("${region_codes[$i]} - ${region_names[$i]}")
        done
        selected=$(printf "%s\n" "${options[@]}" | fzf --prompt="選擇 Region > ")
        selected_region=$(echo "$selected" | awk '{print $1}')
    else
        echo "可用 Region："
        for i in "${!region_codes[@]}"; do
            echo "${region_codes[$i]} - ${region_names[$i]}"
        done
        read -r -p "輸入 Region code: " selected_region
    fi

    echo "正在查詢 ALB 列表..."
    albs=$(aws elbv2 describe-load-balancers --profile "$selected_profile" --region "$selected_region" --query "LoadBalancers[*].[LoadBalancerName,DNSName]" --output text 2>/dev/null || true)

    alb_dns=""
    if [[ -z "$albs" ]]; then
        echo "未在 $selected_region 找到任何 ALB，或無 describe-load-balancers 權限。"
        read -r -p "請手動輸入欲查詢的 ALB DNS Name (留空退出): " alb_dns
    else
        if command -v fzf &>/dev/null; then
            selected_alb=$(printf "%s\n[手動輸入 DNS Name]" "$albs" | fzf --prompt="選擇 ALB > " --header="ALB Name | DNS Name")
            if [[ "$selected_alb" == "[手動輸入 DNS Name]"* ]]; then
                read -r -p "請手動輸入 ALB DNS Name: " alb_dns
            else
                alb_dns=$(echo "$selected_alb" | awk '{print $2}')
            fi
        else
            echo "可用 ALB："
            echo "$albs"
            read -r -p "請輸入欲查詢的 ALB DNS Name: " alb_dns
        fi
    fi

    if [[ -n "$alb_dns" ]]; then
        echo "========================================="
        echo "ALB DNS: $alb_dns"
        echo "External ALB IP:"
        dig +short "$alb_dns"
        echo "========================================="
    fi
}

# ================= Security Group =================
show_security_group_detail() {

    # 選 AWS Profile
    if command -v fzf &>/dev/null; then
        profiles=$(aws configure list-profiles)
        selected_profile=$(echo "$profiles" | fzf --prompt="Select AWS Profile > ")
    else
        read -r -p "Enter AWS Profile: " selected_profile
    fi

    # 驗證 profile 是否存在
    if ! aws configure list-profiles | grep -qw "$selected_profile"; then
        echo "Error: Invalid AWS Profile"
        exit 1
    fi

    # 選資訊模式
    INFO_MODE=$(select_from_list "Select Info Mode >" "List All SG Info" "Specified the group_ids")

    case "$INFO_MODE" in
        "List All SG Info")
            aws ec2 describe-security-groups \
                --profile "$selected_profile" \
                --query "SecurityGroups[*].[GroupId, GroupName, Description]" \
                --output table
            ;;
        "Specified the group_ids")
            read -r -p "Enter space-separated group IDs: " group_ids
            aws ec2 describe-security-groups \
                --group-ids $group_ids \
                --profile "$selected_profile" \
                --query "SecurityGroups[*].[GroupId, GroupName, Description]" \
                --output table
            ;;
        *)
            echo "Invalid Info Mode"
            ;;
    esac
}

# ================= Node Group Info =================
show_node_group_info() {
    # 選 AWS Profile
    if command -v fzf &>/dev/null; then
        profiles=$(aws configure list-profiles)
        selected_profile=$(echo "$profiles" | fzf --prompt="Select AWS Profile > ")
    else
        read -r -p "Enter AWS Profile: " selected_profile
    fi

    # 驗證 profile 是否存在
    if ! aws configure list-profiles | grep -qw "$selected_profile"; then
        echo "Error: Invalid AWS Profile"
        exit 1
    fi
    export AWS_PROFILE="$selected_profile"

    # 選 Region (東京、新加坡)
    region_codes=("ap-northeast-1" "ap-southeast-1")
    region_names=("東京" "新加坡")

    if command -v fzf &>/dev/null; then
        # 顯示中文 + code
        options=()
        for i in "${!region_codes[@]}"; do
            options+=("${region_codes[$i]} - ${region_names[$i]}")
        done
        selected=$(printf "%s\n" "${options[@]}" | fzf --prompt="選擇 Region > ")
        selected_region=$(echo "$selected" | awk '{print $1}')
    else
        echo "可用 Region："
        for i in "${!region_codes[@]}"; do
            echo "${region_codes[$i]} - ${region_names[$i]}"
        done
        read -r -p "輸入 Region code: " selected_region
    fi

    # 驗證 region 是否有效
    valid_region=false
    for code in "${region_codes[@]}"; do
        if [[ "$code" == "$selected_region" ]]; then
            valid_region=true
            break
        fi
    done

    if [[ "$valid_region" == false ]]; then
        echo "Error: 無效的 Region"
        return 1
    fi

    # 選 Cluster
    clusters=$(aws eks list-clusters --region "$selected_region" --query 'clusters' --output text)
    if [[ -z "$clusters" ]]; then
        echo "No clusters found in region $selected_region"
        return 1
    fi

    if command -v fzf &>/dev/null; then
        selected_cluster=$(echo "$clusters" | tr ' ' '\n' | fzf --prompt="Select Cluster > ")
    else
        echo "Available clusters:"
        echo "$clusters"
        read -r -p "Enter Cluster Name: " selected_cluster
    fi

    export CLUSTER="$selected_cluster"

    # 取得 Node Group 名稱
    NODEGROUPS=$(aws eks list-nodegroups --cluster "$CLUSTER" --region "$selected_region" --query 'nodegroups' --output text)

    if [[ -z "$NODEGROUPS" ]]; then
        echo "No Node Groups found in cluster $CLUSTER"
        return 1
    fi

    # 列印 Node Group 名稱
    echo "Node Groups in cluster $CLUSTER:"
    for NG in $NODEGROUPS; do
        echo "Node Group Name - $NG"
        aws eks describe-nodegroup --cluster $CLUSTER --nodegroup-name $NG
    done
}

# ================= 功能分派 =================
run_func() {
    local func="$1"

    if [[ "$func" == "ALB-IP" ]]; then
        show_alb_ip
    elif [[ "$func" == "Security-Group" ]]; then
        show_security_group_detail
    elif [[ "$func" == "Node-Group" ]]; then
        show_node_group_info
    else
        echo "尚未實作的功能"
    fi
}

# ================= 主流程 =================
main() {
    FUNC=$(select_from_list "Select Function >" "${FUNCS[@]}")
    run_func "$FUNC"
}

main
