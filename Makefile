# One command per task. Each team member adds targets in their own section.
PY      := .venv/bin/python
MDB_VER := 11.8
LATEST  := 13.0

.PHONY: setup mariadb load baseline probe verify verify-naive verify-latest diff check \
        load-hr baseline-hr verify-hr verify-hr-naive verify-hr-latest check-hr

setup:
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements.txt

# ---------- Person 1: environment (placeholder until the Oracle container lands) ----------
mariadb:
	docker start lms-mariadb 2>/dev/null || docker run -d --name lms-mariadb -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=lms -p 3307:3306 mariadb:$(MDB_VER)
	docker start lms-mariadb-13 2>/dev/null || docker run -d --name lms-mariadb-13 -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=lms -p 3308:3306 mariadb:$(LATEST)
	@until docker exec lms-mariadb mariadb -uroot -proot -e "select 1" >/dev/null 2>&1; do sleep 2; done; echo "MariaDB $(MDB_VER) ready on 3307"
	@until docker exec lms-mariadb-13 mariadb -uroot -proot -e "select 1" >/dev/null 2>&1; do sleep 2; done; echo "MariaDB $(LATEST) ready on 3308"

# ---------- Person 2: migration and compatibility matrix ----------
load:                     ## migrated corpus into MariaDB 11.8, recommended settings
	$(PY) tools/run_objects.py --reset --quiet corpus/mariadb/lms/0*.sql

baseline:                 ## UNCHANGED Oracle files under plain sql_mode=ORACLE (expected to fail)
	-$(PY) tools/run_objects.py --reset --sql-mode ORACLE --autocommit 1 --collation default --quiet \
	  --json results/probes/baseline_unchanged.json $(filter-out corpus/oracle/lms/01_drop.sql,$(wildcard corpus/oracle/lms/0*.sql))

probe:                    ## one probe per Oracle feature, on 11.8 (two modes) and latest
	python3 tools/probe_features.py --md results/probes/features_oracle_mode.md
	python3 tools/probe_features.py --extra-mode EMPTY_STRING_IS_NULL --md results/probes/features_oracle_esin.md
	MDB_CONTAINER=lms-mariadb-13 python3 tools/probe_features.py --md results/probes/features_oracle_mode_$(LATEST).md

verify:                   ## object-level cases, recommended settings (expect all pass)
	$(PY) tools/verify_objects.py --json results/verify/results_recommended_$(MDB_VER).json

verify-naive:             ## same cases with only sql_mode=ORACLE (shows the silent differences)
	-$(PY) tools/verify_objects.py --sql-mode ORACLE --collation default --autocommit 1 --json results/verify/results_naive_$(MDB_VER).json

verify-latest:
	MDB_PORT=3308 $(PY) tools/verify_objects.py --json results/verify/results_recommended_$(LATEST).json

# The file timestamps diff prints are dropped, so the diffs only change when the SQL does.
NO_TIMES := perl -pe 's/^((?:---|\+\+\+) \S+)\t.*/$$1/'

diff:                     ## regenerate the migration diffs
	diff -ru corpus/oracle/lms corpus/mariadb/lms | $(NO_TIMES) > results/diffs/lms.diff
	diff -ru -x .gitkeep -x README.md -x README.txt -x hr_install.sql -x hr_uninstall.sql \
	  corpus/oracle/hr corpus/mariadb/hr | $(NO_TIMES) > results/diffs/hr.diff

check: load verify verify-latest diff   ## run before every commit to the migration part

# HR sample schema (corpus/oracle/hr -> corpus/mariadb/hr), database 'hr' / 'hr_verify'
HR_ORACLE := $(addprefix corpus/oracle/hr/,hr_create.sql hr_populate.sql hr_code.sql)
HR_LOAD   := $(addprefix corpus/mariadb/hr/,hr_create.sql hr_populate.sql hr_compat.sql hr_code.sql)
HR_CASES  := tests/cases_hr.json

load-hr:                  ## migrated HR schema into MariaDB 11.8, recommended settings
	MDB_DATABASE=hr $(PY) tools/run_objects.py --reset --quiet $(HR_LOAD)

baseline-hr:              ## UNCHANGED Oracle HR files under plain sql_mode=ORACLE (expected to fail)
	-MDB_DATABASE=hr $(PY) tools/run_objects.py --reset --sql-mode ORACLE --autocommit 1 --collation default --quiet \
	  --json results/probes/baseline_hr_unchanged.json $(HR_ORACLE)

verify-hr:
	$(PY) tools/verify_objects.py --cases $(HR_CASES) --json results/verify/results_hr_recommended_$(MDB_VER).json

verify-hr-naive:
	-$(PY) tools/verify_objects.py --cases $(HR_CASES) --sql-mode ORACLE --collation default --autocommit 1 --json results/verify/results_hr_naive_$(MDB_VER).json

verify-hr-latest:
	MDB_PORT=3308 $(PY) tools/verify_objects.py --cases $(HR_CASES) --json results/verify/results_hr_recommended_$(LATEST).json

check-hr: load-hr verify-hr verify-hr-latest diff

# ---------- Person 3: harness and guide ----------
