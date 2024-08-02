#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;

=head1 REDACT

 redact anything that looks like a:
  - phone#
  - email address
  - physical address
  - bind value

  todo: dates.  Currently replaced with values that are clearly not date - maybe that is ok

=cut

my $debug=0;

my %generics=();
my %phones=();
my %numbers=();
my %emails=();
my %ssn=();
# dates not yet implemented
my %dates=();

my %dispatch = (
	'SSN' => \&_redactSSN,
	'NUMBER' => \&_redactNumber,
	'PHONE' => \&_redactPhone,
	'EMAIL' => \&_redactEmail,
	'GENERIC' => \&_redactGeneric,
	'DATE' => \&_redactDate,
);


# build random strings once per run
my %randomStrings = (
	'PHONE' =>  sub{ my $r; for ( my $i=0; $i<100; $i++ ) { $r .= chr(48 + int(rand(10))); } ; return $r },
	'SSN' =>  sub{ my $r; for ( my $i=0; $i<100; $i++ ) { $r .= chr(48 + int(rand(10))); } ; return $r },
	'NUMBER' =>  sub{ my $r; for ( my $i=0; $i<100; $i++ ) { $r .= chr(48 + int(rand(10))); } ; return $r },

	'GENERIC' => sub {
		my $r;
		#my $d = q/ !"#$%&'()*+,.:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}/;
		my $d = q/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz/;
		$d .= '/';
		my @data = split(//,$d);
		for ( my $i=0; $i<=$#data; $i++ ) {   
			$r .= $data[int(rand(scalar(@data)))];
		}
		return $r;
	},

	'EMAIL' =>  sub{ 
		my $d = '0123456789?ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-';
		my @data = split(//,$d);
		my $r; 
		for ( my $i=0; $i<=$#data; $i++ ) {   
			#$r .=  'NA';
			$r .= $data[int(rand(scalar(@data)))];
		}

		return $r;
	},
);

#print Dumper(\%randomStrings);


my @traceKeywords = qw{\*\*\* ====== Version: Version Machine: "'Unix process'" "'Build label:'" CLOSE EXEC FETCH PARSE PARSING STAT WAIT XCTEND};
#my @traceKeywords = qw{Version: Version Machine: "'Unix process'" };

my $traceKeywordsRegex=join('|',@traceKeywords);

warn "$traceKeywordsRegex\n" if $debug;

while (<STDIN>) {
	my $line=$_;

	if ( $line =~ /^($traceKeywordsRegex)/g ) {
		if ($debug) {
			print "keyword line: $line";
		} else {
			print "$line";
		}
		next;
	}

	# is there quoted material?
	#if ($line =~ /'.+'/ ) {
	if ($line =~ /('.+'|value=".+")/ ) {
		my $newLine = $line;
		warn "original: $line" if $debug;

		#  non greedy match, otherwise "'test' more text 'another test'" will match the entire string
		my @terms = $newLine =~ /('.*?'|".*?")/g;
		foreach my $term ( @terms ) {
			warn "====================================\n" if $debug;
			warn "   term: $term\n" if $debug;
			my $newTerm = redact($term);
			warn "   newTerm: $newTerm\n" if $debug;
			# the problem with quotemeta is too much is converted
			# just catch the error
			# use quotemeta as sometimes sqltrace has broken lines
			#$newLine =~ s/\Q$term\E/\Q$newTerm\E/;
			eval {
				$newLine =~ s/$term/$newTerm/;
			};
			if ($@) { 
				# do nothing for now
			}
		}
		$line = $newLine;

		#print "new: $newLine";
	}

	if ( $debug) {
		print "redacted: $line";
	} else {
		print $line;
	}

}


sub _redactPhone ($) {
	my ($term) = @_;

	my $newTerm = $term;

	#print "PHONE TERM: $term\n";

	if ( exists($phones{$term}) ) {
		return $phones{$term};
	} else {
		#my $phoneChars =  int(rand(1) * 9999999999999999999999);
		my $phoneChars = $randomStrings{PHONE}();

		#print "phoneChars: $phoneChars\n";
		# tr does not work for this
		# cannot get regex to work either
		# brute force
		#print "newTerm: $newTerm\n";

		my @chars = split(//,$newTerm);
		#print '@chars: ' . join('|',@chars) . "\n";

		foreach my $idx ( 0 .. $#chars ) {
			next unless $chars[$idx] =~ /[0-9]/;
			#print "old char: $chars[$idx]  new char:  " . substr($phoneChars,$idx,1) . " idx: $idx\n";
			#my $old = substr($newTerm,$idx,1,substr($phoneChars,$idx,1));
			my $pos = int(rand(length($phoneChars)));
			my $old = substr($newTerm,$idx,1,substr($phoneChars,$pos,1));
		}

		#warn "newTerm: $newTerm\n";
	}

	$phones{$term} = $newTerm;
	return $newTerm;
}

sub _redactNumber {
	my ($term) = @_;

	my $newTerm = $term;

	warn "NUMBER TERM: $term\n" if $debug;

	if ( exists($numbers{$term}) ) {
		return $numbers{$term};
	} else {
		my $numberChars = $randomStrings{NUMBER}();

		my @chars = split(//,$newTerm);
		foreach my $idx ( 0 .. $#chars ) {
			next unless $chars[$idx] =~ /[0-9]/;
			my $pos = int(rand(length($numberChars)));
			my $old = substr($newTerm,$idx,1,substr($numberChars,$pos,1));
		}

		#warn "newTerm: $newTerm\n";
	}

	$numbers{$term} = $newTerm;
	return $newTerm;
}

sub _redactSSN {
	my ($term) = @_;

	my $newTerm = $term;

	#print "SSN TERM: $term\n";

	if ( exists($ssn{$term}) ) {
		return $ssn{$term};
	} else {
		my $ssnChars = $randomStrings{SSN}();

		my @chars = split(//,$newTerm);

		foreach my $idx ( 0 .. $#chars ) {
			next unless $chars[$idx] =~ /[0-9]/;
			my $pos = int(rand(length($ssnChars)));
			my $old = substr($newTerm,$idx,1,substr($ssnChars,$pos,1));
		}

	}

	$ssn{$term} = $newTerm;
	return $newTerm;
}

sub _redactEmail {
	my ($term) = @_;

	my $newTerm = $term;

	#print "EMAIL TERM: $term\n";

	if ( exists($emails{$term}) ) {
		return $emails{$term};
	} else {
		my $emailChars = $randomStrings{EMAIL}();
		#print "emailChars: $emailChars\n";

		my @chars = split(//,$newTerm);

		foreach my $idx ( 0 .. $#chars ) {
			next if  $chars[$idx] =~ /['.@]/;
			my $pos = int(rand(length($emailChars)));
			#print "old char: $chars[$idx]  new char:  " . substr($emailChars,$idx,1) . " idx: $idx\n";
			my $old = substr($newTerm,$idx,1,substr($emailChars,$pos,1));
		}

	}

	$emails{$term} = $newTerm;

	return $newTerm;
}

# todo
sub _redactDate {
	my ($term) = @_;
	return $term;
}
# replace characters and numbers

sub _redactGeneric {
	my ($term) = @_;
	
	my $newTerm = $term;

	#print "GENERIC TERM: $term\n";

	if ( exists($generics{$term}) ) {
		return $generics{$term};
	} else {
		my $numberChars = $randomStrings{NUMBER}();
		my $genericChars = $randomStrings{GENERIC}();

		my @chars = split(//,$newTerm);

		foreach my $idx ( 0 .. $#chars ) {
			#print "${numberChars}${genericChars}\n";
			#next unless  $chars[$idx] =~ /[${numberChars}${genericChars}]/;
			#print "chr: $chars[$idx]\n";
			if ( $chars[$idx] =~ /[$numberChars]/ ) {
				#print "number: $chars[$idx]  idx: $idx\n";
				my $pos = int(rand(length($numberChars)));
				my $old = substr($newTerm,$idx,1,substr($numberChars,$pos,1));
 			} elsif (  $chars[$idx] =~ /[$genericChars]/ ) {
				#print "generic: $chars[$idx]  idx: $idx\n";
				my $pos = int(rand(length($genericChars)));
				my $old = substr($newTerm,$idx,1,substr($genericChars,$pos,1));
			} else {
				#die " _redactGeneric:  char  |$chars[$idx]|\n";
				next;
			}
		}

	}

	$generics{$term} = $newTerm;

	return $newTerm;

}

#print '%dispatch: ' .  Dumper(\%dispatch);

sub redact {
	my ($term) = @_;
	my $termType = getTermType($term);
	warn "TERM TYPE: $termType\n" if $debug;
	my $redact = $dispatch{$termType}($term);
}

sub getTermType {
	my ($term) = @_;

	if ( $term =~ /^["']([[:digit:]]{3}-[[:digit:]]{3}-[[:digit:]]{4}|^\+[[:digit:]]{1,2}\s+[[:digit:]\s-]{7,11})["']/) 
	{ return 'PHONE'; };

	if ( $term =~ /^["']([[:digit:]]{3}[- ]{0,1}[[:digit:]]{2}[- ]{0,1}[[:digit:]]{4})["']/) { return 'SSN'; }

	if ( $term =~ /^["'].+@.+["']/ ) { return 'EMAIL'; }
	
	if ( $term =~ /^["'][[:digit:],.]+["']$/ ) { return 'NUMBER'; }

	# dates - for now just call them numbers if the date has no alpha characters
	# will eventually call _redactDate
	if ( $term =~ /^["'][[:digit:]\/:\-]+["']$/ ) { return 'NUMBER'; }


	return 'GENERIC';

}


