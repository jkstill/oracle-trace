#!/usr/bin/env bash

# poc to interpret times in the sqltrace file
# this is only known to work with 19c at this time
# it may work with 12c and later

: << 'COMMENT'

To be accurate, the waits and events following an WAIT or EVENT should be attributed to the next SQL Execution, Fetch, or Parse event.

for instance, 'db file sequential read' should be attributed to the next 'FETCH' event.

As this script is only showing totals by default, it does not matter.

Is a single SQL is filtered, then it will matter.

COMMENT

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
[[ VERBOSE -eq 1 ]] && startTimeEpoch=$(date -d "$startTime" '+%s.%N')
display "Start time epoch: $startTimeEpoch"

# WAIT #140606563493592: nam='PGA memory operation' ela= 8 p1=65536 p2=1 p3=0 obj#=-1 tim=16592944510045
waitRegex="^WAIT\s+#([0-9]+):.*nam='([^']+)'.*ela= ([0-9]+).*tim=([0-9]+)"
# FETCH #140048500767072:c=0,e=2,p=0,cr=1,cu=0,mis=0,r=1,dep=1,og=4,plh=1430409510,tim=1659251011023
eventRegex="^([A-Z]+)\s+#([0-9]+):.*,e=([0-9]+).*tim=([0-9]+)"
# PARSING IN CURSOR #140048500765208 len=39 dep=1 uid=0 oct=3 lid=0 tim=16592510112511 hv=468172370 ad='59fe4ca90' sqlid='865qwpcdyggkk'
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
declare elapsedFromTrace
declare totalElapsedFromTrace=0
declare intervalFromPrevMicroSecs
declare currentEpochSeconds
declare currTimestamp
declare computedElapsedTime=0
declare computedElapsedMicroSecs=0
# work usecs is the total time minus the snmfc times that are skipped due to exceeding the threshold
declare workMicroSecs=0
declare lineType=''
declare sqlIdCursorNumber=''
declare currCursorNumber='NOOP'
declare prevCursorNumber='POON'
# txTime is a scrath buffer to hold the time for the current transaction
# it will be reset to 0 when a new cursor is executed
declare -A txTime
declare -A sqlIdTime
declare -A accumTimes

: << 'COMMENT'

Filtering on a single SQLID will require two passes.

As this is a Bash script, there are no complex data structures like a hash of arrays.

The first pass will find the cursor number(s) for the SQLID.

The second pass will accumulate the times for the cursor numbers.


COMMENT

declare -a cursorNumbers

cursorRegex=''

[[ -n $SQLID ]] && {
	# first pass
	#
	while read -r line
	do
		#echo $line
		if [[ $line =~ $parsingRegex ]]; then
			cursor="${BASH_REMATCH[1]}"
			currSqlID="${BASH_REMATCH[10]}"
			[[ $currSqlID == $SQLID ]] && cursorNumbers+=($cursor)
			#cursorNumbers+=($cursor)
		else
			echo "Error: line did not match expected format"
			echo "line: $line"
			exit 1
		fi

		#echo "Cursor: $cursor SQLID: $currSqlID"

	done < <( grep -E "$parsingRegex" $traceFile )

	for cursor in "${cursorNumbers[@]}"
	do
		#echo "Cursor: $cursor"
		cursorRegex+="|#${cursor}"
	done

	# exit if cursorRegex is empty
	[[ -z $cursorRegex ]] && { echo "Error: no cursor numbers found for SQLID $SQLID"; exit 1; }

}

