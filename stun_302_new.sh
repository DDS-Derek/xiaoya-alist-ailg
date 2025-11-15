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
RULE_NAME=${5:-ailg}  # 如果未提供，默认使用 ailg（用于DNS记录名和规则描述名）

# 检查必需参数
if [ -z "$NEW_IP" ] || [ -z "$NEW_PORT" ] || [ -z "$API_TOKEN" ] || [ -z "$DOMAIN" ]; then
    echo "错误: 缺少必需参数"
    echo "用法: $0 <NEW_IP> <NEW_PORT> <API_TOKEN> <DOMAIN> [RULE_NAME]"
    echo "示例: $0 1.2.3.4 5678 your_token example.com ailg"
    echo "      $0 1.2.3.4 5678 your_token example.com  # RULE_NAME 默认为 ailg"
    echo ""
    echo "功能说明:"
    echo "  1. 创建/更新 ailg.${DOMAIN} 的 A 记录（指向 8.8.8.8，开启代理）"
    echo "  2. 更新 *.${DOMAIN} 的 A 记录（指向 ${NEW_IP}，关闭代理）"
    echo "  3. 创建重定向规则：访问 https://ailg.${DOMAIN}/<服务名> 时，"
    echo "     重定向到 https://<服务名>.${DOMAIN}:${NEW_PORT}"
    exit 1
fi

# 获取 Zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
    echo "错误: 无法获取域名 ${DOMAIN} 的 Zone ID，请检查域名和 API Token"
    exit 1
fi

echo "正在为域名 ${DOMAIN} 配置 DNS 记录和重定向规则..."
echo "公网 IP: ${NEW_IP}, 端口: ${NEW_PORT}"

# 1. 创建或更新 ailg.${DOMAIN} 的 A 记录（开启代理，用于接收用户请求）
DNS_RECORD_NAME="$RULE_NAME"
DNS_RECORD_VALUE="8.8.8.8"
DNS_SUBDOMAIN="${DNS_RECORD_NAME}.${DOMAIN}"

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
if [ "$DNS_SUCCESS" != "true" ]; then
    echo "错误: DNS A 记录创建/更新失败"
    echo "$DNS_RESPONSE" | jq '.'
    exit 1
fi
echo "DNS A 记录创建/更新成功: ${DNS_SUBDOMAIN} -> ${DNS_RECORD_VALUE} (已开启代理)"

# 2. 更新 *.${DOMAIN} 的 A 记录（关闭代理，允许非标端口）
echo "正在更新 *.${DOMAIN} 的通配符 A 记录..."

# 检查通配符记录是否存在
WILDCARD_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=*.${DOMAIN}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -n "$WILDCARD_RECORD" ] && [ "$WILDCARD_RECORD" != "null" ]; then
    echo "通配符 A 记录 *.${DOMAIN} 已存在，正在更新..."
    WILDCARD_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${WILDCARD_RECORD}" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"*\",\"content\":\"${NEW_IP}\",\"proxied\":false}")
else
    echo "正在创建通配符 A 记录 *.${DOMAIN}..."
    WILDCARD_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"*\",\"content\":\"${NEW_IP}\",\"proxied\":false}")
fi

WILDCARD_SUCCESS=$(echo "$WILDCARD_RESPONSE" | jq -r '.success')
if [ "$WILDCARD_SUCCESS" != "true" ]; then
    echo "警告: 通配符 A 记录创建/更新失败，但继续执行..."
    echo "$WILDCARD_RESPONSE" | jq '.'
else
    echo "通配符 A 记录创建/更新成功: *.${DOMAIN} -> ${NEW_IP} (已关闭代理)"
fi

# 3. 创建重定向规则
echo "正在创建重定向规则..."

# 获取现有的重定向规则集
ALL_RULES_JSON=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json")

# 检查规则是否已存在
EXISTING_RULE=$(echo "$ALL_RULES_JSON" | jq -r ".result.rules[] | select(.description == \"$RULE_NAME\") | .id")

# 构建匹配表达式：匹配 ailg.${DOMAIN} 的所有路径（除了根路径）
# 尝试使用正则表达式捕获路径第一段作为服务名
# 例如：/gbox -> 捕获 "gbox", /alist/xxx -> 捕获 "alist"
# 
# 重要：需要确认 Free 计划是否支持 matches 函数和捕获组
# 如果 Free 计划不支持，可能需要：
# 1. 升级到 Business 计划
# 2. 或者为每个服务创建单独的重定向规则（使用 starts_with 匹配特定路径）
MATCH_EXPRESSION="(http.host eq \"${DNS_SUBDOMAIN}\" and http.request.uri.path matches \"^/([^/]+)(/.*)?$\")"

