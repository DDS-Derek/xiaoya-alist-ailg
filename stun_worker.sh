#!/bin/sh

logo() {
    cat << 'LOGO' | echo -e "$(cat -)"

—————————————————————————————————— A I 老 G ———————————————————————————————————————

       $$$$$$\          $$$$$$$\   $$$$$$\  $$\   $$\ 
      $$  __$$\         $$  __$$\ $$  __$$\ $$ |  $$ |
      $$ /  \__|        $$ |  $$ |$$ /  $$ |\$$\ $$  |
      $$ |$$$$\ $$$$$$\ $$$$$$$\ |$$ |  $$ | \$$$$  / 
      $$ |\_$$ |\______|$$  __$$\ $$ |  $$ | $$  $$<  
      $$ |  $$ |        $$ |  $$ |$$ |  $$ |$$  /\$$\ 
      \$$$$$$  |        $$$$$$$  | $$$$$$  |$$ /  $$ |
       \______/         \_______/  \______/ \__|  \__|

———————————————————————————————————————————————————————————————————————————————————
# Copyright (c) 2025 AI老G <https://space.bilibili.com/252166818>
# 有问题可入群交流：TG电报：https://t.me/ailg666；加微入群：ailg_666；
# 如果您喜欢这个脚本，可以请我喝咖啡：https://ailg.ggbond.org/3q.jpg
LOGO
}

logo

# 检查并安装 jq（如果不存在）
if ! command -v jq >/dev/null 2>&1; then
    # 备份源配置文件
    cp /etc/apk/repositories /etc/apk/repositories.bak
    
    # 替换为清华镜像源
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
    
    # 执行 jq 安装
    apk add --no-cache -q jq >/dev/null 2>&1
    
    # 检查是否安装成功，失败则恢复源并中止执行
    if ! command -v jq >/dev/null 2>&1; then
        cp /etc/apk/repositories.bak /etc/apk/repositories
        echo "错误: jq 安装失败，已恢复源配置，脚本中止执行"
        exit 1
    fi
fi

# 参数处理
NEW_IP=$1
NEW_PORT=$2
API_TOKEN=$3
DOMAIN=$4
RULE_NAME=${5:-ailg}  # 如果未提供，默认使用 ailg
ACCOUNT_ID=${6:-""}   # Cloudflare Account ID（可选，会自动获取）

# 检查必需参数
if [ -z "$NEW_IP" ] || [ -z "$NEW_PORT" ] || [ -z "$API_TOKEN" ] || [ -z "$DOMAIN" ]; then
    echo "错误: 缺少必需参数"
    echo "用法: $0 <NEW_IP> <NEW_PORT> <API_TOKEN> <DOMAIN> [RULE_NAME] [ACCOUNT_ID]"
    echo "示例: $0 1.2.3.4 5678 your_token example.com ailg"
    echo "      $0 1.2.3.4 5678 your_token example.com  # RULE_NAME 默认为 ailg"
    echo ""
    echo "功能说明:"
    echo "  1. 创建/更新 KV 存储（存储 IP、端口、域名）"
    echo "  2. 创建/更新 Worker，从 KV 读取配置并实现重定向"
    echo "  3. 创建路由，将 ${RULE_NAME}.${DOMAIN} 指向 Worker"
    echo "  4. 创建/更新 DNS A 记录（指向 8.8.8.8，开启代理）"
    exit 1
fi

