FROM node:22.16.0-alpine3.22@sha256:41e4389f3d988d2ed55392df4db1420ad048ae53324a8e2b7c6d19508288107e
WORKDIR /app
COPY --chmod=644 package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --chown=node:node . .
ARG APP_REVISION=dev
LABEL org.opencontainers.image.revision=$APP_REVISION
ENV NODE_ENV=production PORT=3000
USER 1000:1000
HEALTHCHECK --interval=5s --timeout=3s --start-period=15s --retries=12 CMD node -e "fetch('http://127.0.0.1:3000/health/ready').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
STOPSIGNAL SIGTERM
CMD ["node", "src/index.js"]
