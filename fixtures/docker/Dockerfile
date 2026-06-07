# Tiny multi-arch fixture used by the smoke workflow.
# alpine:3 is multi-arch and ships /bin/true — keeps the smoke build
# fast and the resulting image actually runnable.
FROM alpine:3

ARG BUILD_VERSION=dev
LABEL org.opencontainers.image.title="github-actions-templates-smoke" \
      org.opencontainers.image.description="Smoke fixture for the _docker-buildx reusable workflow" \
      org.opencontainers.image.source="https://github.com/NoobCoder1209/github-actions-templates" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${BUILD_VERSION}"

CMD ["/bin/true"]
