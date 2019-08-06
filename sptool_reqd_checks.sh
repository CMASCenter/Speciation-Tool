#!/bin/bash
#
#==================================================================================
# Filename   : sptool_reqd_checks.sh
# Author     : ENVIRON International Corp. 
# Version    : 3.1
# Description: Script to check software requirements for Speciation Tool
# Release    : 23Apr2013
#
#  This script tests the status of PostgreSQL and Perl installations on
#  a Linux system to determine it's readiness for the Speciation Tool.
#
#  Use:    ./sptool_reqd_checks.sh
#
#====================================================================================
#ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
#c Copyright (C) 2013  ENVIRON International Corporation
#c
#c Developed by:  
#c
#c   Michele Jimenez   <mjimenez@environcorp.com>    415.899.0700
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


#====================================================================================
echo
echo ===== Speciation Tool Requirements Check =====
echo
#====================================================================================
#
# Check environment variables: If not set assign system defaults
#
if  [[ -z "$PERL_BIN" ]]; then
    PERL_BIN=$(dirname `which perl`)
    echo -e "Perl located in $PERL_BIN"
fi
#
if  [[ -z $POSTGRES_BIN ]]; then
    if psql --version < /dev/null > /dev/null 2>&1 ; then
        POSTGRES_BIN=$(dirname `which psql`)
        echo -e "PostgreSQL located in $POSTGRES_BIN"
    fi
fi

#====================================================================================
echo
echo Checking the status of software requirements... 
echo
echo
echo Status of required software:
echo [x] = Installed
echo [ ] = Not installed
echo [?] = Unable to determine, see notes
echo 


#------PERL------#
echo "------PERL------"

perlMods=0

# CHECK IF PERL IS INSTALLED
if $PERL_BIN/perl -v < /dev/null > /dev/null 2>&1 ; then
	# PERL IS INSTALLED
    echo [x] Perl
		
	# CHECK IF PERL DBI MODULE IS INSTALLED
	if $PERL_BIN/perl -MDBI -e 'print "$DBI::VERSION\n";' < /dev/null > /dev/null 2>&1 ; then
		echo -e "[x]    -DBI"
	else
		echo -e "[ ]    -DBI"
		perlMods=$(( $perlMods + 1 ))
	fi

	# CHECK IF PERL DBD::PgPP or DBD::Pg MODULE IS INSTALLED
	if $PERL_BIN/perl -MDBD::PgPP -e 'print "$DBD::PgPP::VERSION\n";' < /dev/null > /dev/null 2>&1 ; then
		echo -e "[x]    -DBD-PgPP"
	else
	   if $PERL_BIN/perl -MDBD::Pg -e 'print "$DBD::Pg::VERSION\n";' < /dev/null > /dev/null 2>&1 ; then
		   echo -e "[x]    -DBD-Pg"
	   else
		   echo -e "[ ]    -DBD-Pg or DBD-PgPP"
		   perlMods=$(( $perlMods + 1 ))
	   fi
	fi

	# CHECK IF PERL TEXT::CSV MODULE IS INSTALLED
	if $PERL_BIN/perl -MText::CSV -e 'print "$Text::CSV::VERSION\n";' < /dev/null > /dev/null 2>&1 ; then
		echo -e "[x]    -Text-CSV"
	else
		echo -e "[ ]    -Text-CSV"
		perlMods=$(( $perlMods + 1 ))
	fi

	# LIST MISSING PERL MODULES 
	if [ "$perlMods" -gt 0 ]; then
		echo
		echo Warning:
		echo "$perlMods missing Perl module(s). Install the missing module(s) before running the Speciation Tool."
		echo
		echo "Check with your system administrator or refer to Appendix A of the Speciation Tool User Guide."
		echo
	fi		
		
else
	# PERL IS NOT INSTALLED
	echo [ ] Perl
	echo -e "[ ]    -DBI"
	echo -e "[ ]    -DBD-Pg or DBD-PgPP"
	echo -e "[ ]    -Text-CSV"
fi



#-------POSTGRESQL-------#
echo
echo "---POSTGRESQL---"

psqlState=0
dateTime=`date +%Y%m%d%H%M`

