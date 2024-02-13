#!/usr/bin/env bash

: << 'COMMENT'

Walk through a single directory of trace files, run tracefile-crop.sh for each file.

Output cropped file to new directory

COMMENT

declare tracefileDir=$1
declare tracefileCropDir=$2
set -u

: ${tracefileDir:?Trace File Directory Name required}
[ -r "$tracefileDir" -a -x "$tracefileDir" ] || { echo "cannot read/exe $tracefileDir"; exit 1; }

: ${tracefileCropDir:?Trace File Crop Directory Name required}
mkdir -p $tracefileCropDir
[ -r "$tracefileCropDir" -a -x "$tracefileCropDir" ] || { echo "cannot read/exe $tracefileCropDir"; exit 1; }

banner () {
	echo
	echo '############################################################'
	echo "## $@"
	echo '############################################################'
	echo
}

for tracefile in $(cd $tracefileDir; ls -1 ) # | head -10 )
do
	banner $tracefile
	./tracefile-crop.sh $tracefileDir/$tracefile > $tracefileCropDir/$tracefile
done
