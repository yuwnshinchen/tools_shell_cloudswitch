#!/bin/bash
# CloudSwitch - 安裝與設定腳本

set -euo pipefail

echo "================================================="
echo "   🚀 CloudSwitch 初始化與安裝程式"
echo "================================================="
echo ""

# 取得目前專案根目錄
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GCP_BIN="$ROOT_DIR/gcp/bin"
AWS_BIN="$ROOT_DIR/aws/bin"

# 偵測預設 Shell
DETECTED_SHELL=$(basename "$SHELL")
RC_FILE=""

case "$DETECTED_SHELL" in
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    bash)
        # MacOS 通常用 bash_profile，Linux 用 bashrc
        if [[ "$OSTYPE" == "darwin"* ]]; then
            RC_FILE="$HOME/.bash_profile"
        else
            RC_FILE="$HOME/.bashrc"
        fi
        ;;
    *)
        echo "⚠️ 偵測不到常見的 Shell (zsh/bash)，請手動將以下路徑加入 PATH："
        echo "   export PATH=\"$GCP_BIN:\$PATH\""
        echo "   export PATH=\"$AWS_BIN:\$PATH\""
        exit 0
        ;;
esac

echo "偵測到您的 Shell 為: $DETECTED_SHELL (設定檔: $RC_FILE)"

add_path_to_rc() {
    local bin_path="$1"
    local tool_name="$2"
    
    if grep -q "$bin_path" "$RC_FILE" 2>/dev/null; then
        echo "✅ [$tool_name] PATH 已經存在於 $RC_FILE 中，跳過新增。"
    else
        echo "" >> "$RC_FILE"
        echo "# CloudSwitch $tool_name PATH" >> "$RC_FILE"
        echo "export PATH=\"$bin_path:\$PATH\"" >> "$RC_FILE"
        echo "✅ [$tool_name] 已成功加入 $RC_FILE"
    fi
}

add_path_to_rc "$GCP_BIN" "GCP (gutil)"
add_path_to_rc "$AWS_BIN" "AWS (autil)"

echo ""
echo "🎉 安裝完成！"
echo "請重新啟動終端機，或輸入以下指令立即生效："
echo -e "\033[1;32m  source $RC_FILE\033[0m"
echo ""
echo "生效後即可使用 \033[1;34mgutil\033[0m 或 \033[1;34mautil\033[0m 指令。"
