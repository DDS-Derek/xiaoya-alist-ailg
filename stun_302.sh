#!/bin/sh

apk add --no-cache -q jq >/dev/null 2>&1

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