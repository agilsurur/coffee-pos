# syntax=docker/dockerfile:1

# ---- Build stage ----
FROM golang:1.25-alpine AS build
WORKDIR /src

# Download dependency dulu agar layer ini di-cache selama go.mod/go.sum tidak berubah
COPY go.mod go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

# ---- Runtime stage ----
# distroless/static sudah berisi CA certificates (HTTPS ke Midtrans) dan tzdata (Asia/Jakarta untuk laporan)
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/api /app/api

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/api"]
