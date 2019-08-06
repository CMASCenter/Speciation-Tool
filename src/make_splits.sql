-- Filename   : make_splits.sql
-- Author     : Michele Jimenez, ENVIRON International Corp. 
-- Version    : Speciation Tool 4.0 
-- Release    : 12 Sep 2016
--
--  Generate and fill the temporary tables used to determine
--  the split factors.  Notices are displayed indicating the progress
--  of execution.
--
--  Modified August 2006
--  Enhanced to include checks for zero or null molecular weights.
--  Added message to report deleted profiles where weight percent sum
--  is outside specifed or default tolerance.
--
--  Modified September 2007
--  Added 'haplist' as run_type to process VOC HAPs that define the calculation of NONHAPVOC 
--  Added metadata header 
--  Enhanced to allow toxic name overwrite  
--  Checked for profiles with 100% active toxics to avoid profile drop-out
--
--  Modified May 2011
--  Moved initial NOTICEs inside the IF construct.
--  Added additional information to warning messages with join.
--
--  Modified May 2013a
--  Added delete tbl_toxics for different chemical mechanism records
--  Correct the tbl_toxics deletion where clause
--  
--  Modified June 2016
--  Included WARNING of list of species not defined for specified
--  mechanism AND referenced in profiles.
--
--  Modified Aug 2016
--  Added support of Volatility Basis Set (VBS) to generate
--  IVOC compounds based on non-methane components.  Defined tmp_species table
--  to support the IVOC compounds.
--
--ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
--c Copyright (C) 2016  Ramboll Environ
--c Copyright (C) 2007  ENVIRON International Corporation
--c
--c Developed by:  
--c
--c       Michele Jimenez   <mjimenez@environcorp.com>    415.899.0700
--c
--c Modified by:
--c       Uarporn Nopmongcol <unopmongcol@environcorp.com>  Sep, 2007 
--c       MJimenez June 2011, to support addition of PM mechanism
--c
--c This program is free software; you can redistribute it and/or
--c modify it under the terms of the GNU General Public License
--c as published by the Free Software Foundation; either version 2
--c of the License, or (at your option) any later version.
--c
--c This program is distributed in the hope that it will be useful,
--c but WITHOUT ANY WARRANTY; without even the implied warranty of
--c MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--c GNU General Public License for more details.
--c
--c To obtain a copy of the GNU General Public License
--c write to the Free Software Foundation, Inc.,
--c 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
--ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
----------------------------------------------------------------------------------

SET search_path=shared;

CREATE OR REPLACE FUNCTION MakeSplits() RETURNS VOID AS
$$
DECLARE

    prfRow                    RECORD;
    hapRow                    RECORD;
    aqmRow                    RECORD;
    wtsRow                    RECORD;
    spcRow                    RECORD;
    toxRow                    RECORD;
    intRow                    RECORD;
    primeRow                  RECORD;

    runMechanism             TEXT; 
    flagMech                 TEXT;
    runType                  TEXT; 
    runOut                   TEXT; 
    runAQM                   TEXT; 
    toxtype                  TEXT; 
    tolerance                FLOAT;  
    runUsrProf               TEXT;
    defTol                   FLOAT;  
    minTol                   FLOAT;  
    maxTol                   FLOAT;  
    outsideTol               INTEGER;
    sumWt                    FLOAT; 
    sumCarbons               FLOAT;
    mole                     FLOAT;
    molesPerGramEm           FLOAT;
    ivocname                 TEXT;
    eminvPoll                TEXT;
    eminv                    TEXT;
    toxoverwrite             TEXT;

    version                  TEXT;
    criteria                 TEXT;
    integrate                TEXT;
    noIntegrate              TEXT;
    haplist                  TEXT;
    vbs                      TEXT;
    cmaq                     TEXT;
    camx                     TEXT;
    methane                  TEXT;
    tmpInteger               INTEGER;
    tmpChar                  TEXT;
    tmpText                  TEXT;

----------------------------------------------------------------------------------

BEGIN

    version := 'Speciation Tool v4.0';

 -- check to proceed VOC speciation -- 
    -- get the list of output requirements from the control table --
    SELECT  INTO runOut dataval
    FROM  tbl_run_control
    WHERE tbl_run_control.keyword = 'OUTPUT';
    runOut := UPPER(runOut);

    -- get the mechanism basis for this run --
    SELECT  INTO runAQM dataval
    FROM  tbl_run_control
    WHERE tbl_run_control.keyword = 'AQM';
    runAQM := UPPER(runAQM);
-----------------------------------------------------------------------------------------

    IF ( runOut ISNULL OR runOut LIKE '%VOC%')  THEN

        RAISE NOTICE '======== % ========', version;
        RAISE NOTICE '  ' ;

        RAISE NOTICE 'Type of Output is  % ', runOut;
        RAISE NOTICE 'AQM is  % ', runAQM;

        -- Set up the temporary tables required for the calculations --
        tmpInteger := Calcs_CreateTempTables();

        -- default to 5% if no tolerance specified by user --      
        defTol := 5.;

        -- initialize run types --
        criteria := 'CRITERIA';
        integrate   := 'INTEGRATE';
        noIntegrate := 'NOINTEGRATE';
        haplist := 'HAPLIST';
	vbs := 'VBS';
	cmaq := 'CMAQ';
	camx := 'CAMX';
	methane := '529';  -- species_id for methane in SPECIATE database

        -- get the run type from the control table --
        SELECT  INTO runType dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'RUN_TYPE';
        runType := UPPER(runType);
        RAISE NOTICE 'Type of run is  % ', runType;

        -- get the mechanism basis for this run --
        SELECT  INTO runMechanism dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'MECH_BASIS';
        runMechanism := UPPER(runMechanism);
        RAISE NOTICE 'Mechanism basis is  % ', runMechanism;

        -- get the mechanism database nonsoaflag 
        SELECT INTO flagMech nonsoaflag 
        FROM tbl_mechanism_description
        WHERE tbl_mechanism_description.mechanism = runMechanism; 

        -- determine if user specified profile weights --
        SELECT  INTO runUsrProf dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'PRO_FILE';

        -- get the user specified profile weights tolerance --
        SELECT  INTO tmpChar dataval 
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'TOLERANCE';

        IF ( tmpChar ISNULL )  THEN 
           tolerance := defTol; 
        ELSE
           tolerance := TO_NUMBER(tmpChar,'99.9');
        END IF; 
        RAISE NOTICE 'Profile Tolerance is  % ', tolerance;
        minTol := 100. - tolerance; 
        maxTol := 100. + tolerance; 

  ---------------------------------------------------------------------------------------
        -- check on width of output pollutant names
        -- Case A Valid length is 7 such as EXH_BENZENE_NOI
        CREATE TABLE tmp_invtable AS
        SELECT eminv_poll 
        FROM tbl_invtable
        WHERE tbl_invtable.mode != ''  
          AND tbl_invtable.model = 'Y'
          AND (tbl_invtable.voc = 'V' OR tbl_invtable.voc = 'T')
          AND ( length(tbl_invtable.eminv_poll) > 7 )	
        GROUP BY eminv_poll;
         
        -- Case B Valid length is 11 such as EXH_AAAAAAAAAAA
        INSERT INTO tmp_invtable 
        SELECT eminv_poll 
        FROM tbl_invtable
        WHERE tbl_invtable.mode != ''  
          AND (tbl_invtable.voc != 'V' AND tbl_invtable.voc != 'T')
          AND ( length(tbl_invtable.eminv_poll) > 11 )	
        GROUP BY eminv_poll;

        -- Case C Valid length is 12 such as TRIETHLAMN_NOI
        -- Note that the tool reads only 12 chars from invtable anyway 
        -- It is only included here in case of future invtable format change
        INSERT INTO tmp_invtable 
        SELECT eminv_poll 
        FROM tbl_invtable
        WHERE tbl_invtable.model = 'Y'
          AND (tbl_invtable.voc = 'V' OR tbl_invtable.voc = 'T')
          AND ( length(tbl_invtable.eminv_poll) > 12 )	
        GROUP BY eminv_poll;
 
        SELECT INTO tmpInteger COUNT(*)
        FROM tmp_invtable;
 
        IF ( tmpInteger > 0 )  THEN
           RAISE NOTICE 'ERROR:  Output pollutant name derived from the inventory table exceeds 16-char.' ;
           FOR spcRow IN
             SELECT DISTINCT eminv_poll 
             FROM tmp_invtable
           LOOP
             RAISE NOTICE '              Species name %  ',spcRow.eminv_poll;
           END LOOP;
           RETURN;
        END IF;
 
