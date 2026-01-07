#!/bin/bash
# Test-Skript für 2FA Flow
# Usage: ./scripts/test-2fa.sh

API_URL="${API_URL:-http://localhost:7842}"
TEST_EMAIL="2fa-test@example.com"
TEST_PASSWORD="TestPass123"

echo "=== VibedTracker 2FA Test ==="
echo "API: $API_URL"
echo ""

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Health Check
echo -n "1. Health Check... "
HEALTH=$(curl -s "$API_URL/health")
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "$HEALTH"
    exit 1
fi

# 2. Login
echo -n "2. Login... "
LOGIN_RESP=$(curl -s -X POST "$API_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\",\"device_name\":\"Test\",\"device_type\":\"web\"}")

if echo "$LOGIN_RESP" | grep -q '"requires_totp":true'; then
    echo -e "${YELLOW}TOTP Required${NC}"
    TEMP_TOKEN=$(echo "$LOGIN_RESP" | sed 's/.*"temp_token":"//' | sed 's/".*//')
    echo "   Temp Token: ${TEMP_TOKEN:0:20}..."

    # 3. Generate TOTP
    echo -n "3. Generating TOTP... "

    # Secret aus DB holen oder hardcoded verwenden
    SECRET="${TOTP_SECRET:-7P6GKE44MUO4ZICSRJYCZVZDJBTQULUZ}"

    TOTP_CODE=$(python3 << EOF
import hmac, hashlib, struct, time, base64
secret = base64.b32decode('$SECRET')
counter = int(time.time()) // 30
h = hmac.new(secret, struct.pack('>Q', counter), hashlib.sha1).digest()
offset = h[-1] & 0x0f
code = struct.unpack('>I', h[offset:offset+4])[0] & 0x7fffffff
print(f'{code % 1000000:06d}')
EOF
)
    echo -e "${GREEN}$TOTP_CODE${NC}"

    # 4. Validate TOTP
    echo -n "4. Validating TOTP... "
    VALIDATE_RESP=$(curl -s -X POST "$API_URL/api/v1/auth/totp/validate" \
        -H "Content-Type: application/json" \
        -d "{\"temp_token\":\"$TEMP_TOKEN\",\"code\":\"$TOTP_CODE\"}")

    if echo "$VALIDATE_RESP" | grep -q '"access_token"'; then
        echo -e "${GREEN}SUCCESS${NC}"
        ACCESS_TOKEN=$(echo "$VALIDATE_RESP" | sed 's/.*"access_token":"//' | sed 's/".*//')
        echo "   Access Token: ${ACCESS_TOKEN:0:30}..."
        echo ""
        echo -e "${GREEN}=== 2FA Login Flow Complete ===${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "   Response: $VALIDATE_RESP"
    fi

elif echo "$LOGIN_RESP" | grep -q '"access_token"'; then
    echo -e "${GREEN}OK (No TOTP)${NC}"
    ACCESS_TOKEN=$(echo "$LOGIN_RESP" | sed 's/.*"access_token":"//' | sed 's/".*//')
    echo "   Access Token: ${ACCESS_TOKEN:0:30}..."
else
    echo -e "${RED}FAILED${NC}"
    echo "   Response: $LOGIN_RESP"
    exit 1
fi

echo ""
echo "Done!"
