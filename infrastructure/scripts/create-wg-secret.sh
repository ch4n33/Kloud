#!/bin/bash
# wg-easy 웹 UI 비밀번호 시크릿 생성 (bcrypt 해시, wg-easy v14+)
# kubectl 접근 가능한 환경에서 실행
set -euo pipefail

read -sp "wg-easy 웹 UI 비밀번호: " WG_PASSWORD
echo

# bcrypt 해시 생성
if command -v htpasswd &>/dev/null; then
  WG_HASH=$(htpasswd -nbBC 12 "" "$WG_PASSWORD" | tr -d ':\n')
elif command -v python3 &>/dev/null && python3 -c "import bcrypt" 2>/dev/null; then
  WG_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$WG_PASSWORD'.encode(), bcrypt.gensalt(rounds=12)).decode())")
else
  echo "htpasswd 또는 python3+bcrypt 필요"
  exit 1
fi

echo "bcrypt 해시 생성 완료"

kubectl create namespace kloud-vpn --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic wg-easy-secret \
  --namespace kloud-vpn \
  --from-literal=PASSWORD_HASH="$WG_HASH" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "wg-easy-secret 시크릿 생성 완료 (kloud-vpn 네임스페이스)"