-----------------------------------------------------------------------------------------
        -- create HAPS table and update active/tracer flag in TOX table      

        DELETE FROM tbl_toxics WHERE aqm_model != runAQM;
        IF ( runType = integrate OR runType = nointegrate OR runType = haplist )  THEN
          -- check that the species specified in the user input toxics exist with active/toxic species in invtable
          FOR intRow IN
            SELECT DISTINCT specie_id, eminv_poll, explicit 
            FROM tbl_invtable
            WHERE (voc = 'V' OR voc = 'T')
            AND keep = 'Y'
            AND model = 'Y'
          LOOP  
            tmpText = 'N';
            FOR toxRow IN
               SELECT DISTINCT specie_id
               FROM tbl_toxics
               WHERE tbl_toxics.aqm_model = runAQM	
            LOOP
              IF (toxRow.specie_id = intRow.specie_id) THEN 
       	         IF (intRow.explicit = 'Y') THEN
                    toxtype = 'A';
                 ELSE
                    toxtype = 'T';
                 END IF;

                 UPDATE tbl_toxics
                 SET active = toxtype	
                 WHERE tbl_toxics.specie_id = toxRow.specie_id; 

                 tmpText = 'Y';
              END IF;
            END LOOP;

            IF ( tmpText = 'N' ) THEN
               RAISE NOTICE 'ERROR ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
               RAISE NOTICE ' Species ID % (Active/Tracer toxic) in invtable not found in Toxic table', intRow.specie_id;
               INSERT INTO tmp_error (error) 
               VALUES ('error'); 
               RETURN;
            END IF;

          END LOOP;  -- intRow

          FOR toxRow IN
              SELECT * FROM tbl_toxics
              WHERE tbl_toxics.aqm_model = runAQM	
                AND tbl_toxics.active IS NULL
          LOOP
              RAISE NOTICE 'WARNING: Species ID % in Toxic table dropped because it is not either active or tracer species', toxRow.specie_id;
          END LOOP; 

          DELETE FROM tbl_toxics 
          WHERE active IS NULL;

          -- create tmp_haps from invtable
     
          INSERT INTO tmp_haps (specie_id, aqminv_poll)
          SELECT DISTINCT specie_id, eminv_poll 
          FROM tbl_invtable
          WHERE voc = 'V'
             OR voc = 'T' 
          GROUP BY specie_id, eminv_poll;

          ----------------------------------------------------------------------------------------
          -- check that the species specified in the user input toxics and haps files
          -- exist in the species table and have nonzero MWs

          INSERT INTO tmp_spcinp
          SELECT tmp_haps.specie_id, volatile_mw
          FROM tmp_haps, tbl_species
          WHERE tmp_haps.specie_id = tbl_species.specie_id
            AND (tbl_species.volatile_mw ISNULL OR tbl_species.volatile_mw <= 0.0);
          INSERT INTO tmp_spcinp
          SELECT tbl_toxics.specie_id, volatile_mw
          FROM tbl_toxics, tbl_species
          WHERE tbl_toxics.specie_id = tbl_species.specie_id
            AND tbl_toxics.aqm_model = runAQM
            AND (tbl_species.volatile_mw ISNULL OR tbl_species.volatile_mw <= 0.0);

          SELECT INTO tmpInteger COUNT(*)
          FROM tmp_spcinp;

          IF ( tmpInteger > 0 )  THEN
             RAISE NOTICE '  ' ;
             RAISE NOTICE 'ERROR:  Species in HAPS_FILE and/or TOX_FILE have invalid molecular weights.' ;
             RAISE NOTICE '        Either correct user input file or update tbl_species field volatile_mw.' ;
             RAISE NOTICE '        Please correct the following: ' ;

             FOR spcRow IN
                SELECT DISTINCT specie_id
                FROM tmp_spcinp
             LOOP
                RAISE NOTICE '                                      Species ID % ',spcRow.specie_id;
             END LOOP;
             RAISE NOTICE 'ERROR ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
             RETURN;
          END IF;

        END IF;  -- non Criteria run
  -----------------------------------------------------------------------------------------
        -- check that number of carbons have been defined for each mechanism aqm compound
        FOR aqmRow IN
          SELECT DISTINCT aqm_poll
          FROM tbl_mechanism
          WHERE tbl_mechanism.mechanism = runMechanism
        LOOP

          SELECT INTO tmpInteger COUNT(*)
          FROM tbl_carbons
          WHERE aqmRow.aqm_poll = tbl_carbons.aqm_poll
            AND tbl_carbons.mechanism = runMechanism;

          IF ( tmpInteger = 0 )  THEN
             INSERT INTO tmp_qa_carbons (aqm_poll)
             VALUES (aqmRow.aqm_poll);
          END IF;
        END LOOP;

        SELECT INTO tmpInteger COUNT(*) FROM tmp_qa_carbons;
        IF ( tmpInteger > 0 )  THEN
           RAISE NOTICE '  ' ;
           RAISE NOTICE 'ERROR:  Compounds exist in mechanism with no carbon data.';
           RAISE NOTICE '        Correct/update carbons in tbl_carbons for the following compounds:' ;
           FOR aqmRow IN
              SELECT * 
              FROM tmp_qa_carbons
           LOOP
              RAISE NOTICE '                                                                            % ',aqmRow.aqm_poll;
           END LOOP;
 
           RAISE NOTICE 'ERROR ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
           RETURN;
        END IF;

  -----------------------------------------------------------------------------------------
        -- determine if no mechanism data exists for each specie --
        -- will set AQM to UNK later in code when establishing mechanism basis ---

        CREATE TABLE tmp_qa_mechanism AS
        SELECT tbl_species.specie_id, 0.0 AS sum_moles
        FROM tbl_species;

        UPDATE tmp_qa_mechanism
        SET sum_moles = tmpSum.sum
        FROM ( SELECT mechanism, specie_id, SUM(moles_per_mole)
               FROM tbl_mechanism
               WHERE tbl_mechanism.mechanism = runMechanism
               GROUP BY mechanism, specie_id ) AS tmpSum
        WHERE tmp_qa_mechanism.specie_id = tmpSum.specie_id;
 
        DELETE FROM tmp_qa_mechanism 
        WHERE sum_moles > 0.;
 
        SELECT INTO tmpInteger COUNT(*) 
        FROM tmp_qa_mechanism;

