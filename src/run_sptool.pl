#!/proj/ie/proj/EMAQ/Platform/SpeciationTool/v4.0/perl-5.24.0/bin
#
# Filename   : run_sptool.pl
# Author     : Michele Jimenez, ENVIRON International Corp. 
# Version    : Speciation Tool 4.0
# Description: Main control script to run Speciation Tool
# Release    : 12 Sep 2016
#
#  This is the controlling perl script that executes the
#  Speciation Tool modules
#
#  Use:    perl run_sptool.pl sptool_db_name run_name control_file
#
#  the database must previously have been initialized and loaded
#  with the raw data for profiles, profile weights, species, 
#  carbons, and mechanisms
#
#  edited 8/25/08 by M Houyoux to correct ERROR message spelling of "prepare"
#  edited 10/29/08 by A Zubrow to send EMF messages and use environment variables
# MJimenez June 2011, to support addition of PM mechanism
#          Mar  2013, to support public release; remove EMF references
# MJimenez Sep  2016, include buffer dump of process message before SQL subroutine call
#
#  <SYSTEM DEPENDENT>  indicates where code needs to be changed to support
#                      specific installation requirements
#
#====================================================================================
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
#c Copyright (C) 2016  Ramboll Environ
#c Copyright (C) 2006  ENVIRON International Corporation
#c
#c Developed by:  
#c
#c       Michele Jimenez   <mjimenez@environcorp.com>    415.899.0700
#c
#c This program is free software; you can redistribute it and/or
#c modify it under the terms of the GNU General Public License
#c as published by the Free Software Foundation; either version 2
#c of the License, or (at your option) any later version.
#c
#c This program is distributed in the hope that it will be useful,
#c but WITHOUT ANY WARRANTY; without even the implied warranty of
#c MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#c GNU General Public License for more details.
#c
#c To obtain a copy of the GNU General Public License
#c write to the Free Software Foundation, Inc.,
#c 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

use warnings;
use strict;
use DBI;

# -- user specified run parameters ---
my ( $dbName, $runName, $ctlFile);
my ( $runout, $retField);

# -- database connection variables ---
my ($userName, $pwd);
my ($dbiPG);
my ($conn, $sql, $sth, $sth2, @data);
my ( $cmdline ,$impStr);
my ($numerrors,$chkerrcode,$prof_cnt);

# -- Get the directory for the speciation tool source code
my $srcDir = $ENV{"SPTOOL_SRC_HOME"};
unless ($srcDir) {
    die "\nError: Undefined SPTOOL_SRC_HOME environment variable (Speciation Tool source code path) is required."
}

my $perlDir = $ENV{"PERLBIN"};
# -- load EMF utilities
#emf#	require "$srcDir/EMF_util.pl";

# -- print/send message that running
print "Running run_sptool.pl\n";
#emf#	print_emf("Running run_sptool.pl");

## if 3 arguments, use control file, 
## if 2 arguments then get control from environmental variables
my $use_env = "f";
if ($#ARGV == 1) {
    $use_env = "t";
    print "No run control file provided - using environment variables.\n";
}elsif ($#ARGV == 2) {
    ## get control file
    $ctlFile = $ARGV[2];
}else {
    die "\nError: Usage- run_sptool.pl DBname runname [control_file]\n";
    #emf#	die_emf("Usage: run_sptool.pl DBname runname [control_file]\n");
}

$dbName = $ARGV[0];
$runName = $ARGV[1];


#======================================================================================
# --- connect to database --- 
# check if PostgreSQL dependent environment variables are set
#
if ( exists $ENV{"PERL_DBI"} ) {
        $dbiPG = $ENV{"PERL_DBI"}; }
else {
        printf "\nERROR: environment variable PERL_DBI is not set.\n";
        printf "       Edit and source Assigns.sptool file.\n\n";
        printf "ABORT: Speciation Tool aborted with errors.\n";
        exit(1);
}
if ( exists $ENV{"SPTOOL_USER"} ) {
        $userName = $ENV{"SPTOOL_USER"}; }
