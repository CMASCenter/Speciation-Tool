#!/usr/bin/perl -w
#
# Filename   : write_outputs.pl
# Author     : Michele Jimenez, ENVIRON International Corp.
# Version    : Speciation Tool 4.5
# Description: Write GSPRO and GSCNV output files
# Release    : 30Sep2017
#
# Outputs the SMOKE GSPRO and GSCNV files
#
#  Modified :  Sep 2007
#              Generalize to either read output file name from database or
#              generate the output file names from the run scenario metadata
#
#              MJimenez June 2011, to support addition of PM mechanism
#                       March 2013, to comment out EMF calls
#                       Sept 2016, added metadata to CNV output file
#                                  added AQM to default PM output file name
#
#  <SYSTEM DEPENDENT>  indicates where code may need to be changed to support
#                      specific installation requirements
#
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
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

use warnings;
use strict;
use DBI;
use FileHandle;

## Get the directory for the speciation tool source code
my $srcDir = $ENV{"SPTOOL_SRC_HOME"};
unless ($srcDir) {
    die "SPTOOL_SRC_HOME environmental variable (path to speciation tool source code) must be set"
}
## load EMF utilities
#emf# require "$srcDir/EMF_util.pl";

#my ($args);
#$args = `echo 'date +%d%b%Y' | awk '{print $1}'`;
#system($args);

# input variables
my ($dbname, $scenario);

# database connection variables
my ($dbiPG);
my ($userName, $pwd);
my ($conn, $sql, $sth, @data);

# run control variables
my ($outGSpro, $outGScnv, $outvoc);
my ( $retField );
# table fields
my ($profileId, $eminvPoll, $aqmPoll, $splitFactor, $divisor, $massFraction );
my ($fromSpecie, $toSpecie, $cnvFactor, $process);
my ($toxPoll);
my ($keyword, $dataval, $version);
my ($tmpInteger);
my ($runout, $runtype,$runpmtype,$runmech,$runaqm,$runDate,$outExt);
my ($lDate,$wday,$mon,$mday,$time,$year);
my ($SpecieID,$SpecieName,$VOCbin);

($#ARGV == 1) or die "Usage: write_outputs.pl project scenario \n";

$dbname = $ARGV[0];
$scenario = $ARGV[1];

# connect to database =========================================
# check if PostgreSQL dependent environment variables are set
#
if ( exists $ENV{"PERL_DBI"} ) {
        $dbiPG = $ENV{"PERL_DBI"}; }
else {
        printf "\nERROR: environment variable PERL_DBI is not set.\n";
        printf "       Edit and source Assigns.sptool file.\n\n";
        printf "ABORT: Outputs not generated.\n";
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
                or die "Database connection not made: $DBI::errstr\nVerify user name correctly set in import_ra
wdata.pl";
}
else 
{
        # --- assume linux installation ---
        #emf# $conn = DBI->connect("DBI:$dbiPG:dbname=$dbname","emf","emf") 
        $conn = DBI->connect("DBI:$dbiPG:dbname=$dbname","$userName","$pwd") 
                or die "Database connection not made: $DBI::errstr\n";
}

#  --- Check output type  ---
$runout = "";       # default if not returned
$retField = "OUTPUT";
$sql = "SELECT dataval \
        FROM $scenario.tbl_run_control \
        WHERE keyword = ?";
$sth = $conn->prepare($sql);
$sth->execute($retField) or die "ERROR checking input errors: " . $sth->errstr;
if (@data = $sth->fetchrow_array())
{
        $runout = $data[0];
}

# --- insert metadata header
$sql = "SELECT * FROM $scenario.tmp_metadataset ORDER BY keyword";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
	++$tmpInteger;
	$keyword    = $data[0];
	$dataval    = $data[1];

        if ( $keyword eq "RUN_TYPE" ) { $runtype = $dataval; }
        if ( $keyword eq "MECH" )     { $runmech = $dataval; }
        if ( $keyword eq "AQM" )      { $runaqm  = $dataval; }
}	

$lDate=scalar(localtime);
($wday,$mon,$mday,$time,$year) = split(/\s+/,$lDate);
#$runDate=sprintf("%s%s%s",$mday,$mon,$year);
$runDate=sprintf("%s%s%s",$year,$mon,$mday);

if ( $runout eq "PM" )
   { $outExt = "PM_${runmech}_${runtype}_${runaqm}_$runDate"; }
elsif ( $runout eq "STATIC" )
   { $outExt = "STATIC_${runmech}_${runaqm}_$runDate"; }
else
   { $outExt = "${runmech}_${runtype}_${runaqm}_$runDate"; }

# ---  retrieve output filenames from run_control table ---
$retField = "SPLITS_OUT";
$sql = "SELECT dataval \
          FROM $scenario.tbl_run_control \
          WHERE keyword = ?";
$sth = $conn->prepare($sql);
$sth->execute($retField) or die "Error executing query: " . $sth->errstr;
if (@data = $sth->fetchrow_array())
{
    $outGSpro = $data[0];
}
else
{
#	die "Error - no SPLITS output file specified in run control table";
    $outGSpro = "../outputs/gspro_${outExt}";
}
$sth->finish;

# --- open splits output file ---
open(SPLFILE, ">$outGSpro") or die "Unable to open GSPRO output file for writing: $outGSpro\n";  # Added more specificifity in error
$tmpInteger = 0;

