# --- STAGE 1: Build GitHub MCP (Go) ---
FROM golang:1.25-alpine AS github-builder
RUN go install github.com/github/github-mcp-server/cmd/github-mcp-server@latest

# --- STAGE 2: Build Supadata MCP from Source (Node) ---
FROM node:23-slim AS supadata-builder
WORKDIR /app
RUN apt-get update && apt-get install -y git
RUN git clone https://github.com/supadata-ai/mcp.git .
RUN npm install && npm run build:stdio

# --- STAGE 3: Final Production Image ---
FROM node:23-slim

# 1. Set the PATH for all tools
ENV PATH="/root/.local/bin:/usr/local/bin:$PATH"

# 2. Install System Essentials
RUN apt-get update && \
    apt-get install -y python3 python3-pip ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

# 3. Install Python Tool Manager (uv)
RUN pip3 install uv --break-system-packages 

# 4. BAKE IN: GitHub MCP Server (from Stage 1)
COPY --from=github-builder /go/bin/github-mcp-server /usr/local/bin/github-mcp-server
RUN chmod +x /usr/local/bin/github-mcp-server

# 5. BAKE IN: Supadata MCP Server (from Stage 2)
WORKDIR /opt/supadata-mcp
COPY --from=supadata-builder /app/dist ./dist
COPY --from=supadata-builder /app/node_modules ./node_modules
COPY --from=supadata-builder /app/package.json ./package.json

# Create the Supadata wrapper script
# This automatically sets RUN_STDIO=true as required by the package
RUN echo '#!/bin/sh\nexport RUN_STDIO=true\ncd /opt/supadata-mcp && node dist/index.js "$@"' > /usr/local/bin/supadata-mcp && \
    chmod +x /usr/local/bin/supadata-mcp

# 6. BAKE IN: Office Word & PowerPoint (Python)
RUN uv tool install office-word-mcp-server && \
    uv tool install office-powerpoint-mcp-server

# 7. Setup TypingMind Connector (Your Main App)
WORKDIR /app
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod
COPY . .

# Set the default port for Cloud Run
ENV PORT=50880
EXPOSE 50880

# Define the command to run the app
# (Ensure bin/index.js is the correct path for your specific connector version)
CMD ["node", "bin/index.js"]
