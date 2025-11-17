#!/bin/sh

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
    echo "  1. 创建/更新 KV 存储（存储域名、端口）"
    echo "  2. 创建/更新 Worker，从 KV 读取配置并实现反向代理"
    echo "  3. 创建路由，将 ${RULE_NAME}.${DOMAIN} 指向 Worker"
    echo "  4. 创建/更新 DNS A 记录（指向 8.8.8.8，开启代理）"
    echo "  5. 创建/更新泛域名 A 记录（指向 ${NEW_IP}，关闭代理，允许非标端口）"
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
echo "正在配置 Worker 反向代理..."
echo "公网 IP: ${NEW_IP}, 端口: ${NEW_PORT}"

# Worker 名称
WORKER_NAME="${RULE_NAME}-proxy"
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

# 更新 KV 存储的值（存储 IP、域名和端口）
echo "更新 KV 存储值..."

# 写入 IP
IP_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/ip" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data "$NEW_IP")
if echo "$IP_RESPONSE" | jq -e '.success == true' > /dev/null 2>&1; then
    echo "  ✓ IP 写入成功: ${NEW_IP}"
else
    echo "  ❌ IP 写入失败！"
    echo "  响应: $IP_RESPONSE"
    echo "  请检查 API Token 权限（需要 Account:Workers KV Storage:Edit）"
    exit 1
fi

# 写入 Domain
DOMAIN_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/domain" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data "$DOMAIN")
if echo "$DOMAIN_RESPONSE" | jq -e '.success == true' > /dev/null 2>&1; then
    echo "  ✓ Domain 写入成功: ${DOMAIN}"
else
    echo "  ⚠ Domain 写入可能失败，继续执行..."
fi

# 写入 Port
PORT_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/port" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data "$NEW_PORT")
if echo "$PORT_RESPONSE" | jq -e '.success == true' > /dev/null 2>&1; then
    echo "  ✓ Port 写入成功: ${NEW_PORT}"
else
    echo "  ⚠ Port 写入可能失败，继续执行..."
fi

# 验证 KV 值（确保值正确写入）
echo "验证 KV 存储值..."
VERIFY_IP=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/ip" \
  -H "Authorization: Bearer ${API_TOKEN}")
VERIFY_DOMAIN=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/domain" \
  -H "Authorization: Bearer ${API_TOKEN}")
VERIFY_PORT=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/port" \
  -H "Authorization: Bearer ${API_TOKEN}")

echo "KV 存储验证结果:"
if [ -n "$VERIFY_IP" ] && [ "$VERIFY_IP" != "null" ]; then
    echo "  ✓ IP: ${VERIFY_IP}"
    if [ "$VERIFY_IP" != "$NEW_IP" ]; then
        echo "    ⚠ 警告: IP 值不匹配！期望: ${NEW_IP}, 实际: ${VERIFY_IP}"
    fi
else
    echo "  ❌ IP: 未找到或为空"
fi

if [ -n "$VERIFY_DOMAIN" ] && [ "$VERIFY_DOMAIN" != "null" ]; then
    echo "  ✓ Domain: ${VERIFY_DOMAIN}"
else
    echo "  ❌ Domain: 未找到或为空"
fi

if [ -n "$VERIFY_PORT" ] && [ "$VERIFY_PORT" != "null" ]; then
    echo "  ✓ Port: ${VERIFY_PORT}"
else
    echo "  ❌ Port: 未找到或为空"
fi
echo ""

# ============================================
# 2. 创建/更新 Worker
# ============================================
echo ""
echo "步骤 2: 创建/更新 Worker..."

