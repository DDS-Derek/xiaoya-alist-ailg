#!/bin/sh

# --- 从Lucky接收参数 ---
# 为了方便调试，您可以先手动设置这些变量
# NEW_IP="1.2.3.4"
# NEW_PORT="5678"
NEW_IP=$1
NEW_PORT=$2
TARGET_URL="http://${NEW_IP}:${NEW_PORT}"

# --- Cloudflare 配置 (使用作用域有限的 API 令牌) ---
# 您为Lucky创建的、拥有正确权限的API令牌
API_TOKEN=$3
ZONE_ID=$4
RULE_NAME=$5

# --- 1. 获取所有重定向规则 ---
# 注意：认证方式已改回 Bearer Token
ALL_RULES_JSON=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json")

# --- 2. 构建要发送的新的规则列表 ---
# 这部分逻辑与成功版本完全相同
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

# --- 3. 使用 PUT 方法更新整个规则集 ---
# 注意：认证方式已改回 Bearer Token
RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$DATA_TO_PUT")

# --- 4. 检查并输出结果 ---
SUCCESS=$(echo "$RESPONSE" | jq -r '.success')

if [ "$SUCCESS" = "true" ]; then
  echo "Cloudflare重定向规则已通过 API 令牌 成功更新！新目标: ${TARGET_URL}"
else
  echo "更新失败！Cloudflare API 返回错误:"
  echo "$RESPONSE" | jq '.'
fi