#!/usr/bin/env perl

use warnings;
use strict;
#use Data::Dumper;
use Getopt::Long;
use IO::File;

=head1 Test

 cp trace/base-test.trc test.trc; chmod u+w test.trc
 ./bind-redact.pl --tracefile test.trc --backup-extension '.bkup'
 grep -E '^\s+value=' test.trc | sort | uniq -c | sort -n
 
 or use this for group by obfuscated bind values
 grep -E '^\s+value=' test.trc | sort | uniq -c | sort -t- -k2 -n

 This diff command is useful for revealing changes to the trace file when the --backup-extension option is used

 diff -w test.trc test.trc.bkup | grep -Ev '^(\.|[[:digit:],]+[cd])$' | sort -u

 or

 diff -w test.trc test.trc.bkup | grep -Ev '^(\.|[[:digit:],]+[cd])[[:digit:],]+$' | sort -u

=cut

# set to 0 to redact dates
my $preserveDates=0; 

## these variables are used only in getObfuscatedRedaction()
my $counterPrecision=5; # number of digits on displayed bind value counters
my %obfuscatedNumerics=();
my %obfuscatedDates=();
my %obfuscatedTimestamps=();

my %obfuscatedCounters = (
	numeric		=> 0,
	date			=> 0,
	timestamp	=> 0,
);

# preserver purely numeric values
# the intent is to preserve data that is only useful from within the database
# primary key values, record number, etc
# be careful that there are no values such as SSN, Phone#, etc.
my $preserveNumerics=0; 
my $useObfuscatedRedactions=0;
my $quoted=0;
my $help=0;
my $traceFile;
my $userBkupExtension='';
my $tempExtension='.orig';  # required for tmp
my $redactSQL=1;
my $redactSQLPhrase="HC-Redacted";  # Hard Coding Redacted

GetOptions (
	"tracefile=s"	=> \$traceFile,
	"backup-extension=s" => \$userBkupExtension,
	"preserve-numerics!" => \$preserveNumerics,
	"preserve-dates!" => \$preserveDates,
	"obfuscate-redactions!" => \$useObfuscatedRedactions,
	"redact-sql!" => \$redactSQL,
	"redact-sql-string=s" => \$redactSQLPhrase,
	"h|help!" => \$help,
) or die usage(1);

usage() if $help;


die "requires filename\n" unless defined($traceFile);
die "cannot read filename\n" unless -r $traceFile;
die "cannot write filename\n" unless -w $traceFile;

print $traceFile . "\n";

# setup the trace file to be like using -i - it is overwritten unless --backup-extension '.bkup' is used

# determine the extension to use, and whether the backup should be kept
# default is to not keep backup
my $bkupExtension = $userBkupExtension ? $userBkupExtension : $tempExtension;
my $keepBackup = $userBkupExtension ? 1 : 0;
my $tempFile=$traceFile.$bkupExtension;

#print "u: $userBkupExtension\n";
#print "b: $bkupExtension\n";
#print "$tempFile\n";
#exit;

my $srcFH = IO::File->new();
my $dstFH = IO::File->new();

$srcFH->open($traceFile,'<');
$dstFH->open($tempFile,'>');

# bind values will not be altered for numerics, or dates/timestamps 
# when preserve-numerics or preserve-dates is set, even if obfuscate-redactions is used
# the use of obfuscate-redactions will affect only the items not indicated for preservation

my $prevLine='NOOP';
my $SQLBlock=0;
my $SQL='';

sub isDate($$);
sub isTimestamp($$);
sub getObfuscatedRedaction($$);
sub redactSQL($$);

# pass handle and line
my %lineActions = (
	'BINDS'	=> sub{$_[0]->write($_[1]);},
	'CLOSE'	=> sub{$_[0]->write($_[1]);},
	'EXEC'	=> sub{$_[0]->write($_[1]);},
	'FETCH'	=> sub{$_[0]->write($_[1]);},
	'PARSE'	=> sub{$_[0]->write($_[1]);},
	'STAT'	=> sub{$_[0]->write($_[1]);},
	'WAIT'	=> sub{$_[0]->write($_[1]);},
);

