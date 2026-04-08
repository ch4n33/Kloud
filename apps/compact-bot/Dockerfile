FROM node:20-bookworm
ARG TARGETARCH

# 기본 CLI 도구 + 빌드 환경 + sudo + kubectl + gh
# kubectl/gh는 멀티아키 (TARGETARCH로 분기)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates tini sudo curl wget \
      jq less vim-tiny nano \
      python3 python3-pip python3-venv python3-dev \
      build-essential \
      openssh-client rsync procps htop \
      gnupg lsb-release \
    && curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl" \
         -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI + Compact-Bot 글로벌 설치 (node-pty native 모듈 컴파일)
RUN npm install -g --omit=optional \
      @anthropic-ai/claude-code \
      @serin511/compact-bot

# node 베이스 이미지에 이미 'node' 사용자(uid 1000) 존재 → 재사용
# 홈 디렉토리를 /claude-home으로 이동, sudo NOPASSWD 부여
# uid 1000은 호스트 ch4n33와 동일 → hostPath 권한 호환
RUN usermod -d /claude-home -m node \
    && echo "node ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node \
    && mkdir -p /app /workspace /opt/cli/bin \
    && chown -R node:node /app /workspace /claude-home /opt/cli

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node
WORKDIR /app
ENV HOME=/claude-home \
    PATH=/opt/cli/bin:/claude-home/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
