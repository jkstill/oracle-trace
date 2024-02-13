#!/usr/bin/env bash

usage () {
	cat <<-EOF

-u username - can use wildcards, is converted to uppercase
-c command to look for (uses cmd + wildcard internally)
-s seconds to run trace
-o Oracle SID - no checking done, is assumed correct.
-d display only - just show sessions
-h help

EOF

}

displayOnly='N'

while getopts u:c:s:o:dh arg
do
	case $arg in
		h) usage; exit;;
		u) username=$OPTARG;;
		s) traceSeconds=$OPTARG;;
		c) cmdToCheck=$OPTARG;;
		o) testOracleSID=$OPTARG;;
		d) displayOnly='Y';;
	esac
done

[[ -z $traceSeconds ]] && { usage; exit 1; }
[[ -z $username ]] && { usage; exit 2; }
[[ -z $cmdToCheck ]] && { usage; exit 3; }
[[ -z $testOracleSID ]] && { usage; exit 4; }

#upper case username
username=${username^^}

PATH=/usr/local/bin/:$PATH; export PATH
export testOracleSID
. oraenv <<< $testOracleSID > /dev/null


emailAddressList=' still@pythian.com  jstill@pplweb.com '

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

while read osPID oraclePID CMD
do
	banner "Oracle PID: $oraclePID  CMD: $CMD"

	# get session ORACLE_SID
	sessionOracleSID=$(strings /proc/$osPID/environ | grep ORACLE_SID | cut -f2 -d=)
	echo "  Session Oracle SID: $sessionOracleSID"

	#. /usr/local/bin/oraenv <<< $sessionOracleSID > /dev/null

	#echo "ORACLE_SID: $ORACLE_SID"

	traceFileName=$(./trace-file-from-pid.sh $ORACLE_SID $oraclePID )
	[[ $? -ne 0 ]] && { die "Host: $HOSTNAME Oracle SID: $ORACLE_SID: called ./trace-file-from-pid.sh $ORACLE_SID $oraclePID" ; }
	echo "  traceFileName: $traceFileName"

	[[ $displayOnly == 'Y' ]] && { continue; } 

	# setup the trace
	echo "tracing oraclePID: $oraclePID for $traceSeconds seconds"
	nohup ./trace-session-from-pid.sh  $sessionOracleSID $oraclePID $traceSeconds &
	[[ $? -ne 0 ]] && { die "Host: $HOSTNAME Oracle SID: $ORACLE_SID: called nohup ./trace-session-from-pid.sh  $sessionOracleSID $oraclePID $traceSeconds"; }

	echo "Host: $HOSTNAME Oracle SID: $sessionOracleSID: tracefile: $traceFileName osPID: $osPID" \
		| mailx -s "$cmdToCheck trace" $emailAddressList

done < <(./show-cmd.sh $testOracleSID $username $cmdToCheck)

