#!/bin/bash

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
# 小雅G-Box工具函数库
# ——————————————————————————————————————————————————————————————————————————————————    
# 包含以下功能模块:
# - 颜色输出函数
# - 系统检查和依赖安装
# - 通用工具函数
# - Docker相关操作
#
# Copyright (c) 2025 AI老G <https://space.bilibili.com/252166818>
# ——————————————————————————————————————————————————————————————————————————————————

# ——————————————————————————————————————————————————————————————————————————————————
# 颜色输出函数
# ——————————————————————————————————————————————————————————————————————————————————
setup_colors() {
    Blue="\033[1;34m"
    Green="\033[1;32m"
    Red="\033[1;31m"
    Yellow="\033[1;33m"
    NC="\033[0m"
    INFO="[${Green}INFO${NC}]"
    ERROR="[${Red}ERROR${NC}]"
    WARN="[${Yellow}WARN${NC}]"
}

function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

# ——————————————————————————————————————————————————————————————————————————————————
# 系统检查函数
# ——————————————————————————————————————————————————————————————————————————————————

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查是否以root用户运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        ERROR "此脚本必须以 root 身份运行！"
        INFO "请在ssh终端输入命令 'sudo -i' 回车，再输入一次当前用户密码，切换到 root 用户后重新运行脚本。"
        exit 1
    fi
}

# 检查和安装依赖
check_env() {
    local required_commands=(
        "curl" "wget"
        "jq"
        "docker"
        "grep" "sed" "awk"
        "stat"
        "du" "df" "mount" "umount" "losetup"
        "ps" "kill"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            WARN "缺少命令: $cmd，尝试安装..."
            if ! install_command "$cmd"; then
                ERROR "安装 $cmd 失败，请手动安装后再运行脚本"
                return 1
            fi
        fi
    done

    if ! docker info &> /dev/null; then
        ERROR "Docker 未运行或者当前用户无权访问 Docker"
        return 1
    fi

    if ! grep -q 'alias gbox' /etc/profile; then
        echo -e "alias gbox='bash -c \"\$(curl -sSLf https://ailg.ggbond.org/xy_install.sh)\"'" >> /etc/profile
    fi
    source /etc/profile

    emby_list=()
    emby_order=()
    img_order=()
    
    return 0
}

# 安装命令
install_command() {
    local pkg="$1"

    case "$pkg" in
        "docker") 
            _install_docker
            return $?
            ;;
        "losetup"|"mount"|"umount") pkg="util-linux" ;;
        "kill"|"ps"|"pkill") pkg="procps" ;;
        "grep"|"cp"|"mv"|"awk"|"sed"|"stat"|"du"|"df") pkg="coreutils" ;;
    esac

    # 尝试使用不同的包管理器安装
    if command -v apt-get &> /dev/null; then
        apt-get update -y
        apt-get install -y "$pkg"
    elif command -v yum &> /dev/null; then
        yum makecache fast
        yum install -y "$pkg"
    elif command -v dnf &> /dev/null; then
        dnf makecache
        dnf install -y "$pkg"
    elif command -v zypper &> /dev/null; then
        zypper refresh
        zypper install -y "$pkg"
    elif command -v pacman &> /dev/null; then
        pacman -Sy
        pacman -S --noconfirm "$pkg"
    elif command -v brew &> /dev/null; then
        brew update
        brew install "$pkg"
    elif command -v apk &> /dev/null; then
        apk update
        apk add --no-cache "$pkg"
    elif command -v opkg &> /dev/null; then
        opkg update
        case "$pkg" in
            "awk") pkg="gawk" ;; 
            "stat") pkg="coreutils-stat" ;;
            "du"|"df") pkg="coreutils" ;;
            "mount"|"umount") pkg="mount-utils" ;;
            *) pkg="$pkg" ;;
        esac
        opkg install "$pkg"
    else
        ERROR "未找到支持的包管理器，请手动安装 $pkg"
        return 1
    fi

    # 验证安装是否成功
    if ! command -v "$pkg" &> /dev/null; then
        ERROR "$pkg 安装失败"
        return 1
    fi

    return 0
}

# Docker相关检查
function _install_docker() {
    if ! command -v docker &> /dev/null; then
        WARN "docker 未安装，脚本尝试自动安装..."
        wget -qO- get.docker.com | bash
        if ! command -v docker &> /dev/null; then
            ERROR "docker 安装失败，请手动安装！"
            exit 1
        fi
    fi

    if ! docker info &> /dev/null; then
        ERROR "Docker 未运行或者当前用户无权访问 Docker"
        return 1
    fi
}

# 检查QNAP系统
check_qnap() {
    if grep -Eqi "QNAP" /etc/issue > /dev/null 2>&1; then
        INFO "检测到您是QNAP威联通系统，正在尝试更新安装环境，以便速装emby/jellyfin……"
        
        if ! command -v opkg &> /dev/null; then
            wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | sh
            echo 'export PATH=$PATH:/opt/bin:/opt/sbin' >> ~/.profile
            source ~/.profile
        fi

        [ -f /bin/mount ] && mv /bin/mount /bin/mount.bak
        [ -f /bin/umount ] && mv /bin/umount /bin/umount.bak
        [ -f /usr/local/sbin/losetup ] && mv /usr/local/sbin/losetup /usr/local/sbin/losetup.bak

        opkg update

        for pkg in mount-utils losetup; do
            success=false
            for i in {1..3}; do
                if opkg install $pkg; then
                    success=true
                    break
                else
                    INFO "尝试安装 $pkg 失败，重试中 ($i/3)..."
                fi
            done
            if [ "$success" = false ]; then
                INFO "$pkg 安装失败，恢复备份文件并退出脚本。"
                [ -f /bin/mount.bak ] && mv /bin/mount.bak /bin/mount
                [ -f /bin/umount.bak ] && mv /bin/umount.bak /bin/umount
                [ -f /usr/local/sbin/losetup.bak ] && mv /usr/local/sbin/losetup.bak /usr/local/sbin/losetup
                exit 1
            fi
        done

        if [ -f /opt/bin/mount ] && [ -f /opt/bin/umount ] && [ -f /opt/sbin/losetup ]; then
            cp /opt/bin/mount /bin/mount
            cp /opt/bin/umount /bin/umount
            cp /opt/sbin/losetup /usr/local/sbin/losetup
            INFO "已完成安装环境更新！"
        else
            INFO "安装文件缺失，恢复备份文件并退出脚本。"
            [ -f /bin/mount.bak ] && mv /bin/mount.bak /bin/mount
            [ -f /bin/umount.bak ] && mv /bin/umount.bak /bin/umount
            [ -f /usr/local/sbin/losetup.bak ] && mv /usr/local/sbin/losetup.bak /usr/local/sbin/losetup
            exit 1
        fi
    fi
}

