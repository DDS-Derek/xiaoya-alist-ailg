#!/bin/bash
DEFAULT_REGISTRY_URLS=('https://hub.rat.dev' 'https://nas.dockerimages.us.kg' 'https://dockerhub.ggbox.us.kg')
REGISTRY_URLS=("${DEFAULT_REGISTRY_URLS[@]}")

DOCKER_CONFIG_FILE=''
BACKUP_FILE=''

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

REQUIRED_COMMANDS=('docker' 'awk' 'jq' 'grep' 'cp' 'mv' 'kill')
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command_exists "$cmd"; then
        echo "缺少命令: $cmd，请安装后再运行脚本。"
        exit 1
    fi
done

docker_pid() {
    if [ -f /var/run/docker.pid ]; then
        kill -SIGHUP $(cat /var/run/docker.pid)
    elif [ -f /var/run/dockerd.pid ]; then
        kill -SIGHUP $(cat /var/run/dockerd.pid)
    else
        echo "Docker进程不存在，脚本中止执行。"
        cp $BACKUP_FILE $DOCKER_CONFIG_FILE
        echo "已恢复原配置文件。"
        exit 1
    fi 
}

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
else
    DOCKER_CONFIG_FILE='/etc/docker/daemon.json'
fi

if [ ! -f $DOCKER_CONFIG_FILE ]; then
    echo "配置文件 $DOCKER_CONFIG_FILE 不存在，脚本中止执行。"
    exit 1
fi

BACKUP_FILE="${DOCKER_CONFIG_FILE}.bak"
cp $DOCKER_CONFIG_FILE $BACKUP_FILE

# if grep -q '"registry-mirrors"' $DOCKER_CONFIG_FILE; then
#     awk -v urls="$REGISTRY_URLS_JSON" '{gsub(/"registry-mirrors":\[[^]]*\]/, "\"registry-mirrors\":" urls)}1' $DOCKER_CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $DOCKER_CONFIG_FILE
# else
#     awk -v urls="$REGISTRY_URLS_JSON" 'BEGIN {FS=OFS="{"} NR==1 {$2="\n  \"registry-mirrors\": " urls ", " $2} 1' $DOCKER_CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $DOCKER_CONFIG_FILE
# fi
jq --argjson urls "$REGISTRY_URLS_JSON" '
    if has("registry-mirrors") then
        .["registry-mirrors"] = $urls
    else
        . + {"registry-mirrors": $urls}
    end
' $DOCKER_CONFIG_FILE > tmp.$$.json && mv tmp.$$.json $DOCKER_CONFIG_FILE
if [ "$REGISTRY_URLS_JSON" == '[]' ]; then
    echo -e "\033[1;33m已清空镜像代理，不再检测docker连接性，直接退出！\033[0m"
    docker_pid
    exit 0
fi

docker_pid

docker rmi hello-world:latest >/dev/null 2>&1
if docker pull hello-world; then
    echo -e "\033[1;32mNice！Docker下载测试成功，配置更新完成！\033[0m"
else
    echo -e "\033[1;31m哎哟！Docker测试下载失败，恢复原配置文件...\033[0m"
    cp $BACKUP_FILE $DOCKER_CONFIG_FILE
    docker_pid
    echo -e "\033[1;31m已恢复原配置文件！\033[0m"
fi