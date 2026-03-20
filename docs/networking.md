# 네트워킹

## 클러스터 네트워크

- **CNI:** Flannel (VXLAN, K3s 기본값)
- **Pod CIDR:** 10.42.0.0/16
- **Service CIDR:** 10.43.0.0/16

## MetalLB

L2 모드, IP풀: `192.168.50.200-192.168.50.220`

현재 할당:
- 192.168.50.200 → Traefik (HTTP/HTTPS)
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

## Mac에서 클러스터 접근

공인 IP의 K8s API 포트(6443)가 포워딩되지 않으므로, SSH 터널을 사용.

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
