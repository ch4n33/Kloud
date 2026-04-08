# Compact-Bot 배포 문서

## 개요

[Serin511/Compact-Bot](https://github.com/Serin511/Compact-Bot)는 Discord/Slack을 Claude Code CLI에 연결하는 셀프호스트 브리지. Discord 채널 메시지를 PTY로 실행되는 `claude` 서브프로세스로 전달하고, 응답을 다시 Discord로 돌려준다. **Claude Max 구독을 사용**하므로 Anthropic API 키가 필요 없다(대신 Claude Code OAuth 로그인 세션 필요).

Kloud에서는 단순한 Discord 챗봇이 아니라 **외부에서 Discord로 클러스터를 원격 운영**하는 도구로 배포됨 — 봇 Pod에게 자체 ServiceAccount + 클러스터 운영 권한(view/edit cluster-wide)을 부여하고, ValidatingAdmissionPolicy로 자기 자신과 `kube-system`을 보호한다.

- **네임스페이스:** `compact-bot` (별도 격리)
- **도메인:** 없음 (outbound only — Discord gateway WebSocket 연결만)
- **노드:** Ryzen 고정 (`kubernetes.io/hostname: ch4n33-server`)
- **스토리지:** hostPath PV 3개 (state, tools, workspace)
- **이미지:** `ghcr.io/ch4n33/compact-bot:latest` (자체 빌드, 멀티아키 amd64+arm64)

## 아키텍처

```
Discord ──(WebSocket gateway)── Pod (compact-bot, ns: compact-bot)
                                  │
                                  ├─ ServiceAccount: compact-bot-sa
                                  │   ├─ ClusterRoleBinding → view  (cluster-wide read)
                                  │   └─ ClusterRoleBinding → edit  (cluster-wide write, RBAC 제외)
                                  │       └─ ValidatingAdmissionPolicy: deny ops on
                                  │            { compact-bot, kube-system, kube-public, kube-node-lease }
                                  │            그리고 namespaces 리소스 자체에 대한 모든 ops
                                  │
                                  ├─ /claude-home              ── hostPath PV (state, 3Gi) [통째 마운트]
                                  │     ├─ .claude.json        (인증 토큰 — 매우 중요)
                                  │     ├─ .claude/            (claude 캐시, backups)
                                  │     ├─ .config/compact-bot/ (봇 데이터 + wrapper.sock)
                                  │     ├─ .local/             (pip --user, npm --prefix 등)
                                  │     └─ .kube/config        (entrypoint이 매번 재생성, 비영속)
                                  │
                                  ├─ /opt/cli                  ── hostPath PV (tools, 5Gi)
                                  │     사용자가 sudo curl로 설치한 시스템 도구
                                  │
                                  └─ /workspace                ── hostPath PV (workspace, 10Gi)
                                        claude의 작업 공간 (사용자가 git clone 등)
```

호스트 디렉토리(Ryzen):

```
/home/ch4n33/server-data/compact-bot/
  state/         # /claude-home에 통째 마운트
  tools/         # /opt/cli에 통째 마운트
  workspace/     # /workspace에 통째 마운트
```

## 매니페스트 구조

`cluster/apps/`가 아닌 별도 디렉토리 `cluster/compact-bot/` 사용 (일반 앱이 아닌 메타-운영 도구).

```
apps/compact-bot/
  Dockerfile             # node:20-bookworm + apt + sudo + git + kubectl + gh + claude + compact-bot
  entrypoint.sh          # env 검증, kubeconfig 생성, npx compact-bot 실행

cluster/compact-bot/
  namespace.yaml         # ns: compact-bot
  rbac.yaml              # SA + view/edit ClusterRoleBindings
  admission-policy.yaml  # ValidatingAdmissionPolicy + Binding (자기보호 + ns 생성 차단)
  pv.yaml                # state(3Gi) + tools(5Gi) + workspace(10Gi) PV/PVC
  deployment.yaml        # Deployment, Recreate, fsGroup 1000
  secret.example.yaml    # DISCORD_BOT_TOKEN, ALLOWED_CHANNEL_IDS 템플릿
  # secret.yaml          # gitignored (**/secret.yaml)

.github/workflows/
  deploy-compact-bot.yml # 멀티아키 빌드 + kubectl set image

infrastructure/scripts/
  create-compact-bot-secret.sh  # 토큰 입력받아 Secret 생성/갱신 헬퍼
```

## 권한 모델

### 1. 빌트인 ClusterRole 두 개를 cluster-wide로 바인딩

- `view`: 클러스터 전체 read (Secret 제외 — 디버깅 시 필요하면 커스텀 ClusterRole로 보강)
- `edit`: 클러스터 전체 write (RBAC, CRD, webhook은 자동 제외 — escalation 차단)

`edit`에는 namespaces verb가 없어 봇이 새 ns를 생성하거나 삭제할 수 없음.

### 2. ValidatingAdmissionPolicy (K3s 1.34+, K8s 1.30 GA)

K8s 네이티브 CEL 정책으로 belt-and-suspenders 추가 차단:

- 보호 ns(`compact-bot`, `kube-system`, `kube-public`, `kube-node-lease`)에 대한 CREATE/UPDATE/DELETE 거부
- 네임스페이스 리소스 자체에 대한 모든 ops 거부 (RBAC 단계에서 이미 막히지만 명시적으로 한 번 더)

`matchConditions`에 user 필터(`system:serviceaccount:compact-bot:compact-bot-sa`) 둬서 다른 SA에는 영향 없음.

## CLI 도구 영속화

이미지에 시드된 도구: `git`, `kubectl`, `gh`, `jq`, `python3`, `pip`, `vim-tiny`, `nano`, `curl`, `wget`, `rsync`, `ssh-client`, `htop`, `procps`, `build-essential` 등.

런타임에 추가 설치할 때:

| 방식 | 위치 | 영속 | 비고 |
|---|---|---|---|
| `sudo curl -o /opt/cli/bin/foo ...` | `/opt/cli/bin` (PV) | ✓ | 권장. PATH 우선순위 최상위 |
| `pip install --user pkg` | `~/.local/...` (PV) | ✓ | python 패키지용 |
| `npm install --prefix ~/.local pkg` | `~/.local/...` (PV) | ✓ | npm 패키지용 |
| `sudo apt install pkg` | `/usr/bin`, `/var/lib/dpkg` | ✗ | 컨테이너 재시작 시 사라짐 (의도된 동작) |

PATH 순서: `/opt/cli/bin > ~/.local/bin > /usr/local/bin > /usr/bin`

## 배포 절차 (처음 한 번)

### 0. 사전 준비 — Discord 봇 만들기

1. https://discord.com/developers/applications → New Application → 봇 생성
2. **Bot 탭 → Privileged Gateway Intents → Message Content Intent ON** (필수, 안 켜면 봇이 메시지를 아예 못 봄)
3. Bot Token 복사 (이후 secret 생성에 사용)
4. **OAuth2 → URL Generator**: scopes `bot`, 권한은 최소 `View Channels` + `Send Messages` + `Read Message History`. URL로 봇을 길드에 초대.

> ⚠️ **채널 ID 복사할 때 주의**: Discord에서 "ID 복사"는 우클릭한 대상의 ID를 복사한다.
> - 길드(서버) 우클릭 → **길드 ID** (사용 X)
> - 채널 우클릭 → **채널 ID** (사용 ✓)
> 길드 ID를 채널 ID로 잘못 등록하면 봇이 영원히 무반응이다 (실제로 한 번 겪었음).
> 개발자 모드 활성화 필요: 사용자 설정 → 고급 → 개발자 모드 ON.

### 1. 호스트 디렉토리 준비 (Ryzen)

```bash
ssh nas-public
sudo mkdir -p /home/ch4n33/server-data/compact-bot/{state,tools,workspace}
sudo chown -R 1000:1000 /home/ch4n33/server-data/compact-bot
```

권한이 1000:1000이어야 하는 이유: 컨테이너 안 `node` 사용자가 uid 1000이고, fsGroup이 1000이라 mount 시 자동으로 권한이 잡힌다.

### 2. 매니페스트 적용 (네임스페이스, RBAC, VAP, PV)

```bash
kubectl --context kloud apply -f cluster/compact-bot/namespace.yaml
kubectl --context kloud apply -f cluster/compact-bot/rbac.yaml
kubectl --context kloud apply -f cluster/compact-bot/admission-policy.yaml
kubectl --context kloud apply -f cluster/compact-bot/pv.yaml
```

### 3. Secret 생성

```bash
./infrastructure/scripts/create-compact-bot-secret.sh
# Discord Bot Token: (입력 숨김)
# Allowed Channel IDs: 채널ID1,채널ID2 (콤마 구분)
```

스크립트는 ns 자동 생성, 네임스페이스가 없으면 만들고 secret 갱신.

### 4. CI 트리거 — git push

```bash
git add apps/compact-bot/ cluster/compact-bot/ \
        .github/workflows/deploy-compact-bot.yml \
        infrastructure/scripts/create-compact-bot-secret.sh
git commit -m "deploy(compact-bot): ..."
git push origin main
```

GitHub Actions self-hosted runner가:
1. 멀티아키 이미지 빌드 (amd64 + arm64, node-pty native 컴파일이 arm64 emulation에서 5–10분 소요)
2. ghcr.io에 push
3. `kubectl apply` + `kubectl set image` + `kubectl rollout status`

> **첫 빌드 시 주의 (이번에 실제로 겪은 함정)**: 새 ghcr.io 패키지를 처음 push할 때 default workflow permissions가 `read`이면 `denied: permission_denied: write_package` 에러가 난다. 한 번 write로 바꿔주면 이후 영구 적용:
> ```bash
> gh api -X PUT /repos/ch4n33/Kloud/actions/permissions/workflow \
>   -f default_workflow_permissions=write -F can_approve_pull_request_reviews=false
> ```

### 5. Claude Code OAuth 로그인 (필수, 사용자 수동)

배포 직후 봇은 무한 hang 상태 (`claude` 서브프로세스가 인증 wizard에서 멈춤). 임시 Pod를 띄워서 **인터랙티브로 한 번 로그인** 해야 한다.

```bash
# 봇 종료 (PVC 충돌 방지)
kubectl --context kloud scale deployment/compact-bot -n compact-bot --replicas=0

# 임시 Pod 생성 — /claude-home 통째 마운트
kubectl --context kloud run claude-login -n compact-bot \
  --image=ghcr.io/ch4n33/compact-bot:latest \
  --restart=Never \
  --overrides='{
    "spec": {
      "nodeSelector": {"kubernetes.io/hostname": "ch4n33-server"},
      "securityContext": {"runAsUser": 1000, "fsGroup": 1000},
      "containers": [{
        "name": "claude-login",
        "image": "ghcr.io/ch4n33/compact-bot:latest",
        "command": ["sleep", "3600"],
        "env": [{"name":"HOME","value":"/claude-home"}],
        "volumeMounts": [{"name":"s","mountPath":"/claude-home"}]
      }],
      "volumes": [{"name":"s","persistentVolumeClaim":{"claimName":"compact-bot-state-pvc"}}]
    }
  }'

# 인터랙티브 진입
kubectl --context kloud exec -it -n compact-bot claude-login -- bash

# === 컨테이너 안 ===
claude auth login
# OAuth URL 출력 → 브라우저에서 열기 → Authorize → 코드 복사 → 터미널에 paste + Enter

claude auth status   # loggedIn: true 확인
ls -la /claude-home/.claude.json   # 20KB 이상이면 성공 (수백 바이트는 stub)
exit

# 임시 Pod 정리 + 봇 재기동
kubectl --context kloud delete pod claude-login -n compact-bot
kubectl --context kloud scale deployment/compact-bot -n compact-bot --replicas=1
kubectl --context kloud rollout status deployment/compact-bot -n compact-bot
```

> ⚠️ **`/claude-home`을 통째로 PV에 마운트해야 한다** (subPath 분기 X). claude 인증의 핵심 토큰은 `~/.claude.json` 파일에 저장되는데 이건 `~/.claude/` 디렉토리와 별개라, subPath로 `~/.claude/`만 마운트하면 인증이 영속화되지 않는다 (실제로 한 번 겪었음).

### 6. 동작 확인

```bash
kubectl --context kloud get pod -n compact-bot
# Running 1/1, RESTARTS 0 이어야 정상

kubectl --context kloud logs -n compact-bot deploy/compact-bot 2>&1 | grep -aE "(Bot Ready|Channels)"
# "✦ Bot Ready" 와 "Channels 1234567890" 가 보여야 정상
```

Discord 채널에서 봇 멘션해서 짧은 메시지 보내면 응답 와야 함.

## 트러블슈팅

이 배포에서 실제로 겪은 함정들 정리.

### 봇이 메시지에 무반응

가능성 순:

1. **채널 ID가 길드 ID와 혼동됐다** — Discord에서 "ID 복사" 시 길드를 우클릭하면 길드 ID가 복사된다. 채널을 우클릭해야 채널 ID. 봇 토큰으로 직접 Discord에 접속해 길드/채널 리스트 확인:
   ```bash
   kubectl --context kloud scale deployment/compact-bot -n compact-bot --replicas=0
   kubectl --context kloud run discord-probe -n compact-bot --rm -i --restart=Never \
     --image=ghcr.io/ch4n33/compact-bot:latest \
     --env="DISCORD_BOT_TOKEN=$(kubectl --context kloud get secret compact-bot-secret -n compact-bot -o jsonpath='{.data.DISCORD_BOT_TOKEN}' | base64 -d)" \
     --command -- node -e '
   const { Client, GatewayIntentBits } = require("/usr/local/lib/node_modules/@serin511/compact-bot/node_modules/discord.js");
   const c = new Client({ intents: [GatewayIntentBits.Guilds] });
   c.once("ready", () => {
     c.guilds.cache.forEach(g => {
       console.log("Guild:", g.name, g.id);
       g.channels.cache.forEach(ch => console.log(" -", ch.type, ch.name, ch.id));
     });
     setTimeout(() => process.exit(0), 1000);
   });
   c.login(process.env.DISCORD_BOT_TOKEN);'
   ```

2. **Message Content Intent OFF** — Discord Developer Portal에서 활성화 필수. 활성화 후 봇 재시작 필요.

3. **봇이 그 채널 권한 없음** — 비공개 채널인 경우 채널 권한에서 봇 역할/멤버 명시 추가 필요.

### Pod이 EACCES wrapper.sock 에러로 죽는다

봇이 데이터/소켓을 `~/.config/compact-bot/`에 만드는데, 그 디렉토리가 쓰기 불가능하면 이 에러. **`/claude-home`을 통째로 PV에 마운트**하면 자동으로 해결 (deployment.yaml에서 subPath 분기를 쓰지 말 것).

### Pod이 Bot Ready는 뜨지만 응답이 없고 로그가 setup wizard에서 멈춤

봇이 `claude` 서브프로세스를 PTY 인터랙티브 모드로 띄우는데, 인증이 안 되어 있으면 onboarding wizard에서 hang. **5단계 (Claude Code OAuth 로그인) 절차를 다시 수행**하면 됨. `~/.claude.json` 파일이 PV에 정상 영속되었는지 확인:
```bash
kubectl --context kloud exec -n compact-bot deploy/compact-bot -- \
  bash -c 'ls -la /claude-home/.claude.json && claude auth status'
```
파일 크기가 20KB 이상이고 `loggedIn: true`면 정상. 작거나 없으면 재인증 필요.

### CI에서 `denied: permission_denied: write_package`

ghcr.io 새 패키지 첫 push 시 워크플로우 토큰 권한 부족. 위 4단계 주의사항 참고.

### node 사용자 uid 1000 충돌

`useradd -u 1000`으로 새 사용자 만들면 충돌. node:20-bookworm에 이미 uid 1000인 `node` 사용자가 있다 → `usermod -d /claude-home -m node`로 홈 이동만 하고 재사용.

## 운영

### Claude Max 세션 만료 시 재인증

Claude OAuth 토큰은 주기적으로 만료된다. 봇 응답이 갑자기 끊기고 인증 에러가 보이면 5단계 절차 재수행:

```bash
kubectl --context kloud scale deployment/compact-bot -n compact-bot --replicas=0
# 임시 Pod 생성 → claude auth login → 정리 → 봇 재기동
```

### 봇 이미지 업데이트

`apps/compact-bot/Dockerfile` 변경 후 commit + push → CI가 자동 빌드/배포. `@serin511/compact-bot`이 npm `latest` 태그라 매 빌드마다 새 버전이 들어올 수 있다. 안정화 후 버전 핀(`@x.y.z`) 권장.

### Discord 채널 변경/추가

```bash
./infrastructure/scripts/create-compact-bot-secret.sh
# 다시 실행해서 채널 ID 입력 (콤마 구분)
kubectl --context kloud rollout restart deployment/compact-bot -n compact-bot
```

### 디버그 로그 활성화

`compact-bot`은 `VERBOSE=true` 환경변수로 추가 로그 활성화 가능:

```bash
kubectl --context kloud patch secret compact-bot-secret -n compact-bot \
  -p '{"stringData":{"VERBOSE":"true"}}'
kubectl --context kloud rollout restart deployment/compact-bot -n compact-bot
```

다만 wrapper가 PTY로 띄운 claude TUI의 ANSI escape가 로그를 뒤덮으므로, raw 텍스트 추출 시 sed 필터:
```bash
kubectl --context kloud logs -n compact-bot deploy/compact-bot 2>&1 \
  | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -aE "(message|route|Bot Ready)"
```

끄려면:
```bash
kubectl --context kloud patch secret compact-bot-secret -n compact-bot \
  --type=json -p='[{"op":"remove","path":"/data/VERBOSE"}]'
kubectl --context kloud rollout restart deployment/compact-bot -n compact-bot
```

## 보안 노트

- **Discord 채널 = 클러스터 admin 입구**: ALLOWED_CHANNEL_IDS만이 유일한 접근 게이트. 채널은 본인만 접근 가능한 비공개로 유지. 채널 ID가 노출되면 그 채널 멤버 누구든 봇과 대화 가능 → 클러스터 운영 가능.
- **sudo NOPASSWD = 컨테이너 안 root**: 봇은 컨테이너 안에서 root 권한이지만 securityContext가 비특권이라 호스트 root는 아님 (호스트 파일시스템 접근 X). hostPath 마운트 디렉토리 안에서는 root처럼 동작 가능.
- **`view` ClusterRole은 Secret 미포함**: 봇이 다른 ns의 Secret 내용을 못 읽음. 디버깅 시 필요하면 커스텀 ClusterRole로 보강.
- **VAP 우회 가능성**: 봇이 kube-system을 직접 만질 수는 없지만, 다른 ns에 cluster-admin 토큰을 가진 Pod를 배포하는 식의 우회는 이론적으로 가능. 다만 `edit` ClusterRole이 RBAC/SA token을 다루지 못해 직접적인 escalation은 막힘.
