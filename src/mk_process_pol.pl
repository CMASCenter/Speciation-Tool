#!/usr/bin/perl
#
# Filename   : mk_process_pol.pl
# Author     : Uarporn Nopmongcol, ENVIRON International Corp.
# Version    : Speciation Tool 4.5
# Description: Create MV process modes
# Release    : 30 Sep 2017
#
# Create mobile mode process file from gsref file	
#
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
#c Copyright (C) 2016  Ramboll Environ
#c Copyright (C) 2007  ENVIRON International Corporation
#c
#c Developed by:  
#c
#c       Uarporn Nopmongcol   <unopmongcol@environcorp.com>    415.899.0700
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

# input variables
my %hash;
my @data;
my ($inGSREF, $outPROC , $chk);

($#ARGV == 1) or die "Usage: mk_process_pol.pl input output \n";

$inGSREF = $ARGV[0];
$outPROC = $ARGV[1];

open ( IN, $inGSREF) || die "Cannot open input file";	
open ( OUT, ">$outPROC") || die "Cannot open output file";	

while(<IN>)
{
        next if (/^#/);
	chomp($_);
	@data = split(";",$_);
	$chk = substr($data[2],6,3);
        if ($chk eq "VOC" || $chk eq "TOG")   
	{
		$data[2] = substr($data[2],1,3);
		$data[1] =~ s/\"//g;
		#$data[2] = substr($data[2],0,3);
		$hash{$data[1],$data[2]}="$data[1],$data[2]"; 

	}
}
close IN;

for my $value (sort keys %hash)
{	
		print OUT "$hash{$value}\n";
}
close OUT;
