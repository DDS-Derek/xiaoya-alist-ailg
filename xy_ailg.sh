#!/bin/bash
# shellcheck shell=bash
# shellcheck disable=SC2086

source /tmp/xy_utils.sh
source /tmp/xy_sync.sh

PATH=${PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/opt/homebrew/bin
export PATH

function get_emby_image() {
    # 设置默认版本号
    local version=${1:-"4.8.10.0"}
    
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        emby_image="emby/embyserver:${version}"
        strmhelper_mode="update"
        ;;
    "aarch64" | *"arm64"* | *"armv8"* | *"arm/v8"*)
        emby_image="emby/embyserver_arm64v8:${version}"
        strmhelper_mode="uninstall"
        ;;
    "armv7l")
        emby_image="emby/embyserver_arm32v7:${version}"
        strmhelper_mode="uninstall"
        ;;
    *)
        ERROR "不支持你的CPU架构：$cpu_arch"
        exit 1
        ;;
    esac

    # 检查镜像是否存在
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image}; then
        for i in {1..3}; do
            if docker_pull $emby_image; then
                INFO "${emby_image}镜像拉取成功！"
                break
            fi
        done
    fi

    # 验证镜像是否成功拉取
    docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image} || { ERROR "${emby_image}镜像拉取失败，请手动安装emby，无需重新运行本脚本，小雅媒体库在${media_dir}！" && exit 1; }
}

function get_jellyfin_image() {
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        linux_version=$(uname -r | cut -d"." -f1)
        if [ "${linux_version}" -lt 5 ];then
            [[ "${f4_select}" == [78] ]] && emby_image="jellyfin/jellyfin:10.9.6" || emby_image="nyanmisaka/jellyfin:250127-amd64"
        else
            [[ "${f4_select}" == [78] ]] && emby_image="jellyfin/jellyfin:10.9.6" || emby_image="nyanmisaka/jellyfin:latest"
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
    local version=$1
    cpu_arch=$(uname -m)
    case $cpu_arch in
    "x86_64" | *"amd64"*)
        emby_image="amilys/embyserver:${version}"
        ;;
    "aarch64" | *"arm64"* | *"armv8"* | *"arm/v8"*)
        emby_image="amilys/embyserver_arm64v8:${version}"
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
    docker images --format '{{.Repository}}:{{.Tag}}' | grep -q ${emby_image} || (ERROR "${emby_image}镜像拉取失败，请手动安装emby，无需重新运行本脚本！" && exit 1)
}

