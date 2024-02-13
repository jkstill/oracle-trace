#!/usr/bin/env perl

# get-hc-sql.pl
# get hard coded sql and redact
# a prototype of redacting everything in single quotes in a SQL
use warnings;
use strict;
use IO::File;


my $srcFH = IO::File->new();
$srcFH->open('sql.txt','<');
#$srcFH->open('test.trc','<');

my ($sqlStart,$sqlEnd)=(0,0);
my $sql = '';

while (my $line = <$srcFH>) {

	next if $line =~ /^\s*$/;

	# sql.txt uses START OF STMT 
	# trace files use PARSING IN
	if ($line =~ /(START OF STMT|PARSING IN)/) {
		$sqlStart=1;
		$sqlEnd=0;
		$sql = '';
		next;
	} elsif ($line =~ /END OF STMT/) {
		$sqlEnd=1;
		$sqlStart=0;
		#print "SQL: $sql";
		
		my $redactedSQL = redactSQL($sql);
		print qq{Original SQL: $sql};
		print qq{Redacted SQL: $redactedSQL};


	} else {
		$sql .= $line;
		next;
	}


}

sub redactSQL {
	my ($SQL) =  @_;

	print "==========================================\n";
	print "redactSQL: $SQL - EOS\n";
	#print "Checking SQL\n";

	my $redactedSQL = $SQL;
	my ($watchdog,$watchdogThreshold) = (0,10000);

	if ($SQL =~ /('[[:alnum:]_\.\,\t\s-]+')/ms) {
		#warn "\t initial match: $1\n";

		while ($SQL =~ /('[[:alnum:]_\.\,\t\s-]+')/gm) {
	
			#warn "\tmatch: $1\n" if $1;
			print "\tWord is $1, ends at position ", pos $SQL, "\n";	
			eval {
				substr($redactedSQL,(pos $SQL) - length($1),length($1)) = q{'} . substr('Redacted' x 100, 0, length($1)-2) . q{'};
			};

			if ($@) {
				die "redactSQL() error - SQL: $redactedSQL\n";
			}

			# in case of endless loop
			die "watchdog threshold $watchdog\n" if ++$watchdog >= $watchdogThreshold;
		}
	}
	return $redactedSQL;
}