# ——————————————————————————————————————————————————————————————————————————————————
# 通用工具函数
# ——————————————————————————————————————————————————————————————————————————————————

# 路径检查
check_path() {
    dir_path=$1
    if [[ ! -d "$dir_path" ]]; then
        read -t 60 -erp "您输入的目录不存在，按Y/y创建，或按其他键退出！" yn || {
            echo ""
            INFO "等待输入超时，默认不创建目录并退出"
            exit 0
        }
        case $yn in
        [Yy]*)
            mkdir -p $dir_path
            if [[ ! -d $dir_path ]]; then
                echo "您的输入有误，目录创建失败，程序退出！"
                exit 1
            else
                chmod 777 $dir_path
                INFO "${dir_path}目录创建成功！"
            fi
            ;;
        *) exit 0 ;;
        esac
    fi
}

# 检查容器是否安装
setup_status() {
    if docker container inspect "${1}" > /dev/null 2>&1; then
        echo -e "${Green}已安装${NC}"
    else
        echo -e "${Red}未安装${NC}"
    fi
}

# 端口检查
check_port() {
    local check_command result
    local port_conflict=0
    local port_conflict_list=()
    local ports_to_check=()

    case "$1" in
        "emby")
            ports_to_check=(6908)
            ;;
        "jellyfin")
            ports_to_check=(6909 6910)
            ;;
        "g-box")
            ports_to_check=(2345 2346 4567 5678 3002)
            ;;
        *)
            ports_to_check=("$1")
            ;;
    esac

    if [[ "${OSNAME}" = "macos" ]]; then
        check_command=lsof
    else
        if ! command -v netstat > /dev/null 2>&1; then
            if ! command -v lsof > /dev/null 2>&1; then
                WARN "未检测到 netstat 或 lsof 命令，跳过端口检查！"
                return 0
            else
                check_command=lsof
            fi
        else
            check_command=netstat
        fi
    fi

    for port in "${ports_to_check[@]}"; do
        if [ "${check_command}" == "netstat" ]; then
            if result=$(netstat -tuln | awk -v port="${port}" '$4 ~ ":"port"$"'); then
                if [ -z "${result}" ]; then
                    INFO "${port} 端口通过检测！"
                else
                    ERROR "${port} 端口被占用！"
                    echo "$(netstat -tulnp | awk -v port="${port}" '$4 ~ ":"port"$"')"
                    port_conflict=$((port_conflict + 1))
                    port_conflict_list+=($port)
                fi
            else
                WARN "检测命令执行错误，跳过 ${port} 端口检查！"
            fi
        elif [ "${check_command}" == "lsof" ]; then
            if ! lsof -i :"${port}" > /dev/null; then
                INFO "${port} 端口通过检测！"
            else
                ERROR "${port} 端口被占用！"
                echo "$(lsof -i :"${port}")"
                port_conflict=$((port_conflict + 1))
                port_conflict_list+=($port)
            fi
        fi
    done

    if [ $port_conflict -gt 0 ]; then
        ERROR "存在 ${port_conflict} 个端口冲突，冲突端口如下："
        for port in "${port_conflict_list[@]}"; do
            echo -e "${Red}端口 ${port} 被占用，请解决后重试！${NC}"
        done
    fi

    export PORT_CONFLICT_COUNT=$port_conflict
    export PORT_CONFLICT_LIST=("${port_conflict_list[@]}")

    return $port_conflict
}

# 空间检查
check_space() {
    free_size=$(df -P "$1" | tail -n1 | awk '{print $4}')
    free_size_G=$((free_size / 1024 / 1024))
    if [ "$free_size_G" -lt "$2" ]; then
        ERROR "空间剩余容量不够：${free_size_G}G 小于最低要求${2}G"
        return 1
    else
        INFO "磁盘可用空间：${free_size_G}G"
        return 0
    fi
}

# 检查loop回循设备支持
check_loop_support() {
    if [ ! -e /dev/loop-control ]; then
        if ! lsmod | awk '$1 == "loop"'; then
            if ! command -v modprobe &> /dev/null; then
                echo "modprobe command not found."
                return 1
            else
                if modprobe loop; then
                    if ! mknod -m 660 /dev/loop-control c 10 237; then
                        ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，请手动启用该功能后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！" && exit 1
                    fi
                else
                    ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，请手动启用该功能后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！" && exit 1
                fi
            fi
        fi
    fi

    if ls -al /dev/loop7 > /dev/null 2>&1; then
        if losetup /dev/loop7; then
            imgs=("emby-ailg.img" "emby-ailg-lite.img" "jellyfin-ailg.img" "jellyfin-ailg-lite.img" "emby-ailg-115.img" "emby-ailg-lite-115.img" "media.img" "/")
            contains=false
            for img in "${imgs[@]}"; do
                if [ "$img" = "/" ]; then
                    if losetup /dev/loop7 | grep -q "^/$"; then
                        contains=true
                        break
                    fi
                else
                    if losetup /dev/loop7 | grep -q "$img"; then
                        contains=true
                        break
                    fi
                fi
            done

            if [ "$contains" = false ]; then
                ERROR "您系统的/dev/loop7设备已被占用，可能是你没有用脚本卸载手动删除了emby的img镜像文件！"
                ERROR "请手动卸载后重装运行脚本安装！不会就删掉爬虫容后重启宿主机设备，再运行脚本安装！" && exit 1
            fi
        else
            for i in {1..3}; do
                curl -o /tmp/loop_test.img https://ailg.ggbond.org/loop_test.img
                if [ -f /tmp/loop_test.img ] && [ $(stat -c%s /tmp/loop_test.img) -gt 1024000 ]; then
                    break
                else
                    rm -f /tmp/loop_test.img
                fi
            done
            if [ ! -f /tmp/loop_test.img ] || [ $(stat -c%s /tmp/loop_test.img) -le 1024000 ]; then
                ERROR "测试文件下载失败，请检查网络后重新运行脚本！" && exit 1
            fi
            if ! losetup -o 35 /dev/loop7 /tmp/loop_test.img > /dev/null 2>&1; then
                ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，建议排查losetup命令后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！"
                rm -rf /tmp/loop_test.img
                exit 1
            else
                mkdir -p /tmp/loop_test
                if ! mount /dev/loop7 /tmp/loop_test; then
                    ERROR "您的系统环境不支持直接挂载loop回循设备，无法安装速装版emby/jellyfin，建议排查mount命令后重新运行脚本安装！或用DDS大佬脚本安装原版小雅emby！"
                    rm -rf /tmp/loop_test /tmp/loop_test.img
                    exit 1
                else
                    umount /tmp/loop_test
                    losetup -d /dev/loop7
                    rm -rf /tmp/loop_test /tmp/loop_test.img
                    return 0
                fi
            fi
        fi
    fi
}

