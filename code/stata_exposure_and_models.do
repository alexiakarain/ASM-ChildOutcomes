********************************************************************************
* Project : ASM Linkage & Analysis
* File    : code/02_exposure_and_models.do
* Purpose : Build pregnancy-level exposure & diagnosis flags from GP events,
*           merge to birth cohort, tidy demographics, and (optionally) model.
* Stata   : 18
********************************************************************************
version 18
clear all
set more off

* ---------------- Paths ----------------
global OUT      "outputs"
global LOGS     "reports"
cap mkdir "$OUT"
cap mkdir "$LOGS"

cap log close _all
log using "$LOGS/02_exposure_and_models.smcl", replace name(main)

* ---------------- Helpers ----------------
program define _coerce_to_td
    // Ensure a date var is numeric %td (handles string YMD/DMY/MDY or datetime)
    version 18
    syntax varname
    tempvar tmp
    capture confirm string variable `varlist'
    if !_rc {
        gen double `tmp' = date(`varlist', "YMD")
        replace `tmp' = date(`varlist', "DMY") if missing(`tmp') & !missing(`varlist')
        replace `tmp' = date(`varlist', "MDY") if missing(`tmp') & !missing(`varlist')
    }
    else {
        gen double `tmp' = `varlist'
        replace `tmp' = dofc(`varlist') if `varlist' > 3e6
    }
    drop `varlist'
    rename `tmp' `varlist'
    format `varlist' %td
end

* ==============================================================================
* 1) OPEN GP EVENTS & IDENTIFY MEDICATION / DIAGNOSIS DURING PREGNANCY
*    Expected file: gp_linked_rxlevel.dta (one row per GP event linked to pregnancy)
*    Must contain: mother_id (or participantID/MOTHER_ID), child_id,
*                  conception_date, birth_date, event_date (or rx_date),
*                  EVENT_CD (string) and/or drug_name.
* ==============================================================================
use "$OUT/gp_linked_rxlevel.dta", clear


* ---- ensure key dates are numeric %td ----
quietly {
    _coerce_to_td `CONCEPTION'
    _coerce_to_td `BIRTH'
    _coerce_to_td `EVENTDATE'
}

