# Kloud

K3s 기반 홈 클라우드 클러스터. 서비스 개발부터 배포까지 자체 인프라에서 수행한다.

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
# Mac에서 kubectl
export KUBECONFIG=~/Dev/Kloud/infrastructure/kubeconfig

# Ryzen SSH
ssh nas        # 192.168.50.18, user: ch4n33, sudo NOPASSWD

# Pi SSH
ssh kloud-pi1  # 192.168.50.167, user: pi, password: .credentials 참조
```

자격증명: `infrastructure/.credentials` (gitignore 대상)

## 아키텍처

- **K3s:** v1.34.5+k3s1
- **CNI:** Flannel (VXLAN, 기본값)
- **Ingress:** Traefik (K3s 내장, Ryzen에서 실행)
- **LoadBalancer:** servicelb 비활성화됨, MetalLB 미설치
- **스토리지:** local-path-provisioner (K3s 내장). NFS provisioner 미설치
- **모니터링:** 미설치

### 미설치 서비스 (cluster/ 매니페스트 준비됨)
- MetalLB L2 — `cluster/core/metallb/`
- cert-manager — `cluster/core/cert-manager/`
- NFS provisioner — `cluster/storage/nfs-provisioner/`
- kube-prometheus-stack — `cluster/monitoring/kube-prometheus-stack/`

## 디렉토리 구조

```
infrastructure/
  kubeconfig            # Mac용 kubeconfig (gitignore 대상)
  .credentials          # Pi 비밀번호, WiFi 정보 (gitignore 대상)
  ansible/
    inventory.yml       # 노드 IP, 역할
    ansible.cfg
    playbooks/          # 00-prepare → 01-server → 02-agents → 03-post
  scripts/
    flash-sd.sh         # Pi SD카드 OS 플래싱 (rpi-imager CLI)
    firstrun.sh         # Pi 첫 부팅 headless 설정 템플릿
    prepare-node.sh     # 노드 OS 준비 (cgroups, swap, log2ram 등)
    install-server.sh   # K3s 서버 설치
    join-agent.sh       # K3s 에이전트 조인
cluster/
  core/                 # MetalLB, cert-manager, Traefik values
  storage/              # NFS provisioner
  monitoring/           # Prometheus + Grafana
```

## 제약 사항

- Pi 노드는 2GB RAM — `resources.limits.memory` 반드시 명시
- Pi는 SD 카드 전용 — log2ram, tmpfs, journald volatile로 쓰기 최소화 권장
- 혼합 아키텍처 (arm64 + amd64) — 멀티아키텍처 이미지 필수, 미지원 시 nodeSelector로 Ryzen 지정
- 무거운 워크로드는 `nodeSelector: kloud/tier: heavy` (Ryzen)로 제한

## CI/CD 전략 (미구현)

```
[git push] → [CI: 빌드 & 테스트] → [이미지 빌드] → [레지스트리 push] → [CD: K3s 배포]
```

- CI 런너: GitHub Actions self-hosted runner (Ryzen)
- CD: 초기 kubectl apply, 이후 Flux CD (GitOps) 전환 예정
- 이미지 빌드: docker buildx (멀티아키텍처 arm64+amd64)

## Pi SD카드 플래싱

```bash
# rpi-imager CLI로 클린 설치
./infrastructure/scripts/flash-sd.sh <hostname> /dev/diskN
# 또는 수동: rpi-imager로 플래싱 후 bootfs에 ssh + userconf.txt 추가
```

주의: `userconf.txt`의 비밀번호 해시는 `openssl passwd -1`(MD5)로 생성. `$apr1$`(Apache)는 Linux에서 인식 불가.

## 컨벤션

- Kubernetes 매니페스트: `cluster/` 하위에 기능별 디렉토리
- Helm values 파일명: `values.yaml`
- 노드 레이블: `kloud/tier=light` (Pi), `kloud/tier=heavy` (Ryzen)
- 한국어 주석 사용
- Pi SSH 접속 시 sshpass 사용: `source .credentials` 후 `sshpass -p "${PI_PASSWORD}" ssh ...` (셸에서 `!` 특수문자 직접 입력 시 히스토리 확장 문제 발생)
