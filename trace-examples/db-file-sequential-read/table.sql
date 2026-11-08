
-- db file sequential read
drop table dbfsq cascade constraints purge;

create table dbfsq
(
  id number,
  c1 varchar2(100)
);

insert into dbfsq
select level as id, lpad('x', 100, 'x') as c1
from dual
connect by level <= 10000;

commit;

exec dbms_stats.gather_table_stats(user, 'DBFSQ');

