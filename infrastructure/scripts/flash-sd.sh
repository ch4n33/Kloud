#!/bin/bash
# Kloud - SD 카드 플래싱 스크립트
# 사용법: ./flash-sd.sh <hostname> [disk_device]
# 예시:   ./flash-sd.sh kloud-cp1 /dev/disk4
#
# 이 스크립트는 macOS에서 실행한다.
# rpi-imager CLI로 Raspberry Pi OS Lite 64-bit를 플래싱하고,
# firstrun.sh를 통해 headless 설정(SSH, WiFi, 사용자, 호스트네임)을 자동 구성한다.

set -euo pipefail

HOSTNAME="${1:?사용법: $0 <hostname> [/dev/diskN]}"
DISK="${2:-/dev/disk4}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREDENTIALS_FILE="${SCRIPT_DIR}/../.credentials"

# --- 자격증명 로드 ---
if [ ! -f "${CREDENTIALS_FILE}" ]; then
  echo "오류: ${CREDENTIALS_FILE} 파일이 없습니다."
  echo "infrastructure/.credentials 파일을 생성하세요."
  exit 1
fi
source "${CREDENTIALS_FILE}"

# --- rpi-imager 확인 ---
RPI_IMAGER="/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager"
if [ ! -x "${RPI_IMAGER}" ]; then
  echo "오류: rpi-imager가 설치되어 있지 않습니다."
  echo "  brew install --cask raspberry-pi-imager"
  exit 1
fi

# --- Pi OS Lite 64-bit 이미지 URL ---
# Raspberry Pi OS (64-bit) Lite, Bookworm
IMAGE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz"

# --- 디스크 확인 ---
echo "=== Kloud SD 카드 플래싱 ==="
echo "호스트네임: ${HOSTNAME}"
echo "대상 디스크: ${DISK}"
echo ""

# 디스크 정보 표시
diskutil list "${DISK}" 2>/dev/null || { echo "오류: ${DISK}를 찾을 수 없습니다."; exit 1; }
echo ""

# 안전 확인
read -p "위 디스크에 OS를 플래싱합니다. 모든 데이터가 삭제됩니다. 계속? (y/N): " confirm
if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
  echo "취소됨."
  exit 0
fi

# --- firstrun.sh 준비 ---
FIRSTRUN_TMP=$(mktemp /tmp/firstrun.XXXXXX.sh)
cp "${SCRIPT_DIR}/firstrun.sh" "${FIRSTRUN_TMP}"

# 플레이스홀더 치환
sed -i '' "s|PLACEHOLDER_HOSTNAME|${HOSTNAME}|g" "${FIRSTRUN_TMP}"
sed -i '' "s|PLACEHOLDER_PASSWORD|${PI_PASSWORD}|g" "${FIRSTRUN_TMP}"
sed -i '' "s|PLACEHOLDER_SSID|${WIFI_SSID}|g" "${FIRSTRUN_TMP}"
sed -i '' "s|PLACEHOLDER_WIFI_PASSWORD|${WIFI_PASSWORD}|g" "${FIRSTRUN_TMP}"

echo ""
echo "--- firstrun.sh 생성 완료 (${FIRSTRUN_TMP}) ---"

# --- SD 카드 언마운트 ---
echo "SD 카드 언마운트 중..."
diskutil unmountDisk "${DISK}"

# --- 플래싱 ---
echo ""
echo "=== rpi-imager CLI로 플래싱 시작 ==="
echo "이미지: ${IMAGE_URL}"
echo "대상: ${DISK}"
echo "(이미지 다운로드 + 플래싱에 시간이 걸립니다)"
echo ""

sudo "${RPI_IMAGER}" --cli \
  --first-run-script "${FIRSTRUN_TMP}" \
  --quiet \
  "${IMAGE_URL}" "${DISK}"

# --- 정리 ---
rm -f "${FIRSTRUN_TMP}"

echo ""
echo "=== 플래싱 완료 ==="
echo ""
echo "다음 단계:"
echo "  1. SD 카드를 Pi에 삽입"
echo "  2. 이더넷 케이블 연결"
echo "  3. 전원 투입 (첫 부팅에 1-2분 소요)"
echo "  4. ssh ${PI_USER}@${HOSTNAME}.local"
echo "     비밀번호: infrastructure/.credentials 파일 참조"
