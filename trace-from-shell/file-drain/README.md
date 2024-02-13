

Experiment with 'draining' a file as it is written.

The diagnostic_dest directory for an oracle database may have limited space for trace files.

If this is not your database, it may not be feasible to change the location or increase the space.

This is an experimental technique to test the following:

- touch the trace file before creation
- start `tail -F tracefile >> tracefile-copy&'
- enable sqltrace
- periodically truncate the trace file
- the '-F' tail argument should be able to keep reading the file.
- oracle will keep writing to the truncated file

This sequence does present a race condition, and a few lines of trace data may be lost when the tracefile is trunctated.

That should be ok, as few lines in a million line file will not matter much.

Initially this is tested without oracle.

Just create a script that continually writes out a sequence, with 1ms between writes.

This will simulate the trace file.

Then create the copy somewhere else.


