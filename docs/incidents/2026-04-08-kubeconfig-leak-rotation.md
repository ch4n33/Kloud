# 2026-04-08 — kubeconfig-external 노출 사고 및 CA 회전

> **상태:** ✅ 완료. 2026-04-08 22:10 KST 클러스터 완전 복구. 잔여 작업: git history rewrite (Phase C), GitHub Actions secret 갱신 (Phase B).

## 사고 개요

`infrastructure/kubeconfig-external` 파일이 K3s admin client cert + **개인 키**를 포함한 채로 공개 GitHub repo([ch4n33/Kloud](https://github.com/ch4n33/Kloud))에 커밋되어 있었다. 누구든 이 파일만 받으면 cluster-admin 권한 획득 가능한 상태였다.

- **노출 대상:** K3s admin client cert + private key (`O = system:masters, CN = system:admin`)
- **노출 위치:** [infrastructure/kubeconfig-external](../../infrastructure/kubeconfig-external) (HEAD 및 git history)
- **GitHub URL:** https://github.com/ch4n33/Kloud/blob/main/infrastructure/kubeconfig-external
- **외부 도달성:** 6443 포트는 외부 차단, WireGuard VPN 안에서만 도달 가능. 그러나 VPN 침투 시 즉시 cluster-admin이라 보안 사고로 분류.
- **원인:** `.gitignore`가 `kubeconfig`만 매칭(13행), `kubeconfig-external`은 매칭하지 못해 커밋됨.

## 대응 결정 사항

1. `.gitignore` 패턴 수정 (`kubeconfig` → `*kubeconfig*`)
2. 노출된 키 무효화 + 키 회전
3. 기타 secret 노출 스캔
4. git history rewrite + force push로 GitHub history 정리

대응 방법으로 **K3s CA 전체 회전(rotate-ca --force)** 선택. 이유: 단순 `certificate rotate --service admin`으로는 같은 CA에 의해 서명된 노출 cert가 만료(1년)까지 valid이기 때문. 직접 검증 완료 (회전 전 leaked cert로 `kubectl get nodes` 정상 동작 확인).

옵션 비교:
- **옵션 A (선택):** in-place CA rotate (`k3s certificate rotate-ca --force`) — 데이터/매니페스트 그대로 유지
- 옵션 B: K3s 클러스터 완전 재설치 — secret 재생성 필요
- 옵션 C: rollback 또는 외부 차단만 의존 — 보안 후퇴

## 진행 타임라인

### 완료 ✅

1. **`.gitignore` 패턴 수정** — `*kubeconfig*` (13행). `kubeconfig-external`도 매칭됨.
2. **`infrastructure/kubeconfig-external` untrack** — `git rm --cached`로 인덱스에서 제거 (working tree 파일은 새 cert로 덮어써짐, gitignore되어 다음 commit에 포함 안 됨).
3. **다른 secret 스캔 — clean 확인**:
   - `.github/workflows/*.yml`: 모두 `${{ secrets.X }}` 참조만, 하드코딩 없음
   - `infrastructure/ansible/playbooks/*.yml`: 변수 참조만 (`b64decode`)
   - `cluster/apps/risuai/middleware.yaml`: secret reference만 (평문 없음)
   - 기타 PEM/private key 패턴 매칭 없음
4. **K3s 백업 생성**:
   - TLS 디렉토리: `nas-public:/home/ch4n33/k3s-tls-backup-1775650596`
   - dynamic-cert: `nas-public:/home/ch4n33/dynamic-cert.json.bak`
5. **새 CA 생성** — `nas-public:/opt/k3s/server/tls` (빈 staging에서 시작 → 새 root + intermediate + 모든 컴포넌트 CA가 새로 생성됨, timestamp `1775650938`)
   - 사용 스크립트: https://raw.githubusercontent.com/k3s-io/k3s/main/contrib/util/generate-custom-ca-certs.sh
   - 명령: `sudo DATA_DIR=/opt/k3s bash /tmp/gen-ca.sh`
6. **`k3s certificate rotate-ca --force --path=/opt/k3s/server`** — `certificates saved to datastore` 출력 확인
7. **K3s 서버 재시작** — disk의 `client-admin.crt`, `server-ca.crt` 등이 새 CA로 갱신됨
   - 새 admin client cert SHA1: `BE:0C:38:C2:A3:6D:91:6A:A4:91:CC:8B:F4:8A:60:79:D1:AE:A5:6D`
   - 새 cluster token prefix: `K1076aebec0e08fbc659c709ddd318...` (이전: `K10df355fe85f0aedc7b...`)
8. **노출된 cert 무효화 검증 ✅** — `git show HEAD:infrastructure/kubeconfig-external`로 옛 kubeconfig 복원 후 `kubectl get nodes` 시도 → **`error: You must be logged in to the server (Unauthorized)`** (exit 1)
   - 즉 client-ca는 정상 회전되어 옛 client cert는 더 이상 인증되지 않음
9. **Pi agent token 갱신** — `/etc/systemd/system/k3s-agent.service.env`의 `K3S_TOKEN`을 새 값으로 교체

### 미완 / 문제 발생 ❌

10. **Pi agent rejoin** — k3s-agent stop → cached agent cert 삭제 → start. systemd service는 `active`로 시작 성공 (background task `blfww1jkc` exit 0 확인). 단, K3s 서버가 `activating` stuck 상태라 cluster join 자체는 미확인. 다음 세션에서 서버 복구 후 `kubectl get nodes`로 raspberrypi가 Ready로 돌아오는지 확인해야 함.
11. **K3s 서버 dynamiclistener cert 갱신 실패** — 아래 § K3s 버그 #13006 참고
12. **K3s 서버 self-handshake 무한 실패** — 서버가 6분+ `activating (start)` 상태에서 ready 못 됨. systemd notify signal 수신 실패. 메모리 7GB (peak 14.2GB) 사용 중.
13. **새 admin kubeconfig 로컬 deploy** — [infrastructure/kubeconfig-external](../../infrastructure/kubeconfig-external)에 새 cert로 작성됨 (gitignore되어 commit X). 단, server cert 검증 실패로 `--insecure-skip-tls-verify` 없이는 사용 불가.
14. **Pod rolling restart** (SA token 재서명) — 미실행
15. **GitHub Actions `secrets.KUBECONFIG` 갱신** — 미실행 (operator 수동 작업 필요)
16. **git history rewrite** (`git filter-repo`) — 미실행
17. **force push** — 미실행

## 발생한 K3s 버그

### #13006 — CA cert rotation does not trigger immediate update to dynamiclistener cert

**증상:**
- `rotate-ca --force` 후 disk의 `server-ca.crt`는 새 CA로 갱신됨 (subject `k3s-server-ca@1775650938`)
- 그러나 K3s가 실제로 서빙하는 TLS cert는 옛 server-ca (`k3s-server-ca@1773711097`)로 서명됨
- `openssl s_client -connect 127.0.0.1:6443 -showcerts` 결과:
  - `subject=O = k3s, CN = k3s` (dynamic listener이 동적으로 발급)
  - `issuer=CN = k3s-server-ca@1773711097` ← **옛 CA**
- K3s 자체가 self-verify 실패: `Remotedialer proxy error; reconnecting... error="tls: failed to verify certificate: x509: certificate signed by unknown authority" url="wss://192.168.50.18:6443/v1-k3s/connect"` (무한 반복)
- 결과: K3s server가 ready 못 되고 `activating` 상태 stuck

**시도한 workaround (모두 실패):**
- `dynamic-cert.json` 삭제 후 K3s 재시작 → datastore에서 옛 cert 다시 sync
- `kube-system/k3s-serving` secret 삭제 후 K3s 재시작 → 동일

**참고:**
- Issue: https://github.com/k3s-io/k3s/issues/13006
- Status: closed 2025-10-14, fix는 **2025-11 release cycle**에 포함
- 현재 클러스터 K3s 버전 `v1.34.5+k3s1`는 fix 이전 버전

## 현재 상태 (2026-04-08 22:10 KST 기준, 최종)

### Cluster
| 노드 | 상태 | 비고 |
|------|------|------|
| ch4n33-server (Ryzen) | **`Ready`** ✅ | K3s v1.34.6+k3s1, dynamic listener 새 CA로 정상 서빙 |
| raspberrypi (Pi) | **`Ready`** ✅ | k3s-agent 자동 rejoin, v1.34.5+k3s1 |

### Cert / Key 상태
- ✅ **노출된 admin client cert: invalid** (401 Unauthorized 검증 완료)
- ✅ **client-ca: 새 CA로 회전 완료** (`k3s-server-ca@1775650938`)
- ✅ **새 admin kubeconfig 발급**: [infrastructure/kubeconfig-external](../../infrastructure/kubeconfig-external) (gitignore됨)
- ✅ **server cert (dynamic listener): 새 CA로 갱신** (`issuer=CN = k3s-server-ca@1775650938`)
- ✅ **kubelet serving cert: 새 CA로 갱신**
- ✅ **새 cluster token**: Pi agent 적용 완료
- ✅ **metrics-server**: rolling restart 후 정상 (SA token 갱신)
- ⏳ **모든 pod SA token 갱신**: rolling restart 미완 (서비스 영향 없음, 자동 갱신 대기)
- ⏳ **GitHub Actions `secrets.KUBECONFIG`**: 수동 갱신 필요
- ⏳ **git history rewrite**: `git filter-repo` 미실행

### 백업
- `nas-public:/home/ch4n33/k3s-tls-backup-1775650596` — rotate-ca 직전 TLS 디렉토리 전체
- `nas-public:/home/ch4n33/dynamic-cert.json.bak` — 첫 K3s 재시작 직후 dynamic-cert.json
- staging 새 CA: `nas-public:/opt/k3s/server/tls`
- agent service.env 백업: `pi:/etc/systemd/system/k3s-agent.service.env.bak`

### Working tree (Mac)
- [.gitignore](../../.gitignore) — `kubeconfig` → `*kubeconfig*` 패턴 변경 (uncommitted)
- [infrastructure/kubeconfig-external](../../infrastructure/kubeconfig-external) — 새 admin cert로 덮어써짐 (gitignore되어 commit 안 됨)
- 인덱스에서 `infrastructure/kubeconfig-external` 제거됨 (`git rm --cached`)

### GitHub repo
- `infrastructure/kubeconfig-external`이 git history에 여전히 존재
- 현재 노출 cert는 invalid 상태이지만, history rewrite로 cert data 자체를 제거하는 작업이 미완
- GitHub Actions `secrets.KUBECONFIG`는 옛 cert 그대로 사용 중 (변경 시 deploy workflow에 영향)

## Post-mortem: 복구 과정 분석

### Phase A 실제 진행

**K3s 업그레이드 (v1.34.5 → v1.34.6):** `INSTALL_K3S_CHANNEL=v1.34`로 업그레이드 완료. 단, 업그레이드만으로는 클러스터가 회복되지 않았음.

**실제 root cause — dynamic-cert.json 오진:**
초기에 `ls /var/lib/rancher/k3s/server/tls/dynamic-cert.json`을 sudo 없이 실행해 permission denied를 "파일 없음"으로 오인. 파일은 존재했으며, K3s 재시작 시마다 이 파일에서 옛 CA cert를 읽어 sqlite(kine)에 `kube-system/k3s-serving` secret으로 복원하는 루프가 계속됐음.

이전 워크어라운드 실패 원인:
- `dynamic-cert.json` 삭제 후 재시작 → `k3s-serving` secret에서 복원
- `k3s-serving` secret 삭제 후 재시작 → `dynamic-cert.json`에서 복원
- 두 소스를 동시에 지우지 않으면 서로가 서로를 복원하는 사이클

**해결 순서:**
1. K3s 중단
2. `sudo rm /var/lib/rancher/k3s/server/tls/dynamic-cert.json`
3. sqlite에서 `kube-system/k3s-serving` 항목 전체 삭제 (python3 + sqlite3 모듈, `sqlite3` binary 미설치)
4. K3s 재시작 → v1.34.6이 새 CA로 cert 신규 발급
5. `issuer=CN = k3s-server-ca@1775650938` 확인 → 완료

**metrics-server:** SA token이 옛 CA trust bundle을 가지고 있어 kubelet scraping 실패. rolling restart 1회로 해결.

### 학습된 교훈

1. **sudo 없이 root-owned 경로 접근 시 permission denied ≠ 파일 없음.** `ls`/`stat` 결과를 해석할 때 항상 에러 종류를 구분할 것.
2. **cert 소스는 항상 복수.** K3s dynamic listener는 `dynamic-cert.json`과 kine sqlite 두 곳에서 cert를 읽음. 하나만 지우면 다른 쪽이 복원. 회전/초기화 시 모든 소스를 동시에 처리해야 함.
3. **#13006 fix는 "새 인스턴스 생성"을 올바르게 처리**하는 것이지, 기존 stale cert를 자동 제거하지 않음. 스스로 cert 소스를 정리해야 fix가 효과를 발휘함.
4. **.gitignore는 glob으로 방어.** `kubeconfig`가 아닌 `*kubeconfig*`처럼 와일드카드로 패턴을 작성해야 변형 파일명을 커버함.
5. **K3s CA 회전 후 metrics-server (및 apiserver 통신 pod) rolling restart 필요.** SA token의 CA bundle이 구버전이므로 pod 재시작으로 갱신.

---

## 다음 세션 액션 아이템

> **사용자 결정:** 옵션 1 (K3s 업그레이드) 진행하기로 함.

### Phase A: 클러스터 운영성 복구 (최우선)

1. **Ryzen K3s 업그레이드 시도**
   ```bash
   ssh nas-public 'curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL=latest sh -'
   ```
   - 목표: #13006 fix가 포함된 버전 (2025-11 release cycle 이후, K3s v1.34.6+ 또는 v1.35.x)
   - 업그레이드 후 K3s 자동 재시작. dynamic listener cert가 새 server-ca로 재발급되는지 확인:
     ```bash
     ssh -o ClearAllForwardings=yes nas-public 'echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null | grep -E "(subject=|issuer=)"'
     ```
   - 기대 결과: `issuer=CN = k3s-server-ca@1775650938` (새 CA)

2. **업그레이드가 실패하거나 dynamic listener가 여전히 옛 CA stuck인 경우, fallback:**
   - **옵션 2 (재설치)**: `k3s-uninstall.sh` 후 재설치, 매니페스트 재적용, secret 재생성
     - Secret 재생성 스크립트: [infrastructure/scripts/create-compact-bot-secret.sh](../../infrastructure/scripts/create-compact-bot-secret.sh), [create-wg-secret.sh](../../infrastructure/scripts/create-wg-secret.sh)
     - 추가 secret 수동 생성 필요: postgres, risuai-basicauth, ghcr 등
   - **옵션 3 (rollback)**: `sudo cp -a /home/ch4n33/k3s-tls-backup-1775650596/* /var/lib/rancher/k3s/server/tls/ && sudo systemctl restart k3s` — ⚠️ 노출 cert가 다시 valid해짐, 보안 후퇴

3. **클러스터 ready 확인 후 Pi rejoin**
   ```bash
   ssh nas-public 'sshpass -p "$(grep PI_PASSWORD ~/Dev/Kloud/infrastructure/.credentials | cut -d= -f2)" ssh pi@192.168.50.167 "sudo systemctl restart k3s-agent && sleep 10 && sudo systemctl is-active k3s-agent"'
   ```
   - Pi token은 이미 새 값으로 갱신되어 있음 (Phase 9에서 완료)
   - Pi 비밀번호 특수문자(`!`) 처리: feedback 메모리 참고

4. **`kubectl get nodes`로 양쪽 노드 Ready 확인**

### Phase B: 잔여 보안 작업

5. **새 admin kubeconfig 검증** — `--insecure-skip-tls-verify` 없이 동작해야 함
   ```bash
   KUBECONFIG=~/Dev/Kloud/infrastructure/kubeconfig-external kubectl get nodes
   ```

6. **모든 pod rolling restart** (SA token 재서명):
   ```bash
   kubectl get deploy -A -o name | xargs -I {} kubectl rollout restart {} -n <namespace>
   # 또는 namespace별로
   ```

7. **GitHub Actions `secrets.KUBECONFIG` 갱신**:
   - 새 admin kubeconfig를 `gh secret set KUBECONFIG -R ch4n33/Kloud < ~/Dev/Kloud/infrastructure/kubeconfig-external`
   - 또는 GitHub UI: Settings → Secrets and variables → Actions → `KUBECONFIG`
   - 갱신 후 deploy workflow 한 번 trigger해서 동작 확인

### Phase C: GitHub history 정리

8. **`git filter-repo`로 history rewrite** (destructive, 별도 사용자 confirm 권장):
   ```bash
   # 백업 브랜치 먼저
   git branch backup-pre-rewrite

   # filter-repo 설치 (없으면)
   brew install git-filter-repo

   # history에서 파일 제거
   git filter-repo --invert-paths --path infrastructure/kubeconfig-external
   ```

9. **force push** (destructive):
   ```bash
   git push --force-with-lease origin main
   ```
   - main 브랜치 force push → 다른 머신/runner의 로컬 clone 영향. 클러스터에 있는 self-hosted runner도 fresh clone으로 갱신 필요할 수 있음.

10. **GitHub secret scanning 알림 확인** — Settings → Security → Secret scanning

### Phase D: 후속 정리

11. **`.gitignore` 변경 commit** — 다른 운영자/세션 보호 목적
12. **이 incident 문서 업데이트** — 최종 결과 반영, status를 "완료"로 변경
13. **백업 파일 정리** — Ryzen `/home/ch4n33/k3s-tls-backup-*`, `/home/ch4n33/dynamic-cert.json.bak`, `/opt/k3s` (검증 완료 후)

## 검증 명령 모음

### 노출 cert가 invalid한지 확인 (재검증)
```bash
git show HEAD~N:infrastructure/kubeconfig-external > /tmp/leaked && \
  KUBECONFIG=/tmp/leaked kubectl --context kloud get nodes; \
  rm -f /tmp/leaked
# 기대: error: You must be logged in to the server (Unauthorized)
```
※ history rewrite 후에는 `git show`로 옛 cert 복원 불가. 그 전에 한 번 더 검증 권장.

### Server cert chain 확인
```bash
ssh -o ClearAllForwardings=yes nas-public 'echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null | grep -E "(subject=|issuer=)"'
# 기대: issuer=CN = k3s-server-ca@1775650938
```

### Disk cert 확인
```bash
ssh -o ClearAllForwardings=yes nas-public 'sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/client-admin.crt -noout -subject -fingerprint -dates'
```

### 새 admin kubeconfig로 cluster API 도달
```bash
KUBECONFIG=~/Dev/Kloud/infrastructure/kubeconfig-external kubectl get nodes
```

## 참고 자료

- K3s 인증서 회전 공식 문서: https://docs.k3s.io/cli/certificate
- K3s 버그 #13006: https://github.com/k3s-io/k3s/issues/13006
- generate-custom-ca-certs.sh: https://raw.githubusercontent.com/k3s-io/k3s/main/contrib/util/generate-custom-ca-certs.sh
- Kubernetes는 CRL 미지원 — 노출된 cert 무효화는 CA 회전이 유일한 방법

## SSH 접속 노트

- **Mac → Ryzen**: `ssh nas-public` (LocalForward 6443 충돌 시 `-o ClearAllForwardings=yes` 필요)
- **Mac → Ryzen → Pi**: `ssh nas-public 'sshpass -p "..." ssh pi@192.168.50.167 "..."'`
- Pi 비밀번호 특수문자(`!`): heredoc 또는 `sshpass -f` 사용 (메모리 `feedback_sshpass.md` 참고)

---

**작성:** Claude Code 세션 (Opus 4.6) / 2026-04-08 21:40 KST
**핸드오프 사유:** K3s 업그레이드 작업으로 넘어가기 전에 새 세션에서 깨끗하게 시작하기 위함