# CHECK IF POSTGRESQL IS INSTALLED
if $POSTGRES_BIN/psql --version < /dev/null > /dev/null 2>&1 ; then
	# POSTGRES IS INSTALLED
	psqlState=$(( $psqlState + 1 ))
	echo [x] PostgreSQL
	
	# POSTGRES IS INSTALLED, SO LET'S CHECK TO SEE IF THE USER HAS AN ACCOUNT
	if $POSTGRES_BIN/psql -l < /dev/null > /dev/null 2>&1 ; then
		
		# USER HAS ACCESS
		#echo User $(whoami) has a PostgreSQL user account of the same name.
		psqlState=$(( $psqlState + 1 ))
		
	else
		# USER DOES NOT HAVE ACCESS TO POSTGRESQL, SO WE CAN'T TEST IF PL/pgSQL IS INSTALLED
		# NEED TO CREATE A NEW USER ACCOUNT IN POSTGRESQL
		
		# CREATE USER WITH NO-SUPERUSER, CREATEDB, CREATEROLE
		if $POSTGRES_BIN/createuser $(whoami) -U postgres -Sdr < /dev/null > /dev/null 2>&1 ; then
			# SUCCESSFULLY CREATED NEW USER
			psqlState=$(( $psqlState + 1 ))
		fi

	fi

	# CREATE NEW DB TO TEST CAPABILITIES AND LANGUAGES
	if [ "$psqlState" -eq 2 ] ; then
		#
		if $POSTGRES_BIN/createdb $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1 ; then
			# SUCCESSFULLY CREATED NEW TESTER DATABASE
			#echo "created new tester database"
			# check to see if language exists before create
			list=`$POSTGRES_BIN/createlang -l -d $(whoami)_test_$dateTime | grep plpgsql`
			if [ -n "$list" ] 
			then
				echo -e "[x]    -PL/pgSQL"
			else
			  if $POSTGRES_BIN/createlang plpgsql -d $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1 ; then
				# LOOKS LIKE IT SUCCESSFULLY PERFORMED THE OPERATION, SO PL/pgSQL IS INSTALLED
				#echo created plpgsql
				echo -e "[x]    -PL/pgSQL"
			  else
				# COULDN'T PERFORM THE OPERATION SO PL/pgSQL IS PROBABLY NOT INSTALLED
				#echo "Can't find plpgsql"
				echo -e "[ ]    -PL/pgSQL"
			  fi
			fi
			$POSTGRES_BIN/dropdb $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1
		else
			#echo "couldn't create new tester database (might already exist?)"
			if $POSTGRES_BIN/dropdb $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1 ; then
				# SUCCESSFULLY DROPPED THE TESTER DB, SO NOW WE CAN RECREATE IT
				#echo "was able to drop old tester database"
				if $POSTGRES_BIN/createdb $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1 ; then
					#echo "and was able to create a new tester database"
					# SUCCESSFULLY CREATED NEW TESTER DATABASE
					# check to see if language exists before create
					list=`$POSTGRES_BIN/createlang -l -d $(whoami)_test_$dateTime | grep plpgsql`
					if [ -n "$list" ] 
					then
						echo -e "[x]    -PL/pgSQL"
					else
					  if $POSTGRES_BIN/createlang plpgsql $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1 ; then
						# LOOKS LIKE IT SUCCESSFULLY PERFORMED THE OPERATION, SO PL/pgSQL IS INSTALLED
						#echo created plpgsql
						echo -e "[x]    -PL/pgSQL"
					  else
						# COULDN'T ADD PL/pgSQL, BUT MIGHT BE ADDED AUTOMATICALLY FROM TEMPLATE1
						if $POSTGRES_BIN/droplang plpgsql -d postgres < /dev/null > /dev/null 2>&1 ; then
							# LOOKS LIKE PL/pgSQL IS ADDED AUTOMATICALLY
							$POSTGRES_BIN/createlang plpgsql -d postgres < /dev/null > /dev/null 2>&1
							#echo PL/pgSQL is automatically added to new databases
							echo -e "[x]    -PL/pgSQL"
						else
							# COULDN'T PERFORM THE OPERATION SO PL/pgSQL IS PROBABLY NOT INSTALLED
							#echo "Can't find plpgsql"
							echo -e "[ ]    -PL/pgSQL"
						fi
					  fi
					fi
					$POSTGRES_BIN/dropdb $(whoami)_test_$dateTime < /dev/null > /dev/null 2>&1
				else
					echo "was not able to create a new tester database"
					if $POSTGRES_BIN/droplang plpgsql -d postgres < /dev/null > /dev/null 2>&1 ; then
						$POSTGRES_BIN/createlang plpgsql -d postgres < /dev/null > /dev/null 2>&1
						#echo dropped and created plpgsql
						echo -e "[x]    -PL/pgSQL"
					else
						# COULDN'T DROP BUT IT COULD JUST NOT BE ADDED TO THAT DATABASE, LET'S TRY ADDING IT.
						echo "couldn't drop plpgsql language from old database?"
						if $POSTGRES_BIN/createlang plpgsql -U postgres -d postgres < /dev/null > /dev/null 2>&1 ; then
							# LOOKS LIKE IT SUCCESSFULLY PERFORMED THE OPERATION, SO PL/pgSQL IS INSTALLED
							#echo created plpgsql
							echo -e "[x]    -PL/pgSQL"
						else
							# COULDN'T PERFORM THE OPERATION SO PL/pgSQL IS PROBABLY NOT INSTALLED
							#echo "Can't find plpgsql"
							echo -e "[ ]    -PL/pgSQL"
						fi
					fi
						
				fi
			else
				# COULDN'T CREATE NOR DROP THE TESTER DB, SO USER DOESN'T HAVE PRIVELEDGES
				echo -e "[?]    -PL/pgSQL"
				echo
				echo Warning:
				echo PostgreSQL user $(whoami) does not have the required privileges to CREATEDB 
				echo or DROPDB. These privileges are required to run the Speciation Tool. Please
				echo contact your system administrator to obtain these privileges.
				echo
			fi
		fi
	else
		if [ "$psqlState" -eq 1 ] ; then
			# NO POSTGRES USER AND WAS UNABLE TO CREATE ONE
			echo -e "[?]    -PL/pgSQL"
			echo
			echo Warning:
			echo User $(whoami) does not have a PostgreSQL user account.
			echo The attempt to create an account for the user was unsuccessful.
			echo Check with your system administrator to create a PostgreSQL account 
			echo in order to install and run the Speciation Tool.
			echo

		
		fi
	fi	
	
else
	# POSTGRESQL DOES NOT APPEAR TO BE INSTALLED
	echo -e "[ ] PostgreSQL"
	echo -e "[ ]	-PL/pgSQL"
	echo
	echo Warning:
	echo PostgreSQL and PL/pgSQL were not found.  These need to be installed to run the Speciation Tool.
	echo Check with your system administrator to have them installed or refer to Appendix A of
	echo the Speciation Tool User Guide.
	echo
fi

echo
echo Refer to the Speciation Tool User Guide Appendix A for installation procedures of the required software.
echo



