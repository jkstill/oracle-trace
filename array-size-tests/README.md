
Performance, Fetch Array Size, and oraaccess.xml 
================================================

When working with programs that fetch any significant amount of from a database, it is important to consider the impact of the fetch array size.

What is that?

When a query is issued, say this one:

```sql
  select * from hr.emp;
```

The database executes the query and returns the data to the client; that much is obvious.

What may not be so obvious is the manner in which the data is returned.

For most applications, the data is sent to the client app via the network.

If the query returns only 1 row, then that row will be returned quickly.

Many queries however return many more rows, 100 or even more rows.

The default settings typically will cause the database to pack a row, or possibly two rows, into a SDU (Session Data Unit) sized packet, and send it off.

The reason for stating '1 or 2' rows is that I have seen both appear as default values when tracing Oracle sessions.

For queries that return more than 1 or 2 rows, this is quite inefficient.

The data must be sent across the network, with all the requisite TCP coordination.

If larger packets are created, then the number of round trips is reduced, and the amount of TCP handshaking is reduced.

While it is true that the larger packets will require more time to send over the network than the smaller ones, this increase in overhead is much less time than the reduction in overhead realized by reducing the overhead of processing many more packets of data.

If your have ever used `set arraysize 100` in sqlplus, that is directly setting the fetch array size.


Following is a simple demonstration.

This script should be run from somewhere other than on the database server, as we want to see the effects of sending different numbers of rows from the database to the client.

This first test shows the effects of having an array size of 1:

```text

spool array-size-1.log

set arraysize 1

show arraysize 

set timing on
set autotrace on stat

set term off

select * from dba_objects;

set term on
spool off

host tail -20 array-size-1.log

```

Here are the results from a test in my lab:

```text
@ 1.sql
arraysize 1


73995 rows selected.

Elapsed: 00:00:05.79

Statistics
----------------------------------------------------------
        700  recursive calls
          0  db block gets
      58429  consistent gets
         82  physical reads
          0  redo size
   18401648  bytes sent via SQL*Net to client
     741008  bytes received via SQL*Net from client
      36999  SQL*Net roundtrips to/from client
         21  sorts (memory)
          0  sorts (disk)
      73995  rows processed

```

The total time was 5.79 seconds.

Note: From now on _SQL*Net roundtrips to/from client_ will referred to as SNMFC

We can see that ~ 2 rows were sent per network round trip:  73995 row / 36999 SNMFC is approximately 2.


Now I will run test that differs only in that the arrays size is now set to 100:



```text
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
```

Results are as follows:

```text
@ 100.sql
arraysize 100


73995 rows selected.

Elapsed: 00:00:01.78

Statistics
----------------------------------------------------------
          0  recursive calls
          0  db block gets
      19901  consistent gets
          0  physical reads
          0  redo size
   10461196  bytes sent via SQL*Net to client
      15406  bytes received via SQL*Net from client
        741  SQL*Net roundtrips to/from client
          0  sorts (memory)
          0  sorts (disk)
      73995  rows processed

```

The runtime is significantly less at 1.78 seconds: 4 seconds faster than the previous test.

It was really 4.01 seconds, but we can round that down.

Rather than 36999 round trips from the database, setting the array size to 100 reduced that to 741 packets.

36999 / 741 is approximately 2.  

This fits in with with the oberved tests.  Even the the arraysize was set explicitly to 1 in the first test, the arraysize was actually 2.

When setting the array size to 100 in the seconds test, this was 50 times the setting for the first test.

The expected number of packets would be approximately 36999 / 50, and it was.

How many rows were sent per network round trip?

The numbers are those just discussed: 2 rows per network round trip in the first test, and 50 rows per round trip in the second test.

## Predicting Performance Increase

Suppose you are working with an application that works with an Oracle database, and you discover that it is returning 1 or 2 rows at a time.

In many cases, the performance of the application may be dramatically improved by increasing the fetch cache size (or row cache size, array size, ...)

