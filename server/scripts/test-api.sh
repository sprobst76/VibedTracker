#!/bin/bash
# Umfassender API Test
# Usage: ./scripts/test-api.sh

API_URL="${API_URL:-http://localhost:7842}"

echo "=== VibedTracker API Test ==="
echo "API: $API_URL"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

test_endpoint() {
    local name="$1"
    local method="$2"
    local path="$3"
    local expected="$4"
    local data="$5"
    local auth="$6"

    echo -n "Testing $name... "

    CURL_OPTS="-s -X $method"
    if [ -n "$auth" ]; then
        CURL_OPTS="$CURL_OPTS -H \"Authorization: Bearer $auth\""
    fi
    if [ -n "$data" ]; then
        CURL_OPTS="$CURL_OPTS -H \"Content-Type: application/json\" -d '$data'"
    fi

    RESP=$(eval "curl $CURL_OPTS \"$API_URL$path\"")
    HTTP_CODE=$(eval "curl -s -o /dev/null -w '%{http_code}' $CURL_OPTS \"$API_URL$path\"")

    if [ "$HTTP_CODE" = "$expected" ]; then
        echo -e "${GREEN}PASS${NC} ($HTTP_CODE)"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC} (expected $expected, got $HTTP_CODE)"
        echo "  Response: $RESP"
        ((FAILED++))
    fi
}

echo "--- Public Endpoints ---"
test_endpoint "Health Check" "GET" "/health" "200"
test_endpoint "Register (no data)" "POST" "/api/v1/auth/register" "400"
test_endpoint "Login (no data)" "POST" "/api/v1/auth/login" "400"
test_endpoint "Login (wrong creds)" "POST" "/api/v1/auth/login" "401" '{"email":"wrong@test.com","password":"wrong"}'

echo ""
echo "--- Protected Endpoints (no auth) ---"
test_endpoint "Me (no auth)" "GET" "/api/v1/me" "401"
test_endpoint "TOTP Status (no auth)" "GET" "/api/v1/totp/status" "401"
test_endpoint "Devices (no auth)" "GET" "/api/v1/devices" "401"
test_endpoint "Sync Status (no auth)" "GET" "/api/v1/sync/status" "401"

echo ""
echo "--- Admin Endpoints (no auth) ---"
test_endpoint "Admin Users (no auth)" "GET" "/api/v1/admin/users" "401"
test_endpoint "Admin Stats (no auth)" "GET" "/api/v1/admin/stats" "401"

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
