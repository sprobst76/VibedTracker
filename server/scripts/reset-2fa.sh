#!/bin/bash
# Reset 2FA für einen User (direkt in DB)
# Usage: ./scripts/reset-2fa.sh [email]

EMAIL="${1:-2fa-test@example.com}"

echo "=== VibedTracker 2FA Reset ==="
echo "User: $EMAIL"
echo ""

read -p "Wirklich 2FA für $EMAIL deaktivieren? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Abgebrochen."
    exit 0
fi

# Via Docker in DB
docker compose -f server/docker-compose.prod.yml exec -T db psql -U vibedtracker << EOF
UPDATE users SET totp_enabled = false, totp_secret = NULL, totp_verified_at = NULL WHERE email = '$EMAIL';
DELETE FROM recovery_codes WHERE user_id = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM totp_attempts WHERE user_id = (SELECT id FROM users WHERE email = '$EMAIL');
EOF

echo ""
echo "2FA für $EMAIL wurde deaktiviert."
echo ""

# Status anzeigen
docker compose -f server/docker-compose.prod.yml exec -T db psql -U vibedtracker -c \
    "SELECT email, totp_enabled, totp_secret IS NOT NULL as has_secret FROM users WHERE email = '$EMAIL';"