# ——————————————————————————————————————————————————————————————————————————————————
# Docker相关操作
# ——————————————————————————————————————————————————————————————————————————————————

# Docker镜像拉取
function docker_pull() {
    [ -z "${config_dir}" ] && get_config_path
    
    if ! [[ "$skip_choose_mirror" == [Yy] ]]; then
        mirrors=()
        INFO "正在从${config_dir}/docker_mirrors.txt文件获取代理点配置……"
        if [ -f "${config_dir}/docker_mirrors.txt" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && mirrors+=("$line")
            done < "${config_dir}/docker_mirrors.txt"
        else
            ERROR "${config_dir}/docker_mirrors.txt 文件不存在！"
            return 1
        fi
        
        if command -v mktemp > /dev/null 2>&1; then
            tempfile=$(mktemp)
        else
            tempfile="/tmp/docker_pull_$$.tmp"
            touch "$tempfile"
        fi
        
        for mirror in "${mirrors[@]}"; do
            INFO "正在从${mirror}代理点为您下载镜像：${1}"
            
            if command -v timeout > /dev/null 2>&1; then
                timeout 300 docker pull "${mirror}/${1}" | tee "$tempfile"
            else
                (docker pull "${mirror}/${1}" 2>&1 | tee "$tempfile") &
                pull_pid=$!
                
                wait_time=0
                while kill -0 $pull_pid 2>/dev/null && [ $wait_time -lt 200 ]; do
                    sleep 5
                    wait_time=$((wait_time + 5))
                done
                
                if [ $wait_time -ge 200 ]; then
                    kill $pull_pid 2>/dev/null
                    wait $pull_pid 2>/dev/null
                    WARN "下载超时，正在尝试下一个镜像源..."
                    continue
                fi
            fi
            
            local_sha=$(grep 'Digest: sha256' "$tempfile" | awk -F':' '{print $3}')
            
            if [ -n "${local_sha}" ]; then
                INFO "${1} 镜像拉取成功！"
                if [ -f "${config_dir}/ailg_sha.txt" ]; then
                    sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
                fi
                echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
                
                [[ "${mirror}" == "docker.io" ]] && rm -f "$tempfile" && return 0
                
                if [ "${mirror}/${1}" != "${1}" ]; then
                    docker tag "${mirror}/${1}" "${1}" && docker rmi "${mirror}/${1}"
                fi
                
                rm -f "$tempfile"
                return 0
            else
                WARN "${1} 从 ${mirror} 拉取失败，正在尝试下一个镜像源..."
            fi
        done
        
        rm -f "$tempfile"        
        ERROR "已尝试所有镜像源，均无法拉取 ${1}，请检查网络后再试！"
        WARN "如需重新测速选择代理，请删除 ${config_dir}/docker_mirrors.txt 文件后重新运行脚本！"
        return 1
    else
        INFO "正在从官方源拉取镜像：${1}"
        tempfile="/tmp/docker_pull_$$.tmp"
        
        docker pull "${1}" | tee "$tempfile"
        local_sha=$(grep 'Digest: sha256' "$tempfile" | awk -F':' '{print $3}')
        rm -f "$tempfile"
        
        if [ -n "${local_sha}" ]; then
            INFO "${1} 镜像拉取成功！"
            if [ -f "${config_dir}/ailg_sha.txt" ]; then
                sed -i "\#${1}#d" "${config_dir}/ailg_sha.txt"
            fi
            echo "${1} ${local_sha}" >> "${config_dir}/ailg_sha.txt"
            return 0
        else
            ERROR "${1} 镜像拉取失败！"
            return 1
        fi
    fi
}

# 更新Docker镜像
update_ailg() {
    [ -n "$1" ] && update_img="$1" || { ERROR "未指定更新镜像的名称"; exit 1; }
    [ -z "${config_dir}" ] && get_config_path
    
    # 检查是否有容器使用此镜像
    local containers_info_file=""
    local containers_count=0
    
    # 添加容器ID数组，避免重复处理同一个容器
    local processed_containers=()
    
    # 检查是否有jq命令
    if command -v jq &> /dev/null; then
        containers_info_file="/tmp/containers_${update_img//[:\/]/_}.json"
        INFO "检查是否有容器依赖镜像 ${update_img}..."
        # 查找使用此镜像的容器
        for container_id in $(docker ps -a --filter "ancestor=${update_img}" --format "{{.ID}}"); do
            # 检查该容器ID是否已经处理过
            local already_processed=0
            for processed_id in "${processed_containers[@]}"; do
                if [[ "$processed_id" == "$container_id" ]]; then
                    already_processed=1
                    break
                fi
            done
            
            # 如果已处理过，则跳过
            if [[ $already_processed -eq 1 ]]; then
                continue
            fi
            
            # 添加到已处理数组
            processed_containers+=("$container_id")
            containers_count=$((containers_count + 1))
            
            # 获取容器详细信息并保存
            docker inspect "$container_id" >> "$containers_info_file"
            
            container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
            INFO "找到依赖容器: $container_name (ID: $container_id)"
            
            # 删除容器
            INFO "删除容器 $container_name..."
            docker rm -f "$container_id"
        done
    else
        containers_info_file="/tmp/containers_${update_img//[:\/]/_}.txt"
        INFO "检查是否有容器依赖镜像 ${update_img}..."
        # 查找使用此镜像的容器
        for container_id in $(docker ps -a --filter "ancestor=${update_img}" --format "{{.ID}}"); do
            # 检查该容器ID是否已经处理过
            local already_processed=0
            for processed_id in "${processed_containers[@]}"; do
                if [[ "$processed_id" == "$container_id" ]]; then
                    already_processed=1
                    break
                fi
            done
            
            # 如果已处理过，则跳过
            if [[ $already_processed -eq 1 ]]; then
                continue
            fi
            
            # 添加到已处理数组
            processed_containers+=("$container_id")
            containers_count=$((containers_count + 1))
            
            # 获取容器名称
            container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
            INFO "找到依赖容器: $container_name (ID: $container_id)"
            
            # 获取容器状态
            container_status=$(docker inspect --format '{{.State.Status}}' "$container_id")
            echo "CONTAINER_STATUS=$container_status" >> "$containers_info_file"
            
            # 获取容器基本信息并保存
            echo "CONTAINER_NAME=$container_name" >> "$containers_info_file"
            
            # 获取网络模式
            network_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container_id")
            echo "NETWORK_MODE=$network_mode" >> "$containers_info_file"
            
            # 获取重启策略
            restart_policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$container_id")
            echo "RESTART_POLICY=$restart_policy" >> "$containers_info_file"
            
            # 获取特权模式
            privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "$container_id")
            echo "PRIVILEGED=$privileged" >> "$containers_info_file"
            
            # 获取挂载点（过滤掉匿名卷）
            echo "MOUNTS_START" >> "$containers_info_file"
            docker inspect "$container_id" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}} {{end}}{{end}}' >> "$containers_info_file"
            echo "MOUNTS_END" >> "$containers_info_file"
            
            # 获取环境变量
            echo "ENV_START" >> "$containers_info_file"
            docker inspect --format '{{range .Config.Env}}{{.}} {{end}}' "$container_id" >> "$containers_info_file"
            echo "ENV_END" >> "$containers_info_file"
            
            # 获取端口映射（修正格式）
            echo "PORTS_START" >> "$containers_info_file"
            docker inspect --format '{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}:{{$p}} {{end}}' "$container_id" >> "$containers_info_file"
            echo "PORTS_END" >> "$containers_info_file"
            
            echo "CONTAINER_END" >> "$containers_info_file"
            
            # 删除容器
            INFO "删除容器 $container_name..."
            docker rm -f "$container_id"
        done
    fi
    
    # 备份旧镜像
    docker rmi "${update_img}_old" > /dev/null 2>&1
    docker tag "${update_img}" "${update_img}_old" > /dev/null 2>&1
    
    # 获取本地和远程SHA
    if [ -f $config_dir/ailg_sha.txt ]; then
        local_sha=$(grep -E "${update_img}" "$config_dir/ailg_sha.txt" | awk '{print $2}')
    else
        local_sha=$(docker inspect -f'{{index .RepoDigests 0}}' "${update_img}" 2>/dev/null | cut -f2 -d:)
    fi
    
    for i in {1..3}; do
        remote_sha=$(curl -sSLf https://ailg.ggbond.org/ailg_sha_remote.txt | grep -E "${update_img}" | awk '{print $2}')
        [ -n "${remote_sha}" ] && break
    done
    echo "remote_sha: $remote_sha"
    echo "local_sha: $local_sha"

    if [ -z "${remote_sha}" ]; then
        local org_name=$(echo "${update_img}" | cut -d'/' -f1)
        local img_name=$(echo "${update_img}" | cut -d'/' -f2 | cut -d':' -f1)
        local tag=$(echo "${update_img}" | cut -d'/' -f2 | cut -d':' -f2)
        for i in {1..3}; do
            remote_sha=$(curl -s -m 20 "https://hub.docker.com/v2/repositories/${org_name}/${img_name}/tags/${tag}" | grep -oE '[0-9a-f]{64}' | tail -1)
            [ -n "${remote_sha}" ] && break
        done
    fi

    # 判断是否需要更新
    if [ "$local_sha" != "$remote_sha" ] || { [ -z "$local_sha" ] && [ -z "$remote_sha" ]; } || ! docker inspect "${update_img}" &>/dev/null; then
        # 删除旧镜像
        docker rmi "${update_img}" > /dev/null 2>&1
        
        # 尝试拉取新镜像
        retries=0
        max_retries=3
        update_success=false
        
        while [ $retries -lt $max_retries ]; do
            if docker_pull "${update_img}"; then
                INFO "${update_img} 镜像拉取成功！"
                update_success=true
                break
            else
                WARN "${update_img} 镜像拉取失败，正在进行第 $((retries + 1)) 次重试..."
                retries=$((retries + 1))
            fi
        done
        
        # 处理更新结果
        if [ "$update_success" = true ]; then
            INFO "镜像更新成功，准备恢复容器..."
            docker rmi "${update_img}_old" > /dev/null 2>&1
            
            # 恢复容器
            if [ $containers_count -gt 0 ] && [ -f "$containers_info_file" ]; then
                # 检查是否有jq命令
                if command -v jq &> /dev/null && [[ "$containers_info_file" == *".json" ]]; then
                    restore_containers "$containers_info_file" "${update_img}"
                else
                    restore_containers_simple "$containers_info_file" "${update_img}"
                fi
            fi
            
            return 0
        else
            ERROR "${update_img} 镜像拉取失败，已达到最大重试次数！将回滚到旧版本..."
            docker tag "${update_img}_old" "${update_img}" > /dev/null 2>&1
            
            # 恢复容器
            if [ $containers_count -gt 0 ] && [ -f "$containers_info_file" ]; then
                # 检查是否有jq命令
                if command -v jq &> /dev/null && [[ "$containers_info_file" == *".json" ]]; then
                    restore_containers "$containers_info_file" "${update_img}"
                else
                    restore_containers_simple "$containers_info_file" "${update_img}"
                fi
            fi
            
            docker rmi "${update_img}_old" > /dev/null 2>&1
            return 1
        fi
    else
        INFO "${update_img} 镜像已是最新版本，无需更新！"
        docker rmi "${update_img}_old" > /dev/null 2>&1
        # 恢复容器
        if [ $containers_count -gt 0 ] && [ -f "$containers_info_file" ]; then
            # 检查是否有jq命令
            if command -v jq &> /dev/null && [[ "$containers_info_file" == *".json" ]]; then
                restore_containers "$containers_info_file" "${update_img}"
            else
                restore_containers_simple "$containers_info_file" "${update_img}"
            fi
        fi
        return 0
    fi
}

