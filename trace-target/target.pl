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
my ($oraPreFetchMemory, $oraPreFetchRows)=(0,0); # alternative to rowCacheSize - do not use both
my $iterations = 0;
my $server='';
my $createTestTable=0;
my $dropTestTable=0;
my $sqlFile='';

Getopt::Long::GetOptions(
	\%optctl,
	"database=s"					=> \$db,
	"username=s"					=> \$username,
	"password=s"					=> \$password,
	"runtime-seconds=i"			=> \$runtimeSeconds,
	"interval-seconds=f"			=> \$intervalSeconds,
	"program-name=s"				=> \$programName,
	"row-cache-size=i"			=> \$rowCacheSize,
	"prefetch-rows=i"				=> \$oraPreFetchRows,
	"prefetch-memory=i"			=> \$oraPreFetchMemory,
	"iterations=i"					=> \$iterations,
	"trace-level=i"				=> \$traceLevel,
	"tracefile-identifier=s"	=> \$tracefileIdentifier,
	"create-test-table!"			=> \$createTestTable,
	"drop-test-table!"			=> \$dropTestTable,
	"sqlfile=s"				      => \$sqlFile,
	"sysdba!"						=> \$sysdba,
	"local-sysdba!"				=> \$localSysdba,
	"sysoper!"						=> \$sysOper,
	"z|h|help"						=> \$help
);

#if ($rowCacheSize and $oraPreFetchRows ) { usage(1); }

my %SQL = (
	CREATE => 'select owner, object_name, object_id, object_type from test_objects where rownum <= 10000',
	QUERY => 'select * from test_objects where rownum <= 10000',
	TABLE => 'TEST_OBJECTS',
	ROWLEN => 500,
);

=head1 sqlfile

 This is a file containing commands to create, and execute a query on something other than the default internal table.

 The default table is TEST_OBJECTS, which is created from DBA_OBJECTS.

 The default query is to select 10,000 rows from this table.

 Here are the contents of a supplied config file 

  CREATE:create table rowcache_test pctfree 0 initrans 1 as select cast(level + 1e6 as number(8) ) id, dbms_random.string('L',93) data from dual connect by level <= 10000
  TABLE:rowcache_test
  QUERY:select id, data from rowcache_test
  ROWLEN:100

=cut

if ($sqlFile) {
	open(FH, $sqlFile) or die "could not open $sqlFile - $!\n";
	while (<FH>) {

		next if /^#/;
		next if /^\s*$/;

		chomp;

		my $line=$_;
		my ($key,$value) = split(/:/,$line);
		$SQL{$key} = $value;
	}
	close FH;
}

#print Dumper(\%SQL);
#exit;

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
			ora_connect_with_default_signals =>  [ 'INT', 'QUIT', 'TERM' ],
		}
	);
}

die "Connect to  $db failed \n" unless $dbh;

if ($rowCacheSize > 0) {
	print "setting RowCacheSize = $rowCacheSize\n";
	$dbh->{RowCacheSize} = $rowCacheSize;
} else {
print "NOT setting RowCacheSize\n";
}


$SIG{INT}=\&cleanup;
$SIG{QUIT}=\&cleanup;
$SIG{TERM}=\&cleanup;

my $sth;

# create table test_objects as select * from dba_objects
# if a SQL File was provided, get the SQL from there
#

dropTestTable($SQL{TABLE}) if $dropTestTable;

createTestTable($SQL{TABLE}, $SQL{CREATE}) if $createTestTable;

if ( $dropTestTable or $createTestTable ) {
	print "exiting after maintenance for table: $SQL{TABLE}\n";
	cleanup(0);
}

