# 네트워킹

## 클러스터 네트워크

- **CNI:** Flannel (VXLAN, K3s 기본값)
- **Pod CIDR:** 10.42.0.0/16
- **Service CIDR:** 10.43.0.0/16

## MetalLB

L2 모드, IP풀: `192.168.50.200-192.168.50.220`

현재 할당:
- 192.168.50.200 → Traefik (TCP 80/443) + WireGuard (UDP 51820) — IP 공유 (`allow-shared-ip`)
- 192.168.50.204 → Minecraft (TCP 25565)

## Traefik Ingress

- kube-system 네임스페이스에서 실행
- nodeSelector: `kloud/tier: heavy` (Ryzen)
- 포트: 80 (web), 443 (websecure, TLS)
- 대시보드: 활성화

## TLS (cert-manager)

- ClusterIssuer: `letsencrypt-prod`
- ACME: HTTP-01 challenge via Traefik
- 이메일: kimiegosearch@gmail.com
- Ingress에 `cert-manager.io/cluster-issuer: letsencrypt-prod` 어노테이션 추가 시 자동 인증서 발급

## DNS (Namecheap)

rche.moe 도메인을 Namecheap에서 관리.

- `*.kloud.rche.moe` → 홈 공인 IP (A 레코드)
- `blog.rche.moe` → 홈 공인 IP (A 레코드, 별도 등록 필요)

## WireGuard VPN

- **Pod:** wg-easy (kloud-vpn 네임스페이스)
- **노드:** Ryzen (nodeSelector)
- **외부 접속:** `vpn.kloud.rche.moe` (UDP 51820, MetalLB 192.168.50.200)
- **웹 UI:** `https://vpn.kloud.rche.moe` (Ingress, TLS)
- **클라이언트 IP 대역:** 10.8.0.x
- **허용 서브넷:** 192.168.50.0/24 (홈 LAN)

## Mac에서 클러스터 접근

### 방법 1: WireGuard VPN (권장)

```bash
# 1. WireGuard 연결
wg-quick up kloud  # 또는 WireGuard GUI 앱

# 2. /etc/hosts에 도메인 매핑 (최초 1회)
#    192.168.50.18 k3s.kloud.rche.moe

# 3. kubectl 사용
export KUBECONFIG=~/Dev/Kloud/infrastructure/kubeconfig-external
kubectl get nodes
k9s
```

### 방법 2: SSH 터널 (대안)

```bash
# SSH 터널 (nas-public에 LocalForward 6443 설정됨)
ssh -N nas-public &

# kubectl / k9s 사용
export KUBECONFIG=~/Dev/Kloud/infrastructure/kubeconfig
kubectl get nodes
k9s
```

`~/.ssh/config`의 `nas-public` 호스트에 `LocalForward 6443 127.0.0.1:6443`이 설정되어 있어, SSH 연결 시 자동으로 터널이 열림.

## 포트 포워딩 (홈 라우터)

| 외부 포트 | 내부 IP:포트 | 용도 |
|-----------|-------------|------|
| 80 | 192.168.50.200:80 | Traefik HTTP |
| 443 | 192.168.50.200:443 | Traefik HTTPS |
| 8022 | 192.168.50.18:22 | Ryzen SSH (nas-public) |
| 25565 | 192.168.50.204:25565 | Minecraft |
| 51820 (UDP) | 192.168.50.200:51820 | WireGuard VPN |
