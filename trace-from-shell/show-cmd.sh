#!/usr/bin/env bash

[ -z "$1" -o -z "$2" -o -z "$3" ] && {
	echo 
	echo $0 oracle_sid username command
	echo
	exit 1
}

debug='N'

[[ $debug == 'Y' ]] && {

cat <<-EOF >&2

show-cmd.sh

  oracle_sid: $1
    username: $2
     command: $3


EOF


}

PATH=/usr/local/bin:$PATH; export PATH

. oraenv <<< $1 > /dev/null

while read line
do
	echo "$line"
done < <(
sqlplus -S -L / as sysdba  <<-EOF

set pause off
set echo off
set timing off
set trimspool on
set verify off

clear col
clear break
clear computes

btitle ''
ttitle ''

btitle off
ttitle off

set newpage 1

set tab off

set pagesize 0 linesize 200
set term on
set feed off

select
	--s.username,
	--s.machine,
	--s.osuser,
	p.spid os_pid,
	s.process oracle_pid,
	'"' || s.program || '"'
from v\$session s, v\$process p
where s.username like upper('$2')
	and s.program like '$3%'
	and p.addr = s.paddr
	order by 1
/

exit

EOF
)



