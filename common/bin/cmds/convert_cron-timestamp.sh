#!/bin/bash

set -euo pipefail

# 載入共用工具 (依賴進入點設定的 CLOUDSWITCH_ROOT)
if [[ -z "${CLOUDSWITCH_ROOT:-}" ]]; then
    export CLOUDSWITCH_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)
fi
source "$CLOUDSWITCH_ROOT/common/utils.sh"

# MODE: NORMAL
# DESC: 將輸入的Cronjob數字轉換成時間   

# 提問使用者輸入 CronJob 中的時間戳記（分鐘）
read -p "請輸入 CronJob 中的數字（分鐘，例如 29439550）: " minutes

# 檢查是否有輸入
if [ -z "$minutes" ]; then
  echo "沒有輸入數字，程式結束"
  exit 1
fi

# 檢查輸入是否為數字
if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
  echo "輸入必須是正整數"
  exit 1
fi

# 將分鐘轉成秒
seconds=$((minutes * 60))

# macOS 轉換 Unix 秒數到日期，使用台北時間 (CST)
datetime=$(TZ='Asia/Taipei' date -r "$seconds" "+%Y-%m-%d %H:%M:%S %Z")

# 輸出結果
echo "輸入的 CronJob 數字: $minutes"
echo "轉換後的日期時間: $datetime"