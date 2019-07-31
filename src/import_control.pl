#!/usr/bin/perl
#
# Filename   : import_control.pl
# Author     : Michele Jimenez, ENVIRON International Corp.
# Version    : Speciation Tool 4.5
# Description: Import run control
# Release    : 30 Sep 2017
#
# Imports the run control parameters to the table tbl_run_control in schema runname
#
#c Modified by:
#c       Uarporn Nopmongcol <unopmongcol@environcorp.com>  Sep, 2007  
#c
#c       MJimenez June 2011, to support addition of PM mechanism
#c       MJimenez March 2013, comment out the EMF calls for public release
#c       MJimenez Sep 2016, support VBS check
#
#  <SYSTEM DEPENDENT>  indicates where code may need to be changed to support
#                      specific installation requirements
#
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
#c Copyright (C) 2016  Ramboll Environ
#c Copyright (C) 2007  ENVIRON International Corporation
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
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

use warnings;
use strict;
use DBI;

## Get the directory for the speciation tool source code
my $srcDir = $ENV{"SPTOOL_SRC_HOME"};
unless ($srcDir) {
    die "SPTOOL_SRC_HOME environment variable (path to speciation tool source code) must be set"
}
## load EMF utilities
#emf# require "$srcDir/EMF_util.pl";

my ($dbname, $runname, $filename, $userName, $pwd);
my ($dbiPG);
my ($conn, $sql, $sth);
my ($line, @data);
my ($keyword, $datakey, $dataval, %keyword_list);
my ($output,$procfile, $toxfile, $hapsfile, $profile, $primaryfile);
my ($qa);

## if 3 arguments, use control file, 
## if 2 then get control from environment variables
my $use_env = "f";
if ($#ARGV == 1) {
    $use_env = "t";
}elsif ($#ARGV == 2) {
    ## get control file
    $filename = $ARGV[2];

}else {
    die "Usage: import_control.pl DBname runName [control_file]\n";
}

## get rest of arguments
$dbname = $ARGV[0];
$runname = $ARGV[1];


# initialize the acceptable keywords for the run control file =====================
$keyword_list{"MECH_BASIS"}     = 1;
$keyword_list{"RUN_TYPE"}       = 1;
$keyword_list{"AQM"}		= 1;
$keyword_list{"MECH_FILE"}      = 1;
$keyword_list{"TOX_FILE"}       = 1;
$keyword_list{"HAPS_FILE"}      = 1;
$keyword_list{"PRO_FILE"}       = 1;
$keyword_list{"PROC_FILE"}      = 1;
$keyword_list{"PRIMARY_FILE"}   = 1;
$keyword_list{"SPLITS_OUT"}     = 1;
$keyword_list{"CNV_OUT"}        = 1;
$keyword_list{"OUTPUT"}		= 1;
$keyword_list{"TOLERANCE"}	= 1;

# connect to database =========================================
# check if PostgreSQL dependent environment variables are set
#
if ( exists $ENV{"PERL_DBI"} ) {
        $dbiPG = $ENV{"PERL_DBI"}; }
