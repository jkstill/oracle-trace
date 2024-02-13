
-- get-trace-file-contents.sql

set linesize 4000 trimspool on
set pagesize 0

col v_trace_filename new_value v_trace_filename noprint

prompt trace file name (not including path): 

set echo off pause off feed off term off verify off tab off

select '&1' v_trace_filename from dual;

set term off feed on

col payload format a4000

spool &v_trace_filename

select payload 
from v$diag_sql_trace_records
where trace_filename = '&v_trace_filename'
order by line_number
/

set pagesize 100
set linesize 200 trimspool on

set term on