sub getLineClass {

	my ($lineClass,$line) = @_;

	if ( $line =~ /^?(BINDS|CLOSE|EXEC|FETCH|PARSE|STAT|WAIT|PARSING IN CURSOR|END OF STMT)/) {
		if ($1 eq 'PARSING IN CURSOR') { return 'SQL'; }
		elsif ($1 eq 'END OF STMT') { return 'SQLEND'; }
		else {return $1; }
	}

	if ($lineClass eq 'SQL') { return 'SQL'; }

}

my $lineClass='';

while (my $line = <$srcFH>) {

	if ( $. <2 && $line =~ /modified by bind-redact.pl/ ) {
		die "file previously modified by bind-redact.pl - abort\n";
	}

	if ($. == 1) {
		$dstFH->write("*** modified by bind-redact.pl\n");
	}

	# classify the line
	# classify as bind,close,fetch,... 
	# for SQL, classify as SQL until END OF STMT
	# my $lineClass;
	# lineClass = getLineClass($lineClass,$line)
	$lineClass = getLineClass($lineClass,$line);
	warn "lineClass: $lineClass\n";
	
	
	if ( $line =~ /^?(BINDS|CLOSE|EXEC|FETCH|PARSE|STAT|WAIT)/) {
		#$dstFH->write($line);
		$lineActions{$1}($dstFH,$line);
		next;
	}

	# the line after PARSING is SQL or PL/SQL
	# end of SQL marked by 'END OF STMT'
	if ($line =~/^PARSING IN CURSOR/ or $SQLBlock) {

		if ($line =~/^PARSING IN CURSOR/) {
			#print "LINE: $line\n";
			$dstFH->write($line);
			$SQL='';
			$SQLBlock=1;
			next;
		}
	
		#print "PARSING:\n";
		if ($line =~ /^END OF STMT/) {
				$SQLBlock=0;
				#print "SQL: $SQL\n";
				if ($redactSQL) {
					my $redactedSQL = redactSQL($SQL,$redactSQLPhrase);
					$dstFH->write("$redactedSQL\n");
				} else {
					$dstFH->write("$SQL\n");
				}
				#print "SQL: $redactedSQL\n";
				$dstFH->write($line);
			} else {
				#$SQLBlock=1;
				$SQL .=  $line;
			}

		next;
	}


	# bind value line
	if ( $line =~ /^\s+value=["]{0,1}.*["]{0,1}$/ ) {

		$prevLine=$line;
		my ($prefix,$value) = split(/=/,$line);

		if ( isTimestamp($value,\$quoted)) {
			if ($preserveDates) {
				#print "$line\n";
				$dstFH->write($line);
			} else {
				if ($useObfuscatedRedactions) {
					$value=getObfuscatedRedaction('timestamp',$value);
				} else {
					$value='"Timestamp Redacted"';
				}
				#print qq{$prefix=$value\n};
				$dstFH->write( qq{$prefix=$value\n});
			}
			next;
		} elsif ( isDate($value,\$quoted) ) {
			if ($preserveDates) {
				#print "$line\n";
				$dstFH->write($line);
			} else {
				if ($useObfuscatedRedactions) {
					$value=getObfuscatedRedaction('date',$value);
				} else {
					$value='"Date Redacted"';
				}
				#print qq{$prefix=$value\n};
				$dstFH->write(qq{$prefix=$value\n});
			}
			next;
		# timestamps

		# integer numeric values
		} elsif (
			$value =~ /^["]{0,1}[[:digit:]]+["]{0,1}$/
				or
			$value =~ /^[[:digit:]]+$/
			or
			$value =~ /^1227$/
		) {
			#warn "numeric: $value\n";
			if ($preserveNumerics) {
				#print "$line\n";
				$dstFH->write($line);
			} else {
				if ($useObfuscatedRedactions) {
					$value=getObfuscatedRedaction('numeric',$value);
				} else {
					$value='"Numeric Redacted"';
				}
				#warn "$value : $line\n";
				#print qq{$prefix=$value\n};
				$dstFH->write(qq{$prefix=$value\n});
				next;
			}
		} else {
			$value='"Redacted"';
			#print qq{$prefix=$value\n};
			$dstFH->write(qq{$prefix=$value\n});
			next;
		}	
	}

	# catch wrapped lines
	if ($prevLine =~ /^\s+value=".*["]*/ ) {
		unless ( $line =~ / +Bind#[0-9]+/ ) {
			#warn "redacting wrapped line\n";
			#print "#WRAP REDACTED\n";
			$dstFH->write("#WRAP REDACTED\n");
			next;
		}
	}

	#print "$line\n";
	$dstFH->write($line);
	$prevLine=$line;
}

