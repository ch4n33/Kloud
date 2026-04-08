# Spot Node Backlog — Linux 랩탑

Linux 랩탑을 K3s 클러스터의 spot instance 노드로 활용하기 위한 백로그.

## 개요

- 여분의 Linux 랩탑을 K3s agent로 조인
- 필요할 때 전원 ON (WoL), 불필요 시 전원 OFF (shutdown)
- stateless 워크로드 전용, 언제든 제거 가능한 spot 패턴

## 사전 조건

- [ ] 랩탑 하드웨어 스펙 확인 (RAM, CPU, 아키텍처)
- [ ] Linux 설치 (Ubuntu Server 권장)
- [ ] 네트워크 접근 확인 (Ryzen과 같은 LAN, 192.168.50.x)
- [ ] BIOS에서 Wake-on-LAN 활성화
- [ ] 랩탑 MAC 주소 기록

## Phase 1: K3s Agent 조인

- [ ] K3s agent 설치 및 조인
  ```bash
  curl -sfL https://get.k3s.io | K3S_URL=https://192.168.50.18:6443 \
    K3S_TOKEN=<node-token> \
    INSTALL_K3S_EXEC="agent" sh -
  ```
- [ ] `systemctl enable k3s-agent` — 부팅 시 자동 시작
- [ ] 노드 레이블 부여: `kloud/tier=spot`
- [ ] Taint 설정: `kloud/spot=true:NoSchedule`
  ```bash
  kubectl label node <laptop> kloud/tier=spot
  kubectl taint node <laptop> kloud/spot=true:NoSchedule
  ```

## Phase 2: 랩탑 OS 설정

- [ ] WoL 활성화
  ```bash
  sudo ethtool -s eth0 wol g
  # 부팅마다 적용되도록 systemd 또는 netplan 설정
  ```
- [ ] 뚜껑 닫아도 sleep 방지
  ```bash
  # /etc/systemd/logind.conf
  HandleLidSwitch=ignore
  ```
- [ ] journald volatile 설정 (SSD 수명 보호, 선택)

## Phase 3: 전원 관리 (K3s 내)

### 전원 OFF — CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: spot-node-shutdown
  namespace: kloud-system
spec:
  schedule: "0 2 * * *"  # 매일 새벽 2시
  jobTemplate:
    spec:
      template:
        spec:
          nodeSelector:
            kubernetes.io/hostname: <laptop>
          hostPID: true
          containers:
            - name: shutdown
              image: alpine
              command: ["nsenter", "-t", "1", "-m", "-u", "-i", "-n", "--", "shutdown", "-h", "now"]
              securityContext:
                privileged: true
          restartPolicy: Never
```

### 전원 ON — WoL CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: spot-node-wakeup
  namespace: kloud-system
spec:
  schedule: "0 8 * * 1-5"  # 평일 오전 8시
  jobTemplate:
    spec:
      template:
        spec:
          nodeSelector:
            kloud/tier: heavy  # Ryzen에서 실행
          hostNetwork: true
          containers:
            - name: wol
              image: alpine
              command: ["sh", "-c", "apk add --no-cache etherwake && etherwake -i eth0 <MAC>"]
          restartPolicy: Never
```

- [ ] CronJob 매니페스트 작성 (`cluster/core/spot-manager/`)
- [ ] WoL 매직패킷 전송 테스트 (Ryzen → 랩탑)
- [ ] shutdown CronJob 테스트

## Phase 4: 수요 기반 스케일링 (선택)

시간 기반이 아닌, Pending pod 감지 시 자동 WoL 트리거.

- [ ] spot-autoscaler controller 작성
  - Ryzen에서 실행, `hostNetwork: true`
  - `status.phase=Pending` + spot toleration 가진 pod 감지
  - 노드 `NotReady` 상태일 때 WoL 전송
- [ ] 매니페스트 위치: `cluster/core/spot-manager/`

## 스케줄링 패턴

spot 노드에 워크로드를 배치하려면 toleration 추가:

```yaml
tolerations:
  - key: kloud/spot
    operator: Equal
    value: "true"
    effect: NoSchedule
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 50
        preference:
          matchExpressions:
            - key: kloud/tier
              operator: In
              values: ["spot"]
```

## 적합한 워크로드

- CI runner 추가 인스턴스
- 빌드 작업 (Docker buildx)
- 배치/크론 작업
- 부하 테스트

## 부적합한 워크로드

- PV 의존 서비스 (DB, 블로그 등)
- 항상 가용해야 하는 서비스

## 참고

- `docs/scheduling.md` — 기존 노드 스케줄링 패턴
- 매니페스트 디렉토리 예정: `cluster/core/spot-manager/`