else {
        $userName="";
}
if ( exists $ENV{"SPTOOL_PWD"} ) {
        $pwd= $ENV{"SPTOOL_PWD"}; }
else {
        $pwd="";
}

# --- check operating system ---
# << SYSTEM DEPENDENT >> ====================
#
if ( $^O eq 'MSWin32' || $^O eq 'dos' )
{
        # -- PC users must change username to the local PostgreSQL installation --  <SYSTEM DEPENDENT>
        $conn = DBI->connect("dbi:$dbiPG:dbname=$dbName;host=localhost","$userName","$pwd") 
                or die "Database connection not made: $DBI::errstr\nVerify user name correctly set in import_rawdata.pl";
                #emf# or die_emf("Database connection not made: $DBI::errstr\nVerify user name correctly set in import_rawdata.pl");
}
else 
{
        # --- assume linux installation ---
        $conn = DBI->connect("DBI:$dbiPG:dbname=$dbName","$userName","$pwd") 
                or die "\nError: Database connection not made: $DBI::errstr\nHas the database been initialized?";
        #emf#	$conn = DBI->connect("DBI:Pg:dbname=$dbName","emf","emf") 
        #emf#	        or die_emf("Database connection not made: $DBI::errstr\nHas the database been initialized?");
}

# -- Error reporting through DBI
$conn->{PrintError} = 1; # enable

# --- check that schema exists before drop, then create and grant permissions ---
$sql = "SELECT * from pg_namespace WHERE nspname = ?";
$sth = $conn->prepare($sql) or die $conn->errstr;
#emf#	$sth = $conn->prepare($sql) or die_emf($conn->errstr);
$sth->execute($runName) or die $conn->errstr;
#emf#	$sth->execute($runName) or die_emf($conn->errstr);
if (@data = $sth->fetchrow_array())
{
        print "Dropping $runName schema\n";
        #emf#	print_emf("Dropping $runName schema\n");
	$sql = "DROP SCHEMA $runName CASCADE";
	$sth2 = $conn->prepare($sql);
	$sth2->execute() or  die "ERROR executing DROP SCHEMA: ",$sth2->errstr;
	#emf#	$sth2->execute() or  die_emf( "ERROR executing DROP SCHEMA: ",$sth2->errstr);
	$sth2->finish;
}

$sth->finish;
$sql = "CREATE SCHEMA $runName";
$sth = $conn->prepare($sql);
$sth->execute() or die "ERROR executing CREATE SCHEMA: " ,$sth->errstr;
#emf#	$sth->execute() or die_emf( "ERROR executing CREATE SCHEMA: " ,$sth->errstr);
$sth->finish;
print "\n\nCreated $runName schema in $dbName database\n";
#emf#	print_emf("\n\nCreated $runName schema in $dbName database\n");


$sql = "GRANT ALL ON SCHEMA $runName TO PUBLIC";
$sth = $conn->prepare($sql);
$sth->execute() or die "ERROR executing GRANT PERMISSIONS ON SCHEMA: ", $sth->errstr;
#emf#	$sth->execute() or die_emf( "ERROR executing GRANT PERMISSIONS ON SCHEMA: ", $sth->errstr);
$sth->finish;
print "Granted permissions on $runName schema\n";

#======================================================================================
#  --- define tables and import the user specified run control file and data ---
$sql = "SET SEARCH_PATH=${runName}, shared";
$sth = $conn->prepare($sql);
$sth->execute() or die "ERROR setting search path: " ,$sth->errstr;
#emf#	$sth->execute() or die_emf( "ERROR setting search path: " ,$sth->errstr);
$sth->finish;
print "Set path successfully to $runName schema\n";

