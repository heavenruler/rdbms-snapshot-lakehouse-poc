#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 '<SQL>'" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${DOCKER_HOST:-}" ]]; then
  detected_docker_host="$(docker context inspect colima --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  [[ -n "$detected_docker_host" ]] && export DOCKER_HOST="$detected_docker_host"
fi
export DOCKER_CONFIG="${DOCKER_CONFIG:-$project_dir/docker-config}"
docker-compose --project-directory "$project_dir" exec -T trino \
  trino --server http://localhost:8080 --output-format ALIGNED --execute "$1"
