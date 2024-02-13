#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;

my $VERBOSITY=0;

my $arraySize=100;
my $skipInaccessible=0;
my $help=0;
# tcpTime does not seem to have much effect - debugging required
my $tcpTime = 50;  # milliseconds to sent packet
my $thinkTime = 1;

GetOptions (
	"array-size=i" => \$arraySize,
	"skip-inaccessible!" => \$skipInaccessible,
	"verbosity=i" => \$VERBOSITY,
	"think-time=f" => \$thinkTime,
	"tcp-time=f" => \$tcpTime,
	"h|help!" => \$help,
) or die usage(1);

$thinkTime *= 1e6; # convert to microseconds

usage() if $help;

die "array-size must be > 0" unless $arraySize;

my $verbose = Verbose->new(
	{
		VERBOSITY=>$VERBOSITY, 
		LABELS=>1, 
		TIMESTAMP=>1, 
		HANDLE=>*STDERR
	} 
);

#my %h=(a=>1, b=>2, c=>3);
#print "doing some work with \%h\n";
#$verbose->print(2,'reference to %h', \%h);

my @files=@ARGV;

$verbose->print(2, 'Before: ' , \@files);

my $accessCheck = checkFileAccess($skipInaccessible,\@files);

#print "access check: $accessCheck\n";

$verbose->print(2, 'After ' , \@files);
# check that files can be read

if (! $accessCheck && ! $skipInaccessible) {
	die "could not access all files\n";
}

die "the input list is empty - perhaps all files are inaccessible?\n" unless @files;

# process files