--	comment out warning - only interested if used in profile which is now reported below 
        IF ( tmpInteger > 0 )  THEN
          RAISE NOTICE '  ' ;
          RAISE NOTICE 'WARNING review vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
          RAISE NOTICE 'WARNING: % mechanism undefined for the following species.', runMechanism ;
          RAISE NOTICE '         The following will be set to UNK if referenced.' ;

          FOR spcRow IN 
            SELECT q.*,s.specie_name FROM tmp_qa_mechanism q
            LEFT OUTER JOIN tbl_species s ON s.specie_id = q.specie_id
          LOOP    
            RAISE NOTICE 'WARNING:           SPECIES ID  % %', spcRow.specie_id, spcRow.specie_name;

          END LOOP;
          RAISE NOTICE 'WARNING review ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
          RAISE NOTICE '  ' ;
        END IF;

  -----------------------------------------------------------------------------------------
        -- set up the number of carbons by specie for specified mechanism -------------------
        FOR spcRow IN
         SELECT *
         FROM tbl_species
        LOOP

          SELECT INTO sumCarbons SUM(tbl_mechanism.moles_per_mole * tbl_carbons.num_carbons)
          FROM tbl_mechanism, tbl_carbons
          WHERE tbl_mechanism.mechanism = runMechanism
            AND tbl_mechanism.specie_id = spcRow.specie_id
            AND tbl_carbons.mechanism   = runMechanism
            AND tbl_mechanism.aqm_poll  = tbl_carbons.aqm_poll;

          -- if the sum is zero, then no mechanism data exists, --
          -- it will be set to 1.0 UNK --
          IF ( sumCarbons > 0 )  THEN
       	     INSERT INTO tmp_species_carbons ( mechanism, specie_id, num_carbons )
             VALUES (runMechanism, spcRow.specie_id,  sumCarbons );
          ELSE
             INSERT INTO tmp_species_carbons ( mechanism, specie_id, num_carbons )
             VALUES (runMechanism, spcRow.specie_id,  1.0 );

          END IF;
        END LOOP;

	-- insert IVOC species with carbons set to 1. for VBS run
        IF ( runType = vbs ) THEN
             INSERT INTO tmp_species_carbons ( mechanism, specie_id, num_carbons )
	     SELECT runMechanism, specie_id, 1.0
	     FROM tbl_vbs_ivoc_species
	     WHERE aqm = runAQM;
        END IF;

        -- update the number of carbons into toxic table
        IF ( runType = integrate OR runType = nointegrate OR runType = haplist )  THEN
          UPDATE tbl_toxics 
             SET num_carbons = tmp_species_carbons.num_carbons
          FROM tmp_species_carbons
          WHERE tmp_species_carbons.specie_id = tbl_toxics.specie_id
            AND tmp_species_carbons.mechanism = runMechanism;
        END IF;
  -----------------------------------------------------------------------------------------
        -- populate the temporary array of AQM pollutants carbon count -----------------------
        INSERT INTO tmp_aqm_carbons (mechanism, aqm_poll, num_carbons)
        SELECT mechanism, aqm_poll, num_carbons
        FROM tbl_carbons
        WHERE tbl_carbons.mechanism = runMechanism;

        FOR toxRow IN
        SELECT aqm_model, aqm_poll, num_carbons
          FROM tbl_toxics
          WHERE tbl_toxics.aqm_model = runAQM
        LOOP

          SELECT INTO tmpInteger COUNT(*)
          FROM tmp_aqm_carbons
          WHERE toxRow.aqm_poll = tmp_aqm_carbons.aqm_poll;

          IF ( tmpInteger = 0 ) THEN
             INSERT INTO tmp_aqm_carbons (mechanism, aqm_poll, num_carbons)
             VALUES (runMechanism, toxRow.aqm_poll, toxRow.num_carbons);
          END IF;
       	
        END LOOP;

	-- insert IVOC AQM compounds with carbons set to 1. for VBS run
        IF ( runType = vbs ) THEN
             INSERT INTO tmp_aqm_carbons ( mechanism, aqm_poll, num_carbons )
	     SELECT runMechanism, specie_id, 1.0
	     FROM tbl_vbs_ivoc_species
	     WHERE aqm = runAQM;
        END IF;

        SELECT INTO tmpInteger COUNT(*) 
        FROM tmp_aqm_carbons
        WHERE aqm_poll = 'UNK';

        IF ( tmpInteger = 0 ) THEN
           INSERT INTO tmp_aqm_carbons (mechanism, aqm_poll, num_carbons)
           VALUES (runMechanism, 'UNK', 1.0);
        END IF;

  -----------------------------------------------------------------------------------------
        -- Establish the mechanism ------------------------------------------------------
        -- set up the temporary mechanism table, incorporate active and tracer toxics
        -- first, include base mechanism
        RAISE NOTICE '... establishing mechanism' ;
        INSERT INTO tmp_mechanism
              (mechanism, specie_id, aqm_poll, moles_per_mole)
        SELECT mechanism, specie_id, aqm_poll, moles_per_mole
        FROM tbl_mechanism
        WHERE tbl_mechanism.mechanism = runMechanism
          AND tbl_mechanism.moles_per_mole > 0.0;

        -- add records for species with no mechanism definition --
         INSERT INTO tmp_mechanism
               (mechanism, specie_id, aqm_poll, moles_per_mole)
         SELECT runMechanism, specie_id, 'UNK', 1.0
         FROM tmp_qa_mechanism;
 
        -- next, delete toxics with active tracers from the base mechanism       --
        FOR toxRow IN 
           SELECT  *   FROM tbl_toxics 
           WHERE active = 'A'
             AND aqm_model = runAQM
        LOOP

           DELETE FROM tmp_mechanism
           WHERE tmp_mechanism.mechanism = runMechanism
             AND tmp_mechanism.specie_id = toxRow.specie_id;
        END LOOP;

        -- and finally, insert the toxic species in the temporary mechanism table --
        IF ( runType != nointegrate )  THEN
           FOR toxRow IN 
               SELECT  *   FROM tbl_toxics 
               WHERE aqm_model = runAQM
           LOOP
              INSERT INTO tmp_mechanism (mechanism, specie_id, aqm_poll, moles_per_mole )
              VALUES (runMechanism, toxRow.specie_id, toxRow.aqm_poll, 1.0);
           END LOOP;
        END IF;

	-- insert IVOC AQM compounds with carbons set to 1. for VBS run
        IF ( runType = vbs ) THEN
             INSERT INTO tmp_mechanism ( mechanism, specie_id, aqm_poll, moles_per_mole )
	     SELECT runMechanism, specie_id, specie_id, 1.0
	     FROM tbl_vbs_ivoc_species
	     WHERE aqm = runAQM;
        END IF;

  -----------------------------------------------------------------------------------------
        -- Establish the profile weights -----------------------------------------------------
        -- set up the temporary profile weights table incorporating the nonhaps --
        IF ( runType != haplist )  THEN

          -- first, copy the profile weights to a temporary work table --
          RAISE NOTICE '... establishing profile weights' ;

          -- either use the shared profile weights or the user specified --
          IF ( runUsrProf ISNULL )  THEN
             INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
             SELECT profile_id, tbl_gas_profile_weights.specie_id, percent
             FROM tbl_gas_profile_weights, tbl_species
             WHERE tbl_gas_profile_weights.specie_id = tbl_species.specie_id
               AND percent > 0.;
          ELSE
             INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
             SELECT profile_id, tbl_user_profile_wts.specie_id, percent
             FROM tbl_user_profile_wts, tbl_species
             WHERE tbl_user_profile_wts.specie_id = tbl_species.specie_id
               AND percent > 0.;
          END IF;

          -- delete records where the corresponding molecular weight is invalid --
          RAISE NOTICE '  ' ;
          RAISE NOTICE 'WARNING - Missing molecular weights. These components dropped:';
          FOR prfRow IN
             SELECT * 
             FROM tmp_raw_profiles, tbl_species
             WHERE tmp_raw_profiles.specie_id = tbl_species.specie_id
               AND (volatile_mw IsNull OR volatile_mw <= 0.0)
          LOOP
            DELETE  
            FROM tmp_raw_profiles
            WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
              AND prfRow.specie_id = tmp_raw_profiles.specie_id;

            RAISE NOTICE '       profile %  species % wtpct % %',prfRow.profile_id,prfRow.specie_id, prfRow.percent, prfRow.specie_name ;
          END LOOP;
          RAISE NOTICE 'WARNING - Missing molecular weights. End List';
          RAISE NOTICE '  ' ;

          -- sum weight percents by profile --
          INSERT INTO tmp_sums (profile_id, sum_pct)
          SELECT DISTINCT profile_id, SUM(percent)
          FROM tmp_raw_profiles
          WHERE percent > 0.
          GROUP BY profile_id;
 
          --  delete weight profiles whose sum is outside the tolerance --
          SELECT INTO outsideTol COUNT(*) 
          FROM tmp_sums
          WHERE tmp_sums.sum_pct > maxTol OR tmp_sums.sum_pct < minTol;
          IF ( outsideTol > 0 )  THEN
             RAISE NOTICE '  ' ;
             RAISE NOTICE 'WARNING review vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
             RAISE NOTICE 'WARNING The following profiles were dropped.';
             RAISE NOTICE 'WARNING Total weight percent is outside the tolerance of % percent.',tolerance ;

             FOR prfRow IN 
                SELECT tmp_sums.*, substring(p.profile_name from 1 for 50) AS profile_name 
                FROM tmp_sums
                INNER JOIN tbl_gas_profiles p ON p.profile_id = tmp_sums.profile_id
                WHERE tmp_sums.sum_pct > maxTol OR tmp_sums.sum_pct < minTol
             LOOP    
                RAISE NOTICE 'WARNING:   PROFILE ID  % % percent %', prfRow.profile_id,prfRow.sum_pct,prfRow.profile_name;
 
                DELETE  
                FROM tmp_raw_profiles
                WHERE tmp_raw_profiles.profile_id = prfRow.profile_id;
             END LOOP;
             RAISE NOTICE 'WARNING review ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
             RAISE NOTICE '  ' ;
          END IF;

          -- determine the species that are undefined for the specified mechanism --
          CREATE TABLE tmp2_qa_mechanism AS
           SELECT DISTINCT tmp_raw_profiles.specie_id, 0.0 AS sum_moles
           FROM tmp_raw_profiles;

          UPDATE tmp2_qa_mechanism
          SET sum_moles = tmpSum.sum
          FROM ( SELECT mechanism, specie_id, SUM(moles_per_mole)
               FROM tbl_mechanism
               WHERE tbl_mechanism.mechanism = runMechanism
               GROUP BY mechanism, specie_id ) AS tmpSum
          WHERE tmp2_qa_mechanism.specie_id = tmpSum.specie_id;
 
          DELETE FROM tmp2_qa_mechanism 
          WHERE sum_moles > 0.;
 
          SELECT INTO tmpInteger COUNT(*) 
            FROM tmp2_qa_mechanism;
          IF ( tmpInteger > 0 )  THEN 
          RAISE NOTICE '  ' ;
          RAISE NOTICE 'WARNING review vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
          RAISE NOTICE 'WARNING: % mechanism undefined for the following species.', runMechanism ;
          RAISE NOTICE '         The following species are referenced by profiles and will be set to UNK.' ; 
          FOR spcRow IN 
            SELECT q.*,s.specie_name FROM tmp2_qa_mechanism q
            LEFT OUTER JOIN tbl_species s ON s.specie_id = q.specie_id
          LOOP    
            RAISE NOTICE 'WARNING:           SPECIES ID  % %', spcRow.specie_id, spcRow.specie_name;
          END LOOP;
          RAISE NOTICE 'WARNING review ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
          RAISE NOTICE '  ' ;
          END IF; 
 
          -- renormalize --
          RAISE NOTICE '...renormalizing profile weights' ;
          UPDATE tmp_raw_profiles 
          SET percent = (tmp_raw_profiles.percent / tmp_sums.sum_pct) * 100.
          FROM tmp_sums
          WHERE tmp_raw_profiles.profile_id = tmp_sums.profile_id;

          -- copy tbl_species to temporary table.  append IVOCs if VBS run
          CREATE TABLE tmp_species AS
          SELECT specie_id,volatile_mw,non_voctog
          FROM tbl_species;
          IF ( runType = vbs ) THEN
             INSERT INTO tmp_species 
             SELECT specie_id,molwt,FALSE
             FROM tbl_vbs_ivoc_species;
          END IF;

          -- adjust the  non-methane species for VBS IVOC run
          IF ( runType = vbs ) THEN
             CREATE TABLE tmp_sumnmog AS
             SELECT profile_id, 0.0 AS sum_nmog
             FROM tbl_vbs_ivoc_nmogfactors;
             -- save the non-methane wtpct sum for each profile
             UPDATE tmp_sumnmog
             SET sum_nmog = tmpSum.sum
             FROM ( SELECT profile_id, SUM(percent)
                    FROM tmp_raw_profiles
                    WHERE specie_id != methane
                    GROUP BY profile_id ) AS tmpSum
             WHERE tmp_sumnmog.profile_id = tmpSum.profile_id;

             -- adjust the non-methane weight fractions
             FOR prfRow IN
                 SELECT * FROM tbl_vbs_ivoc_nmogfactors
             LOOP
                 FOR spcRow IN
                     SELECT * FROM tmp_raw_profiles
                     WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
                       AND specie_id != methane
                 LOOP
                     UPDATE tmp_raw_profiles
                     SET percent = (1. - prfRow.nmogfraction) * spcRow.percent
                     WHERE prfRow.profile_id = tmp_raw_profiles.profile_id
                       AND spcRow.specie_id = tmp_raw_profiles.specie_id;

                 END LOOP; --spcRow
             END LOOP; --prfRow


             -- now insert the IVOC component
             FOR prfRow IN
                 SELECT * FROM tbl_vbs_ivoc_nmogfactors
             LOOP
                 IF ( runAQM = cmaq ) THEN
                     ivocname := prfRow.cmaq_ivocname;
                 ELSE
                     ivocname := prfRow.camx_ivocname;
                 END IF;
       
                 INSERT INTO tmp_raw_profiles (profile_id,specie_id,percent)
                 SELECT prfRow.profile_id, ivocname, prfRow.nmogfraction * s.sum_nmog
                 FROM tmp_sumnmog s
                 WHERE prfRow.profile_id = s.profile_id;
              END LOOP;

          END IF; -- vbs run profile adjustments

          -- copy the renormalized raw profiles to the working profile table tmp_prfwts
          INSERT INTO tmp_prfwts (profile_id, specie_id, percent)
          SELECT profile_id, specie_id, percent
          FROM tmp_raw_profiles;

          -- for the INTEGRATE case delete all HAPS from profile and renormalize --
          IF ( runType = integrate OR runType = nointegrate )  THEN
                
             -- check for profiles with 100% active toxics
             INSERT INTO tmp_actox (profile_id, sum_pct)
             SELECT profile_id, SUM(tmp_prfwts.percent)
             FROM tmp_prfwts, tbl_toxics
             WHERE tmp_prfwts.specie_id = tbl_toxics.specie_id
               AND tbl_toxics.active = 'A'
               AND tbl_toxics.aqm_model = runAQM 
             GROUP BY profile_id;

             DELETE FROM tmp_actox
             WHERE tmp_actox.sum_pct < 100.;
          END IF;
 
          IF ( runType = integrate )  THEN

              -- prepare nonhaptog header entry
              --TRUNCATE TABLE tmp_header;	
              FOR spcRow IN
                  SELECT * FROM tbl_invtable
                  WHERE  voc = 'V' 
                     OR  voc = 'T'
              LOOP
                  IF ( spcRow.mode = '' ) THEN
                     eminv := spcRow.eminv_poll;
                  ELSE
                     eminv := spcRow.mode || '__' || spcRow.eminv_poll;
                  END IF;
       
                  INSERT INTO tmp_header (specie_id,aqminv_poll)
                  VALUES (spcRow.specie_id,eminv);
              END LOOP;
 
              FOR hapRow IN
                  SELECT * FROM tmp_haps
              LOOP
                  DELETE FROM tmp_prfwts
                  WHERE tmp_prfwts.specie_id = hapRow.specie_id;
              END LOOP;  -- hapRow

              -- renormalize after removing the HAPS for INTEGRATE case --
              TRUNCATE TABLE tmp_sums;
              INSERT INTO tmp_sums (profile_id, sum_pct)
              SELECT DISTINCT profile_id, SUM(percent)
              FROM tmp_prfwts
              GROUP BY profile_id;

              UPDATE tmp_prfwts 
              SET percent = ( tmp_prfwts.percent / tmp_sums.sum_pct ) * 100.
              FROM tmp_sums
              WHERE tmp_prfwts.profile_id = tmp_sums.profile_id;
          END IF;  -- runType = integrate

          -- for the NOINTEGRATE case, delete ACTIVE HAPS species --
          IF ( runType = nointegrate )  THEN
         
              FOR hapRow IN
                 SELECT * from tmp_haps, tbl_toxics
                 WHERE tmp_haps.specie_id = tbl_toxics.specie_id
                   AND tbl_toxics.active  = 'A'
                   AND tbl_toxics.aqm_model  = runAQM 
              LOOP
 
                 DELETE FROM tmp_prfwts
                 WHERE tmp_prfwts.specie_id = hapRow.specie_id;
              END LOOP;  -- hapRow
          END IF;

  	  ------------------------------------------------------------------------------

          -- establish calculations by profile_id, specie_id, aqm_poll --
          RAISE NOTICE '...calculating moles per gram emissions' ;
          FOR prfRow IN
              SELECT  DISTINCT profile_id   
              FROM tmp_prfwts
          LOOP

             -- invalid or zero MWs have been deleted from tmp_prfwts
             UPDATE tmp_prfwts 
             SET moles = ( tmp_prfwts.percent / 100.) / tmp_species.volatile_mw
             FROM tmp_species
             WHERE tmp_prfwts.profile_id = prfRow.profile_id
               AND tmp_prfwts.specie_id  = tmp_species.specie_id;
        		
             -- determine the mole based weight fractions --
             FOR wtsRow IN
                SELECT *
                FROM tmp_prfwts, tmp_species
                WHERE tmp_prfwts.profile_id = prfRow.profile_id
                  AND tmp_prfwts.specie_id = tmp_species.specie_id
             LOOP

                 FOR aqmRow IN
                    SELECT *
                    FROM tmp_mechanism
                    WHERE tmp_mechanism.mechanism = runMechanism
                      AND tmp_mechanism.specie_id = wtsRow.specie_id
                 LOOP
  
                    molesPerGramEm := wtsRow.percent / 100.0 
       				* aqmRow.moles_per_mole / wtsRow.volatile_mw;

                    INSERT INTO tmp_calcs_byspc (mechanism, profile_id, specie_id, 
       						aqm_poll, moles_per_gram )
                    VALUES (aqmRow.mechanism, wtsRow.profile_id, aqmRow.specie_id,
       					aqmRow.aqm_poll, molesPerGramEm);

                 END LOOP;  --- aqmRow

             END LOOP;  --- wtsRow

          END LOOP;  --- prfRow

          -- update the mole based percents based on profile sums --
          RAISE NOTICE '...calculating mole percent' ;
          TRUNCATE TABLE tmp_sums;
          INSERT INTO tmp_sums (profile_id, sum_pct)
          SELECT DISTINCT profile_id, SUM(moles)
          FROM tmp_prfwts
          GROUP BY profile_id;

          UPDATE tmp_prfwts 
          SET moles_pct = tmp_prfwts.moles / tmp_sums.sum_pct 
          FROM tmp_sums
          WHERE tmp_prfwts.profile_id = tmp_sums.profile_id;

          -- calculate the moles model species per moles emissions ---
          RAISE NOTICE '...calculating moles per mole emissions' ;
          UPDATE tmp_calcs_byspc 
          SET moles_per_mole_em = moles_pct * moles_per_mole
          FROM tmp_prfwts, tmp_mechanism
          WHERE tmp_calcs_byspc.profile_id = tmp_prfwts.profile_id
            AND tmp_calcs_byspc.specie_id  = tmp_prfwts.specie_id
            AND tmp_calcs_byspc.specie_id  = tmp_mechanism.specie_id
            AND tmp_calcs_byspc.aqm_poll   = tmp_mechanism.aqm_poll
            AND tmp_mechanism.mechanism    = runMechanism;


          --  sum the moles_per_gram and moles_per_mole_em values over all species by aqm_poll ---
          RAISE NOTICE '...summing on AQM pollutant' ;
          INSERT INTO tmp_calcs_byaqm 
              (mechanism, profile_id, aqm_poll, moles_per_gram, moles_per_mole_em)
          SELECT DISTINCT mechanism, profile_id, aqm_poll, 
                          SUM(moles_per_gram), SUM(moles_per_mole_em)
          FROM tmp_calcs_byspc
          GROUP BY mechanism, profile_id, aqm_poll
          HAVING SUM(moles_per_gram) > 0.;

          -- calculate the mole weight percent  ---
          RAISE NOTICE '...calculating mole weight percent' ;
          UPDATE tmp_calcs_byspc 
          SET mole_wtpct = tmp_calcs_byspc.moles_per_mole_em / tmp_calcs_byaqm.moles_per_mole_em
          FROM tmp_calcs_byaqm
          WHERE tmp_calcs_byspc.profile_id = tmp_calcs_byaqm.profile_id
            AND tmp_calcs_byspc.aqm_poll = tmp_calcs_byaqm.aqm_poll;
 
          --  calculate the average molecular weight of aqm_poll ---
          RAISE NOTICE '...calculating average molecular weight by species' ;
          UPDATE tmp_calcs_byspc 
          SET gram_per_mole = tmp_species.volatile_mw * tmp_aqm_carbons.num_carbons 
                              / tmp_species_carbons.num_carbons,
              avg_mw = tmp_species.volatile_mw 
        			* tmp_aqm_carbons.num_carbons / tmp_species_carbons.num_carbons
        			* tmp_calcs_byspc.mole_wtpct
          FROM tmp_species, tmp_species_carbons, tmp_aqm_carbons
          WHERE tmp_calcs_byspc.specie_id = tmp_species.specie_id
            AND tmp_calcs_byspc.specie_id = tmp_species_carbons.specie_id
            AND tmp_calcs_byspc.aqm_poll = tmp_aqm_carbons.aqm_poll
            AND tmp_aqm_carbons.mechanism = runMechanism;

          -- calculate the average molecular weight of aqm_poll ---
          RAISE NOTICE '...calculating average molecular weight by AQM' ;
          UPDATE tmp_calcs_byaqm
          SET avg_mw = tmp_avg.sum
          FROM (SELECT mechanism, profile_id, aqm_poll, SUM(avg_mw) 
          FROM tmp_calcs_byspc
          GROUP BY mechanism, profile_id, aqm_poll ) AS tmp_avg
          WHERE tmp_calcs_byaqm.profile_id = tmp_avg.profile_id
            AND tmp_calcs_byaqm.aqm_poll = tmp_avg.aqm_poll;

        END IF; -- not haplist
