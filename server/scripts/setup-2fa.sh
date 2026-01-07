#!/bin/bash
# Setup 2FA für einen User
# Usage: ./scripts/setup-2fa.sh [email] [password]

API_URL="${API_URL:-http://localhost:7842}"
EMAIL="${1:-2fa-test@example.com}"
PASSWORD="${2:-TestPass123}"

echo "=== VibedTracker 2FA Setup ==="
echo "API: $API_URL"
echo "User: $EMAIL"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Login (ohne TOTP)
echo -n "1. Login... "
LOGIN_RESP=$(curl -s -X POST "$API_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"device_name\":\"Setup\",\"device_type\":\"web\"}")

if echo "$LOGIN_RESP" | grep -q '"requires_totp":true'; then
    echo -e "${YELLOW}TOTP already enabled!${NC}"
    echo "Use test-2fa.sh to test the login flow."
    exit 0
fi

if ! echo "$LOGIN_RESP" | grep -q '"access_token"'; then
    echo -e "${RED}FAILED${NC}"
    echo "Response: $LOGIN_RESP"
    exit 1
fi

ACCESS_TOKEN=$(echo "$LOGIN_RESP" | sed 's/.*"access_token":"//' | sed 's/".*//')
echo -e "${GREEN}OK${NC}"

# 2. TOTP Status
echo -n "2. TOTP Status... "
STATUS_RESP=$(curl -s "$API_URL/api/v1/totp/status" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$STATUS_RESP"

# 3. Setup TOTP
echo -n "3. Setup TOTP... "
SETUP_RESP=$(curl -s -X POST "$API_URL/api/v1/totp/setup" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

if ! echo "$SETUP_RESP" | grep -q '"secret"'; then
    echo -e "${RED}FAILED${NC}"
    echo "Response: $SETUP_RESP"
    exit 1
fi

SECRET=$(echo "$SETUP_RESP" | sed 's/.*"secret":"//' | sed 's/".*//')
QR_URL=$(echo "$SETUP_RESP" | sed 's/.*"qr_code_url":"//' | sed 's/".*//')
echo -e "${GREEN}OK${NC}"

echo ""
echo -e "${CYAN}=== TOTP Secret ===${NC}"
echo -e "Secret: ${YELLOW}$SECRET${NC}"
echo ""
echo "QR Code URL:"
echo "$QR_URL"
echo ""

# 4. Generate and verify TOTP
echo -n "4. Generating TOTP code... "
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

# 5. Verify TOTP (aktiviert 2FA)
echo -n "5. Verifying TOTP (activates 2FA)... "
VERIFY_RESP=$(curl -s -X POST "$API_URL/api/v1/totp/verify" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"code\":\"$TOTP_CODE\"}")

if echo "$VERIFY_RESP" | grep -q '"recovery_codes"'; then
    echo -e "${GREEN}SUCCESS${NC}"
    echo ""
    echo -e "${CYAN}=== Recovery Codes ===${NC}"
    echo -e "${YELLOW}WICHTIG: Diese Codes sicher aufbewahren!${NC}"
    echo "$VERIFY_RESP" | python3 -c "import sys,json;codes=json.load(sys.stdin).get('recovery_codes',[]);print('\n'.join(codes))"
    echo ""
    echo -e "${GREEN}=== 2FA Setup Complete ===${NC}"
    echo ""
    echo "Secret für Test-Skript:"
    echo "export TOTP_SECRET='$SECRET'"
else
    echo -e "${RED}FAILED${NC}"
    echo "Response: $VERIFY_RESP"
fi
