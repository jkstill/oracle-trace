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
startTimeuSecs=$(grep -E 'tim=[0-9]{1,}' $traceFile | head -1 | awk -F'tim=' '{print $2}')
prevTimeuSecs=$startTimeuSecs
echo "First time: $startTimeuSecs"


declare currTimeuSecs
declare elapsedFromStartuSecs
declare intervalFromPrevuSecs
declare currentEpochSeconds
declare currTimestamp
declare computedElapsedTime=0
declare computedElapseduSecs=0

# now read the file getting the tim= values
while read -r line
do
	#echo line: $line
	# WAIT lines have ^WAIT...nam='some name'...tim=1234
	# all other lines have ^[EXEC|FETCH|PARSE|...)...tim=1234
	# For WAITS we want the WAIT, the event (nam=) and the time
	
	if [[ $line =~ $waitRegex ]]; then
		nam=${BASH_REMATCH[1]}
		currTimeuSecs=${BASH_REMATCH[2]}
		echo "WAIT name: $nam  time: $currTimeuSecs"
	elif [[ $line =~ $eventRegex ]]; then
		event=${BASH_REMATCH[1]}
		currTimeuSecs=${BASH_REMATCH[2]}
		echo "$event: time: $currTimeuSecs"
	else
		echo "Error: line did not match expected format"
		echo "line: $line"
		exit 1
	fi

	(( elapsedFromStartuSecs = $currTimeuSecs - $startTimeuSecs ))
	(( intervalFromPrevuSecs = $currTimeuSecs - $prevTimeuSecs ))

	currentEpochSeconds=$(echo "scale=9; $startTimeEpoch + ( $intervalFromPrevuSecs / 1000000) " | bc)
	echo "scale=9; $startTimeEpoch + ( $intervalFromPrevuSecs / 1000000) " 
	currTimestamp=$(date -d "@$currentEpochSeconds" '+%FT%T.%N')

	echo "        Start Time: $startTime"
	echo "  Start time epoch: $startTimeEpoch"
	echo "  Start time usecs: $startTimeuSecs"
	echo "Current time usecs: $currTimeuSecs"
	echo " Elapsed time secs: $elapsedFromStartuSecs"
	echo "Interval from prev: $intervalFromPrevuSecs"
	echo "Current time epoch: $currTimestamp"
	echo

	(( computedElapseduSecs += intervalFromPrevuSecs ))

	prevTimeuSecs=$currTimeuSecs

done < <( grep -E 'tim=[0-9]{1,}' $traceFile )

echo
echo "   Total elapsed usecs: $elapsedFromStartuSecs"
echo "Computed elapsed usecs: $computedElapseduSecs"
 
# copilot added this comment
#The script reads the trace file and extracts the time values. It then converts the time values to epoch time and prints the elapsed time from the start of the trace file. 
#The script is a proof of concept and is not intended to be used in production. 
#Share this: Twitter Twitter Facebook Facebook 
#Like this: Like   Loadingjson 
#This website uses cookies to improve your experience. We'll assume you're ok with this, but you can opt-out if you wish.  Accept