$sql = "SELECT inputs_createtables()";
$sth = $conn->prepare($sql);
$sth->execute() or die "ERROR creating input tables: ", $sth->errstr;
#emf#	$sth->execute() or die_emf( "ERROR creating input tables: ", $sth->errstr);
$sth->finish;
print "Input tables created in $runName schema\n";
#emf#	print_emf("Input tables created in $runName schema\n");
if ($use_env eq "t") {
    ## getting controls from environmental variables
    $impStr = "${perlDir}/perl -w ${srcDir}/import_control.pl $dbName $runName";
    $chkerrcode = system($impStr);
    if ($chkerrcode != 0) { die "STOP: error occured while reading the control variables";}
    #emf#	if ($chkerrcode != 0) { die_emf("STOP: error occured while reading the control variables");}
    print "Imported run control variables in $runName schema\n";
    #emf#	print_emf("Imported run control variables in $runName schema\n");
}
else {
# --- check that the user specified control file exists ---
    open(CONTROLFILE, "$ctlFile") or die "ERROR User specified control file not found: $ctlFile\n";
    #emf#	open(CONTROLFILE, "$ctlFile") or die_emf( "ERROR User specified control file not found: $ctlFile\n");
    close(CONTROLFILE);

    $impStr = "${perlDir}/perl -w ${srcDir}/import_control.pl $dbName $runName $ctlFile";
    $chkerrcode = system($impStr);
    if ($chkerrcode != 0) { die "STOP: error occured while reading the control file";}
    my $oldfh = select(STDOUT); $| = 1; select($oldfh);
    print "Imported run control file $ctlFile in $runName schema\n";
    #emf#	if ($chkerrcode != 0) { die_emf("STOP: error occured while reading the control file");}
    #emf#	print_emf("Imported run control file $ctlFile in $runName schema\n");
}

#======================================================================================

#============== generate process VOCs
$sql = "SELECT MakeSplits()";
$sth = $conn->prepare($sql);
$sth->execute() or die "ERROR generating split factors: ", $sth->errstr;
#emf#	$sth->execute() or die_emf( "ERROR generating split factors: ", $sth->errstr);
$sth->finish;

#  --- Check output type  ---
$runout = "";       # default if not returned
$retField = "OUTPUT";
$sql = "SELECT dataval \
        FROM tbl_run_control 
        WHERE tbl_run_control.keyword = ?";
$sth = $conn->prepare($sql);
$sth->execute($retField) or die ( "ERROR checking input errors: ", $sth->errstr);
#emf#	$sth->execute($retField) or die_emf( "ERROR checking input errors: ", $sth->errstr);
if (@data = $sth->fetchrow_array()) 
{
	$runout = $data[0];
}

#============== QA some VOC tables ---
if ( $runout eq "" || $runout eq "VOC")
{
#  -- check if encountered errors on toxic file --
$sql = "SELECT * FROM tmp_error";
$sth = $conn->prepare($sql);
$sth->execute() or die ("ERROR : ", $sth->errstr);
#emf#	$sth->execute() or die_emf("ERROR : ", $sth->errstr);
if ($sth->rows > 0) 
{
    die ("Error found in toxic table - please make corrections\n");
    #emf#	die_emf("Error found in toxic table - please make corrections\n");
}

#  -- check if encountered errors on inputs ---
$sql = "SELECT * FROM tmp_spcinp";
$sth = $conn->prepare($sql);
$sth->execute() or die ("ERROR checking input errors: ", $sth->errstr);
#emf#	$sth->execute() or die_emf("ERROR checking input errors: ", $sth->errstr);
if ($sth->rows > 0) 
{
    die ("Errors were reported in the inputs (see tmp_spcinp) - please make corrections\n");
    #emf#	die_emf("Errors were reported in the inputs (see tmp_spcinp) - please make corrections\n");
}

$sql = "SELECT * FROM tmp_qa_carbons";
$sth = $conn->prepare($sql);
$sth->execute() or die ("ERROR checking input errors: ", $sth->errstr);
#emf#	$sth->execute() or die_emf("ERROR checking input errors: ", $sth->errstr);
if ($sth->rows > 0) 
{
    die ( "Errors were reported in the inputs (see tmp_qa_carbons) - please make corrections\n");
    #emf#	die_emf( "Errors were reported in the inputs (see tmp_qa_carbons) - please make corrections\n");
}
$sth->finish;
print ("Completed splits calculations\n\n");
#emf#	print_emf("Completed splits calculations\n");
#
}

