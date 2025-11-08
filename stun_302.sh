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
RULE_NAME_VAR=$3  # 用于URL路径匹配的变量名
API_TOKEN=$4
DOMAIN=$5
RULE_NAME=${6:-ailg}  # 如果未提供，默认使用 ailg（用于DNS记录名和规则描述名）
TARGET_URL="http://${NEW_IP}:${NEW_PORT}"

# 检查必需参数
if [ -z "$NEW_IP" ] || [ -z "$NEW_PORT" ] || [ -z "$RULE_NAME_VAR" ] || [ -z "$API_TOKEN" ] || [ -z "$DOMAIN" ]; then
    echo "错误: 缺少必需参数"
    echo "用法: $0 <NEW_IP> <NEW_PORT> <RULE_NAME_VAR> <API_TOKEN> <DOMAIN> [RULE_NAME]"
    echo "示例: $0 1.2.3.4 5678 ailg your_token example.com ailg"
    echo "      $0 1.2.3.4 5678 custom your_token example.com custom"
    echo "      $0 1.2.3.4 5678 custom your_token example.com  # RULE_NAME 默认为 ailg"
    echo "说明: RULE_NAME_VAR 用于URL路径匹配，RULE_NAME 用于DNS记录名和规则描述名（可选，默认ailg）"
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

echo "正在为域名 ${DOMAIN} 创建 DNS A 记录和重定向规则..."

# 1. 创建或更新 DNS A 记录
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

# 2. 创建重定向规则
echo "正在创建重定向规则..."

# 获取现有的重定向规则集
ALL_RULES_JSON=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json")

# 检查规则是否已存在
EXISTING_RULE=$(echo "$ALL_RULES_JSON" | jq -r ".result.rules[] | select(.description == \"$RULE_NAME\") | .id")

# 构建匹配表达式：匹配新建的A记录域名的完整URL
# 注意：使用 starts_with 替代 matches，因为 matches 需要 Business 或 WAF Advanced 计划
MATCH_EXPRESSION="(http.host eq \"${DNS_SUBDOMAIN}\" and starts_with(http.request.uri.path, \"/${RULE_NAME_VAR}\"))"

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
    echo "匹配模式: https://${DNS_SUBDOMAIN}/${RULE_NAME_VAR}*"
    echo "重定向目标: ${TARGET_URL}"
else
    echo "错误: 重定向规则创建/更新失败"
    echo "$RESPONSE" | jq '.'
    exit 1
fi