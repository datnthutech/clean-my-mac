#!/usr/bin/env bash
# Runs the DiskKit tests inside the official Swift Docker image (works on Linux or any Docker host).
set -euo pipefail
cd "$(dirname "$0")/.."
docker run --rm -v "$PWD":/src -w /src/Packages/DiskKit swift:6.1-noble swift test
