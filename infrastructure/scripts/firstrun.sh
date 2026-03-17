#!/bin/bash
# Kloud - Pi 첫 부팅 설정 스크립트
# rpi-imager --first-run-script 옵션으로 전달됨
# systemd.run= 으로 실행되므로 최소한의 설정만 수행한다.
# 에러가 발생해도 계속 진행 (set -e 사용하지 않음)

# --- 사용자 설정 ---
HOSTNAME="PLACEHOLDER_HOSTNAME"
USER_NAME="pi"
USER_PASSWORD="PLACEHOLDER_PASSWORD"
WIFI_SSID="PLACEHOLDER_SSID"
WIFI_PASSWORD="PLACEHOLDER_WIFI_PASSWORD"
WIFI_COUNTRY="KR"

# --- 호스트네임 ---
echo "${HOSTNAME}" > /etc/hostname
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts || true

# --- 사용자 생성 및 비밀번호 설정 ---
# Bookworm Lite에는 기본 사용자가 없으므로 생성 필요
if ! id "${USER_NAME}" >/dev/null 2>&1; then
  useradd -m -G sudo,adm,dialout,cdrom,audio,video,plugdev,games,users,input,render,netdev,gpio,i2c,spi -s /bin/bash "${USER_NAME}" || true
fi
echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd || true

# sudoers 설정 (비밀번호 없이 sudo)
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/010_${USER_NAME}" || true
chmod 440 "/etc/sudoers.d/010_${USER_NAME}" || true

# --- SSH 활성화 ---
systemctl enable ssh || true
# start는 reboot 후 자동으로 됨

# --- WiFi 설정 (NetworkManager 설정 파일 직접 작성) ---
# nmcli가 이 시점에 동작하지 않을 수 있으므로 설정 파일을 직접 작성
mkdir -p /etc/NetworkManager/system-connections
cat > "/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection" << WIFIEOF
[connection]
id=${WIFI_SSID}
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
WIFIEOF
chmod 600 "/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection" || true

# WiFi 국가 코드 설정
iw reg set "${WIFI_COUNTRY}" 2>/dev/null || true
raspi-config nonint do_wifi_country "${WIFI_COUNTRY}" 2>/dev/null || true

# --- 타임존 ---
ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime || true
echo "Asia/Seoul" > /etc/timezone || true

# --- 정리: 자기 자신 삭제 ---
rm -f /boot/firmware/firstrun.sh 2>/dev/null || true
rm -f /boot/firstrun.sh 2>/dev/null || true

exit 0
