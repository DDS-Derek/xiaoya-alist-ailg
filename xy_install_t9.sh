#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2086

PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

Blue="\033[1;34m"
Green="\033[1;32m"
Red="\033[1;31m"
Yellow="\033[1;33m"
NC="\033[0m"
INFO="[${Green}INFO${NC}]"
ERROR="[${Red}ERROR${NC}]"
WARN="[${Yellow}WARN${NC}]"

function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

function root_need() {
    if [[ $EUID -ne 0 ]]; then
        ERROR '此脚本必须以 root 身份运行！'
        exit 1
    fi
}

function ___install_docker() {

    if ! which docker; then
        WARN "docker 未安装，脚本尝试自动安装..."
        wget -qO- get.docker.com | bash
        if which docker; then
            INFO "docker 安装成功！"
        else
            ERROR "docker 安装失败，请手动安装！"
            exit 1
        fi
    fi

}

install_package() {
    local package=$1
    local install_cmd="$2 $package"

    if ! which $package > /dev/null 2>&1; then
        WARN "$package 未安装，脚本尝试自动安装..."
        if eval "$install_cmd"; then
            INFO "$package 安装成功！"
        else
            ERROR "$package 安装失败，请手动安装！"
            exit 1
        fi
    fi
}

packages_need() {
    local update_cmd
    local install_cmd

    if [ -f /etc/debian_version ]; then
        update_cmd="apt update -y"
        install_cmd="apt install -y"
    elif [ -f /etc/redhat-release ]; then
        install_cmd="yum install -y"
    elif [ -f /etc/SuSE-release ]; then
        update_cmd="zypper refresh"
        install_cmd="zypper install"
    elif [ -f /etc/alpine-release ]; then
        install_cmd="apk add"
    elif [ -f /etc/arch-release ]; then
        update_cmd="pacman -Sy --noconfirm"
        install_cmd="pacman -S --noconfirm"
    else
        ERROR "不支持的操作系统."
        exit 1
    fi

    [ -n "$update_cmd" ] && eval "$update_cmd"
    install_package "curl" "$install_cmd"
    if ! which wget; then
        install_package "wget" "$install_cmd"
    fi
    ___install_docker
}

function check_space() {
    free_size=$(df -P "$1" | tail -n1 | awk '{print $4}')
    free_size_G=$((free_size / 1024 / 1024))
    if [ "$free_size_G" -le "$2" ]; then
        ERROR "空间剩余容量不够：${free_size_G}G 小于最低要求${2}G"
        exit 1
    else
        INFO "磁盘可用空间：${free_size_G}G"
    fi
}

function get_emby_image() {
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        emby_image="emby/embyserver:4.8.0.56"
        ;;
    "aarch64" | *"arm64"* | *"armv8"* | *"arm/v8"*)
        emby_image="emby/embyserver_arm64v8:4.8.0.56"
        ;;
    "armv7l")
        emby_image="emby/embyserver_arm32v7:4.8.0.56"
        ;;
    *)
        ERROR "不支持你的CPU架构：$cpu_arch"
        exit 1
        ;;
    esac
    for i in {1..3}; do
        if docker_pull $emby_image; then
            INFO "${emby_image}镜像拉取成功！"
            break
        fi
    done
    docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image} || (ERROR "${emby_image}镜像拉取失败，请手动安装emby，无需重新运行本脚本，小雅媒体库在${media_dir}！" && exit 1)
}

function get_jellyfin_image() {
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        linux_version=$(uname -r | cut -d"." -f1)
        if [ "${linux_version}" -lt 5 ];then
            emby_image="nyanmisaka/jellyfin:240220-amd64-legacy"
        else
            emby_image="nyanmisaka/jellyfin:latest"
        fi
        ;;
    *)
        ERROR "不支持你的CPU架构：$cpu_arch"
        exit 1
        ;;
    esac
    for i in {1..3}; do
        if docker_pull $emby_image; then
            INFO "${emby_image}镜像拉取成功！"
            break
        fi
    done
    docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image} || (ERROR "${emby_image}镜像拉取失败，请手动安装emby，无需重新运行本脚本，小雅媒体库在${media_dir}！" && exit 1)
}

function get_emby_happy_image() {
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        emby_image="amilys/embyserver:4.8.0.56"
        ;;
    "aarch64" | *"arm64"* | *"armv8"* | *"arm/v8"*)
        emby_image="amilys/embyserver_arm64v8:4.8.6.0"
        ;;
    *)
        ERROR "不支持你的CPU架构：$cpu_arch"
        exit 1
        ;;
    esac
    for i in {1..3}; do
        if docker_pull $emby_image; then
            INFO "${emby_image}镜像拉取成功！"
            break
        fi
    done
    docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image} || (ERROR "${emby_image}镜像拉取失败，请手动安装emby，无需重新运行本脚本，小雅媒体库在${img_mount}！" && exit 1)
}