-------------------------------------------------------------------------------------------
        --  now we add the HAPS --

        IF ( runType = haplist )  THEN
           RAISE NOTICE '...processing VOC HAPs that define the calculation of NONHAPVOC' ;

           FOR hapRow IN
              SELECT * FROM tmp_haps
           LOOP
              FOR aqmRow IN
                  SELECT * FROM tbl_mechanism
                  WHERE tbl_mechanism.specie_id = hapRow.specie_id
                    AND tbl_mechanism.mechanism = runMechanism
                    AND tbl_mechanism.moles_per_mole > 0.0
              LOOP

                  INSERT INTO tmp_calcs_haps
                  (mechanism, profile_id, specie_id, 
                  eminv_poll, aqm_poll, moles_per_mole)
                  VALUES (runMechanism, '0000', hapRow.specie_id,
                  hapRow.aqminv_poll, aqmRow.aqm_poll, aqmRow.moles_per_mole);

              END LOOP;  -- aqmRow
           END LOOP;  -- hapRow

           IF ( flagMech = 'Y' ) THEN
              FOR toxRow IN
                  SELECT * from tbl_toxics
                  WHERE active = 'A'
                    AND aqm_model = runAQM 
              LOOP

                  DELETE FROM tmp_calcs_haps
                  WHERE tmp_calcs_haps.specie_id = toxRow.specie_id;
              END LOOP;  -- toxRow

        
              FOR toxRow IN
                  SELECT * from tbl_toxics, tmp_haps
                  WHERE tbl_toxics.specie_id = tmp_haps.specie_id
                    AND tbl_toxics.aqm_model = runAQM 
              LOOP

                  toxoverwrite := 'N';
                  FOR primeRow IN
                      SELECT aqminv_poll, writeflag
                      FROM tbl_primary
                      GROUP BY aqminv_poll, writeflag
                      HAVING writeflag = 'Y'
                  LOOP     

                      IF ( toxRow.aqminv_poll = primeRow.aqminv_poll ) THEN
                         toxoverwrite := 'Y';
                         RAISE NOTICE 'WARNING: Overwrite toxic specie name:  %', primeRow.aqminv_poll;
                      END IF;

                  END LOOP; -- primeRow
       
                  IF ( toxoverwrite = 'N' ) THEN

                     IF ( toxRow.active = 'T' ) THEN
                        eminvPoll := toxRow.aqminv_poll || '_NOI';
                        INSERT INTO tmp_calcs_haps
                               (mechanism, profile_id, specie_id, 
                                eminv_poll, aqm_poll, moles_per_mole)
                        VALUES (runMechanism, '0000', toxRow.specie_id,
                                eminvPoll, toxRow.aqm_poll, 1.0 );
                     END IF;

                     eminvPoll := toxRow.aqminv_poll;

                     INSERT INTO tmp_calcs_haps
                            (mechanism, profile_id, specie_id, 
                                  eminv_poll, aqm_poll, moles_per_mole)
                     VALUES (runMechanism, '0000', toxRow.specie_id,
                                  eminvPoll, toxRow.aqm_poll, 1.0 );

                  END IF;
              END LOOP; -- toxRow
        
              -- add toxic entry from primary_file
 
              FOR primeRow IN
                 SELECT *  FROM tbl_primary, tmp_haps, tbl_toxics
                 WHERE tmp_haps.aqminv_poll = tbl_primary.aqminv_poll
                   AND tbl_toxics.specie_id = tmp_haps.specie_id
                   AND tbl_toxics.aqm_model = runAQM	
              LOOP
  
                IF (  primeRow.active = 'T' )  THEN

                   eminvPoll := primeRow.aqminv_poll || '_NOI';
                   INSERT INTO tmp_calcs_haps
       			(mechanism, profile_id, specie_id, 
       			eminv_poll, aqm_poll, moles_per_mole)
                   VALUES (runMechanism, '0000', primeRow.specie_id,
       			eminvPoll, primeRow.aqm_add, primeRow.split_factor );
                END IF;

                eminvPoll := primeRow.aqminv_poll;
                INSERT INTO tmp_calcs_haps
                       (mechanism, profile_id, specie_id, 
                       eminv_poll, aqm_poll, moles_per_mole)
                VALUES (runMechanism, '0000', primeRow.specie_id,
                       eminvPoll, primeRow.aqm_add, primeRow.split_factor );

              END LOOP; -- primeRow
           END IF; -- flagMech
 
           -- calculate the average molecular weight for each HAPS --
           UPDATE tmp_calcs_haps
           SET moles_per_gram = tmp_calcs_haps.moles_per_mole / tmp_species.volatile_mw
           FROM tmp_species
           WHERE tmp_calcs_haps.specie_id = tmp_species.specie_id;


           FOR primeRow IN
              SELECT * from tbl_primary
           LOOP
              UPDATE tmp_calcs_haps
              SET avg_mw = tmp_species.volatile_mw
              FROM tmp_species
              WHERE tmp_calcs_haps.specie_id = tmp_species.specie_id
                AND tmp_calcs_haps.aqm_poll  = primeRow.aqm_add;

           END LOOP; -- primeRow

           FOR toxRow IN
              SELECT * from tbl_toxics
              WHERE aqm_model = runAQM
           LOOP
              UPDATE tmp_calcs_haps
              SET avg_mw = tmp_species.volatile_mw
              FROM tmp_species
              WHERE tmp_calcs_haps.specie_id = tmp_species.specie_id
                AND tmp_calcs_haps.aqm_poll  = toxRow.aqm_poll;

           END LOOP; -- toxRow


           FOR hapRow IN
              SELECT *
              FROM tmp_calcs_haps
              WHERE tmp_calcs_haps.avg_mw isNull
           LOOP

              INSERT INTO tmp_calcs_haps_null
                     (mechanism, profile_id, specie_id, eminv_poll, aqm_poll)
              VALUES (hapRow.mechanism, hapRow.profile_id, hapRow.specie_id,
                     hapRow.eminv_poll, hapRow.aqm_poll);
           END LOOP;
       
           FOR hapRow IN
               SELECT *
               FROM tmp_calcs_haps_null
           LOOP
               UPDATE tmp_calcs_haps
               SET avg_mw = tmp_species.volatile_mw
                            * tmp_aqm_carbons.num_carbons
                            / tmp_species_carbons.num_carbons
               FROM tmp_species, tmp_aqm_carbons, tmp_species_carbons
               WHERE hapRow.mechanism = tmp_calcs_haps.mechanism
                 AND hapRow.specie_id = tmp_calcs_haps.specie_id
                 AND hapRow.eminv_poll = tmp_calcs_haps.eminv_poll
                 AND hapRow.aqm_poll = tmp_calcs_haps.aqm_poll
                 AND hapRow.specie_id = tmp_species.specie_id
                 AND hapRow.mechanism = tmp_aqm_carbons.mechanism
                 AND hapRow.aqm_poll = tmp_aqm_carbons.aqm_poll
                 AND hapRow.mechanism = tmp_species_carbons.mechanism
                 AND hapRow.specie_id = tmp_species_carbons.specie_id;
           END LOOP;  -- hapRow

        END IF;   -- insert HAPS for haplist 

    END IF;  -- voc case