# 恢复容器
restore_containers() {
    local containers_file="$1"
    local image_name="$2"
    local restored_count=0
    local failed_count=0
    
    INFO "开始恢复依赖镜像 ${image_name} 的容器..."
    
    # 解析JSON文件中的容器信息
    for container_id in $(jq -r '.[].Id' "$containers_file"); do
        # 从保存的信息中提取容器配置
        local container_json=$(jq -r ".[] | select(.Id==\"$container_id\")" "$containers_file")
        local name=$(echo "$container_json" | jq -r '.Name' | sed 's/^\///')
        # local cmd=$(echo "$container_json" | jq -r '.Config.Cmd[]?' 2>/dev/null | tr '\n' ' ')
        # local entrypoint=$(echo "$container_json" | jq -r '.Config.Entrypoint[]?' 2>/dev/null | tr '\n' ' ')
        local network_mode=$(echo "$container_json" | jq -r '.HostConfig.NetworkMode')
        local restart_policy=$(echo "$container_json" | jq -r '.HostConfig.RestartPolicy.Name')
        
        # 提取挂载点（过滤掉匿名卷）
        local mounts=""
        while read -r mount; do
            local source=$(echo "$mount" | jq -r '.Source')
            local destination=$(echo "$mount" | jq -r '.Destination')
            local type=$(echo "$mount" | jq -r '.Type')
            local vol_name=$(echo "$mount" | jq -r '.Name')
            
            # 过滤掉匿名卷（类型为volume且名称为空，或者路径包含@docker/volumes）
            if [ "$type" != "volume" ] || [ -n "$vol_name" ]; then
                if [[ "$source" != *"@docker/volumes"* ]]; then
                    [ -n "$source" ] && [ -n "$destination" ] && mounts="$mounts -v $source:$destination"
                fi
            fi
        done < <(echo "$container_json" | jq -c '.Mounts[]?')
        
        # 提取环境变量
        local env_vars=""
        while read -r env; do
            [ -n "$env" ] && env_vars="$env_vars -e \"$env\""
        done < <(echo "$container_json" | jq -r '.Config.Env[]?')
        
        # 提取端口映射
        local ports=""
        local port_bindings=$(echo "$container_json" | jq -r '.HostConfig.PortBindings')
        if [ "$port_bindings" != "null" ] && [ "$port_bindings" != "{}" ]; then
            while read -r port_mapping; do
                local container_port=$(echo "$port_mapping" | cut -d: -f1)
                local host_port=$(echo "$port_mapping" | cut -d: -f2)
                [ -n "$container_port" ] && [ -n "$host_port" ] && ports="$ports -p $host_port:$container_port"
            done < <(echo "$port_bindings" | jq -r 'to_entries[] | "\(.key):\(.value[0].HostPort)"')
        fi
        
        # 提取其他重要参数
        local privileged=$(echo "$container_json" | jq -r '.HostConfig.Privileged')
        local privileged_param=""
        [ "$privileged" = "true" ] && privileged_param="--privileged"
        
        # 构建运行命令
        local run_cmd="docker run -d --name \"$name\" $privileged_param"
        
        # 添加网络模式
        if [ "$network_mode" = "host" ]; then
            run_cmd="$run_cmd --net=host"
        elif [ -n "$network_mode" ] && [ "$network_mode" != "default" ]; then
            run_cmd="$run_cmd --net=$network_mode"
        fi
        
        # 添加重启策略
        if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
            run_cmd="$run_cmd --restart=$restart_policy"
        fi
        
        # 添加挂载点、环境变量和端口
        [ -n "$mounts" ] && run_cmd="$run_cmd $mounts"
        [ -n "$env_vars" ] && run_cmd="$run_cmd $env_vars"
        [ -n "$ports" ] && run_cmd="$run_cmd $ports"
        
        # 添加镜像名称
        run_cmd="$run_cmd $image_name"
        
        # # 添加入口点和命令
        # [ -n "$entrypoint" ] && run_cmd="$run_cmd --entrypoint=\"$entrypoint\""
        # [ -n "$cmd" ] && run_cmd="$run_cmd $cmd"
        
        container_status=$(echo "$container_json" | jq -r '.State.Status')
        # 执行命令
        INFO "恢复容器 $name..."
        if eval "$run_cmd"; then
            if [ "$container_status" = "running" ]; then
                INFO "容器 $name 恢复并启动成功"
            else
                # 如果原容器不是running状态，创建后停止它
                INFO "容器 $name 恢复成功，正在恢复到原始状态（停止）..."
                docker stop "$name" > /dev/null 2>&1
                INFO "容器 $name 已停止，与原始状态一致"
            fi
            restored_count=$((restored_count + 1))
        else
            ERROR "容器 $name 恢复失败"
            failed_count=$((failed_count + 1))
        fi
    done
    
    # 清理临时文件
    rm -f "$containers_file"
    
    INFO "容器恢复完成: 成功 $restored_count, 失败 $failed_count"
    
    if [ $failed_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 使用docker inspect --format恢复容器的简化函数
restore_containers_simple() {
    local containers_file="$1"
    local image_name="$2"
    local restored_count=0
    local failed_count=0
    
    INFO "开始恢复依赖镜像 ${image_name} 的容器..."
    
    # 解析文本文件中的容器信息
    local container_name=""
    local network_mode=""
    local restart_policy=""
    local privileged=""
    local mounts=""
    local env_vars=""
    local ports=""
    local in_mounts=0
    local in_env=0
    local in_ports=0
    local container_status=""
    
    while IFS= read -r line; do
        if [[ "$line" == CONTAINER_NAME=* ]]; then
            # 如果已经处理过一个容器，先恢复它
            if [ -n "$container_name" ]; then
                restore_single_container
                # 重置变量
                container_name=""
                network_mode=""
                restart_policy=""
                privileged=""
                mounts=""
                env_vars=""
                ports=""
            fi
            container_name="${line#CONTAINER_NAME=}"
        elif [[ "$line" == NETWORK_MODE=* ]]; then
            network_mode="${line#NETWORK_MODE=}"
        elif [[ "$line" == RESTART_POLICY=* ]]; then
            restart_policy="${line#RESTART_POLICY=}"
        elif [[ "$line" == PRIVILEGED=* ]]; then
            privileged="${line#PRIVILEGED=}"
        elif [[ "$line" == "MOUNTS_START" ]]; then
            in_mounts=1
        elif [[ "$line" == "MOUNTS_END" ]]; then
            in_mounts=0
        elif [[ "$line" == "ENV_START" ]]; then
            in_env=1
        elif [[ "$line" == "ENV_END" ]]; then
            in_env=0
        elif [[ "$line" == "PORTS_START" ]]; then
            in_ports=1
        elif [[ "$line" == "PORTS_END" ]]; then
            in_ports=0
        elif [[ "$line" == CONTAINER_STATUS=* ]]; then
            container_status="${line#CONTAINER_STATUS=}"
        elif [[ "$line" == "CONTAINER_END" ]]; then
            # 恢复容器
            restore_single_container
            # 重置变量
            container_name=""
            network_mode=""
            restart_policy=""
            privileged=""
            mounts=""
            env_vars=""
            ports=""
            container_status=""
        elif [ $in_mounts -eq 1 ]; then
            mounts="$line"
        elif [ $in_env -eq 1 ]; then
            env_vars="$line"
        elif [ $in_ports -eq 1 ]; then
            ports="$line"
        fi
    done < "$containers_file"
    
    # 处理最后一个容器（如果有）
    if [ -n "$container_name" ]; then
        restore_single_container
    fi
    
    # 清理临时文件
    rm -f "$containers_file"
    
    INFO "容器恢复完成: 成功 $restored_count, 失败 $failed_count"
    
    if [ $failed_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
    
    # 内部函数：恢复单个容器
    function restore_single_container() {
        # 构建运行命令 - 始终使用docker run -d
        local run_cmd="docker run -d --name \"$container_name\""
        
        # 添加网络模式
        if [ "$network_mode" = "host" ]; then
            run_cmd="$run_cmd --net=host"
        elif [ -n "$network_mode" ] && [ "$network_mode" != "default" ]; then
            run_cmd="$run_cmd --net=$network_mode"
        fi
        
        # 添加重启策略
        if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
            run_cmd="$run_cmd --restart=$restart_policy"
        fi
        
        # 添加特权模式
        if [ "$privileged" = "true" ]; then
            run_cmd="$run_cmd --privileged"
        fi
        
        # 添加挂载点
        for mount in $mounts; do
            if [[ "$mount" == *":"* ]]; then
                run_cmd="$run_cmd -v $mount"
            fi
        done
        
        # 添加环境变量
        for env in $env_vars; do
            if [ -n "$env" ]; then
                run_cmd="$run_cmd -e \"$env\""
            fi
        done
        
        # 添加端口映射
        for port in $ports; do
            if [[ "$port" == *":"* ]]; then
                run_cmd="$run_cmd -p $port"
            fi
        done
        
        # 添加镜像名称
        run_cmd="$run_cmd $image_name"
        
        # 执行命令
        INFO "恢复容器 $container_name..."
        if eval "$run_cmd"; then
            if [ "$container_status" = "running" ]; then
                INFO "容器 $container_name 恢复并启动成功"
            else
                # 如果原容器不是running状态，创建后停止它
                INFO "容器 $container_name 恢复成功，正在恢复到原始状态（停止）..."
                docker stop "$container_name" > /dev/null 2>&1
                INFO "容器 $container_name 已停止，与原始状态一致"
            fi
            restored_count=$((restored_count + 1))
        else
            ERROR "容器 $container_name 恢复失败"
            failed_count=$((failed_count + 1))
        fi
    }
}

xy_media_reunzip() {
    # 初始化变量
    running_container_id=""
    
    # 添加特殊的SIGINT处理，确保Ctrl+C能立即终止脚本
    trap 'echo -e "\n${INFO} 检测到Ctrl+C，立即终止脚本"; exit 1' SIGINT
    
    # Files to process mapping - 使用普通数组代替关联数组
    FILE_OPTIONS=(
        "all.mp4"
        "115.mp4"
        "pikpak.mp4"
        "json.mp4"
        "短剧.mp4"
        "蓝光原盘.mp4"
        "config.mp4"
        "music.mp4"
    )
    
    FILE_DIRS=(
        "📺画质演示测试（4K，8K，HDR，Dolby） 动漫 每日更新 测试 电影 电视剧 纪录片 纪录片（已刮削） 综艺 音乐"
        "115"
        "PikPak"
        "json"
        "短剧"
        "ISO"
        "config"
        "Music"
    )

    # --- Cleanup Function ---
    cleanup() {
        INFO "Attempting cleanup..."

        # 终止所有可能的子进程
        local script_pid=$$
        
        # 检查pkill命令是否可用
        if command -v pkill &>/dev/null; then
            # 首先尝试使用SIGTERM终止子进程
            pkill -TERM -P $script_pid 2>/dev/null || true
            sleep 1
            # 如果子进程仍然存在，使用SIGKILL终止
            pkill -KILL -P $script_pid 2>/dev/null || true
        else
            # 如果pkill不可用，尝试使用ps和kill组合
            if command -v ps &>/dev/null; then
                # 获取所有子进程PID
                local child_pids=$(ps -o pid --no-headers --ppid $script_pid 2>/dev/null)
                if [ -n "$child_pids" ]; then
                    INFO "终止子进程: $child_pids"
                    # 先尝试SIGTERM
                    for pid in $child_pids; do
                        kill -TERM $pid 2>/dev/null || true
                    done
                    sleep 1
                    # 再尝试SIGKILL
                    for pid in $child_pids; do
                        kill -KILL $pid 2>/dev/null || true
                    done
                fi
            else
                WARN "无法终止子进程: ps和pkill命令均不可用"
            fi
        fi
        
        # 终止可能的Docker容器
        if [ -n "$running_container_id" ]; then
            INFO "Stopping running Docker container..."
            docker stop $running_container_id >/dev/null 2>&1 || true
            docker rm $running_container_id >/dev/null 2>&1 || true
        fi
        
        # Unmount if mounted
        if [ -n "$img_mount" ] && mount | grep -q " ${img_mount} "; then
            INFO "Unmounting ${img_mount}..."
            umount "${img_mount}" || WARN "Failed to unmount ${img_mount}"
        fi
        
        INFO "Cleanup attempt finished."
        
        # 强制退出脚本，确保不会继续执行
        # 注意：这会导致trap再次被触发，但由于我们使用exit 1而不是kill，不会导致无限循环
        exit 1
    }
    # 捕获EXIT、SIGHUP、SIGINT和SIGTERM信号
    trap cleanup EXIT SIGHUP SIGINT SIGTERM

    # --- File Processing Functions ---
    prepare_directories() {
        # Remove old directories in intermediate_dir based on files to process
        for file_to_download in "${files_to_process[@]}"; do
            # 查找文件在FILE_OPTIONS中的索引
            local idx=-1
            for i in "${!FILE_OPTIONS[@]}"; do
                if [ "${FILE_OPTIONS[$i]}" = "$file_to_download" ]; then
                    idx=$i
                    break
                fi
            done
            
            # 如果找到了索引，获取对应的目录
            if [ $idx -ge 0 ]; then
                local dir_names_str="${FILE_DIRS[$idx]}"
                if [ "$file_to_download" == "config.mp4" ]; then
                    INFO "删除旧的config目录: ${img_mount}/config"
                    rm -rf "${img_mount:?}/config" # Protect against empty vars
                else
                    # Handle multiple dirs for all.mp4
                    IFS=' ' read -r -a dir_array <<< "$dir_names_str"
                    for dir_name_part in "${dir_array[@]}"; do
                        if [ -n "$dir_name_part" ]; then # Ensure not empty
                            INFO "删除旧的数据目录: ${img_mount}/xiaoya/${dir_name_part}"
                            rm -rf "${img_mount:?}/xiaoya/${dir_name_part:?}"
                        fi
                    done
                fi
            fi
        done
    }

    download_and_extract() {
        local file_to_download=$1
        INFO "处理文件: $file_to_download"
        
        # 检查文件是否已存在且下载完成
        local skip_download=false
        if [ -f "${source_dir}/${file_to_download}" ] && [ ! -f "${source_dir}/${file_to_download}.aria2" ]; then
            INFO "文件 ${file_to_download} 已存在且下载完成，跳过下载步骤"
            skip_download=true
        fi

        if update_ailg ailg/ggbond:latest; then
            INFO "ailg/ggbond:latest 镜像更新成功！"
        else
            ERROR "ailg/ggbond:latest 镜像更新失败，请检查网络后重新运行脚本！"
            return 1
        fi
        
        # 添加处理中断的函数
        handle_interrupt() {
            INFO "检测到中断，正在清理..."
            
            # 终止Docker容器
            if [ -n "$running_container_id" ]; then
                docker stop $running_container_id >/dev/null 2>&1 || true
                docker rm $running_container_id >/dev/null 2>&1 || true
                running_container_id=""
            fi
            
            # 终止所有可能的子进程
            local script_pid=$$
            
            # 检查pkill命令是否可用
            if command -v pkill &>/dev/null; then
                pkill -TERM -P $script_pid 2>/dev/null || true
            else
                # 如果pkill不可用，尝试使用ps和kill组合
                if command -v ps &>/dev/null; then
                    # 获取所有子进程PID
                    local child_pids=$(ps -o pid --no-headers --ppid $script_pid 2>/dev/null)
                    if [ -n "$child_pids" ]; then
                        INFO "终止子进程: $child_pids"
                        for pid in $child_pids; do
                            kill -TERM $pid 2>/dev/null || true
                        done
                    fi
                fi
            fi
            
            exit 1
        }
        
        # 临时设置中断处理
        trap handle_interrupt SIGINT SIGTERM
        
        if [ "$skip_download" = true ]; then
            # 直接解压已有文件
            running_container_id=$(docker run -d --rm --net=host \
                -v "${source_dir}:/source_temp_dir" \
                -v "${img_mount}:/dist" \
                ailg/ggbond:latest \
                bash -c "cd /source_temp_dir && \
                        echo '正在解压 ${file_to_download}...' && \
                        if [ \"$file_to_download\" = \"config.mp4\" ]; then \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/\" ; \
                        else \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/xiaoya\" ; \
                        fi")
            
            # 等待容器完成
            docker wait $running_container_id >/dev/null 2>&1
            extract_status=$?
            running_container_id=""
        else
            # 下载并解压文件
            running_container_id=$(docker run -d --rm --net=host \
                -v "${source_dir}:/source_temp_dir" \
                -v "${img_mount}:/dist" \
                ailg/ggbond:latest \
                bash -c "cd /source_temp_dir && \
                        echo '正在下载 ${file_to_download}...' && \
                        aria2c -o \"${file_to_download}\" --auto-file-renaming=false --allow-overwrite=true -c -x6 \"${xiaoya_addr}/d/元数据/${file_to_download}\" && \
                        echo '正在解压 ${file_to_download}...' && \
                        if [ \"$file_to_download\" = \"config.mp4\" ]; then \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/\" ; \
                        else \
                            7z x -aoa -bb1 -mmt=16 \"${file_to_download}\" -o\"/dist/xiaoya\" ; \
                        fi")
            
            # 等待容器完成
            docker wait $running_container_id >/dev/null 2>&1
            extract_status=$?
            running_container_id=""
        fi
        
        # 恢复原来的中断处理
        trap cleanup EXIT SIGHUP SIGINT SIGTERM
        
        if [ $extract_status -eq 0 ]; then
            INFO "√ $file_to_download 处理成功."
            return 0
        else
            ERROR "× $file_to_download 处理失败."
            return 1
        fi
    }

    get_remote_file_sizes() {
        local files_to_check=("$@")
        local total_size_bytes=0
        
        for file_to_check in "${files_to_check[@]}"; do
            INFO "获取远程文件 $file_to_check 的大小..."
            local remote_file_url="${xiaoya_addr}/d/元数据/${file_to_check}"
            local remote_size=0
            local attempts=0
            local max_attempts=3
            
            while [ $attempts -lt $max_attempts ]; do
                let attempts+=1
                INFO "尝试 $attempts/$max_attempts 获取 $file_to_check 的远程大小"
                remote_size=$(curl -sL -D - --max-time 10 "$remote_file_url" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r' | tail -n1)
                
                if [[ "$remote_size" =~ ^[0-9]+$ ]] && [ "$remote_size" -gt 10000000 ]; then
                    INFO "成功获取 $file_to_check 的远程大小: $remote_size 字节"
                    break
                else
                    WARN "获取 $file_to_check 的远程大小失败 (得到 '$remote_size')，尝试 $attempts/$max_attempts"
                    if [ $attempts -lt $max_attempts ]; then
                        sleep 2
                    fi
                    remote_size=0
                fi
            done
            if [ "$remote_size" -eq 0 ]; then
                ERROR "无法获取 $file_to_check 的远程大小"
                exit 1
            fi
            
            total_size_bytes=$((total_size_bytes + remote_size))
            if [ -f "${source_dir}/${file_to_check}" ]; then
                local local_size_bytes=$(stat -c%s "${source_dir}/${file_to_check}")
                if [ "$remote_size" -ne "$local_size_bytes" ]; then
                INFO "本地文件 $file_to_check 大小($local_size_bytes 字节)与远程文件大小($remote_size 字节)不一致，需要重新下载"
                rm -f "${source_dir}/${file_to_check}"
                fi
            fi
        done

        total_size_gb=$((total_size_bytes / 1024 / 1024 / 1024 + 5))
        INFO "所有选定文件所需总大小为: $total_size_gb GB"
    }

    # --- Main Function ---
    media_reunzip_main() {
        if [[ $st_gbox =~ "未安装" ]]; then
            ERROR "请先安装G-Box，再执行本安装！"
            main_menu
            return
        fi

        WARN "当前此功能只适配4.9版本的emby，如果是4.8版的不要用此功能更新config"
        WARN "可以用此功能更新4.8版emby的其他元数据，不要更新config,否则会emby无法启动!"
        WARN "如果用此功能更新4.8版config之外的元数据，需要自己手动添加媒体库后扫描媒体库完成更新和入库！"
        read -p "是否继续? (y/n): " confirm_continue
        if [[ ! "$confirm_continue" =~ ^[Yy]$ ]]; then
            main_menu
            return
        fi

        mount_img || exit 1
        
        INFO "当前挂载模式: $mount_type"
        if [ -n "${emby_name}" ]; then
            if ! docker stop "${emby_name}" > /dev/null 2>&1; then
                WARN "停止容器 ${emby_name} 失败"
                exit 1
            fi
        fi
        [ -z "${config_dir}" ] && get_config_path

        if [ -s $config_dir/docker_address.txt ]; then
            xiaoya_addr=$(head -n1 $config_dir/docker_address.txt)
        else
            echo "请先配置 $config_dir/docker_address.txt，以便获取docker 地址"
            exit
        fi   
        # Verify xiaoya address is accessible
        if ! curl -siL "${xiaoya_addr}/d/README.md" | grep -v 302 | grep -q "x-oss-"; then
            ERROR "无法连接到小雅alist: $xiaoya_addr"
            exit 1
        fi
        
        docker_addr="$xiaoya_addr"
        
        # Ask user to select which files to process
        echo -e "\n请选择要重新下载和解压的文件:"
        
        # 根据mount_type显示选择限制信息
        if [[ "$mount_type" == "config" ]]; then
            WARN "当前为config镜像挂载模式，只能选择 config.mp4 文件"
        elif [[ "$mount_type" == "media" ]]; then
            WARN "当前为媒体库镜像挂载模式，不能选择 config.mp4 文件"
        fi
        
        # 使用FILE_OPTIONS数组代替file_options
        # 初始化选择状态数组，0表示未选择，1表示已选择
        selected_status=()
        for ((i=0; i<${#FILE_OPTIONS[@]}; i++)); do
            selected_status[i]=0
        done
        
        while true; do
            # Display current selection
            for index in "${!FILE_OPTIONS[@]}"; do
                local file_opt="${FILE_OPTIONS[$index]}"
                local status_char="×"; local color="$Red"
                local disabled=""
                
                # 检查选择限制
                if [[ "$mount_type" == "config" && "$file_opt" != "config.mp4" ]]; then
                    status_char="❌"; color="$Red"
                    disabled=" (不可选择)"
                elif [[ "$mount_type" == "media" && "$file_opt" == "config.mp4" ]]; then
                    status_char="❌"; color="$Red"
                    disabled=" (不可选择)"
                elif [ "${selected_status[$index]}" -eq 1 ]; then 
                    status_char="√"; color="$Green"
                fi
                
                printf "[ %-1d ] ${color}[%s] %s${NC}%s\n" $((index + 1)) "$status_char" "$file_opt" "$disabled"
            done
            printf "[ 0 ] 确认并继续\n"
            
            local select_input
            # 使用-t选项设置超时，确保能够定期检查信号
            read -t 60 -erp "请输入序号(0-${#FILE_OPTIONS[@]})，可用逗号分隔多选，或按Ctrl+C退出: " select_input || {
                # 如果read超时，提示用户并继续
                echo ""
                INFO "等待输入超时，请重新输入或按Ctrl+C退出"
                continue
            }
            
            # 处理输入为0的情况
            if [[ "$select_input" == "0" ]]; then
                local count_selected=0
                for ((i=0; i<${#selected_status[@]}; i++)); do
                    if [ "${selected_status[$i]}" -eq 1 ]; then 
                        let count_selected+=1
                    fi
                done
                if [ $count_selected -eq 0 ]; then 
                    ERROR "至少选择一个文件"
                else 
                    break
                fi
                continue
            fi
            
            # 替换中文逗号为英文逗号
            select_input=${select_input//，/,}
            
            # 分割输入的序号
            IFS=',' read -ra select_nums <<< "$select_input"
            
            # 处理每个序号
            for select_num in "${select_nums[@]}"; do
                # 去除空格
                select_num=$(echo "$select_num" | tr -d ' ')
                
                if [[ "$select_num" =~ ^[0-9]+$ ]]; then
                    if [ "$select_num" -ge 1 ] && [ "$select_num" -le ${#FILE_OPTIONS[@]} ]; then
                        idx=$((select_num-1))
                        local file_to_select="${FILE_OPTIONS[$idx]}"
                        
                        # 检查选择合法性
                        local selection_valid=true
                        if [[ "$mount_type" == "config" && "$file_to_select" != "config.mp4" ]]; then
                            ERROR "配置镜像模式下只能选择 config.mp4 文件"
                            selection_valid=false
                        elif [[ "$mount_type" == "media" && "$file_to_select" == "config.mp4" ]]; then
                            ERROR "媒体库镜像模式下不能选择 config.mp4 文件"
                            selection_valid=false
                        fi
                        
                        # 如果选择合法，则切换选择状态
                        if [ "$selection_valid" = true ]; then
                            selected_status[$idx]=$((1 - selected_status[$idx]))
                            if [ "${selected_status[$idx]}" -eq 1 ]; then
                                INFO "已选择: ${FILE_OPTIONS[$idx]}"
                            else
                                INFO "已取消选择: ${FILE_OPTIONS[$idx]}"
                            fi
                        fi
                    else 
                        ERROR "无效序号: $select_num，请输入1-${#FILE_OPTIONS[@]}之间的数字"
                    fi
                else 
                    ERROR "无效输入: $select_num，请输入数字"
                fi
            done
        done
        
        # Create array of files to process
        files_to_process=()
        for index in "${!FILE_OPTIONS[@]}"; do
            if [ "${selected_status[$index]}" -eq 1 ]; then
                files_to_process+=("${FILE_OPTIONS[$index]}")
            fi
        done
        
        INFO "将处理以下文件: ${files_to_process[*]}"
        
        # 获取用户输入的source_dir并检查空间是否足够
        while true; do
            read -t 60 -erp "请输入临时存放下载文件的目录（默认：/tmp/xy_reunzip_source）: " source_dir || {
                echo ""
                INFO "等待输入超时，请重新输入或按Ctrl+C退出"
                continue
            }
            source_dir=${source_dir:-/tmp/xy_reunzip_source}
            check_path "$source_dir"
            
            # 获取所有选定文件的总大小
            get_remote_file_sizes "${files_to_process[@]}"

            if check_space "$source_dir" "$total_size_gb"; then
                break
            else
                read -t 60 -erp "是否选择其他目录? (y/n): " choose_another || {
                    echo ""
                    INFO "等待输入超时，默认选择其他目录"
                    choose_another="y"
                }
                if [[ ! "$choose_another" =~ ^[Yy]$ ]]; then
                    ERROR "由于空间不足，脚本终止"
                    exit 1
                fi
            fi
        done

        # Prepare directories for processing
        prepare_directories
        
        # 解压后的文件通常比原始文件大1.5倍
        required_intermediate_gb=$(awk "BEGIN {printf \"%.0f\", $total_size_gb * 1.5}")
        
        # 检查镜像空间是否足够
        if ! check_space "$img_mount" "$required_intermediate_gb"; then
            WARN "${img_path}镜像空间不足，请在一键脚本主菜单选择X再选择6对其扩容后重试！"
            exit 1
        fi

        
        # Process each selected file
        for file_to_process in "${files_to_process[@]}"; do
            if ! download_and_extract "$file_to_process"; then
                ERROR "文件 $file_to_process 处理失败，请手动删除${source_dir}/${file_to_process}文件"
            else
                rm -f "${source_dir}/${file_to_process}"
            fi
        done
        
        # Final success message
        INFO "所有文件处理完成"
        umount "$img_mount" && INFO "镜像卸载完成" || WARN "卸载 $img_mount 失败"
        [ -n "${emby_name}" ] && docker start "${emby_name}" || INFO "容器 ${emby_name} 未启动"
        
        INFO "脚本执行完成"
    }
    media_reunzip_main "$@"
}

# 初始化颜色
setup_colors

# 导出颜色变量
export Blue Green Red Yellow NC INFO ERROR WARN

# 导出函数
export -f INFO ERROR WARN \
    check_path check_port check_space check_root check_env check_loop_support check_qnap \
    setup_status command_exists \
    docker_pull update_ailg restore_containers restore_containers_simple \
    xy_media_reunzip