#获取小雅alist配置目录路径
function get_config_path() {
    docker_name=$(docker ps -a | grep ailg/alist | awk '{print $NF}')
    docker_name=${docker_name:-"xiaoya_jf"}
    if command -v jq; then
        config_dir=$(docker inspect $docker_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
    else
        #config_dir=$(docker inspect xiaoya | awk '/"Destination": "\/data"/{print a} {a=$0}'|awk -F\" '{print $4}')
        config_dir=$(docker inspect --format '{{ (index .Mounts 0).Source }}' "$docker_name")
    fi
    echo -e "\033[1;37m找到您的小雅ALIST配置文件路径是: \033[1;35m\n$config_dir\033[0m"
    echo -e "\n"
    read -erp "确认请按任意键，或者按N/n手动输入路径（注：上方显示多个路径也请选择手动输入）：" f12_select_0
    if [[ $f12_select_0 == [Nn] ]]; then
        echo -e "\033[1;35m请输入您的小雅ALIST配置文件路径:\033[0m"
        read -r config_dir
        if ! [[ -d "$config_dir" && -f "$config_dir/mytoken.txt" ]]; then
            ERROR "该路径不存在或该路径下没有mytoken.txt配置文件"
            ERROR "如果你是选择全新目录重装小雅alist，请先删除原来的容器，再重新运行本脚本！"
            ERROR -e "\033[1;31m您选择的目录不正确，程序退出。\033[0m"
            exit 1
        fi
    fi
}

function get_jf_media_path() {
    jf_name=${1}
    if command -v jq; then
        media_dir=$(docker inspect $jf_name | jq -r '.[].Mounts[] | select(.Destination=="/media") | .Source')
    else
        media_dir=$(docker inspect $jf_name | awk '/"Destination": "\/media"/{print a} {a=$0}' | awk -F\" '{print $4}')
    fi
    if [[ -n $media_dir ]]; then
        media_dir=$(dirname "$media_dir")
        echo -e "\033[1;37m找到您的小雅姐夫媒体库路径是: \033[1;35m\n$media_dir\033[0m"
        echo -e "\n"
        read -erp "确认请按任意键，或者按N/n手动输入路径：" f12_select_2
        if [[ $f12_select_2 == [Nn] ]]; then
            echo -e "\033[1;35m请输入您的小雅姐夫媒体库路径:\033[0m"
            read -r media_dir
            check_path $media_dir
        fi
        echo -e "\n"
    else
        echo -e "\033[1;35m请输入您的小雅姐夫媒体库路径:\033[0m"
        read -r media_dir
        check_path $media_dir
    fi
}

function get_emby_media_path() {
    emby_name=${1:-emby}
    if command -v jq; then
        media_dir=$(docker inspect $emby_name | jq -r '.[].Mounts[] | select(.Destination=="/media") | .Source')
    else
        media_dir=$(docker inspect $emby_name | awk '/"Destination": "\/media"/{print a} {a=$0}' | awk -F\" '{print $4}')
    fi
    if [[ -n $media_dir ]]; then
        media_dir=$(dirname "$media_dir")
        echo -e "\033[1;37m找到您原来的小雅emby媒体库路径是: \033[1;35m\n$media_dir\033[0m"
        echo -e "\n"
        read -erp "确认请按任意键，或者按N/n手动输入路径：" f12_select_1
        if [[ $f12_select_1 == [Nn] ]]; then
            echo -e "\033[1;35m请输入您的小雅emby媒体库路径:\033[0m"
            read -r media_dir
            check_path $media_dir
        fi
        echo -e "\n"
    else
        echo -e "\033[1;35m请输入您的小雅emby媒体库路径:\033[0m"
        read -r media_dir
        check_path $media_dir
    fi
}

meta_select() {
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、config.mp4 —— 小雅姐夫的配置目录数据\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、all.mp4 —— 除pikpak之外的所有小雅元数据\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m3、pikpak.mp4 —— pikpak元数据（需魔法才能观看）\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m4、全部安装\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    echo -e "请选择您\033[1;31m需要安装\033[0m的元数据(输入序号，多项用逗号分隔）："
    read -r f8_select
    if ! [[ $f8_select =~ ^[1-4]([\,\，][1-4])*$ ]]; then
        echo "输入的序号无效，请输入1到3之间的数字。"
        exit 1
    fi

    if ! [[ $f8_select == "4" ]]; then
        files=("config_jf.mp4" "all_jf.mp4" "pikpak_jf.mp4")
        for i in {1..3}; do
            file=${files[$i - 1]}
            if ! [[ $f8_select == *$i* ]]; then
                sed -i "/aria2c.*$file/d" /tmp/update_meta_jf.sh
                sed -i "/7z.*$file/d" /tmp/update_meta_jf.sh
            else
                if [[ -f $media_dir/temp/$file ]] && ! [[ -f $media_dir/temp/$file.aria2 ]]; then
                    WARN "${Yellow}${file}文件已在${media_dir}/temp目录存在,是否要重新解压？$NC"
                    read -erp "请选择：（是-按任意键，否-按N/n键）" yn
                    if [[ $yn == [Nn] ]]; then
                        sed -i "/7z.*$file/d" /tmp/update_meta_jf.sh
                        sed -i "/aria2c.*$file/d" /tmp/update_meta_jf.sh
                    else
                        remote_size=$(curl -sL -D - -o /dev/null --max-time 5 "$docker_addr/d/ailg_jf/${file}" | grep "Content-Length" | cut -d' ' -f2)
                        local_size=$(du -b $media_dir/temp/$file | cut -f1)
                        [[ $remote_size == "$local_size" ]] && sed -i "/aria2c.*$file/d" /tmp/update_meta_jf.sh
                    fi
                fi
            fi
        done
    fi
}

get_emby_status() {
    declare -gA emby_list
    declare -ga emby_order

    while read -r container_id; do
        if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' $container_id | grep -qE "/xiaoya$ /media\b|\.img /media\.img"; then
            container_name=$(docker ps -a --format '{{.Names}}' --filter "id=$container_id")
            host_path=$(docker inspect --format '{{ range .Mounts }}{{ println .Source }}{{ end }}' $container_id | grep -E "/xiaoya$|\.img\b")
            emby_list[$container_name]=$host_path
            emby_order+=("$container_name")
        fi
    done < <(docker ps -a | grep -E "${search_img}" | awk '{print $1}')

    if [ ${#emby_list[@]} -ne 0 ]; then
        echo -e "\033[1;37m默认会关闭以下您已安装的小雅emby/jellyfin容器，并删除名为emby/jellyfin_xy的容器！\033[0m"
        for index in "${!emby_order[@]}"; do
            name=${emby_order[$index]}
            printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name ${emby_list[$name]}
        done
    fi
}

#镜像代理的内容抄的DDSRem大佬的，适当修改了一下
function docker_pull() {
    [ -z "${config_dir}" ] && get_config_path
    local mirrors=("docker.io" "registry-docker-hub-latest-9vqc.onrender.com" "docker.fxxk.dedyn.io" "docker.chenby.cn" "dockerproxy.com" "hub.uuuadc.top" "docker.jsdelivr.fyi" "docker.registry.cyou" "dockerhub.anzu.vip")
    if [ -s "${config_dir}/docker_mirrors.txt" ]; then
        mirrors=()
        while IFS= read -r line; do
            mirrors+=("$line")
        done < "${config_dir}/docker_mirrors.txt"
    else
        for mirror in "${mirrors[@]}"; do
            printf "%s\n" "$mirror" >> "${config_dir}/docker_mirrors.txt"
        done
    fi

    for mirror in "${mirrors[@]}"; do
        if docker pull "${mirror}/library/hello-world:latest"; then
            INFO "${mirror}代理点连通性测试正常！正在为您下载镜像……"
            for i in {1..2}; do
                docker pull "${mirror}/${1}" && { INFO "${1} 镜像拉取成功！";break; } || WARN "${1} 镜像拉取失败，正在进行重试..."
            done
            [ -n "$(docker images -q "${mirror}/${1}")" ] && break
        fi
    done

    if [ -n "$(docker images -q "${mirror}/${1}")" ]; then
        docker tag "${mirror}/${1}" "${1}"
        docker rmi "${mirror}/${1}"
        return 0
    else
        ERROR "已尝试所有镜像代理拉取失败，程序退出，请检查网络后再试！"
        exit 1       
    fi
}

update_ailg() {
    if [[ -n "$1" ]];then
        update_img="$1"
    fi
    local name_img
    name_img=$(echo "${update_img}" | awk -F'[/:]' '{print $2}')
    local tag_img
    tag_img=$(echo "${update_img}" | awk -F'[/:]' '{print $3}')
    local_sha=$(docker inspect -f'{{index .RepoDigests 0}}' "${update_img}" | cut -f2 -d:)
    remote_sha=$(curl -s "https://hub.docker.com/v2/repositories/ailg/${name_img}/tags/${tag_img}" | grep -oE '[0-9a-f]{64}' | tail -1)
    [ -z "${remote_sha}" ] && remote_sha=$(docker exec $docker_name cat "/${name_img}_${tag_img}_sha.txt")
    if [ ! "$local_sha" == "$remote_sha" ]; then
        docker rmi "${update_img}"
        retries=0
        max_retries=3
        while [ $retries -lt $max_retries ]; do
            if docker_pull "${update_img}"; then
                INFO "${update_img} 镜像拉取成功！"
                break
            else
                WARN "${update_img} 镜像拉取失败，正在进行第 $((retries + 1)) 次重试..."
                retries=$((retries + 1))
            fi
        done
        if [ $retries -eq $max_retries ]; then
            ERROR "镜像拉取失败，已达到最大重试次数！"
            exit 1
        fi
    fi
}

function user_select1() {
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、host版 - 无🍉十全大补瓜🍉第三方播放器$NC"
    echo -e "\n"
    echo -e "\033[1;35m2、latest版 - 也是host网络模式！适配小雅emby/jellyfin速装版 有🍉十全大补瓜🍉第三方播放器，推荐安装！$NC"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    while :;do
        read -erp "请选择您要安装的版本（输入1-2，按b返回上级或按q退出）：" ver_alist
        case "$ver_alist" in
            1)
                host="host"
                _update_img="ailg/alist:hostmode"
                break
                ;;
            2)
                host=""
                _update_img="ailg/alist:latest"
                break
                ;;
            [Bb])
                clear
                main
                break
                ;;
            [Qq])
                exit
                ;;
            *)
                ERROR "输入错误，按任意键重新输入！"
                read -rn 1
                continue
                ;;
        esac
    done
    if [[ $st_alist =~ "已安装" ]]; then
        WARN "您的小雅ALIST老G版已安装，是否需要重装？"
        read -erp "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
        if [[ $re_setup == [Yy] ]]; then
            check_env
            get_config_path
            INFO "小雅ALIST老G版配置路径为：$config_dir"
            INFO "正在停止和删除旧的小雅alist容器"
            docker stop $docker_name
            docker rm $docker_name
            INFO "$docker_name 容器已删除"
            update_ailg "${_update_img}"
        else
            main
            return
        fi
    else
        check_env
        INFO "正在检查和删除已安装的小雅alist"
        rm_alist
        INFO "原有小雅alist容器已删除"
        if [[ -n "$config_dir" ]]; then
            INFO "你原来小雅alist的配置路径是：${Blue}${config_dir}${NC}，可使用原有配置继续安装！"
            read -erp "确认请按任意键，或者按N/n手动输入路径：" user_select_0
            if [[ $user_select_0 == [Nn] ]]; then
                echo -e "\033[1;35m请输入您的小雅ALIST配置文件路径:\033[0m"
                read -r config_dir
                check_path $config_dir
                INFO "小雅ALIST老G版配置路径为：$config_dir"
                update_ailg "${_update_img}"
            fi
        else
            read -erp "请输入小雅alist的安装路径，使用默认的/etc/xiaoya可直接回车：" config_dir
            [[ -z $config_dir ]] && config_dir="/etc/xiaoya"
            check_path $config_dir
            INFO "小雅ALIST老G版配置路径为：$config_dir"
            update_ailg "${_update_img}"
        fi
    fi
    curl -o /tmp/update_new_jf.sh https://xy.ggbond.org/xy/update_new_jf.sh
    for i in {1..5}; do
        grep -q "长度不对" /tmp/update_new_jf.sh && break
        echo -e "文件获取失败，正在进行第${i}次重试……"
        rm -f /tmp/update_new_jf.sh >/dev/null 2>&1
        curl -o /tmp/update_new_jf.sh https://xy.ggbond.org/xy/update_new_jf.sh
    done
    grep -q "长度不对" /tmp/update_new_jf.sh || {
        echo -e "文件获取失败，检查网络后重新运行脚本！"
        rm -f /tmp/update_new_jf.sh
        exit 1
    }
    echo "http://127.0.0.1:6908" > $config_dir/emby_server.txt
    echo "http://127.0.0.1:6909" > $config_dir/jellyfin_server.txt
    bash -c "$(cat /tmp/update_new_jf.sh)" -s $config_dir $host
    INFO "${Blue}哇塞！你的小雅ALIST老G版安装完成了！$NC"
}

