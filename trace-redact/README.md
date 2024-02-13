
Tracefile Redact
================


## TLDR

Get a copy of the tracefile

Check values of $preserveDates and $preserveNumerics in ./bind-redact-02.pl

Run ./bind-redact.pl

Get uniq list of remaining binds

```text
cp trace/base-test.trc test.trc; chmod u+w test.trc
/bind-redact.pl --tracefile test.trc --preserve-numeric --obfuscate-redactions --preserve-dates --backup-extension '.save'
grep -E '^\s+value=' test.trc | sort | uniq -c | sort -n
```

Or, use this to group by obfuscated bind values:

```text
grep -E '^\s+value=' test.trc | sort | uniq -c | sort -t- -k2 -n
```

### Example of Date, Timestamp and Integer bind values obfustated

```text
$ cp trace/base-test.trc test.trc; chmod u+w test.trc

$ ./bind-redact-02.pl --tracefile test.trc --preserve-numeric --obfuscate-redactions --preserve-dates --backup-extension '.save'

$  grep -E '^\s+value=' test.trc | sort | uniq -c | sort -t- -k2 -n
     16   value="Redacted"
   2646   value=Numeric-0000
      2   value=Timestamp-0000
   6177   value=Date-0000
   2647   value=Numeric-0001
      2   value=Timestamp-0001
   6172   value=Date-0001
   2647   value=Numeric-0002
   5290   value=Date-0002
   2647   value=Numeric-0003
   2646   value=Numeric-0004
   2646   value=Numeric-0005
   1764   value=Numeric-0006
      1   value=Numeric-0007
     14   value=Numeric-0008
      1   value=Numeric-0009
      1   value=Numeric-0010
      4   value=Numeric-0011
      1   value=Numeric-0012
      1   value=Numeric-0013
      1   value=Numeric-0014
      1   value=Numeric-0015
      6   value=Numeric-0016
      1   value=Numeric-0017
      1   value=Numeric-0018
      1   value=Numeric-0019
      1   value=Numeric-0020
      1   value=Numeric-0021
      1   value=Numeric-0022
```


## Bind Variable Values

If a tracefile has bind variable values in it, they may contain sensitive data.

Here are some methods to redact bind values.

### What are the bind values?

This test file has no identifiable data in it other than dates and digits

```text
$  grep -E '^\s+value=' trace/base-test.trc  |  sort -u
  value="2230"
  value="2231"
  value="2232"
  value="2233"
  value="2234"
  value="2235"
  value="2236"
  value="5/10/2023 0:0:0"
  value="5/11/2023 0:0:0"
  value="5/9/2023 0:0:0"
  value="Block Count Current"
  value="Block Count Max"
  value="Block Size"
  value="Create Count Failure"
  value="Create Count Success"
  value="Delete Count Invalid"
  value="Delete Count Valid"
  value="FAKEDATA"
  value="Find Count"
  value="Hash Bucket Count"
  value="Invalidation Count"
  value="net8://?PR=0"
  value=0
  value=1
  value=10
  value=1024
  value=1227
  value=128
  value=2
  value=256
  value=3
  value=4
  value=4096
  value=5
  value=6
  value=7
  value=8
  value=9
```

There are no identifiable values hard coded into any SQL:

```text
$  grep -A1 -E PARSING trace/base-test.trc  |  sort -u | grep -Ev '^--|PARSING IN'
SELECT H.* FROM TEST_TABLE_1 H WHERE ( H."Col01" = 0 OR H."Col01" = (SELECT C."Col01" FROM TEST_TABLE_2 C WHERE C."Col01" = :p1)) AND H."StartDate" <= :p2 AND H."EndDate" >= :p2 AND H."PartDay" = 0 ORDER BY H."Id" DESC
delete from CRC$_RESULT_CACHE_STATS where CACHE_ID = :1
delete from chnf$_reg_queries where regid = :1
delete from invalidation_registry$ where regid = :1
delete from reg$ where subscription_name = :1 and namespace = :2
select location_name, user#, user_context, context_size, presentation,  version, status, any_context, context_type, qosflags, payload_callback,  timeout, reg_id, reg_time, ntfn_grouping_class, ntfn_grouping_value,  ntfn_grouping_type, ntfn_grouping_start_time, ntfn_grouping_repeat_count,  state, session_key from reg$  where subscription_name = :1 and  namespace = :2  order by location_name, user#, presentation, version
select queryid, fromList from chnf$_queries where queryid IN     (select unique(queryId) from chnf$_reg_queries where regid = :1)
select user# from reg$ where location_name = :1 and  (subscription_name != :2 or namespace != :3)
update CRC$_RESULT_CACHE_STATS                   set NAME = :1, VALUE = :2 where CACHE_ID = :3 and                   STAT_ID = :4
```

The test trace file has been modified so that two quoted bind values will wrap to the following line.  

This happens with text that may be inserted or selected.

### Nuke them all

This is fairly straightforward with sed.

The following script will edit the trace file in place, replacing all bind values that appear in double quotes with 'Redacted'

Testing will be done with copies of the base trace file.

