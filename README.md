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

This part takes the Oracle code in `corpus/oracle/`, migrates it to MariaDB 11.8 in `corpus/mariadb/`, and checks the result. Every changed line in the migrated code has a `-- MIGRATION:` comment that says what changed and why.

**What it found**

| | LMS | HR |
|---|---|---|
| Schema objects | 39 | 32 |
| Run on MariaDB without any change | 29 | 16 |
| Needed a change | 10 | 15 |
| No MariaDB equivalent | 0 | 1 |
| Test cases passing (MariaDB 11.8 and 13.0) | 62 / 62 | 57 / 57 |
| Test cases giving a wrong answer with only `sql_mode=ORACLE` set | 7 | 6 |

The last row is the most important result. With only `sql_mode=ORACLE` switched on, some queries quietly return a different answer than Oracle would, with no error at all. Examples: an empty string is not treated as NULL, `'student'` and `'STUDENT'` count as the same value, and a number that is too large is silently cut down. A few extra server settings fix these, and they are collected in `config/mariadb-oracle.cnf`. Other differences, such as date arithmetic counting seconds instead of days, can only be fixed by changing the code, and the migrated code does that.

**Where to read more**

- [`docs/COMPATIBILITY_MATRIX.md`](docs/COMPATIBILITY_MATRIX.md): every object, what happened to it, and how it was tested. It ends with a feature table that is useful for any Oracle to MariaDB migration.
- [`docs/SILENT_DIFFERENCES.md`](docs/SILENT_DIFFERENCES.md): the cases where MariaDB gives a different answer without an error, and how to avoid each one.
- [`docs/MIGRATION_GUIDE.md`](docs/MIGRATION_GUIDE.md): how the work was done, and how to migrate another schema the same way.

**How to run it**

You need Docker, Python 3 and `make`.

```sh
make setup        # create the Python environment
make mariadb      # start MariaDB 11.8 (port 3307) and 13.0 (port 3308) in Docker

make check        # LMS: load the migrated code and run all 62 test cases
make check-hr     # HR: load the migrated code and run all 57 test cases

make verify-naive     # LMS test cases with only sql_mode=ORACLE, to see the wrong answers
make verify-hr-naive  # the same for HR
```

`make probe` re-runs the 125 small tests that each check one Oracle feature on its own, and `make baseline` / `make baseline-hr` show how much of the original Oracle code runs before any migration.

## License

MIT, see [`LICENSE`](LICENSE). The HR sample schema in `corpus/oracle/hr/` is published by Oracle under the MIT license; its own notice is in that folder.
