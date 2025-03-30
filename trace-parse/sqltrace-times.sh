#!/usr/bin/env bash

# poc to interpret times in the sqltrace file
#

# set -u will break the array assignments
#set -u

: ${VERBOSE:=0}
: ${SQLID:=''}

#echo "SQLID: $SQLID"
#exit

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

display () {
	[ $VERBOSE -eq 1 ] && echo "$*"
}

#display "${dateRegex}T${timeRegex}${timezoneRegex}"

# '^*** [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}\+[0-9]{2}:[0-9]{2}$' 
startTime=$(grep -E "^*** ${dateRegex}T${timeRegex}${timezoneRegex}$" $traceFile | head -1 | awk '{print $2}') \
	|| { echo "Error: no timestamp found"; exit 1; }

# convert the timestamp to a format that date can understand
display "Start time: $startTime"
startTime=$(date -d "$startTime" '+%FT%T.%N')
display "Start time: $startTime"
 
# now convert that time to epoch
startTimeEpoch=$(date -d "$startTime" '+%s.%N')
display "Start time epoch: $startTimeEpoch"

#waitRegex="^WAIT.*nam='([^']+)'.*tim=([0-9]+)"
#eventRegex="^([A-Z]+).*tim=([0-9]+)"

waitRegex="^WAIT\s+#([0-9]):.*nam='([^']+)'.*tim=([0-9]+)"
eventRegex="^([A-Z]+)\s+#([0-9]+):.*tim=([0-9]+)"
parsingRegex="^PARSING IN CURSOR \#([0-9]+) len=([0-9]+) dep=([0-9]+) uid=([0-9]+) oct=([0-9]+) lid=([0-9]+) tim=([0-9]+) hv=([0-9]+) ad='([^']+)' sqlid='([^']+)'"

# now get the first 'tim=' value from the file
# this will be the first time after the start time
# this value is in microseconds
# for purposes of establishing timestamps, the first tim= is equivalent to the start time
startTimeMicroSecs=$(grep -E 'tim=[0-9]{1,}' $traceFile | head -1 | awk -F'tim=' '{print $2}')
prevTimeMicroSecs=$startTimeMicroSecs
display "First time: $startTimeMicroSecs"


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
declare cursorNumber=''

declare -A accumTimes

# now read the file getting the tim= values
while read -r line
do
	#echo line: $line
	# WAIT lines have ^WAIT...nam='some name'...tim=1234
	# all other lines have ^[EXEC|FETCH|PARSE|...)...tim=1234
	# For WAITS we want the WAIT, the event (nam=) and the time
	event=''
	lineType=''
	cursor=''

	if [[ $line =~ $waitRegex ]]; then
		cursor=${BASH_REMATCH[1]}
		nam=${BASH_REMATCH[2]}
		currTimeMicroSecs=${BASH_REMATCH[3]}
		lineType='WAIT'
	elif [[ $line =~ $eventRegex ]]; then
		event=${BASH_REMATCH[1]}
		cursor=${BASH_REMATCH[2]}
		currTimeMicroSecs=${BASH_REMATCH[3]}
		lineType='EVENT'
	elif [[ $line =~ $parsingRegex ]]; then
		event='PARSING'
		cursor=${BASH_REMATCH[1]}
		currTimeMicroSecs=${BASH_REMATCH[7]}
		lineType='EVENT'
	else
		echo "Error: line did not match expected format"
		echo "line: $line"
		echo "waitRegex: $waitRegex"
		echo "eventRegex: $eventRegex"
		exit 1
	fi

	# parsing in cursor line
	# PARSING IN CURSOR #140633838757592 len=226 dep=1 uid=0 oct=3 lid=0 tim=16593273447539 hv=3008674554 ad='47b1e5df8' sqlid='5dqz0hqtp9fru'
	if [[ -n $SQLID ]] && [[ $event == 'PARSING' ]]; then
		# if sqlid is found, then get the cursor number
		[[ $line =~ "sqlid='$SQLID'" ]] || continue
		[[ $line =~ 'CURSOR '\#([0-9]+) ]] && cursorNumber=${BASH_REMATCH[1]}
		display "line: $line"
		display "cursorNumber: $cursorNumber"
		# the cursor number could change if the cursor is closed and reopened or the SQL is re-parsed
		[[ -n $cursorNumber ]] && echo "Cursor number: $cursorNumber"
		[[ -z $cursorNumber ]] && { echo "Error: cursor number not found"; exit 1; }

		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	elif [[ $event ==	'PARSING' ]]; then
		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	fi

	if [[ -n $SQLID ]] && [[ -n $cursorNumber ]] && [[ $cursor != $cursorNumber ]] ; then
		#[[ $cursor != $cursorNumber ]] && echo "cursors are different: $cursor != $cursorNumber"
		#[[ $cursor == $cursorNumber ]] && echo "cursors are the same: $cursor == $cursorNumber"
		#[[ $cursor != $cursorNumber ]] &&
		#echo "Skipping cursor: $cursor"
		#echo "   cursorNumber: $cursorNumber"
		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	fi

	(( elapsedFromStartMicroSecs = $currTimeMicroSecs - $startTimeMicroSecs ))
	(( intervalFromPrevMicroSecs = $currTimeMicroSecs - $prevTimeMicroSecs ))

	# skip SQL*Net message from client lines if the time is greater than the threshold
	[[ $intervalFromPrevMicroSecs -gt $snmfcThreshold ]] && [[ $line =~ 'message from client' ]] && {
		display "Skipping SQL*Net message from client"
		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	}

	if [[ $lineType == 'WAIT' ]]; then
		display "WAIT time: $currTimeMicroSecs name: $nam"
		key="WAIT: $nam"
		(( accumTimes[$key] += intervalFromPrevMicroSecs ))
	else
		display "$event: time: $currTimeMicroSecs"
		(( accumTimes[$event] += intervalFromPrevMicroSecs ))
	fi

	(( workMicroSecs += intervalFromPrevMicroSecs ))

	currentEpochSeconds=$(echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " | bc)
	#echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " 
	currTimestamp=$(date -d "@$currentEpochSeconds" '+%FT%T.%N')

	display "             Event: $event"
	display "            Cursor: $cursor"
	display "        Start Time: $startTime"
	display "  Start time epoch: $startTimeEpoch"
	display "  Start time usecs: $startTimeMicroSecs"
	display "Current time usecs: $currTimeMicroSecs"
	display "Elapsed time usecs: $elapsedFromStartMicroSecs"
	display "Interval from prev: $intervalFromPrevMicroSecs"
	display "Current time epoch: $currTimestamp"
	display

	(( computedElapsedMicroSecs += intervalFromPrevMicroSecs ))

	prevTimeMicroSecs=$currTimeMicroSecs

done < <( grep -E 'tim=[0-9]{1,}' $traceFile )

echo
echo "   Total elapsed usecs: $elapsedFromStartMicroSecs"
echo "Computed elapsed usecs: $computedElapsedMicroSecs"
echo "    Work elapsed usecs: $workMicroSecs"
echo
 

for key in "${!accumTimes[@]}"
do
	seconds=$(echo "scale=9; ${accumTimes[$key]} / 1000000" | bc)
	printf "%50s: %12.6f\n" "$key" $seconds
done | awk '{ print $NF, $0 }' | sort -nr | cut -d' ' -f2-





