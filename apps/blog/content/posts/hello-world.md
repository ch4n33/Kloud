---
title: "블로그를 시작합니다"
date: 2026-03-20
summary: "K3s 홈 클라우드에서 호스팅하는 블로그의 첫 글입니다."
tags: ["blog", "k3s", "homelab"]
---

K3s 홈 클라우드 클러스터에 Hugo 블로그를 배포했습니다.

## 구성

이 블로그는 다음과 같이 운영됩니다:

- **Hugo** 정적 사이트 생성기로 빌드
- **nginx** 컨테이너에서 서빙
- **K3s** 클러스터의 Raspberry Pi 노드에서 실행
- **Traefik** + **cert-manager**로 HTTPS 자동 인증서 발급
- **GitHub Actions**로 CI/CD 자동 배포

코드를 push하면 자동으로 멀티아키텍처 이미지가 빌드되고 클러스터에 배포됩니다.
