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

NEW_IP=$1
NEW_PORT=$2
TARGET_URL="http://${NEW_IP}:${NEW_PORT}"

API_TOKEN=$3
DOMAIN=$4
RULE_NAME=$5

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

ALL_RULES_JSON=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json")

DATA_TO_PUT=$(echo "$ALL_RULES_JSON" | jq -c "
  .result.rules |= map(
    if .description == \"$RULE_NAME\" then
      .action_parameters.from_value.target_url |= { \"value\": \"$TARGET_URL\" }
    else
      .
    end
  ) |
  .result.rules |= map(
    del(.id, .last_updated, .ref, .version)
  ) |
  { \"rules\": .result.rules, \"description\": .result.description }
")

RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$DATA_TO_PUT")

SUCCESS=$(echo "$RESPONSE" | jq -r '.success')

if [ "$SUCCESS" = "true" ]; then
  echo "Cloudflare重定向规则已通过 API 令牌 成功更新！新目标: ${TARGET_URL}"
else
  echo "更新失败！Cloudflare API 返回错误:"
  echo "$RESPONSE" | jq '.'
fi