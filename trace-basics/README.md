

Enable Session Trace and retrieve Tracefile Contents
=====================================================

## Enable Trace

When first using SQL Trace in a database, the following are a good practice:

* do not collect bind variable values
* do not use 'all_executions' for execution plan STAT lines

Both of these can significantly increase the amount of data written to the trace file.

When you need to bind values, it may be a good idea to then include them if you know the following:

* the program does not emit them too frequently
* the values dumpt to a trace file are not a security violation


### In the current session

This can be done with SQL such as:

```sql
alter session set events '10046 trace name context forever, level 12';
```

Oracle has provided some simpler methods for doing this as well.

`exec dbms_session.session_trace_enable( waits => true)`

The defaults for the `binds` and `plan_stat` arguments set them to `false` and `NULL`, which are both acceptable to start with.

Here are two methods to get the name of the trace file:

```text
select value from v$diag_info where name = 'Default Trace File';

VALUE
------------------------------------------------------------
C:\ORACLE\APP\diag\rdbms\orcl\orcl\trace\orcl_ora_9928.trc
```


Here is another method:

```sql
select tracefile from v$process where addr=(
   select paddr from v$session where sid=sys_context('userenv','sid')
);

TRACEFILE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
C:\ORACLE\APP\diag\rdbms\orcl\orcl\trace\orcl_ora_9928.trc

```

### In a different session

The DBMS_MONITOR package can be used to set SQL Trace on in another session:

Sessions:

```text
  1  select
  2     s.username,
  3     s.sid,
  4     s.serial#,
  5     s.sql_id
  6  from v$session s
  7  where s.username is not null
  8* order by username, sid
/

USERNAME      SID SERIAL# SQL ID
---------- ------ ------- -------------
SOE            42   56427 0w2qpuc6u2zsp
               49   52961 0w2qpuc6u2zsp
               51    2921 147a57cxq3w5y
               54   64436 147a57cxq3w5y
               55   64380 0w2qpuc6u2zsp
               57    5871 147a57cxq3w5y
               69   27046 0w2qpuc6u2zsp
               70   55298 147a57cxq3w5y
               73   49859 147a57cxq3w5y
              768    9028 0w2qpuc6u2zsp
              789   27382 0w2qpuc6u2zsp
              795   23248 0w2qpuc6u2zsp
              803   64303 0w2qpuc6u2zsp
              812   46642
              815   39852 0w2qpuc6u2zsp
              816   14998 147a57cxq3w5y
              824   53372 0w2qpuc6u2zsp
              826   11069
              836   10043 147a57cxq3w5y
              837   15090 0w2qpuc6u2zsp

SYS           831   36116 f672s11wngm8u


21 rows selected.
```

Set SQL Trace on for Session 42

```text
exec dbms_monitor.session_trace_enable(session_id => 42, serial_num => 56427, waits => true)

PL/SQL procedure successfully completed.
```

Find the trace file for this session:

```sql
  1  select tracefile from v$process where addr=(
  2     select paddr from v$session where sid=42
  3* )
/

TRACEFILE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
C:\ORACLE\APP\diag\rdbms\orcl\orcl\trace\orcl_ora_3036.trc

```

If this were a Linux server I could just scp that file to my workstation for analysis.

As it is a windows machine, we can use another method, one that works regardless of platform.

First, let's disable trace on this session:

```text
exec dbms_monitor.session_trace_disable(session_id => 42, serial_num => 56427)

PL/SQL procedure successfully completed.
```

Using the base file name, the tracefile contents can be retrieved from any of the following views:

* [G]V$DIAG_SQL_TRACE_RECORDS
* [G]V$DIAG_TRACE_FILE_CONTENTS

In this 19c database, these views are exactly the same

```text
@ get-trace-file-contents

trace file name (not including path):
orcl_ora_3036.trc

!ls -ltar
total 8004
drwxr-x--- 274 jkstill dba   12288 Aug  9 11:07 ..
-rw-r--r--   1 jkstill dba     113 Aug  9 11:17 find-arg.sql
-rw-r--r--   1 jkstill dba    4143 Aug  9 11:44 README.md
-rw-r--r--   1 jkstill dba     112 Aug  9 11:46 afiedt.buf
-rw-r--r--   1 jkstill dba     495 Aug  9 11:49 get-trace-file-contents.sql
drwxr-xr-x   2 jkstill dba    4096 Aug  9 11:50 .
-rw-r--r--   1 jkstill dba 8159232 Aug  9 11:50 orcl_ora_3036.trc

```

## get-trace-file-contents.sql

```sql

-- get-trace-file-contents.sql

set linesize 4000 trimspool on
set pagesize 0

col v_trace_filename new_value v_trace_filename noprint

prompt trace file name (not including path): 

set echo off pause off feed off term off verify off

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

set term on
```



