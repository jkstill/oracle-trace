#!/usr/bin/env perl

use warnings;
use strict;


my $quoted=0;

while (<STDIN>){
	my $line=$_;
	chomp $line;

	printf "%5i - " , $.+0;

	if ($line =~ /^\s*$/) {
		print "blank:$line|\n";	
	# this is identifying all 'date' values in dates.txt
	#} elsif ($line =~ /^[[:digit:](\s)*:\/"(AM|PM|am|pm)*-]+$/) {
	} elsif ( isDate($line,\$quoted)) {
		my $quoteChar = $quoted ? '"' : '';
		print "date: $quoteChar$line$quoteChar  $quoted\n";
	} elsif (isTimestamp($line,\$quoted)) {
		print "timestamp $line\n";
	} else {
		print "not date: $line\n";
	}
}


# return 0 if not date, 1 if date
# if date, then set quoted to 0 if no double quotes, and to 1 if double quotes
# my $quoted=0
# my $isThisADate = isDate($dateString,\$quoted)
sub isDate () {
	my ($_internalDateString, $_quotedRef) = @_;
	if (
		$_internalDateString =~ /^["]{0,1}
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
		#no strict 'refs';
		$$_quotedRef = 1 if $_internalDateString =~ /^".*"$/;
		return 1;
	}

	return 0;
}

sub isTimestamp () {
	my ($_internalDateString, $_quotedRef) = @_;
	if (
		$_internalDateString =~ /^["]{0,1}
			[[:alnum:]\s.-]{9,11}			# date in dd-Mon-YY - maybe YYYY
			[[:digit:].]{10,20}				# time
			[\s]+
			(AM|PM|am|pm)+(\s+[[:digit:]:+-]+)*
			["]{0,1}
		$/x
	) {
		$$_quotedRef = 1 if $_internalDateString =~ /^".*"$/;
		return 1;
	}
	return 0;
}



