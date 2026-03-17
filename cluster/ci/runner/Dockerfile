# Self-hosted GitHub Actions Runner with Docker CLI + kubectl
# 부트스트랩용: Ryzen에서 수동 빌드 후 ghcr.io에 push
#   docker build -t ghcr.io/ch4n33/kloud-runner:latest .
#   docker push ghcr.io/ch4n33/kloud-runner:latest
FROM ghcr.io/actions/actions-runner:latest

USER root

# Docker CLI + buildx (이미지 빌드용, Docker daemon은 호스트 소켓 마운트로 사용)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli docker-buildx-plugin && \
    rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# PAT 기반 자동 등록 entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
