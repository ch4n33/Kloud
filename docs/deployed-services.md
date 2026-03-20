# 배포된 서비스 현황

2026-03-20 기준 클러스터에 실제 배포된 리소스 목록.

## 네임스페이스별 배포 현황

### kloud-apps

| 서비스 | 이미지 | 노드 | Ingress | 비고 |
|--------|--------|------|---------|------|
| blog | hugomods/hugo:latest | Ryzen (nodeSelector, hostPath PV) | blog.rche.moe (TLS) | Hugo server, PaperMod 테마 |
| sample-app | ghcr.io/ch4n33/sample-app:latest | 양쪽 (replicas: 2) | app.kloud.rche.moe (TLS) | Go HTTP 서버, 멀티아키텍처 검증용 |
| minecraft | itzg/minecraft-server | Ryzen (nodeSelector) | 없음 (LoadBalancer 25565) | PAPER 서버, on-demand (replicas: 0~1) |

### kloud-metrics

| 서비스 | 이미지 | 노드 | Ingress |
|--------|--------|------|---------|
| prometheus | prom/prometheus:latest | Ryzen (nodeSelector) | 없음 |
| grafana | grafana/grafana:latest | Ryzen (nodeSelector) | grafana.kloud.rche.moe (TLS) |
| node-exporter | prom/node-exporter:latest | 전체 (DaemonSet) | 없음 |
| cadvisor | gcr.io/cadvisor/cadvisor:latest | 전체 (DaemonSet) | 없음 |

### kloud-db

| 서비스 | 이미지 | 노드 | Ingress |
|--------|--------|------|---------|
| postgres | postgres:16 | Ryzen (nodeSelector) | 없음 |
| adminer | adminer:latest | 양쪽 | 없음 |

### kloud-ci

| 서비스 | 이미지 | 노드 | 비고 |
|--------|--------|------|------|
| github-runner | myoung34/github-runner:latest | Ryzen | self-hosted, 라벨: kloud,self-hosted,linux,amd64 |

### 인프라 (별도 네임스페이스)

| 네임스페이스 | 서비스 | 상태 |
|-------------|--------|------|
| kube-system | Traefik | LoadBalancer 192.168.50.200 (80, 443) |
| metallb-system | MetalLB | L2 모드, IP풀 192.168.50.200-220 |
| cert-manager | cert-manager | letsencrypt-prod ClusterIssuer (HTTP-01) |

### 미배포 (매니페스트만 존재)

| 서비스 | 매니페스트 위치 | 사유 |
|--------|----------------|------|
| WireGuard (wg-easy) | cluster/vpn/wireguard/ | DDNS 미설정 (WG_HOST: TODO) |
| NFS provisioner | cluster/storage/nfs-provisioner/ | NFS 서버 미구성 |
| Descheduler | cluster/core/descheduler/ | 배포 예정 (Pi failover rollback용) |

## 스토리지 (hostPath PV)

모든 PV는 Ryzen `/home/ch4n33/server-data/` 하위에 위치.

| PV | 용량 | 경로 |
|----|------|------|
| grafana-pv | 1Gi | /home/ch4n33/server-data/grafana |
| prometheus-pv | 5Gi | /home/ch4n33/server-data/prometheus |
| postgres-pv | 10Gi | /home/ch4n33/server-data/postgresql/data |
| minecraft-data-pv | 20Gi | /home/ch4n33/server-data/minecraft-server/data |
| minecraft-plugins-pv | 2Gi | /home/ch4n33/server-data/minecraft-server/plugins |
| blog-pv | 1Gi | /home/ch4n33/server-data/blog |
| wireguard-pv | 100Mi | /home/ch4n33/server-data/wireguard (미사용) |

## 외부 접근 (Ingress 도메인)

| 도메인 | 서비스 | TLS | DNS |
|--------|--------|-----|-----|
| blog.rche.moe | blog | cert-manager | Namecheap A 레코드 필요 |
| app.kloud.rche.moe | sample-app | cert-manager | *.kloud.rche.moe |
| grafana.kloud.rche.moe | grafana | cert-manager | *.kloud.rche.moe |
