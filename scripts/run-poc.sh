#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

# Keep this PoC independent from Docker Desktop credential helpers. Public
# images do not need credentials, and Colima may run without the Desktop helper
# binary being present.
if [[ -z "${DOCKER_HOST:-}" ]]; then
  detected_docker_host="$(docker context inspect colima --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  [[ -n "$detected_docker_host" ]] && export DOCKER_HOST="$detected_docker_host"
fi
export DOCKER_CONFIG="${DOCKER_CONFIG:-$project_dir/docker-config}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

compose() {
  docker-compose --project-directory "$project_dir" "$@"
}

trino() {
  compose exec -T trino trino --server http://localhost:8080 \
    --output-format TSV_HEADER --execute "$1"
}

wait_for_services() {
  echo "Waiting for Floci S3..."
  for _ in $(seq 1 60); do
    if aws --endpoint-url http://localhost:4566 s3api list-buckets >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  aws --endpoint-url http://localhost:4566 s3api list-buckets >/dev/null

  echo "Waiting for Trino..."
  for _ in $(seq 1 90); do
    if compose exec -T trino trino --server http://localhost:8080 \
      --execute "SELECT 1" >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  compose exec -T trino trino --server http://localhost:8080 --execute "SELECT 1" >/dev/null
}

restore_fixture() {
  local fixture="$1"
  echo "Restoring $(basename "$fixture") into the temporary MySQL worker..."
  compose exec -T mysql mysql -uroot -ppocroot < "$fixture"
}

current_projection() {
  local has_city="$1"
  local has_email="$2"
  local city_expr="CAST(NULL AS varchar)"
  local email_expr="CAST(NULL AS varchar)"
  [[ "$has_city" == "yes" ]] && city_expr="city"
  [[ "$has_email" == "yes" ]] && email_expr="email"

  cat <<SQL
SELECT
  id,
  name,
  $city_expr AS city,
  $email_expr AS email,
  to_hex(md5(to_utf8(format(
    '%s|%s|%s|%s',
    CAST(id AS varchar),
    COALESCE(name, '<NULL>'),
    COALESCE($city_expr, '<NULL>'),
    COALESCE($email_expr, '<NULL>')
  )))) AS row_hash
FROM mysql.snapshot.table1
SQL
}

apply_snapshot() {
  local snapshot_date="$1"
  local snapshot_id="$2"
  local has_city="$3"
  local has_email="$4"
  local projection
  local insert_columns
  local insert_values
  projection="$(current_projection "$has_city" "$has_email")"

  insert_columns="id, name, city, valid_from, valid_to, source_snapshot, row_hash"
  insert_values="current_rows.id, current_rows.name, current_rows.city, DATE '$snapshot_date', CAST(NULL AS date), '$snapshot_id', current_rows.row_hash"
  if [[ "$has_email" == "yes" ]]; then
    insert_columns="id, name, city, email, valid_from, valid_to, source_snapshot, row_hash"
    insert_values="current_rows.id, current_rows.name, current_rows.city, current_rows.email, DATE '$snapshot_date', CAST(NULL AS date), '$snapshot_id', current_rows.row_hash"
  fi

  echo "Applying observed snapshot $snapshot_id..."

  trino "
MERGE INTO iceberg.history.table1_history AS target
USING (
  WITH current_rows AS ($projection)
  SELECT
    active.id,
    current_rows.row_hash,
    current_rows.id IS NULL AS disappeared
  FROM iceberg.history.table1_history active
  LEFT JOIN current_rows ON current_rows.id = active.id
  WHERE active.valid_to IS NULL
) AS observed
ON target.id = observed.id AND target.valid_to IS NULL
WHEN MATCHED AND (observed.disappeared OR target.row_hash <> observed.row_hash)
  THEN UPDATE SET valid_to = DATE '$snapshot_date'"

  trino "
INSERT INTO iceberg.history.table1_history
  ($insert_columns)
WITH current_rows AS ($projection)
SELECT
  $insert_values
FROM current_rows
LEFT JOIN iceberg.history.table1_history active
  ON active.id = current_rows.id
 AND active.valid_to IS NULL
 AND active.row_hash = current_rows.row_hash
WHERE active.id IS NULL"
}

