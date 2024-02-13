#!/usr/bin/env perl

use strict;
use warnings;

my $debug=0;
my $arraySize=100;
my $thinkTime = 1e6; #  microseconds

die "array-size must be > 0" unless $arraySize;

#my %h=(a=>1, b=>2, c=>3);
#print "doing some work with \%h\n";

#print "access check: $accessCheck\n";

# check that files can be read


my %execLookup=();
my %cursorMetrics=();
my %snmfcMetrics=(
	COUNT => 1,
	TIME => 1
); # cumulative metrics for calculating averages at runtime

# track cursor# and line#
# this can be problematic, as cursor# can be reused
# for this exercise, it may not be too important
my $cursors=();
my $execID=0;

while (<STDIN>) {
	my $line=$_;
	# skip lines that are not EXEC, FETCH or SNMFC	
	next unless $line =~ /(^WAIT #[[:digit:]]+: nam='SQL\*Net message from client'|^EXEC|^FETCH)/;
	chomp $line;
	print "$line\n" if $debug;
	#
		
	my ($rowCount,$elapsed) = (0,0);

	my $cursorID = getCursorID($line);
	$execID = '0:' . $cursorID unless $cursorID;

	print "cursorID: $cursorID\n" if $debug;

	if ( $line =~ /^WAIT/ ) {
		$elapsed = getElapsed($line);
		next if $elapsed >= $thinkTime;
		$cursorMetrics{$execID}->{SNMFC_TIME} += $elapsed;
		$cursorMetrics{$execID}->{SNMFC_COUNT}++;
		$snmfcMetrics{TIME} += $elapsed;
		$snmfcMetrics{COUNT}++;
		print "WAIT elapsed: $elapsed\n" if $debug;
	} elsif ( $line =~ /^FETCH/ ) {
		$rowCount = getRowCount($line);
		$cursorMetrics{$execID}->{FETCH_COUNT}++;
		$cursorMetrics{$execID}->{FETCH_ROWS} += $rowCount;
		print "FETCH Rows: $rowCount\n" if $debug;
	} elsif ( $line =~ /^EXEC/ ) {
		$rowCount = getRowCount($line);
		$execID = $. . ':' . $cursorID;
		$execLookup{$cursorID} = $.;
		# times calculated later per averages
		$cursorMetrics{$execID}->{EXEC_ROWS} += $rowCount;
		print "EXEC Rows: $rowCount   execID $execID\n" if $debug;

	}

}

my $snmfcAvgTime = $snmfcMetrics{TIME} / $snmfcMetrics{COUNT};

print qq{

  TIME: $snmfcMetrics{TIME}
 COUNT: $snmfcMetrics{COUNT}
   AVG: $snmfcAvgTime

} ; #if $debug ;
	
my ($realSNMFC,$optimizedSNMFC,$checkSNMFC) = (0,0);

foreach my $execID (keys %cursorMetrics) {
	if (
		exists $cursorMetrics{$execID}->{SNMFC_TIME}
			and exists $cursorMetrics{$execID}->{SNMFC_COUNT}
	) {
		$realSNMFC +=  $cursorMetrics{$execID}->{SNMFC_TIME};
		$checkSNMFC += $cursorMetrics{$execID}->{SNMFC_COUNT} * $snmfcAvgTime;
		#$optimizedSNMFC += (int($arraySize % $cursorMetrics{$execID}->{SNMFC_COUNT} ) + 1) * $snmfcAvgTime;

		$optimizedSNMFC += (
			int($cursorMetrics{$execID}->{SNMFC_COUNT} / $arraySize ) 
			+ ($cursorMetrics{$execID}->{SNMFC_COUNT} % $arraySize ) 
		) * $snmfcAvgTime;
		
		if ($debug > 1) {
			my $mod = int($cursorMetrics{$execID}->{SNMFC_COUNT} / $arraySize ) + ($cursorMetrics{$execID}->{SNMFC_COUNT} % $arraySize );
			print qq{

  SNFMC AVG: $snmfcAvgTime
      COUNT: $cursorMetrics{$execID}->{SNMFC_COUNT}
  arraySize: $arraySize
        mod: $mod

};
		}

	}
}

# convert to seconds
my $realSNMFCFormatted = sprintf('%06.6f',$realSNMFC / 1e6);
my $checkSNMFCFormatted = sprintf('%06.6f',$checkSNMFC / 1e6);
my $optimizedSNMFCFormatted = sprintf('%06.6f',$optimizedSNMFC / 1e6);
my $optimizedSNMFCSavingsFormatted = sprintf('%06.6f',($realSNMFC - $optimizedSNMFC) / 1e6);

print qq{

       real SNMFC: $realSNMFCFormatted
      check SNMFC: $checkSNMFCFormatted
  optimized SNMFC: $optimizedSNMFCFormatted
       time saved: $optimizedSNMFCSavingsFormatted


};




# example rows
#EXEC #139903861875728:c=55,e=55,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=1636480816,tim=3023862738398
#FETCH #139903861875728:c=45,e=46,p=0,cr=0,cu=0,mis=0,r=1,dep=0,og=1,plh=1636480816,tim=3023862738468
#WAIT #139903861875728: nam='SQL*Net message from client' ela= 5478 driver id=1952673792 #bytes=1 p3=0 obj#=9010 tim=3023862744036
#

# we only care about elapse time for WAITs on SNMFC 
# EXEC may return 1+ rows
# it can take a relatively long time for EXEC to complete
# the SNMFC must be calculated or estimated, as that time is included in the EXEC
# estimating, as per the following table
#
# time per row in usecs
# established by testing
# used for EXEC fetch times

sub getElapsed {
	my ($line) = @_;

	# microseconds
	# might be milliseconds or centiseconds in versions before 11g
	# do not care at this time
	my $elapsed;

	if ( $line =~ /^WAIT/ ) {
 		$line =~ m/^WAIT\s+#.*\sela= ([[:digit:]]+)/; 
		$elapsed = $1;
	} else {
		die "getElapsed: invalid input of $line\n";
	}
	return $elapsed;
}


sub getRowCount {
	my ($line) = @_;

	# isolate ,r=N
	#print "getRowCount line: $line\n";
	my $rowCount = -1;

	if ( $line =~ /^?(EXEC|FETCH)/ ) {
		$line =~ m/(,r=[[:digit:]]+)/; 
		$line=$1;
		$line =~ /([[:digit:]]+)/; 
		$rowCount=$1;
	} elsif ( $line =~ /^WAIT/ ) {
	}

	return $rowCount;

}

sub getCursorID {
	my ($line) = @_;

	die "getCursorID - invalid row - line: $line\n" unless $line =~ /^(EXEC|FETCH|WAIT)/;

 	$line =~ m/^?(EXEC|FETCH|WAIT)\s+#([[:digit:]]+)/; 
 	return $2;
}



