FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download || true
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates && adduser -D -u 1000 app
WORKDIR /app
COPY --from=builder /out/server /app/server
RUN mkdir -p /app/uploads && chown -R app /app
USER app
ENV UPLOAD_DIR=/app/uploads
VOLUME /app/uploads
EXPOSE 8080
ENTRYPOINT ["/app/server"]