# remove the leading pipe
# this is the regex to match the cursor numbers
cursorRegex=${cursorRegex#|}
#echo "Cursor regex: $cursorRegex"
#exit

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
	elapsedFromTrace=0

	[[ -n SQLID ]] && [[ ! $line =~ $cursorRegex ]] && continue

	display "============================="
	display "line: $line"


	# WAIT #140048500737752: nam='PGA memory operation' ela= 6 p1=65536 p2=1 p3=0 obj#=-1 tim=16592510109714
	if [[ $line =~ $waitRegex ]]; then
		cursor="${BASH_REMATCH[1]}"
		nam="${BASH_REMATCH[2]}"
		[[ -z $nam ]] && { echo "Error: nam not found"; exit 1; }
		elapsedFromTrace="${BASH_REMATCH[3]}"
		currTimeMicroSecs="${BASH_REMATCH[4]}"
		lineType='WAIT'
		display "lineType: $lineType"
	# FETCH #140048500767072:c=0,e=2,p=0,cr=1,cu=0,mis=0,r=1,dep=1,og=4,plh=1430409510,tim=1659251011023
	elif [[ $line =~ $eventRegex ]]; then
		event="${BASH_REMATCH[1]}"
		[[ -z $event ]] && { echo "Error: event not found"; exit 1; }
		cursor="${BASH_REMATCH[2]}"
		elapsedFromTrace="${BASH_REMATCH[3]}"
		currTimeMicroSecs="${BASH_REMATCH[4]}"
		lineType='EVENT'
		display "lineType: $lineType"
	elif [[ $line =~ $parsingRegex ]]; then
		event='PARSING'
		cursor="${BASH_REMATCH[1]}"
		currTimeMicroSecs="${BASH_REMATCH[7]}"
		elapsedFromTrace=0 # no time recorded for this event
		lineType='EVENT'
		display "lineType: $lineType"
	# commits
	elif [[ $line =~ 'XCTEND' ]]; then
		# example XCTEND line: XCTEND rlbk=0, rd_only=0, tim=16593273447539
		# parse the tim value
		[[ $line =~ 'tim=([0-9]+)' ]] && prevTimeMicroSecs=${BASH_REMATCH[1]}
		# no time recorded for this event
		(( accumTimes['XCTEND'] = 0 ))
		#echo "EXCTEND line: $line"
		continue
	else
		echo "Error: line did not match expected format"
		echo "line: $line"
		echo "waitRegex: $waitRegex"
		echo "eventRegex: $eventRegex"
		exit 1
	fi


	# skip SQL*Net message from client lines if the time is greater than the threshold
	#[[ $intervalFromPrevMicroSecs -ge $snmfcThreshold ]] && [[ $line =~ 'message from client' ]] && {
	[[ $elapsedFromTrace -ge $snmfcThreshold ]] && [[ $line =~ 'message from client' ]] && {
		display "Skipping SQL*Net message from client"
		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	}

	(( elapsedFromStartMicroSecs = $currTimeMicroSecs - $startTimeMicroSecs ))
	(( intervalFromPrevMicroSecs = $currTimeMicroSecs - $prevTimeMicroSecs ))

	key=''
	if [[ $lineType == 'WAIT' ]]; then
		display "WAIT time: $currTimeMicroSecs name: $nam"
		[[ -z $nam ]] && { echo "Error: nam not found"; exit 1; }
		key="WAIT: $nam"
		[[ $key == 'WAIT' ]] && { 
			echo "Error: key is WAIT"
			exit 1
		}
	elif [[ $lineType == 'EVENT' ]]; then
		display "$event: time: $currTimeMicroSecs"
		[[ -z $event ]] && { echo "Error: event not found"; exit 1; }
		key="$event"
		[[ $event == 'WAIT' ]] && { 
			echo "Error: event is WAIT"
			echo "line: $line"
			exit 1
		}
	else
		echo "Error: unknown line type"
		echo "line: $line"
		exit 1
	fi

	#(( accumTimes["$key"] += intervalFromPrevMicroSecs ))
	(( accumTimes["$key"] += elapsedFromTrace ))

	(( totalElapsedFromTrace += elapsedFromTrace ))
	#echo "Elapsed from trace: $totalElapsedFromTrace"

	(( workMicroSecs += intervalFromPrevMicroSecs ))
	[[ VERBOSE -eq 1 ]] && currentEpochSeconds=$(echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " | bc)
	#echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " 
	[[ VERBOSE -eq 1 ]] && currTimestamp=$(date -d "@$currentEpochSeconds" '+%FT%T.%N')

	display "             Event: $event"
	display "            Cursor: $currCursorNumber"
	display "        Start Time: $startTime"
	display "  Start time epoch: $startTimeEpoch"
	display "  Start time usecs: $startTimeMicroSecs"
	display "Current time usecs: $currTimeMicroSecs"
	display "Elapsed time usecs: $elapsedFromStartMicroSecs"
	display "Elapsed from trace: $totalElapsedFromTrace"
	display "Interval from prev: $intervalFromPrevMicroSecs"
	display "Current time epoch: $currTimestamp"
	display

	(( computedElapsedMicroSecs += intervalFromPrevMicroSecs ))

	prevTimeMicroSecs=$currTimeMicroSecs

done < <( grep -E "tim=[0-9]{1,}" $traceFile )

echo
echo "   Total elapsed usecs: $elapsedFromStartMicroSecs"
echo "Computed elapsed usecs: $computedElapsedMicroSecs"
echo "    Work elapsed usecs: $workMicroSecs"

echo
echo -n "Elapsed from trace: "; printf "%12.6f\n" $(echo "scale=6; $totalElapsedFromTrace / 1000000" | bc)
echo
 
totalSeconds=0


for key in "${!accumTimes[@]}"
do
	seconds=${accumTimes["$key"]} 
	(( totalSeconds += $seconds ))
done

for key in "${!accumTimes[@]}"
do
	seconds=$(echo "scale=9; ${accumTimes["$key"]} / 1000000" | bc)
	printf "%50s: %12.6f\n" "$key" $seconds
done | awk '{ print $NF, $0 }' | sort -nr | cut -d' ' -f2-

printf "%50s: %12.6f\n" "Total Seconds" $(echo "scale=9; $totalSeconds / 1000000" | bc)





