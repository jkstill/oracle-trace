#!/usr/bin/env bash


# 25k rows read per trace file

#[[ -z "$1" ]] && { echo "please send files"; exit 1; }

#echo "array size,avgSNMFC"

banner () {

	echo
	echo '###################################'
	echo "## $@"
	echo '###################################'
	echo 

}

traceFile='trace/poirot/select-10k/cdb2_ora_2018_RC-0001.trc'

banner Original

mrskew --rc=cull-snmfc.rc --where1='$sqlid eq q{07tutd2xkaqms}' $traceFile

for arraySize in 1 2 5 10 20 50 100 150 200 250 300 350 400 450 500
do
	echo
	echo "== $arraySize"
	ARRAYSIZE=$arraySize mrskew --rc=snmfc-savings.rc --where1='$sqlid eq q{07tutd2xkaqms}' $traceFile > /dev/null	
done

