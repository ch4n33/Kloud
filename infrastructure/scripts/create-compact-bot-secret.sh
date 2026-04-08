#!/bin/bash
# compact-bot Discord 토큰 시크릿 생성
# kubectl 접근 가능한 환경에서 실행 (KUBECONFIG 또는 ~/.kube/config 설정 필요)
set -euo pipefail

NS=compact-bot
SECRET_NAME=compact-bot-secret

# 토큰 입력 (입력 숨김)
read -srp "Discord Bot Token: " DISCORD_BOT_TOKEN
echo
if [[ -z "$DISCORD_BOT_TOKEN" ]]; then
  echo "Error: 토큰이 비어 있습니다" >&2
  exit 1
fi

# 허용 채널 ID (콤마 구분, 화면에 표시 OK — 비밀 아님)
read -rp "Allowed Channel IDs (콤마 구분): " ALLOWED_CHANNEL_IDS
if [[ -z "$ALLOWED_CHANNEL_IDS" ]]; then
  echo "Error: 최소 1개 채널 ID가 필요합니다" >&2
  exit 1
fi

# 네임스페이스가 없으면 생성 (있으면 무시)
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Secret 생성/갱신 (디스크에 yaml 파일 안 남김)
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NS" \
  --from-literal=DISCORD_BOT_TOKEN="$DISCORD_BOT_TOKEN" \
  --from-literal=ALLOWED_CHANNEL_IDS="$ALLOWED_CHANNEL_IDS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo
echo "✓ ${SECRET_NAME} 시크릿 생성/갱신 완료 (${NS} 네임스페이스)"
echo "  Pod이 이미 떠 있다면 재시작 필요:"
echo "    kubectl rollout restart deployment/compact-bot -n ${NS}"
