FROM node:20-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
COPY prisma ./prisma
RUN npm install --include=dev

COPY . .
RUN npx prisma generate && npm run build

ENV NODE_ENV=production
CMD npx prisma migrate deploy && node dist/main
