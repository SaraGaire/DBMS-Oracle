# Migration guide: Oracle → MariaDB compatibility work (Person 2)

What happened to each object of `corpus/oracle/lms` and `corpus/oracle/hr` when it ran on MariaDB under `sql_mode=ORACLE`, with the evidence.

| File | What it is |
|---|---|
| [`COMPATIBILITY_MATRIX.md`](COMPATIBILITY_MATRIX.md) | **The deliverable.** One row per object (unchanged / rewritten / no equivalent), the change, why, and how it was verified. Also a feature matrix for 11.8 vs 13.0. |
| [`SILENT_DIFFERENCES.md`](SILENT_DIFFERENCES.md) | Differences that return wrong results without an error: NULL vs `''`, date arithmetic, autocommit, collation, strict mode, NUMBER→DOUBLE, error codes. Source material for the migration guide. |
| [`config/mariadb-oracle.cnf`](../config/mariadb-oracle.cnf) | Server settings that remove those differences. Mount into the MariaDB container. |
| [`results/diffs/lms.diff`](../results/diffs/lms.diff), [`results/diffs/hr.diff`](../results/diffs/hr.diff) | `diff -ru corpus/oracle/<name> corpus/mariadb/<name>`: the full migration effort per corpus. |
| `tools/run_objects.py` | Loads `.sql` files statement by statement (SQL*Plus `/` rules) in one session and reports each object's result. |
| `tools/probe_features.py` | 125 isolated probes, one per Oracle feature, with the Oracle-documented result next to MariaDB's. |
| `tools/verify_objects.py` + `tests/cases_lms.json`, `tests/cases_hr.json` | 62 LMS + 57 HR object-level cases (inputs, NULLs, `''`, boundaries, every error path). Each case runs on a fresh load. Cases are data, so the harness can reuse them. A cases file names its corpus and load order (`"corpus"`, `"load"`); without them it means LMS. |
| `results/probes/`, `results/verify/results_*.json` | Saved outputs of the runs the matrix cites. |

## Reproduce

```sh
# MariaDB 11.8 (pinned target) and 13.0 (latest, for the version watch)
docker run -d --name lms-mariadb    -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=lms -p 3307:3306 mariadb:11.8
docker run -d --name lms-mariadb-13 -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=lms -p 3308:3306 mariadb:13.0
python3 -m venv .venv && .venv/bin/pip install pymysql==1.1.1

# 1. Baseline: the UNCHANGED Oracle files, plain sql_mode=ORACLE
.venv/bin/python tools/run_objects.py --reset --sql-mode ORACLE --autocommit 1 --collation default --quiet \
  corpus/oracle/lms/02_schema.sql corpus/oracle/lms/03_plsql.sql corpus/oracle/lms/04_data.sql corpus/oracle/lms/05_views.sql corpus/oracle/lms/06_queries.sql

# 2. Feature probes (uses docker exec; MDB_CONTAINER picks the server)
python3 tools/probe_features.py --md results/probes/features_oracle_mode.md
python3 tools/probe_features.py --extra-mode EMPTY_STRING_IS_NULL --md results/probes/features_oracle_esin.md
MDB_CONTAINER=lms-mariadb-13 python3 tools/probe_features.py --md results/probes/features_oracle_mode_13.0.md

# 3. Load the migrated corpus (recommended settings are the defaults)
.venv/bin/python tools/run_objects.py --reset corpus/mariadb/lms/0*.sql

# 4. Verify: 62/62 expected; naive settings give 55/62; 13.0 gives 62/62
.venv/bin/python tools/verify_objects.py
.venv/bin/python tools/verify_objects.py --sql-mode ORACLE --collation default --autocommit 1
MDB_PORT=3308 .venv/bin/python tools/verify_objects.py
```

Connection settings come from the environment: `MDB_HOST`, `MDB_PORT` (3307), `MDB_USER`, `MDB_PASSWORD`, `MDB_DATABASE`.

The same steps are available as `make baseline`, `make probe`, `make load`, `make verify`, `make verify-naive` and `make verify-latest`. Run `make check` before each commit.

For HR (database `hr`): `make baseline-hr`, `make load-hr`, `make verify-hr` (57/57), `make verify-hr-naive` (51/57), `make verify-hr-latest`, and `make check-hr` before each commit.

## Continuing the work

Every rule below keeps `diff -ru corpus/oracle/<name> corpus/mariadb/<name>` an honest record of the migration.

**Migrating a new corpus or file** (done: `lms`, `hr`):
1. Person 1 puts it in `corpus/oracle/<name>/` unchanged. Copy it to `corpus/mariadb/<name>/` with the same file names.
2. Run it through `run_objects.py` with the baseline settings (as `make baseline` does for `lms`) to see what fails as-is. For each failure, find or add a probe that isolates the feature (below) before changing code.
3. Make the smallest change that works, with a `-- MIGRATION: <what> (<why>)` comment above it. If the same Oracle built-in is used in several places, add a shim to `00_compat.sql` instead of editing each call.
4. Add cases for the object to `tests/cases_lms.json` (or a new `tests/cases_<name>.json` with `"corpus"` and `"load"` keys): happy path, NULL, `''`, a boundary, and every error it can raise.
5. Add or update the object's row in `COMPATIBILITY_MATRIX.md`, and update the headline counts.

**Adding a probe:** append a tuple to `PROBES` in `tools/probe_features.py`: `(id, feature, used_in, script, oracle_expected)`. The script uses `$$` between statements. Probes added for HR are at the end of the list. IDs: `T` types/DDL, `F` functions, `P` PL/SQL, `R` triggers, `D` dictionary, `N` NULL/numeric semantics, `X` features not in the corpus.

**Adding a case:** add an object to `cases` in `tests/cases_lms.json`. No code changes are needed; the format is described in its `_doc` field.

**Changing the pinned version:** set `MDB_VER`/`LATEST` in the Makefile, then run `make probe verify verify-latest` and update the 11.8/13.0 columns of the feature matrix. A gap that closes in a new release is a result worth recording.

## Commit convention

One logical part per commit, prefixed by area, so the history can be pushed and reviewed piece by piece:
`corpus:` (Oracle source), `migrate:` (corpus/mariadb/), `probe:`, `verify:`, `tools:`, `docs:`. Commit generated outputs (`results/probes/`, `results/verify/results_*.json`, `results/diffs/*.diff`) together with the change that produced them.

## Hand-offs

- **Person 1 (environment):** pin `mariadb:11.8` and mount `config/mariadb-oracle.cnf`. HR's `hr_install.sql`/`hr_uninstall.sql` (Oracle user + tablespace) were not ported; in MariaDB that is `CREATE DATABASE hr` and a user granted on it. The `mariadb` target in the Makefile is a placeholder to replace with the real setup (compose file, Oracle container, healthchecks). The loader needs `requirements.txt`. The Oracle originals live only in `corpus/oracle/<name>/`; the LMS corpus is in `corpus/oracle/lms/`, next to `hr/`.
- **Person 3 (harness and guide):** `tests/cases_lms.json` and `tests/cases_hr.json` already hold inputs and Oracle-expected results per object, so run the same cases against the Oracle container. See "Notes for the team" in the matrix for non-deterministic queries and the normalisation needed. `SILENT_DIFFERENCES.md` §1 is the guide's NULL section.
