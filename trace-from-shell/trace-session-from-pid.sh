#!/usr/bin/env bash

: << 'COMMENT'

Given an OS PID, enabl SQL Trace on a session for a given amount of time.

For simplicity, the time should be specified in seconds

Do not enable capturing Bind Values unless there is a need for it.

Bind have been enabled.

If row by row processing occurs, we can see if it is due to selecting only 1 row.
If that is the case, a new bind value will appear between each 1 row fetch.


COMMENT

oracleSid=${1:?'Please send ORACLE_SID'}; shift
pid=${1:?'Please send PID'}; shift
secondsToTrace=${1:?'Please send Seconds to Trace'}; shift

[[ $secondsToTrace =~ ^[0-9]+$ ]] || { echo secondsToTrace must be numeric; exit 1; }

#traceFileID=$(echo "$@" | sed -r -e 's/[[:space:]]/-/g')
#echo "traceFileID: $traceFileID"

#[[ -z $traceFileID ]] && { echo tracefile ID required; exit 1; }

#echo ORACLE_SID: $oracleSid
#echo PID: $pid

export PATH=$PATH:/usr/local/bin

. oraenv <<< $oracleSid 2>&1 >/dev/null

LOCKFILE=/tmp/trace-setup-${pid}.lock

function scriptLock	 {
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
		trap 'rm -f "$MY_LOCKFILE"; exit $?' INT TERM EXIT
		return 0
	else
		echo "Failed to acquire $LOCKFILE. Held by $(cat $LOCKFILE)"
		exit 1
	fi
}

function scriptUnlock {
	rm -f "$LOCKFILE"
	trap - INT TERM EXIT
}

logDir='logs';

mkdir -p $logDir

logFile=$logDir/trace-session-${pid}-$(date +%Y-%m-%d_%H-%M-%S).log

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# process substitution
# clear/recreate the logfile
> $logFile
exec 1> >(tee -ia $logFile)
exec 2> >(tee -ia $logFile >&2)

scriptLock $LOCKFILE

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
		and s.process = '$pid';

	prompt ORACLE_SID: $oracleSid
	prompt ORACLE_PID: $pid
	prompt Trace File ID:  &u_program
	prompt sid: &u_sid
	prompt serial: &u_serial

	prompt setting tracefile parameters
	oradebug setorapid &u_orapid
	oradebug unlimit
	-- setting the tracefile id causes ORA-32522: restricted heap violation while executing ORADEBUG command: [kghalo bad heap ds] [0x012E314E8] [0x06014A888]
	-- it appears to be non-fatal, and it does seem to work
	oradebug settracefileid &u_program
	oradebug setmypid

	prompt enable trace
	exec dbms_monitor.session_trace_enable( session_id => '&u_sid',  serial_num => '&u_serial', binds => true, waits => true, plan_stat => 'FIRST_EXECUTION')
	prompt sleeping $secondsToTrace seconds
	exec dbms_lock.sleep($secondsToTrace)
	prompt disable trace
	exec dbms_monitor.session_trace_disable( session_id => '&u_sid',  serial_num => '&u_serial')

	exit

EOF

rc=$?

case $rc in 
	11)
		echo "trace script died with os error";
		scriptUnlock;
		exit $rc;;
	12)
		echo "trace script died with os sql error";
		scriptUnlock;
		exit $rc;;
	0) ;;
	*)
		echo "trace script died with unknown error - $rc";
		scriptUnlock;
		exit $rc;;
esac


scriptUnlock