function get_config_path() {
    images=("ailg/alist" "xiaoyaliu/alist" "ailg/g-box")
    results=()
    for image in "${images[@]}"; do
        while IFS= read -r line; do
            container_name=$(echo $line | awk '{print $NF}')
            if command -v jq > /dev/null 2>&1; then
                config_dir=$(docker inspect $container_name | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
            else
                config_dir=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container_name")
            fi
            results+=("$container_name $config_dir")
        done < <(docker ps -a | grep "$image")
    done
    if [ ${#results[@]} -eq 0 ]; then
        read -erp "请输入alist/g-box的配置目录路径：(直接回车将使用/etc/xiaoya目录) " config_dir
        config_dir=${config_dir:-"/etc/xiaoya"}
        check_path $config_dir
    elif [ ${#results[@]} -eq 1 ]; then
        docker_name=$(echo "${results[0]}" | awk '{print $1}')
        config_dir=$(echo "${results[0]}" | awk '{print $2}')
    else
        for i in "${!results[@]}"; do
            printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 配置路径: \033[1;33m%s\033[0m\n" $((i+1)) $(echo "${results[$i]}" | awk '{print $1}') $(echo "${results[$i]}" | awk '{print $2}')
        done
        t=15
        while [[ -z "$choice" && $t -gt 0 ]]; do
            printf "\r找到多个alist相关容器，请选择配置目录所在的正确容器（默认选择第一个正在运行的容器）：（%2d 秒后将默认确认）：" $t
            read -r -t 1 -n 1 choice
            [ $? -eq 0 ] && break
            t=$((t - 1))
        done
        choice=${choice:-1}
        docker_name=$(echo "${results[$((choice-1))]}" | awk '{print $1}')
        config_dir=$(echo "${results[$((choice-1))]}" | awk '{print $2}')
    fi
    echo -e "\033[1;37m你选择的alist容器是：\033[1;35m$docker_name\033[0m"
    echo -e "\033[1;37m你选择的配置目录是：\033[1;35m$config_dir\033[0m"
}

function get_jf_media_path() {
    jf_name=${1}
    if command -v jq; then
        media_dir=$(docker inspect $jf_name | jq -r '.[].Mounts[] | select(.Destination=="/media_jf") | .Source')
    else
        media_dir=$(docker inspect $jf_name | awk '/"Destination": "\/media_jf"/{print a} {a=$0}' | awk -F\" '{print $4}')
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
    emby_list=()
    emby_order=()

    if command -v mktemp > /dev/null; then
        temp_file=$(mktemp)
    else
        temp_file="/tmp/tmp_img"
    fi
    docker ps -a | grep -E "${search_img}" | awk '{print $1}' > "$temp_file"

    while read -r container_id; do
        if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' $container_id | grep -qE "/xiaoya$ /media|\.img /media\.img"; then
            container_name=$(docker ps -a --format '{{.Names}}' --filter "id=$container_id")
            host_path=$(docker inspect --format '{{ range .Mounts }}{{ println .Source }}{{ end }}' $container_id | grep -E "/xiaoya$|\.img\b")
            emby_list+=("$container_name:$host_path")
            emby_order+=("$container_name")
        fi
    done < "$temp_file"

    rm "$temp_file"

    if [ ${#emby_list[@]} -ne 0 ]; then
        echo -e "\033[1;37m默认会关闭以下您已安装的小雅emby/jellyfin容器，并删除名为emby/jellyfin_xy的容器！\033[0m"
        for index in "${!emby_order[@]}"; do
            name=${emby_order[$index]}
            for entry in "${emby_list[@]}"; do
                if [[ $entry == $name:* ]]; then
                    host_path=${entry#*:}
                    printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name $host_path
                fi
            done
        done
    fi
}

function user_jellyfin() {
    if [[ $st_gbox =~ "未安装" ]]; then
        ERROR "请先安装G-Box，再执行本安装！"
        main_menu
        return
    fi
    if [[ $st_jf =~ "已安装" ]]; then
        WARN "您的小雅姐夫已安装，是否需要重装？"
        read -erp "请选择：（确认重装按Y/y，否则按任意键返回！）" re_setup
        if [[ $re_setup == [Yy] ]]; then
            [ -z "${config_dir}" ] && get_config_path
            get_jf_media_path "jellyfin_xy"
            docker stop $jf_name
            docker rm $jf_name
        else
            main_menu
            return
        fi
    else
        [ -z "${config_dir}" ] && get_config_path
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
    curl -o /tmp/update_meta_jf.sh https://ailg.ggbond.org/update_meta_jf.sh
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
        -v $media_dir/config_jf:/config \
        -v $media_dir/xiaoya:/media_jf \
        --user 0:0 \
        -e JELLYFIN_CACHE_DIR=/config/cache \
        -e HEALTHCHECK_URL=http://localhost:6909/health \
        -p 6909:8096 \
        -p 6920:8920 \
        -p 1909:1900/udp \
        -p 7369:7359/udp \
        --privileged --add-host="xiaoya.host:${host_ip}" --restart always nyanmisaka/jellyfin:240220-amd64-legacy
    INFO "${Blue}小雅姐夫安装完成，正在为您重启G-Box！$NC"
    echo "${host}:6909" > $config_dir/jellyfin_server.txt
    docker restart g-box
    start_time=$(date +%s)
    TARGET_LOG_LINE_SUCCESS="success load storage: [/©️"
    while true; do
        line=$(docker logs "g-box" 2>&1 | tail -n 10)
        echo $line
        if [[ "$line" == *"$TARGET_LOG_LINE_SUCCESS"* ]]; then
            break
        fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ "$elapsed_time" -gt 300 ]; then
            echo "G-Box未正常启动超时 5分钟，请检查G-Box的安装！"
            break
        fi
        sleep 3
    done
    INFO "请登陆${Blue} $host:2346 ${NC}访问小雅姐夫，用户名：${Blue} ailg ${NC}，密码：${Blue} 5678 ${NC}"
}

function user_emby_fast() {
    down_img() {
        if update_ailg ailg/ggbond:latest; then
            INFO "ailg/ggbond:latest 镜像更新成功！"
        else
            ERROR "ailg/ggbond:latest 镜像更新失败，请检查网络后重新运行脚本！"
            exit 1
        fi
        if [[ ! -f $image_dir/$emby_ailg ]] || [[ -f $image_dir/$emby_ailg.aria2 ]]; then
            docker exec $docker_name ali_clear -1 > /dev/null 2>&1

            if [[ $ok_115 =~ ^[Yy]$ ]]; then
                docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                    aria2c -o /image/test.mp4 --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/115/gbox_intro.mp4" > /dev/null 2>&1
                test_file_size=$(du -b $image_dir/test.mp4 2>/dev/null | cut -f1)
                if [[ ! -f $image_dir/test.mp4.aria2 ]] && [[ $test_file_size -eq 17675105 ]]; then
                    rm -f $image_dir/test.mp4
                    use_115_path=true
                else
                    use_115_path=false
                fi
            else
                use_115_path=false
            fi

            if $use_115_path; then
                docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                    aria2c -o /image/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/115/${down_path}/$emby_ailg"
            else
                docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                    aria2c -o /image/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/${down_path}/$emby_ailg"
            fi
        fi

        local_size=$(du -b $image_dir/$emby_ailg | cut -f1)

        for i in {1..3}; do
            if [[ -f $image_dir/$emby_ailg.aria2 ]] || [[ $remote_size -gt "$local_size" ]]; then
                docker exec $docker_name ali_clear -1 > /dev/null 2>&1
                if $use_115_path; then
                    docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                        aria2c -o /image/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/115/${down_path}/$emby_ailg"
                else
                    docker run --rm --net=host -v $image_dir:/image ailg/ggbond:latest \
                        aria2c -o /image/$emby_ailg --auto-file-renaming=false --allow-overwrite=true -c -x6 "$docker_addr/d/ailg_jf/${down_path}/$emby_ailg"
                fi
                local_size=$(du -b $image_dir/$emby_ailg | cut -f1)
            else
                break
            fi
        done

        if [[ -f $image_dir/$emby_ailg.aria2 ]] || [[ $remote_size != "$local_size" ]]; then
            ERROR "文件下载失败，请检查网络后重新运行脚本！"
            WARN "未下完的文件存放在${image_dir}目录，以便您续传下载，如不再需要请手动清除！"
            exit 1
        fi
    }

    check_qnap
    check_loop_support
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
        echo -e "D、${Red}💡💡💡非固态硬盘且低于8G内存💡💡💡不建议安装jellyfin或4.9版本的Emby!!!${NC}"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m1、小雅EMBY老G速装 - 115完整版 - 4.8.10.0\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m2、小雅EMBY老G速装 - 115-Lite版 - 4.8.10.0\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m3、小雅EMBY老G速装 - 115完整版 - 4.9.0.38\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m4、小雅EMBY老G速装 - 115-Lite版 - 4.9.0.38\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m5、小雅JELLYFIN老G速装 - 10.8.13 - 完整版\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m6、小雅JELLYFIN老G速装 - 10.8.13 - Lite版\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m7、小雅JELLYFIN老G速装 - 10.9.6 - 完整版\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m8、小雅JELLYFIN老G速装 - 10.9.6 - Lite版\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"

        read -erp "请输入您的选择（1-8，按b返回上级菜单或按q退出）：" f4_select
        case "$f4_select" in
        1)
            emby_ailg="emby-ailg-115.mp4"
            emby_img="emby-ailg-115.img"
            space_need=120
            break
            ;;
        2)
            emby_ailg="emby-ailg-lite-115.mp4"
            emby_img="emby-ailg-lite-115.img"
            space_need=110
            break
            ;;
        3)
            emby_ailg="emby-ailg-115-4.9.mp4"
            emby_img="emby-ailg-115-4.9.img"
            space_need=125
            break
            ;;
        4)
            emby_ailg="emby-ailg-lite-115-4.9.mp4"
            emby_img="emby-ailg-lite-115-4.9.img"
            space_need=115
            break
            ;;
        5)
            emby_ailg="jellyfin-ailg.mp4"
            emby_img="jellyfin-ailg.img"
            space_need=130
            break
            ;;
        6)
            emby_ailg="jellyfin-ailg-lite.mp4"
            emby_img="jellyfin-ailg-lite.img"
            space_need=110
            break
            ;;
        7)
            emby_ailg="jellyfin-10.9.6-ailg.mp4"
            emby_img="jellyfin-10.9.6-ailg.img"
            space_need=120
            break
            ;;
        8)
            emby_ailg="jellyfin-10.9.6-ailg-lite.mp4"
            emby_img="jellyfin-10.9.6-ailg-lite.img"
            space_need=110
            break
            ;;
        [Bb])
            clear
            main_menu
            return
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

    if [[ $st_gbox =~ "未安装" ]]; then
        ERROR "请先安装G-Box，再执行本安装！"
        read -erp -n 1 '按任意键返回主菜单'
        main_menu
        return
    fi
    umask 000
    [ -z "${config_dir}" ] && get_config_path
    INFO "正在为您清理阿里云盘空间……"
    docker exec $docker_name ali_clear -1 > /dev/null 2>&1
    echo -e "\033[1;35m请输入您的小雅emby/jellyfin镜像存放路径（请确保大于${space_need}G剩余空间！）:\033[0m"
    read -r image_dir
    echo -e "\033[1;35m请输入镜像下载后需要扩容的空间（单位：GB，默认60G可直接回车，请确保大于${space_need}G剩余空间！）:\033[0m"
    read -r expand_size
    expand_size=${expand_size:-60}
    # 先询问用户 115 网盘空间是否足够
    read -p "使用115下载镜像请确保cookie正常且网盘剩余空间不低于100G，（按Y/y 确认，按任意键走阿里云盘下载！）: " ok_115
    check_path $image_dir
    if [ -f "${image_dir}/${emby_ailg}" ] || [ -f "${image_dir}/${emby_img}" ]; then
        echo "镜像文件已存在，跳过空间检查"
    else
        check_space $image_dir $space_need
    fi

    if [[ "${f4_select}" == [1234] ]]; then
        search_img="emby/embyserver|amilys/embyserver"
        del_name="emby"
        loop_order="/dev/loop7"
        down_path="emby"
        [[ "${f4_select}" == [34] ]] && get_emby_image 4.9.0.38 || get_emby_image
        init="run"
        # emd_name="xiaoya-emd"
        emd_name="xy-emd"
        entrypoint_mount="entrypoint_emd"
        check_port "emby"
    elif [[ "${f4_select}" == [5678] ]]; then
        search_img="nyanmisaka/jellyfin|jellyfin/jellyfin"
        del_name="jellyfin_xy"
        loop_order="/dev/loop6"
        down_path="jellyfin"
        get_jellyfin_image
        init="run_jf"
        emd_name="xiaoya-emd-jf"
        entrypoint_mount="entrypoint_emd_jf"
        check_port "jellyfin"
    fi
    get_emby_status

    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs -r docker stop
    docker ps -a | grep 'ailg/xy-emd' | awk '{print $1}' | xargs -r docker stop
    if [ ${#emby_list[@]} -ne 0 ]; then
        for entry in "${emby_list[@]}"; do
            op_emby=${entry%%:*} 
            host_path=${entry#*:} 

            docker stop "${op_emby}" &> /dev/null
            INFO "${op_emby}容器已关闭！"

            if [[ "${host_path}" =~ .*\.img ]]; then
                mount | grep "${host_path%/*}/emby-xy" && umount "${host_path%/*}/emby-xy" && losetup -d "${loop_order}"
            else
                mount | grep "${host_path%/*}" && umount "${host_path%/*}"
            fi

            [[ "${op_emby}" == "${del_name}" ]] && docker rm "${op_emby}" && INFO "${op_emby}容器已删除！"
        done
    fi

    emby_name=${del_name}
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
        if [[ $ok_115 =~ ^[Yy]$ ]]; then
            remote_size=$(curl -sL -D - -o /dev/null --max-time 10 "$docker_addr/d/ailg_jf/115/${down_path}/$emby_ailg" | grep "Content-Length" | cut -d' ' -f2 | tail -n 1 | tr -d '\r')
        else
            remote_size=$(curl -sL -D - -o /dev/null --max-time 10 "$docker_addr/d/ailg_jf/${down_path}/$emby_ailg" | grep "Content-Length" | cut -d' ' -f2 | tail -n 1 | tr -d '\r')
        fi
        [[ -n $remote_size ]] && echo -e "remotesize is：${remote_size}" && break
    done
    if [[ $remote_size -lt 100000 ]]; then
        ERROR "获取文件大小失败，请检查网络后重新运行脚本！"
        echo -e "${Yellow}排障步骤：\n1、检查5678打开alist能否正常播放（排除token失效和风控！）"
        echo -e "${Yellow}2、检查alist配置目录的docker_address.txt是否正确指向你的alist访问地址，\n   应为宿主机+5678端口，示例：http://192.168.2.3:5678"
        echo -e "${Yellow}3、检查阿里云盘空间，确保剩余空间大于${space_need}G${NC}"
        echo -e "${Yellow}4、如果打开了阿里快传115，确保有115会员且添加了正确的cookie，不是115会员不要打开阿里快传115！${NC}"
        echo -e "${Yellow}5、💡使用115通道下载失败，检查5678页ailg_jf/115目录的视频是否能放，如cookie正常但此目录提示重新登陆，重启一次G-Box容器即可！💡${NC}"
        echo -e "${Yellow}6、如果网盘空间不足下载文件的2倍大小，在4567页的高级设置中将延时删除设置为2或3秒后重新运行脚本！${NC}"
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

    echo "$local_size $remote_size $image_dir/$emby_ailg $media_dir"
    mount | grep $media_dir && umount $media_dir
    if [ "$local_size" -eq "$remote_size" ]; then
        if [ -f "$image_dir/$emby_img" ]; then
            docker run -i --privileged --rm --net=host -v ${image_dir}:/ailg -v $media_dir:/mount_emby ailg/ggbond:latest \
                bash -c "strmhelper \"/ailg/${emby_img}\" \"/mount_emby\" \"${strmhelper_mode}\" && exp_ailg \"/ailg/${emby_img}\" \"/mount_emby\" ${expand_size} || { echo '执行strmhelper失败'; exit 1; }"
        else
            docker run -i --privileged --rm --net=host -v ${image_dir}:/ailg -v $media_dir:/mount_emby ailg/ggbond:latest \
                bash -c "strmhelper \"/ailg/${emby_ailg}\" \"/mount_emby\" \"${strmhelper_mode}\" && exp_ailg \"/ailg/${emby_img}\" \"/mount_emby\" ${expand_size} || { echo '执行strmhelper失败'; exit 1; }"
        fi
    else
        INFO "本地已有镜像，无需重新下载！"
    fi

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
    #if [ ! -f "$image_dir/${init}" ]; then
        rm -rf "$image_dir/${init}"
        docker cp "${docker_name}":/var/lib/${init} "$image_dir/"
        chmod 777 "$image_dir/${init}"
    #fi
    #if ${del_emby}; then
        if [[ "${emby_image}" =~ emby ]]; then
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run":/etc/cont-init.d/run \
                --user 0:0 \
                -e UID=0 -e GID=0 -e GIDLIST=0 \
                --net=host \
                --privileged --add-host="xiaoya.host:127.0.0.1" --restart always $emby_image
            echo "http://127.0.0.1:6908" > $config_dir/emby_server.txt
            fuck_cors "$emby_name"
        elif [[ "${emby_image}" =~ jellyfin/jellyfin ]]; then
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run_jf":/etc/run_jf \
                --entrypoint "/etc/run_jf" \
                --user 0:0 \
                -e XDG_CACHE_HOME=/config/cache \
                -e LC_ALL=zh_CN.UTF-8 \
                -e LANG=zh_CN.UTF-8 \
                -e LANGUAGE=zh_CN:zh \
                -e JELLYFIN_CACHE_DIR=/config/cache \
                -e HEALTHCHECK_URL=http://localhost:6910/health \
                --net=host \
                --privileged --add-host="xiaoya.host:127.0.0.1" --restart always $emby_image   
            echo "http://127.0.0.1:6910" > $config_dir/jellyfin_server.txt   
        else
            docker run -d --name $emby_name -v /etc/nsswitch.conf:/etc/nsswitch.conf \
                -v $image_dir/$emby_img:/media.img \
                -v "$image_dir/run_jf":/etc/run_jf \
                --entrypoint "/etc/run_jf" \
                --user 0:0 \
                -e XDG_CACHE_HOME=/config/cache \
                -e LC_ALL=zh_CN.UTF-8 \
                -e LANG=zh_CN.UTF-8 \
                -e LANGUAGE=zh_CN:zh \
                -e JELLYFIN_CACHE_DIR=/config/cache \
                -e HEALTHCHECK_URL=http://localhost:6909/health \
                -p 6909:6909 \
                -p 6920:6920 \
                -p 1909:1900/udp \
                -p 6359:7359/udp \
                --privileged --add-host="xiaoya.host:${host_ip}" --restart always $emby_image
            echo "${host}:6909" > $config_dir/jellyfin_server.txt
        fi

    [[ ! "${emby_image}" =~ emby ]] && echo "aec47bd0434940b480c348f91e4b8c2b" > $config_dir/infuse_api_key_jf.txt

    current_time=$(date +%s)
    elapsed_time=$(awk -v start=$start_time -v end=$current_time 'BEGIN {printf "%.2f\n", (end-start)/60}')
    INFO "${Blue}恭喜您！小雅emby/jellyfin安装完成，安装时间为 ${elapsed_time} 分钟！$NC"
    INFO "小雅emby请登陆${Blue} $host:2345 ${NC}访问，用户名：${Blue} xiaoya ${NC}，密码：${Blue} 1234 ${NC}"
    INFO "小雅jellyfin请登陆${Blue} $host:2346 ${NC}访问，用户名：${Blue} ailg ${NC}，密码：${Blue} 5678 ${NC}"
    INFO "注：Emby如果$host:6908可访问，而$host:2345访问失败（502/500等错误），按如下步骤排障：\n\t1、检查$config_dir/emby_server.txt文件中的地址是否正确指向emby的访问地址，即：$host:6908或http://127.0.0.1:6908\n\t2、地址正确重启你的G-Box容器即可。"
    INFO "注：Jellyfin如果$host:6909可访问（10.9.6版本端口为6910），而$host:2346访问失败（502/500等错误），按如下步骤排障：\n\t1、检查$config_dir/jellyfin_server.txt文件中的地址是否正确指向jellyfin的访问地址，即：$host:6909（10.9.6版是6910）或http://127.0.0.1:6909\n\t2、地址正确重启你的G-Box容器即可。"
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
        docker rm -f xiaoya-emd &> /dev/null
        docker stop ${emd_name} &> /dev/null
        if update_ailg "ailg/xy-emd:latest"; then
            xy_emby_sync
            if [ $? -eq 0 ]; then
                INFO "小雅元数据同步爬虫安装成功！"
            else
                INFO "小雅元数据同步爬虫安装失败，请重装安装！"
            fi
        else
            ERROR "ailg/xy-emd:latest镜像更新失败，请检查网络后手动安装！" && exit 1
        fi
    else
        INFO "安装完成，您选择不安装小雅爬虫同步！"
    fi
}

fuck_cors() {
    emby_name=${1:-emby}
    docker exec $emby_name sh -c "cp /system/dashboard-ui/modules/htmlvideoplayer/plugin.js /system/dashboard-ui/modules/htmlvideoplayer/plugin.js_backup && sed -i 's/&&(elem\.crossOrigin=initialSubtitleStream)//g' /system/dashboard-ui/modules/htmlvideoplayer/plugin.js"
    docker exec $emby_name sh -c "cp /system/dashboard-ui/modules/htmlvideoplayer/basehtmlplayer.js /system/dashboard-ui/modules/htmlvideoplayer/basehtmlplayer.js_backup && sed -i 's/mediaSource\.IsRemote&&"DirectPlay"===playMethod?null:"anonymous"/null/g' /system/dashboard-ui/modules/htmlvideoplayer/basehtmlplayer.js"
}

general_uninstall() {
    if [ -z "$2" ]; then
        containers=$(docker ps -a --filter "ancestor=${1}" --format "{{.ID}}")
        if [ -n "$containers" ]; then
            INFO "正在卸载${1}镜像的容器..."
            docker rm -f $containers
            INFO "卸载完成。"
        else
            WARN "未安装${1}镜像的容器！"
        fi
    else
        if docker ps -a | grep -qE " ${2}\b"; then
            docker rm -f $2
            INFO "${2}容器卸载完成！"
        else
            WARN "未安装${2}容器！"
        fi
    fi
}

ailg_uninstall() {
    clear
    while true; do
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m1、卸载老G版alist\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m2、卸载G-Box\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m3、卸载小雅老G速装版EMBY/JELLYFIN\033[0m"
        echo -e "\n"
        echo -e "\033[1;32m4、卸载G-Box内置的Sun-Panel导航\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m5、卸载小雅EMBY老G速装版爬虫\033[0m"
        echo -e "\n"
        echo -e "\033[1;35m6、卸载小雅JELLYFIN老G速装版爬虫\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"

        read -erp "请输入您的选择（1-6，按b返回上级菜单或按q退出）：" uninstall_select
        case "$uninstall_select" in
        1)
            general_uninstall "ailg/alist:latest"
            general_uninstall "ailg/alist:hostmode"
            break
            ;;
        2)
            general_uninstall "ailg/g-box:hostmode"
            break
            ;;
        3)
            img_uninstall
            break
            ;;
        4)
            sp_uninstall
            break
            ;;
        5)
            general_uninstall "ddsderek/xiaoya-emd:latest" "xiaoya-emd"
            break
            ;;
        6)
            general_uninstall "ddsderek/xiaoya-emd:latest" "xiaoya-emd-jf"
            break
            ;;
        [Bb])
            clear
            user_selecto
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
    read -n 1 -rp "按任意键返回主菜单"
    main_menu
}

