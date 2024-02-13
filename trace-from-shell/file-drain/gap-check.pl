#!/usr/bin/env perl

use warnings;
use strict;

my $chkSeq=0;
my $missingLines=0;
my $lineCount=0;

while(<STDIN>){
	$lineCount++;
	s/\0//g;
	my ($lineSeq) = split(/:/);
	#print "chkSeq: $chkSeq  lineSeq: $lineSeq\n";

	if ($chkSeq != $lineSeq ) {
		print "chkSeq: $chkSeq  lineSeq: $lineSeq\n";
		print "GAP of " . ($lineSeq - $chkSeq) . "\n";
		$missingLines += ($lineSeq - $chkSeq);
		$chkSeq = $lineSeq + 1;
		next;
	} else {
		$chkSeq++;
	}

}

print "   Line Count: $lineCount\n";
print "Missing Lines:  $missingLines\n";
print "% lost: " . ($missingLines / $lineCount) * 100 . "\n";

