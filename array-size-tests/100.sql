
spool array-size-100.log

set arraysize 100

show arraysize

set timing on
set autotrace on stat

set term off

select * from dba_objects;

set term on
spool off

host tail -20 array-size-100.log


