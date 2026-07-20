# Decision record

## Goal

Allow one SQL query to retrieve distinct row versions observed in weekly logical
backups across a requested date range, without repeatedly restoring many backup
sets for each request.

## Agreed decisions

1. Only weekly logical backups are available; binlog CDC is out of scope.
2. History means versions visible at weekly observation points, not every DML.
3. Rows are correlated by each source table's stable primary key.
4. Consecutive identical rows are collapsed using a canonical row hash.
5. History uses half-open `[valid_from, valid_to)` observation intervals.
6. A missing primary key closes the previous interval; no tombstone is emitted.
7. Source schema is unified for querying. A column absent in an older snapshot is
   returned as `NULL`.
8. Each logical table exposes a current object and one history object, such as
   `table1` and `table1_history`.
9. Historical backfill covers all retained years once. The same snapshot-diff
   process can ingest later weekly logical backups.
10. Raw dumps are retained on the existing tape system. During backfill they are
    retrieved once into a temporary S3 raw zone and removed after validation.
11. Dumps are restored through compatible temporary MySQL/MariaDB workers;
    `.sql` is not parsed directly.
12. Long-term query data uses Parquet with Iceberg metadata on S3.

## Important limitation

If a row changes several times and returns to its original value between two
weekly backups, none of those intermediate changes can be reconstructed. This
limitation follows from the available evidence and is not solved by Iceberg.

## PoC-specific choices

- Floci emulates S3 locally.
- Trino validates Iceberg read/write and SQL semantics because Floci Athena reads
  Glue-backed Parquet but does not currently implement full Iceberg behavior.
- PostgreSQL is only the local JDBC Iceberg catalog.
- MySQL 8.4 is the fixture restore worker. Production needs a dump-to-engine
  compatibility inventory and potentially multiple worker versions.

## Cost model to measure after PoC

```text
one-time cost = raw S3 staging byte-days + restore compute + conversion compute
ongoing cost  = compressed Iceberg byte-months + S3 requests + query bytes scanned
```

Do not retain a second permanent raw-dump copy in S3 when tape already provides
the authoritative retained source. Keep compact run metadata, counts, checksums,
and source identifiers instead.
