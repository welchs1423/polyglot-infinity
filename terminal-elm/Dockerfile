FROM node:22-alpine AS builder

RUN npm install --global --silent elm@0.19.1

WORKDIR /app
COPY elm.json .
COPY src/ ./src/
RUN elm make src/Main.elm --output=elm.js --optimize


FROM nginx:1.27-alpine

WORKDIR /usr/share/nginx/html
COPY --from=builder /app/elm.js .
COPY index.html .

EXPOSE 80
