# 노드 스케줄링

## 노드 레이블

| 노드 | 레이블 | 용도 |
|------|--------|------|
| ch4n33-server (Ryzen) | `kloud/tier=heavy` | 무거운 워크로드 |
| raspberrypi (Pi 4B) | `kloud/tier=light` | 경량 워크로드, 테스트/개발 |

## 스케줄링 패턴

### 1. Ryzen 고정 (`nodeSelector`)
무겁거나 아키텍처 제한이 있는 워크로드.
```yaml
nodeSelector:
  kloud/tier: heavy
```
사용: prometheus, grafana, postgres, minecraft, github-runner, blog (hostPath PV)

### 2. 양쪽 배포 (제한 없음)
멀티아키텍처 이미지, 가벼운 워크로드.
```yaml
# nodeSelector/affinity 없음
```
사용: sample-app, adminer, node-exporter, cadvisor

### 3. Pi 우선 + failover (`preferredDuringScheduling`)
Pi에 우선 배치하되, 다운 시 Ryzen으로 자동 이동.
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: kloud/tier
              operator: In
              values: ["light"]
```
사용: 현재 없음 (blog은 hostPath PV로 Ryzen 고정, 향후 NFS 전환 시 적용 가능)

## Descheduler (미배포)

Pi 복구 시 자동 rollback을 위해 Descheduler를 CronJob으로 배포 예정.

- `RemovePodsViolatingNodeAffinity` 전략
- 5분 간격 실행
- kloud-apps 네임스페이스 대상
- 매니페스트: `cluster/core/descheduler/`

배포: `kubectl apply -f cluster/core/descheduler/`
