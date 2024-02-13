#!/usr/bin/env bash

: << 'COMMENT'

Tracefiles may be quite large when bloated with Deadlock graphs or other internal operations that are writtent to trace files.

This script creats a cropped tracefile.

It is not perfect, but probably good enough for most uses

This is the command used to get the first occurrence of a line caused by 10046 (SQLTrace)

  grep -n -m1 -E '?^(EXEC|FETCH|PARSING|WAIT)' edb_ora_13335.trc | cut -f1 -d:

There may be other deadlock graphs or other things after this, but this should greatly reduce tracefile processing time.

This script reads the tracefile, gets the header and lines following deadlock graphs.

Output is strictly to STDOUT


COMMENT


declare tracefileName=$1
set -u

: ${tracefileName:?Trace File Name required}

[[ -r $tracefileName ]] || { echo "cannot read $tracefileName"; exit 1; }

declare hdrEndLine=$(grep -m1 -n '^*** CLIENT DRIVER' $tracefileName | cut -f1 -d:)

declare hdr="$(head -${hdrEndLine} $tracefileName)"
echo

declare bodyStartLine=$(grep -n -m1 -E '?^(COMMIT|XCTEND|EXEC|FETCH|PARSING|WAIT)' $tracefileName | cut -f1 -d:)

[[ -z $bodyStartLine ]] && {
	echo
	echo "No SQL Trace lines found in $tracefileName"
	echo
	exit 1
}

#echo "line: $bodyStartLine"

echo "$hdr"

tail -n+${bodyStartLine} $tracefileName
