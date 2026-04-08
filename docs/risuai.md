# RisuAI 배포 문서

## 개요

RisuAI는 AI 프론트엔드 웹앱. 자체 빌드 없이 업스트림 Docker 이미지를 그대로 사용하며, 런타임 sed 패치로 버그를 우회한다.

- **네임스페이스:** `kloud-apps`
- **도메인:** `risu.kloud.rche.moe`
- **Ingress:** Traefik + BasicAuth 미들웨어
- **스토리지:** hostPath PV (`/home/ch4n33/server-data/risuai/`) → `/app/save`
- **노드:** Ryzen 고정 (`kubernetes.io/hostname: ch4n33-server`)

## 이미지 정보

| 항목 | 값 |
|------|---|
| 이미지 | `ghcr.io/kwaroran/risuai:latest` |
| Digest (2026-04-03 기준) | `sha256:6492ada3150dc048645f547b6c06f89cbfaa4ae17372463fab116a51638862fb` |
| Node.js | v20.20.2 |
| 태그 정책 | `latest` + 커밋 SHA (7자리). 시맨틱 버전 태그 없음 |

> **주의:** `latest` 태그를 사용하므로 업스트림 push 시 이미지가 바뀔 수 있다. 문제 발생 시 위 digest로 롤백 가능:
> `ghcr.io/kwaroran/risuai@sha256:6492ada...`

## 런타임 패치 (sed)

업스트림 이미지에 버그가 있어 컨테이너 시작 시 sed로 패치한다. 매니페스트: `cluster/apps/risuai/deployment.yaml`

### 1. trust proxy 설정

```
sed -i "s/const app = express();/const app = express();\napp.set('trust proxy', 1);/" /app/server/node/server.cjs
```

- **문제:** Traefik 리버스 프록시 뒤에서 Express가 클라이언트 IP를 프록시 IP로 인식
- **영향:** rate-limit이 모든 사용자를 단일 IP로 카운트하여 429 발생

### 2. rate-limit 완화

```
sed -i 's/max: 90/max: 100000/g' /app/server/node/server.cjs
```

- **문제:** 기본 rate-limit이 90회로 설정되어 정상 사용에도 429 반환
- **영향:** BasicAuth 인증 시도 + 헬스체크가 빠르게 한도를 소진

### 3. fs/promises 동기 함수 크래시 수정

```
sed -i "s/const fs = require('fs\/promises')/const fs = require('fs\/promises'); const fsSync = require('fs')/" /app/server/node/server.cjs
sed -i 's/fs\.writeFileSync/fsSync.writeFileSync/g' /app/server/node/server.cjs
sed -i 's/fs\.readFileSync/fsSync.readFileSync/g' /app/server/node/server.cjs
```

- **문제:** `server.cjs`에서 `const fs = require('fs/promises')`로 비동기 모듈을 `fs`에 할당. 이후 `fs.writeFileSync()` 호출 시 `TypeError: fs.writeFileSync is not a function` 크래시
- **영향:** 로그인(비밀번호 입력) 시 서버 프로세스 종료 → CrashLoopBackOff
- **발생 위치:** `/api/login` 핸들러 (server.cjs:1151) — 인증 성공 후 public key를 파일에 저장하는 코드

### 4. safeStructuredClone 폴리필 주입

```
sed -i 's|<head>|<head><script>globalThis.safeStructuredClone=function(o){try{return structuredClone(o)}catch(e){return JSON.parse(JSON.stringify(o))}}</script>|' /app/dist/index.html
```

- **문제:** `index.js`에서 `globalThis.safeStructuredClone = UA`를 설정하지만, import된 `database.svelte.js` 모듈이 top-level에서 `safeStructuredClone`을 먼저 참조. ES 모듈 평가 순서상 아직 정의되지 않은 시점에 호출 → `ReferenceError: safeStructuredClone is not defined`
- **영향:** 프론트엔드 무한 로딩 (앱 초기화 실패, `#preloading` 스피너가 영원히 표시)

## 매니페스트 구성

```
cluster/apps/risuai/
├── deployment.yaml   # Deployment (sed 패치 포함)
├── service.yaml      # ClusterIP :80 → :6001
├── ingress.yaml      # Traefik Ingress + TLS
├── middleware.yaml   # BasicAuth 미들웨어
├── secret.yaml       # BasicAuth 크리덴셜
└── pv.yaml           # PV + PVC (hostPath)
```

## 이미지 업데이트 시 확인사항

`latest` 이미지가 업데이트되면 기존 sed 패치가 깨질 수 있다. 업데이트 후 반드시 확인:

1. **sed 패턴 매칭 확인** — 대상 문자열이 변경되었으면 sed가 아무것도 안 하고 넘어감
2. **로그인 테스트** — 비밀번호 입력 후 서버 크래시 여부 확인
3. **프론트엔드 로딩** — 브라우저 콘솔에서 `ReferenceError` 확인
4. **rate-limit** — 반복 요청 시 429 응답 여부 확인
