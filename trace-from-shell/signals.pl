        use Config;
        use strict;

        my %sig_num;
        my @sig_name;
        unless($Config{sig_name} && $Config{sig_num}) {
            die "No sigs?";
        } else {
            my @names = split ' ', $Config{sig_name};
            @sig_num{@names} = split ' ', $Config{sig_num};
            foreach (@names) {
                $sig_name[$sig_num{$_}] ||= $_;
            }
        }

        print "signal #17 = $sig_name[17]\n";
        if ($sig_num{ALRM}) {
            print "SIGALRM is $sig_num{ALRM}\n";
        }
