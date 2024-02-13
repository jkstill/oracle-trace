#!/usr/bin/env bash

set -u


logDir='logs';

mkdir -p $logDir

logFile=$logDir/uniform-rs-$(date +%Y-%m-%d_%H-%M-%S).log

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# process substitution
# clear/recreate the logfile
> $logFile
exec 1> >(tee -ia $logFile)
exec 2> >(tee -ia $logFile >&2)

# row in file created from uniform-row-size.conf are 100 bytes/characters

for preFetchRows in 1 5 10 20 50 100 200 300 400 500
do

	#(( preFetchRows *= 100 ))
	#(( preFetchRows *= -1 ))
	#echo preFetchRows: $preFetchRows
	#continue


	time ./target.pl  --sqlfile uniform-row-size.conf \
		--username jkstill \
		--password grok \
		--database 'ora192rac-scan/pdb1.jks.com' \
		--interval-seconds 0.01 \
 		--iterations  10 \
		--trace-level 12 \
		--tracefile-identifier  "PF-$(printf "%03d" $preFetchRows)" \
		--row-cache-size $preFetchRows


done

