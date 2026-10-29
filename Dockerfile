# ═══════════════════════════════════════════════════════════════════
#   Mawa Homebazar BD — BACKEND (Express + TypeScript + Socket.IO)
#   Multi-stage build for Coolify / any Docker host.
# ═══════════════════════════════════════════════════════════════════

# ---- Stage 1: build TypeScript -> dist/ ---------------------------
FROM node:20-alpine AS builder
WORKDIR /app

# Install ALL deps (including devDependencies) using the lockfile.
# --include=dev forces dev deps even when Coolify injects NODE_ENV=production
# at build time (otherwise build tools would be skipped and the build fails).
COPY package.json package-lock.json ./
RUN npm ci --include=dev

COPY tsconfig.json ./
COPY src ./src
# Compile straight with tsc instead of `npm run build`, so the build never
# depends on the package.json build script (which may be prefixed with other
# commands). This produces the same dist/ output.
RUN npx tsc


# ---- Stage 2: runtime --------------------------------------------
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=5000

# Production dependencies only.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Compiled output + the thin entry point that requires dist/src/server.js
COPY --from=builder /app/dist ./dist
COPY index.js ./

# Disk-storage uploads land here. Mount a persistent volume on /app/uploads
# in Coolify, otherwise product images are lost on every redeploy.
RUN mkdir -p /app/uploads && chown -R node:node /app/uploads

USER node
EXPOSE 5000

# Coolify reads this for container health; also useful for `docker ps`.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||5000)+'/api/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "index.js"]