sp_uninstall() {
    container=$(docker ps -a --filter "ancestor=ailg/g-box:hostmode" --format "{{.ID}}")
    if [ -n "$container" ]; then
        host_dir=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' $container)       
        if [ -n "$host_dir" ]; then
            echo "uninstall" > "$host_dir/sun-panel.txt"
            if docker exec "$container" test -f /app/sun-panel; then
                INFO "已为您卸载Sun-Panel导航，正在重启g-box容器……"
                docker restart $container
            else
                echo "Sun-Panel导航已经卸载。"
            fi
        else
            ERROR "未能定位到g-box容器的配置文件目录，请确认g-box是否正确安装，程序退出！"
            return 1
        fi
    else
        ERROR "老铁！你还没安装g-box怎么来卸载sun-panel呢？"
        return 1
    fi
}

img_uninstall() {   
    INFO "是否${Red}删除老G速装版镜像文件${NC} [Y/n]（保留请按N/n键，按其他任意键默认删除）"
    read -erp "请输入：" clear_img
    [[ ! "${clear_img}" =~ ^[Nn]$ ]] && clear_img="y"

    # declare -ga img_order
    img_order=()
    search_img="emby/embyserver|amilys/embyserver|nyanmisaka/jellyfin|jellyfin/jellyfin"
    check_qnap
    # check_loop_support
    get_emby_status > /dev/null
    if [ ${#emby_list[@]} -ne 0 ]; then
        for entry in "${emby_list[@]}"; do
            op_emby=${entry%%:*}
            host_path=${entry#*:}

            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done

        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要卸载的老G速装版emby：\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                host_path=""
                for entry in "${emby_list[@]}"; do
                    if [[ $entry == $name:* ]]; then
                        host_path=${entry#*:}
                        break
                    fi
                done
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name $host_path
            done

            while :; do
                read -erp "输入序号：" img_select
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    emby_name=${img_order[$((img_select - 1))]}
                    img_path=""
                    for entry in "${emby_list[@]}"; do
                        if [[ $entry == $emby_name:* ]]; then
                            img_path=${entry#*:}
                            break
                        fi
                    done

                    for op_emby in "${img_order[@]}"; do
                        docker stop "${op_emby}"
                        INFO "${op_emby}容器已关闭！"
                    done

                    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs -r docker stop
                    INFO "小雅爬虫容器已关闭！"

                    if [[ $(basename "${img_path}") == emby*.img ]]; then
                        loop_order=/dev/loop7
                        docker rm xiaoya-emd
                    else
                        loop_order=/dev/loop6
                        docker rm xiaoya-emd-jf
                    fi

                    umount "${loop_order}" > /dev/null 2>&1
                    losetup -d "${loop_order}" > /dev/null 2>&1
                    mount | grep -qF "${img_mount}" && umount "${img_mount}"
                    docker rm ${emby_name}

                    if [[ "${clear_img}" =~ ^[Yy]$ ]]; then
                        rm -f "${img_path}"
                        if [ -n "${img_path%/*}" ]; then
                            rm -rf "${img_path%/*}"/*
                        fi
                        INFO "已卸载${Yellow}${emby_name}${NC}容器，并删除${Yellow}${img_path}${NC}镜像！"
                        INFO "按任意键返回主菜单，或按q退出！"
                        read -erp -n 1 end_select
                        if [[ "${end_select}" =~ ^[Qq]$ ]]; then
                            exit
                        else
                            main_menu
                            return
                        fi  
                    else
                        INFO "已卸载${Yellow}${emby_name}${NC}容器，未删除${Yellow}${img_path}${NC}镜像！"
                        INFO "按任意键返回主菜单，或按q退出！"
                        read -erp -n 1 end_select
                        if [[ "${end_select}" =~ ^[Qq]$ ]]; then
                            exit
                        else
                            main_menu
                            return
                        fi
                    fi
                    break
                else
                    ERROR "您输入的序号无效，请输入一个在 1 到 ${#img_order[@]} 的数字。"
                fi
            done
        else
            INFO "您未安装任何老G速装版emby，按任意键返回主菜单，或按q退出！"
            read -erp -n 1 end_select
            if [[ "${end_select}" =~ ^[Qq]$ ]]; then
                exit
            else
                main_menu
                return
            fi
        fi
    else
        INFO "您未安装任何老G速装版emby，按任意键返回主菜单，或按q退出！"
        read -erp -n 1 end_select
        if [[ "${end_select}" =~ ^[Qq]$ ]]; then
            exit
        else
            main_menu
            return
        fi
    fi
}

happy_emby() {
    # declare -ga img_order
    img_order=()
    check_qnap
    # check_loop_support
    get_emby_status > /dev/null
    if [ ${#emby_list[@]} -ne 0 ]; then
        for entry in "${emby_list[@]}"; do
            op_emby=${entry%%:*}
            host_path=${entry#*:}

            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done

        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要换装/重装开心版的emby！\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                host_path=""
                for entry in "${emby_list[@]}"; do
                    if [[ $entry == $name:* ]]; then
                        host_path=${entry#*:}
                        break
                    fi
                done
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name $host_path
            done

            while :; do
                read -erp "输入序号：" img_select
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    happy_name=${img_order[$((img_select - 1))]}
                    happy_path=""
                    for entry in "${emby_list[@]}"; do
                        if [[ $entry == $happy_name:* ]]; then
                            happy_path=${entry#*:}
                            break
                        fi
                    done

                    # 获取当前emby容器使用的镜像版本
                    current_image=$(docker inspect --format '{{.Config.Image}}' "${happy_name}")
                    current_version=$(echo "$current_image" | awk -F':' '{print $NF}')
                    
                    # 如果无法获取版本号，让用户手动输入
                    if [[ -z "$current_version" ]]; then
                        echo -e "\033[1;33m无法自动获取emby版本号，请手动输入版本号。\033[0m"
                        echo -e "常见版本号示例："
                        echo -e "4.8.9.0  - 老G速装版默认版本"
                        echo -e "4.9.0.38 - 老G速装版新版本"
                        while true; do
                            read -erp "请输入版本号(格式如: 4.8.9.0): " current_version
                            if [[ $current_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                                break
                            else
                                ERROR "版本号格式不正确，请重新输入！"
                            fi
                        done
                    fi
                    
                    # 获取开心版镜像
                    get_emby_happy_image "$current_version"

                    docker rm -f "${happy_name}"
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
                    
                    sleep 5
                    if docker ps --format '{{.Names}}' | grep -q "^${happy_name}$"; then
                        fuck_cors "${happy_name}"
                        INFO "${Green}恭喜！开心版emby安装成功！${NC}"
                        INFO "请使用浏览器访问 ${Blue}http://ip:2345${NC} 使用小雅emby"
                        INFO "如需启用硬解，请使用 ${Blue}http://ip:6908${NC} 访问并自行配置"
                    else
                        ERROR "开心版emby安装失败！请检查docker日志:"
                    fi
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
    read -erp "请输入您要挂载的镜像的完整路径：（示例：/volume3/emby/emby-ailg-lite-115.img）" img_path
    img_name=$(basename "${img_path}")
    case "${img_name}" in
    "emby-ailg-115.img" | "emby-ailg-lite-115.img" | "jellyfin-ailg.img" | "jellyfin-ailg-lite.img" | "jellyfin-10.9.6-ailg-lite.img" | "jellyfin-10.9.6-ailg.img") ;;
    "emby-ailg-115-4.9.img" | "emby-ailg-lite-115-4.9.img") ;;
    "emby-ailg-115.mp4" | "emby-ailg-lite-115.mp4" | "jellyfin-ailg.mp4" | "jellyfin-ailg-lite.mp4" | "jellyfin-10.9.6-ailg-lite.mp4" | "jellyfin-10.9.6-ailg.mp4") ;;
    "emby-ailg-115-4.9.mp4" | "emby-ailg-lite-115-4.9.mp4")
        img_path="${img_path%.mp4}.img"
        ;;
    *)
        ERROR "您输入的不是老G的镜像，或已改名，确保文件名正确后重新运行脚本！"
        exit 1
        ;;
    esac
    img_mount=${img_path%/*.img}/emby-xy
    # read -p "$(echo img_mount is: $img_mount)"
    check_path ${img_mount}
}

mount_img() {
    # declare -ga img_order
    img_order=()
    search_img="emby/embyserver|amilys/embyserver|nyanmisaka/jellyfin|jellyfin/jellyfin"
    check_qnap
    # check_loop_support
    get_emby_status > /dev/null
    # update_ailg ailg/ggbond:latest
    if [ ! -f /usr/bin/mount_ailg ]; then
        docker cp g-box:/var/lib/mount_ailg "/usr/bin/mount_ailg"
        chmod 777 /usr/bin/mount_ailg
    fi
    if [ ${#emby_list[@]} -ne 0 ]; then
        for entry in "${emby_list[@]}"; do
            op_emby=${entry%%:*}
            host_path=${entry#*:}

            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done

        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要挂载的镜像：\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                host_path=""
                for entry in "${emby_list[@]}"; do
                    if [[ $entry == $name:* ]]; then
                        host_path=${entry#*:}
                        break
                    fi
                done
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 媒体库路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name $host_path
            done
            printf "[ 0 ] \033[1;33m手动输入需要挂载的老G速装版镜像的完整路径\n\033[0m"

            while :; do
                read -erp "输入序号：" img_select
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    emby_name=${img_order[$((img_select - 1))]}
                    img_path=""
                    for entry in "${emby_list[@]}"; do
                        if [[ $entry == $emby_name:* ]]; then
                            img_path=${entry#*:}
                            break
                        fi
                    done
                    img_mount=${img_path%/*.img}/emby-xy

                    for op_emby in "${img_order[@]}"; do
                        docker stop "${op_emby}"
                        INFO "${op_emby}容器已关闭！"
                    done

                    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs docker stop
                    INFO "小雅爬虫容器已关闭！"

                    [[ $(basename "${img_path}") == emby*.img ]] && loop_order=/dev/loop7 || loop_order=/dev/loop6
                    umount "${loop_order}" > /dev/null 2>&1
                    losetup -d "${loop_order}" > /dev/null 2>&1
                    mount | grep -qF "${img_mount}" && umount "${img_mount}"

                    docker start ${emby_name}
                    sleep 5

                    if ! docker ps --format '{{.Names}}' | grep -q "^${emby_name}$"; then
                        if mount_ailg "${img_path}" "${img_mount}"; then
                            INFO "已将${img_path}挂载到${img_mount}目录！"
                            return 0
                        else
                            ERROR "挂载失败，请重启设备后重试！"
                            exit 1
                        fi
                    fi

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

expand_img() {
    # declare -ga img_order
    img_order=()
    search_img="emby/embyserver|amilys/embyserver|nyanmisaka/jellyfin|jellyfin/jellyfin"
    check_qnap
    # check_loop_support
    get_emby_status > /dev/null
    # update_ailg ailg/ggbond:latest
    if [ ! -f /usr/bin/mount_ailg ]; then
        docker cp g-box:/var/lib/mount_ailg "/usr/bin/mount_ailg"
        chmod 777 /usr/bin/mount_ailg
    fi
    if [ ${#emby_list[@]} -ne 0 ]; then
        for entry in "${emby_list[@]}"; do
            op_emby=${entry%%:*}
            host_path=${entry#*:}

            if docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' "${op_emby}" | grep -qE "\.img /media\.img"; then
                img_order+=("${op_emby}")
            fi
        done

        if [ ${#img_order[@]} -ne 0 ]; then
            echo -e "\033[1;37m请选择你要扩容的镜像：\033[0m"
            for index in "${!img_order[@]}"; do
                name=${img_order[$index]}
                host_path=""
                for entry in "${emby_list[@]}"; do
                    if [[ $entry == $name:* ]]; then
                        host_path=${entry#*:}
                        break
                    fi
                done
                printf "[ %-1d ] 容器名: \033[1;33m%-20s\033[0m 镜像路径: \033[1;33m%s\033[0m\n" $((index + 1)) $name $host_path
            done
            printf "[ 0 ] \033[1;33m手动输入需要扩容的老G速装版镜像的完整路径\n\033[0m"

            while :; do
                read -erp "输入序号：" img_select
                WARN "注：扩容后镜像文件所在磁盘至少保留3G空间，比如所在磁盘\033[1;33m剩余100G\033[0m空间，扩容数值不能超过\033[1;33m97\033[0m！"
                read -erp "输入您要扩容的大小（单位：GB）：" expand_size
                if [ "${img_select}" -gt 0 ] && [ "${img_select}" -le ${#img_order[@]} ]; then
                    emby_name=${img_order[$((img_select - 1))]}
                    img_path=""
                    for entry in "${emby_list[@]}"; do
                        if [[ $entry == $emby_name:* ]]; then
                            img_path=${entry#*:}
                            break
                        fi
                    done
                    img_mount=${img_path%/*.img}/emby-xy

                    expand_diy_img_path
                    break
                elif [ "${img_select}" -eq 0 ]; then
                    get_img_path
                    expand_diy_img_path
                    losetup -d "${loop_order}" > /dev/null 2>&1
                    break
                else
                    ERROR "您输入的序号无效，请输入一个在 0 到 ${#img_order[@]} 的数字。"
                fi
            done
        else
            get_img_path
            expand_diy_img_path
            losetup -d "${loop_order}" > /dev/null 2>&1
        fi
    else
        echo -e "\033[1;35m请输入镜像下载后需要扩容的空间（单位：GB，默认60G可直接回车，请确保扩容后剩余空间大于5G！）:\033[0m"
        read -r expand_size
        expand_size=${expand_size:-60}
        get_img_path
        expand_diy_img_path
        losetup -d "${loop_order}" > /dev/null 2>&1
    fi
}

expand_diy_img_path() { 
    image_dir="$(dirname "${img_path}")"
    emby_img="$(basename "${img_path}")"
    for op_emby in "${img_order[@]}"; do
        docker stop "${op_emby}"
        INFO "${op_emby}容器已关闭！"
    done
    docker ps -a | grep 'ddsderek/xiaoya-emd' | awk '{print $1}' | xargs docker stop
    INFO "小雅爬虫容器已关闭！"
    [[ $(basename "${img_path}") == emby*.img ]] && loop_order=/dev/loop7 || loop_order=/dev/loop6
    umount "${loop_order}" > /dev/null 2>&1
    losetup -d "${loop_order}" > /dev/null 2>&1
    mount | grep -qF "${img_mount}" && umount "${img_mount}"
    docker run -i --privileged --rm --net=host -v ${image_dir}:/ailg -v ${img_mount}:/mount_emby ailg/ggbond:latest \
        exp_ailg "/ailg/$emby_img" "/mount_emby" ${expand_size}
    [ $? -eq 0 ] && docker start ${emby_name} || WARN "如扩容失败，请重启设备手动关闭emby/jellyfin和小雅爬虫容器后重试！"
}

sync_config() {
    if [[ $st_gbox =~ "未安装" ]]; then
        ERROR "请先安装G-Box，再执行本安装！"
        main_menu
        return
    fi
    umask 000
    [ -z "${config_dir}" ] && get_config_path
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
            ERROR "config.mp4下载失败，请检查网络，如果token失效或触发阿里风控将G-Box停止1小时后再打开重试！"
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
            curl -sSfL -o /tmp/sync_emby_config_ailg.sh https://ailg.ggbond.org/sync_emby_config_img_ailg.sh
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
        echo -e "\033[1;32m1、卸载全在这\033[0m"
        echo -e "\033[1;32m2、更换开心版小雅EMBY\033[0m"
        echo -e "\033[1;32m3、挂载老G速装版镜像\033[0m"
        echo -e "\033[1;32m4、老G速装版镜像重装/同步config\033[0m"
        echo -e "\033[1;32m5、G-box自动更新/取消自动更新\033[0m"
        echo -e "\033[1;32m6、速装emby/jellyfin镜像扩容\033[0m"
        echo -e "\033[1;32m7、修复docker镜像无法拉取（可手动配置镜像代理）\033[0m\033[0m"
        echo -e "\033[1;32m8、G-Box安装常用镜像下载（暂不可用，新方案测试中）\033[0m\033[0m"
        echo -e "\033[1;32m9、Emby/Jellyfin添加第三方播放器（适用Docker版）\033[0m\033[0m"
        echo -e "\033[1;32m10、安装/配置小雅Emby爬虫同步（G-Box专用版）\033[0m\033[0m"
        echo -e "\033[1;32m11、一键安装小雅Emby音乐资源\033[0m\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        read -erp "请输入您的选择（1-9，按b返回上级菜单或按q退出）：" fo_select
        case "$fo_select" in
        1) ailg_uninstall emby; break ;;
        2) happy_emby; break ;;
        3) mount_img; break ;;
        4) sync_config; break ;;
        5) sync_plan; break ;;
        6) expand_img; break ;;
        7) fix_docker; break ;;
        8) docker_image_download; break ;;
        9) add_player; break ;;
        10) xy_emby_sync; break ;;
        11) xy_emby_music; break ;;
        [Bb]) clear; break ;;
        [Qq]) exit 0 ;;
        *)
            ERROR "输入错误，按任意键重新输入！"
            read -r -n 1
            continue
            ;;
        esac
    done
    read -n 1 -rp "按任意键返回主菜单"
    main_menu
}

function xy_emby_music() {
    if [[ $st_gbox =~ "未安装" ]]; then
        ERROR "请先安装G-Box，再执行本安装！"
        main_menu
        return
    fi
    umask 000
    [ -z "${config_dir}" ] && get_config_path
    mount_img || exit 1
    if [ -s $config_dir/docker_address.txt ]; then
        docker_address=$(head -n1 $config_dir/docker_address.txt)
        if curl -siL ${docker_address}/d/README.md | grep -v 302 | grep "x-oss-"; then
            xiaoya_addr=${docker_address}
        else
            ERROR "请检查xiaoya是否正常运行后再试"
            exit 1
        fi
    else
        ERROR "请先配置 $config_dir/docker_address.txt 后重试"
        exit 1
    fi
    
    for i in {1..3}; do
        remote_size=$(curl -sL -D - -o /dev/null --max-time 10 "${xiaoya_addr}/d/元数据/music.mp4" | grep "Content-Length" | cut -d' ' -f2 | tail -n 1 | tr -d '\r')
        [[ -n $remote_size ]] && echo -e "远程music.mp4文件大小：${remote_size}" && break
    done
    
    if [[ -z $remote_size ]]; then
        ERROR "获取远程文件大小失败，请检查网络后重新运行脚本！"
        exit 1
    fi
    
    download_success=false
    for attempt in {1..3}; do
        INFO "第 ${attempt} 次尝试下载music.mp4文件..."
        
        docker run -i \
            --security-opt seccomp=unconfined \
            --rm \
            --net=host \
            -v ${img_mount}:/media \
            -v /tmp:/download \
            --workdir=/download \
            -e LANG=C.UTF-8 \
            ailg/ggbond:latest \
            aria2c -o music.mp4 --continue=true -x6 --conditional-get=true --allow-overwrite=true "${xiaoya_addr}/d/元数据/music.mp4"
        
        local_size=$(du -b /tmp/music.mp4 | cut -f1)
        
        if [[ -f /tmp/music.mp4.aria2 ]] || [[ $remote_size -ne "$local_size" ]]; then
            WARN "第 ${attempt} 次下载music.mp4文件不完整，将重新下载！"
            
            if [[ $attempt -eq 3 ]]; then
                ERROR "三次尝试后音乐文件依然下载不完整，请检查网络后重新运行脚本！"
                exit 1
            fi
        else
            INFO "music.mp4文件下载成功，开始解压..."
            download_success=true
            break
        fi
    done
    
    if $download_success; then
        docker run -i \
            --security-opt seccomp=unconfined \
            --rm \
            --net=host \
            -v ${img_mount}:/media \
            -v /tmp:/download \
            --workdir=/download \
            -e LANG=C.UTF-8 \
            ailg/ggbond:latest \
            bash -c "7z x -aoa -bb1 -mmt=16 /download/music.mp4 -o/media/xiaoya/ && chmod -R 777 /media/xiaoya/Music"
        
        if [ $? -eq 0 ]; then
            INFO "${Green}小雅Emby音乐资源安装成功！${NC}"
            INFO "音乐文件已解压到${Blue}${img_mount}/xiaoya/Music${NC}目录"
            INFO "请在Emby/Jellyfin中扫描Music目录完成入库，如没有Music媒体库，请自行添加，媒体库命名为Music，类型选音乐，挂载目录为${Blue}/media/Music${NC}"
            
            rm -f /tmp/music.mp4
        else
            ERROR "音乐资源解压失败，请检查磁盘空间或重新运行脚本！"
        fi
    fi
}


function docker_image_download() {
    echo -e "\033[1;33m使用本功能请确保您已安装G-Box并正在运行，且G-Box中添加了夸克网盘并正常运行，否则将无法下载！\033[0m"
    [[ -z $config_dir ]] && get_config_path
    base_url="$(head -n1 $config_dir/docker_address.txt)"
    while :; do
        echo -e "\n请选择CPU架构："
        echo -e "1. x86_64/amd64"
        echo -e "2. arm64/aarch64"
        read -erp "请选择（1-2）：" arch_choice
        
        case $arch_choice in
            1) arch="amd64" ; break ;;
            2) arch="arm64" ; break ;;
            *) ERROR "无效的选择" ;;
        esac
    done
    while :; do
        clear
        echo -e "\n"
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\033[1;35m1、G-Box镜像最新版 (ailg/g-box:hostmode)\033[0m"
        echo -e "\033[1;35m2、GGBond镜像最新版 (ailg/ggbond:latest)\033[0m"
        echo -e "\033[1;35m3、Emby官方镜像 4.8.9.0\033[0m"
        echo -e "\033[1;35m4、Emby官方镜像 4.9.0.38\033[0m"
        echo -e "\033[1;35m5、Jellyfin官方镜像 10.9.6\033[0m"
        echo -e "\033[1;35m6、Nyanmisaka Jellyfin最新版\033[0m"
        echo -e "\033[1;35m7、小雅爬虫镜像ddsderek/xiaoya-emd最新版\033[0m"
        echo -e "\033[1;35m8、CloudDrive2官方最新版\033[0m"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        
        read -erp "请选择要下载的镜像（1-8）：" image_choice

        # 根据选择确定镜像文件名
        case $image_choice in
            1) image_file="ailg.gbox.hostmode.${arch}.tar.gz" ; break ;;
            2) image_file="ailg.ggbond.latest.${arch}.tar.gz" ; break ;;
            3) image_file="emby.embyserver$([[ $arch == "arm64" ]] && echo "_arm64v8" || echo "").4.8.9.0.${arch}.tar.gz" ; break ;;
            4) image_file="emby.embyserver$([[ $arch == "arm64" ]] && echo "_arm64v8" || echo "").4.9.0.38.${arch}.tar.gz" ; break ;;
            5) image_file="jellyfin.jellyfin.10.9.6.${arch}.tar.gz" ; break ;;
            6) image_file="nyanmisaka.jellyfin.$([[ $arch == "arm64" ]] && echo "latest-rockchip" || echo "latest").${arch}.tar.gz" ; break ;;
            7) image_file="ddsderek.xiaoya-emd.latest.${arch}.tar.gz" ; break ;;
            8) image_file="cloudnas.clouddrive2.latest.${arch}.tar.gz" ; break ;;
            *) ERROR "无效的选择";;
        esac
    done
    
    # 获取下载目录
    read -erp "请输入保存镜像的目录路径：" save_dir
    check_path "$save_dir"
    
    # 下载镜像文件
    download_url="${base_url}/d/AI老G常用分享（夸克）/gbox常用镜像/${image_file}"
    
    if docker images | grep -q "ailg/ggbond" && [[ ! $image_file == *"ggbond"* ]]; then
        INFO "使用ailg/ggbond容器下载镜像..."
        # 添加文件大小检查
        docker run --rm \
            -v "${save_dir}:/ailg" \
            ailg/ggbond:latest \
            aria2c -o "/ailg/${image_file}" --auto-file-renaming=false --allow-overwrite=true -c -x6 "${download_url}"
        
        if ! [ -f "${save_dir}/${image_file}" ] || [[ -f "${save_dir}/${image_file}.aria2" ]]; then
            ERROR "镜像文件下载或验证失败"
            rm -f "${save_dir}/${image_file}"
            return 1
        fi
    else
        INFO "使用wget下载镜像..."
        if command -v wget > /dev/null; then
            wget -O "${save_dir}/${image_file}" "${download_url}"
        elif command -v curl > /dev/null; then
            curl -sSLf "${download_url}" -o "${save_dir}/${image_file}"
        else
            ERROR "未找到wget或curl，无法下载"
            return 1
        fi

        # 验证下载的文件
        if [[ ! -f "${save_dir}/${image_file}" ]] || \
           [[ $(stat -c%s "${save_dir}/${image_file}") -lt 1000000 ]] || \
           ! gunzip -t "${save_dir}/${image_file}" 2>/dev/null; then
            ERROR "下载的文件无效或损坏"
            rm -f "${save_dir}/${image_file}"
            return 1
        fi
    fi
    
    if [ -f "${save_dir}/${image_file}" ]; then
        INFO "镜像文件下载完成，正在导入..."
        if gunzip -c "${save_dir}/${image_file}" | docker load; then
            INFO "镜像导入成功！"
        else
            ERROR "镜像导入失败！"
        fi
    else
        ERROR "镜像文件下载失败！"
        return 1
    fi
}

function add_player() {
    while :; do
        clear
        logo
        echo -e "\n"
        echo -e "\033[1;32m请输入您要添加第三方播放器的Docker容器名称！\033[0m"
        WARN "注意：是容器名，不是Docker镜像名！比如：小雅Emby的镜像名是—— emby/embyserver:latest ，容器名是—— emby"
        read -erp "请输入：" container_name
        if [ -z "$container_name" ]; then
            ERROR "未输入容器名称，请重新输入！"
            continue
        fi
        if ! docker ps | grep -q "$container_name"; then
            ERROR "未找到容器，请重新输入！"
            continue
        else
            break
        fi
    done
        
    WARN "如果您的Emby/Jellyfin容器已安装第三方播放器，请勿重复安装，继续请按y，按任意键返回主菜单！"
    WARN "如果您用此脚本安装过需要恢复原样，请按 r或R"
    read -erp "请输入：" add_player_choice
    if [[ "$add_player_choice" == [Rr] ]]; then
        restore_player=1
    elif [[ "$add_player_choice" != [Yy] ]]; then
        main_menu
        return 0
    fi
    isEmby=$(docker inspect "$container_name" --format '{{.Config.Image}}' | grep -q "emby" && echo "true" || echo "false")
    if [ "$isEmby" == "true" ]; then
        INDEX_FILE=$(docker exec "$container_name" sh -c "find /system /app /opt -name index.html 2>/dev/null")
    else
        INDEX_FILE=$(docker exec "$container_name" sh -c 'echo $JELLYFIN_WEB_DIR')/index.html
        if [ -z "$INDEX_FILE" ]; then
            INDEX_FILE=$(docker exec "$container_name" sh -c "find /jellyfin -name index.html 2>/dev/null")
        fi
    fi
    
    if [ -z "$INDEX_FILE" ]; then
        ERROR "未在您的容器中找到index.html路径，操作取消"
        return 1
    fi
    
    INDEX_DIR=$(dirname "$INDEX_FILE")

    if [ "$restore_player" == "1" ]; then
        if [ -f "${INDEX_FILE}.bak" ]; then
            docker exec "$container_name" sh -c "cp -f \"${INDEX_FILE}.bak\" \"$INDEX_FILE\"" >/dev/null 2>&1
        else
            docker exec "$container_name" sh -c "sed -i 's|<script src=\"externalPlayer.js\" defer></script>||g' $INDEX_FILE"
        fi
        [ $? -eq 0 ] && INFO "恢复成功！" || ERROR "恢复失败！您可能要重新安装${container_name}容器！"
        return 0
    fi

    for i in {1..3}; do
        curl -sSLf https://ailg.ggbond.org/externalPlayer.js -o "/tmp/externalPlayer.js"
        if [ -f "/tmp/externalPlayer.js" ]; then
            if grep -q "embyPot" "/tmp/externalPlayer.js"; then
                break
            fi 
        fi
    done
    
    if [ -f "/tmp/externalPlayer.js" ]; then
        if grep -q "embyPot" "/tmp/externalPlayer.js"; then
            docker cp "/tmp/externalPlayer.js" "$container_name":"$INDEX_DIR/externalPlayer.js"
            docker exec "$container_name" sh -c "cp \"$INDEX_FILE\" \"${INDEX_FILE}.bak\""
            INFO "备份文件：${INDEX_FILE}.bak"
            docker exec "$container_name" sh -c "sed -i 's|</body>|<script src=\"externalPlayer.js\" defer></script></body>|g' \"$INDEX_FILE\""
            INFO "第三方播放器添加成功！"
        else
            ERROR "文件下载失败，第三方播放器添加失败！"
        fi
    fi
    
    read -n 1 -rp "按任意键返回主菜单"
    main_menu
}

fix_docker() {
    docker_pid() {
        if [ -f /var/run/docker.pid ]; then
            kill -SIGHUP $(cat /var/run/docker.pid)
        elif [ -f /var/run/dockerd.pid ]; then
            kill -SIGHUP $(cat /var/run/dockerd.pid)
        else
            echo "Docker进程不存在，脚本中止执行。"
            if [ "$FILE_CREATED" == false ]; then
                cp $BACKUP_FILE $DOCKER_CONFIG_FILE
                echo -e "\033[1;33m原配置文件：${DOCKER_CONFIG_FILE} 已恢复，请检查是否正确！\033[0m"
            else
                rm -f $DOCKER_CONFIG_FILE
                echo -e "\033[1;31m已删除新建的配置文件：${DOCKER_CONFIG_FILE}\033[0m"
            fi
            return 1
        fi 
    }

    jq_exec() {
        jq --argjson urls "$REGISTRY_URLS_JSON" '
            if has("registry-mirrors") then
                .["registry-mirrors"] = $urls
            else
                . + {"registry-mirrors": $urls}
            end
        ' "$DOCKER_CONFIG_FILE" > tmp.$$.json && mv tmp.$$.json "$DOCKER_CONFIG_FILE"
    }

    clear
    if ! command_exists "docker"; then
        echo -e $'\033[1;33m你还没有安装docker，请先安装docker，安装后无法拖取镜像再运行脚本！\033[0m'
        echo -e "docker一键安装脚本参考："
        echo -e $'\033[1;32m\tcurl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh\033[0m'
        echo -e "或者："
        echo -e $'\033[1;32m\twget -qO- https://get.docker.com | sh\033[0m'
        exit 1
    fi

    REGISTRY_URLS=('https://docker.gbox.us.kg' 'https://hub.rat.dev' 'https://docker.1ms.run' 'https://dockerhub.anzu.vip' 'https://freeno.xyz' 'https://dk.nastool.de' 'https://docker.fxxk.dedyn.io')

    DOCKER_CONFIG_FILE=''
    BACKUP_FILE=''

    REQUIRED_COMMANDS=('awk' 'jq' 'grep' 'cp' 'mv' 'kill')
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command_exists "$cmd"; then
            echo "缺少命令: $cmd，尝试安装..."
            if ! install_command "$cmd"; then
                echo "安装 $cmd 失败，请手动安装后再运行脚本。"
                exit 1
            fi
        fi
    done

    read -p $'\033[1;33m是否使用自定义镜像代理？（y/n）: \033[0m' use_custom_registry
    if [[ "$use_custom_registry" == [Yy] ]]; then
        read -p "请输入自定义镜像代理（示例：https://docker.ggbox.us.kg，多个请用空格分开。直接回车将重置为空）: " -a custom_registry_urls
        if [ ${#custom_registry_urls[@]} -eq 0 ]; then
            echo "未输入任何自定义镜像代理，镜像代理将重置为空。"
            REGISTRY_URLS=()
        else
            REGISTRY_URLS=("${custom_registry_urls[@]}")
        fi
    fi

    echo -e "\033[1;33m正在执行修复，请稍候……\033[0m"

    if [ ${#REGISTRY_URLS[@]} -eq 0 ]; then
        REGISTRY_URLS_JSON='[]'
    else
        REGISTRY_URLS_JSON=$(printf '%s\n' "${REGISTRY_URLS[@]}" | jq -R . | jq -s .)
    fi

    if [ -f /etc/synoinfo.conf ]; then
        DOCKER_ROOT_DIR=$(docker info 2>/dev/null | grep 'Docker Root Dir' | awk -F': ' '{print $2}')
        DOCKER_CONFIG_FILE="${DOCKER_ROOT_DIR%/@docker}/@appconf/ContainerManager/dockerd.json"
    elif command_exists busybox; then
        DOCKER_CONFIG_FILE=$(ps | grep dockerd | awk '{for(i=1;i<=NF;i++) if ($i ~ /^--config-file(=|$)/) {if ($i ~ /^--config-file=/) print substr($i, index($i, "=") + 1); else print $(i+1)}}')
    else
        DOCKER_CONFIG_FILE=$(ps -ef | grep dockerd | awk '{for(i=1;i<=NF;i++) if ($i ~ /^--config-file(=|$)/) {if ($i ~ /^--config-file=/) print substr($i, index($i, "=") + 1); else print $(i+1)}}')
    fi

    DOCKER_CONFIG_FILE=${DOCKER_CONFIG_FILE:-/etc/docker/daemon.json}

    if [ ! -f "$DOCKER_CONFIG_FILE" ]; then
        echo "配置文件 $DOCKER_CONFIG_FILE 不存在，创建新文件。"
        mkdir -p "$(dirname "$DOCKER_CONFIG_FILE")" && echo "{}" > $DOCKER_CONFIG_FILE
        FILE_CREATED=true
    else
        FILE_CREATED=false
    fi

    if [ "$FILE_CREATED" == false ]; then
        BACKUP_FILE="${DOCKER_CONFIG_FILE}.bak"
        cp -f $DOCKER_CONFIG_FILE $BACKUP_FILE
    fi

    jq_exec

    if ! docker_pid; then
        exit 1
    fi

    if [ "$REGISTRY_URLS_JSON" == '[]' ]; then
        echo -e "\033[1;33m已清空镜像代理，不再检测docker连接性，直接退出！\033[0m"
        exit 0
    fi

    docker rmi hello-world:latest >/dev/null 2>&1
    if docker pull hello-world; then
        echo -e "\033[1;32mNice！Docker下载测试成功，配置更新完成！\033[0m"
    else
        echo -e "\033[1;31m哎哟！Docker测试下载失败，恢复原配置文件...\033[0m"
        if [ "$FILE_CREATED" == false ]; then
            cp -f $BACKUP_FILE $DOCKER_CONFIG_FILE
            echo -e "\033[1;33m原配置文件：${DOCKER_CONFIG_FILE} 已恢复，请检查是否正确！\033[0m"
            docker_pid
        else
            REGISTRY_URLS_JSON='[]'
            jq_exec
            docker_pid
            rm -f $DOCKER_CONFIG_FILE
            echo -e "\033[1;31m已删除新建的配置文件：${DOCKER_CONFIG_FILE}\033[0m"
        fi  
    fi
}

function sync_plan() {
    while :; do
        clear
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m请输入您的选择：\033[0m"
        echo -e "\033[1;32m1、设置G-Box自动更新\033[0m"
        echo -e "\033[1;32m2、取消G-Box自动更新\033[0m"
        echo -e "\033[1;32m3、立即更新G-Box\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        read -erp "输入序号：（1-3，按b返回上级菜单或按q退出）" user_select_sync_ailg
        case "$user_select_sync_ailg" in
        1) 
            docker_name="g-box"
            image_name="ailg/g-box:hostmode"
            break
            ;;
        2)
            if [[ -f /etc/synoinfo.conf ]]; then
                sed -i '/xy_install/d' /etc/crontab
                INFO "已取消G-Box自动更新"
            else
                crontab -l | grep -v xy_install > /tmp/cronjob.tmp
                crontab /tmp/cronjob.tmp
                rm -f /tmp/cronjob.tmp
                INFO "已取消G-Box自动更新"
            fi
            exit 0
            ;;
        3)
            docker_name="$(docker ps -a | grep -E 'ailg/g-box' | awk '{print $NF}' | head -n1)"
            if [ -n "${docker_name}" ]; then
                /bin/bash -c "$(curl -sSLf https://ailg.ggbond.org/xy_install.sh)" -s "${docker_name}"
            else
                ERROR "未找到G-Box容器，请先安装G-Box！"
            fi
            exit 0
            ;;
        [Bb])
            clear
            main_menu
            return
            ;;
        [Qq])
            exit 0
            ;;
        *)
            ERROR "输入错误，按任意键重新输入！"
            read -r -n 1
            continue
            ;;
        esac
    done

    while :; do
        echo -e "\033[1;37m请设置您希望${docker_name}每次检查更新的时间：\033[0m"
        read -erp "注意：24小时制，格式：\"hh:mm\"，小时分钟之间用英文冒号分隔，示例：23:45）：" sync_time
        read -erp "您希望几天检查一次？（单位：天）" sync_day
        [[ -f /etc/synoinfo.conf ]] && is_syno="syno"
        time_value=${sync_time//：/:}
        hour=${time_value%%:*}
        minu=${time_value#*:}

        
        if ! [[ "$hour" =~ ^([01]?[0-9]|2[0-3])$ ]] || ! [[ "$minu" =~ ^([0-5]?[0-9])$ ]]; then
            echo "输入错误，请重新输入。小时必须为0-23的正整数，分钟必须为0-59的正整数。"
        else
            break
        fi
    done


    config_dir=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/data" }}{{ .Source }}{{ end }}{{ end }}' "${docker_name}")
    [ -z "${config_dir}" ] && ERROR "未找到${docker_name}的挂载目录，请检查！" && exit 1
    if command -v crontab >/dev/null 2>&1; then
        crontab -l | grep -v xy_install > /tmp/cronjob.tmp
        echo "$minu $hour */${sync_day} * * /bin/bash -c \"\$(curl -sSLf https://ailg.ggbond.org/xy_install.sh)\" -s "${docker_name}" | tee ${config_dir}/cron.log" >> /tmp/cronjob.tmp
        crontab /tmp/cronjob.tmp
        chmod 777 ${config_dir}/cron.log
        echo -e "\n"
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\n"	
        INFO "已经添加下面的记录到crontab定时任务，每${sync_day}天更新一次${docker_name}镜像"
        echo -e "\033[1;35m"
        grep xy_install /tmp/cronjob.tmp
        echo -e "\033[0m"
        INFO "您可以在 > ${config_dir}/cron.log < 中查看同步执行日志！"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
    elif [[ "${is_syno}" == syno ]];then
        cp /etc/crontab /etc/crontab.bak
        echo -e "\033[1;35m已创建/etc/crontab.bak备份文件！\033[0m"
        
        sed -i '/xy_install/d' /etc/crontab
        echo "$minu $hour */${sync_day} * * root /bin/bash -c \"\$(curl -sSLf https://ailg.ggbond.org/xy_install.sh)\" -s "${docker_name}" | tee ${config_dir}/cron.log" >> /etc/crontab
        chmod 777 ${config_dir}/cron.log
        echo -e "\n"
        echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
        echo -e "\n"	
        INFO "已经添加下面的记录到crontab定时任务，每$4天更新一次config"
        echo -e "\033[1;35m"
        grep xy_install /tmp/cronjob.tmp
        echo -e "\033[0m"
        INFO "您可以在 > ${config_dir}/cron.log < 中查看同步执行日志！"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
    fi
}

function user_gbox() {
    WARN "安装g-box会卸载已安装的G-Box和小雅tv-box以避免端口冲突！"
    read -erp "请选择：（确认按Y/y，否则按任意键返回！）" re_setup
    _update_img="ailg/g-box:hostmode"
    if [[ $re_setup == [Yy] ]]; then
        image_keywords=("ailg/alist" "xiaoyaliu/alist" "ailg/g-box" "haroldli/xiaoya-tvbox")
        for keyword in "${image_keywords[@]}"; do
            for container_id in $(docker ps -a | grep "$keyword" | awk '{print $1}'); do
                config_dir=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Destination=="/data") | .Source')
                if docker rm -f "$container_id"; then
                    echo -e "${container_id}容器已删除！"
                fi
            done
        done

        if ! update_ailg "${_update_img}"; then
            ERROR "G-Box镜像拉取失败，请检查网络环境或稍后再试！"
            exit 1
        fi
    else
        main_menu
        return
    fi
    check_port "g-box"
    
    #获取安装路径
    if [[ -n "$config_dir" ]]; then
        INFO "你原来G-Box/小雅alist/tvbox的配置路径是：${Blue}${config_dir}${NC}，可使用原有配置继续安装！"
        read -erp "确认请按任意键，或者按N/n手动输入路径：" user_select_0
        if [[ $user_select_0 == [Nn] ]]; then
            echo -e "\033[1;35m请输入您的小雅g-box配置文件路径:\033[0m"
            read -r config_dir
            check_path $config_dir
            INFO "G-Box配置路径为：$config_dir"
        fi
    else
        read -erp "请输入G-Box的安装路径，使用默认的/etc/g-box可直接回车：" config_dir
        config_dir=${config_dir:-"/etc/g-box"}
        check_path $config_dir
        INFO "G-Box配置路径为：$config_dir"
    fi

    read -erp "$(INFO "是否打开docker容器管理功能？（y/n）")" open_warn
    if [[ $open_warn == [Yy] ]]; then
        echo -e "${Yellow}风险警示："
        echo -e "打开docker容器管理功能会挂载/var/run/docker.sock！"
        echo -e "想在G-Box首页Sun-Panel中管理docker容器必须打开此功能！！"
        echo -e "想实现G-Box重启自动更新或添加G-Box自定义挂载必须打开此功能！！"
        echo -e "${Red}打开此功能会获取所有容器操作权限，有一定安全风险，确保您有良好的风险防范意识和妥当操作能力，否则不要打开此功能！！！"
        echo -e "如您已打开此功能想要关闭，请重新安装G-Box，重新进行此项选择！${NC}"
        read -erp "$(WARN "是否继续开启docker容器管理功能？（y/n）")" open_sock
    fi

    local extra_volumes=""
    if [ -s "$config_dir/diy_mount.txt" ]; then
        while IFS=' ' read -r host_path container_path; do
            if [[ -z "$host_path" || -z "$container_path" ]]; then
                continue
            fi

            if [ ! -d "$host_path" ]; then
                WARN "宿主机路径 $host_path 不存在，中止处理 diy_mount.txt 文件"
                extra_volumes=""
                break
            fi

            local reserved_paths=("/app" "/etc" "/sys" "/home" "/mnt" "/bin" "/data" "/dev" "/index" "/jre" "/lib" "/opt" "/proc" "/root" "/run" "/sbin" "/tmp" "/usr" "/var" "/www")
            if [[ " ${reserved_paths[@]} " =~ " $container_path " ]]; then
                WARN "容器路径 $container_path 是内部保留路径，中止处理 diy_mount.txt 文件"
                extra_volumes=""
                break
            fi

            extra_volumes+="-v $host_path:$container_path "
        done < "$config_dir/diy_mount.txt"
    fi

    if [[ $open_sock == [Yy] ]]; then
        if [ -S /var/run/docker.sock ]; then
            extra_volumes+="-v /var/run/docker.sock:/var/run/docker.sock"
        else
            WARN "您系统不存在/var/run/docker.sock，可能它在其他位置，请定位文件位置后自行挂载，此脚本不处理特殊情况！"
        fi
    fi

    if curl -sSLf -o /tmp/share_resources.sh https://ailg.ggbond.org/share_resources.sh &> /dev/null; then
        source /tmp/share_resources.sh
        select_share_resources "$config_dir"
        rm -f /tmp/share_resources.sh
    fi
    
    mkdir -p "$config_dir/data"
    docker run -d --name=g-box --net=host \
        -v "$config_dir":/data \
        -v "$config_dir/data":/www/data \
        --restart=always \
        $extra_volumes \
        ailg/g-box:hostmode

    if command -v ifconfig &> /dev/null; then
        localip=$(ifconfig -a|grep inet|grep -v 172. | grep -v 127.0.0.1|grep -v 169. |grep -v inet6|awk '{print $2}'|tr -d "addr:"|head -n1)
    else
        localip=$(ip address|grep inet|grep -v 172. | grep -v 127.0.0.1|grep -v 169. |grep -v inet6|awk '{print $2}'|tr -d "addr:"|head -n1|cut -f1 -d"/")
    fi

    echo "http://$localip:5678" > $config_dir/docker_address.txt
    [ ! -s $config_dir/infuse_api_key.txt ] && echo "e825ed6f7f8f44ffa0563cddaddce14d" > "$config_dir/infuse_api_key.txt"
    [ ! -s $config_dir/infuse_api_key_jf.txt ] && echo "aec47bd0434940b480c348f91e4b8c2b" > "$config_dir/infuse_api_key_jf.txt"
    [ ! -s $config_dir/emby_server.txt ] && echo "http://127.0.0.1:6908" > $config_dir/emby_server.txt
    [ ! -s $config_dir/jellyfin_server.txt ] && echo "http://127.0.0.1:6909" > $config_dir/jellyfin_server.txt

    INFO "${Blue}哇塞！你的G-Box安装完成了！$NC"
    INFO "${Blue}如果你没有配置mytoken.txt和myopentoken.txt文件，请登陆\033[1;35mhttp://${localip}:4567\033[0m网页在'账号-详情'中配置！$NC"
    INFO "G-Box初始登陆${Green}用户名：admin\t密码：admin ${NC}"
    INFO "内置sun-panel导航初始登陆${Green}用户名：ailg666\t\t密码：12345678 ${NC}"
}



#删除原来的小雅容器
rm_alist() {
    for container in $(docker ps -aq); do
        image=$(docker inspect --format '{{.Config.Image}}' "$container")
        if [[ "$image" == "xiaoyaliu/alist:latest" ]] || [[ "$image" == "xiaoyaliu/alist:hostmode" ]]; then
            WARN "本安装会删除原有的小雅alist容器，按任意键继续，或按CTRL+C退出！"
            read -r -n 1
            echo "Deleting container $container using image $image ..."
            # config_dir=$(docker inspect --format '{{ (index .Mounts 0).Source }}' "$container")
            config_dir=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$container")
            docker stop "$container"
            docker rm "$container"
            echo "Container $container has been deleted."
        fi
    done
}

choose_mirrors() {
    [ -z "${config_dir}" ] && get_config_path check_docker
    mirrors=(
        "docker.io"
        "docker.gbox.us.kg"
        "hub.rat.dev"
        "docker.1ms.run"
        "dk.nastool.de"
        "docker.aidenxin.xyz"
        "dockerhub.anzu.vip"
        "proxy.1panel.live"
        "freeno.xyz"
        "docker.adysec.com"
        "dockerhub.icu"
    )
    mirror_total_delays=()

    if [ ! -f "${config_dir}/docker_mirrors.txt" ]; then
        echo -e "\033[1;32m正在进行代理测速，为您选择最佳代理……\033[0m"
        start_time=$SECONDS
        for i in "${!mirrors[@]}"; do
            total_delay=0
            success=true
            INFO "${mirrors[i]}代理点测速中……"
            for n in {1..3}; do
                output=$(
                    curl -s -o /dev/null -w '%{time_total}' --head --request GET -m 10 "${mirrors[$i]}"
                    [ $? -ne 0 ] && success=false && break
                )
                total_delay=$(echo "$total_delay + $output" | awk '{print $1 + $3}')
            done
            if $success && docker pull "${mirrors[$i]}/library/hello-world:latest" &> /dev/null; then
                INFO "${mirrors[i]}代理可用，测试完成！"
                mirror_total_delays+=("${mirrors[$i]}:$total_delay")
                docker rmi "${mirrors[$i]}/library/hello-world:latest" &> /dev/null
            else
                INFO "${mirrors[i]}代理测试失败，将继续测试下一代理点！"
            fi
        done

        if [ ${#mirror_total_delays[@]} -eq 0 ]; then
            echo -e "\033[1;31m所有代理测试失败，检查网络或配置可用代理后重新运行脚本，请从主菜单手动退出！\033[0m"
        else
            sorted_mirrors=$(for entry in "${mirror_total_delays[@]}"; do echo $entry; done | sort -t: -k2 -n)
            echo "$sorted_mirrors" | head -n 2 | awk -F: '{print $1}' > "${config_dir}/docker_mirrors.txt"
            echo -e "\033[1;32m已为您选取两个最佳代理点并添加到了${config_dir}/docker_mirrors.txt文件中：\033[0m"
            cat "${config_dir}/docker_mirrors.txt"
        fi

        end_time=$SECONDS
        execution_time=$((end_time - start_time))
        minutes=$((execution_time / 60))
        seconds=$((execution_time % 60))
        echo "代理测速用时：${minutes} 分 ${seconds} 秒"
        read -n 1 -s -p "$(echo -e "\033[1;32m按任意键继续！\n\033[0m")"
    fi 
}


fuck_docker() {
    clear
    echo -e "\n"
    echo -e "———————————————————————————————————— \033[1;33mA  I  老  G\033[0m —————————————————————————————————"
    echo -e "\033[1;37m1、本脚本首次运行会自动检测docker站点的连接性，并自动为您筛选连接性最好的docker镜像代理！\033[0m"
    echo -e "\033[1;37m2、代理配置文件docker_mirrors.txt默认存放在G-Box的配置目录，如未自动找到请根据提示完成填写！\033[0m"
    echo -e "\033[1;37m3、如果您找到更好的镜像代理，可手动添加到docker_mirrors.txt中，一行一个，越靠前优化级越高！\033[0m"
    echo -e "\033[1;37m4、如果所有镜像代理测试失败，请勿继续安装并检查您的网络环境，不听劝的将大概率拖取镜像失败！\033[0m"
    echo -e "\033[1;37m5、代理测速正常2-3分钟左右，如某个代理测速卡很久，可按CTRL+C键终止执行，检查网络后重试（如DNS等）！\033[0m"
    echo -e "\033[1;33m6、仅首次运行或docker_mirrors.txt文件不存在或文件中代理失效时需要测速！为了后续顺利安装请耐心等待！\033[0m"
    echo -e "——————————————————————————————————————————————————————————————————————————————————"
    read -erp "$(echo -e "\033[1;32m跳过测速将使用您当前网络和环境设置直接拉取镜像，是否跳过？（Y/N）\n\033[0m")" skip_choose_mirror
    if ! [[ "$skip_choose_mirror" == [Yy] ]]; then
        choose_mirrors
    fi
}

update_gbox() {
    INFO "正在更新G-Box容器……"
    image_name="ailg/g-box:hostmode"
    docker_name="$(docker ps -a | grep -E 'ailg/g-box' | awk '{print $NF}' | head -n1)"
    if [ -z "${docker_name}" ]; then
        WARN "您未安装G-Box容器，是否立即安装？（Y/N）  " && read -r -n 1 get_install
        case $get_install in
        [Yy]*)
            user_gbox
            exit 0
            ;;
        *) exit 0 ;;
        esac
    fi
    
    if update_ailg "${image_name}"; then
        echo "$(date): ${image_name} 镜像更新完成！"
    else
        ERROR "更新 ${image_name} 镜像失败，将为您恢复旧镜像和容器……"
    fi
}

update_data() {
    INFO "正在更新小雅的data文件……"
    docker_name="$(docker ps -a | grep -E 'ailg/g-box' | awk '{print $NF}' | head -n1)"
    if [ -n "${docker_name}" ]; then
        files=("version.txt" "index.zip" "update.zip" "tvbox.zip")  
        url_base="https://ailg.ggbond.org/"
        download_dir="/www/data"

        mkdir -p /tmp/data
        cd /tmp/data    
        rm -rf /tmp/data/*

        download_file() {
            local file=$1
            local retries=3
            local success=1 

            for ((i=1; i<=retries; i++)); do
                if curl -s -O ${url_base}${file}; then
                    INFO "${file}下载成功"
                    if [[ ${file} == *.zip ]]; then
                        if [[ $(stat -c%s "${file}") -gt 500000 ]]; then
                            success=0
                            break
                        else
                            WARN "${file}文件大小不足，重试..."
                        fi
                    else    
                        success=0
                        break
                    fi
                else
                    ERROR "${file}下载失败，重试..."
                fi
            done    

            return ${success}
        }

        all_success=1
        for file in "${files[@]}"; do
            if download_file ${file}; then
                docker exec ${docker_name} mkdir -p ${download_dir}
                docker cp ${file} ${docker_name}:${download_dir}
            else
                all_success=0
                ERROR "${file}下载失败，程序退出！"
                exit 1  
            fi
        done

        if [[ ${all_success} -eq 1 ]]; then
            INFO "所有文件更新成功，正在为您重启G-Box容器……"
            docker restart ${docker_name}  
            INFO "G-Box容器已成功重启，请检查！"
        else
            ERROR "部分文件下载失败，程序退出！"
            exit 1
        fi
    else    
        ERROR "未找到G-Box容器，程序退出！"
        exit 1
    fi
}

temp_gbox() {
    INFO "正在使用临时方法更新/安装G-Box容器……"
    [ -z "${config_dir}" ] && get_config_path
    docker_name="$(docker ps -a | grep -E 'ailg/g-box' | awk '{print $NF}' | head -n1)" 
    docker_name="${docker_name:-g-box}"

    # 获取GB版本号并提取日期值作为tag
    local gb_version=""
    if [ -n "$1 " ]; then
        gb_version_tag="$1"
        if ! [[ "${gb_version_tag}" =~ ^([0-9]{6})$ ]]; then
            ERROR "输入的GB版本号格式不正确，请输入正确的GB版本号！"
            exit 1
        fi  
    else
        for i in {1..3}; do
            gb_version=$(curl -sSLf https://ailg.ggbond.org/GB_version)
        if [[ "${gb_version}" =~ ^GB\.([0-9]{6})\.[0-9]{4}$ ]]; then
            gb_version_tag="${BASH_REMATCH[1]}"
            break
        fi
            sleep 1
        done
    fi

    if [ -z "$gb_version_tag" ]; then
        ERROR "无法获取有效的GB版本号，程序退出！"
        exit 1
    fi

    read -erp "$(INFO "是否打开docker容器管理功能？（y/n）")" open_warn
    if [[ $open_warn == [Yy] ]]; then
        echo -e "${Yellow}风险警示："
        echo -e "打开docker容器管理功能会挂载/var/run/docker.sock！"
        echo -e "想在G-Box首页Sun-Panel中管理docker容器必须打开此功能！！"
        echo -e "想实现G-Box重启自动更新或添加G-Box自定义挂载必须打开此功能！！"
        echo -e "${Red}打开此功能会获取所有容器操作权限，有一定安全风险，确保您有良好的风险防范意识和妥当操作能力，否则不要打开此功能！！！"
        echo -e "如您已打开此功能想要关闭，请重新安装G-Box，重新进行此项选择！${NC}"
        read -erp "$(WARN "是否继续开启docker容器管理功能？（y/n）")" open_sock
    fi

    docker rm -f ${docker_name}
    docker rmi ailg/g-box:hostmode
    INFO "正在为您拉取G-Box临时镜像……"
    if docker_pull "ailg/g-box:${gb_version_tag}" &> /dev/null; then
        INFO "G-Box镜像更新成功，正在为您安装/更新G-Box容器……"
        docker tag "ailg/g-box:${gb_version_tag}" ailg/g-box:hostmode
    else
        ERROR "G-Box镜像更新失败，程序退出！"
        exit 1
    fi

    if [[ $open_sock == [Yy] ]]; then
        docker run -d --name="${docker_name}" --net=host \
            -v "$config_dir":/data \
            -v "$config_dir/data":/www/data \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --restart=always \
            ailg/g-box:hostmode
    else
        docker run -d --name="${docker_name}" --net=host \
            -v "$config_dir":/data \
            -v "$config_dir/data":/www/data \
            --restart=always \
            ailg/g-box:hostmode
    fi

    [ $? -eq 0 ] && INFO "G-Box容器用临时镜像成功安装/更新，但下次重启仍会更新标准版镜像，可关闭重启自动更新功能，确认网络可正常更新后再打开！" || ERROR "G-Box容器安装/更新失败，程序退出！"
}

logo() {
    cat << 'LOGO' | echo -e "$(cat -)"

\033[1;32m—————————————————————————————————— \033[1;31mA I \033[1;33m老 \033[1;36mG \033[1;32m———————————————————————————————————————\033[0m

       $$$$$$\          $$$$$$$\   $$$$$$\  $$\   $$\ 
      $$  __$$\         $$  __$$\ $$  __$$\ $$ |  $$ |
      $$ /  \__|        $$ |  $$ |$$ /  $$ |\$$\ $$  |
      $$ |$$$$\ $$$$$$\ $$$$$$$\ |$$ |  $$ | \$$$$  / 
      $$ |\_$$ |\______|$$  __$$\ $$ |  $$ | $$  $$<  
      $$ |  $$ |        $$ |  $$ |$$ |  $$ |$$  /\$$\ 
      \$$$$$$  |        $$$$$$$  | $$$$$$  |$$ /  $$ |
       \______/         \_______/  \______/ \__|  \__|

\033[1;32m———————————————————————————————————————————————————————————————————————————————————\033[0m
# Copyright (c) 2025 AI老G <\033[1;36mhttps://space.bilibili.com/252166818\033[0m>
# 作者很菜，无法经常更新，不保证适用每个人的环境，请勿用于商业用途；
# 如果您喜欢这个脚本，可以请我喝咖啡：\033[1;36mhttps://ailg.ggbond.org/3q.jpg\033[0m
LOGO
}

main_menu() {
    clear
    st_gbox=$(setup_status "$(docker ps -a | grep -E 'ailg/g-box' | awk '{print $NF}' | head -n1)")
    st_jf=$(setup_status "$(docker ps -a --format '{{.Names}}' | grep 'jellyfin_xy')")
    st_emby=$(setup_status "$(docker inspect --format '{{ range .Mounts }}{{ println .Source .Destination }}{{ end }}' emby |
        grep -qE "/xiaoya$ /media\b|\.img /media\.img" && echo 'emby')")

    logo
    echo -e "————————————————————————————————— \033[1;33m安  装  状  态\033[0m ——————————————————————————————————"
    echo -e "\e[33m\n\
G-Box：${st_gbox}      \e[33m小雅姐夫（Jellyfin）：${st_jf}      \e[33m小雅Emby：${st_emby}\n\
\e[0m\n\
———————————————————————————————————— \033[1;33mA  I  老  G\033[0m ——————————————————————————————————\n\
\033[1;35m1、安装/重装 G-Box\033[0m\n\
\n\
\033[1;35m2、安装/重装 小雅Emby/Jellyfin（老G速装版）\033[0m\n\
\n\
\033[1;35m3、安装/重装 小雅Jellyfin（非速装版）\033[0m\n\
\n\
\033[1;35mX、卸载/扩容/挂载 等周边功能\033[0m\n\
———————————————————————————————————————————————————————————————————————————————————"

    read -erp "请输入您的选择（1-3、X或q退出）：" user_select
    case $user_select in
        1) clear; user_gbox ;;
        2) clear; user_emby_fast ;;
        3) clear; user_jellyfin ;;
        [Xx]) clear; user_selecto ;;
        [Qq]) exit 0 ;;
        *)
            ERROR "输入错误，按任意键重新输入！"
            read -r -n 1
            main_menu
            return
            ;;
    esac
}


check_root
check_env

case $1 in
    "g-box")
        fuck_docker
        update_gbox
        ;;
    "update_data")
        update_data
        ;;
    "temp-gbox")
        fuck_docker
        [ -z "$2" ] && temp_gbox || temp_gbox $2
        ;;
    "3player")
        add_player
        ;;
    "xy-sync")
        xy_emby_sync
        ;;
    *)
        fuck_docker
        main_menu
        ;;
esac
