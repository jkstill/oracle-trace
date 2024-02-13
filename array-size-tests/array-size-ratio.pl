#!/usr/bin/env perl
#
use warnings;
use strict;

# per row times for array sizes 1-500
# test from client/db in same local network

# time per row in usecs
my %snmfcTimes = (
1 => 300,,
2 => 243,
5 => 131,
10 => 77,
20 => 57,
50 => 40,
100 => 28,
150 => 30,
200 => 25,
250 => 24,
300 => 23,
350 => 27,
400 => 24,
450 => 23,
500 => 27,
);

my %arraySizesToCompare = (
	1 => 10,
	2 => 100,
	10 => 100,
	2 => 500,
	20 => 500,
	100 => 100,
	400 => 400,
	500 => 500,
);


foreach my $key (sort { $a <=> $b } keys %arraySizesToCompare) {
	my $currTimePerRow = getTimePerRow($key);
	my $newTimePerRow = getTimePerRow($arraySizesToCompare{$key});

	#my $ratio = $newTimePerRow / $currTimePerRow;
	my $ratio = getRatio($key,$arraySizesToCompare{$key});

	print qq {

 cur array size: $key
 new array size: $arraySizesToCompare{$key}
currTimePerRows: $currTimePerRow
 newTimePerRows: $newTimePerRow
          ratio: $ratio

};


}



# the unit size is not important
# this is just used to approximate the speed advantage for array sizes
# slow / fast = speed factor

sub getTimePerRow {
	my ($arraySize) = @_;

	my $prevTime=$snmfcTimes{1};
	foreach my $stdSize ( sort { $a <=> $b } keys %snmfcTimes ) {
		#print "stdSize: $stdSize  per row: $snmfcTimes{$stdSize}\n";
		if ( $stdSize > $arraySize ) {
			return $prevTime;
		}
		$prevTime=$snmfcTimes{$stdSize};
	}
	
	return $snmfcTimes{500};
}

sub getRatio {
	my ($smallerArraySize, $largerArraySize) = @_;
	return getTimePerRow($largerArraySize) / getTimePerRow($smallerArraySize);
}


