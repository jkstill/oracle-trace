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
	elapsedFromTrace=0

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

	# skip SQL*Net message from client lines if the time is greater than the threshold
	#[[ $intervalFromPrevMicroSecs -ge $snmfcThreshold ]] && [[ $line =~ 'message from client' ]] && {
	[[ $elapsedFromTrace -ge $snmfcThreshold ]] && [[ $line =~ 'message from client' ]] && {
		display "Skipping SQL*Net message from client"
		prevTimeMicroSecs=$currTimeMicroSecs
		continue
	}

	(( elapsedFromStartMicroSecs = $currTimeMicroSecs - $startTimeMicroSecs ))
	(( intervalFromPrevMicroSecs = $currTimeMicroSecs - $prevTimeMicroSecs ))

	if [[ $lineType == 'WAIT' ]]; then
		display "WAIT time: $currTimeMicroSecs name: $nam"
		[[ -z $nam ]] && { echo "Error: nam not found"; exit 1; }
		key="WAIT: $nam"
		[[ $key == 'WAIT' ]] && { 
			echo "Error: key is WAIT"
			exit 1
		}
		#(( accumTimes["$key"] += intervalFromPrevMicroSecs ))
		(( accumTimes["$key"] += elapsedFromTrace ))
	elif [[ $lineType == 'EVENT' ]]; then
		display "$event: time: $currTimeMicroSecs"
		[[ -z $event ]] && { echo "Error: event not found"; exit 1; }
		[[ $event == 'WAIT' ]] && { 
			echo "Error: event is WAIT"
			echo "line: $line"
			exit 1
		}
		#(( accumTimes["$event"] += intervalFromPrevMicroSecs ))
		(( accumTimes["$event"] += elapsedFromTrace ))
	else
		echo "Error: unknown line type"
		echo "line: $line"
		exit 1
	fi

	(( totalElapsedFromTrace += elapsedFromTrace ))
	#echo "Elapsed from trace: $totalElapsedFromTrace"

	(( workMicroSecs += intervalFromPrevMicroSecs ))
	[[ VERBOSE -eq 1 ]] && currentEpochSeconds=$(echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " | bc)
	#echo "scale=9; $startTimeEpoch + ( $intervalFromPrevMicroSecs / 1000000) " 
	[[ VERBOSE -eq 1 ]] && currTimestamp=$(date -d "@$currentEpochSeconds" '+%FT%T.%N')

	display "             Event: $event"
	display "            Cursor: $cursor"
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

done < <( grep -E 'tim=[0-9]{1,}' $traceFile )

echo
echo "   Total elapsed usecs: $elapsedFromStartMicroSecs"
echo "Computed elapsed usecs: $computedElapsedMicroSecs"
echo "    Work elapsed usecs: $workMicroSecs"

echo
echo -n "Elapsed from trace: "; printf "%12.6f\n" $(echo "scale=6; $totalElapsedFromTrace / 1000000" | bc)
echo
 
for key in "${!accumTimes[@]}"
do
	seconds=$(echo "scale=9; ${accumTimes["$key"]} / 1000000" | bc)
	printf "%50s: %12.6f\n" "$key" $seconds
done | awk '{ print $NF, $0 }' | sort -nr | cut -d' ' -f2-