function user_select2() {
    if [[ $st_alist =~ "未安装" ]]; then
        ERROR "请先安装小雅ALIST老G版，再执行本安装！"
        main
        return
    fi
    if [[ $st_jf =~ "已安装" ]]; then
        WARN "您的小雅姐夫已安装，是否需要重装？"
        read -erp "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
        if [[ $re_setup == [Yy] ]]; then
            check_env
            get_config_path
            get_jf_media_path "jellyfin_xy"
            docker stop $jf_name
            docker rm $jf_name
        else
            main
            return
        fi
    else
        get_config_path
        echo -e "\033[1;35m请输入您的小雅姐夫媒体库路径:\033[0m"
        read -r media_dir
        check_path $media_dir
    fi
    if [ -s $config_dir/docker_address.txt ]; then
        docker_addr=$(head -n1 $config_dir/docker_address.txt)
    else
        echo "请先配置 $config_dir/docker_address.txt，以便获取docker 地址"
        exit
    fi
    mkdir -p $media_dir/xiaoya
    mkdir -p $media_dir/temp
    curl -o /tmp/update_meta_jf.sh https://xy.ggbond.org/xy/update_meta_jf.sh
    meta_select
    chmod 777 /tmp/update_meta_jf.sh
    docker run -i --security-opt seccomp=unconfined --rm --net=host -v /tmp:/tmp -v $media_dir:/media -v $config_dir:/etc/xiaoya -e LANG=C.UTF-8 ailg/ggbond:latest /tmp/update_meta_jf.sh
    #dir=$(find $media_dir -type d -name "*config*" -print -quit)
    mv "$media_dir/jf_config" "$media_dir/confg"
    chmod -R 777 $media_dir/confg
    chmod -R 777 $media_dir/xiaoya
    host=$(echo $docker_addr | cut -f1,2 -d:)
    host_ip=$(grep -oP '\d+\.\d+\.\d+\.\d+' $config_dir/docker_address.txt)
    if ! [[ -f /etc/nsswitch.conf ]]; then
        echo -e "hosts:\tfiles dns\nnetworks:\tfiles" > /etc/nsswitch.conf
    fi
    docker run -d --name jellyfin_xy -v /etc/nsswitch.conf:/etc/nsswitch.conf \
        -v $media_dir/config:/config \
        -v $media_dir/xiaoya:/media \
        -v /$media_dir/config/cache:/cache \
        --user 0:0 \
        -p 6909:8096 \
        -p 6920:8920 \
        -p 1909:1900/udp \
        -p 7369:7359/udp \
        --privileged --add-host="xiaoya.host:127.0.0.1" --restart always nyanmisaka/jellyfin:240220-amd64-legacy
    INFO "${Blue}小雅姐夫安装完成，正在为您重启小雅alist！$NC"
    echo "${host}:6909" > $config_dir/emby_server.txt
    docker restart xiaoya_jf
    start_time=$(date +%s)
    TARGET_LOG_LINE_SUCCESS="success load storage: [/©️"
    while true; do
        line=$(docker logs "xiaoya_jf" 2>&1 | tail -n 10)
        echo $line
        if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
            break
        fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ "$elapsed_time" -gt 300 ]; then
            echo "小雅alist未正常启动超时 5分钟，请检查小雅alist的安装！"
            break
        fi
        sleep 3
    done
    INFO "请登陆${Blue} $host:2345 ${NC}访问小雅姐夫，用户名：${Blue} ailg ${NC}，密码：${Blue} 5678 ${NC}"
}