#============== process PMs 
#
$sql = "SELECT MakePMSplits()";
$sth = $conn->prepare($sql);
$sth->execute() or die ( "ERROR generating split factors: " , $sth->errstr);
#emf#	$sth->execute() or die_emf( "ERROR generating split factors: " , $sth->errstr);
$sth->finish;

#============== QA some PM tables --- 

if ( $runout eq "PM")
{
#  -- check if encountered errors --
$retField = "ERROR";
$sql = "SELECT * FROM tmp_error WHERE error = ?"; 
$sth = $conn->prepare($sql);
$sth->execute($retField) or die("ERROR checking PM errors: ", $sth->errstr);
#emf#	$sth->execute($retField) or die_emf("ERROR checking PM errors: ", $sth->errstr);
if ($sth->rows > 0)  
{
    die("Error found in PM processing - review log file for keyword ERROR \n\n");
    #emf#	die_emf("Error found in PM processing - review log file for keyword ERROR \n\n");
    exit 1;
}

#  -- check if encountered warnings --
$retField = "warning";
$sql = "SELECT * FROM tmp_error WHERE error = ?"; 
$sth = $conn->prepare($sql);
$sth->execute($retField) or die("ERROR checking PM errors: ", $sth->errstr);
#emf#	$sth->execute($retField) or die_emf("ERROR checking PM errors: ", $sth->errstr);
if ($sth->rows > 0)  
{
    die("Warning found in PM processing - review log file for keyword WARNING \n");
    #emf#	die_emf("Warning found in PM processing - review log file for keyword WARNING \n");
}
$sth->finish;
print("\nCompleted PM splits calculations\n\n");
#emf#	print_emf("\nCompleted PM splits calculations\n");
}

#============== Prepare and write output files --- 

$sql = "SELECT gspro_createtemptables()";
$sth = $conn->prepare($sql);
$sth->execute() or die("ERROR preparing temp tables: ", $sth->errstr);
#emf#	$sth->execute() or die_emf("ERROR preparing temp tables: ", $sth->errstr);

$sql = "SELECT PrepOut()";
$sth = $conn->prepare($sql);
$sth->execute() or die("ERROR preparing output tables: ", $sth->errstr);
#emf#	$sth->execute() or die_emf("ERROR preparing output tables: ", $sth->errstr);
$sth->finish;

print("\nCompleted output preparations\n");
#emf#	print_emf("Completed output preparations\n");

$sql = "SELECT COUNT(DISTINCT profile_id) FROM tmp_gspro";
$sth = $conn->prepare($sql);
$sth->execute() or die("ERROR retrieving profile summary: ", $sth->errstr);
#emf#	$sth->execute() or die_emf("ERROR retrieving profile summary: ", $sth->errstr);
if (@data = $sth->fetchrow_array())
{
        $prof_cnt = $data[0];
        print("SUMMARY:  Number of profiles generated in run $runName is $prof_cnt \n\n");
        #emf#	print_emf("SUMMARY:  Number of profiles generated in run $runName is $prof_cnt \n\n");
}
$sth->finish;

#  --- write the output files ---

$impStr = "${perlDir}/perl -w ${srcDir}/write_outputs.pl $dbName $runName";
system ($impStr);
print( "Completed writing the output files for run $runName \n");
#emf#	print_emf( "Completed writing the output files for run $runName \n");

$conn->disconnect();


#======================================================================================
## send message that completed
print("Finished run_sptool.pl\n\n");
#emf#	print_emf("Finished run_sptool.pl");
    
exit;

