#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2068
PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

# ——————————————————————————————————————————————————————————————————————————————————
#  $$$$$$\          $$$$$$$\   $$$$$$\  $$\   $$\ 
# $$  __$$\         $$  __$$\ $$  __$$\ $$ |  $$ |
# $$ /  \__|        $$ |  $$ |$$ /  $$ |\$$\ $$  |
# $$ |$$$$\ $$$$$$\ $$$$$$$\ |$$ |  $$ | \$$$$  / 
# $$ |\_$$ |\______|$$  __$$\ $$ |  $$ | $$  $$<  
# $$ |  $$ |        $$ |  $$ |$$ |  $$ |$$  /\$$\ 
# \$$$$$$  |        $$$$$$$  | $$$$$$  |$$ /  $$ |
#  \______/         \_______/  \______/ \__|  \__|
#
# ——————————————————————————————————————————————————————————————————————————————————
# Copyright (c) 2025 AI老G <https://space.bilibili.com/252166818>
#
# 作者很菜，无法经常更新，不保证适用每个人的环境，请勿用于商业用途；
#
# 如果您喜欢这个脚本，可以请我喝咖啡：https://ailg.ggbond.org/3q.jpg
# ——————————————————————————————————————————————————————————————————————————————————

Green="\033[32m"
Red="\033[31m"
Yellow='\033[33m'
Font="\033[0m"
INFO="[${Green}INFO${Font}]"
ERROR="[${Red}ERROR${Font}]"
WARN="[${Yellow}WARN${Font}]"

function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

# 检查curl命令
if ! command -v curl >/dev/null 2>&1; then
    WARN "未找到curl命令,尝试使用wget..."
    if ! command -v wget >/dev/null 2>&1; then
        WARN "未找到wget命令,尝试安装curl..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y curl
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy curl --noconfirm
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl
        else
            ERROR "无法安装curl或wget,请手动安装后重试!"
            exit 1
        fi
        
        if ! command -v curl >/dev/null 2>&1; then
            ERROR "curl安装失败,请手动安装后重试!"
            exit 1
        fi
    fi
fi

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    ERROR "此脚本必须以root权限运行!"
    INFO "请使用 sudo -i 切换到root用户后重试"
    exit 1
fi

# 清理函数
cleanup() {
    local temp_files=(
        "/tmp/xy_ailg.sh"
        "/tmp/update_meta_jf.sh"
        "/tmp/share_resources.sh"
        "/tmp/sync_emby_config_ailg.sh"
        "/tmp/cronjob.tmp"
        "/tmp/cron.log"
    )
    
    for file in "${temp_files[@]}"; do
        [ -f "$file" ] && rm -f "$file" > /dev/null 2>&1
    done
}

# 注册退出清理
trap cleanup EXIT INT TERM

# 定义下载源
SCRIPT_URLS=(
    "https://ailg.ggbond.org/xy_ailg.sh"
    "https://gbox.ggbond.org/xy_ailg.sh"
    "https://xy.ggbond.org/xy/xy_ailg.sh"
)

# 下载主脚本
download_success=0
for url in "${SCRIPT_URLS[@]}"; do
    if command -v curl >/dev/null 2>&1; then
        download_cmd="curl -sL --connect-timeout 20 $url -o /tmp/xy_ailg.sh"
    else
        download_cmd="wget -qO /tmp/xy_ailg.sh --timeout=20 $url"
    fi

    if eval "$download_cmd"; then
        if [ -s /tmp/xy_ailg.sh ]; then
            if grep -q "fuck_docker" /tmp/xy_ailg.sh; then
                download_success=1
                break
            else
                rm -f /tmp/xy_ailg.sh
            fi
        else
            rm -f /tmp/xy_ailg.sh
        fi
    else
        WARN "从 ${url} 下载失败,尝试其他源..."
    fi
done

if [ $download_success -eq 1 ]; then
    # 添加执行权限
    chmod +x /tmp/xy_ailg.sh
    
    # 执行主脚本
    INFO "初始化完成..."
    bash /tmp/xy_ailg.sh "$@"

    rm -f /tmp/xy_ailg.sh
    
else
    ERROR "所有下载源均失败,请检查网络连接后重试!"
    exit 1
fi 