function user_select3() {
    user_select1
    start_time=$(date +%s)
    TARGET_LOG_LINE_SUCCESS="success load storage: [/©️"
    while true; do
        line=$(docker logs "xiaoya_jf" 2>&1 | tail -n 10)
        echo $line
        if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
            break
        fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ "$elapsed_time" -gt 300 ]; then
            echo "小雅alist未正常启动超时 5分钟，程序将退出，请检查小雅alist的安装，或重启小雅alist后重新运行脚本！"
            exit
        fi
        sleep 3
    done
    user_select2
}

function user_select4() {
    down_img() {
        if [[ ! -f $image_dir/$emby_ailg ]] || [[ -f $image_dir/$emby_ailg.aria2 ]]; then
            docker exec $docker_name ali_clear -1 > /dev/null 2>&1
            docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                aria2c -o /image/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/${down_path}/$emby_ailg"
        fi
        local_size=$(du -b $image_dir/$emby_ailg | cut -f1)
        for i in {1..3}; do
            if [[ -f $image_dir/$emby_ailg.aria2 ]] || [[ $remote_size -gt "$local_size" ]]; then
                docker exec $docker_name ali_clear -1 > /dev/null 2>&1
                docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                    aria2c -o /image/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/${down_path}/$emby_ailg"
                local_size=$(du -b $image_dir/$emby_ailg | cut -f1)
            else
                break
            fi
        done
        [[ -f $image_dir/$emby_ailg.aria2 ]] || [[ $remote_size != "$local_size" ]] && ERROR "文件下载失败，请检查网络后重新运行脚本！" && WARN "未下完的文件存放在${image_dir}目录，以便您续传下载，如不再需要请手动清除！" && exit 1
    }
    while :; do
        clear
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\n"
        echo -e "A、安装小雅EMBY老G速装版会$Red删除原小雅emby/jellyfin容器，如需保留请退出脚本停止原容器进行更名！$NC"
        echo -e "\n"
        echo -e "B、完整版与小雅emby原版一样，Lite版无PikPak数据（适合无梯子用户），请按需选择！"
        echo -e "\n"
        echo -e "C、${Yellow}老G速装版会随emby/jellyfin启动自动挂载镜像，感谢DDSRem大佬提供的解决思路！${NC}"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m1、小雅EMBY老G速装 - 完整版\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m2、小雅EMBY老G速装 - Lite版\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m3、小雅JELLYFIN老G速装 - 完整版\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m4、小雅JELLYFIN老G速装 - Lite版（未推送暂勿安装）\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"

        read -erp "请输入您的选择（1-4，按b返回上级菜单或按q退出）；" f4_select
        case "$f4_select" in
        1)
            emby_ailg="emby-ailg.mp4"
            emby_img="emby-ailg.img"
            space_need=110
            break
            ;;
        2)
            emby_ailg="emby-ailg-lite.mp4"
            emby_img="emby-ailg-lite.img"
            space_need=95
            break
            ;;
        3)
            emby_ailg="jellyfin-ailg.mp4"
            emby_img="jellyfin-ailg.img"
            space_need=130
            break
            ;;
        4)
            emby_ailg="jellyfin-ailg-lite.mp4"
            emby_img="jellyfin-ailg-lite.img"
            space_need=100
            break
            ;;
        [Bb])
            clear
            main
            break
            ;;
        [Qq])
            exit
            ;;
        *)
            ERROR "输入错误，按任意键重新输入！"
            read -rn 1
            continue
            ;;
        esac
    done

    if [[ $st_alist =~ "未安装" ]]; then
        ERROR "请先安装小雅ALIST老G版，再执行本安装！"
        main
        return
    fi
    umask 000
    check_env
    get_config_path
    docker exec $docker_name ali_clear -1 > /dev/null 2>&1
    echo -e "\033[1;35m请输入您的小雅emby/jellyfin镜像存放路径（请确保大于${space_need}G剩余空间！）:\033[0m"
    read -r image_dir
    check_path $image_dir
    check_space $image_dir $space_need

    if [[ "${f4_select}" == [12] ]]; then
        search_img="emby/embyserver|amilys/embyserver"
        del_name="emby"
        loop_order="/dev/loop7"
        down_path="emby"
        get_emby_image
        init="run"
        emd_name="xiaoya-emd"
        entrypoint_mount="entrypoint_emd"
    elif [[ "${f4_select}" == [34] ]]; then
        search_img="nyanmisaka/jellyfin"
        del_name="jellyfin_xy"
        loop_order="/dev/loop6"
        down_path="jellyfin"
        get_jellyfin_image
        init="run_jf"
        emd_name="xiaoya-emd-jf"
        entrypoint_mount="entrypoint_emd_jf"
    fi
    get_emby_status

    for name in "${!emby_list[@]}"; do
        if [[ "${name}" == "${del_name}" ]]; then
            read -erp "$(echo -e "\033[1;36m是否保留名为${del_name}的容器！按Y/y保留，按其他任意键将删除！\033[0m\n请输入：") " del_emby
            [[ "${del_emby}" == [Yy] ]] && del_emby=false || del_emby=true
        fi
    done
    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs docker stop
    if [ ${#emby_list[@]} -ne 0 ]; then
        for op_emby in "${!emby_list[@]}"; do
            docker stop "${op_emby}"
            INFO "${op_emby}容器已关闭！"
            if [[ "${emby_list[$op_emby]}" =~ .*\.img ]]; then
                mount | grep "${emby_list[$op_emby]%/*}/emby-xy" && umount "${emby_list[$op_emby]%/*}/emby-xy" && losetup -d "${loop_order}"
            else
                mount | grep "${emby_list[$op_emby]%/*}" && umount "${emby_list[$op_emby]%/*}"
            fi
            [[ "${op_emby}" == "${del_name}" ]] && $del_emby && docker rm "${op_emby}" && INFO "${op_emby}容器已删除！"
        done
    fi
    $del_emby && emby_name=${del_name} || emby_name="${del_name}-ailg"
    mkdir -p "$image_dir/emby-xy" && media_dir="$image_dir/emby-xy"
    losetup | grep -q "${loop_order#/dev/}" && losetup -d "${loop_order}"

    if [ -s $config_dir/docker_address.txt ]; then
        docker_addr=$(head -n1 $config_dir/docker_address.txt)
    else
        echo "请先配置 $config_dir/docker_address.txt，以便获取docker 地址"
        exit
    fi

    start_time=$(date +%s)
    for i in {1..5}; do
        remote_size=$(curl -sL -D - -o /dev/null --max-time 5 "$docker_addr/d/ailg_jf/${down_path}/$emby_ailg" | grep "Content-Length" | cut -d' ' -f2 | tail -n 1 | tr -d '\r')
        [[ -n $remote_size ]] && break
    done
    if [[ $remote_size -lt 100000 ]]; then
        ERROR "获取文件大小失败，请检查网络后重新运行脚本！"
        echo -e "${Yellow}排障步骤：\n1、检查5678打开alist能否正常播放（排除token失效和风控！）"
        echo -e "${Yellow}2、检查alist配置目录的docker_address.txt是否正确指向你的alist访问地址，\n   应为宿主机+5678端口，示例：http://192.168.2.3:5678"
        echo -e "${Yellow}3、检查阿里云盘空间，确保剩余空间大于${space_need}G${NC}"
        exit 1
    fi
    INFO "远程文件大小获取成功！"
    INFO "即将下载${emby_ailg}文件……"
    if [ ! -f $image_dir/$emby_img ]; then
        down_img
    else
        local_size=$(du -b $image_dir/$emby_img | cut -f1)
        [ "$local_size" -lt "$remote_size" ] && down_img
    fi

    update_ailg ailg/ggbond:latest

    echo "$local_size $remote_size $image_dir/$emby_ailg $media_dir"
    mount | grep $media_dir && umount $media_dir
    if [ "$local_size" -eq "$remote_size" ]; then
        if [ -f "$image_dir/$emby_img" ]; then
            docker run -i --privileged --rm --net=host -v ${image_dir}:/ailg -v $media_dir:/mount_emby ailg/ggbond:latest \
                exp_ailg "/ailg/$emby_img" "/mount_emby" 30
        else
            docker run -i --privileged --rm --net=host -v ${image_dir}:/ailg -v $media_dir:/mount_emby ailg/ggbond:latest \
                exp_ailg "/ailg/$emby_ailg" "/mount_emby" 30
        fi
    else
        INFO "本地已有镜像，无需重新下载！"
    fi

    #清除原来可能存在的任务计划
    sed -i '/mount_ailg/d' /etc/rc.local > /dev/null
    sed -i '/mount_ailg/d' /boot/config/go > /dev/null
    crontab -l | grep -v mount_ailg > /tmp/cronjob.tmp
    crontab /tmp/cronjob.tmp

    if [ ! -f /usr/bin/mount_ailg ]; then
        docker cp "${docker_name}":/var/lib/mount_ailg "/usr/bin/mount_ailg"
        chmod 777 /usr/bin/mount_ailg
    fi

    INFO "开始安装小雅emby/jellyfin……"
    host=$(echo $docker_addr | cut -f1,2 -d:)
    host_ip=$(echo $docker_addr | cut -d':' -f2 | tr -d '/')
    if ! [[ -f /etc/nsswitch.conf ]]; then
        echo -e "hosts:\tfiles dns\nnetworks:\tfiles" > /etc/nsswitch.conf
    fi
    #get_emby_image
    if [ ! -f "$image_dir/${init}" ]; then
        docker cp "${docker_name}":/var/lib/${init} "$image_dir/"
        chmod 777 "$image_dir/${init}"
    fi
    if ${del_emby}; then
        if [[ "${emby_image}" =~ emby ]]; then
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run":/etc/cont-init.d/run \
                --user 0:0 \
                --net=host \
                --privileged --add-host="xiaoya.host:127.0.0.1" --restart always $emby_image
        else
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run_jf":/etc/run_jf \
                --entrypoint "/etc/run_jf" \
                --user 0:0 \
                -p 6909:8096 \
                -p 6920:8920 \
                -p 1909:1900/udp \
                -p 6359:7359/udp \
                --privileged --add-host="xiaoya.host:${host_ip}" --restart always $emby_image
        fi
    else
        if [[ "${emby_image}" =~ emby ]]; then
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run":/etc/cont-init.d/run \
                --user 0:0 \
                -p 5908:6908 \
                -p 5920:8920 \
                -p 5900:1900/udp \
                -p 5359:7359/udp \
                --privileged --add-host="xiaoya.host:127.0.0.1" --restart always $emby_image
                echo -e "http://${host_ip}:5908" > $config_dir/emby_server.txt
        else
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run_jf":/etc/run_jf \
                --entrypoint "/etc/run_jf" \
                --user 0:0 \
                -p 5909:8096 \
                -p 5920:8920 \
                -p 1919:1900/udp \
                -p 5359:7359/udp \
                --privileged --add-host="xiaoya.host:${host_ip}" --restart always $emby_image
                echo -e "http://${host_ip}:5909" > $config_dir/jellyfin_server.txt
        fi
    fi
    [[ ! "${emby_image}" =~ emby ]] && echo "2553384366474427ad8be5ca878ff7a9" > $config_dir/infuse_api_key_jf.txt

    current_time=$(date +%s)
    elapsed_time=$(awk -v start=$start_time -v end=$current_time 'BEGIN {printf "%.2f\n", (end-start)/60}')
    INFO "${Blue}恭喜您！小雅emby/jellyfin安装完成，安装时间为 ${elapsed_time} 分钟！$NC"
    INFO "请登陆${Blue} $host:2345/2346 ${NC}访问小雅emby/jellyfin，用户名：${Blue} xiaoya/ailg ${NC}，密码：${Blue} 1234/5678 ${NC}"
    INFO "注：如果$host:6908/6909/5908/5909可访问，$host:2345/2346访问失败（502/500等错误），按如下步骤排障：\n\t1、检查$config_dir/emby/jellyfin_server.txt文件中的地址是否正确指向emby的访问地址，即：$host:6908/6909/5908/5909或http://127.0.0.1:6908/6909/5908/5909\n\t2、地址正确重启你的小雅alist容器即可。"
    echo -e "\n"
    echo -e "\033[1;33m是否继续安装小雅元数据爬虫同步？${NC}"
    answer=""
    t=30
    while [[ -z "$answer" && $t -gt 0 ]]; do
        printf "\r按Y/y键安装，按N/n退出（%2d 秒后将默认安装）：" $t
        read -r -t 1 -n 1 answer
        t=$((t - 1))
    done

    if [[ ! $answer =~ ^[Nn]$ || -z "$answer" ]]; then
        INFO "正在为您安装小雅元数据爬虫同步……"

        for i in {1..3}; do
            if docker_pull ddsderek/xiaoya-emd:latest; then
                INFO "ddsderek/xiaoya-emd:latest镜像拉取成功！"
                break
            fi
        done
        docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ddsderek/xiaoya-emd:latest || (ERROR "ddsderek/xiaoya-emd:latest镜像拉取失败，请检查网络后手动安装！" && exit 1)

        if ! docker cp "${docker_name}":/var/lib/"${entrypoint_mount}" "$image_dir/entrypoint.sh"; then
            if ! curl -o "$image_dir/entrypoint.sh" https://xy.ggbond.org/xy/${entrypoint_mount}; then
                ERROR "获取文件失败，请将老G的alist更新到最新版或检查网络后重试。更新方法：重新运行一键脚本，选1重装alist，使用原来的目录！" && exit 1
            fi
        fi
        chmod 777 "$image_dir/entrypoint.sh"
        if docker ps -a | grep -qE " ${emd_name}\b" && docker stop "${emd_name}" && docker rm "${emd_name}"; then
            INFO "${Yellow}已删除您原来的${emd_name}容器！${NC}"
        fi
        docker_pull ddsderek/xiaoya-emd:latest
        if docker run -d \
            --name="${emd_name}" \
            --privileged \
            --restart=always \
            --net=host \
            -e IMG_VOLUME=true \
            -v "$image_dir/entrypoint.sh":/entrypoint.sh \
            ddsderek/xiaoya-emd:latest; then
            INFO "小雅元数据同步爬虫安装成功！"
        else
            INFO "小雅元数据同步爬虫安装失败，请手动安装！"
        fi
    fi
}

ailg_uninstall() {
    INFO "是否${Red}删除老G速装版镜像文件${NC} [Y/n]（保留请按N/n键，按其他任意键默认删除）"
    read -erp "请输入：" clear_img
    [[ ! "${clear_img}" =~ ^[Nn]$ ]] && clear_img="y"

    declare -ga img_order
    get_emby_status > /dev/null
    if [ ${#emby_list[@]} -ne 0 ]; then
        for op_emby in "${!emby_list[@]}"; do
            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done
        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要卸载的老G速装版emby：\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name ${emby_list[$name]}
            done
            while :; do
                read -erp "输入序号：" img_select
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    img_path=${emby_list[${img_order[$((img_select - 1))]}]}
                    emby_name=${img_order[$((img_select - 1))]}
                    for op_emby in "${img_order[@]}"; do
                        docker stop "${op_emby}"
                        INFO "${op_emby}容器已关闭！"
                    done
                    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs docker stop
                    INFO "小雅爬虫容器已关闭！"
                    umount "${loop_order}" > /dev/null 2>&1
                    losetup -d "${loop_order}" > /dev/null 2>&1
                    mount | grep -qF "${img_mount}" && umount "${img_mount}"
                    docker rm ${emby_name}
                    if [[ "${clear_img}" =~ ^[Yy]$ ]]; then
                        rm -f "${img_path}" && rm -f "${img_path%/*}"/run && INFO "已卸载${Yellow}${emby_name}${NC}容器，并删除${Yellow}${img_path}${NC}镜像！"
                    else
                        INFO "已卸载${Yellow}${emby_name}${NC}容器，未删除${Yellow}${img_path}${NC}镜像！"
                    fi
                    break
                else
                    ERROR "您输入的序号无效，请输入一个在 1 到 ${#img_order[@]} 的数字。"
                fi
            done
        else
            INFO "您未安装任何老G速装版emby，程序退出！" && exit 1
        fi
    else
        INFO "您未安装任何老G速装版emby，程序退出！" && exit 1
    fi
}

happy_emby() {
    declare -ga img_order
    get_emby_happy_image
    get_emby_status > /dev/null
    if [ ${#emby_list[@]} -ne 0 ]; then
        for op_emby in "${!emby_list[@]}"; do
            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done
        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要换装/重装开心版的emby！\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name ${emby_list[$name]}
            done
            while :; do
                read -erp "输入序号：" img_select
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    happy_name=${img_order[$((img_select - 1))]}
                    happy_path=${emby_list[${happy_name}]}
                    docker stop "${happy_name}" && docker rm "${happy_name}"
                    INFO "旧的${happy_name}容器已删除！"
                    INFO "开始安装小雅emby……"
                    xiaoya_host="127.0.0.1"
                    if ! [[ -f /etc/nsswitch.conf ]]; then
                        echo -e "hosts:\tfiles dns\nnetworks:\tfiles" > /etc/nsswitch.conf
                    fi
                    docker run -d --name "${happy_name}" -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                        -v "${happy_path}":/media.img \
                        -v "${happy_path%/*.img}/run":/etc/cont-init.d/run \
                        --device /dev/dri:/dev/dri \
                        --user 0:0 \
                        --net=host \
                        --privileged --add-host="xiaoya.host:$xiaoya_host" --restart always ${emby_image}
                    break
                else
                    ERROR "您输入的序号无效，请输入一个在 1 到 ${#img_order[@]} 之间的数字。"
                fi
            done
        fi
    else
        ERROR "您当前未安装小雅emby，程序退出！" && exit 1
    fi
}

get_img_path() {
    read -erp "请输入您要挂载的镜像的完整路径：" img_path
    img_name=$(basename "${img_path}")
    case "${img_name}" in
    "emby-ailg.img" | "emby-ailg-lite.img" | "jellyfin-ailg.img" | "jellyfin-ailg-lite.img") ;;

    *)
        ERROR "您输入的不是老G的镜像，或已改名，确保文件名正确后重新运行脚本！"
        exit 1
        ;;
    esac
    img_mount=${img_path%*.img}/emby-xy
    check_path ${img_mount}
}

mount_img() {
    declare -ga img_order
    get_emby_status > /dev/null
    update_ailg ailg/ggbond:latest
    if [ ! -f /usr/bin/mount_ailg ]; then
        docker cp xiaoya_jf:/var/lib/mount_ailg "/usr/bin/mount_ailg"
        chmod 777 /usr/bin/mount_ailg
    fi
    if [ ${#emby_list[@]} -ne 0 ]; then
        for op_emby in "${!emby_list[@]}"; do
            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done
        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要挂载的镜像：\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name ${emby_list[$name]}
            done
            printf "[ 0 ] \033[1;33m手动输入需要挂载的老G速装版镜像的完整路径\n\033[0m"
            while :; do
                read -erp "输入序号：" img_select
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    img_path=${emby_list[${img_order[$((img_select - 1))]}]}
                    img_mount=${img_path%/*.img}/emby-xy
                    emby_name=${img_order[$((img_select - 1))]}
                    for op_emby in "${img_order[@]}"; do
                        docker stop "${op_emby}"
                        INFO "${op_emby}容器已关闭！"
                    done
                    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs docker stop
                    INFO "小雅爬虫容器已关闭！"
                    umount "${loop_order}" > /dev/null 2>&1
                    losetup -d "${loop_order}" > /dev/null 2>&1
                    mount | grep -qF "${img_mount}" && umount "${img_mount}"
                    sleep 3
                    docker start ${emby_name}
                    if mount "${loop_order}" ${img_mount}; then
                        INFO "已将${Yellow}${img_path}${NC}挂载到${Yellow}${img_mount}${NC}目录！" && WARN "如您想操作小雅config数据的同步或更新，请先手动关闭${Yellow}${emby_name}${NC}容器！"
                    else
                        ERROR "挂载失败，${Yellow}${img_mount}${NC}挂载目录非空或已经挂载，请重启设备后重试！" && exit 1
                    fi
                    break
                elif [ "${img_select}" -eq 0 ]; then
                    get_img_path
                    if mount_ailg "${img_path}" "${img_mount}"; then
                        INFO "已将${img_path}挂载到${img_mount}目录！"
                    else
                        ERROR "挂载失败，请重启设备后重试！"
                        exit 1
                    fi
                    break
                else
                    ERROR "您输入的序号无效，请输入一个在 0 到 ${#img_order[@]} 的数字。"
                fi
            done
        else
            get_img_path
            if mount_ailg "${img_path}" "${img_mount}"; then
                INFO "已将${img_path}挂载到${img_mount}目录！"
            else
                ERROR "挂载失败，请重启设备后重试！"
                exit 1
            fi
        fi
    else
        get_img_path
        if mount_ailg "${img_path}" "${img_mount}"; then
            INFO "已将${img_path}挂载到${img_mount}目录！"
        else
            ERROR "挂载失败，请重启设备后重试！"
            exit 1
        fi
    fi
}

sync_config() {
    if [[ $st_alist =~ "未安装" ]]; then
        ERROR "请先安装小雅ALIST老G版，再执行本安装！"
        main
        return
    fi
    umask 000
    check_env
    get_config_path
    mount_img || exit 1
    #docker stop ${emby_name}
    if [ "${img_select}" -eq 0 ]; then
        get_emby_image
    else
        emby_name=${img_order[$((img_select - 1))]}
        emby_image=$(docker inspect -f '{{.Config.Image}}' "${emby_name}")
    fi
    if command -v ifconfig > /dev/null 2>&1; then
        docker0=$(ifconfig docker0 | awk '/inet / {print $2}' | sed 's/addr://')
    else
        docker0=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d '/' -f 1)
    fi
    if [ -n "$docker0" ]; then
        INFO "docker0 的 IP 地址是：$docker0"
    else
        WARN "无法获取 docker0 的 IP 地址！"
        docker0=$(ip address | grep inet | grep -v 172.17 | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | sed 's/addr://' | head -n1 | cut -f1 -d"/")
        INFO "尝试使用本地IP：${docker0}"
    fi
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、小雅config干净重装/更新（config数据已损坏请选此项！）\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、小雅config保留重装/更新（config数据未损坏想保留用户数据及自己媒体库可选此项！）\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"

    read -erp "请输入您的选择（1-2）；" sync_select
    if [[ "$sync_select" == "1" ]]; then
        echo -e "测试xiaoya的联通性..."
        if curl -siL http://127.0.0.1:5678/d/README.md | grep -v 302 | grep -q "x-oss-"; then
            xiaoya_addr="http://127.0.0.1:5678"
        elif curl -siL http://${docker0}:5678/d/README.md | grep -v 302 | grep -q "x-oss-"; then
            xiaoya_addr="http://${docker0}:5678"
        else
            if [ -s $config_dir/docker_address.txt ]; then
                docker_address=$(head -n1 $config_dir/docker_address.txt)
                if curl -siL http://${docker_address}:5678/d/README.md | grep -v 302 | grep "x-oss-"; then
                    xiaoya_addr=${docker_address}
                else
                    ERROR "请检查xiaoya是否正常运行后再试"
                    exit 1
                fi
            else
                ERROR "请先配置 $config_dir/docker_address.txt 后重试"
                exit 1
            fi
        fi
        for i in {1..5}; do
            remote_cfg_size=$(curl -sL -D - -o /dev/null --max-time 5 "$xiaoya_addr/d/元数据/config.mp4" | grep "Content-Length" | cut -d' ' -f2)
            [[ -n $remote_cfg_size ]] && break
        done
        local_cfg_size=$(du -b "${img_mount}/temp/config.mp4" | cut -f1)
        echo -e "\033[1;33mremote_cfg_size=${remote_cfg_size}\nlocal_cfg_size=${local_cfg_size}\033[0m"
        for i in {1..5}; do
            if [[ -z "${local_cfg_size}" ]] || [[ ! $remote_size == "$local_size" ]] || [[ -f ${img_mount}/temp/config.mp4.aria2 ]]; then
                echo -e "\033[1;33m正在下载config.mp4……\033[0m"
                rm -f ${img_mount}/temp/config.mp4
                docker run -i \
                    --security-opt seccomp=unconfined \
                    --rm \
                    --net=host \
                    -v ${img_mount}:/media \
                    -v $config_dir:/etc/xiaoya \
                    --workdir=/media/temp \
                    -e LANG=C.UTF-8 \
                    ailg/ggbond:latest \
                    aria2c -o config.mp4 --continue=true -x6 --conditional-get=true --allow-overwrite=true "${xiaoya_addr}/d/元数据/config.mp4"
                local_cfg_size=$(du -b "${img_mount}/temp/config.mp4" | cut -f1)
                run_7z=true
            else
                echo -e "\033[1;33m本地config.mp4与远程文件一样，无需重新下载！\033[0m"
                run_7z=false
                break
            fi
        done
        if [[ -z "${local_cfg_size}" ]] || [[ ! $remote_size == "$local_size" ]] || [[ -f ${img_mount}/temp/config.mp4.aria2 ]]; then
            ERROR "config.mp4下载失败，请检查网络，如果token失效或触发阿里风控将小雅alist停止1小时后再打开重试！"
            exit 1
        fi

        #rm -rf ${img_mount}/config/cache/* ${img_mount}/config/metadata/* ${img_mount}/config/data/library.db*
        #7z x -aoa -bb1 -mmt=16 /media/temp/config.mp4 -o/media/config/data/ config/data/library.db*
        #7z x -aoa -bb1 -mmt=16 /media/temp/config.mp4 -o/media/config/cache/ config/cache/*
        #7z x -aoa -bb1 -mmt=16 /media/temp/config.mp4 -o/media/config/metadata/ config/metadata/*
        if ! "${run_7z}"; then
            echo -e "\033[1;33m远程小雅config未更新，与本地数据一样，是否重新解压本地config.mp4？${NC}"
            answer=""
            t=30
            while [[ -z "$answer" && $t -gt 0 ]]; do
                printf "\r按Y/y键解压，按N/n退出（%2d 秒后将默认不解压退出）：" $t
                read -r -t 1 -n 1 answer
                t=$((t - 1))
            done
            [[ "${answer}" == [Yy] ]] && run_7z=true
        fi
        if "${run_7z}"; then
            rm -rf ${img_mount}/config
            docker run -i \
                --security-opt seccomp=unconfined \
                --rm \
                --net=host \
                -v ${img_mount}:/media \
                -v $config_dir:/etc/xiaoya \
                --workdir=/media \
                -e LANG=C.UTF-8 \
                ailg/ggbond:latest \
                7z x -aoa -bb1 -mmt=16 /media/temp/config.mp4
            echo -e "下载解压元数据完成"
            INFO "小雅config安装完成！"
            docker start "${emby_name}"
        else
            INFO "远程config与本地一样，未执行解压/更新！"
            exit 0
        fi

    elif [[ "$sync_select" == "2" ]]; then
        ! docker ps | grep -q "${emby_name}" && ERROR "${emby_name}未正常启动，如果数据库已损坏请重新运行脚本，选择干净安装！" && exit 1
        xiaoya_host="127.0.0.1"
        # docker run -d --name emby-sync -v /etc/nsswitch.conf:/etc/nsswitch.conf \
        # -v ${img_mount}/xiaoya:/media \
        # -v ${img_mount}/config:/config \
        # --user 0:0 \
        # --net=host \
        # --privileged --add-host="xiaoya.host:$xiaoya_host" --restart always $emby_image
        echo -e "\n"
        echo -e "\033[1;31m同步进行中，需要较长时间，请耐心等待，直到出命令行提示符才算结束！\033[0m"
        [ -f "/tmp/sync_emby_config_ailg.sh" ] && rm -f /tmp/sync_emby_config_ailg.sh
        for i in {1..3}; do
            curl -sSfL -o /tmp/sync_emby_config_ailg.sh https://xy.ggbond.org/xy/sync_emby_config_img_ailg.sh
            grep -q "返回错误" /tmp/sync_emby_config_ailg.sh && break
        done
        grep -q "返回错误" /tmp/sync_emby_config_ailg.sh || {
            echo -e "文件获取失败，检查网络或重新运行脚本！"
            rm -f /tmp/sync_emby_config_ailg.sh
            exit 1
        }
        chmod 777 /tmp/sync_emby_config_ailg.sh
        bash -c "$(cat /tmp/sync_emby_config_ailg.sh)" -s ${img_mount} $config_dir "${emby_name}" | tee /tmp/cron.log
        echo -e "\n"
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        INFO "安装完成"
        WARN "已在原目录（config/data）为您创建library.db的备份文件library.org.db"
        echo -e "\n"
        WARN "只有emby启动报错，或启动后媒体库丢失才需执行以下操作："
        echo -e "\033[1;35m1、先停止容器，检查emby媒体库目录的config/data目录中是否有library.org.db备份文件！"
        echo -e "2、如果没有，说明备份文件已自动恢复，原数据启动不了需要排查其他问题，或重装config目录！"
        echo -e "3、如果有，继续执行3-5步，先删除library.db/library.db-shm/library.db-wal三个文件！"
        echo -e "4、将library.org.db改名为library.db，library.db-wal.bak改名为library.db-wal（没有此文件则略过）！"
        echo -e "5、将library.db-shm.bak改名为library.db-shm（没有此文件则略过），重启emby容器即可恢复原数据！\033[0m"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
    else
        ERROR "您的输入有误，程序退出" && exit 1
    fi
}

user_selecto() {
    while :; do
        clear
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m1、卸载小雅emby老G速装版\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m2、更换开心版小雅EMBY\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m3、挂载老G速装版镜像\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m4、老G速装版镜像重装/同步config\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        read -erp "请输入您的选择（1-2，按b返回上级菜单或按q退出）；" fo_select
        case "$fo_select" in
        1)
            ailg_uninstall emby
            break
            ;;
        2)
            happy_emby
            break
            ;;
        3)
            mount_img
            break
            ;;
        4)
            sync_config
            break
            ;;
        [Bb])
            clear
            main
            break
            ;;
        [Qq])
            exit
            ;;
        *)
            ERROR "输入错误，按任意键重新输入！"
            read -r -n 1
            continue
            ;;
        esac
    done
}

function main() {
    clear
    st_alist=$(setup_status "$(docker ps -a | grep ailg/alist | awk '{print $NF}' | head -n1)")
    st_jf=$(setup_status "$(docker ps -a | grep nyanmisaka/jellyfin:240220 | awk '{print $NF}')")
    st_emby=$(setup_status "$(docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' emby |
        grep -qE "/xiaoya$ /media\b|\.img /media\.img" && echo 'emby')")
    echo -e "\e[33m"
    echo -e "————————————————————————————————————使  用  说  明————————————————————————————————"
    echo -e "1、本脚本为小雅Jellyfin全家桶的安装脚本，使用于群晖系统环境，不保证其他系统通用；"
    echo -e "2、本脚本为个人自用，不维护，不更新，不保证适用每个人的环境，请勿用于商业用途；"
    echo -e "3、作者不对使用本脚本造成的任何后果负责，有任何顾虑，请勿运行，按CTRL+C立即退出；"
    echo -e "4、如果您喜欢这个脚本，可以请我喝咖啡：https://xy.ggbond.org/xy/3q.jpg\033[0m"
    echo -e "————————————————————————————————————\033[1;33m安  装  状  态\033[0m————————————————————————————————"
    echo -e "\e[0m"
    echo -e "小雅ALIST老G版：${st_alist}         小雅姐夫（jellyfin）：${st_jf}		小雅emby：${st_emby}"
    echo -e "\e[0m"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\n"
    echo -e "\033[1;32m1、安装/重装小雅ALIST老G版\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m2、安装/重装小雅姐夫（jellyfin）-需更新暂别使用\033[0m"
    echo -e "\n"
    echo -e "\033[1;32m3、无脑一键全装/重装小雅姐夫-需更新暂别使用\033[0m"
    echo -e "\n"
    echo -e "\033[1;35m4、安装/重装小雅emby（老G速装版）\033[0m"
    echo -e "\n"
    echo -e "\033[1;35mo、有问题？选我看看\033[0m"
    echo -e "\n"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -erp "请输入您的选择（1-4或q退出）；" user_select
    case $user_select in
    1)
        clear
        user_select1
        ;;
    2)
        clear
        user_select2
        ;;
    3)
        clear
        user_select3
        ;;
    4)
        clear
        user_select4
        ;;
    [Oo])
        clear
        user_selecto
        ;;
    [Qq])
        exit 0
        ;;
    *)
        ERROR "输入错误，按任意键重新输入！"
        read -r -n 1
        main
        ;;
    esac
}

setup_status() {
    if docker container inspect "${1}" > /dev/null 2>&1; then
        echo -e "${Green}已安装${NC}"
    else
        echo -e "${Red}未安装${NC}"
    fi
}

#检查用户路径输入
check_path() {
    dir_path=$1
    if [[ ! -d "$dir_path" ]]; then
        read -erp "您输入的目录不存在，按Y/y创建，或按其他键退出！" yn
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

#安装环境检查
check_env() {
    if ! which curl; then
        packages_need
        if ! which curl; then
            ERROR "curl 未安装，请手动安装！"
            exit 1
        fi
        if ! which wget; then
            ERROR "wget 未安装，请手动安装！"
            exit 1
        fi
        if ! which docker; then
            ERROR "docker 未安装，请手动安装！"
            exit 1
        fi
    fi
}

#删除原来的小雅容器
rm_alist() {
    for container in $(docker ps -aq); do
        image=$(docker inspect --format '{{.Config.Image}}' "$container")
        if [[ "$image" == "xiaoyaliu/alist:latest" ]] || [[ "$image" == "xiaoyaliu/alist:hostmode" ]]; then
            WARN "本安装会删除原有的小雅alist容器，按任意键继续，或按CTRL+C退出！"
            read -r -n 1
            echo "Deleting container $container using image $image ..."
            config_dir=$(docker inspect --format '{{ (index .Mounts 0).Source }}' "$container")
            docker stop "$container"
            docker rm "$container"
            echo "Container $container has been deleted."
        fi
    done
}

main