echo "Starting local Floci, PostgreSQL catalog, MySQL worker, and Trino..."
compose up -d
wait_for_services

# The Iceberg JDBC catalog does not initialize an empty PostgreSQL database in
# every Trino/Iceberg version combination. Apply the exact V0 schema explicitly;
# IF NOT EXISTS keeps reruns safe.
compose exec -T catalog-db psql -U iceberg -d iceberg \
  < "$project_dir/catalog/init.sql" >/dev/null

aws --endpoint-url http://localhost:4566 s3api create-bucket \
  --bucket lakehouse >/dev/null 2>&1 || true

echo "Recreating the Iceberg PoC schema..."
trino "DROP TABLE IF EXISTS iceberg.history.table1"
trino "DROP TABLE IF EXISTS iceberg.history.table1_history"
trino "CREATE SCHEMA IF NOT EXISTS iceberg.history WITH (location = 's3://lakehouse/warehouse/history')"
trino "
CREATE TABLE iceberg.history.table1_history (
  id bigint,
  name varchar,
  city varchar,
  valid_from date,
  valid_to date,
  source_snapshot varchar,
  row_hash varchar
)
WITH (format = 'PARQUET', format_version = 2)"

restore_fixture "$project_dir/fixtures/2005-01-02.sql"
# The source did not have email yet. Iceberg adds it when that source column appears.
apply_snapshot "2005-01-02" "2005-01-02" yes no

restore_fixture "$project_dir/fixtures/2005-01-09.sql"
apply_snapshot "2005-01-09" "2005-01-09" yes no

echo "Applying Iceberg schema evolution: ADD COLUMN email..."
trino "ALTER TABLE iceberg.history.table1_history ADD COLUMN email varchar"

restore_fixture "$project_dir/fixtures/2005-01-16.sql"
apply_snapshot "2005-01-16" "2005-01-16" yes yes

restore_fixture "$project_dir/fixtures/2005-01-23.sql"
apply_snapshot "2005-01-23" "2005-01-23" no yes

trino "DROP TABLE IF EXISTS iceberg.history.table1"
trino "CREATE TABLE iceberg.history.table1
  WITH (format = 'PARQUET', format_version = 2)
  AS SELECT id, name, city, email
  FROM iceberg.history.table1_history
  WHERE valid_to IS NULL"

echo "Running assertions..."
history_count="$(trino "SELECT count(*) AS history_count FROM iceberg.history.table1_history" | tail -n 1 | tr -d '[:space:]')"
active_count="$(trino "SELECT count(*) AS active_count FROM iceberg.history.table1" | tail -n 1 | tr -d '[:space:]')"
duplicate_count="$(trino "
SELECT count(*) AS duplicate_count
FROM (
  SELECT id, row_hash, count(*) AS copies
  FROM iceberg.history.table1_history
  GROUP BY id, row_hash
  HAVING count(*) > 1
)" | tail -n 1 | tr -d '[:space:]')"

[[ "$history_count" == "6" ]] || {
  echo "Expected 6 history versions, got $history_count" >&2
  exit 1
}
[[ "$active_count" == "2" ]] || {
  echo "Expected 2 active rows, got $active_count" >&2
  exit 1
}
[[ "$duplicate_count" == "0" ]] || {
  echo "Expected no duplicate versions, got $duplicate_count" >&2
  exit 1
}

echo
echo "table1_history"
trino "
SELECT id, name, city, email, valid_from, valid_to, source_snapshot
FROM iceberg.history.table1_history
ORDER BY id, valid_from"

echo
echo "table1 (latest observed state)"
trino "SELECT * FROM iceberg.history.table1 ORDER BY id"

echo
echo "PoC passed: 6 distinct history versions, 2 current rows, no duplicates."
