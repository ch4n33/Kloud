#!/bin/bash
# Kloud - 노드 준비 스크립트
# 사용법: sudo ./prepare-node.sh <hostname> [pi|ryzen]
#
# 모든 노드에서 실행하여 K3s 설치 전 OS를 준비한다.
# Pi 노드: SD 카드 수명 보호 설정 포함
# Ryzen 노드: NFS 서버 준비 포함

set -euo pipefail

HOSTNAME="${1:?사용법: $0 <hostname> [pi|ryzen]}"
NODE_TYPE="${2:-pi}"

echo "=== Kloud 노드 준비: ${HOSTNAME} (${NODE_TYPE}) ==="

# --- 공통 설정 ---

# 호스트네임 설정
hostnamectl set-hostname "${HOSTNAME}"
echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

# 패키지 업데이트 및 필수 패키지 설치
apt-get update
apt-get install -y \
  curl \
  nfs-common \
  open-iscsi \
  util-linux \
  apt-transport-https \
  ca-certificates \
  gnupg

# swap 비활성화
swapoff -a
sed -i '/swap/d' /etc/fstab
# dphys-swapfile이 있으면 비활성화 (Pi OS)
if systemctl is-active --quiet dphys-swapfile 2>/dev/null; then
  systemctl disable --now dphys-swapfile
  rm -f /var/swap
fi

# 필수 커널 모듈
cat > /etc/modules-load.d/k3s.conf <<EOF
br_netfilter
overlay
EOF
modprobe br_netfilter
modprobe overlay

# sysctl 설정
cat > /etc/sysctl.d/99-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# --- Pi 전용 설정 ---
if [ "${NODE_TYPE}" = "pi" ]; then
  echo "--- Pi SD 카드 수명 보호 설정 ---"

  # cgroups 활성화 (Pi OS)
  CMDLINE="/boot/firmware/cmdline.txt"
  if [ ! -f "${CMDLINE}" ]; then
    CMDLINE="/boot/cmdline.txt"
  fi
  if ! grep -q "cgroup_memory=1" "${CMDLINE}"; then
    sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' "${CMDLINE}"
    echo "cgroups 활성화됨 — 재부팅 필요"
  fi

  # log2ram 설치 — 로그를 RAM에 저장하여 SD 쓰기 최소화
  if ! command -v log2ram &>/dev/null; then
    echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" > /etc/apt/sources.list.d/azlux.list
    curl -fsSL https://azlux.fr/repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/azlux-archive-keyring.gpg
    apt-get update
    apt-get install -y log2ram
    # log2ram 크기 설정 (2GB RAM에서 40MB 할당)
    sed -i 's/^SIZE=.*$/SIZE=40M/' /etc/log2ram.conf
    echo "log2ram 설치됨 — 재부팅 후 활성화"
  fi

  # tmpfs 마운트 — /tmp, /var/tmp
  if ! grep -q "tmpfs /tmp" /etc/fstab; then
    cat >> /etc/fstab <<EOF
tmpfs /tmp     tmpfs defaults,noatime,nosuid,nodev,size=100M 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,size=50M  0 0
EOF
    mount -a 2>/dev/null || true
  fi

  # journald 설정 — 저장 크기 제한
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/sd-card.conf <<EOF
[Journal]
Storage=volatile
RuntimeMaxUse=30M
EOF
  systemctl restart systemd-journald
fi

# --- Ryzen 전용 설정 ---
if [ "${NODE_TYPE}" = "ryzen" ]; then
  echo "--- Ryzen NFS 서버 준비 ---"
  apt-get install -y nfs-kernel-server

  # NFS 공유 디렉토리 생성
  mkdir -p /srv/nfs/kloud
  chown nobody:nogroup /srv/nfs/kloud

  if ! grep -q "/srv/nfs/kloud" /etc/exports; then
    echo "/srv/nfs/kloud *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra
  fi

  systemctl enable --now nfs-kernel-server
fi

echo "=== 노드 준비 완료: ${HOSTNAME} ==="
if [ "${NODE_TYPE}" = "pi" ]; then
  echo "※ Pi 노드는 재부팅이 필요합니다: sudo reboot"
fi
