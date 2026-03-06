#!/bin/bash
set -euo pipefail

VERSION="$1"
MAJOR="${VERSION%%.*}"
IMAGE="raudssus/codefork"

echo "Building ${IMAGE}:${VERSION}..."
docker build -t "${IMAGE}:${VERSION}" -t "${IMAGE}:${MAJOR}" -t "${IMAGE}:latest" .

echo "Pushing ${IMAGE}:${VERSION}, :${MAJOR}, :latest..."
docker push "${IMAGE}:${VERSION}"
docker push "${IMAGE}:${MAJOR}"
docker push "${IMAGE}:latest"

echo "Done: ${IMAGE}:${VERSION}, ${IMAGE}:${MAJOR}, ${IMAGE}:latest pushed."
