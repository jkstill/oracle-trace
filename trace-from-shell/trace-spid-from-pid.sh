#!/usr/bin/env bash

: << 'COMMENT'

Given an OS PID, get the Oracle Server PId

COMMENT

oracleSid=${1:?'Please send ORACLE_SID'}; shift
pid=${1:?'Please send PID'}; shift

export PATH=$PATH:/usr/local/bin

. oraenv <<< $oracleSid 2>&1 >/dev/null

sqlplus -S /nolog  <<-EOF | tail -1

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

	col spid new_value u_spid noprint 

	select p.spid
	from v\$session s, v\$process p
	where p.addr = s.paddr
		and s.process = '$pid';

	prompt &u_spid

	exit

EOF

rc=$?

case $rc in 
	11)
		echo "trace script died with os error";
		exit $rc;;
	12)
		echo "trace script died with os sql error";
		exit $rc;;
	0) ;;
	*)
		echo "trace script died with unknown error - $rc";
		exit $rc;;
esac

