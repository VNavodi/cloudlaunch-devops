# Production image for the Express REST API.
FROM node:24-alpine AS dependencies

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node backend/ ./backend/

USER node
EXPOSE 3000
CMD ["node", "backend/src/server.js"]
