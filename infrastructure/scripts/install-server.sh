#!/bin/bash
# Kloud - K3s 서버(컨트롤 플레인) 설치
# 사용법: sudo ./install-server.sh [SERVER_IP]
#
# Ryzen 서버 (kloud-ryzen)에서 실행한다.
# 컨트롤 플레인 + 워커 겸용 (NoSchedule 없음, 32GB RAM 활용)

set -euo pipefail

SERVER_IP="${1:-$(hostname -I | awk '{print $1}')}"
K3S_VERSION="${K3S_VERSION:-}"

echo "=== K3s 서버 설치: ${SERVER_IP} ==="

# K3s 설치 옵션:
# --disable servicelb   : 내장 LB 제거 (MetalLB 사용)
# --tls-san             : API 서버 인증서에 IP 추가 (원격 kubectl용)
# --node-label          : Ryzen을 heavy tier로 레이블
# --write-kubeconfig-mode : kubeconfig 읽기 권한
# NoSchedule taint 없음 — Ryzen은 컨트롤 플레인 + 주력 워커 겸용

INSTALL_ARGS="server \
  --disable servicelb \
  --tls-san ${SERVER_IP} \
  --tls-san kloud-ryzen \
  --node-label=kloud/tier=heavy \
  --write-kubeconfig-mode 644"

if [ -n "${K3S_VERSION}" ]; then
  export INSTALL_K3S_VERSION="${K3S_VERSION}"
fi

curl -sfL https://get.k3s.io | sh -s - ${INSTALL_ARGS}

# 설치 확인
echo ""
echo "=== 설치 완료 ==="
echo "K3s 버전: $(k3s --version)"
echo ""
echo "노드 토큰 (에이전트 조인에 필요):"
cat /var/lib/rancher/k3s/server/node-token
echo ""
echo "kubeconfig 위치: /etc/rancher/k3s/k3s.yaml"
echo ""
echo "원격 접속 설정:"
echo "  scp ${USER}@${SERVER_IP}:/etc/rancher/k3s/k3s.yaml ~/.kube/kloud-config"
echo "  # k3s.yaml에서 127.0.0.1을 ${SERVER_IP}로 변경"
echo "  export KUBECONFIG=~/.kube/kloud-config"
echo "  kubectl get nodes"
