# Stage 1: Install production dependencies
FROM node:24-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev


# Stage 2: Production runtime
FROM node:24-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production

COPY --from=builder --chown=node:node /app/node_modules ./node_modules

COPY --chown=node:node package*.json ./
COPY --chown=node:node src/ ./src/

# npm is not needed to run our Node.js application
RUN rm -rf /usr/local/lib/node_modules/npm \
    /usr/local/lib/node_modules/corepack \
    /opt/yarn-v1.22.22

USER node

EXPOSE 3000

CMD ["node", "src/server.js"]