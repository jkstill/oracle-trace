
col trigger_name format a30
col status format a15

select trigger_name, status from dba_triggers where trigger_name = 'SOE_10046_TRG'
/