# 获取 Account ID（如果未提供）
if [ -z "$ACCOUNT_ID" ]; then
    echo "正在获取 Account ID..."
    ACCOUNTS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json")
    
    ACCOUNT_ID=$(echo "$ACCOUNTS_RESPONSE" | jq -r '.result[0].id')
    
    if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "null" ]; then
        echo "错误: 无法获取 Account ID"
        echo ""
        echo "API 响应:"
        echo "$ACCOUNTS_RESPONSE" | jq '.'
        echo ""
        echo "可能的原因:"
        echo "  1. API Token 权限不足（需要 Account:Read 权限）"
        echo "  2. 账户下没有可用的 Account"
        echo ""
        echo "解决方法:"
        echo "  1. 检查 API Token 权限"
        echo "  2. 手动获取 Account ID："
        echo "     - 登录 Cloudflare Dashboard"
        echo "     - 右侧边栏底部可以看到 Account ID"
        echo "  3. 或者使用命令获取（需要正确的 Token）:"
        echo "     curl -s -X GET \"https://api.cloudflare.com/client/v4/accounts\" \\"
        echo "       -H \"Authorization: Bearer \${API_TOKEN}\" | jq -r '.result[0].id'"
        echo ""
        echo "然后手动提供 Account ID:"
        echo "用法: $0 <NEW_IP> <NEW_PORT> <API_TOKEN> <DOMAIN> [RULE_NAME] <ACCOUNT_ID>"
        exit 1
    fi
fi

echo "Account ID: ${ACCOUNT_ID}"

# 获取 Zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
    echo "错误: 无法获取域名 ${DOMAIN} 的 Zone ID，请检查域名和 API Token"
    exit 1
fi

echo "Zone ID: ${ZONE_ID}"
echo "正在配置 Worker 重定向..."
echo "公网 IP: ${NEW_IP}, 端口: ${NEW_PORT}"

# Worker 名称
WORKER_NAME="${RULE_NAME}-redirect"
KV_NAMESPACE_NAME="${RULE_NAME}-config"

# ============================================
# 1. 创建/更新 KV Namespace
# ============================================
echo ""
echo "步骤 1: 创建/更新 KV Namespace..."

# 检查 KV Namespace 是否存在
KV_NAMESPACE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r ".result[] | select(.title == \"${KV_NAMESPACE_NAME}\") | .id")

if [ -z "$KV_NAMESPACE_ID" ] || [ "$KV_NAMESPACE_ID" = "null" ]; then
    echo "创建 KV Namespace: ${KV_NAMESPACE_NAME}..."
    KV_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"title\":\"${KV_NAMESPACE_NAME}\"}")
    
    KV_NAMESPACE_ID=$(echo "$KV_RESPONSE" | jq -r '.result.id')
    
    if [ -z "$KV_NAMESPACE_ID" ] || [ "$KV_NAMESPACE_ID" = "null" ]; then
        echo "错误: KV Namespace 创建失败"
        echo "$KV_RESPONSE" | jq '.'
        exit 1
    fi
    echo "KV Namespace 创建成功: ${KV_NAMESPACE_ID}"
else
    echo "KV Namespace 已存在: ${KV_NAMESPACE_ID}"
fi

# 更新 KV 存储的值
echo "更新 KV 存储值..."
curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/ip" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data "$NEW_IP" > /dev/null

curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/port" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data "$NEW_PORT" > /dev/null

curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/domain" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data "$DOMAIN" > /dev/null

echo "KV 存储更新成功: IP=${NEW_IP}, Port=${NEW_PORT}, Domain=${DOMAIN}"

# ============================================
# 2. 创建/更新 Worker
# ============================================
echo ""
echo "步骤 2: 创建/更新 Worker..."

# Worker 代码（从 KV 读取配置）
# 使用 Service Worker 格式（API 上传时使用 body_part: "script"）
WORKER_CODE=$(cat <<'EOF'
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  // 在 Service Worker 格式中，绑定(bindings)是全局变量，而不是通过 env 传入
  // 因此，直接使用 CONFIG，而不是 env.CONFIG
    const url = new URL(request.url);
    const pathSegments = url.pathname.split('/').filter(Boolean);

    if (pathSegments.length > 0) {
      const subdomain = pathSegments[0];

      // 检查全局变量 CONFIG 是否存在
      if (typeof CONFIG === 'undefined') {
        return new Response("KV namespace not bound to this worker", { status: 500 });
      }

      let targetDomain, targetPort;
      try {
        targetDomain = await CONFIG.get('domain');
        targetPort = await CONFIG.get('port');

        if (!targetDomain || !targetPort) {
          return new Response("Configuration (domain/port) not found in KV storage.", { status: 500 });
        }
      } catch (e) {
        console.error('Error reading KV:', e.message);
        return new Response("Failed to read configuration from KV storage.", { status: 500 });
      }

      // 将剩余路径和查询字符串保留并拼接到目标 URL 上
      const rest = pathSegments.slice(1).join('/');
      const restPath = rest ? '/' + rest : '';
      const search = url.search || '';
      const targetUrl = `https://${subdomain}.${targetDomain}:${targetPort}${restPath}${search}`;

      // 使用 302 临时重定向
      return Response.redirect(targetUrl, 302);
    }
  
  return new Response("Please specify a path, for example /alist", { status: 404 });
}
EOF
)