# --- insert metadata header
$sql = "SELECT * FROM $scenario.tmp_metadataset ORDER BY keyword";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
	++$tmpInteger;
	$keyword    = $data[0];
	$dataval    = $data[1];
	$version    = $data[2];
	
        ## sometime the version is missing, so set to ""
	unless ($version) { $version = "";}

	printf SPLFILE "%-20s %s %s\n", "#SPTOOL_$keyword", $dataval, $version; 
}

# --- prepare the header
if ( $runtype eq "INTEGRATE" )
{
$sql = "SELECT  aqminv_poll \
              FROM  $scenario.tmp_header \
              ORDER BY aqminv_poll";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
	++$tmpInteger;
	$toxPoll    = $data[0];
	printf SPLFILE "%-15s %-20s\n", "#NHAP NONHAPTOG", $toxPoll; 
}
}

# --- prepare the retrieval of the splits data ---
$sql = "SELECT  profile_id, eminv_poll, aqm_poll, split_factor, divisor, mass_fraction \
              FROM  $scenario.tmp_gspro \
              ORDER BY profile_id, eminv_poll, aqm_poll";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
	++$tmpInteger;
	$profileId    = $data[0];
	$eminvPoll    = $data[1];
	$aqmPoll      = $data[2];
	$splitFactor  = $data[3];
	$divisor      = $data[4];
	$massFraction = $data[5];

	## sometime the profileID is missing, so set to ""
	unless ($profileId) { $profileId = "";}


	## depending on size of split factor, potentially use scientific notation
 	if ( $splitFactor >= 0.0099 )
	{
		printf SPLFILE "%-20s %-20s %-10s %12.4f %12.4f %12.4f\n", 
			$profileId, $eminvPoll, $aqmPoll, $splitFactor, $divisor, $massFraction;
	}
	elsif ( $splitFactor < 0.0099 && $splitFactor >= 0.00000001 )
	{

 		printf SPLFILE "%-20s %-20s %-10s %.4e %12.4f %.4e\n", 
			$profileId, $eminvPoll, $aqmPoll, $splitFactor, $divisor, $massFraction;
	}
	else
	{
		printf SPLFILE "%-20s %-20s %-10s %.4e %12.4f %.4e\n", 
			$profileId, $eminvPoll, $aqmPoll, $splitFactor, $divisor, $massFraction;
	}
}

if ($tmpInteger == 0)
{
	die "Error - no data in splits factor table";
}
$sth->finish;
close(SPLFILE);

## Register output GSPRO file w/ EMF
#emf# output_emf($outGSpro,"Chemical Speciation Profiles (GSPRO)");

if ( $runout eq "" || $runout eq "VOC" && $runtype ne "HAPLIST" )
{
$retField = "CNV_OUT";
$sql = "SELECT dataval \
          FROM $scenario.tbl_run_control \
          WHERE keyword = ?";
$sth = $conn->prepare($sql);
$sth->execute($retField) or die "Error executing query: " . $sth->errstr;
if (@data = $sth->fetchrow_array())
{
    $outGScnv = $data[0];
}
else
{
#	die "Error - no CNV output file specified in run control table";
    $outGScnv = "../outputs/gscnv_${outExt}";
    print($outGScnv)
}
$sth->finish;

# --- open conversion factors output file ---
open(CNVFILE, ">$outGScnv") or die "Unable to open GSCNV output file for writing: $outGScnv\n";  # Added more specificity in error
$tmpInteger = 0;

# --- insert metadata header
$sql = "SELECT * FROM $scenario.tmp_metadataset ORDER BY keyword";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
	$keyword    = $data[0];
	$dataval    = $data[1];
	$version    = $data[2];
	
        ## sometime the version is missing, so set to ""
	unless ($version) { $version = "";}

	printf CNVFILE "%-20s %s %s\n", "#SPTOOL_$keyword", $dataval, $version; 
}

# --- prepare the retrieval of the conversion factor data ---
$sql = "SELECT  from_specie, to_specie, profile_id, cnv_factor \
              FROM  $scenario.tmp_gscnv";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
	++$tmpInteger;
	$fromSpecie = $data[0];
	$toSpecie   = $data[1];
	$profileId  = $data[2];
	$cnvFactor  = $data[3];

	printf CNVFILE "%-20s %-20s %-20s %12.8f \n", 
		$fromSpecie, $toSpecie, $profileId, $cnvFactor;  
}
if ($tmpInteger == 0)
{
	die "Error - no data in conversion factor table";
}
$sth->finish;

close(CNVFILE);

## Register output GSCNV file w/ EMF
#emf# output_emf($outGScnv,"Pollutant to Pollutant Conversion (GSCNV)");

}

if ( $runout eq "" || $runout eq "VOC" && $runtype ne "HAPLIST" )
{
$outvoc = "../outputs/SPECIATE5_VP.IVOCP6-SVOCN1.$runDate.txt";
open(VOCFILE, ">$outvoc") or die "Unable to open SPECIATE VP output file for writing: $outvoc\n";
$tmpInteger = 0;
$sql = "SELECT * FROM  $scenario.tmp_species_vp";
$sth = $conn->prepare($sql);
$sth->execute() or die "Error executing query: " . $sth->errstr;
while (@data = $sth->fetchrow_array())
{
        ++$tmpInteger;
        $SpecieID = $data[0];
        $SpecieName   = $data[1];
        $VOCbin   = $data[2];

        printf VOCFILE "%i	%s	%s\n",
                $SpecieID, $SpecieName, $VOCbin;
}
if ($tmpInteger == 0)
{
        die "Error - no data in SPECIATE VOC table";
}
$sth->finish;

close(VOCFILE);

}

$conn->disconnect();

