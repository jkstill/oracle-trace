#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;
use IO::File;

# get stats for EXECT/WAIT/FETCH between bind sets
# currently interesting in SNMFC waits
# this script attempts to create an estimate of the time that may
# be saved by increasing the row cache size, that is, the number
# of rows that oracle returns per network packet

my $firstTime=1;

my $waits=0;
my $waitTime=0;
my $fetchCount=0;
my $fetchTime=0;
my $execCount=0;
my $execTime=0;
my $rowsFetched=0;
my $ticksPerSecond=1e6;
# arbitrary choice of 500 fro max rows packet
my $maxRowsPerPacket=500;
my $fileSetSavings=0;

# verbose off by default
# enable
# VERBOSE=1 program_name.pl ...
my $verbose = exists($ENV{VERBOSE}) ? $ENV{VERBOSE} : 0;

# defaults to banner on 
# to disable:
# BANNER=0 program_name.pl ...
my $banner = exists($ENV{BANNER}) ? $ENV{BANNER} : 1;

# file names on STDIN

my @files = @ARGV;

foreach  my $traceFile ( @files ) {

	#print "file: $traceFile\n";

	unless (-r $traceFile) {
		 warnBanner("cannot read $traceFile","$!");
		 next;
	}

	my $tfh = IO::File->new;

	unless ($tfh->open($traceFile,'<') ) { 
		warnBanner("cannot open $traceFile","$!");
		next;
	}

	banner("$traceFile");

	my $totalSavings=0;
	my $totalReducedWaitTime=0;
	my $totalReducedFetchTime=0;

	while (<$tfh>) {
		my $line=$_; chomp $line;
	
		if ($line =~ /(^EXEC|^BINDS)/ ) {

			if ($waits == 0 and $fetchCount == 0 and $execCount == 0 ) {
				next;
			}
		
			if ($firstTime) {
				$firstTime=0;
				next;
			}

			# some analysis
			my $responseTime = $waitTime + $execTime + $fetchTime;

			my $reducedFetches =  ( $rowsFetched / $maxRowsPerPacket );
			if ($reducedFetches < 1 ) {
				$reducedFetches = 1;
			}	

			if ( $reducedFetches - int($reducedFetches)) {
					$reducedFetches = int($reducedFetches +1);
			}

			my $reducedFetchTime = calcTime($reducedFetches, $fetchTime, $fetchCount, $line);

			my $reducedWaits = ( $rowsFetched / $maxRowsPerPacket );
			if ($reducedWaits < 1 ) {
				$reducedWaits = 1;
			}	

			if ( $reducedWaits - int($reducedWaits)) {
					$reducedWaits = int($reducedWaits +1);
			}

			my $reducedWaitTime = calcTime($reducedWaits,$waitTime, $waits, $line );

			my $reducedResponseTime = $reducedWaitTime + $reducedFetchTime ; #+ $execTime;

			my $waitTimeRpt = sprintf('%6.6f', $waitTime / $ticksPerSecond);
			my $fetchTimeRpt = sprintf('%6.6f', $fetchTime / $ticksPerSecond);
			my $execTimeRpt = sprintf('%6.6f', $execTime / $ticksPerSecond);
			my $responseTimeRpt = sprintf('%6.6f', $responseTime / $ticksPerSecond);
			my $reducedWaitTimeRpt = sprintf('%6.6f',$reducedWaitTime / $ticksPerSecond);
			my $reducedFetchTimeRpt = sprintf('%6.6f',$reducedFetchTime / $ticksPerSecond);
			my $reducedResponseTimeRpt = sprintf('%6.6f', $reducedResponseTime / $ticksPerSecond);

			my $reducedTimeRpt = sprintf('%6.6f', $reducedResponseTime / $ticksPerSecond);
			$totalSavings += $reducedResponseTime;

			$totalReducedWaitTime += $reducedWaitTime;
			$totalReducedFetchTime += $reducedFetchTime;

			print qq{

               waits: $waits
            waitTime: $waitTimeRpt
          fetchCount: $fetchCount
           fetchTime: $fetchTimeRpt
           execCount: $execCount
            execTime: $execTimeRpt
         rowsFetched: $rowsFetched
        responseTime: $responseTimeRpt

     reducedWaitTime: $reducedWaitTimeRpt
    reducedFetchTime: $reducedFetchTimeRpt
 reducedResponseTime: $reducedResponseTimeRpt

             Savings: $reducedTimeRpt

			} if $verbose;
		
			$waits=0;
			$waitTime=0;
			$fetchCount=0;
			$fetchTime=0;
			$execCount=0;
			$execTime=0;
			$rowsFetched=0;

			next;
		}

=head1 trace format

EXEC #140485504970824:c=99,e=938,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=905514141,tim=3413606531459
WAIT #140485504970824: nam='SQL*Net message to client' ela= 1 driver id=1413697536 #bytes=1 p3=0 obj#=69017 tim=3413606531483
FETCH #140485504970824:c=24,e=24,p=0,cr=2,cu=0,mis=0,r=1,dep=0,og=1,plh=905514141,tim=3413606531502
WAIT #140485504970824: nam='SQL*Net message from client' ela= 109 driver id=1413697536 #bytes=1 p3=0 obj#=69017 tim=3413606531634

=cut 

		if ($line =~ /^WAIT/ ) {
			my @lineBits = split(/\s+/,$line);

			# only care about sqlnet messages at this time
			if (! $line =~ /^SQL*Net message/) {
				next;
			}

			my $timTxt = pop @lineBits;
			my ($dummy, $tim) = split(/=/,$timTxt);
			#print "w tim: $tim\n";
			$line =~ /(ela=\s+[[:digit:]]+)/;
			#print "\nWAIT Elapsed: $1\n";
			my $etim = split(/\s+/,$1);
			$waitTime += $etim;
			$waits++;

		} elsif ( $line =~ /^FETCH/ ) {

			my @lineBits = split(/,/,$line);
			my $timTxt = pop @lineBits;
			my ($dummy, $tim) = split(/=/,$timTxt);
			my $etimTxt = $lineBits[1];
			my $etim;
			($dummy, $etim) = split(/=/,$etimTxt);
			my $rows=0;
			my $rowTxt = $lineBits[6];
			($dummy, $rows) = split(/=/, $rowTxt);
			$rowsFetched += $rows;
			$fetchTime += $etim;
			#print "f tim: $tim\n";
			$fetchCount++;

		} elsif ( $line =~ /^EXEC/ ) {

			# EXEC may have a rowcount. when there is, there does not seem to be a FETCH
			# possibly for known single row, such as count(*)?

			my @lineBits = split(/,/,$line);
			my $timTxt = pop @lineBits;
			my $etimTxt = $lineBits[1];
			my ($dummy, $etim) = split(/=/,$etimTxt);
			$execTime += $etim;
			my ($rows,$tim);
			($dummy, $tim) = split(/=/,$timTxt);

			my $rowTxt = $lineBits[6];
			($dummy, $rows) = split(/=/, $rowTxt);
			$rowsFetched += $rows;

			#print "e tim: $tim\n";
			$execCount++;

		}

	}

	print "\n  Reduced Wait Time: " . sprintf($totalReducedWaitTime / $ticksPerSecond) . "\n";
	print " Reduced Fetch Time: " . sprintf($totalReducedFetchTime / $ticksPerSecond) . "\n";
	print " Total Reduced Time: " . sprintf('%6.6f', $totalSavings / $ticksPerSecond) . "\n";

	$fileSetSavings += $totalSavings;

}

print "\n   File Set Savings: " . sprintf('%6.6f', $fileSetSavings / $ticksPerSecond) . "\n\n";

# end of main
#
sub calcTime {
	my ($reduced,$time,$count,$line) = @_;
	my $reducedResult=0;

	my ($error1, $error2);
	{
    	local $@;
		# if both fetchtime is 0, then fetchcount is most likely 0
		# so far in testing anyway - avoid divide by zero 
		unless (eval { $reducedResult = int($reduced * ( $time / ( ($time > 0) ? $count : 1) )); return 1; }) {
        	$error1 = 1;
        	$error2 = $@;
    	}
	}

	if ($error1) {
		warn "error: $error2\n";
		warn " line: $line\n";
		warn "count: $count\n";
		warn " time: $time\n";
	}

	return $reducedResult;

}

sub banner {
	return unless $banner;
	print "\n";
	print '#' x 80 . "\n";
	print "## " . join ("\n## ", @_) . "\n";
	print '#' x 80 . "\n";
	print "\n";
}

sub warnBanner {
	print "\n";
	print '!' x 80 . "\n";
	print '!! ' . join ("\n!! ", @_) . "\n";
	print '!' x 80 . "\n";
	print "\n";
}


