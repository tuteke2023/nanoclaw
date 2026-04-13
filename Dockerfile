FROM node:22-slim

# Install git, Docker CLI, and build tools for native modules
RUN apt-get update && apt-get install -y \
    git \
    curl \
    gnupg \
    python3 \
    make \
    g++ \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy source and config
COPY package*.json ./
COPY tsconfig.json ./
COPY src/ ./src/
COPY groups/ ./groups/
COPY container/ ./container/
COPY scripts/ ./scripts/
COPY setup/ ./setup/

# Install deps (skip husky prepare), build TS, prune to prod
ENV HUSKY=0
RUN npm ci && npm run build && npm prune --omit=dev

# Create required directories
RUN mkdir -p store data groups

EXPOSE 3002

CMD ["node", "dist/index.js"]