# set tracing on after internal work, such as the test_table drop/create
if ($traceLevel) {
	$dbh->do(qq{alter session set events '10046 trace name context forever, level $traceLevel'});
	if ($@) {
		warn "could not enable trace level: $traceLevel";
		warn "error: $@\n";
		cleanup(1);
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


=head1 RowCacheSize and PreFetching

 To enforce the number of rows prefetched by Oracle, more is needed than just setting the database handle attribute 'RowCacheSize'

 Typically, this is what is looks like to set RowCacheSize

	$dbh->{RowCacheSize} = $rowCacheSize;

 If you set this to 10, you may find that DBI has silently set this to 120. 

 The required value can be set by setting the amount of memory available to the fetch buffer.

 In the case of this script, the `uniform-row-size.conf` file is used to create a table where each row is 100 bytes.

 ./target.pl --create-test-table  --sqlfile uniform-row-size.conf  --username scott --password tiger --database ORCL

 The `uniform-row-size.conf` contains an attribute ROWLEN, which specifes the length of each row as 100 bytes.

 When --row-cache-size is used, the parameter passed to --row-cache-size is multiplied by ROWLEN to set the prefetch buffer size for the statement handle:

	$sth=$dbh->prepare($SQL{QUERY}, {ora_prefetch_memory=> $rowCacheSize * $SQL{ROWLEN}});

 This has resulted in requesting exactly the asked for rowCacheSize size.

 For testing, this is rather important, as you may be trying to find an ideal cache size for a query.

 The calculated value for ora_prefetch_memory can be overridden by using the --prefetch-memory argument

=cut


print "oraPreFetchMemory: $oraPreFetchMemory\n";

# not too sure this is necessary, at least not for uniform rows
#my $rowCacheFudge=1.05;
my $rowCacheFudge=1;

if ($rowCacheSize) {
	my $preFetchMem = $oraPreFetchMemory ? $oraPreFetchMemory : $rowCacheSize * $SQL{ROWLEN} * $rowCacheFudge;
	print "using ora_prefetch_memory $preFetchMem\n";
	$sth=$dbh->prepare($SQL{QUERY}, {ora_prefetch_memory=> $preFetchMem});
} else {
	$sth=$dbh->prepare($SQL{QUERY});
}

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
	print '.';
	usleep($uSleepSeconds);
}

print "\n";

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
  --create-test-table     creates the table 'TEST_OBJECTS' and exit
  --drop-test-table       drops the table 'TEST_OBJECTS' and exit
  --sqlfile          name of file that contains SQL to create the test table
                          if not provided, a default table is created

  --program-name          change the \$0 value to something else

  --row-cache-size        rows to fetch per call

  --prefetch-rows         rows to fetch per call - alernate method
                          you cannot use both of --row-cache-size and --prefetch-rows
  --prefetch-memory       amount of memory, in bytes, to support --prefetch-rows

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
	my ($exitCode,$sth) = @_;
	$exitCode = 0 unless $exitCode;
	if ($exitCode =~ /^?(INT|QUIT|TERM)$/ ) {
		$exitCode=1;
	}
	$sth->finish if $sth;
	$dbh->disconnect;
	exit $exitCode;
}

sub createTestTable {
	# check for table existance
	my ($tableName, $sql) =  @_;
	my $countSQL=q{select count(*) from user_tables where table_name = upper('} . $tableName . q{')};
	my $sth = $dbh->prepare($countSQL);
	$sth->execute;
	my ($tabCount) = $sth->fetchrow_array;
	$sth->finish;

	if ($tabCount) { 
		warn "Table $tableName already exists - exiting\n";
		cleanup(1);
	}

	$sth = $dbh->prepare($sql);
	$sth->execute;

	$sql = qq{select count(*) from $tableName};
	$sth = $dbh->prepare($sql);
	$sth->execute;
	($tabCount) = $sth->fetchrow_array;
	$sth->finish;

	print "$tabCount rows created in $tableName\n";

	return;

}

sub dropTestTable {
	my ($tableName) = @_;
	# check for table existance
	my $sql = q{select count(*) from user_tables where table_name = upper('} . $tableName . q{')};
	my $sth = $dbh->prepare($sql) or die "could not parse sql: $sql";
	$sth->execute;
	my ($tabCount) = $sth->fetchrow_array;
	$sth->finish;

	if (! $tabCount) { 
		warn "Table $tableName does not exist \n";
		return;
	}

	$sql = "drop table $tableName";
	$sth = $dbh->prepare($sql);
	$sth->execute;

	print "dropped $tableName\n";

	return;

}