# 构建重定向目标URL
# 从路径提取服务名，构建 https://<服务名>.${DOMAIN}:${NEW_PORT}
# 例如：用户访问 https://ailg.abc.com/gbox -> 重定向到 https://gbox.abc.com:5678
# 例如：用户访问 https://ailg.abc.com/alist/xxx -> 重定向到 https://alist.abc.com:5678/xxx
# 
# 注意：${1} 是正则表达式第一个捕获组（服务名），${2} 是第二个捕获组（剩余路径）
# Cloudflare Redirect Rules 的捕获组引用语法需要确认，可能是：
# - ${1} 或 $1 或其他格式
# - 如果创建失败，说明 Free 计划不支持，需要调整方案
TARGET_URL="https://\${1}.${DOMAIN}:${NEW_PORT}\${2}"

if [ -n "$EXISTING_RULE" ] && [ "$EXISTING_RULE" != "null" ]; then
    echo "重定向规则 ${RULE_NAME} 已存在，正在更新..."
    # 更新现有规则（使用 --arg 安全传递变量，确保设置 status_code 为 302）
    DATA_TO_PUT=$(echo "$ALL_RULES_JSON" | jq -c \
      --arg rule_name "$RULE_NAME" \
      --arg target_url "$TARGET_URL" \
      --arg expression "$MATCH_EXPRESSION" \
      '.result.rules |= map(
        if .description == $rule_name then
          .action_parameters.from_value.target_url |= { "value": $target_url } |
          .action_parameters.from_value.status_code |= 302 |
          .expression |= $expression
        else
          .
        end
      ) |
      .result.rules |= map(
        del(.id, .last_updated, .ref, .version)
      ) |
      { "rules": .result.rules, "description": .result.description }
    ')
else
    echo "正在创建新的重定向规则 ${RULE_NAME}..."
    # 创建新规则（使用 --arg 安全传递变量，明确设置 status_code 为 302）
    NEW_RULE=$(jq -n -c \
      --arg description "$RULE_NAME" \
      --arg expression "$MATCH_EXPRESSION" \
      --arg target_url "$TARGET_URL" \
      '{
        "description": $description,
        "expression": $expression,
        "action": "redirect",
        "action_parameters": {
          "from_value": {
            "target_url": {
              "value": $target_url
            },
            "status_code": 302
          }
        }
      }')
    
    DATA_TO_PUT=$(echo "$ALL_RULES_JSON" | jq -c "
      .result.rules += [$NEW_RULE] |
      .result.rules |= map(
        del(.id, .last_updated, .ref, .version)
      ) |
      { \"rules\": .result.rules, \"description\": .result.description }
    ")
fi

# 更新规则集
RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$DATA_TO_PUT")

SUCCESS=$(echo "$RESPONSE" | jq -r '.success')

if [ "$SUCCESS" = "true" ]; then
    echo "重定向规则创建/更新成功！"
    echo "规则名称: ${RULE_NAME}"
    echo "匹配模式: https://${DNS_SUBDOMAIN}/* (使用正则表达式捕获路径第一段)"
    echo "重定向目标: ${TARGET_URL}"
    echo ""
    echo "测试: 访问 https://${DNS_SUBDOMAIN}/gbox 应该重定向到 https://gbox.${DOMAIN}:${NEW_PORT}"
    echo ""
    echo "注意: 如果实际重定向不工作，可能是："
    echo "  1. Free 计划不支持 matches 函数或捕获组"
    echo "  2. 捕获组引用语法不正确（当前使用 \${1} 和 \${2}）"
    echo "  3. 需要升级到 Business 计划"
else
    echo "错误: 重定向规则创建/更新失败"
    echo ""
    echo "错误详情:"
    echo "$RESPONSE" | jq '.'
    echo ""
    echo "可能的原因:"
    echo "  1. Free 计划不支持 matches 函数（需要 Business 计划）"
    echo "  2. 捕获组引用语法不正确"
    echo "  3. API Token 权限不足"
    echo ""
    echo "如果是因为 Free 计划不支持，需要："
    echo "  - 升级到 Business 计划，或"
    echo "  - 修改脚本为每个服务创建单独的重定向规则（使用 starts_with）"
    exit 1
fi

