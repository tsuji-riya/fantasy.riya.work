# ファイルを集めるだけなので、ビルド機のアーキテクチャで動かす (arm64 用でも QEMU 不要)
FROM --platform=$BUILDPLATFORM node:25-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
# 全コア入りの @emulatorjs/cores は数百 MB あるので入れず、FBNeo だけ使う
RUN npm ci --omit=optional --ignore-scripts
COPY site/ /out/
RUN cp -r node_modules/@emulatorjs/emulatorjs/data /out/data \
 && cp -r node_modules/@emulatorjs/core-fbneo/. /out/data/cores/

# 配信用サーバーは Go 標準ライブラリだけで自作する (server/)。
# 静的リンクなので実行イメージは scratch にバイナリだけを入れられる。
FROM --platform=$BUILDPLATFORM golang:1.27-alpine@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280 AS server
WORKDIR /src
COPY server/ ./
ARG TARGETOS TARGETARCH
RUN go test ./... \
 && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags='-s -w -buildid=' -o /server .

# distroless ですらなく scratch。OS パッケージもシェルもライブラリも無いので、
# nginx + Alpine に付いていた脆弱性 (code scanning 72 件) が丸ごと消える。
FROM scratch
COPY --from=server /server /server
COPY --from=build /out /srv/
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/server"]
