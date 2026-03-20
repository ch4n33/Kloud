# Kloud

K3s 기반 홈 클라우드 클러스터. 서비스 개발부터 배포까지 자체 인프라에서 수행한다.

## 상세 문서

- [docs/deployed-services.md](docs/deployed-services.md) — 배포된 서비스 현황, 스토리지, 외부 도메인
- [docs/networking.md](docs/networking.md) — 네트워크 구성, MetalLB, TLS, DNS, SSH 터널
- [docs/ci-cd.md](docs/ci-cd.md) — GitHub Actions 파이프라인, ghcr.io, 새 앱 추가 방법
- [docs/scheduling.md](docs/scheduling.md) — 노드 레이블, 스케줄링 패턴, Descheduler

## 클러스터 현황

K3s v1.34.5+k3s1, 2노드 운영 중.

| K3s 노드명 | 하드웨어 | IP | 역할 | 상태 |
|------------|---------|-----|------|------|
| ch4n33-server | Ryzen 5625U, 32GB RAM, 2TB SSD, Ubuntu 24.04 | 192.168.50.18 | control-plane + 워커 | **Ready** |
| raspberrypi | Pi 4B 2GB, SD 카드, Debian Bookworm | 192.168.50.167 | 워커 | **Ready** |
| (kloud-pi2) | Pi 4B 2GB | — | 미배포 | — |
| (kloud-pi3) | Pi 4B 2GB | — | 미배포 | — |

## 접속

```bash
# Mac에서 kubectl (SSH 터널 필요)
ssh -N nas-public &  # LocalForward 6443 설정됨
export KUBECONFIG=~/Dev/Kloud/infrastructure/kubeconfig

# Ryzen SSH (외부)
ssh nas-public  # 121.152.143.55:8022, user: ch4n33

# Ryzen SSH (내부)
ssh nas         # 192.168.50.18, user: ch4n33, sudo NOPASSWD

# Pi SSH (Ryzen 경유)
ssh nas-public  # 후 sshpass로 pi@192.168.50.167 접속
```

자격증명: `infrastructure/.credentials` (gitignore 대상)

## 아키텍처

- **K3s:** v1.34.5+k3s1
- **CNI:** Flannel (VXLAN)
- **Ingress:** Traefik (K3s 내장, Ryzen에서 실행, LB IP: 192.168.50.200)
- **LoadBalancer:** MetalLB L2 (IP풀: 192.168.50.200-220)
- **TLS:** cert-manager + Let's Encrypt (HTTP-01)
- **스토리지:** hostPath PV (Ryzen `/home/ch4n33/server-data/`)
- **모니터링:** Prometheus + Grafana + node-exporter + cAdvisor
- **CI/CD:** GitHub Actions self-hosted runner → ghcr.io → kubectl
- **DNS:** Namecheap (rche.moe)

### 미배포 (매니페스트 준비됨)
- WireGuard (wg-easy) — `cluster/vpn/wireguard/` (DDNS 미설정)
- NFS provisioner — `cluster/storage/nfs-provisioner/`
- Descheduler — `cluster/core/descheduler/` (Pi failover rollback용)

## 디렉토리 구조

```
apps/
  sample-app/             # Go HTTP 서버 (멀티아키텍처 검증용)
  blog/                   # Hugo 블로그 (PaperMod 테마, ghcr.io/ch4n33/blog)
infrastructure/
  kubeconfig              # Mac용 (127.0.0.1:6443, SSH 터널 필요)
  kubeconfig-external     # 외부용 (공인 IP, 포트 미개방)
  .credentials            # Pi 비밀번호, WiFi 정보 (gitignore)
  ansible/                # 노드 프로비저닝 플레이북
  scripts/                # SD카드 플래싱, K3s 설치 스크립트
cluster/
  core/                   # MetalLB, cert-manager, Traefik, Descheduler
  apps/                   # sample-app, blog, minecraft
  metrics/                # Prometheus, Grafana, node-exporter, cAdvisor
  db/                     # PostgreSQL, Adminer
  ci/                     # GitHub Actions runner
  vpn/                    # WireGuard (미배포)
  storage/                # NFS provisioner (미배포)
.github/workflows/
  deploy.yml              # sample-app CI/CD
  deploy-blog.yml         # blog CI/CD
```

## 제약 사항

- Pi 노드는 2GB RAM — `resources.limits.memory` 반드시 명시
- Pi는 SD 카드 전용 — log2ram, tmpfs, journald volatile로 쓰기 최소화 권장
- 혼합 아키텍처 (arm64 + amd64) — 멀티아키텍처 이미지 필수, 미지원 시 nodeSelector로 Ryzen 지정
- 무거운 워크로드는 `nodeSelector: kloud/tier: heavy` (Ryzen)로 제한
- macOS에서 dd: `bs=1m` (소문자), `status=progress` 사용 불가
- Pi 비밀번호 해시: `openssl passwd -6` (SHA-512) 사용, `$apr1$`/`$1$` 금지

## 컨벤션

- Kubernetes 매니페스트: `cluster/` 하위에 기능별 디렉토리
- Helm values 파일명: `values.yaml`
- 노드 레이블: `kloud/tier=light` (Pi), `kloud/tier=heavy` (Ryzen)
- 한국어 주석 사용
- 멀티아키텍처 Docker 빌드: `docker buildx` + `--platform linux/amd64,linux/arm64`
- Pi SSH: Ryzen 경유, sshpass 사용 시 비밀번호는 파일로 전달 (`sshpass -f`, heredoc)
