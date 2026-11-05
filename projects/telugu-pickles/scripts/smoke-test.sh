#!/usr/bin/env bash
# End-to-end smoke test through the FRONTEND (nginx -> gateway -> services).
#   ./scripts/smoke-test.sh                       # local docker compose
#   ./scripts/smoke-test.sh http://<elb-host>     # EKS
set -uo pipefail
BASE="${1:-http://localhost:3000}"
PASS=0; FAIL=0
# Use local Node if installed, otherwise the Node inside the running gateway container
# (so students only need Docker + Git Bash).
if command -v node >/dev/null 2>&1; then NODE=(node); else NODE=(docker exec -i tp-gateway node); fi
json() { "${NODE[@]}" -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const o=JSON.parse(d);console.log(eval('o'+process.argv[1]))}catch(e){console.log('')}})" "$1"; }
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "Smoke testing $BASE"
check "storefront HTML served"            "$(code "$BASE/")" 200
check "SPA deep link falls back to index" "$(code "$BASE/pickles/avakaya")" 200
check "frontend /healthz"                 "$(code "$BASE/healthz")" 200
check "aggregated API health"             "$(code "$BASE/api/health")" 200

VEG=$(curl -s "$BASE/api/products?category=veg" | json .count)
NONVEG=$(curl -s "$BASE/api/products?category=non-veg" | json .count)
echo "  info  catalogue: $VEG veg, $NONVEG non-veg pickles"
check "veg catalogue not empty"           "$([ "${VEG:-0}" -gt 0 ] && echo yes)" yes
check "non-veg catalogue not empty"       "$([ "${NONVEG:-0}" -gt 0 ] && echo yes)" yes
check "/categories not shadowed by /:slug" "$(curl -s "$BASE/api/categories" | json '.categories.length')" 2
check "product detail"                    "$(curl -s "$BASE/api/products/gongura" | json .product.name)" "Gongura Pachadi"
check "search works"                      "$( [ "$(curl -s "$BASE/api/products?q=prawn" | json .count)" -ge 2 ] && echo yes)" yes
check "unknown product -> 404"            "$(code "$BASE/api/products/not-a-pickle")" 404

# security boundaries
check "cart requires login"               "$(code "$BASE/api/cart")" 401
check "internal stock API not exposed"    "$(code -X POST "$BASE/api/internal/stock/reserve")" 404
check "payment-service not exposed"       "$(code -X POST "$BASE/api/payments")" 404
check "bad login rejected"                "$(code -X POST -H 'Content-Type: application/json' -d '{"email":"demo@telugupickles.in","password":"wrong"}' "$BASE/api/auth/login")" 401

# shopper journey
EMAIL="smoke$(date +%s)$RANDOM@telugupickles.in"
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' -d "{\"name\":\"Smoke Tester\",\"email\":\"$EMAIL\",\"password\":\"Pickle@123\"}" "$BASE/api/auth/register" | json .token)
check "register returns JWT"              "$([ -n "$TOKEN" ] && echo yes)" yes
AUTH=(-H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json')
check "me"                                "$(curl -s "${AUTH[@]}" "$BASE/api/auth/me" | json .user.email)" "$EMAIL"
check "add avakaya 1kg x2"                "$(code -X POST "${AUTH[@]}" -d '{"slug":"avakaya","weight":"1kg","qty":2}' "$BASE/api/cart/items")" 201
check "add gongura mutton 500g"           "$(code -X POST "${AUTH[@]}" -d '{"slug":"gongura-mutton","weight":"500g","qty":1}' "$BASE/api/cart/items")" 201
check "invalid pack size rejected"        "$(code -X POST "${AUTH[@]}" -d '{"slug":"avakaya","weight":"5kg","qty":1}' "$BASE/api/cart/items")" 400
CART_TOTAL=$(curl -s "${AUTH[@]}" "$BASE/api/cart" | json .total)
check "cart total priced by server"       "$CART_TOTAL" $((663*2 + 949))

ADDR='{"fullName":"Smoke Tester","phone":"9876543210","line1":"1-2-3 Ameerpet","city":"Hyderabad","state":"Telangana","pincode":"500016"}'
ORDER=$(curl -s -X POST "${AUTH[@]}" -d "{\"paymentMethod\":\"UPI\",\"address\":$ADDR}" "$BASE/api/orders")
ORDER_ID=$(echo "$ORDER" | json .order.id)
check "order placed + paid (UPI)"         "$(echo "$ORDER" | json .order.status)" CONFIRMED
check "cart emptied after order"          "$(curl -s "${AUTH[@]}" "$BASE/api/cart" | json '.items.length')" 0
check "order in history"                  "$(curl -s "${AUTH[@]}" "$BASE/api/orders" | json '.orders.length')" 1
check "cancel order"                      "$(curl -s -X POST "${AUTH[@]}" "$BASE/api/orders/$ORDER_ID/cancel" | json .order.status)" CANCELLED
check "empty cart checkout rejected"      "$(code -X POST "${AUTH[@]}" -d "{\"paymentMethod\":\"COD\",\"address\":$ADDR}" "$BASE/api/orders")" 400

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