`cp trace/base-test.trc test.trc; chmod u+w test.trc`

The following sed replaces 35k of bind values.


The following command will redact all bind values

```text
$  sed -r -e 's/^(\s+)(value=)(.*)$/\1\2"Redacted"/' test.trc| grep -E '^\s+value='| sort | uniq -c
  35339   value="Redacted"
```

This sed command will redact only quoted bind values.

The final double quote is optional, as it will not be at the end of line that has wrapped to the next line.

```text
$  sed -r -e 's/^(\s+)(value=)(".*["]{0,1}$)$/\1\2"Redacted"/' test.trc| grep -E '^\s+value='| sort | uniq -c
  35302   value="Redacted"
      6   value=0
      1   value=1
      1   value=10
      1   value=1024
     14   value=1227
      1   value=128
      4   value=2
      1   value=256
      1   value=3
      1   value=4
      1   value=4096
      1   value=5
      1   value=6
      1   value=7
      1   value=8
```

What it did not do is replace values where the bind value has wrapped to the next line:

```text
$  sed -r -e 's/^(\s+)(value=)(.*)$/\1\2"Redacted"/' test.trc | grep -A1 -E '^\s+value=' | grep -vE 'Bind#|^--|Redacted|^(BINDS|EXEC|WAIT)'
the next line"
   next line - has      tabs and spaces "
```

These can be saved to a file, and the file used by sed to delete these lines

```text
sed -r -e 's/^(\s+)(value=)(.*)$/\1\2"Redacted"/' test.trc | grep -A1 -E '^\s+value=' | grep -vE 'Bind#|^--|Redacted|^(BINDS|EXEC|WAIT)' | awk '{print "/"$0"/d" }' > sed-exp.txt
```

Now use the sed command with the `sed-exp.txt` file to delete the wrapped lines

```text
$ sed -f sed-exp.txt test.trc > x
```

The lines are removed

```test
$  diff test.trc x
287d286
< the next line"
409d407
<    next line - has    tabs and spaces "
```

Now we can use these commands to make a few passes on the file, and edit it in place.


```text

sed -i -r -e 's/^(\s+)(value=)(.*)$/\1\2"Redacted"/' test.trc

sed -r -e 's/^(\s+)(value=)(.*)$/\1\2"Redacted"/' test.trc | grep -A1 -E '^\s+value=' | grep -vE 'Bind#|^--|Redacted|^(BINDS|EXEC|WAIT)' | awk '{print "/"$0"/d" }' > sed-exp.txt

sed -i -f sed-exp.txt test.trc

```

Now run the same discovery checks on the redacted file:

```text
$  grep -E '^\s+value=' test.trc  |  sort | uniq -c
  35339   value="Redacted"

$ grep -A1 -E '^\s+value=' test.trc | grep -vE 'Bind#|^--|Redacted|^(BINDS|EXEC|WAIT)' | sort | uniq -c
```

### Selectively keeping some bind variable values.

It may be that some bind values can be preserved.

For instance, the step that redacts all bind variables can be modified as shown previously to affect only quoted values.
This would leave numeric data only, which typically is not sensitive data.

It may be that dates can be preserved, as dates are not sensitive when not associated with person or action.

Keeping just the dates and possibly numeric data my be possible with sed, but probably easier to do with awk, perl or python.

Following is how it might be done in perl.

#### bind-redact.pl

The Perl script `bind-redact.pl` incorporates these ideas in to an easy to use format.

Note: Hard coded SQL Predicates are not yet included.

help:

```text

bind-redact.pl

usage: bind-redact.pl - Redact or obfuscate bind values in Oracle 10046 trace files

   bind-redact.pl --tracefile filename  <--preserve-numerics> <--preserve-dates> <--obfuscate-redactions> 
      <--redact-sql> <--redact-sql-string>

   Defaults: 
   The source file will be over-written
   All bind variable values will be redacted

   --tracefile               The 10046 trace file

   --backup-extension        The extension for the backup file - by default no backup is made

   --preserve-numerics       preserve integer bind values. these are often internal values, not personal data
                             be careful of things such as SSN, phone#, etc.
                             future: recognize common exceptions such as SSN
 
   --preserve-dates          preserve dates and timestamps

   --obfuscate-redactions    for dates, timestamps and numeric values that are not being preserved, replace
                             them with numbered place holders
                             Ex.  '2023-02-01' becomes 'Date-00000', '2023-06-10' becomes 'Date-00002', etc.
                             These can still be valuable for analysis when grouping on bind values is desired
                             Otherwise the value will simply be 'Redacted'

   --redact-sql              Redact anything found in hard coded in single quotes in a SQL statement
                             This is the default.

   --redact-sql-string       The phrase used to redact hard coding found in SQL. Default is 'HC-Redacted'


   Options that are a binary on/off switch, such as --redact-sql, can be negatet with 'no'
   eg. bind-redact.pl ... --noredact-sql
  
examples here:

   bind-redact.pl --tracefile DWDB_ora_63389.trc --preserve-dates --obfuscate-redactions --backup-extension '.save'


```

