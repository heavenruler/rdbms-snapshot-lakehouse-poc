# Validation record

## Run

- Date: 2026-07-20 (Asia/Taipei)
- Host: macOS arm64 with Colima
- Trino: 483
- Apache Iceberg library: 1.11.0
- Restore worker: MySQL 8.4
- Object storage: Floci S3 emulator
- Catalog: PostgreSQL 17, Iceberg JDBC catalog schema V0

Command:

```bash
./scripts/run-poc.sh
```

Result: passed.

## Assertions

```text
Distinct history versions: 6
Latest/current rows:        2
Duplicate (PK, row_hash):   0
Iceberg snapshots:          6
```

The identical 2005-01-09 snapshot produced `INSERT: 0 rows`. Source schema
evolution added `email` on 2005-01-16 and removed `city` on 2005-01-23. The
unified Iceberg result returned absent columns as `NULL`.

## Verified history result

```text
id   name   city       email               valid_from  valid_to    source_snapshot
101  Amy    Taipei                         2005-01-02  2005-01-16  2005-01-02
101  Amy    Taichung   amy@example.test    2005-01-16  2005-01-23  2005-01-16
101  Amy               amy@example.test    2005-01-23  NULL        2005-01-23
102  Bob    Tainan                         2005-01-02  2005-01-23  2005-01-02
102  Bobby                                     2005-01-23  NULL        2005-01-23
103  Carol  Kaohsiung  carol@example.test  2005-01-16  2005-01-23  2005-01-16
```

## Verified current result

```text
id   name   city  email
101  Amy          amy@example.test
102  Bobby
```

## Storage evidence

Floci S3 contained all expected Iceberg artifacts below the table prefix:

```text
s3://lakehouse/warehouse/history/table1_history-<uuid>/data/*.parquet
s3://lakehouse/warehouse/history/table1_history-<uuid>/metadata/*.metadata.json
s3://lakehouse/warehouse/history/table1_history-<uuid>/metadata/*.avro
```

This proves the result is an Iceberg table backed by Parquet and metadata files,
not merely rows left in the temporary MySQL worker.

## Compatibility findings

- Floci S3 accepted Trino Iceberg atomic metadata and data-file writes.
- Iceberg JDBC catalog V0 requires explicit base-table initialization with this
  Trino/Iceberg combination.
- JDBC catalog V0 does not support views and even schema-drop paths can enumerate
  views. The PoC therefore keeps the namespace, explicitly recreates its two
  tables, and materializes `table1` from active `table1_history` rows.
- Production Athena/Glue behavior remains a separate validation gate.
