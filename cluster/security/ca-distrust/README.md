# 공용 컨테이너의 CA 불신 정책

2026-10 eMudhra 사고 대응으로 아래 두 루트의 신뢰만 제거한다. 다른 루트,
서비스 바이너리, 데이터, entrypoint는 기존 이미지에서 유지한다.

| 인증서 | SHA-256 |
| --- | --- |
| emSign ECC Root CA - G3 | `86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B` |
| AAA Certificate Services | `D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4` |

근거: [Ubuntu 수정 공지](https://ubuntu.com/blog/emudhra-ca-compromise-fixes-available),
[사고 대응 및 테스트 체인](https://emudhra.we-have-a-problem.com/).

`image-lock.json`은 기존 vendor 이미지와 패치 이미지의 multi-arch index 및
amd64/arm64 child digest를 기록한다. Dockerfile은 기존 번들의 두 지문만
제거하고 `SSL_CERT_FILE`과 `SSL_CERT_DIR`을 필터된 저장소로 지정한다.
이렇게 해야 기존 CA 디렉터리에서 제거한 루트가 다시 로드되지 않는다.
별도 Java truststore나 애플리케이션이 직접 지정한 CA 파일까지 바꾸는 기능은 없다.
CI runner와 WireGuard 본체는 각 디렉터리의 `Dockerfile.security`를 사용한다.
Cloudflared는 이 사고 대응이 포함된 공식
`cloudflare/cloudflared:2026.10.3@sha256:faa8e0a1475f137c910be6025f43c8e4092fdd35461b31e19fd1390657a1ff39`를 사용한다.

2026-10-22 사용자가 승인한 이번 보안 작업에 한해 Kloud에 남은 blog,
character-sites, sample-app, CouchDB, Minecraft, MinIO 설정도 갱신한다.
`legacy-image-lock.json` 및 `minecraft/image-lock.json`은 이 예외 대상의
검사 결과다. 이후 앱 변경은 원래 앱 저장소 소유권 규칙을 따른다.
MinIO는 공급처의 기존 이미지가 내려받기 불가능하여 기존 캐시 이미지를
유지하고 ConfigMap으로 필터된 CA 파일을 투영한다. 해당 설정과 제약은
`legacy/minio-ca/` 및 `cluster/apps/minio/`를 따른다.
CouchDB는 외부 복제 연결의 TLS 검증도 명시적으로 켠다. 적용 전 활성
서버 복제 작업이 없음을 확인했으며, Obsidian 클라이언트 접속 설정은 유지한다.

## 검사와 적용

```sh
python3 -m unittest discover -s cluster/security/ca-distrust -v
python3 cluster/security/ca-distrust/apply_policy.py
python3 cluster/security/ca-distrust/apply_policy.py \
  --target kloud-metrics/grafana --apply
kubectl --context kloud -n kloud-metrics rollout status deployment/grafana
```

기본 명령은 읽기 전용이며 `--apply`는 한 워크로드씩만 허용한다.
canonical Kloud 저장소, origin, `kloud` API와 Ready NAS의 IP를 확인한다.
`targets.json`의 기존 이미지 또는 이미 적용된 패치 이미지만 허용하며,
검사하지 않은 vendor 버전을 과거 버전으로 되돌리지 않는다. 실제 patch는
resourceVersion과 현재 이미지도 검사하여 동시 변경을 덮어쓰지 않는다.
기존 pull secret은 유지하고 개인 GHCR의 `ghcr-ch4n33` 참조만 추가한다.
각 대상 namespace에 검증된 개인 GHCR pull secret이 먼저 있어야 한다.
자격증명은 이 디렉터리에 저장하지 않는다.

이 디렉터리는 공용 인프라의 이미지별 CA 정책을 소유한다. Helm과 K3s가
생성하는 workload 전체를 중복 보관하지 않고 기존 리소스의 이미지 참조만
변경한다. Helm 재설치·업그레이드 및 K3s 재시작 후에는 위 읽기 전용 검사를
실행하고 필요한 정책을 다시 적용한다. 새 vendor 버전은 새 base digest와
CA 검사를 거쳐 lock 및 target을 갱신해야 한다. 기존 vendor manifest를
그대로 재적용하면 CA 패치가 사라질 수 있으므로 정책 검사까지 수행한다.

DaemonSet 전체 rollout은 연결이 끊긴 Pi 때문에 완료되지 않을 수 있다.
Ready NAS의 새 pod와 이미지가 정상인지 별도로 확인하고, Pi의 이전 pod나
스토리지는 강제 삭제하지 않는다. Pi는 복구 후 실제 업데이트를 확인한다.

TLS 검증은 정상 HTTPS 성공과 아래 두 호스트의 인증서 검증 실패를 함께
확인한다. 연결 시간 초과는 차단 검증의 성공으로 처리하지 않는다.

- `https://dv-g3b-emudhra.we-have-a-problem.com/`
- `https://dv-g3b-aaa-emudhra.we-have-a-problem.com/`

인증서 검증을 끄는 옵션으로 우회하지 않는다.