#### Results


Dates and Integers Obfuscated

```text
$  cp trace/base-test.trc test.trc; chmod u+w test.trc

$  ./bind-redact.pl --tracefile test.trc --obfuscate-redactions --backup-extension '.save'
test.trc
Backup file is test.trc.save

$  grep -E '^\s+value=' test.trc | sort | uniq -c | sort -t- -k2 -n
     16   value="Redacted"
   2646   value=Numeric-00000
      2   value=Timestamp-00000
   6177   value=Date-00000
   2647   value=Numeric-00001
      2   value=Timestamp-00001
   6172   value=Date-00001
   2647   value=Numeric-00002
   5290   value=Date-00002
   2647   value=Numeric-00003
   2646   value=Numeric-00004
   2646   value=Numeric-00005
   1764   value=Numeric-00006
      1   value=Numeric-00007
     14   value=Numeric-00008
      1   value=Numeric-00009
      1   value=Numeric-00010
      4   value=Numeric-00011
      1   value=Numeric-00012
      1   value=Numeric-00013
      1   value=Numeric-00014
      1   value=Numeric-00015
      6   value=Numeric-00016
      1   value=Numeric-00017
      1   value=Numeric-00018
      1   value=Numeric-00019
      1   value=Numeric-00020
      1   value=Numeric-00021
      1   value=Numeric-00022
```

Only Dates Preserved, Integers Obfuscated

```text
$  cp trace/base-test.trc test.trc; chmod u+w test.trc
(oci) jkstill@poirot  ~/oracle/trace-redact $
$  ./bind-redact.pl --tracefile test.trc --preserve-dates --obfuscate-redactions --backup-extension '.save'
test.trc
Backup file is test.trc.save
(oci) jkstill@poirot  ~/oracle/trace-redact $
$  grep -E '^\s+value=' test.trc | sort | uniq -c | sort -t- -k2 -n
     16   value="Redacted"
   2646   value=Numeric-00000
      2   value="11-JUN-23 09.15.33.425616 AM +10:00"
      2   value="11-JUN-23 12.00.33.425616 PM -07:00"
   5290   value="5/10/2023 0:0:0"
   6172   value="5/11/2023 0:0:0"
   6177   value="5/9/2023 0:0:0"
   2647   value=Numeric-00001
   2647   value=Numeric-00002
   2647   value=Numeric-00003
   2646   value=Numeric-00004
   2646   value=Numeric-00005
   1764   value=Numeric-00006
      1   value=Numeric-00007
     14   value=Numeric-00008
      1   value=Numeric-00009
      1   value=Numeric-00010
      4   value=Numeric-00011
      1   value=Numeric-00012
      1   value=Numeric-00013
      1   value=Numeric-00014
      1   value=Numeric-00015
      6   value=Numeric-00016
      1   value=Numeric-00017
      1   value=Numeric-00018
      1   value=Numeric-00019
      1   value=Numeric-00020
      1   value=Numeric-00021
      1   value=Numeric-00022
```

## Hard Coded SQL Predicates

Sensitive data may be found in hard coded SQL as well.

The test trace file has been modified by replacing bind values with hard coded values.

These can be found with grep:

The blanks that appear in the final grep are TAB and SPACE

For some reason '\t' and '\s' were not working, even when escaped.
 

```test

$  grep -A1 -E PARSING trace/base-test.trc  |  sort -u | grep -Ev '^--|PARSING IN' | grep -Eo "'[[:alnum:]_\.\,         -]+'"
'0'
'HARD-CODE-01'
'HARD-CODE,02 '
'       HARD.CODE-03'

```


If necessary, these can be redacted with a technique used earlier.

The warning can be ignored.

```text
$  grep -A1 -E PARSING trace/base-test.trc  |  sort -u | grep -Ev '^--|PARSING IN' | grep -Eo "'[[:alnum:]_\.\,         -]+'" | awk '{ print "s/"$0"/\\'REDACTED\\'/g" }'  | sed -e "s/REDACTED/'REDACTED'/" > sed-exp.txt
awk: cmd. line:1: warning: escape sequence `\/' treated as plain `/'

```

```text
$   sed -i -f sed-exp.txt test.trc
```

The hard coded values have been redacted.

```text
$  grep 'FROM TEST_TABLE' test.trc
SELECT H.* FROM TEST_TABLE_1 H WHERE ( H."Col01" = 'REDACTED' OR H."Col01" = (SELECT C."Col01" FROM TEST_TABLE_2 C WHERE C."Col01" = 'REDACTED')) AND H."StartDate" <= 'REDACTED' AND H."EndDate" >= 'REDACTED' AND H."PartDay" = 0 ORDER BY H."Id" DESC
SELECT H.* FROM TEST_TABLE_1 H WHERE ( H."Col01" = 0 OR H."Col01" = (SELECT C."Col01" FROM TEST_TABLE_2 C WHERE C."Col01" = :p1)) AND H."StartDate" <= :p2 AND H."EndDate" >= :p2 AND H."PartDay" = 0 ORDER BY H."Id" DESC
```



