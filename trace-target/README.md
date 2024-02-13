
Trace Target
============

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
  --create-test-table     creates the table 'TEST_OBJECTS' and exits
  --drop-test-table       drops the table 'TEST_OBJECTS' and exits
  --program-name          change the $0 value to something else
  --row-cache-size        rows to fetch per call
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

