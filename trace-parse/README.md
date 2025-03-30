
Scripts to Parse SQL Trace Files
================================

This repository contains scripts to parse SQL trace files. 

Accurately parsing the trace files is not straightforward. 

Some of the things that complicate parsing are:

- The same SQL ID may appear in multiple cursors due to re-parsing.
  - Can be caused by different bind variables.
  - Or the app may open and close the cursor multiple times.
- Differences in trace file format due to different versions of Oracle.


## sqltrace-times.sh

This script parses a single trace file and reports the times per event or wait.

Optionally, a single SQL ID can be specified to report only the times for that SQL ID.

Example usage:

```bash
$  ./sqltrace-times.sh a/72899.trc

   Total elapsed usecs: 16174677
Computed elapsed usecs: 1075944
    Work elapsed usecs: 1075944

                 WAIT: SQL*Net message from client:     0.934194
                                              WAIT:     0.096194
                                             FETCH:     0.030191
                                              EXEC:     0.005569
                   WAIT: SQL*Net message to client:     0.004171
                        WAIT: PGA memory operation:     0.002356
                                             CLOSE:     0.001622
                                             PARSE:     0.001091
       WAIT: ges resource directory to be unfrozen:     0.000556

```

Enable Verbosity:

```bash
$  VERBOSE=1  ./sqltrace-times.sh a/72899.trc  | head
Start time: 2025-03-14T13:54:10.419147+00:00
Start time: 2025-03-14T06:54:10.419147000
Start time epoch: 1741960450.419147000
First time: 16593273438638
WAIT time: 16593273438638 name: PGA memory operation
             Event:
            Cursor: 0
        Start Time: 2025-03-14T06:54:10.419147000
  Start time epoch: 1741960450.419147000
  Start time usecs: 16593273438638
...
CLOSE: time: 16593289613315
             Event: CLOSE
            Cursor: 140633839165744
        Start Time: 2025-03-14T06:54:10.419147000
  Start time epoch: 1741960450.419147000
  Start time usecs: 16593273438638
Current time usecs: 16593289613315
Elapsed time usecs: 16174677
Interval from prev: 17
Current time epoch: 2025-03-14T06:54:10.419164000


   Total elapsed usecs: 16174677
Computed elapsed usecs: 1075944
    Work elapsed usecs: 1075944

                 WAIT: SQL*Net message from client:     0.934194
                                              WAIT:     0.096194
                                             FETCH:     0.030191
                                              EXEC:     0.005569
                   WAIT: SQL*Net message to client:     0.004171
                        WAIT: PGA memory operation:     0.002356
                                             CLOSE:     0.001622
                                             PARSE:     0.001091
       WAIT: ges resource directory to be unfrozen:     0.000556

```

Profile just a single SQLID:

```bash
$  SQLID='9zg9qd9bm4spu' ./sqltrace-times.sh a/72899.trc
line: PARSING IN CURSOR #140633839165744 len=105 dep=1 uid=0 oct=6 lid=0 tim=16593273453875 hv=1462919866 ad='59fdeaa38' sqlid='9zg9qd9bm4spu'
cursorNumber: 140633839165744
Cursor number: 140633839165744

   Total elapsed usecs: 16174677
Computed elapsed usecs: 15878
    Work elapsed usecs: 15878

                   WAIT: SQL*Net message to client:     0.003874
                        WAIT: PGA memory operation:     0.002250
                                              EXEC:     0.002200
                                              WAIT:     0.002157
                                             PARSE:     0.001615
                 WAIT: SQL*Net message from client:     0.001441
                                             FETCH:     0.000982
                                             CLOSE:     0.000803
       WAIT: ges resource directory to be unfrozen:     0.000556

```


