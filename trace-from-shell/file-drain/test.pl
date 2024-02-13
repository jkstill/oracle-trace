#!/usr/bin/env perl
#

use strict;
use warnings;

#
#---------------------------------------------------------------------------------------#
# do what's needed to read in the configuration file.                                   #
# see the bottom of this url (http://www.perl.com/pub/a/2003/08/07/design2.html?page=3) #
#---------------------------------------------------------------------------------------#
my $config_file = $ARGV[0];
open CONFIG, "$config_file" or die "Program stopping, couldn't open the configuration file '$config_file'.\n";
my $config = join "", <CONFIG>;
close CONFIG;

print $config;

exit;

no strict;
eval $config;
die "Couldn't interpret the configuration file ($config_file) that was given.\nError details follow: $@\n" if $@;

no strict;
print "debug_mode: $debug_mode\n";

