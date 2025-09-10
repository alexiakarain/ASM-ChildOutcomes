* ============================================================================
* Ingest births & initial assessment, prep for linkage, and export to Stata
* Skills: ODBC/SQL ingest, date harmonisation, creating a cut-off window (2009–2022), duplicate
*         detection (LAG), ID hygiene, export to .dta
* NOTE: Replace <SECURE_DSN>, <UID>, <PWD>, <SCHEMA>, <BIRTHS>, <IA>
*       when running inside your secure environment. Keep placeholders on GitHub.
* ============================================================================.

* --- BIRTHS ---
GET DATA
  /TYPE=ODBC
  /CONNECT='DSN=<SECURE_DSN>;UID=<UID>;PWD=<PWD>;DBALIAS=<ALIAS>'
  /SQL='
    SELECT CHILD_ID, MOTHER_ID, BABY_BIRTH_DT, NEONATE_SEX, BIRTH_WEIGHT
    FROM <SCHEMA>.<BIRTHS>
  '.
CACHE.
EXECUTE.

MATCH FILES FILE=* /KEEP=CHILD_ID MOTHER_ID BABY_BIRTH_DT NEONATE_SEX BIRTH_WEIGHT.
EXECUTE.

COMPUTE BABY_BIRTH_DT2 = BABY_BIRTH_DT.
ALTER TYPE BABY_BIRTH_DT2 (DATETIME20).
ALTER TYPE BABY_BIRTH_DT2 (SDATE10).

STRING birth_year (A4) birth_month (A2) birth_day (A2) birthdate (A8).
COMPUTE birth_year  = CHAR.SUBSTR(BABY_BIRTH_DT2,1,4).
COMPUTE birth_month = CHAR.SUBSTR(BABY_BIRTH_DT2,6,2).
COMPUTE birth_day   = CHAR.SUBSTR(BABY_BIRTH_DT2,9,2).
COMPUTE birthdate = CONCAT(birth_year,birth_month,birth_day).
ALTER TYPE birth_year (F4.0).
SELECT IF birth_year >= 2009 AND birth_year <= 2022.
EXECUTE.

SORT CASES BY CHILD_ID(A).
COMPUTE CHILD_rec = 1.
IF (CHILD_ID = LAG(CHILD_ID)) CHILD_rec = LAG(CHILD_rec)+1.
SELECT IF CHILD_rec = 1.
RECODE MOTHER_ID (SYSMIS=999999999).
SELECT IF MOTHER_ID <> 999999999.
EXECUTE.

SAVE TRANSLATE OUTFILE='outputs\mids_births_cohort.dta' /TYPE=STATA /VERSION=14 /REPLACE.

* --- INITIAL ASSESSMENT ---
GET DATA
  /TYPE=ODBC
  /CONNECT='DSN=<SECURE_DSN>;UID=<UID>;PWD=<PWD>;DBALIAS=<ALIAS>'
  /SQL='
    SELECT MOTHER_ID, INITIAL_ASS_DT, GEST_WEEKS,
           SERVICE_USER_SMOKER_STS_CD, SERVICE_USER_ETHNIC_GRP_CD,
           SERVICE_USER_WEIGHT_KG, SERVICE_USER_HEIGHT
    FROM <SCHEMA>.<IA>
  '.
CACHE.
EXECUTE.

COMPUTE INITIAL_ASS_DT2 = INITIAL_ASS_DT.
ALTER TYPE INITIAL_ASS_DT2 (DATETIME20).
ALTER TYPE INITIAL_ASS_DT2 (SDATE10).

STRING ia_year (A4) ia_month (A2) ia_day (A2) IA_date (A8).
COMPUTE ia_year  = CHAR.SUBSTR(INITIAL_ASS_DT2,1,4).
COMPUTE ia_month = CHAR.SUBSTR(INITIAL_ASS_DT2,6,2).
COMPUTE ia_day   = CHAR.SUBSTR(INITIAL_ASS_DT2,9,2).
COMPUTE IA_date  = CONCAT(ia_year,ia_month,ia_day).

RECODE MOTHER_ID (SYSMIS=999999999).
SELECT IF MOTHER_ID <> 999999999.
SORT CASES BY MOTHER_ID(A) INITIAL_ASS_DT(A).
COMPUTE dup = 1.
IF (MOTHER_ID = LAG(MOTHER_ID) AND INITIAL_ASS_DT = LAG(INITIAL_ASS_DT)) dup = LAG(dup)+1.
SELECT IF dup = 1.
EXECUTE.

SAVE TRANSLATE OUTFILE='outputs\mids_initial_ass_cohort.dta' /TYPE=STATA /VERSION=14 /REPLACE.

* --- Merge outline (key may vary in practice) ---
MATCH FILES
  /FILE='outputs\mids_births_cohort.dta'
  /TABLE='outputs\mids_initial_ass_cohort.dta'
  /BY MOTHER_ID INITIAL_ASS_DT.
EXECUTE.

SAVE TRANSLATE OUTFILE='outputs\mids_births_plus_ia.dta' /TYPE=STATA /VERSION=14 /REPLACE.