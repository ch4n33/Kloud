#!/bin/bash
# Kloud - K3s 에이전트(워커) 조인
# 사용법: sudo ./join-agent.sh <SERVER_IP> <TOKEN> [light|heavy]
#
# Pi #2, Pi #3, Ryzen에서 실행한다.

set -euo pipefail

SERVER_IP="${1:?사용법: $0 <SERVER_IP> <TOKEN> [light|heavy]}"
TOKEN="${2:?사용법: $0 <SERVER_IP> <TOKEN> [light|heavy]}"
TIER="${3:-light}"

echo "=== K3s 에이전트 조인: ${HOSTNAME} (tier=${TIER}) ==="

INSTALL_ARGS="agent"

# Pi 노드 (light tier): 컨테이너 로그 제한
if [ "${TIER}" = "light" ]; then
  INSTALL_ARGS="${INSTALL_ARGS} \
    --kubelet-arg=container-log-max-size=5Mi \
    --kubelet-arg=container-log-max-files=2"
fi

# 노드 레이블
INSTALL_ARGS="${INSTALL_ARGS} \
  --node-label=kloud/tier=${TIER}"

export K3S_URL="https://${SERVER_IP}:6443"
export K3S_TOKEN="${TOKEN}"

curl -sfL https://get.k3s.io | sh -s - ${INSTALL_ARGS}

echo ""
echo "=== 에이전트 조인 완료 ==="
echo "서버에서 확인: kubectl get nodes"