# Worker 代码（反向代理实现）
# 使用 Service Worker 格式（API 上传时使用 body_part: "script"）
WORKER_CODE=$(cat <<'EOF'
addEventListener('fetch', event => {
  // 确保所有异常都被捕获并返回响应
  event.respondWith(
    handleRequest(event.request).catch(error => {
      console.error('Unhandled error in handleRequest:', error);
      return new Response('Internal Server Error: ' + error.message, {
        status: 500,
        headers: { 'Content-Type': 'text/plain' }
      });
    })
  );
});

async function handleRequest(request) {
  const url = new URL(request.url);
  const pathSegments = url.pathname.split('/').filter(Boolean);
  
  // 检查路径中至少有一节（服务名）
  if (pathSegments.length === 0) {
    return new Response("Please specify a service path, for example /alist", { status: 404 });
  }
  
  // 提取服务名（第一段路径），与重定向模式逻辑一致
  const subdomain = pathSegments[0];
  // 剩余路径（第二段及之后）
  const remainingPath = pathSegments.slice(1).join('/');
  const fullPath = remainingPath ? `/${remainingPath}` : '';
  
  // 检查全局变量 CONFIG 是否存在
  if (typeof CONFIG === 'undefined') {
    console.error('CONFIG is undefined - KV namespace not bound to this worker');
    return new Response("KV namespace not bound to this worker. Please check Worker bindings in Cloudflare Dashboard.", { 
      status: 500,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  // 调试：检查 CONFIG 对象
  console.log('CONFIG type:', typeof CONFIG);
  console.log('CONFIG methods:', Object.keys(CONFIG || {}));
  
  let targetIP, targetDomain, targetPort;
  try {
    // 尝试读取 KV 值（注意：key 名称区分大小写）
    // 先尝试小写的 'ip'
    targetIP = await CONFIG.get('ip');
    // 如果小写 'ip' 不存在，尝试大写 'IP'（兼容性）
    if (!targetIP) {
      console.log('Trying uppercase IP key...');
      targetIP = await CONFIG.get('IP');
    }
    
    targetDomain = await CONFIG.get('domain');
    targetPort = await CONFIG.get('port');
    
    // 调试信息（可以在 Cloudflare Dashboard 的 Worker 日志中查看）
    console.log('KV read results:', { 
      ip: targetIP ? `found: ${targetIP.substring(0, 10)}...` : 'missing', 
      domain: targetDomain ? `found: ${targetDomain}` : 'missing', 
      port: targetPort ? `found: ${targetPort}` : 'missing' 
    });
    
    if (!targetIP || !targetDomain || !targetPort) {
      const missing = [];
      if (!targetIP) missing.push('ip');
      if (!targetDomain) missing.push('domain');
      if (!targetPort) missing.push('port');
      console.error('Missing KV values:', missing);
      return new Response(`Configuration missing in KV storage: ${missing.join(', ')}\n\nPlease run the setup script to update KV storage.\n\nCurrent values:\n- ip: ${targetIP || 'NOT FOUND'}\n- domain: ${targetDomain || 'NOT FOUND'}\n- port: ${targetPort || 'NOT FOUND'}`, { 
        status: 500,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
  } catch (e) {
    console.error('Error reading KV:', e.message, e.stack);
    return new Response(`Failed to read configuration from KV storage.\n\nError: ${e.message}\n\nPlease check:\n1. KV namespace is bound to this Worker\n2. KV values are set correctly\n3. Worker has proper permissions`, { 
      status: 500,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  // 构建目标 URL：使用域名而不是 IP（Cloudflare 不允许 Worker 直接访问 IP）
  // 使用 HTTPS（目标服务启用了 TLS）
  // 注意：使用域名访问，需要确保泛域名记录指向正确的 IP（关闭代理）
  const targetUrl = `https://${subdomain}.${targetDomain}:${targetPort}${fullPath}${url.search}`;
  
  // 创建新的请求，转发原始请求的所有信息
  // 注意：必须设置正确的 Host 头，因为目标服务器（lucky）根据 Host 头路由请求
  const headers = new Headers(request.headers);
  // 设置正确的 Host 头，让目标服务器能正确识别请求
  headers.set('Host', `${subdomain}.${targetDomain}:${targetPort}`);
  // 移除可能引起问题的 Cloudflare 特定头部
  headers.delete('CF-Connecting-IP');
  headers.delete('CF-Ray');
  headers.delete('CF-Visitor');
  headers.delete('CF-IPCountry');
  // 移除可能引起问题的其他头部
  headers.delete('X-Forwarded-Proto');
  headers.delete('X-Forwarded-For');
  
  const proxyRequest = new Request(targetUrl, {
    method: request.method,
    headers: headers,
    body: request.body,
    redirect: 'follow'
  });
  
  try {
    // 发起代理请求
    // 注意：Cloudflare Workers 的 fetch 会验证 SSL 证书
    // 如果目标服务器使用自签名证书，可能会失败
    // 但根据你的测试，直接访问是正常的，所以证书应该是有效的
    console.log('Attempting to fetch:', targetUrl);
    console.log('Request method:', request.method);
    
    // 添加超时控制（Workers 默认 30 秒，但我们可以提前处理）
    const fetchPromise = fetch(proxyRequest);
    
    // 创建一个超时 Promise（25 秒）
    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => reject(new Error('Request timeout after 25 seconds')), 25000);
    });
    
    // 使用 Promise.race 实现超时
    const response = await Promise.race([fetchPromise, timeoutPromise]);
    
    console.log('Response status:', response.status);
    
    // 检查响应是否有效
    if (!response || !response.ok) {
      console.warn('Response not OK:', response.status, response.statusText);
    }
    
    // 创建响应，复制状态码和头部
    // 注意：response.body 是一个 ReadableStream，需要正确传递
    const proxyResponse = new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers
    });
    
    return proxyResponse;
  } catch (e) {
    // 详细的错误信息，帮助调试
    console.error('Proxy error:', e.message);
    console.error('Error name:', e.name);
    console.error('Error stack:', e.stack);
    console.error('Target URL:', targetUrl);
    console.error('Target domain:', `${subdomain}.${targetDomain}`);
    console.error('Target port:', targetPort);
    
    // 提供更详细的错误信息
    let errorMessage = `Proxy error: ${e.message}`;
    if (e.name === 'TypeError' && e.message.includes('fetch')) {
      errorMessage += '\n\n可能的原因：\n';
      errorMessage += '1. 目标服务器无法访问（检查防火墙、服务是否运行）\n';
      errorMessage += '2. DNS 解析失败（检查泛域名记录 *.ailg.dpdns.org 是否正确配置）\n';
      errorMessage += '3. SSL 证书验证失败（检查证书是否有效）\n';
      errorMessage += '4. 端口被阻止（检查防火墙是否允许 Cloudflare IP 访问）';
    }
    
    return new Response(`${errorMessage}\n\nTarget URL: ${targetUrl}`, { 
      status: 502,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
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

# 验证代码文件是否正确写入（调试用）
if [ ! -s "$WORKER_CODE_FILE" ]; then
    echo "错误: Worker 代码文件为空"
    exit 1
fi

# 检查代码文件的行数（用于调试）
CODE_LINES=$(wc -l < "$WORKER_CODE_FILE")
echo "Worker 代码行数: ${CODE_LINES}"

# 检查代码中是否有明显的语法错误（检查是否有未闭合的括号等）
if ! grep -q "^}" "$WORKER_CODE_FILE"; then
    echo "警告: Worker 代码可能不完整（未找到结束的 }）"
fi

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
# 使用 --data-binary 确保文件内容完整上传，不会被 shell 解释
WORKER_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -F "metadata=${METADATA_JSON};type=application/json" \
  -F "script=@${WORKER_CODE_FILE};type=application/javascript;filename=worker.js")

# 清理临时文件
rm -f "$WORKER_CODE_FILE" "$METADATA_FILE"

# 检查 Worker 创建/更新是否成功
WORKER_SUCCESS=$(echo "$WORKER_RESPONSE" | jq -r '.success // false')
if [ "$WORKER_SUCCESS" != "true" ] && [ -n "$(echo "$WORKER_RESPONSE" | jq -r '.errors // empty')" ]; then
    echo "❌ Worker 创建/更新失败！"
    echo "$WORKER_RESPONSE" | jq '.'
    exit 1
else
    echo "✓ Worker 创建/更新成功: ${WORKER_NAME}"
    
    # 验证上传的代码是否完整（通过 API 获取 Worker 代码并检查）
    echo "验证上传的 Worker 代码..."
    UPLOADED_CODE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" 2>/dev/null)
    
    if echo "$UPLOADED_CODE" | grep -q "addEventListener"; then
        UPLOADED_LINES=$(echo "$UPLOADED_CODE" | wc -l)
        echo "  ✓ 上传的代码包含 addEventListener（代码行数: ${UPLOADED_LINES}）"
    else
        echo "  ⚠ 警告: 上传的代码可能不完整或有问题"
        echo "  代码前 200 字符: $(echo "$UPLOADED_CODE" | head -c 200)"
    fi
    
    # 验证 Worker 的 KV 绑定
    echo "验证 Worker 的 KV 绑定..."
    WORKER_DETAILS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/services/${WORKER_NAME}" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json")
    
    WORKER_BINDINGS=$(echo "$WORKER_DETAILS" | jq -r '.result.bindings[]? | select(.type == "kv_namespace") | .name // empty')
    if echo "$WORKER_BINDINGS" | grep -q "CONFIG"; then
        echo "  ✓ Worker 已正确绑定 KV namespace: CONFIG"
        BOUND_NAMESPACE_ID=$(echo "$WORKER_DETAILS" | jq -r '.result.bindings[]? | select(.type == "kv_namespace" and .name == "CONFIG") | .namespace_id // empty')
        if [ "$BOUND_NAMESPACE_ID" = "$KV_NAMESPACE_ID" ]; then
            echo "  ✓ 绑定的 KV namespace ID 正确: ${KV_NAMESPACE_ID}"
        else
            echo "  ⚠ 警告: 绑定的 KV namespace ID 不匹配!"
            echo "    期望: ${KV_NAMESPACE_ID}"
            echo "    实际: ${BOUND_NAMESPACE_ID}"
        fi
    else
        echo "  ⚠ 警告: Worker 未找到 CONFIG 绑定!"
        echo "  当前绑定: $WORKER_BINDINGS"
    fi
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
echo "反向代理逻辑: /<服务名>/<路径> -> https://<服务名>.${DOMAIN}:${NEW_PORT}/<路径>"
echo ""
echo "测试: 访问 https://${DNS_SUBDOMAIN}/alist/xxx 应该代理到 https://alist.${DOMAIN}:${NEW_PORT}/xxx"
echo ""
echo "下次更新时，只需运行此脚本即可自动更新 KV 存储和 Worker"

