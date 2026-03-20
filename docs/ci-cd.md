# CI/CD

## 구조

```
[git push to main] → [GitHub Actions (self-hosted runner)] → [docker buildx 멀티아키텍처] → [ghcr.io push] → [kubectl apply + set image]
```

## Self-Hosted Runner

- **이미지:** myoung34/github-runner:latest
- **노드:** Ryzen (Docker socket 마운트)
- **라벨:** kloud, self-hosted, linux, amd64
- **인증:** GITHUB_PAT (fine-grained, repo + write:packages)
- **매니페스트:** `cluster/ci/runner/`

## 워크플로우

### sample-app (`.github/workflows/deploy.yml`)
- **트리거:** push to main, paths: `apps/sample-app/**`, `cluster/apps/sample-app/**`
- **빌드:** docker buildx (linux/amd64, linux/arm64) → ghcr.io/ch4n33/sample-app
- **배포:** kubectl apply + set image

### blog (`.github/workflows/deploy-blog.yml`)
- **트리거:** push to main, paths: `apps/blog/**`, `cluster/apps/blog/**`
- **빌드:** docker buildx (linux/amd64, linux/arm64) → ghcr.io/ch4n33/blog
- **배포:** kubectl apply + set image
- **참고:** checkout에 `submodules: true` 필수 (PaperMod 테마)

## 이미지 레지스트리

ghcr.io 사용. Ryzen에서 `gh auth login` + `docker login ghcr.io` 완료.

- ghcr.io/ch4n33/sample-app
- ghcr.io/ch4n33/blog

## 새 앱 추가 시

1. `apps/<app-name>/` 에 소스 + Dockerfile 작성
2. `cluster/apps/<app-name>/` 에 deployment, service, ingress 작성
3. `.github/workflows/deploy-<app-name>.yml` 작성 (기존 워크플로우 복사 후 수정)
4. 멀티아키텍처 이미지 필수 (`platforms: linux/amd64,linux/arm64`)
