# Static SPA build (ssr: false) served by nginx.
# Public runtime values are baked in at build time:
#   docker build --build-arg SUPABASE_URL=... --build-arg SUPABASE_KEY=... --build-arg PARSER_URL=... .
FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.31.0 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
ARG SUPABASE_URL
ARG SUPABASE_KEY
ARG PARSER_URL
ENV SUPABASE_URL=$SUPABASE_URL SUPABASE_KEY=$SUPABASE_KEY PARSER_URL=$PARSER_URL
RUN pnpm generate

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/.output/public /usr/share/nginx/html
EXPOSE 80
