#!/bin/bash
# 共用工具（顏色、log、檢查命令、提示等）

# 顏色
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
WHITE="\033[0m"

# 顯示函數
red()    { echo -e "${RED}$*${WHITE}"; }
green()  { echo -e "${GREEN}$*${WHITE}"; }
yellow() { echo -e "${YELLOW}$*${WHITE}"; }
blue()   { echo -e "${BLUE}$*${WHITE}"; }

info()    { echo -e "$(blue [INFO]) $*"; }
success() { echo -e "$(green [SUCCESS]) $*"; }
warn()    { echo -e "$(yellow [WARN]) $*" >&2; }
error()   { echo -e "$(red [ERROR]) $*" >&2; }

# 檢查必要命令是否安裝
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        read -r -e -p "本腳本需要安裝 $1，是否安裝？(Y/N)：" answer
        case "$answer" in
            Y|y) 
                brew install "$1" || { error "安裝 $1 失敗"; exit 1; } ;;
            N|n) 
                error "$1 未安裝，退出腳本"; exit 1 ;;
            *) 
                error "無效輸入 ($answer)，退出"; exit 1 ;;
        esac
    fi
}
