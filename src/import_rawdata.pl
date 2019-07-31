#!/usr/bin/perl
#
# Filename   : import_rawdata.pl
# Author     : Michele Jimenez, ENVIRON International Corp.
# Version    : Speciation Tool 4.5
# Description: Import shared data files
# Release    : 30 Sep 2017
#
# Speciation Tool - a tool generating split factors by profile code for AQM.
#	This module imports data into the shared schema.
#
#c Modified by:
#c 	Uarporn Nopmongcol <unopmongcol@environcorp.com> Sep, 2007
#c	  - enhanced to read invtable
#
#c       MJimenez June 2011, to support addition of PM mechanism
#c       MJimenez July 2016, to support CAMx FCRS compound
#c       MJimenez Sep 2016, to support VBS processing; additional input files
#c				vbs_svoc_factors
#c				vbs_ivoc_nmogfactors
#c				ivoc_species
#c       MJimenez Sep 2018, to make PM2.5 profiles AE6-ready
#c
#  <SYSTEM DEPENDENT>  indicates where code may need to be changed to support
#                      specific installation requirements
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
#
# This program imports the raw csv data files required for populating the db.
# Possible choices are:
#      mechanism
#      mechanismPM
#      mechanism_description	
#      species
#      gas_profiles
#      gas_profile_weights
#      pm_profiles
#      pm_profile_weights
#      rename_species  
#      invtable
#      carbons
#      static
#      camx_fcrs
#      vbs_svoc_factors
#      vbs_ivoc_nmogfactors
#      ivoc_species
#      zero_ph2o
#      pncom_facs
#      o2m_ratios
#  ====================================================================================

use warnings;
use strict;
use DBI;
require Text::CSV;
my $csv = Text::CSV->new;

my $usage = "Usage: import_rawdata.pl database table inputfile\n";