When working on Oracle performance I frequently use [Method-R](https://method-r.com) tools such as [mrskew](https://method-r.com/man/mrskew.pdf) to evaluate Oracle trace files.

While I can parse basic metrics from an Oracle trace file with a variety of tools, that task becomes quite complicated when the tracefile consists of multiple executions and multiple SQL statements.

Hence my reliance on this third party tool.  Similar to what you may hear from many YouTube vloggers, I do not get paid or free product for my comments here.

One of the features of mrskew is the abilty to create rc files that can add additional processing to the raw trace data.

That is what I have used in this case to try an predict SNMFC performance improvements.

mrskew was originally written in Perl, but is now written in C. Even so, there are still Perl libraries linked in to mrskew, as the rc files can include Perl code.

The file `snmfc-savings` can be found the end of this document.

### Is complexity necessary?

At first it may seem that the code is rather complex for the topic at hand.

It is tempting to just count the number of FETCH operations from the file, derive an average row count per fetch, count up the SNMFC and use these values to derive the savings in time by increasing the fetch cache size.

Given:

100 FETCH operations with 2 rows per fetch
100 SNMFC at an average or 0.01 seconds each: 1.0 seconds

New fetch array size: 50

Time saved = 1.0 - (( 100 / 50 ) * 0.01)

So the time saved is 0.98 seconds, and the time required to complete the query is now 0.02 seconds.

In reality there will be a little overhead for the larger amount of data being sent at one time to the client.

The reality is not quite that linear, as we shall see later, but it is not too far off.


Let's consider some examples from a trace file.

Here is an excerpt from a trace file where the client executing `select sysdate from dual` 1000  times.

First, generate the trace file using target.pl (found at the end of this article or this url)


```text
$  ./target.pl  --database ora192rac02/pdb1.jks.com -username jkstill --password grok --iterations 1000 --interval-seconds 0.025 --row-cache-size 100 --trace-level 12 --tracefile-identifier DUAL
setting RowCacheSize = 100

  runtimeSeconds: 1
 intervalSeconds: 0.025
      iterations: 1000

server: ora192rac02.jks.com
tracefile: /u01/app/oracle/diag/rdbms/cdb/cdb2/trace/cdb2_ora_27847_DUAL.trc

scp oracle@ora192rac02.jks.com:/u01/app/oracle/diag/rdbms/cdb/cdb2/trace/cdb2_ora_27847_DUAL.trc ...
```

The statement is parse, then executed.

For each EXEC operation there is a FETCH and two WAITS.

You may have seen the `--row-cache-size 100' option on the command line.

As this query returns only 1 row, setting the fetch array size will have no effect.

This can be seen from `r=1` in each of the FETCH operations. There is always just 1 row returned.


```text
PARSING IN CURSOR #139952410147440 len=24 dep=0 uid=108 oct=3 lid=108 tim=2329698743813 hv=2343063137 ad='b6bed6c8' sqlid='7h35uxf5uhmm1'
select sysdate from dual
END OF STMT
PARSE #139952410147440:c=5428,e=8021,p=2,cr=29,cu=0,mis=1,r=0,dep=0,og=1,plh=1388734953,tim=2329698743812
WAIT #139952410147440: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698743866
WAIT #139952410147440: nam='SQL*Net message from client' ela= 665 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698744558
EXEC #139952410147440:c=15,e=16,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=1388734953,tim=2329698744600
WAIT #139952410147440: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698744617
FETCH #139952410147440:c=10,e=10,p=0,cr=0,cu=0,mis=0,r=1,dep=0,og=1,plh=1388734953,tim=2329698744623
STAT #139952410147440 id=1 cnt=1 pid=0 pos=1 obj=0 op='FAST DUAL  (cr=0 pr=0 pw=0 str=1 time=0 us cost=2 size=0 card=1)'
WAIT #139952410147440: nam='SQL*Net message from client' ela= 25552 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698770207
EXEC #139952410147440:c=0,e=24,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=1388734953,tim=2329698770297
WAIT #139952410147440: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698770316
FETCH #139952410147440:c=0,e=11,p=0,cr=0,cu=0,mis=0,r=1,dep=0,og=1,plh=1388734953,tim=2329698770323
WAIT #139952410147440: nam='SQL*Net message from client' ela= 26107 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698796454
EXEC #139952410147440:c=0,e=29,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=1388734953,tim=2329698796568
WAIT #139952410147440: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=2329698796606
```

Now let's contrast that to trace data from a statement that returns 10000 rows per each execution.

```text
PARSING IN CURSOR #139844608973424 len=48 dep=0 uid=108 oct=3 lid=108 tim=2335137582895 hv=3139787384 ad='be79cf40' sqlid='07tutd2xkaqms'
select * from test_objects where rownum <= 10000
END OF STMT
PARSE #139844608973424:c=0,e=13,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=1534368783,tim=2335137582895
WAIT #139844608973424: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137582925
WAIT #139844608973424: nam='SQL*Net message from client' ela= 211 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583148
WAIT #139844608973424: nam='PGA memory operation' ela= 5 p1=65536 p2=1 p3=0 obj#=-1 tim=2335137583184
WAIT #139844608973424: nam='PGA memory operation' ela= 2 p1=65536 p2=1 p3=0 obj#=-1 tim=2335137583200
WAIT #139844608973424: nam='PGA memory operation' ela= 2 p1=65536 p2=1 p3=0 obj#=-1 tim=2335137583211
WAIT #139844608973424: nam='PGA memory operation' ela= 4 p1=65536 p2=2 p3=0 obj#=-1 tim=2335137583222
EXEC #139844608973424:c=0,e=81,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=1534368783,tim=2335137583249
WAIT #139844608973424: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583311
FETCH #139844608973424:c=0,e=60,p=0,cr=3,cu=0,mis=0,r=1,dep=0,og=1,plh=1534368783,tim=2335137583320
WAIT #139844608973424: nam='SQL*Net message from client' ela= 137 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583470
WAIT #139844608973424: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583486
FETCH #139844608973424:c=11,e=11,p=0,cr=1,cu=0,mis=0,r=2,dep=0,og=1,plh=1534368783,tim=2335137583492
WAIT #139844608973424: nam='SQL*Net message from client' ela= 101 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583603
WAIT #139844608973424: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583623
FETCH #139844608973424:c=12,e=12,p=0,cr=1,cu=0,mis=0,r=2,dep=0,og=1,plh=1534368783,tim=2335137583630
WAIT #139844608973424: nam='SQL*Net message from client' ela= 88 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137583729

thousands of lines later 

FETCH #139844608973424:c=0,e=9,p=0,cr=1,cu=0,mis=0,r=2,dep=0,og=1,plh=1534368783,tim=2335137777611
WAIT #139844608973424: nam='SQL*Net message from client' ela= 99 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137777717
WAIT #139844608973424: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137777729
FETCH #139844608973424:c=0,e=8,p=0,cr=1,cu=0,mis=0,r=2,dep=0,og=1,plh=1534368783,tim=2335137777734
WAIT #139844608973424: nam='SQL*Net message from client' ela= 100 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137777842
WAIT #139844608973424: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137777853
FETCH #139844608973424:c=0,e=9,p=0,cr=1,cu=0,mis=0,r=2,dep=0,og=1,plh=1534368783,tim=2335137777859
WAIT #139844608973424: nam='SQL*Net message from client' ela= 97 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137777963
WAIT #139844608973424: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137777974
FETCH #139844608973424:c=0,e=9,p=0,cr=1,cu=0,mis=0,r=2,dep=0,og=1,plh=1534368783,tim=2335137777980
WAIT #139844608973424: nam='SQL*Net message from client' ela= 97 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137778084
WAIT #139844608973424: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2335137778099

still not finished

```

These traces lines are all received for a single execution of a query.

If the row cache size is increased, the number of trips on the network can be reduced.


What can be seen from the trace data is that the measurements used to predict improvement should be done between EXEC operations.


## Measuring uSeconds per row.

Not sure now what was to go here.


## target.pl


target.pl is a Perl script that makes a convenient target for many kinds of testing.

## Help

```text

usage: target.pl

  --database              target instance
  --username              target instance account name
  --password              target instance account password
  --runtime-seconds       total seconds to run
  --interval-seconds      seconds to sleep each pass - can be < 1 second
  --iterations            set the iterations - default is calculated
  --trace-level           10046 trace - default is 0 (off)
  --tracefile-identifier  tag for the trace filename
  --create-test-table     creates the table 'TEST_OBJECTS' and exit
  --drop-test-table       drops the table 'TEST_OBJECTS' and exit
  --sqlfile          name of file that contains SQL to create the test table
                          if not provided, a default table is created

  --program-name          change the $0 value to something else

  --row-cache-size        rows to fetch per call

  --prefetch-rows         rows to fetch per call - alernate method
                          you cannot use both of --row-cache-size and --prefetch-rows
  --prefetch-memory       amount of memory, in bytes, to support --prefetch-rows

  --sysdba                logon as sysdba
  --sysoper               logon as sysoper
  --local-sysdba          logon to local instance as sysdba. ORACLE_SID must be set
                            the following options will be ignored:
                            --database
                            --username
                            --password

  example:

  target.pl --database dv07 --username scott --password tiger --sysdba

  target.pl --local-sysdba



```

