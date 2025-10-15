#!/bin/bash

# --- 配置段 ---
# 脚本执行前，手动将专用令牌粘贴到这里
# 用完后，这个文件会被删除，令牌不会留在磁盘上
DEPLOY_TOKEN="TempPass050472d7"
REGISTRY_URL="wts.gbox.us.kg"
DOCKER_USERNAME="ailg666-temp"
IMAGE_TO_PULL="wts.gbox.us.kg/ailg666/wg-web:latest"

# 设置一个"陷阱"，无论脚本是成功结束还是中途出错退出，都会执行清理函数
trap cleanup EXIT

# --- 清理函数 ---
cleanup() {
  echo "--- 开始执行安全清理程序 ---"
  
  # 1. 登出账号
  docker logout $REGISTRY_URL 2>/dev/null
  
  # 2. 恢复 Docker 凭据文件备份
  if [ -f "/root/.docker/config.json.backup" ]; then
    mv /root/.docker/config.json.backup /root/.docker/config.json 2>/dev/null
  elif [ -f "~/.docker/config.json.backup" ]; then
    mv ~/.docker/config.json.backup ~/.docker/config.json 2>/dev/null
  fi
  
  # 3. 删除脚本自身，确保令牌不被留下
  rm -f -- "$0"
  
  echo "--- 清理完成 ---"
}

# --- 主程序 ---
echo "--- 开始部署 wg-web ---"

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
  echo "错误: Docker 未安装，请先安装 Docker"
  exit 1
fi

# 检查 Docker 服务是否运行
if ! docker info &> /dev/null; then
  echo "错误: Docker 服务未运行，请启动 Docker 服务"
  exit 1
fi

# 0. 备份现有的 Docker 凭据文件
if [ -f "/root/.docker/config.json" ]; then
  cp /root/.docker/config.json /root/.docker/config.json.backup
elif [ -f "~/.docker/config.json" ]; then
  cp ~/.docker/config.json ~/.docker/config.json.backup
fi

# 1. 使用专用令牌登录
echo "$DEPLOY_TOKEN" | docker login $REGISTRY_URL -u "$DOCKER_USERNAME" --password-stdin
if [ $? -ne 0 ]; then
  echo "登录失败！"
  exit 1
fi

# 2. 停止并删除旧容器（如果存在）
echo "正在清理旧容器..."
docker rm -f wg-web 2>/dev/null

# 3. 删除旧镜像（如果存在）
docker rmi ailg666/wg-web:latest 2>/dev/null
docker rmi $IMAGE_TO_PULL 2>/dev/null

# 4. 拉取新镜像
echo "正在拉取镜像..."
docker pull $IMAGE_TO_PULL
if [ $? -ne 0 ]; then
  echo "镜像拉取失败！"
  exit 1
fi

# 5. 创建短标签镜像
docker tag $IMAGE_TO_PULL ailg666/wg-web:latest
if [ $? -ne 0 ]; then
  echo "镜像创建失败！"
  exit 1
fi

# 6. 删除长标签镜像
docker rmi $IMAGE_TO_PULL 2>/dev/null

# 7. 检查挂载目录参数
MOUNT_DIR=""
if [ -n "$1" ]; then
  MOUNT_DIR="$1"
  
  # 检查目录是否存在
  if [ ! -d "$MOUNT_DIR" ]; then
    echo "错误: 挂载目录 $MOUNT_DIR 不存在"
    exit 1
  fi
  
  # 创建子目录
  mkdir -p "$MOUNT_DIR/configs"
  mkdir -p "$MOUNT_DIR/logs"
fi

# 8. 启动新容器
echo "正在启动 wg-web 容器..."

# 构建 docker run 命令
DOCKER_CMD="docker run -d \
  --name wg-web \
  --network host \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -e WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go \
  -e WIREGUARD_GO=/usr/bin/wireguard-go \
  --restart unless-stopped \
  -e WG_DEBUG=false \
  -e TZ=Asia/Shanghai \
  -e DEBUG_KEY=ailg666798 \
  -e NAT_CHECK=false"

# 如果有挂载目录参数，添加挂载选项
if [ -n "$MOUNT_DIR" ]; then
  DOCKER_CMD="$DOCKER_CMD \
  -v $MOUNT_DIR/configs:/etc/wireguard \
  -v $MOUNT_DIR/logs:/app/logs"
fi

# 添加镜像名称并执行
DOCKER_CMD="$DOCKER_CMD ailg666/wg-web:latest"

# 执行命令
eval $DOCKER_CMD

if [ $? -eq 0 ]; then
  echo "--- 部署成功 ---"
else
  echo "容器启动失败！"
  exit 1
fi

# 脚本正常执行完毕后，也会自动触发 trap 设置的 cleanup 函数
