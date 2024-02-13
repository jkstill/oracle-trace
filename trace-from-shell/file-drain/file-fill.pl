#!/usr/bin/env perl

use warnings;
use strict;
use IO::File;
use Fcntl;
use Data::Dumper;
use Time::HiRes qw( usleep );

# this script just files the source 'trace' file

my $confFile='file-drain.conf';

my $fh = IO::File->new;

$fh->open($confFile,'<') or die "could not open $confFile - $!\n";

my @conf = <$fh>;

chomp @conf;

# config file is in a form for Bash
# modify for use by Perl
@conf = grep (/^[[:alnum:]]/, @conf);
@conf = map { $_ = '$' . $_ . ';' } @conf;

#print Dumper(\@conf);

# necessary for this type of config file
no strict 'vars';

foreach my $kv ( @conf ) {
	our ($key,$val) = split(/=/,$kv);
	$key =~ s/\s//g;
	$val =~ s/\s//g;
	print "key: $key  val: $val\n";
	eval "$kv";
	#print "$diagDest\n";
}


print "diagDest: $diagDest\n";
#print "copyDest: $copyDest\n";
my $traceFile="$diagDest/$traceFileName";
print "traceFile: $traceFile\n";


# initial open of source file is read - later will be w+ to truncate
$fh->open($traceFile,'w', O_APPEND) or die "could not open $traceFile for writing - $!\n";

$|=1;

while (1) {
	#print ".";
	$fh->write( $i++ . ":test line\n" );
	#$fh->sysseek(0, SEEK_CUR);
	sysseek($fh, 0, SEEK_CUR);
	$fh->flush;
	usleep(100);
}





