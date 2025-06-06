#!/usr/bin/env bash

# find the sqlid
# mrskew  --group='$sqlid . q{:} . substr($sql,0,50)'  trace/cdb1_ora_14973_PF-001.trc


# mrskew  --top=0 --group='$nam . sprintf(q{ : %3.5f},$e)'  --where1='$sqlid eq q{4y53369cbbaqf} and $nam eq q{FETCH}'  trace/cdb1_ora_14973_PF-001.trc

# snmfc
# mrskew  --top=0 --group='$nam . sprintf(q{ : %3.3f},$ela)'  --where1='$sqlid eq q{4y53369cbbaqf}'  --name='message from client'  trace/cdb1_ora_14973_PF-001.trc

#this one best for snmfc
# mrskew  --rc=p10.rc --top=0  --where1='$sqlid eq q{4y53369cbbaqf}'  --name='message from client'  trace/cdb1_ora_14973_PF-001.trc

# projected snmfc savings
# mrskew  --rc=snmfc-savings.rc  --where1='$sqlid eq q{4y53369cbbaqf}'  trace/cdb1_ora_14973_PF-001.trc


declare RPTTAG=''

while getopts t: arg
do
   case $arg in
      t) RPTTAG="$OPTARG-";shift;shift;;
   esac
done


logDir='logs';

mkdir -p $logDir

logFile="$logDir/mrskew-rpt-${RPTTAG}$(date +%Y-%m-%d_%H-%M-%S).log"

#echo RPTTAG: $RPTTAG
#echo logFile: $logFile
#echo files: $@
#exit


# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
# process substitution
# clear/recreate the logfile
> $logFile
exec 1> >(tee -ia $logFile)
exec 2> >(tee -ia $logFile >&2)


sqlID='4y53369cbbaqf'

declare -A arraySizeCompare=(
	[001]=100
	[005]=100
	[010]=100
	[020]=100
	[050]=500
	[100]=500
	[200]=1000
	[300]=1000
	[400]=2000
	[500]=2000
)

#for traceFile in $(ls -1 trace/*.trc| sort -t_ -k4)
: << HOWTOCALL

 ./mrskew-snmfc-savings.sh $(ls -1 trace/latency-0.2ms/*.trc| sort -t_ -k4)

 or , add a tag to the log name

 ./mrskew-snmfc-savings.sh -t 0.02ms $(ls -1 trace/latency-0.2ms/*.trc| sort -t_ -k4)

HOWTOCALL


for traceFile in $(ls -1 trace/*.trc| sort -t_ -k4)
do
	rows=$(echo $traceFile| cut -f4 -d_ | tr -d '[PF\-.trc]')

	# desired output is on STDERR
	while read a b c
	do
		echo a: $a
		echo b: $b
		echo c: $c
	done < <( ARRAYSIZE=${arraySizeCompare[$rows]} mrskew  --rc=snmfc-savings.rc  --where1="\$sqlid eq q{$sqlID}"  $traceFile >/dev/null)

done

echo
echo LogFile: $logFile
echo

