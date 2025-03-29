#!/usr/bin/env bash

# poc to interpret times in the sqltrace file
#

set -u

traceFile=$1
[ -z "$traceFile" ] && echo "Usage: $0 <tracefile>" && exit 1
[ -r "$traceFile" ] || { echo "Error: $traceFile not found"; exit 1; }

# assumed that trace file has the following format
# YYYY-MM-DDTHH:MM:SS.ssssss+00:00
# 2025-03-14T13:36:06.953105+00:00
# this has been true since 12c

# *** 2025-03-14T13:55:05.123571+00:00
dateRegex='[0-9]{4}-[0-9]{2}-[0-9]{2}'
timeRegex='[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}'
timezoneRegex='\+[0-9]{2}:[0-9]{2}'

echo "${dateRegex}T${timeRegex}${timezoneRegex}"

# '^*** [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}\+[0-9]{2}:[0-9]{2}$' 
startTime=$(grep -E "^*** ${dateRegex}T${timeRegex}${timezoneRegex}$" $traceFile | head -1 | awk '{print $2}') \
	|| { echo "Error: no timestamp found"; exit 1; }

# convert the timestamp to a format that date can understand
echo "Start time: $startTime"
startTime=$(date -d "$startTime" '+%FT%T.%N')
echo "Start time: $startTime"
 
# now convert that time to epoch
startTimeEpoch=$(date -d "$startTime" '+%s.%N')
echo "Start time epoch: $startTimeEpoch"

waitRegex="^WAIT.*nam='([^']+)'.*tim=([0-9]+)"
eventRegex="^([A-Z]+).*tim=([0-9]+)"

# now get the first 'tim=' value from the file
# this will be the first time after the start time
# this value is in microseconds
# for purposes of establishing timestamps, the first tim= is equivalent to the start time
startTimeMicroSecs=$(grep -E 'tim=[0-9]{1,}' $traceFile | head -1 | awk -F'tim=' '{print $2}')
prevTimeMicroSecs=$startTimeMicroSecs
echo "First time: $startTimeMicroSecs"


declare snmfcThreshold=1000000
declare currTimeMicroSecs
declare elapsedFromStartMicroSecs
declare intervalFromPrevMicroSecs
declare currentEpochSeconds
declare currTimestamp
declare computedElapsedTime=0
declare computedElapsedMicroSecs=0
# work usecs is the total time minus the snmfc times that are skipped due to exceeding the threshold
declare workMicroSecs=0
declare lineType=''

# now read the file getting the tim= values
while read -r line
do
	#echo line: $line
	# WAIT lines have ^WAIT...nam='some name'...tim=1234
	# all other lines have ^[EXEC|FETCH|PARSE|...)...tim=1234
	# For WAITS we want the WAIT, the event (nam=) and the time
	
	if [[ $line =~ $waitRegex ]]; then
		nam=${BASH_REMATCH[1]}
		currTimeMicroSecs=${BASH_REMATCH[2]}
		lineType='WAIT'
	elif [[ $line =~ $eventRegex ]]; then
		event=${BASH_REMATCH[1]}
		currTimeMicroSecs=${BASH_REMATCH[2]}
		lineType='EVENT'
	else
		echo "Error: line did not match expected format"
		echo "line: $line"
		exit 1
	fi

	(( elapsedFromStartMicroSecs = $currTimeMicroSecs - $startTimeMicroSecs ))
	(( intervalFromPrevMicroSecs = $currTimeMicroSecs - $prevTimeMicroSecs ))

	# skip SQL*Net message from client lines if the time is greater than the threshold
	[[ $intervalFromPrevMicroSecs -gt $snmfcThreshold ]] && [[ $line =~ 'message from client' ]] && {
		echo "Skipping SQL*Net message from client"
		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	}

	if [[ $lineType == 'WAIT' ]]; then
		echo "WAIT time: $currTimeMicroSecs name: $nam"
	else
		echo "$event: time: $currTimeMicroSecs"
	fi

	(( workMicroSecs += intervalFromPrevMicroSecs ))

	currentEpochSeconds=$(echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " | bc)
	#echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " 
	currTimestamp=$(date -d "@$currentEpochSeconds" '+%FT%T.%N')

	echo "        Start Time: $startTime"
	echo "  Start time epoch: $startTimeEpoch"
	echo "  Start time usecs: $startTimeMicroSecs"
	echo "Current time usecs: $currTimeMicroSecs"
	echo " Elapsed time secs: $elapsedFromStartMicroSecs"
	echo "Interval from prev: $intervalFromPrevMicroSecs"
	echo "Current time epoch: $currTimestamp"
	echo

	(( computedElapsedMicroSecs += intervalFromPrevMicroSecs ))

	prevTimeMicroSecs=$currTimeMicroSecs

done < <( grep -E 'tim=[0-9]{1,}' $traceFile )

echo
echo "   Total elapsed usecs: $elapsedFromStartMicroSecs"
echo "Computed elapsed usecs: $computedElapsedMicroSecs"
echo "    Work elapsed usecs: $workMicroSecs"
 





