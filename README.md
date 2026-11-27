# DBMS-Oracle

Can Oracle PL/SQL code run on MariaDB? MariaDB has an Oracle compatibility mode (`sql_mode=ORACLE`), and this project tests how far it really goes. I took two real Oracle schemas, ran them on MariaDB, fixed what broke, and wrote down every change, why it was needed, and how I checked that the result still behaves like Oracle.

The two schemas:

- **LMS**, a Library Management System with tables, triggers, procedures, functions and views.
- **HR**, Oracle's own Human Resources sample schema, which is mostly tables, constraints and a lot of data.

## Folder layout

```
config/    MariaDB settings that make it behave more like Oracle
corpus/    the SQL code
  oracle/    the original Oracle code, unchanged
  mariadb/   the same code after migration
docs/      the findings (start here)
tools/     Python scripts that load the code and run the tests
tests/     the test cases, with the result Oracle would give for each
results/   saved output of the runs the docs refer to
```

## Part 2: Migration and compatibility (Person 2)

**Status: finished.** Both schemas run on MariaDB 11.8 and 13.0, and every test case gives the same answer Oracle would.

This part takes the Oracle code in `corpus/oracle/`, migrates it to MariaDB in `corpus/mariadb/`, and checks the result. Every changed line in the migrated code has a `-- MIGRATION:` comment that says what changed and why, so you can open any file and see the reason next to the change. `results/diffs/` holds the full side-by-side difference between the original and the migrated code.

### What it found

| | LMS | HR |
|---|---|---|
| Schema objects | 39 | 32 |
| Run on MariaDB without any change | 29 | 16 |
| Needed a change | 10 | 15 |
| No MariaDB equivalent | 0 | 1 |
| Test cases passing (MariaDB 11.8 and 13.0) | 62 / 62 | 57 / 57 |
| Test cases giving a wrong answer with only `sql_mode=ORACLE` set | 7 | 6 |

The last row is the most important result. With only `sql_mode=ORACLE` switched on, some queries quietly return a different answer than Oracle would, with no error at all. Examples: an empty string is not treated as NULL, `'student'` and `'STUDENT'` count as the same value, and a number that is too large is silently cut down. A few extra server settings fix these, and they are collected in `config/mariadb-oracle.cnf`. Other differences, such as date arithmetic counting seconds instead of days, can only be fixed by changing the code, and the migrated code does that.

### What had to change

Most of the PL/SQL (procedures, functions, triggers, cursors, exceptions) ran as it was. The changes were mostly in table definitions and a few built-in functions:

- **Missing built-ins.** `RAISE_APPLICATION_ERROR` does not exist, so a small replacement procedure was added that raises the same error. `TO_DATE` does not exist either, so the HR data uses plain date values instead.
- **Constraints.** MariaDB does not accept a name on an inline `NOT NULL`, a foreign key without a column list, or a primary key and a self-referencing foreign key in the same statement. These were rewritten in the form MariaDB accepts.
- **Table options with no equivalent.** `ORGANIZATION INDEX` was removed (MariaDB tables are already stored by primary key), and `COMMENT ON` became a comment inside the table definition.
- **Turning constraints off and on.** Oracle can disable a foreign key while loading data. In MariaDB the foreign key is dropped and added again, which also checks that every row is still valid.
- **Views and session settings.** `WITH READ ONLY` became a view that cannot be updated, and the Oracle date-language setting became `lc_time_names`. `TO_CHAR(date, 'DY')` returns `Sat` instead of `SAT`, so it is wrapped in `UPPER()`.
- **One object with no equivalent.** HR's `secure_employees` trigger is installed switched off in Oracle. MariaDB cannot switch a trigger off, so it is not created, which gives the same behaviour. The rewritten version is in the file, commented out, for anyone who wants it switched on.

### Settings to use

Set these on the MariaDB server (they are all in `config/mariadb-oracle.cnf`):

```ini
sql_mode = ORACLE,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,EMPTY_STRING_IS_NULL
autocommit = 0
character_set_server = utf8mb4
collation_server = utf8mb4_nopad_bin
```

Without them, the migrated code still runs, but some answers differ from Oracle's (the last row of the table above).

### What it was tested with

- **Probes:** 125 small tests, each checking one Oracle feature on its own, so every failure has a clear cause. The results are in `results/probes/`.
- **Test cases:** 62 for LMS and 57 for HR in `tests/`. Each case loads the migrated code into a fresh database and compares the result with what Oracle would return. The cases cover normal input, NULL, empty strings, limits, and every error the code can raise.
- **Two MariaDB versions:** 11.8, the long-term-support version the project is pinned to, and 13.0, the latest, to see which gaps close in newer releases. Both give the same results.

### Limits

- The expected answers come from Oracle's documented behaviour. The code was not also run on a real Oracle database, which is planned as part of the project setup (Part 1).
- `BULK COLLECT`, `FORALL`, autonomous transactions and object types have no MariaDB equivalent. Neither schema uses them, but they are listed in the feature table in `docs/COMPATIBILITY_MATRIX.md` for anyone migrating other code.

### Where to read more

- [`docs/COMPATIBILITY_MATRIX.md`](docs/COMPATIBILITY_MATRIX.md): every object, what happened to it, and how it was tested. It ends with a feature table that is useful for any Oracle to MariaDB migration.
- [`docs/SILENT_DIFFERENCES.md`](docs/SILENT_DIFFERENCES.md): the cases where MariaDB gives a different answer without an error, and how to avoid each one.
- [`docs/MIGRATION_GUIDE.md`](docs/MIGRATION_GUIDE.md): how the work was done, and how to migrate another schema the same way.

### How to run it

You need Docker, Python 3 and `make`.

```sh
make setup        # create the Python environment
make mariadb      # start MariaDB 11.8 (port 3307) and 13.0 (port 3308) in Docker

make check        # LMS: load the migrated code and run all 62 test cases
make check-hr     # HR: load the migrated code and run all 57 test cases

make verify-naive     # LMS test cases with only sql_mode=ORACLE, to see the wrong answers
make verify-hr-naive  # the same for HR
```

`make probe` re-runs the 125 feature probes, and `make baseline` / `make baseline-hr` show how much of the original Oracle code runs before any migration.

## License

MIT, see [`LICENSE`](LICENSE). The HR sample schema in `corpus/oracle/hr/` is published by Oracle under the MIT license; its own notice is in that folder.