* ---- trimester end dates ----
gen t1end = `CONCEPTION' + 90
gen t2end = `CONCEPTION' + 195
gen t3end = `CONCEPTION' + 307
label var t1end "End of trimester 1 (conception+90)"
label var t2end "End of trimester 2 (conception+195)"
label var t3end "End of trimester 3 (conception+307)"

* ---- trimester windows for each event ----
gen byte trimester1 = (`EVENTDATE' >= `CONCEPTION' & `EVENTDATE' <= t1end & `EVENTDATE' <= `BIRTH')
gen byte trimester2 = (`EVENTDATE' >  t1end      & `EVENTDATE' <= t2end & `EVENTDATE' <= `BIRTH')
gen byte trimester3 = (`EVENTDATE' >  t2end      & `EVENTDATE' <= t3end & `EVENTDATE' <= `BIRTH')

* ---- generic medication flag from EVENT_CD prefixes (sample list) ----
gen med = 0
replace med = 1 if inlist(__pref,"d26","dnb","dn3","dn4") & (`EVENTDATE' <= `BIRTH')


* ---- drug-specific flags (either by drug_name text or EVENT_CD prefixes) ----
foreach d in valproate carbamazepine clobazam clonazepam {
    gen byte `d' = 0
}
if "`DRUGNAME'" != "" {
    replace valproate     = (strpos(lower(`DRUGNAME'),"valproate")    > 0)
    replace carbamazepine = (strpos(lower(`DRUGNAME'),"carbamazep")   > 0)
    replace clobazam      = (strpos(lower(`DRUGNAME'),"clobazam")     > 0)
    replace clonazepam    = (strpos(lower(`DRUGNAME'),"clonazepam")   > 0)
}

* ---- trimester-specific medication flags ----
gen byte t1_med = (trimester1==1 & med==1)
gen byte t2_med = (trimester2==1 & med==1)
gen byte t3_med = (trimester3==1 & med==1)

* ---- count distinct exemplar drugs on an event row (toy example) ----
egen med_count = rowtotal(clobazam carbamazepine valproate clonazepam)
label var med_count "Count of exemplar ASM drugs on event row"

* ---- diagnosis flag from EVENT_CD prefixes (sample list) ----
gen byte diagnosis = 0
replace diagnosis = 1 if inlist(__dpre,"F25","667","9H6","9OF")
  

* ---- create pregnancy_id if not present (mother + birth_date) ----
capture confirm variable pregnancy_id
if _rc {
    egen long pregnancy_id = group(`MOTHER' `BIRTH'), label
    label var pregnancy_id "Mother x birth_date"
}

* ---- collapse to pregnancy-level (max within conception→delivery window) ----
egen byte any_med = max(med), by(pregnancy_id)
collapse (max) t1_med t2_med t3_med any_med valproate carbamazepine clobazam ///
                 clonazepam diagnosis, by(pregnancy_id `MOTHER' `BIRTH')

gen byte mother_linked_flag = 1
order pregnancy_id `MOTHER' `BIRTH' t1_med t2_med t3_med any_med diagnosis
label var mother_linked_flag "Has linked GP data"
save "$OUT/pregnancy_exposures.dta", replace

* ==============================================================================
* 2) OPEN BIRTH COHORT AND MERGE WITH EXPOSURE SUMMARY
* ==============================================================================
use "$OUT/birth_cohort.dta", clear   // <<-- put your birth cohort file here
* Expect: one row per child×pregnancy with mother_id & birth_date (or pregnancy_id)

* If pregnancy_id absent, recreate to match exposure file
capture confirm variable pregnancy_id
if _rc {
    local MOTHER2 ""
    foreach v in mother_id participantID MOTHER_ID { capture confirm variable `v' ; if !_rc local MOTHER2 `v' }
    local BIRTH2 ""
    foreach v in birth_date delivery_date birthdate { capture confirm variable `v' ; if !_rc local BIRTH2 `v' }
    egen long pregnancy_id = group(`MOTHER2' `BIRTH2'), label
}

merge 1:1 pregnancy_id using "$OUT/pregnancy_exposures.dta"
tabulate _merge
drop if _merge==2   // drop exposure-only rows (safety)
drop _merge

* ==============================================================================
* 3) EXCLUSIONS & DEMOGRAPHIC TIDY
* ==============================================================================
* --- exclude stillbirths ---
capture confirm variable stillbirth_flag
if !_rc {
    tab stillbirth_flag, m
    drop if stillbirth_flag==1
}

* --- multiple births indicator (per mother×birth_date) ---
local MOM ""
foreach v in mother_id maternalID MOTHER_ID { capture confirm variable `v' ; if !_rc local MOM `v' }
local BDT ""
foreach v in birth_date delivery_date birthdate { capture confirm variable `v' ; if !_rc local BDT `v' }
sort `MOM' `BDT'
by `MOM' `BDT': gen multiple = _N
replace multiple = 2 if multiple >= 2
label define mult 1 "Singleton" 2 "Multiple"
label values multiple mult
tab multiple

* --- recode ethnicity (example mapping) ---
capture confirm variable ETHNICITY_CD
if !_rc {
    gen byte ethnicity = .
    replace ethnicity = 1 if inlist(ETHNICITY_CD,"A","B","C","D")        // White
    replace ethnicity = 2 if inlist(ETHNICITY_CD,"H","J","K")            // Asian
    replace ethnicity = 3 if inlist(ETHNICITY_CD,"M","N","P")            // Black
    replace ethnicity = 4 if inlist(ETHNICITY_CD,"F","E","G","S")        // Mixed/Other
    label define ethlab 1 "White" 2 "Asian" 3 "Black" 4 "Mixed/Other"
    label values ethnicity ethlab
    label var ethnicity "Ethnicity (recoded)"
}

save "$OUT/analysis_base_enriched.dta", replace

* ==============================================================================
* 4) MODELLING SHELL
* ==============================================================================
GEE: binary SEN ~ exposure (+ minimal covariates as example)

xtset child_id
xtgee anySEN i.any_med i.poly i.sex c.birth_year, ///
      family(binomial) link(logit) corr(independent) vce(robust)

Cox: time-to-SEN
stset sen_age_days, failure(anySEN==1) origin(time 0)
stcox i.any_med i.poly i.sex c.birth_year

save "outputs/analysis_dataset_demo.dta", replace
display as text _n "Done. Models fitted; dataset saved to outputs/."
