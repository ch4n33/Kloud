---
title: "kubeconfig를 GitHub에 올렸다 — K3s CA 회전 삽질기"
date: 2026-04-08
summary: "홈 클러스터 admin 키를 퍼블릭 레포에 통째로 커밋했다. CA를 통째로 갈아엎으며 배운 것들."
tags: ["k3s", "kubernetes", "security", "homelab", "incident"]
---

오늘 홈 클러스터를 관리하다가 꽤 민망한 실수를 발견했다.

`infrastructure/kubeconfig-external` — K3s cluster-admin 권한을 가진 client cert와 **private key** 가 포함된 파일 — 이 퍼블릭 GitHub 레포에 몇 주째 커밋되어 있었다.

## 왜 이게 올라갔나

`.gitignore`에는 `kubeconfig`만 있었다. `kubeconfig-external`은 매칭하지 않았다.

```gitignore
# 이렇게 되어 있었다
kubeconfig

# 이렇게 됐어야 했다
*kubeconfig*
```

glob 하나의 차이. 단순하고 치명적이다.

## 노출 cert를 단순히 revoke할 수 없다

Kubernetes는 CRL(Certificate Revocation List)을 지원하지 않는다. 노출된 cert를 "무효화"하는 방법은 딱 하나 — **CA 자체를 교체**하는 것이다.

`k3s certificate rotate --service admin` 같은 커맨드는 같은 CA로 재서명할 뿐이다. 새 cert를 발급해도 옛 cert가 만료(1년 뒤)까지 유효하다는 의미다. 그래서 K3s CA 전체 교체(`k3s certificate rotate-ca --force`)를 선택했다.

실제로 옛 kubeconfig로 `kubectl get nodes`를 시도해서 **401 Unauthorized**가 뜨는 걸 확인하고 나서야 마음이 놓였다.

## K3s 버그 #13006

CA를 교체했더니 K3s 서버가 `activating` 상태에서 멈췄다.

원인은 K3s 버그 [#13006](https://github.com/k3s-io/k3s/issues/13006): CA 회전 후 dynamic listener가 계속 **옛 CA로 서명된 cert**를 서빙한다. K3s 자신이 자기 API 서버에 접속할 때 새 trust bundle을 사용하는데, 서버가 옛 CA cert를 내밀다 보니 self-handshake가 무한 실패하는 것이다.

```
k3s: Failed to validate connection: CA cert validation failed:
  tls: failed to verify certificate: x509: certificate signed by unknown authority
```

2초 간격으로 무한 반복.

## 해결 시도들이 왜 다 실패했나

처음에 시도한 두 가지:

1. `dynamic-cert.json` 삭제 후 K3s 재시작
   → K3s가 kine(sqlite) 안의 `kube-system/k3s-serving` secret에서 **옛 cert를 복원**
2. `k3s-serving` secret 삭제 후 K3s 재시작
   → K3s가 `dynamic-cert.json`에서 **옛 cert를 복원**

두 소스가 서로를 복원하는 루프다. **둘 다 동시에** 없애야 했다.

그리고 여기서 내가 저지른 실수가 하나 더 있었다.

### sudo 없이 root 디렉토리를 ls하면

```bash
ls /var/lib/rancher/k3s/server/tls/dynamic-cert.json 2>/dev/null \
  && echo "exists" || echo "missing"
```

이 명령의 출력: **`missing`**

실제 파일: **존재함**

`/var/lib/rancher/k3s/server/tls/`는 `rwx------`(root 전용)이다. sudo 없이 접근하면 `permission denied`가 나오고, `2>/dev/null`로 stderr를 버리면 `missing`처럼 보인다. 파일이 없는 게 아니라 볼 수 없는 것인데, 없다고 판단해버렸다.

이것 때문에 동일한 루프를 몇 번이나 반복했다.

## 실제 해결

K3s 업그레이드(v1.34.5 → v1.34.6, #13006 fix 포함) 후:

1. K3s 중단
2. `sudo rm /var/lib/rancher/k3s/server/tls/dynamic-cert.json`
3. kine sqlite에서 `k3s-serving` 항목 직접 삭제

   ```python
   # sqlite3 바이너리가 없어서 python3으로
   import sqlite3
   conn = sqlite3.connect("/var/lib/rancher/k3s/server/db/state.db")
   cur = conn.cursor()
   cur.execute("DELETE FROM kine WHERE name LIKE '/registry/secrets/kube-system/k3s-serving%'")
   conn.commit()
   ```

4. K3s 재시작

결과:

```
issuer=CN = k3s-server-ca@1775650938  ✅ (새 CA)
```

K3s `active`, 두 노드 모두 `Ready`.

## 한 가지 더 — SA token과 metrics-server

CA 회전 후 metrics-server가 kubelet scraping에 실패했다.

```
Failed to scrape node: tls: failed to verify certificate:
  x509: certificate signed by unknown authority
```

원인은 metrics-server pod가 들고 있는 **Service Account token의 CA bundle**이 구버전이라 새 cert를 신뢰하지 못하는 것. rolling restart 한 번으로 해결됐다.

CA를 회전하면 `kube-apiserver`와 직접 통신하는 pod들(특히 metrics-server, cert-manager 등)은 rolling restart가 필요하다.

## 정리

| 교훈 | 내용 |
|------|------|
| `.gitignore`는 glob으로 | `kubeconfig` → `*kubeconfig*` |
| Kubernetes CRL 미지원 | 노출 cert 무효화 = CA 교체가 유일한 방법 |
| cert 소스는 항상 복수 | `dynamic-cert.json` + sqlite, 둘 다 제거해야 |
| sudo 빠진 ls 결과 믿지 말 것 | permission denied ≠ 파일 없음 |
| CA 회전 후 rolling restart | SA token CA bundle 갱신 필요 |

보안 사고 자체는 6443 포트가 외부에 막혀 있어 실질적 피해 가능성이 낮았다. 하지만 WireGuard VPN이 뚫렸다면 즉시 cluster-admin이 되는 구조였으니 운이 좋았다고 봐야 한다.

다음엔 `git-secrets` 또는 `gitleaks`를 pre-commit hook에 달아두는 걸 검토해봐야겠다.
