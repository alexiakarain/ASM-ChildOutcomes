# \# ASM Linkage \& Analysis (Stata + SPSS)

# 

# \*\*Goal.\*\* Link birth \& maternity records (MIDS) → construct pregnancy episodes → attach maternal GP prescribing (2-year lookback) → join education outcomes (SEN), then model ASM exposure vs SEN.

# 

# \*\*Scale.\*\* National birth cohorts (2009–2022), GP 2007–2022.  

# \*\*Tech.\*\* SPSS (ODBC/SQL ETL, de-dup with `LAG`), Stata (exposure construction, GEE/Cox).

# 

# \## What’s in here

# \- `code/spss\_births.sps` – ODBC/SQL ingest of births \& initial assessment, date harmonisation, 2009–2022 window, duplicate handling, export to Stata.

# \- `code/stata\_exposure\_and\_models.do` – builds trimester/polytherapy exposure from rx-level data and runs GEE \& Cox examples.

# 

# > No real data is included. Sensitive connection details remain placeholders.

# 

# \## Run (conceptual)

# 1\. In secure environment, set DSN/UID/PWD and table names in `spss\_ingest\_mids.sps`; run to create `.dta` outputs.

# 2\. Prepare `outputs/gp\_linked\_rxlevel.dta` and `outputs/sen\_outcomes.dta`.

# 3\. In Stata: `do code/stata\_exposure\_and\_models.do`

# 

# \## License

# MIT