else {
        printf "\nERROR: environment variable PERL_DBI is not set.\n";
        printf "       Edit and source Assigns.sptool file.\n\n";
        printf "ABORT: Control file $filename not imported.\n";
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
if ( $^O eq 'MSWin32' || $^O eq 'dos' )
{
        # -- PC users must change username to the local PostgreSQL installation --  <SYSTEM DEPENDENT>
        $conn = DBI->connect("dbi:$dbiPG:dbname=$dbname;host=localhost","$userName","$pwd") 
                or die "Database connection not made: $DBI::errstr\nVerify user name correctly set in Assigns file.";
}
else 
{
        # --- assume linux installation ---
        #emf# $conn = DBI->connect("DBI:$dbiPG:dbname=$dbname","emf","emf") 
        $conn = DBI->connect("DBI:$dbiPG:dbname=$dbname","$userName","$pwd") 
                or die "Database connection not made: $DBI::errstr\n";
}

print "Starting run_control file import\n";

# delete existing run control data
$sql = "DELETE FROM $runname.tbl_run_control";
$sth = $conn->prepare($sql) or die $conn->errstr;
$sth->execute();

# prepare the SQL statement to insert data
$sql = "INSERT INTO $runname.tbl_run_control (keyword, dataval)
                     VALUES (?, ?);";
$sth = $conn->prepare($sql) or die $conn->errstr;


# insert the run name into the run control file
$datakey  = "RUN_NAME";
$dataval  = trim($runname);
$sth->execute($datakey, $dataval) or die $conn->errstr;

## Get the keyword values from the environment variables
if ($use_env eq "t") {
    print "Getting control values from environmental variables\n";
    foreach my $env_var (keys %keyword_list){
	## get the env variable value based on the keywords
	## if empty, means not set
	my $env_val = $ENV{$env_var};
	if ($env_val) {
	    #emf# print_emf("control variables: $env_var = $env_val\n");
	    print("control variables: $env_var = $env_val\n");

	    $env_val  = trim($env_val);
	    ## insert the new data into the run control table
	    $sth->execute($env_var, $env_val) or die $conn->errstr;
		
	}
    }

} else {

## Or get from control file
    print "Getting control values from control file\n";
    # open control file
    open(CONTROLFILE, "$filename") or die "Can't open file: $filename\n";

    while (<CONTROLFILE>)
    {
	chomp;
	$line = trim($_);

	if (($line eq "") || (substr($line, 0, 1) eq "#"))
	{
	    next;
	}

	@data = split ",";

	$keyword = uc trim($data[0]);
	if ($keyword_list{$keyword} == 1) 
	{
	    $dataval  = trim($data[1]);

	    #emf# print_emf("control variables: $keyword = $dataval\n");
	    print("control variables: $keyword = $dataval\n");
	    ## insert the new data
	    $sth->execute($keyword, $dataval) or die $conn->errstr;

       }
    }

    ## close the file
    close CONTROLFILE;
}

# QA if controls contains valid information  --------
#  ---  get the AQM name for the run
   $sql = "SELECT dataval \
                  FROM $runname.tbl_run_control
                  WHERE keyword = 'AQM'";
   $sth = $conn ->prepare($sql);
   $sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
   while (@data = $sth->fetchrow_array())
   {
     $qa = $data[0];
   }
   if ($qa eq "") { $conn->disconnect(); print "ERROR: AQM is not set\n"; exit 10 }

#  ---  get the Output Type for the run
   $output = "";
   $sql = "SELECT dataval \
                  FROM $runname.tbl_run_control
                  WHERE keyword = 'OUTPUT'";
   $sth = $conn ->prepare($sql);
   $sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
   while (@data = $sth->fetchrow_array())
   {
     $output = $data[0];
   }

   if ($output eq "VOC" || $output eq "")
   {
	## check mechanism
   	$sql = "SELECT dataval FROM $runname.tbl_run_control WHERE keyword = 'MECH_BASIS'";
   	$sth = $conn ->prepare($sql);
   	$sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
	$qa = "";
   	while (@data = $sth->fetchrow_array()) { $qa = $data[0]; }
   	if ($qa eq "") 
	{ $conn->disconnect(); print "ERROR: MECHANISM is not set\n"; exit 10 }

	## check run_type
   	$sql = "SELECT dataval FROM $runname.tbl_run_control WHERE keyword = 'RUN_TYPE'";
   	$sth = $conn ->prepare($sql);
   	$sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
	$qa = "";
   	while (@data = $sth->fetchrow_array()) { $qa = $data[0]; }

   	if ($qa eq "") 
	{ $conn->disconnect(); print "ERROR: Run type is not set 'CRITERIA/VBS/INTEGRATE/NONINTEGRATE/HAPLIST'\n"; exit 10 }
    }
   if ($output eq "PM")
   {
	## check mechanism
   	$sql = "SELECT dataval FROM $runname.tbl_run_control WHERE keyword = 'MECH_BASIS'";
   	$sth = $conn ->prepare($sql);
   	$sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
	$qa = "";
   	while (@data = $sth->fetchrow_array()) { $qa = $data[0]; }

   	if ($qa eq "") 
	{ $conn->disconnect(); print "ERROR: MECHANISM is not set\n"; exit 10 }

    }

# now import the toxic species, haps species lists, and user specified prfile weights  --------
#  ---  get the input file names for the run
   $toxfile = "";
   $sql = "SELECT dataval \
                  FROM $runname.tbl_run_control
                  WHERE keyword = 'TOX_FILE'";
   $sth = $conn ->prepare($sql);
   $sth->execute() or die "Error retrieving control information: " . $sth->errstr;

   while (@data = $sth->fetchrow_array())
   {
	$toxfile     = $data[0];
   }

   if ( $toxfile ne "" )
   {
	# delete existing toxics
	$sql = "DELETE FROM $runname.tbl_toxics";
	$sth = $conn->prepare($sql) or die $conn->errstr;
	$sth->execute() or die $conn->errstr;
	# prepare the SQL statement to insert data
	$sql = "INSERT INTO $runname.tbl_toxics (aqm_model, specie_id, aqm_poll )
                     VALUES (?, ?, ?);";
	$sth = $conn->prepare($sql) or die $conn->errstr;

	# open toxics file
	open(TOXFILE, "$toxfile") or die "Can't open file: $toxfile\n";

	while (<TOXFILE>)
	{
	    chomp;
	    $line = trim($_);

	    @data = split ",";
            
            ## remove double quotes
            s/\"//g for (@data);


	    $sth->execute(@data) or die $conn->errstr;
	}
#	close the file
	close TOXFILE;
	#emf# print_emf("Completed importing toxics file ", $toxfile);
	print("Completed importing toxics file $toxfile\n");
   }


# now import the process file for mode specific profiles such as mobile  --------
#  ---  get the input file names for the run
   $procfile = "";
   $sql = "SELECT dataval \
                  FROM $runname.tbl_run_control
                  WHERE keyword = 'PROC_FILE'";
   $sth = $conn ->prepare($sql);
   $sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
   while (@data = $sth->fetchrow_array())
   {
	$procfile     = $data[0];
   }
   
   if ( $procfile ne "" )
   {
	# delete existing process 
	$sql = "DELETE FROM $runname.tbl_gas_process";
	$sth = $conn->prepare($sql) or die $conn->errstr;
	$sth->execute() or die $conn->errstr;
	# prepare the SQL statement to insert data
	$sql = "INSERT INTO $runname.tbl_gas_process (profile_id, process)
                     VALUES (?, ?);";
	$sth = $conn->prepare($sql) or die $conn->errstr;

	# open process file
	open(PROCFILE, "$procfile") or die "Can't open file: $procfile\n";

	while (<PROCFILE>)
	{
	    chomp;
	    $line = trim($_);

	    @data = split ",";

            ## remove double quotes
            s/\"//g for (@data);

	    $sth->execute(@data) or die $conn->errstr;
	}
#	close the file
	close PROCFILE;
	#emf# print_emf("Completed importing process file ", $procfile);
	print("Completed importing process file $procfile\n");
   }


# now import the primary toxic file for _primary and one-to-many toxic mapping  --------
#  ---  get the input file names for the run
   $primaryfile = "";
   $sql = "SELECT dataval \
                  FROM $runname.tbl_run_control
                  WHERE keyword = 'PRIMARY_FILE'";
   $sth = $conn ->prepare($sql);
   $sth->execute() or die "Error retrieving control information: " . $sth->errstr;
   
   while (@data = $sth->fetchrow_array())
   {
	$primaryfile     = $data[0];
   }
   if ( $primaryfile ne "" )
   {
	# delete existing process 
	$sql = "DELETE FROM $runname.tbl_primary";
	$sth = $conn->prepare($sql) or die $conn->errstr;
	$sth->execute() or die $conn->errstr;
	# prepare the SQL statement to insert data
	$sql = "INSERT INTO $runname.tbl_primary (aqminv_poll, aqm_add, split_factor, writeflag)
                     VALUES (?, ?, ?, ?);";
	$sth = $conn->prepare($sql) or die $conn->errstr;

	# open primary toxic file
	open(PRIMFILE, "$primaryfile") or die "Can't open file: $primaryfile\n";

	while (<PRIMFILE>)
	{
	    chomp;
	    $line = trim($_);

	    @data = split ",";

            ## remove double quotes
            s/\"//g for (@data);

	    $sth->execute(@data) or die $conn->errstr;
	}
#	close the file
	close PRIMFILE;
	#emf# print_emf("Completed importing primary toxic file ", $primaryfile);
	print("Completed importing primary toxic file $primaryfile\n");
   }


# now import the user profile weights --------
#  ---  get the input file names for the run
   $profile = "";
   $sql = "SELECT dataval \
                  FROM $runname.tbl_run_control
                  WHERE keyword = 'PRO_FILE'";
   $sth = $conn ->prepare($sql);
   $sth->execute() or die "Error retrieving control information: " . $sth->errstr;

   while (@data = $sth->fetchrow_array())
   {
	$profile     = $data[0];
   }

   if ( $profile ne "" )
   {
	# delete existing user specified profile weights
	$sql = "DELETE FROM $runname.tbl_user_profile_wts";
	$sth = $conn->prepare($sql) or die $conn->errstr;
	$sth->execute() or die $conn->errstr;

	# prepare the SQL statement to insert data
	$sql = "INSERT INTO $runname.tbl_user_profile_wts (profile_id, specie_id, percent )
                     VALUES (?, ?, ? );";
	$sth = $conn->prepare($sql) or die $conn->errstr;

	# open profile weights file
	open(PROFILE, "$profile") or die "Can't open file: $profile\n";

	while (<PROFILE>)
	{
	    chomp;
	    $line = trim($_);

	    @data = split ",";

            ## remove double quotes
            s/\"//g for (@data);

	    $sth->execute(@data) or die $conn->errstr;

	}
#	close the file
	close PROFILE;
	#emf# print_emf("Completed importing User Profile Weights file ", $profile);
	print("Completed importing User Profile Weights file $profile\n");
   }

print "Completed run_control file import\n\n";

$conn->disconnect();

sub trim
{
    my $s = shift;
# remove leading spaces
    $s =~ s/^\s+//;
# remove trailing spaces
    $s =~ s/\s+$//;
# remove leading tabs
    $s =~ s/^\t+//;
# remove trailing tabs
    $s =~ s/\t+$//;
    return $s;
}