# 检查 Worker 是否存在
# 注意：使用 /workers/services/ 而不是 /workers/scripts/
# /workers/scripts/ 返回的是代码文本，/workers/services/ 返回的是 JSON
EXISTING_WORKER=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/services/${WORKER_NAME}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" 2>/dev/null | jq -r '.success // false')

# 创建临时文件存储 Worker 代码
WORKER_CODE_FILE=$(mktemp)
echo "$WORKER_CODE" > "$WORKER_CODE_FILE"

# 创建 metadata JSON（包含 KV 绑定）
# 使用 Service Worker 格式，需要指定 body_part: "script"
METADATA_JSON=$(jq -n -c \
  --arg namespace_id "$KV_NAMESPACE_ID" \
  '{
    "body_part": "script",
    "compatibility_date": "2024-01-01",
    "bindings": [
      {
        "name": "CONFIG",
        "namespace_id": $namespace_id,
        "type": "kv_namespace"
      }
    ]
  }')

METADATA_FILE=$(mktemp)
echo "$METADATA_JSON" > "$METADATA_FILE"

if [ "$EXISTING_WORKER" = "true" ]; then
    echo "Worker 已存在，正在更新..."
else
    echo "创建 Worker: ${WORKER_NAME}..."
fi

# 使用 multipart/form-data 上传 Worker 代码和 metadata
# Service Worker 格式：metadata 中指定 body_part: "script"，上传时使用 script 字段名
# 注意：PUT 到 /workers/scripts/ 可以创建或更新 Worker
WORKER_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -F "metadata=${METADATA_JSON};type=application/json" \
  -F "script=@${WORKER_CODE_FILE};type=application/javascript")

# 清理临时文件
rm -f "$WORKER_CODE_FILE" "$METADATA_FILE"

# 检查 Worker 创建/更新是否成功
WORKER_SUCCESS=$(echo "$WORKER_RESPONSE" | jq -r '.success // false')
if [ "$WORKER_SUCCESS" != "true" ] && [ -n "$(echo "$WORKER_RESPONSE" | jq -r '.errors // empty')" ]; then
    echo "警告: Worker 创建/更新可能有问题"
    echo "$WORKER_RESPONSE" | jq '.'
else
    echo "Worker 创建/更新成功: ${WORKER_NAME}"
fi

# ============================================
# 3. 创建/更新 Worker 路由
# ============================================
echo ""
echo "步骤 3: 创建/更新 Worker 路由..."

DNS_SUBDOMAIN="${RULE_NAME}.${DOMAIN}"
ROUTE_PATTERN="${DNS_SUBDOMAIN}/*"

# 检查路由是否已存在（使用 Workers Routes API）
EXISTING_ROUTE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r ".result[] | select(.pattern == \"${ROUTE_PATTERN}\") | .id // empty")

if [ -n "$EXISTING_ROUTE" ] && [ "$EXISTING_ROUTE" != "null" ]; then
    echo "路由已存在 (ID: ${EXISTING_ROUTE})，正在更新..."
    # 先删除旧路由
    curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes/${EXISTING_ROUTE}" \
      -H "Authorization: Bearer ${API_TOKEN}" > /dev/null
    # 创建新路由
    ROUTE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"pattern\":\"${ROUTE_PATTERN}\",\"script\":\"${WORKER_NAME}\"}")
