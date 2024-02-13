#!/usr/bin/env bash

chkSeq=1

while read line
do
	#echo "$line"
	lineSeq=$(echo $line | cut -f1 -d:)
	echo $chkSeq  $lineSeq

	(( chkSeq += 1 ))

done < /mnt/zips/tmp/oracle/oracle-trace/copy/trace-file.trc