($#ARGV == 2) or die $usage;

my ($dbname, $tablename, $filename, $file, $userName, $pwd);
my ($dbiPG);
my ($conn, $sql, $sth);
my ($err, $i, $useTransactions);
my (@data, $counter, $nlines, $template);
my ($start);

$dbname = $ARGV[0];
$tablename = $ARGV[1];
$filename = $ARGV[2];
$useTransactions = "Y";

# -- check environment variables and connect to database
#
if ( exists $ENV{"PERL_DBI"} ) {
        $dbiPG = $ENV{"PERL_DBI"}; }
else {
	printf "\nERROR: environment variable PERL_DBI is not set.\n";
	printf "       Edit and source Assigns.sptool file.\n\n";
	printf "ABORT: $filename not imported.\n";
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
# check if PostgreSQL dependent environment variables are set
#
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
	$conn = DBI->connect("DBI:$dbiPG:dbname=$dbname","$userName","$pwd") 
	#emf#	$conn = DBI->connect("DBI:Pg:dbname=$dbname","emf","emf") 
		or die "Database connection not made: $DBI::errstr\n";
}

$conn->{RaiseError} = 1;
$conn->{PrintError} = 0;

$sql = 'SET SEARCH_PATH=shared';
$conn->do($sql) ;


# -- turn off autocommit so we can control our transaction scopes
(!(defined $useTransactions)) or $conn->{AutoCommit} = 0;

# -- Prepare metadata header
$start = (index $filename, "/") + 1;
$file = substr($filename, $start, length($filename));


# -- prepare sql statement for the inserts ==========================================
if ( $tablename eq "invtable" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('INVTABLE','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_invtable \
				(eminv_poll, mode, poll_code, specie_id, reactivity, \ 
				keep, factor, voc, model, explicit, activity, \
				nti, unit, description, cas_description ) \ 
	        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";

	$template = "A12A4A17A6A2A2A6A2A2A2A2A4A17A41A40"; 
}
elsif ( $tablename eq "gas_profiles" )
{
	$sql = "INSERT INTO tbl_gas_profiles \
				(profile_id, profile_name, quality, controls, date_added, \ 
				notes, total, master_poll, test_method, norm_basis, composite, \
				standard, test_year, j_rating, v_rating, d_rating, \ 
				region, old_profile, sibling, voc_to_tog, data_origin, \
				primary_prof, description, documentation ) \ 
	        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
}
elsif ( $tablename eq "pm_profiles" )
{
	$sql = "INSERT INTO tbl_pm_profiles \
				(profile_id, profile_name, quality, controls, date_added, \ 
				notes, total, master_poll, test_method, norm_basis, composite, \
				standard, incl_gas, test_year, j_rating, v_rating, d_rating, \ 
				region, lower_size, upper_size, sibling, data_origin, \
				primary_prof, description, documentation,type ) \ 
	        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
}
elsif ( $tablename eq "mechanism" )
{
	#$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('MECH','$file');";
	#$sth = $conn ->prepare($sql) or die $conn->errstr;
	#$sth->execute();

	$sql = "INSERT INTO tbl_mechanism \
				(mechanism, specie_id, aqm_poll, moles_per_mole ) \
 				VALUES (?, ?, ?, ? );";
}
elsif ( $tablename eq "mechanismPM" )
{
        $sql = "INSERT INTO tbl_pm_mechanism \
                                (mechanism, specie_id, aqm_poll, qualify, compute ) \
                                VALUES (?, ?, ?, ?, ? );";
}
elsif ( $tablename eq "mechanism_description" )
{
	$sql = "INSERT INTO tbl_mechanism_description \
				(mechanism, description, nonsoaflag, origin, reference, comment ) \
 				VALUES (?, ?, ?, ? ,?, ?);";
}
elsif ( $tablename eq "species" )
{
	$sql = "INSERT INTO tbl_species \
				( specie_id, specie_name, cas, epaid, saroad, pams, haps, \         
				symbol, molecular_weight, non_voctog, non_vol_wt, unknown_wt, \
                                unassign_wt, exempt_wt, volatile_mw, num_carbons, epa_itn, comment ) \
				VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
}
elsif ( $tablename eq "gas_profile_weights" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('GAS_PROFILES','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_gas_profile_weights \
				(profile_id, specie_id, percent, uncertainty, unc_method, \ 
				analytic_method )\
				VALUES (?, ?, ?, ?, ?, ? );";
}
elsif ( $tablename eq "pm_profile_weights" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('PM_PROFILES','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_pm_profile_weights \
				(profile_id, specie_id, percent, uncertainty, unc_method, \ 
				analytic_method )\
				VALUES (?, ?, ?, ?, ?, ? );";
}
elsif ( $tablename eq "carbons" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('CARBONS','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_carbons \
				( mechanism, aqm_poll, num_carbons ) \
				VALUES ( ?, ?, ? );";
}
elsif ( $tablename eq "static" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('STATIC','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_static \
				( profile_id, eminv_poll, aqm_poll, split_factor, \
				divisor, mass_fraction, aq_model ) \
				VALUES ( ?, ?, ?, ?, ?, ?, ? );";
}
elsif ( $tablename eq "rename_species" )
{
	$sql = "INSERT INTO tbl_rename_species \
				( aq_model, mechanism, eminv_poll, aqm_poll ) \
				VALUES ( ?, ?, ?, ? );";
}
elsif ( $tablename eq "zero_ph2o" )
{
	$sql = "INSERT INTO tbl_zero_ph2o \
				( profile_id, profile_name ) \
				VALUES ( ?, ? );";
}
elsif ( $tablename eq "pncom_facs" )
{
	$sql = "INSERT INTO tbl_pncom_facs \
				( profile_id, profile_name, pncom_frac ) \
				VALUES ( ?, ?, ? );";
}
elsif ( $tablename eq "o2m_ratios" )
{
	$sql = "INSERT INTO tbl_o2m_ratios \
				( specie_id, symbol, o2m_ratio ) \
				VALUES ( ?, ?, ? );";
}
elsif ( $tablename eq "camx_fcrs" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('CAMX_FCRS','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_camx_fcrs \
				( profile_id ) \
				VALUES ( ? );";
}
elsif ( $tablename eq "vbs_svoc_factors" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('VBS_SVOC_FACTORS','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_vbs_svoc_factors \
				( profile_id, cmaq_svocname, camx_svocname,  \
				bin0, bin1, bin2, bin3, bin4 ) \
				VALUES ( ?, ?, ?, ?, ?, ?, ?, ? );";
}
elsif ( $tablename eq "vbs_ivoc_factors" )
{
	$sql = "INSERT INTO tbl_metadata (keyword, dataval) VALUES ('VBS_IVOC_FACTORS','$file');";
	$sth = $conn ->prepare($sql) or die $conn->errstr;
	$sth->execute();

	$sql = "INSERT INTO tbl_vbs_ivoc_nmogfactors \
				( profile_id, cmaq_ivocname, camx_ivocname, nmogfraction ) \
				VALUES ( ?, ?, ?, ? );";
}
elsif ( $tablename eq "ivoc_species" )
{
	$sql = "INSERT INTO tbl_vbs_ivoc_species \
				( aqm, specie_id, molwt ) \
				VALUES ( ?, ?, ? );";
}
else
{
	print "ERROR - invalid table type specified ", $tablename, "\n";
        print "Valid options: \n";
	print "    invatble\n gas_profiles\n    pm_profiles\n    mechanism\n"; 
	print "    species\n   gas_profile_weights\n    pm_profile_weights\n";
	print "    carbons\n  static\n   rename_species\n  ";
	die   "Retry with a valid table type specified.\n";
}

$sth = $conn->prepare($sql) or die $conn->errstr;

# -- open data file
open(DATAFILE, "$filename") or die "Cannot open file: $filename\n";

print "\nUsing transactions - import of data will abort on any error.\n";
print "Reading data from $filename...\n";

# -- read the lines in the file and insert the data, rollback inserts if error found
$counter = 0;
$nlines = 0;
while (<DATAFILE>)
{
    next if (/^#/);
  if ( $tablename eq "invtable" )
  {
    chomp;
    @data = unpack ($template, $_);
    ## deleting whitespace
    s/\s+$// for (@data);
    s/^\s+// for (@data);
#qa             for($i=0;$i<=$#data;++$i)
#qa             {
#qa                 print $i, " => ", $data[$i], "\n";
#qa             }
  }
  else
  {
	if ($csv->parse($_)) 
	{
		@data = $csv->fields();
	}
	else 
	{
		$err = $csv->error_input;
		print "parse() failed on argument: ", $err, "\n";
		$conn->rollback;
		$conn->disconnect();
		print "Parse failed at record $.\n";
                die "ERRORS:  Terminating import.  Correct the formatting problem and rerun.\n"
	}
  } 
	if (@data > 0)
	{
	        ## remove double quotes
	        s/\"//g for (@data);

#       -- insert the new data
		eval
		{
			$sth->execute(@data);
		};
		$nlines++;

		if (($@) )
		{
			if ($@ =~ /duplicate key/)
			{       
				print "Duplicate key error on input file line $.\n";
			}       
			else    
			{       
				print "Error on datafile line $.\n";
				print "  line : $_\n";
				print "  sql  : $sql\n";
				print "  error: $DBI::errstr\n";
				print "  data :  \n";
				for($i=0;$i<=$#data;++$i)
				{
					print "  $i : $data[$i] \n";
				}
			}       
			if (defined $useTransactions)
			{
				$conn->rollback;
				$conn->disconnect();
				die "ERRORS:  Terminating import.  Correct input file errors and rerun.\n"; 
			}
		}       

		# give some feedback and commit the transaction so far
		if (($counter % 1000) == 0 && $counter > 0 )
		{
			print "  $counter lines processed\n";
		}
	}   #  end of parsed data fields processing
	$counter++;

}    #  end of data input

# -- close the file
close DATAFILE;

# -- disconnect the database, commit 
(!(defined $useTransactions)) or $conn->commit;
$conn->disconnect;

print "...finished, imported $nlines lines.\n\n";

