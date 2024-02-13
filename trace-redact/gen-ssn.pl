#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

# generate values that are formatted as valid SSN
# does not matter if they are possibly valid or invalid
# anything in text that looks like an SSN will be redacted
# keeping it simple.
#
# Valid Formats
# 999999999
# 999-99-9999
#
# anything else is not SSN
# values that consist of exactly 9 digits, but are not quoted, are not considered SSN

# build a string of random single digits

my $ssnMaster='';
my $ssnMasterLastPos=2047;

for (my $i=0; $i < $ssnMasterLastPos; $i++ ){
	my $charInt = int(rand(10));
	# uncomment and use this to test for distribution
	# ./gen-ssn.pl | sort -n | uniq -c
	#print ":$charInt:\n";
	$ssnMaster .=  chr(48+$charInt);
}

# comment out  - viewed for testing distribution
# print "$ssnMaster\n";

# now generate some random SSN strings
my $ssnLength=9;

for (my $i=0; $i < 1e6; $i++ ){
	# get rand lengths from 5 - 17
	my $strLen = 5+int(rand(13));
	#print "$strLen\n";

	# periodically format as SSN
	# quotes required
	# dashes optional


	my $ssnPos = int(rand($ssnMasterLastPos)) - $strLen - 1;
	if ($ssnPos < 0) { $ssnPos = int(rand($strLen)); }

	if ($strLen = $ssnLength) {

		my $notSSN = $i % 13;

		if ($notSSN) {
			print substr($ssnMaster,$ssnPos,$strLen) . ",NOTSSN\n"
		} else {
			my $ssnStr = substr($ssnMaster,$ssnPos,$strLen);
			if ($i % 2) {
				print qq{'$ssnStr',SSN\n};
			} else {

				print q{'} . substr($ssnStr,0,3) . '-' . substr($ssnStr,3,2) . '-' . substr($ssnStr,5) . "',SSN\n";

				# was used for troubleshooting
=cut

				eval {
					use warnings FATAL => 'all';
					print q{SSN: '} . substr($ssnStr,0,3) . '-' . substr($ssnStr,3,2) . '-' . substr($ssnStr,5) . "'\n";
				};

				if ($@) {
					warn "=================================\n";
					warn "end of ssnMaster: " . substr($ssnMaster, -20) . "\n";
					warn "ssnPos $ssnPos\n";
					warn "ssn length: $ssnLength\n";
					warn "ssnStr: $ssnStr\n";
				}

=cut

			}
		}
	} else {
		my $quoteChar = ($i % 2) ? q{'} : '';
		print $quoteChar . substr($ssnMaster,$ssnPos,$strLen) . $quoteChar . "\n";
	}

}
	




