FROM node:24-bookworm-slim AS frontend
WORKDIR /app
RUN npm install -g elm@0.19.2-0
COPY elm.json ./
COPY src ./src
RUN elm make src/Main.elm --optimize --output=elm.js
RUN mkdir -p public
RUN elm make src/Account.elm --optimize --output=public/account-elm.js
RUN elm make src/RecordBrowser.elm --optimize --output=public/record-browser-elm.js
RUN elm make src/WorkDashboard.elm --optimize --output=public/work-dashboard-elm.js

FROM golang:1.26-bookworm AS backend
WORKDIR /app/golang-backend
COPY golang-backend/go.mod golang-backend/go.sum ./
RUN go mod download
COPY golang-backend ./
RUN CGO_ENABLED=1 go build -trimpath -o /app/ecc-crm .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates sqlite3 python3 qrencode zbar-tools poppler-utils && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --create-home crm
WORKDIR /app
COPY --from=backend /app/ecc-crm /app/build/ecc-crm
COPY --from=frontend /app/elm.js /app/elm.js
COPY index.html ./
COPY manifest.webmanifest ./
COPY public ./public
COPY --from=frontend /app/public/account-elm.js /app/public/account-elm.js
COPY --from=frontend /app/public/record-browser-elm.js /app/public/record-browser-elm.js
COPY --from=frontend /app/public/work-dashboard-elm.js /app/public/work-dashboard-elm.js
COPY scripts ./scripts
RUN mkdir /app/data && chown crm:crm /app/data
USER crm
ENV PORT=7000 DATABASE_PATH=/app/data/crm.sqlite3 ALLOW_SIGNUP=false
EXPOSE 7000
VOLUME ["/app/data"]
HEALTHCHECK --interval=30s --timeout=5s CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7000/api/health',timeout=3)" || exit 1
CMD ["/app/build/ecc-crm"]