RETURN;
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION Calcs_CreateTempTables() RETURNS INTEGER AS
$$
DECLARE
    runName               TEXT;

BEGIN

     -- get the run name from the control table --
      SELECT  INTO runName dataval
      FROM  tbl_run_control
      WHERE tbl_run_control.keyword = 'RUN_NAME';

    -- Table tmp_raw_profiles, copy of either tbl_gas_profile_weights or tbl_user_prof 
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_raw_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_raw_profiles;
    END IF;
    CREATE TABLE tmp_raw_profiles
    (
        profile_id         VARCHAR(20), 
        specie_id          VARCHAR(20), 
        percent            NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_raw_profiles
           ON tmp_raw_profiles (profile_id, specie_id);

    -- Table tmp_prfwts to carry the profile weights, renormalized for haps
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_prfwts'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_prfwts;
    END IF;
    CREATE TABLE tmp_prfwts
    (
        profile_id         VARCHAR(20), 
        specie_id          VARCHAR(20), 
        percent            NUMERIC(15,8),
        moles              NUMERIC(15,8),
        moles_pct          NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_prfwts
           ON tmp_prfwts (profile_id, specie_id);

    -- Table tmp_mechanism to carry the run mechanism definition
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_mechanism'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_mechanism;
    END IF;
    CREATE TABLE tmp_mechanism
    (
        mechanism          VARCHAR(20), 
        specie_id          VARCHAR(20), 
        aqm_poll           VARCHAR(20), 
        moles_per_mole     NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_mechanism
           ON tmp_mechanism (mechanism, specie_id, aqm_poll);

    -- Table tmp_aqm_carbons 
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_aqm_carbons'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_aqm_carbons;
    END IF;
    CREATE TABLE tmp_aqm_carbons
    (
        mechanism          VARCHAR(20), 
        aqm_poll           VARCHAR(20),
        num_carbons        NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_aqm_carbons
           ON tmp_aqm_carbons (mechanism, aqm_poll);

    -- Table tmp_species_carbons to carry number of carbons by species by mechanism
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_species_carbons'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_species_carbons;
    END IF;
    CREATE TABLE tmp_species_carbons
    (
        mechanism          VARCHAR(20), 
        specie_id          VARCHAR(20),
        num_carbons        NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_species_carbons
           ON tmp_species_carbons (mechanism, specie_id);

    -- Table tmp_calcs_byspc carries calculations by mechanism, profile, specie, aqmpoll
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_calcs_byspc'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_calcs_byspc;
    END IF;
    CREATE TABLE tmp_calcs_byspc
    (
        mechanism          VARCHAR(20), 
        profile_id         VARCHAR(20), 
        specie_id          VARCHAR(20),
        aqm_poll           VARCHAR(20),
        moles_per_gram     NUMERIC(15,8),
        moles_per_mole_em  NUMERIC(15,8),
        mole_wtpct         NUMERIC(15,8),
        gram_per_mole      NUMERIC(15,8),
        avg_mw             NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_calcs_byspc
           ON tmp_calcs_byspc (mechanism, profile_id, specie_id, aqm_poll);

    -- Table tmp_calcs_byaqm carries calculations by mechanism, profile, specie
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_calcs_byaqm'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_calcs_byaqm;
    END IF;
    CREATE TABLE tmp_calcs_byaqm
    (
        mechanism          VARCHAR(20), 
        profile_id         VARCHAR(20), 
        aqm_poll           VARCHAR(20),
        moles_per_gram     NUMERIC(15,8),
        moles_per_mole_em  NUMERIC(15,8),
        avg_mw             NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_calcs_byaqm
           ON tmp_calcs_byaqm (mechanism, profile_id, aqm_poll);


    -- Table tmp_calcs_haps   carries the HAPS calcs
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_calcs_haps'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_calcs_haps;
    END IF;
    CREATE TABLE tmp_calcs_haps
    (
        mechanism          VARCHAR(20), 
        profile_id         VARCHAR(20), 
        specie_id          VARCHAR(20), 
        eminv_poll         VARCHAR(20),
        aqm_poll           VARCHAR(20),
        moles_per_mole     NUMERIC(15,8),
        moles_per_gram     NUMERIC(15,8),
        avg_mw             NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_calcs_haps
           ON tmp_calcs_haps (mechanism, profile_id, specie_id, eminv_poll, aqm_poll);


    -- Table tmp_calcs_haps_null   carries the HAPS calcs
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_calcs_haps_null'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_calcs_haps_null;
    END IF;
    CREATE TABLE tmp_calcs_haps_null
    (
        mechanism          VARCHAR(20), 
        profile_id         VARCHAR(20), 
        specie_id          VARCHAR(20), 
        eminv_poll         VARCHAR(20),
        aqm_poll           VARCHAR(20),
        moles_per_mole     NUMERIC(15,8),
        moles_per_gram     NUMERIC(15,8),
        avg_mw             NUMERIC(15,8)
    );

    CREATE UNIQUE INDEX idx_tmp_calcs_haps_null
           ON tmp_calcs_haps_null (mechanism, profile_id, specie_id, eminv_poll, aqm_poll);


    -- Table tmp_sums
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_sums'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_sums;
    END IF;
    CREATE TABLE tmp_sums
    (
        profile_id         VARCHAR(20), 
        sum_pct            NUMERIC(12,8)
    );
    CREATE UNIQUE INDEX idx_tmp_sums
           ON tmp_sums (profile_id);


    -- Table tmp_actox
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_actox'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_actox;
    END IF;
    CREATE TABLE tmp_actox
    (
        profile_id         VARCHAR(20), 
        sum_pct            NUMERIC(12,8)
    );

    CREATE UNIQUE INDEX idx_tmp_actox
           ON tmp_actox (profile_id);

    -- Table tmp_qa_carbons
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_qa_carbons'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_qa_carbons;
    END IF;
    CREATE TABLE tmp_qa_carbons
    (
        aqm_poll         VARCHAR(20)
    );

    -- Table tmp_header
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_header'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_header;
    END IF;
    CREATE TABLE tmp_header
    (
        specie_id          VARCHAR(20), 
        aqminv_poll         VARCHAR(20)
    );

    -- Table tmp_haps
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_haps'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_haps;
    END IF;
    CREATE TABLE tmp_haps
    (
        specie_id          VARCHAR(20), 
        aqminv_poll         VARCHAR(20)
    );
    CREATE UNIQUE INDEX idx_tmp_haps
           ON tmp_haps (specie_id,aqminv_poll);

     CREATE TABLE tmp_error (error VARCHAR(20));
     CREATE TABLE tmp_spcinp (specie_id VARCHAR(20), mw VARCHAR(20));
    RETURN 0;
END;
$$
LANGUAGE plpgsql;

