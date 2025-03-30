#!/usr/bin/env bash

# get SQL Statements from SQL Trace file
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

display () {
	[ $VERBOSE -eq 1 ] && echo "$*"
}

sqlidRegex="sqlid='([0-9a-zA-Z]+)'"
readSQL=0
sqlLineCount=0

declare -A sqls

while IFS='' read -r line
do

	[[ $line =~ 'END OF STMT' ]] && [[ $readSQL -eq 1 ]] && {
		#echo "SQLID: $foundSqlID"
		#echo "$sql"
		sqls[$foundSqlID]="$sql"
		readSQL=0
		foundSqlID=''
		sql=''
		sqlLineCount=0
		continue
	}

	[[ $readSQL -eq 1 ]] && {
		[[ $sqlLineCount -gt 0 ]] && sql+="\n"
		sql+="$line" 
		((sqlLineCount++))
		display "sql: $sql"
		continue
	}

	[[ $line =~ 'PARSING IN CURSOR' ]] && {
		# PARSING IN CURSOR #140633838757592 len=226 dep=1 uid=0 oct=3 lid=0 tim=16593273447539 hv=3008674554 ad='47b1e5df8' sqlid='5dqz0hqtp9fru'
		# get the SQLID
		#echo "sqlid line: $line"
		
		#[[ $line =~ 'sqlid=.([0-9a-z]+).' ]] && {
		[[ $line =~ $sqlidRegex ]] && {
			#echo "Assigning SQLID"
			foundSqlID=${BASH_REMATCH[1]}
		}
		[[ -z $foundSqlID ]] && { 
			echo "Error: SQLID not found"
			echo "line: $line"
			exit 1
		}

		display "sqlid: $foundSqlID"

		[[ -n $foundSqlID ]] && readSQL=1 && continue
	
	}

done < $traceFile

# if SQLID was set, then display only that SQL
# raise an error if SQLID is not found
if [ -n "$SQLID" ] && [ -z "${sqls[$SQLID]}" ]
then
	echo "Error: SQLID $SQLID not found"
	exit 1
fi

# display the SQL Statements
for sqlid in "${!sqls[@]}"
do
	[ -n "$SQLID" ] && [[ $sqlid != $SQLID ]] && continue
	echo "SQLID: $sqlid"
	echo -e "${sqls[$sqlid]}"
	echo "---------------------------------"
done

