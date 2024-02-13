#!/usr/bin/env bash

: << 'COMMENT'

Given an OS PID, enabl SQL Trace on a session for a given amount of time.

For simplicity, the time should be specified in seconds

Do not enable capturing Bind Values unless there is a need for it.

Bind have been enabled.

If row by row processing occurs, we can see if it is due to selecting only 1 row.
If that is the case, a new bind value will appear between each 1 row fetch.

Called as:

  ./trace-session-from-pid-dup.sh  $sessionOracleSID $osPID $oraclePID $traceFileName $dupFilePID $traceSeconds $truncateInterval

COMMENT

oracleSid=${1:?'Please send ORACLE_SID'}; shift
osPID=${1:?'Please send osPID'}; shift
oraclePID=${1:?'Please send oraclePID'}; shift
traceFileName=${1:?'Please send tracefile name'}; shift
dupFilePID=${1:?'Please send duplicate file job PID'}; shift
secondsToTrace=${1:?'Please send Seconds to Trace'}; shift
truncateInterval=${1:?'Please send Truncate Interval Seconds'}; shift

[[ $secondsToTrace =~ ^[0-9]+$ ]] || { echo secondsToTrace must be numeric; exit 1; }
[[ $truncateInterval =~ ^[0-9]+$ ]] || { echo truncateInterval must be numeric; exit 1; }

osCMD=$(ps -hp $osPID -o cmd)

cat <<-EOF

         oracleSid: $oracleSid
             osPID: $osPID
         oraclePID: $oraclePID
     traceFileName: $traceFileName
        dupFilePID: $dupFilePID
    secondsToTrace: $secondsToTrace
  truncateInterval: $truncateInterval
    secondsToTrace: $secondsToTrace
  truncateInterval: $truncateInterval
             osCMD: $osCMD

EOF

[[ -z $osCMD ]] && { echo "failed to set osCMD for osPID: $osPID"; exit 1; }

#traceFileID=$(echo "$@" | sed -r -e 's/[[:space:]]/-/g')
#echo "traceFileID: $traceFileID"

#[[ -z $traceFileID ]] && { echo tracefile ID required; exit 1; }

#echo ORACLE_SID: $oracleSid
#echo oraclePID: $oraclePID

export PATH=$PATH:/usr/local/bin

. oraenv <<< $oracleSid 2>&1 >/dev/null

LOCKFILE=/tmp/trace-setup-${oraclePID}.lock

scriptLock () {
	typeset MY_LOCKFILE
	MY_LOCKFILE=$1
	SCRIPTNAME=$(basename $0)

	# remove stale lockfile
	[ -r "$MY_LOCKFILE" ] && {
		PID=$(cat $MY_LOCKFILE)
		ACTIVE=$(ps -p $PID --no-headers -o cmd | grep --color=never $SCRIPTNAME)
		if [ -z "$ACTIVE" ]; then
			rm -f $MY_LOCKFILE
		fi
	}

	# set lock

	if (set -o noclobber; echo "$$" > "$MY_LOCKFILE") 2> /dev/null; then
		#trap 'rm -f "$MY_LOCKFILE"; exit $?' INT TERM EXIT
		trap "scriptUnlock; exit 0" INT TERM EXIT QUIT
		return 0
	else
		echo "Failed to acquire $LOCKFILE. Held by $(cat $LOCKFILE)"
		return 1
	fi
}

scriptUnlock () {
	local MY_LOCKFILE=$1
	rm -f "$MY_LOCKFILE"
	ps -hp $dupFilePID -o cmd | grep 'tail -F' >/dev/null && { kill $dupFilePID; }
	trap - INT TERM EXIT QUIT
}

cleanup () {
	scriptUnlock
	exit 0
}

isTracedSessionAlive () {
	local pidToCheck=$1; shift
	local cmdToCheck="$@"

	testCMD=$(ps -hp $pidToCheck -o cmd)
	
	[[ $testCMD != $cmdToCheck ]] && {
		echo "isTracedSessionAlive: $pidToCheck $cmdToCheck is dead"
		return 1
	}

	[[ -z $testCMD ]] && {
		echo "isTracedSessionAlive: $pidToCheck $cmdToCheck is dead"
		return 1
	}

	return 0
}


logDir='logs'

mkdir -p $logDir

logFile="$logDir/trace-session-${oraclePID}-$(date +%Y-%m-%d_%H-%M-%S).log"
echo "logFile: $logFile"

#exit

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# process substitution
: << 'FAIL'

 for some reason this does not work in this called script when it has also bern
 run in the caller, which uses a different logfile

 see p1.sh and p2.sh for working example

FAIL

# clear/recreate the logfile
#> $logFile
# exec 1> >(tee -ia $logFile)
# exec 2> >(tee -ia $logFile >&2)

scriptLock $LOCKFILE
lockResult=$?
[[ $lockResult != 0 ]] && { echo "could not acquire lock - lockfile: $LOCKFILE"; scriptUnlock; exit 1; }


trap "cleanup" INT TERM EXIT QUIT

