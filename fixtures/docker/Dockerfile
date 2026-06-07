# Tiny multi-arch fixture used by the smoke workflow.
# Distroless static — no shell, no package manager, builds for both amd64 and arm64.
FROM gcr.io/distroless/static:nonroot

ARG BUILD_VERSION=dev
LABEL org.opencontainers.image.title="github-actions-templates-smoke" \
      org.opencontainers.image.description="Smoke fixture for the _docker-buildx reusable workflow" \
      org.opencontainers.image.source="https://github.com/aleksandar-chapkanov/github-actions-templates" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${BUILD_VERSION}"

USER nonroot:nonroot

ENTRYPOINT ["/no-op"]
