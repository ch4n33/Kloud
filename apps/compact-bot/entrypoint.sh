#!/bin/bash
set -eu

# 필수 환경변수 검증 — 누락 시 즉시 실패하여 CrashLoopBackOff로 가시화
: "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN required}"
: "${ALLOWED_CHANNEL_IDS:?ALLOWED_CHANNEL_IDS required}"

# 영속 디렉토리 보장 (state PV가 비어 있을 수 있음)
mkdir -p /claude-home/.claude /claude-home/.local/bin /claude-home/.config/compact-bot /opt/cli/bin

# in-cluster ServiceAccount 토큰 기반 kubeconfig 생성
# tokenFile 참조 방식이라 K8s가 자동으로 토큰을 회전해도 즉시 반영됨
SA=/var/run/secrets/kubernetes.io/serviceaccount
if [ -r "$SA/token" ]; then
  mkdir -p /claude-home/.kube
  CA_B64=$(base64 -w0 < "$SA/ca.crt")
  NS=$(cat "$SA/namespace")
  cat > /claude-home/.kube/config <<EOF
apiVersion: v1
kind: Config
clusters:
- name: kloud
  cluster:
    server: https://kubernetes.default.svc
    certificate-authority-data: ${CA_B64}
users:
- name: compact-bot
  user:
    tokenFile: ${SA}/token
contexts:
- name: kloud
  context:
    cluster: kloud
    user: compact-bot
    namespace: ${NS}
current-context: kloud
EOF
  chmod 600 /claude-home/.kube/config
  echo "[entrypoint] kubeconfig 생성 완료 (ns=${NS})"
fi

# compact-bot은 환경변수(DISCORD_BOT_TOKEN, ALLOWED_CHANNEL_IDS)만으로 부팅 가능
# init 단계는 stdin 토큰 입력을 요구하므로 자동화 환경에서 부적합 → 건너뜀

export DEFAULT_CWD="${DEFAULT_CWD:-/workspace}"
export CLAUDE_PATH="${CLAUDE_PATH:-/usr/local/bin/claude}"
export KUBECONFIG="${KUBECONFIG:-/claude-home/.kube/config}"

cd /app
exec npx --yes @serin511/compact-bot
