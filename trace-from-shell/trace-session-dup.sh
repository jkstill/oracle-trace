#!/usr/bin/env bash


: << 'COMMENTS'

When you need trace files, and the diagnostic_dest is too small, and you cannot change it.

- create the trace file before tracing is started
- start tail -F to the copy location
- periodically truncate the trace file (Oracle handles this well)
- disable tracing when time is up

ToDo: gracefully exit early if the traced session exits

COMMENTS

emailAddressList=' still@pythian.com  jstill@pplweb.com '

usage () {
	cat <<-EOF

-u username - can use wildcards, is converted to uppercase
-c command to look for (uses cmd + wildcard internally)
-s seconds to run trace
-t seconds between trace file truncates
-o Oracle SID - no checking done, is assumed correct.
-p copy dir - the trace destination
-d display only - just show sessions
-h help

EOF

}

displayOnly='N'

while getopts u:c:s:t:o:p:dh arg
do
	case $arg in
		h) usage; exit;;
		u) username=$OPTARG;;
		s) traceSeconds=$OPTARG;;
		t) truncateInterval=$OPTARG;;
		c) cmdToCheck=$OPTARG;;
		o) testOracleSID=$OPTARG;;
		p) copyDir=$OPTARG;;
		d) displayOnly='Y';;
	esac
done


[[ -z $traceSeconds ]] && { usage; exit 1; }
[[ -z $truncateInterval ]] && { usage; exit 2; }
[[ -z $username ]] && { usage; exit 3; }
[[ -z $cmdToCheck ]] && { usage; exit 4; }
[[ -z $testOracleSID ]] && { usage; exit 5; }
[[ -z $copyDir ]] && { usage; exit 6; }

#upper case username
username=${username^^}

PATH=/usr/local/bin/:$PATH; export PATH
export testOracleSID
. oraenv <<< $testOracleSID > /dev/null

# set to the location where the trace file is to be copied
#copyDest='/mnt/zips/tmp/oracle/oracle-trace/copy'
copyDest="$copyDir/$ORACLE_SID"

mkdir -p $copyDest

[[ -w $copyDest ]] || {
	echo
	echo "cannot read $copyDest"
	echo "ls follows - it may not exist"
	ls -ld $copyDest
	echo
	exit 1
}


: << 'COMMENTS'

check for some running job, trace them for several minutes

COMMENTS

scriptHome=$(dirname -- "$( readlink -f -- "$0" )")

#echo scriptHome: $scriptHome

cd $scriptHome || { 
	echo
	echo could not cd to scriptHome: $scriptHome
	echo 
	exit 1
}


banner () {
	echo
	echo '###################################################################################'
	echo "## $@"
	echo '###################################################################################'
	echo
}

die () {
	echo '######################################'
	echo "## Error:  $@"
	echo '######################################'

	echo "$@" | mailx -s "$cmdToCheck trace" "$emailAddressList"
	exit 1
}

logDir='logs';
mkdir -p $logDir
logFile=$logDir/session-trace-$(date +%Y-%m-%d_%H-%M-%S).log

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# process substitution
# clear/recreate the logfile
> $logFile
exec 1> >(tee -ia $logFile)
exec 2> >(tee -ia $logFile >&2)

[[ $displayOnly == 'Y' ]] && { echo; echo 'display only - no tracing will be enabled'; echo; }

sessionCount=1

while read osPID oraclePID CMD
do
	banner "Oracle PID: $oraclePID  CMD: $CMD"

	traceFileName=$(./trace-file-from-pid.sh $ORACLE_SID $oraclePID )
	[[ $? -ne 0 ]] && { die "Host: $HOSTNAME Oracle SID: $ORACLE_SID: called ./trace-file-from-pid.sh $ORACLE_SID $oraclePID" ; }
	echo "  traceFileName: $traceFileName"


	[[ $sessionCount -ge 10 ]] && { break; }
	(( sessionCount++ ))

	[[ $displayOnly == 'Y' ]] && { continue; } 

	##################################
	## setup tail -F here 
	## see file-drain.sh proto script
	##################################

	# set to the tracefile location for this db
	diagDest=$(dirname $traceFileName)
	baseTraceFileName=$(basename $traceFileName)

	
	dupFile="$copyDest/$baseTraceFileName"
	echo "timeout $traceSeconds tail -F $traceFileName >> $dupFile "
	timeout $traceSeconds tail -F $traceFileName >> $dupFile &

	rc=$?
	dupFilePID=$!

	[[ $rc -ne 0 ]] && {
		echo
		echo "Error encountered creating dupFile"
		echo "             dupFile: $dupFile"
		echo "            diagDest: $diagDest"
		echo "       traceFileName: $traceFileName"
		echo "   baseTraceFileName: $baseTraceFileName"
		echo
		exit 1
	}


	# setup the trace
	echo "tracing oraclePID: $oraclePID for $traceSeconds seconds"
	./trace-session-from-pid-dup.sh  $ORACLE_SID $osPID $oraclePID "$traceFileName" $dupFilePID $traceSeconds $truncateInterval &
	rc=$?;
	[[ $rc -ne 0 ]] && { die "Host: $HOSTNAME Oracle SID: $ORACLE_SID: called ./trace-session-from-pid-dup.sh  $ORACLE_SID $oraclePID $traceSeconds"; }

	# wait a bit for sqlplus to start up
	#sleep 5
	bgTracePID=$!
	#sqlplusPID=$(pstree -apn  $bgTracePID | grep -oE 'sqlplus,[[:digit:]]+' | cut -f2 -d,)
	echo "bgTracePID: $bgTracePID"
	#echo "sqlplusPID: $sqlplusPID"


	echo "Host: $HOSTNAME Oracle SID: $ORACLE_SID: tracefile: $traceFileName osPID: $osPID" \
		| mailx -s "$cmdToCheck trace" $emailAddressList


done < <(./show-cmd.sh $ORACLE_SID $username $cmdToCheck)


