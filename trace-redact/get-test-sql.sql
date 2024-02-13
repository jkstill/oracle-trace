
set pagesize 0
set head off
set term off
set feed off
set long 1000000

col sql_fulltext format a32767
set linesize 32767 trimspool on

spool sql.txt


with sep_1 as (
	select rownum id, 'START OF STMT' sep
	from dual
	connect by level <= 10000
),
sep_2 as (
	select rownum id, 'END OF STMT' sep
	from dual
	connect by level <= 10000
),
sql as (
	select rownum id, s.sql_fulltext 
	from v$sqlstats s
)
select sep_1.sep
	, s.sql_fulltext
	, sep_2.sep
from sql s
	join sep_2 on sep_2.id = s.id
	join sep_1 on sep_1.id = sep_2.id
order by s.id
/

spool off

set head on term on feed on