foreach my $file (@files) {
	#$verbose->print(1,"working on file: $file", []);
	print "\nfile: $file\n";

	open FH, $file || die "could not open $file - $!\n";

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

	while (<FH>) {
		my $line=$_;
		# skip lines that are not EXEC, FETCH or SNMFC	
		next unless $line =~ /(^WAIT #[[:digit:]]+: nam='SQL\*Net message from client'|^EXEC|^FETCH)/;
		chomp $line;
		print "$line\n" if $VERBOSITY > 1;
		#
		
		my ($rowCount,$elapsed) = (0,0);

		my $cursorID = getCursorID($line);
		$execID = '0:' . $cursorID unless $cursorID;

		print "cursorID: $cursorID\n" if $VERBOSITY;

		if ( $line =~ /^WAIT/ ) {
			$elapsed = getElapsed($line);
			next if $elapsed >= $thinkTime;
			$cursorMetrics{$execID}->{SNMFC_TIME} += $elapsed;
			$cursorMetrics{$execID}->{SNMFC_COUNT}++;
			$snmfcMetrics{TIME} += $elapsed;
			$snmfcMetrics{COUNT}++;
			print "WAIT elapsed: $elapsed\n" if $VERBOSITY;
		} elsif ( $line =~ /^FETCH/ ) {
			$rowCount = getRowCount($line);
			$cursorMetrics{$execID}->{FETCH_COUNT}++;
			$cursorMetrics{$execID}->{FETCH_ROWS} += $rowCount;
			print "FETCH Rows: $rowCount\n" if $VERBOSITY;
		} elsif ( $line =~ /^EXEC/ ) {
			$rowCount = getRowCount($line);
			$execID = $. . ':' . $cursorID;
			$execLookup{$cursorID} = $.;
			# times calculated later per averages
			$cursorMetrics{$execID}->{EXEC_ROWS} += $rowCount;
			print "EXEC Rows: $rowCount   execID $execID\n" if $VERBOSITY;

		}

	}


	my $snmfcAvgTime = $snmfcMetrics{TIME} / $snmfcMetrics{COUNT};

	print qq{

  TIME: $snmfcMetrics{TIME}
 COUNT: $snmfcMetrics{COUNT}
   AVG: $snmfcAvgTime

} if $VERBOSITY ;
	
	# estimate snmfc time for EXEC that returns rows 
#Estimating time for EXEC calls returning rows

# no longer using this
# EXEC that returns rows appears to be 2 things mostly
# DML that reports how many rows were affected, so this does not even work 'correctly' - there are no rows to count
# SELECT COUNT(*), which is always 1 row
# Most of the time is in CPU, not network

	#foreach my $execID ( keys %cursorMetrics ) {
		#next unless exists $cursorMetrics{$execID}->{EXEC_ROWS};

		##print "getting cursorMetrics EXEC_ROWS counts\n";
		##my $rowCount = $cursorMetrics{$execID}->{EXEC_ROWS};
		#my $rowCount = 1;
		##print "exec Rowcount: $rowCount\n";
		## use the table in estimateSnmfcTime or use averages

		## calculate avg rows if possible
		#my $snmfcRowsPerFetch=1;
		#if (
			#exists $cursorMetrics{$execID}->{FETCH_COUNT} 
			#and exists $cursorMetrics{$execID}->{FETCH_ROWS} 
		#) {
			#$snmfcRowsPerFetch = $cursorMetrics{$execID}->{FETCH_COUNT} /  ($cursorMetrics{$execID}->{FETCH_ROWS}+1);
		#} 
		#my $snmfcTime = ($rowCount * $snmfcAvgTime) + ($snmfcRowsPerFetch * $tcpTime) ;
		#$cursorMetrics{$execID}->{EXEC_TIME} = $snmfcTime;

	#}
#

	print '%cursorMetrics: ' . Dumper(\%cursorMetrics) if $VERBOSITY;

	# now total up real and optimized SNMFC

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
		
			if ($VERBOSITY > 1) {
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


}

exit;

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

sub estimateSnmfcTime {
	my ($rowCount) = @_;

	my %snmfcTimes = (
		1 => 300,
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

	my $prevRC=1;
	foreach my $arraySize ( sort { $a <=> $b } keys %snmfcTimes ) {
		last if $arraySize >= $rowCount;
		my $prevRC=$arraySize;
	}

	return $snmfcTimes{$prevRC} * $rowCount;

}


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


sub checkFileAccess {
	my ($skipInaccessible, $filesRef) = @_;

	my @filesToRemove=();

	my $verbose = Verbose->new(
		{
			VERBOSITY=>$VERBOSITY, 
			LABELS=>1, 
			TIMESTAMP=>1, 
			HANDLE=>*STDERR
		} 
	);

	my $rc=1;

	#foreach my $file (@{$filesRef}) {
	foreach my $el (0 .. $#{$filesRef}) {
		my $file = ${filesRef}->[$el];
		$verbose->print(2, "el $el  file:", [$file]);

		-r $file || $verbose->print(2, "marking for removal\n",[$file]);
		-r $file || push @filesToRemove, $file;
	}

	$rc = 0 if @filesToRemove;

	# remove duplicates
	# get unique list of filenames
	my %files = map { $_ => 'noop' } @{$filesRef};
	$verbose->print(2, '%files: ' , \%files);
	foreach my $file ( keys %files ) {
		my @elementList = reverse ( grep { ${filesRef}->[$_] eq $file } 0..$#{$filesRef});
		$verbose->print(2, '@elementList before: ' , \@elementList);
		pop @elementList;
		$verbose->print(2, '@elementList after ' , \@elementList);
		
		foreach my $elDedup (@elementList) {
			splice(@{$filesRef},$elDedup,1);
		}
	}

	if ($skipInaccessible) {
		foreach my $file ( @filesToRemove ) {
			# create the list in reverse
			# as elements are remove, the list changes
			# removing from last to first avoids the need to calculate changing indices
			foreach my $elToRemove (reverse ( grep { ${filesRef}->[$_] eq $file } 0..$#{$filesRef})) {
				warn "removing inaccessible file from input: $filesRef->[$elToRemove]\n";
				splice(@{$filesRef},$elToRemove,1);
			}
			#print '@delIndexes: ' . Dumper(\@delIndexes);
			#splice(@{$filesRef},$el,1);
		}
	}

	return $rc;
}

sub usage {

	my $exitVal = shift;
	use File::Basename;
	my $basename = basename($0);
	print qq{
$basename

usage: $basename [--array-size N ] (list of files) 

   $basename -option1 parameter1 -option2 parameter2 ...

SNMFC == SQLNet message from client

--array-size          Size of the array to use for optimization
                      If FETCH is getting 1 or 2 rows, calculate the likely snmfc for arraysize N, where N defaults to 100

--skip-inaccessible   Continue if there are files that are inaccessible.
                      The default is to exit if there are files that cannot be read.
                      Exits with error if no files are accessible

--think-time          Amount of time in seconds, to allow for think time - default is 1 second
                      SNMFC >= think time are ignored

--tcp-time            Currently this has no effect - do not use.
                      Amount of time in milliseconds to allow for a SQLNet packet to reach the client and be acked
                      Default is 50 ms.  For a client that is 100 miles away, this might be 250 ms. Use a LAN distance calculator.

--verbosity           Set to 1 or 2.  If set, a lot of output will apepar. Useful for debugging.

examples here:

   $basename --array-size 50 --skip-inaccessible orcl_ora_001520.trc orcl_ora_043220.trc ...
};

	exit eval { defined($exitVal) ? $exitVal : 0 };
}


#######################
## End of Main
#######################


# see https://github.com/jkstill/Verbose

package Verbose;

use strict;
use warnings;

require Exporter;
our @ISA= qw(Exporter);
#our @EXPORT_OK = ( 'showself','print');
our $VERSION = '0.02';

use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);

sub new {

	use Data::Dumper;
	use Carp;

	my $pkg = shift;
	my $class = ref($pkg) || $pkg;
	my ($args) = @_;
		
	# handle could be stdout,stderr, filehandle, etc
	my $self = { 
		VERBOSITY=>$args->{VERBOSITY}, 
		LABELS=>$args->{LABELS}, 
		HANDLE=>$args->{HANDLE},
		TIMESTAMP=>$args->{TIMESTAMP},
		CLASS=>$class 
	};

	$self->{HANDLE}=*STDOUT unless defined $self->{HANDLE};

	{ 
		no warnings;
		if ( (not defined $self->{VERBOSITY}) || (not defined $self->{LABELS}) ) { 
			warn "invalid call to $self->{CLASS}\n";
			warn "call with \nmy \$a = $self->{CLASS}->new(\n";
			warn "   {\n";
			warn "      VERBOSITY=> (level - 0 or 1-N),\n";
			warn "      LABELS=> (0 or 1)\n"; 
			warn "   }\n";
			croak;
		}
	}
	my $retval = bless $self, $class;
	return $retval;
}

sub showself {
	use Data::Dumper;
	my $self = shift;
	print Dumper($self);
}

sub getlvl {
	my $self = shift;
	$self->{VERBOSITY};
}


sub print {
	use Carp;
	my $self = shift;
	my ($verboseLvl,$label, $data) = @_;

	return unless ($verboseLvl <= $self->{VERBOSITY} );

	# handle could be stdout,stderr, filehandle, etc
	my $handle = $self->{HANDLE};

	my $padding='  ' x $verboseLvl;

	my $isRef = ref($data) ? 1 : 0;

	unless ($isRef) {carp "Must pass a reference to $self->{class}->print\n" }

	my $refType = ref($data);

	my $wallClockTime='';
	my ($dummy,$microSeconds)=(0,0);
	if ( $self->{TIMESTAMP} ) {
		($dummy,$microSeconds)=gettimeofday();
		$wallClockTime = strftime("%Y-%m-%d %H:%M:%S",localtime) . '.' . sprintf("%06d",$microSeconds);
	}

	print $handle "$wallClockTime$padding======= $label - level $verboseLvl =========\n" if $self->{LABELS} ;
	
	my $isThereData=0;

	if ('ARRAY' eq $refType) {
		if (@{$data}) {
			print $handle $padding, join("\n" . $padding, @{$data}), "\n";
			$isThereData=1;
		}
	} elsif ('HASH' eq $refType) {
		#print "HASH: ", Dumper(\$data);
		if (%{$data}) {
			foreach my $key ( sort keys %{$data} ) {
				print $handle "${padding}$key: $data->{$key}\n";
			}
			$isThereData=1;
		}
	} else { croak "Must pass reference to a simple HASH or ARRAY to  $self->{CLASS}->print\n" }

	# no point in printing a separator if an empty hash or array was passed
	# this is how to do label only
	print $handle "$padding============================================\n" if $self->{LABELS} and $isThereData;

}

1;

__END__

=head1 Predict Time Saved by Increasing Array Size
	
 SNMFC == SQLNet message from client

 High on the list of things that cause client-server type applications to be slow, is SNMCF.

 It is not at all unusual to see busy applications retrieving data from the database one or two rows at a time.

 The data from a SQL Trace will look like this:

 PARSING IN CURSOR #139768321223280 len=34 dep=0 uid=108 oct=3 lid=108 tim=2942206501276 hv=1488300750 ad='d53dc038' sqlid='4y53369cbbaqf'
 select id, data from rowcache_test
 END OF STMT
 PARSE #139768321223280:c=0,e=20,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=3844077149,tim=2942206501276
 WAIT #139768321223280: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206501300
 WAIT #139768321223280: nam='SQL*Net message from client' ela= 441 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206501751
...
 FETCH #139768321223280:c=6,e=6,p=0,cr=1,cu=0,mis=0,r=1,dep=0,og=1,plh=3844077149,tim=2942206502481
 WAIT #139768321223280: nam='SQL*Net message from client' ela= 74 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206502565
 WAIT #139768321223280: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206502581
 FETCH #139768321223280:c=8,e=8,p=0,cr=1,cu=0,mis=0,r=1,dep=0,og=1,plh=3844077149,tim=2942206502586
 WAIT #139768321223280: nam='SQL*Net message from client' ela= 70 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206502664
 WAIT #139768321223280: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206502673
 FETCH #139768321223280:c=6,e=6,p=0,cr=1,cu=0,mis=0,r=1,dep=0,og=1,plh=3844077149,tim=2942206502677
 WAIT #139768321223280: nam='SQL*Net message from client' ela= 71 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206502754
 WAIT #139768321223280: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=9009 tim=2942206502762

 Every row is FETCHed one at a time, which is very inefficient.

 You can see this by the 'r=1' in each FETCH call.

 Fetching 10 rows will require 10 separate network round trips.

 Here is an example of the same SQL, but fetching 100 rows at a time:

 PARSING IN CURSOR #140640346983024 len=34 dep=0 uid=108 oct=3 lid=108 tim=2942224739610 hv=1488300750 ad='d53dc038' sqlid='4y53369cbbaqf'
 select id, data from rowcache_test
 END OF STMT
 PARSE #140640346983024:c=0,e=20,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=3844077149,tim=2942224739610
 WAIT #140640346983024: nam='SQL*Net message to client' ela= 0 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224739634
 WAIT #140640346983024: nam='SQL*Net message from client' ela= 188 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224739832
 EXEC #140640346983024:c=10,e=9,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=3844077149,tim=2942224739857
 WAIT #140640346983024: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224739930
 FETCH #140640346983024:c=71,e=71,p=0,cr=3,cu=0,mis=0,r=2,dep=0,og=1,plh=3844077149,tim=2942224739938
 WAIT #140640346983024: nam='SQL*Net message from client' ela= 153 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224740101
 WAIT #140640346983024: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224740128
 WAIT #140640346983024: nam='SQL*Net more data to client' ela= 25 driver id=1952673792 #bytes=8129 p3=0 obj#=-1 tim=2942224740168
 FETCH #140640346983024:c=76,e=76,p=0,cr=2,cu=0,mis=0,r=100,dep=0,og=1,plh=3844077149,tim=2942224740198
 WAIT #140640346983024: nam='SQL*Net message from client' ela= 394 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224740604
 WAIT #140640346983024: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224740623
 WAIT #140640346983024: nam='SQL*Net more data to client' ela= 14 driver id=1952673792 #bytes=8129 p3=0 obj#=-1 tim=2942224740655
 FETCH #140640346983024:c=64,e=64,p=0,cr=2,cu=0,mis=0,r=100,dep=0,og=1,plh=3844077149,tim=2942224740683
 WAIT #140640346983024: nam='SQL*Net message from client' ela= 230 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224740924
 WAIT #140640346983024: nam='SQL*Net message to client' ela= 1 driver id=1952673792 #bytes=1 p3=0 obj#=-1 tim=2942224740944
 WAIT #140640346983024: nam='SQL*Net more data to client' ela= 14 driver id=1952673792 #bytes=8129 p3=0 obj#=-1 tim=2942224740974
 ...

 The amount of time saved by fetching more rows is quite significant.

 Here are the SNMFC times for each of these tests, both running the same SQL.

 The first is fetching 1 row per network round trip, and the second is fetching 100 rows per network round trip.

   array size 1:  9.15 seconds
 array size 100:  0.24 seconds

 These tests were run from a VM that is running on the same machine as the database, so network latencies are quite low.

 The next example is with a 6ms network lag, which emulates the client being about 100 miles from the database server.

   array size 1:  1130.39 seconds
 array size 100:    11.11 seconds


 Determine the average array size.

 It is not too difficult to determine the average array size of an app.

 Enable SQL Trace on one or more session, let them run a few minutes, or until there are several megabytes of data.

 It is not necessary to include bind values in trace. 

 It is actually better to not include bind values unless they are needed.

   - bind values can be a security issue
   - bind values can greatly inflate the size of a trace file.

 Now that you have some trace files, get some stats

 The following trace file is fetching 100 rows on nearly all FETCH calls

 $  grep -E '^FETCH' trace/latency-0.2ms/cdb1_ora_15125_PF-100.trc | grep -oE ',r=[[:digit:]]+' | sed -e 's/,r=//' | sort | uniq -c | sort -n
      1 0
      3 1
     10 2
     10 98
    990 100

 While this trace file shows nearly all data being fetched 1 row at a time:

 $  grep -E '^FETCH' trace/latency-0.2ms/cdb1_ora_14973_PF-001.trc | grep -oE ',r=[[:digit:]]+' | sed -e 's/,r=//' | sort | uniq -c | sort -n
     11 0
 100003 1


 This next trace file shows a widely varying number of rows per FETCH call, but most of them are 1 row at a time:

 $  grep -E '^FETCH' CSRIPRD_ora_82935-combined.trc  | grep -oE ',r=[[:digit:]]+' | sed -e 's/,r=//' | sort | uniq -c | sort -n
      1 12
      1 13
      1 19
      1 3
      1 8
      2 15
      2 5
      2 9
      3 10
      3 6
      3 7
      5 16
      7 14
     40 50
     85 2
    130 20
    166 100
  20119 0
  81690 1

 Those that are 0 rows count as well, as the sql is just not returning anything, but the network round trip must still be made for acknowledgement.

 The goal with this script is to make a prediction of how much time will be consumed by SNMFC if the array size is increased to something larger than what is currently being seen.

 Two of the trace files shown are benchmark files. They were created with SQL that returned a constant row size of 100 bytes, and the array size was carefully controlled.

 So now I will run the estimation script against the trace file where array size == 1:

 The test array size defaults to 100, but the --array-size parameter is set here for clarity.

  $  ./calc-snmfc-savings.pl --array-size 100 trace/latency-0.2ms/cdb1_ora_14973_PF-001.trc

  file: trace/latency-0.2ms/cdb1_ora_14973_PF-001.trc


       real SNMFC: 9.154835
      check SNMFC: 9.154744
  optimized SNMFC: 0.093994
       time saved: 9.060841

 The prediction is that by using an array size of 100, the application run time would be reduced by 9.06 seconds

 How close is this to reality?

 When run with an array size of 100, the total SNMFC time was 0.24 seconds.

 This is nearly 3x what was predicted, which was 0.09 seconds.

 It is quite difficult to get a prediction that matches the reality.

 What is important:  this script shows there will be a significant time savings if the array size is increased from 1 to 100.

 Let's consider the other trace file, CSRIPRD_ora_82935-combined.trc, which is real production trace data.

 As seen previous, nearly all FETCH calls returned 0 or 1 row. 

 The same estimate is asked for: how much time might be saved if the array size is set to 100:

 $  ./calc-snmfc-savings.pl CSRIPRD_ora_82935-combined.trc

  file: CSRIPRD_ora_82935-combined.trc

       real SNMFC: 2.552158
      check SNMFC: 2.518130
  optimized SNMFC: 2.518130
       time saved: 0.034028


 Even though there are 100k+ FETCH calls for 1 row each, the estimate of time saved is quite small.

 Here is the execution of a SQL statement that is a typical of this trace file:

 PARSING IN CURSOR #47214410064360 len=109 dep=0 uid=45 oct=3 lid=45 tim=3592707058282 hv=341130062 ad='12cd4b6b0' sqlid='ajp186ha5afuf'
 SELECT  ...
 END OF STMT
 PARSE #47214410064360:c=103,e=102,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=2725478998,tim=3592707058280
 EXEC #47214410064360:c=32,e=33,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,plh=2725478998,tim=3592707058459
 WAIT #47214410064360: nam='SQL*Net message to client' ela= 1 driver id=1413697536 #bytes=1 p3=0 obj#=36496 tim=3592707058506
 FETCH #47214410064360:c=18,e=19,p=0,cr=3,cu=0,mis=0,r=0,dep=0,og=1,plh=2725478998,tim=3592707058565
 STAT #47214410064360 id=1 cnt=0 pid=0 pos=1 obj=0 op='NESTED LOOPS  (cr=3 pr=0 pw=0 str=1 time=19 us cost=2 size=25 card=1)'
 STAT #47214410064360 id=2 cnt=0 pid=1 pos=1 obj=36155 op='TABLE ACCESS BY INDEX ROWID PATIENT (cr=3 pr=0 pw=0 str=1 time=18 us cost=1 size=8 card=1)'
 STAT #47214410064360 id=3 cnt=1 pid=2 pos=1 obj=36828 op='INDEX UNIQUE SCAN PATIENT_PRIMARY (cr=2 pr=0 pw=0 str=1 time=9 us cost=1 size=0 card=1)'
 STAT #47214410064360 id=4 cnt=0 pid=1 pos=2 obj=59873 op='TABLE ACCESS BY INDEX ROWID LANGCD (cr=0 pr=0 pw=0 str=0 time=0 us cost=1 size=17 card=1)'
 STAT #47214410064360 id=5 cnt=0 pid=4 pos=1 obj=59874 op='INDEX UNIQUE SCAN LANGCD_PRIMARY (cr=0 pr=0 pw=0 str=0 time=0 us cost=1 size=0 card=1)'
 XCTEND rlbk=0, rd_only=1, tim=3592707059273
 WAIT #47214410064360: nam='SQL*Net message from client' ela= 5194 driver id=1413697536 #bytes=1 p3=0 obj#=36496 tim=3592707064511
 CLOSE #47214410064360:c=16,e=16,dep=0,type=1,tim=3592707064576

 Many of the SQL statements in this trace file return only 1 row.

 There is nothing that can be done to speed this up by setting any array size parameter.

 In this case, it would be worth investigating just why there are so many SQL statements returning only 1 row.

 If this is just how the application works, there's little to be done to improve performanance, at least from the perspective of a DBA.
 
 It would likely be necessary to make changes to the application to improve this situation.

 There is a case though that is worth considering.

 Some applications will perform many SQL statements that nearly always return the same data.

 Think of rarely changing configuration data, or nearly static application data.

 For applications built with OCI (Oracle Call Interface), there is a possibilty of using Oracle Client Result Cache to eliminate database calls.

 See: https://www.pythian.com/blog/mitigating-long-distance-network-latencies-with-oracle-client-result-cache


=cut

=head1 Some internals explanations

 - measure the time for snmfc for each EXEC
 - get the rows returned per FETCH
 - count the SNMFC
 - accumulate time for SNMFC

 $execID = trace file line# + cursor_id

 the $execID used is the most recent one that matches the cursor#

 In this case, execID is being set only for EXEC calls

 We want to get stats for an executing cursor
 
 $cursorMetrics{$execID} = (
 	FETCH_COUNT => total number of fetches for exec
	FETCH_ROWS => total number of rows FETCHed
	SNMFC_COUNT => total number of SNMFC
	SNMFC_TIME => accumulated time for cursor
 )

 the average array size can be calculated from these metrics
 We do not care about the time for FETCH - there is no performance increase availablein the FETCH
 the more you FETCH, the longer it takes.
 the savings is in reducing SNMFC

 This technique has no value for PL/SQL - there is no SNMFC

=cut


