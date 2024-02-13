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

for file in $( ls -1tr trace/sqlrun-server/select-10k/*.trc)
do
	#echo
	#echo $file
	# the array size requested is probably not what is requested
	#arraySize=$(echo $file | awk -F- '{ print $NF }' | cut -f1 -d\. | sed -r -e 's/^0+//' )

	#mrskew --where1='$sqlid =~ /07tutd2xkaqms/' --nohead --csv  --nofoot --name='FETCH'  $file  | cut -d, -f2

	arraySize=$(mrskew --top=0  --nohistogram --where1='$sqlid =~ /07tutd2xkaqms/' --group='$r . q{:} . $line' --nohead  --nofoot --name='FETCH' $file | cut -f1 -d: | sort  | uniq -c  | tail -1 | awk '{ print $2 }')

	export durationSNMFC=$(mrskew --rc=cull-snmfc.rc --where1='$sqlid =~ /07tutd2xkaqms/' --nohead --csv  --nofoot --name='message from client'  $file  | cut -d, -f2)
	#echo "durationSNMFC:  $durationSNMFC"
	# the 50000 is 5 iterations of 10k rows in each test
	timePerRow=$(echo $durationSNMFC | perl -e '$n=<STDIN>; $x =  $n / 50000; printf qq{%s\n}, int($x * 1e6)')

	echo "$arraySize => $timePerRow,"
done