close $srcFH;
close $srcFH;

my $tmpName = $traceFile . '.' . $$;
if ($keepBackup) {
	unless (rename $traceFile, $tmpName) {die "failed renaming $traceFile to $tmpName\n";};
	unless (rename $tempFile, $traceFile) {die "failed renaming $tempFile to $traceFile\n";};
	unless (rename $tmpName, $tempFile ) {die "failed renaming $traceFile to $tempFile\n";};
	print "Backup file is $tempFile\n";
} else {
	unless (rename $traceFile, $tmpName) {die "failed renaming $traceFile to $tmpName\n";};
	unless (rename $tempFile, $traceFile) {die "failed renaming $tempFile to $traceFile\n";};
	unless (unlink $tmpName) {die "failed removing $tmpName\n";};
}

######################################################
## End of Main
######################################################


sub redactSQL($$) {
	my ($SQL,$redactPhrase) =  @_;

	#print "==========================================\n";
	#print "redactSQL: $SQL - EOS\n";
	#print "Checking SQL\n";

	my $redactedSQL = $SQL;
	my ($watchdog,$watchdogThreshold) = (0,10000);

	my $metaChars='\.\,\t\s\?\^\!';

	if ($SQL =~ /('[[:alnum:]_${metaChars}-]+')/ms) { # tb + space
		#warn "\t initial match: $1\n";
		
		while ($SQL =~ /('[[:alnum:]_${metaChars}-]+')/gm) {

			#warn "\tmatch: $1\n" if $1;
			#warn "\tWord is $1, ends at position ", pos $SQL, "\n";	

			eval {
				substr($redactedSQL,(pos $SQL) - length($1),length($1)) = q{'} . substr($redactPhrase x 100, 0, length($1)-2) . q{'};
			};

			if ($@) {
				die "\nredactSQL()  error\n$@\nSQL: $redactedSQL\n";
			}

			# in case of endless loop
			die "\nredactSQL() - watchdog threshold $watchdog\n" if ++$watchdog >= $watchdogThreshold;
		}
	}
	return $redactedSQL;
}


