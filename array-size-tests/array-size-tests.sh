#!/usr/bin/env bash

#for arraySize in 1
# sometime the request array size is set, sometimes not
#for arraySize in 2 10 20 50 100 150 200 300 400 600 800 1000
for arraySize in 1 2 5 10 20 50 100 150 200 250 300 350 400 450 500
do
	formattedArraySize=$(printf '%04d' $arraySize)
	echo  "array size: $formattedArraySize"
	(( requestArraySize = arraySize / 2 ))
	./target.pl  --database ora192rac02/pdb1.jks.com -username jkstill --password grok --interval-seconds 1 --iterations 5 --row-cache-size $arraySize --trace-level 12 --tracefile-identifier RC-$formattedArraySize
done

