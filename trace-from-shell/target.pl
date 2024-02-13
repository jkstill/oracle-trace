#!/usr/bin/env perl

use warnings;
use strict;
use FileHandle;
use DBI;
use Getopt::Long;
use Data::Dumper;
use Time::HiRes qw(usleep);
use Term::ReadKey;


my %optctl = ();

my($db, $username, $password);
my ($help, $sysdba, $connectionMode, $localSysdba, $sysOper) = (0,0,0,0,0);
my $traceLevel=0;
my $traceFileName='';
my $tracefileIdentifier=''; # probably not using this
my $runtimeSeconds=1; 
my $intervalSeconds=1;
my $programName='';
my $rowCacheSize=0; # if zero, the value is not set and defaults are used
my $iterations = 0;
my $server='';

Getopt::Long::GetOptions(
	\%optctl,
	"database=s"					=> \$db,
	"username=s"					=> \$username,
	"password=s"					=> \$password,
	"runtime-seconds=i"			=> \$runtimeSeconds,
	"interval-seconds=f"			=> \$intervalSeconds,
	"program-name=s"				=> \$programName,
	"row-cache-size=i"			=> \$rowCacheSize,
	"iterations=i"					=> \$iterations,
	"trace-level=i"				=> \$traceLevel,
	"tracefile-identifier=s"	=> \$tracefileIdentifier,
	"sysdba!"						=> \$sysdba,
	"local-sysdba!"				=> \$localSysdba,
	"sysoper!"						=> \$sysOper,
	"z|h|help"						=> \$help
);

my $uSleepSeconds = $intervalSeconds * 1_000_000;

if (! $localSysdba) {

	$connectionMode = 0;
	if ( $sysOper ) { $connectionMode = 4 }
	if ( $sysdba ) { $connectionMode = 2 }

	#usage(1) unless ($db and $username and $password);
	usage(1) unless ($db and $username);
}

if ($programName) {
	$0="$programName";
}

$|=1; # flush output immediately

my $dbh ;

if ($localSysdba) {
	$dbh = DBI->connect(
		'dbi:Oracle:',undef,undef,
		{
			RaiseError => 1,
			AutoCommit => 0,
			ora_session_mode => 2,
			ora_connect_with_default_signals =>  [ 'INT', 'QUIT', 'TERM' ]
		}
	);
} else {

	unless ($password) {
		print "Password: ";
		ReadMode ( 'noecho' );
		$password = <STDIN>;
		chomp $password;
		ReadMode ( 'normal' );
	}
	
	$dbh = DBI->connect(
		'dbi:Oracle:' . $db,
		$username, $password,
		{
			RaiseError => 1,
			AutoCommit => 0,
			ora_session_mode => $connectionMode,
			ora_connect_with_default_signals =>  [ 'INT', 'QUIT', 'TERM' ]
		}
	);
}

die "Connect to  $db failed \n" unless $dbh;

if ($traceLevel) {
	$dbh->do(qq{alter session set events '10046 trace name context forever, level $traceLevel'});
	if ($@) {
		warn "could not enable trace level: $traceLevel";
		die "error: $@\n";
	}

	if ($tracefileIdentifier) {
		$dbh->do(qq{alter session set tracefile_identifier = '$tracefileIdentifier'});
	}

	my $sql=q{select value from v$diag_info where name = 'Default Trace File'};
	my $sth=$dbh->prepare($sql);
	$sth->execute;
	($traceFileName) = $sth->fetchrow_array;
	$sth->finish;

	$sql=q{select host_name from v$instance};
	$sth=$dbh->prepare($sql);
	$sth->execute;
	($server) = $sth->fetchrow_array;
	$sth->finish;


}

if ($rowCacheSize > 0) {
	print "setting RowCacheSize = $rowCacheSize\n";
	$dbh->{RowCacheSize} = $rowCacheSize;
} else {
print "NOT setting RowCacheSize\n";
}

$SIG{INT}=\&cleanup;
$SIG{QUIT}=\&cleanup;
$SIG{TERM}=\&cleanup;
	
my ($sql,$sth);

#$sql = 'select sysdate from dual';
# create table '302910".test_objects as select * from dba_objects
$sql = 'select owner, object_name, object_id, object_type from test_objects where rownum <= 10000';
$sth=$dbh->prepare($sql);

# $runtimeSeconds is approximate, as the value actually used will be $runtimeSeconds / $usleepSeconds

# do not calculate iterations if it was set from the cli
unless($iterations) { $iterations = int($runtimeSeconds / $intervalSeconds); }

print qq{
  runtimeSeconds: $runtimeSeconds
 intervalSeconds: $intervalSeconds
      iterations: $iterations
};

for  (my $i=1; $i<=$iterations; $i++) {
	$sth->execute;
	while ( my  ($owner, $objectName, $objectID, $objectType) = $sth->fetchrow_array ) {
		;
	}
	$sth->finish;
	#print "$i ";
	usleep($uSleepSeconds);
}

$dbh->disconnect;

print "\n";
print "server: $server\n" if $server;
print "tracefile: $traceFileName\n\n" if $traceFileName;
if ($server and $traceFileName) {
	print "scp oracle\@$server:$traceFileName ...\n";
	mkdir 'trace';
	qx(scp oracle\@$server:$traceFileName trace);
}


sub usage {
	my $exitVal = shift;
	$exitVal = 0 unless defined $exitVal;
	use File::Basename;
	my $basename = basename($0);
	print qq/

usage: $basename

  --database              target instance
  --username              target instance account name
  --password              target instance account password
  --runtime-seconds       total seconds to run
  --interval-seconds      seconds to sleep each pass - can be < 1 second
  --iterations            set the iterations - default is calculated
  --trace-level           10046 trace - default is 0 (off)
  --tracefile-identifier  tag for the trace filename
  --program-name          change the \$0 value to something else
  --row-cache-size        rows to fetch per call
  --sysdba                logon as sysdba
  --sysoper               logon as sysoper
  --local-sysdba          logon to local instance as sysdba. ORACLE_SID must be set
                            the following options will be ignored:
                            --database
                            --username
                            --password

  example:

  $basename --database dv07 --username scott --password tiger --sysdba

  $basename --local-sysdba

/;
	exit $exitVal;
};

sub cleanup {
	$sth->finish;
	$dbh->disconnect;
	exit 0;
}