else
    echo "创建路由: ${ROUTE_PATTERN} -> ${WORKER_NAME}..."
    ROUTE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"pattern\":\"${ROUTE_PATTERN}\",\"script\":\"${WORKER_NAME}\"}")
fi

ROUTE_SUCCESS=$(echo "$ROUTE_RESPONSE" | jq -r '.success // false')
if [ "$ROUTE_SUCCESS" = "true" ]; then
    echo "路由创建/更新成功: ${ROUTE_PATTERN}"
else
    echo "警告: 路由创建/更新可能有问题"
    echo "$ROUTE_RESPONSE" | jq '.'
fi

# ============================================
# 4. 创建/更新 DNS A 记录
# ============================================
echo ""
echo "步骤 4: 创建/更新 DNS A 记录..."

DNS_RECORD_NAME="$RULE_NAME"
DNS_RECORD_VALUE="8.8.8.8"

# 检查 DNS 记录是否已存在
EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${DNS_SUBDOMAIN}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -n "$EXISTING_RECORD" ] && [ "$EXISTING_RECORD" != "null" ]; then
    echo "DNS A 记录 ${DNS_SUBDOMAIN} 已存在，正在更新..."
    DNS_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${EXISTING_RECORD}" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${DNS_RECORD_VALUE}\",\"proxied\":true}")
else
    echo "正在创建 DNS A 记录 ${DNS_SUBDOMAIN}..."
    DNS_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${DNS_RECORD_VALUE}\",\"proxied\":true}")
fi

DNS_SUCCESS=$(echo "$DNS_RESPONSE" | jq -r '.success')
if [ "$DNS_SUCCESS" = "true" ]; then
    echo "DNS A 记录创建/更新成功: ${DNS_SUBDOMAIN} -> ${DNS_RECORD_VALUE} (已开启代理)"
else
    echo "错误: DNS A 记录创建/更新失败"
    echo "$DNS_RESPONSE" | jq '.'
    exit 1
fi

# ============================================
# 5. 创建/更新泛域名 A 记录（关闭代理，允许非标端口）
# ============================================
echo ""
echo "步骤 5: 创建/更新泛域名 A 记录..."

# 检查泛域名记录是否存在
WILDCARD_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=*.${DOMAIN}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -n "$WILDCARD_RECORD" ] && [ "$WILDCARD_RECORD" != "null" ]; then
    echo "泛域名 A 记录 *.${DOMAIN} 已存在，正在更新..."
    WILDCARD_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${WILDCARD_RECORD}" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"*\",\"content\":\"${NEW_IP}\",\"proxied\":false}")
else
    echo "正在创建泛域名 A 记录 *.${DOMAIN}..."
    WILDCARD_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"*\",\"content\":\"${NEW_IP}\",\"proxied\":false}")
fi

WILDCARD_SUCCESS=$(echo "$WILDCARD_RESPONSE" | jq -r '.success')
if [ "$WILDCARD_SUCCESS" != "true" ]; then
    echo "警告: 泛域名 A 记录创建/更新失败，但继续执行..."
    echo "$WILDCARD_RESPONSE" | jq '.'
else
    echo "泛域名 A 记录创建/更新成功: *.${DOMAIN} -> ${NEW_IP} (已关闭代理)"
fi

# ============================================
# 完成
# ============================================
echo ""
echo "=========================================="
echo "配置完成！"
echo "=========================================="
echo "Worker 名称: ${WORKER_NAME}"
echo "KV Namespace: ${KV_NAMESPACE_NAME} (ID: ${KV_NAMESPACE_ID})"
echo "路由: https://${DNS_SUBDOMAIN}/*"
echo "重定向逻辑: /<服务名> -> https://<服务名>.${DOMAIN}:${NEW_PORT}"
echo ""
echo "测试: 访问 https://${DNS_SUBDOMAIN}/alist 应该重定向到 https://alist.${DOMAIN}:${NEW_PORT}"
echo ""
echo "下次更新时，只需运行此脚本即可自动更新 KV 存储和 Worker"