# return 0 if not date, 1 if date
# if date, then set quoted to 0 if no double quotes, and to 1 if double quotes
# my $quoted=0
# my $isThisADate = isDate($dateString,\$quoted)
sub isDate ($$) {
	my ($internalDateString, $quotedRef) = @_;
	if (
		$internalDateString =~ /^["]{0,1}
			[[:digit:]]{1,4}			# year, month or day
			[\/-]{1}        
			[[:digit:]]{1,2}			# month or day
			[\/-]{1}        
			[[:digit:]]{1,4}			# year, month or day
			(\s)*							# whitespace
			([[:digit:]:_-]{1,8})*  # time
			[\s+-]*						# whitespace
			(AM|PM|am|pm)*
			["]{0,1}
		$/x
	) {
		$$quotedRef = 1 if $internalDateString =~ /^".*"$/;
		return 1;
	}

	return 0;
}

sub isTimestamp ($$) {
	my ($internalDateString, $quotedRef) = @_;
	if (
		$internalDateString =~ /^["]{0,1}
			[[:alnum:]\s.-]{9,11}			# date in dd-Mon-YY - maybe YYYY
			[[:digit:].]{10,20}				# time
			[\s]+
			(AM|PM|am|pm)+(\s+[[:digit:]:+-]+)*
			["]{0,1}
		$/x
	) {
		$$quotedRef = 1 if $internalDateString =~ /^".*"$/;
		return 1;
	}
	return 0;
}

sub getObfuscatedRedaction($$) {

	my ($type,$value) = @_;
	my ($counter,$prefix);

	if ($type eq 'numeric') {
		$prefix = 'Numeric';
		if ($obfuscatedNumerics{$value}) {
			$counter=sprintf("%0${counterPrecision}s", $obfuscatedNumerics{$value});	
		} else {
			$counter=sprintf("%0${counterPrecision}s", $obfuscatedCounters{$type}++);
			$obfuscatedNumerics{$value} = $counter;
		}
	} elsif ($type eq 'date') {
		$prefix = 'Date';
		if ($obfuscatedDates{$value}) {
			$counter=sprintf("%0${counterPrecision}s", $obfuscatedDates{$value});	
		} else {
			$counter=sprintf("%0${counterPrecision}s", $obfuscatedCounters{$type}++);
			$obfuscatedDates{$value} = $counter;
		}
	} elsif ($type eq 'timestamp') {
		#warn "Timestamp - $type - $value\n";
		$prefix = 'Timestamp';
		if ($obfuscatedTimestamps{$value}) {
			$counter=sprintf("%0${counterPrecision}s", $obfuscatedTimestamps{$value});	
		} else {
			$counter=sprintf("%0${counterPrecision}s", $obfuscatedCounters{$type}++);
			$obfuscatedTimestamps{$value} = $counter;
		}
	} else {
		die "unknown type of $type in getObfuscatedRedaction()\n";
	}


	return sprintf('%s', $prefix . '-' . $counter);
}

sub usage {

   my $exitVal = shift;
   use File::Basename;
   my $basename = basename($0);
   print qq{
$basename

usage: $basename - Redact or obfuscate bind values in Oracle 10046 trace files

   $basename --tracefile filename  <--preserve-numerics> <--preserve-dates> <--obfuscate-redactions> \
      <--redact-sql> <--redact-sql-string>

   Defaults: 
   The source file will be over-written
   All bind variable values will be redacted

   --tracefile               The 10046 trace file

   --backup-extension        The extension for the backup file - by default no backup is made

   --preserve-numerics       preserve integer bind values. these are often internal values, not personal data
                             be careful of things such as SSN, phone#, etc.
                             future: recognize common exceptions such as SSN
 
   --preserve-dates          preserve dates and timestamps

   --obfuscate-redactions    for dates, timestamps and numeric values that are not being preserved, replace
                             them with numbered place holders
                             Ex.  '2023-02-01' becomes 'Date-00000', '2023-06-10' becomes 'Date-00002', etc.
                             These can still be valuable for analysis when grouping on bind values is desired
                             Otherwise the value will simply be 'Redacted'

   --redact-sql              Redact anything found in hard coded in single quotes in a SQL statement
                             This is the default.

   --redact-sql-string       The phrase used to redact hard coding found in SQL. Default is 'HC-Redacted'


   Options that are a binary on/off switch, such as --redact-sql, can be negatet with 'no'
   eg. $basename ... --noredact-sql
  
examples here:

   $basename --tracefile DWDB_ora_63389.trc --preserve-dates --obfuscate-redactions --backup-extension '.save'

};

   exit eval { defined($exitVal) ? $exitVal : 0 };
}


