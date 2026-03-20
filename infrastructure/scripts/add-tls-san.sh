#!/bin/bash
# K3s API 서버 인증서에 TLS SAN 추가
# Ryzen 서버에서 sudo로 실행: sudo ./add-tls-san.sh
set -euo pipefail

CONFIG_FILE="/etc/rancher/k3s/config.yaml"
CERT_FILE="/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt"
KEY_FILE="/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.key"
NEW_SAN="k3s.kloud.rche.moe"

echo "=== K3s TLS SAN 추가: ${NEW_SAN} ==="

# 기존 config.yaml 백업
if [ -f "${CONFIG_FILE}" ]; then
  cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
  echo "기존 설정 백업: ${CONFIG_FILE}.bak"
fi

# config.yaml 작성 (기존 설치 옵션 포함)
cat > "${CONFIG_FILE}" <<'EOF'
tls-san:
  - 192.168.50.18
  - kloud-ryzen
  - k3s.kloud.rche.moe
disable:
  - servicelb
node-label:
  - kloud/tier=heavy
write-kubeconfig-mode: "0644"
EOF

echo "config.yaml 업데이트 완료"

# 기존 serving 인증서 삭제 (재시작 시 새 SAN으로 재생성)
if [ -f "${CERT_FILE}" ]; then
  rm -f "${CERT_FILE}" "${KEY_FILE}"
  echo "기존 serving 인증서 삭제"
fi

# K3s 재시작
echo "K3s 재시작 중..."
systemctl restart k3s

# 재시작 대기
echo "K3s 안정화 대기 (10초)..."
sleep 10

# 새 인증서 SAN 확인
echo ""
echo "=== 새 인증서 SAN 확인 ==="
openssl x509 -in "${CERT_FILE}" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" || {
  echo "인증서 확인 실패 — K3s 재시작이 완료되지 않았을 수 있음"
  echo "수동 확인: openssl x509 -in ${CERT_FILE} -noout -text | grep -A1 'Subject Alternative Name'"
  exit 1
}

echo ""
echo "=== 완료 ==="
echo "kubeconfig-external에서 server: https://k3s.kloud.rche.moe:6443 으로 접근 가능"
