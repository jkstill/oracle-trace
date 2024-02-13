#!/usr/bin/env bash

source file-drain.conf

timeOutSeconds=300
timeOutIterations=12

mkdir -p $diagDest || { echo "could not create $diagDest"; exit 1; }
mkdir -p $copyDest || { echo "could not create $copyDest"; exit 1; }

traceFile=$diagDest/$traceFileName
dupFile=$copyDest/$traceFileName


rm -f $traceFile
touch $traceFile

tail -F $traceFile > $dupFile &
tailPID=$!

./file-fill.pl &
filefillPID=$!

echo traceFile: $traceFile
echo dupFile: $dupFile

cleanup () {
	echo
	echo Cleaning Up!
	kill $tailPID
	kill $filefillPID
	echo
	echo Exiting...
	echo
	exit 0
}

trap "cleanup" INT
trap "cleanup" TERM

for i in $(seq 1 $timeOutIterations)
do
	echo i: $i
	sleep $timeOutSeconds
	# '> file' or 'truncate file' may not change the number of bytes reported by ls or stat

	#> $traceFile
	printf "\n" > $traceFile
	echo "truncated $traceFile"

done

kill $tailPID
kill $filefillPID


echo " traceFile: $traceFile"
echo "   dupFile: $dupFile"