###########################
# setup the trace
###########################

sqlplus -S /nolog  <<-EOF

	connect / as sysdba

	whenever oserror exit 11
	whenever sqlerror exit 12

	set timing off
	set term on

	clear col
	clear break
	clear computes

	btitle ''
	ttitle ''

	btitle off
	ttitle off

	set newpage 1
	set tab off

	set pause off echo off term on feed off head off  verify off
	set linesize 200 trimspool on

	set pagesize 0 linesize 200 trimspool on
	set feed off


	col sid new_value u_sid  noprint format 999999999
	col oracle_pid new_value u_oracle_pid noprint format 99999999
	col serial# new_value u_serial noprint format 99999999
	col program new_value u_program noprint
	col orapid new_value u_orapid noprint
	col tracefile new_value u_tracefile noprint format a200

	select s.sid, s.serial#, p.spid  oracle_pid, p.pid orapid,
		regexp_replace(substr(s.program,1,20),'[[:space:]()@]','-',1,0) program
	from v\$session s, v\$process p
	where p.addr = s.paddr
		and s.process = '$oraclePID';

	prompt ORACLE_SID: $oracleSid
	prompt ORACLE_PID: $oraclePID
	prompt Trace File ID:  &u_program
	prompt sid: &u_sid
	prompt serial: &u_serial

	prompt setting tracefile parameters
	oradebug setorapid &u_orapid
	oradebug unlimit
	-- setting the tracefile id causes ORA-32522: restricted heap violation while executing ORADEBUG command: [kghalo bad heap ds] [0x012E314E8] [0x06014A888]
	-- it appears to be non-fatal, and it does seem to work
	-- oradebug settracefileid &u_program
	oradebug setmypid

	prompt enable trace
	exec dbms_monitor.session_trace_enable( session_id => '&u_sid',  serial_num => '&u_serial', binds => true, waits => true, plan_stat => 'FIRST_EXECUTION')

	exit

EOF

rc=$?

case $rc in 
	21) echo "trace script died with os error";;
	22) echo "trace script died with os sql error";;
	0) ;;
	*) echo "trace script died with unknown error - $rc";;
esac

[[ $rc -ne 0 ]] && {
	scriptUnlock $LOCKFILE
	exit $rc
}

#########################################################
# loop and truncate source trace file until time is up
#########################################################


# passed as a parameter
#traceFileName=$(./trace-file-from-pid.sh $oracleSid $oraclePID )
#echo "traceFileName-2: $traceFileName" 

usedSleepSeconds=0

cat <<-EOF

   secondsToTrace: $secondsToTrace
 truncateInterval: $truncateInterval

EOF

while :
do

	isTracedSessionAlive $osPID "$osCMD" || {
		echo
		echo "traced session $osPID '$osCMD' has exited"
		echo "shutting down trace"
		break
	}

	echo sleeping $truncateInterval seconds
	sleep $truncateInterval

	> $traceFileName

	(( usedSleepSeconds += truncateInterval ))

	[[ $usedSleepSeconds -ge $secondsToTrace ]] && { break; }

done

rc=$?

case $rc in 
	21) echo "trace script died with os error";;
	22) echo "trace script died with os sql error";;
	0) ;;
	*) echo "trace script died with unknown error - $rc";;
esac

[[ $rc -ne 0 ]] && {
	scriptUnlock $LOCKFILE
	exit $rc
}

##################
# disable trace
##################

sqlplus -S /nolog  <<-EOF

	connect / as sysdba

	whenever oserror exit 31
	whenever sqlerror exit 32

	set timing off
	set term on

	clear col
	clear break
	clear computes

	btitle ''
	ttitle ''

	btitle off
	ttitle off

	set newpage 1
	set tab off

	set pause off echo off term on feed off head off  verify off
	set linesize 200 trimspool on

	set pagesize 0 linesize 200 trimspool on
	set feed off


	col sid new_value u_sid  noprint format 999999999
	col oracle_pid new_value u_oracle_pid noprint format 99999999
	col serial# new_value u_serial noprint format 99999999
	col program new_value u_program noprint
	col orapid new_value u_orapid noprint
	col tracefile new_value u_tracefile noprint format a200

	select s.sid, s.serial#, p.spid  oracle_pid, p.pid orapid,
		regexp_replace(substr(s.program,1,20),'[[:space:]()@]','-',1,0) program
	from v\$session s, v\$process p
	where p.addr = s.paddr
		and s.process = '$oraclePID';

	prompt ORACLE_SID: $oracleSid
	prompt ORACLE_PID: $oraclePID
	prompt Trace File ID:  &u_program
	prompt sid: &u_sid
	prompt serial: &u_serial


	prompt disable trace
	exec dbms_monitor.session_trace_disable( session_id => '&u_sid',  serial_num => '&u_serial')

	exit

EOF

rc=$?

case $rc in 
	31) echo "trace script died with os error";;
	32) echo "trace script died with sql error";;
	0) ;;
	*) echo "trace script died with unknown error - $rc";;
esac

scriptUnlock $LOCKFILE
exit $rc

