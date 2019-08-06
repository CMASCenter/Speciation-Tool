-- Filename   : make_pm_splits.sql
-- Author     : Michele Jimenez, ENVIRON International Corp. 
-- Version    : Speciation Tool 4.0
-- Release    : 12 Sep 2016
--
--  Generate and fill the temporary tables used to determine
--  the PM2.5 split factors.  Notices are displayed indicating the progress
--  of execution.
--
--   Updates:	June 2016 	Support CAMx PM mechanism CF
--              Sep 2016	Add VBS (Volatility Basis Set) SVOC option
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

CREATE OR REPLACE FUNCTION MakePMSplits() RETURNS VOID AS
$$
DECLARE

    prfRow                    RECORD;
    spcRow                    RECORD;
    facRow                    RECORD;

    runMechanism             TEXT; 
    runType                  TEXT; 
    runAQM                   TEXT; 
    runOut                   TEXT; 
    runUsrProf               TEXT;
    eminv                    TEXT;
    pmOther                  TEXT;
    svocname                 TEXT;
    nameout                  TEXT;

    version                  TEXT;
    criteria   	             TEXT;
    vbs                      TEXT;
    camx                     TEXT;
    cmaq                     TEXT;
    tmpInteger               INTEGER;

----------------------------------------------------------------------------------

BEGIN

        version := 'Speciation Tool v4.0';

 -- check to proceed PM speciation -- 
     -- get the list of output requirements from the control table --
        SELECT  INTO runOut dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'OUTPUT';
        runOut := UPPER(runOut);

-----------------------------------------------------------------------------------------

 IF ( runOut LIKE '%PM%')  THEN
        RAISE NOTICE '======== % ========', version;
        RAISE NOTICE '  ' ; 

        RAISE NOTICE 'Type of Output is  % ', runOut;

     -- Set up the temporary tables required for the calculations --
        tmpInteger := Calcs_CreateTempPMTables();

     -- get the run air quality model (AQM) from the control table --
        SELECT  INTO runAQM dataval 
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'AQM';
        runAQM := UPPER(runAQM);

     -- initialize run types --
	criteria := 'CRITERIA';
	vbs      := 'VBS';
	camx     := 'CAMX';
        cmaq     := 'CMAQ';

     -- get the run type from the control table --
	SELECT  INTO runType dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'RUN_TYPE';
	runType := UPPER(runType);
        IF ( runType LIKE criteria ) THEN
	    RAISE NOTICE 'Type of run is  % ', runType;
	ELSIF ( runType LIKE vbs ) THEN
	    RAISE NOTICE 'Type of run is CRITERIA with % ', runType;
        ELSE
	    RAISE NOTICE 'Type of run is  % ', runType;
	    RAISE NOTICE 'ERROR:  Only CRITERIA and VBS are supported for PM outputs.  Change run type and rerun. ';
            INSERT INTO tmp_error(error,description)
                   VALUES ('error','Invalid RUN_TYPE specified in run_control for PM processing');
	    RETURN;
        END IF;

     -- get the mechanism basis for this run --
	SELECT  INTO runMechanism dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'MECH_BASIS';
	runMechanism := UPPER(runMechanism);
	RAISE NOTICE 'Mechanism basis is  % ', runMechanism;

     -- determine if user specified profile weights --
	SELECT  INTO runUsrProf dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'PRO_FILE';

  ---------------------------------------------------------------------------------------
  -- check on width of output pollutant names
      -- Case A Valid length is 7 such as EXH_BENZENE_NOI
	CREATE TABLE tmp_invtable AS
  		SELECT eminv_poll 
		FROM tbl_invtable
		WHERE tbl_invtable.mode != ''  
		  AND tbl_invtable.model = 'Y'
		  AND (tbl_invtable.voc != 'V' AND tbl_invtable.voc != 'T')
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
                INSERT INTO tmp_error(error,description)
                       VALUES ('error','Output pollutant name exceeds 16-char maximum.');
		RETURN;
	END IF;


  -----------------------------------------------------------------------------------------
      -- extract PM mechanism to process --
        CREATE TABLE tmp_pm_mechanism AS
               SELECT m.*
               FROM tbl_pm_mechanism m
               WHERE m.mechanism = runMechanism;

      -- determine if the mechanism definition does not contain one and only one pollutant to be computed --
                SELECT INTO tmpInteger COUNT(*) 
                FROM tmp_pm_mechanism m
                WHERE m.compute
                  AND NOT m.aqm_poll IsNull
                  AND (m.specie_id Is Null OR m.specie_id = '');

	IF ( tmpInteger <> 1 )  THEN
		RAISE NOTICE 'ERROR review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'ERROR: Mechanism definition must contain one, and only one, ' ;
                RAISE NOTICE '       AQM pollutant flagged to be computed (with null species_id).' ;
		RAISE NOTICE 'ERROR review and correct   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
                INSERT INTO tmp_error(error,description)
                       VALUES ('error','PM mechanism definition error.');
                RETURN;
	END IF;

      -- determine if the mechanism definition contains any species_id with no match in species table --
	CREATE TABLE tmp_qa_mechanism AS
                SELECT m.*
                FROM tmp_pm_mechanism m
                LEFT JOIN tbl_species s ON m.specie_id = s.specie_id
                WHERE NOT m.compute
                  AND s.specie_id Is Null;

	SELECT INTO tmpInteger COUNT(*) 
	FROM tmp_qa_mechanism;

	IF ( tmpInteger > 0 )  THEN
		RAISE NOTICE 'ERROR review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'ERROR: Mechanism contains species that are missing from species table (tbl_species).' ;

		FOR spcRow IN 
			SELECT * FROM tmp_qa_mechanism
		LOOP    
			RAISE NOTICE 'ERROR:           SPECIES ID  %', spcRow.specie_id;

		END LOOP;
		RAISE NOTICE 'ERROR review and correct   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ' ;
                INSERT INTO tmp_error(error,description)
                       VALUES ('error','No species found for component of PM mechanism.');
                RETURN;
	END IF;

  -----------------------------------------------------------------------------------------
     -- Establish the mechanism ------------------------------------------------------
     -- set up the temporary mechanism table
     -- implied WHERE mechanism = runMechanism, since FROM table has the condition
	RAISE NOTICE '...establishing mechanism' ;
	INSERT INTO tmp_mechanism
			(mechanism, specie_id, aqm_poll, qualify )
		SELECT mechanism, specie_id, aqm_poll, qualify
		FROM tmp_pm_mechanism
		WHERE NOT compute;

     -- get the AQM pollutant to assign remainder of PMs
	SELECT  INTO pmOther aqm_poll
	FROM  tmp_pm_mechanism
	WHERE compute;

  -----------------------------------------------------------------------------------------
     -- Establish the profile weights -----------------------------------------------------
     -- set up the temporary profile weights table ---

	-- first, generate a list of profile ids that qualify --
	RAISE NOTICE '...establishing profile weights' ;

	-- either use the shared profile weights or the user specified --
	IF ( runUsrProf ISNULL )  THEN
		INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
                        SELECT w.profile_id, w.specie_id, w.percent
                        FROM tbl_pm_profiles p
                        INNER JOIN tbl_pm_profile_weights w ON p.profile_id = w.profile_id
                        WHERE p.lower_size = 0.0
                          AND p.upper_size = 2.5;
	ELSE
		INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
                        SELECT profile_id, specie_id, percent
                        FROM tbl_user_profile_wts w;
	END IF;

	-- determine the unique set of profiles to process --
        -- and the weight percent sum of each profile for all non-computed mechanism compounds -- 
	RAISE NOTICE '...calculating weight percent sum of mechanism compounds' ;

        INSERT INTO tmp_profile_list (profile_id)
                        SELECT DISTINCT profile_id
                        FROM tmp_mechanism m
                        INNER JOIN tmp_raw_profiles w
                              ON m.specie_id = w.specie_id
                        GROUP BY m.qualify, w.profile_id
                        HAVING m.qualify = true;

        INSERT INTO tmp_sums (profile_id, sum_pct)
                      SELECT DISTINCT  p.profile_id, SUM(w.percent)
                      FROM tmp_mechanism m
                      INNER JOIN tmp_raw_profiles w ON m.specie_id = w.specie_id
                      INNER JOIN tmp_profile_list p ON p.profile_id = w.profile_id
                      GROUP BY p.profile_id;

	--  warning if weight profiles exceed 100 percent for the non-computed compounds --
	SELECT INTO tmpInteger COUNT(*) 
		FROM tmp_sums
                WHERE TRUNC(sum_pct) > 100.;
	IF ( tmpInteger > 0 )  THEN
		RAISE NOTICE 'WARNING review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'WARNING: The following profiles are invalid and will be excluded from processing.  ' ;
		RAISE NOTICE 'WARNING: Total weight percent of qualifying compounds is greater than 100 percent.' ;

		FOR prfRow IN 
			SELECT t.*, substring(p.profile_name from 1 for 50) AS profile_name
                            FROM tmp_sums t, tbl_pm_profiles p
                            WHERE t.profile_id = p.profile_id
                              AND TRUNC(sum_pct) > 100.
		LOOP    
			RAISE NOTICE 'WARNING: PROFILE  %  Percent %  %', prfRow.profile_id, prfRow.sum_pct, prfRow.profile_name;

		END LOOP;
		RAISE NOTICE 'WARNING review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
                INSERT INTO tmp_error(error,description)
                       VALUES ('warning','Profiles dropped with total weight percent > 100.');
	END IF;

--	-- delete records from profile list if weight percent sums exceed 100 percent --
	DELETE FROM tmp_sums
		WHERE TRUNC(sum_pct,0) > 100;

	--  warning if a profile has an element with negative weight percent --
	SELECT INTO tmpInteger COUNT(*) 
		FROM tmp_raw_profiles w
                INNER JOIN tmp_sums p ON w.profile_id = p.profile_id
                WHERE w.percent < 0.0;
	IF ( tmpInteger > 0 )  THEN
		RAISE NOTICE 'WARNING review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'WARNING: The following profiles are invalid and will be excluded from processing.  ' ;
		RAISE NOTICE 'WARNING: They contain an element with a negative weight percent.' ;

		FOR prfRow IN 
	                SELECT p.profile_id, w.specie_id, substring(t.profile_name from 1 for 50) AS profile_name, w.percent
                		FROM tmp_sums p 
                                INNER JOIN tbl_pm_profiles t  ON p.profile_id = t.profile_id
                                INNER JOIN tmp_raw_profiles w ON p.profile_id = w.profile_id
                                                              AND w.percent < 0.0
		LOOP    
			RAISE NOTICE 'WARNING:    PROFILE  %  Species % Percent %', prfRow.profile_id, prfRow.specie_id, prfRow.percent;
			RAISE NOTICE '                     %', prfRow.profile_name;

		END LOOP;
		RAISE NOTICE 'WARNING review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
                INSERT INTO tmp_error(error,description)
                       VALUES ('warning','Profiles dropped containing a component with a negative weight percent.');
	END IF;

	-- delete records from profile list if weight percent sums are negative --
	DELETE FROM tmp_sums 
		WHERE profile_id IN 
		(SELECT w.profile_id FROM tmp_raw_profiles w 
		 INNER JOIN tmp_sums p ON w.profile_id = p.profile_id WHERE w.percent < 0.0);

  -----------------------------------------------------------------------------------------

        -- generate PM split factors, for profiles in tmp_profile_list -- 
 	-- extract only specie_ids that match mechanism definition     --
	-- convert weight percents to weight fractions                 --

	INSERT INTO tmp_pm_splits (profile_id, eminv_poll, aqm_poll, fraction)
		SELECT t.profile_id, 'PM2_5', m.aqm_poll, p.percent/100.
		FROM tmp_raw_profiles p, tmp_sums t, tmp_mechanism m
                WHERE p.profile_id = t.profile_id
                  AND p.specie_id = m.specie_id;

        -- for each profile, compute the remainder = 1 - sum(mechanism definition compounds)
	INSERT INTO tmp_pm_splits (profile_id, eminv_poll, aqm_poll, fraction)
		SELECT t.profile_id, 'PM2_5', pmOther, 1.0-(t.sum_pct/100.0)
		FROM tmp_sums t
                WHERE t.sum_pct < 100. ;

  -----------------------------------------------------------------------------------------
	-- adjust AE6 if generating CAMX PM --
	IF ( runAQM = 'CAMX' AND runMechanism = 'AE6' ) THEN
		TRUNCATE tmp_sums;
		INSERT INTO tmp_sums (profile_id,sum_pct)
			SELECT a.profile_id, SUM(a.fraction)
			FROM (SELECT profile_id,eminv_poll,aqm_poll,fraction
				FROM tmp_pm_splits WHERE aqm_poll = 'PNCOM' or aqm_poll = 'POC') a 
			GROUP BY a.profile_id;
		INSERT INTO tmp_camxpm_splits
			(profile_id, eminv_poll, aqm_poll, fraction)
			SELECT profile_id,'PM2_5','POA',sum_pct
			FROM tmp_sums;

		TRUNCATE tmp_sums;
		INSERT INTO tmp_sums 
			(profile_id,sum_pct)
			SELECT a.profile_id, SUM(a.fraction) 
			FROM (SELECT profile_id,eminv_poll,aqm_poll,fraction 
			FROM tmp_pm_splits 
			WHERE aqm_poll  IN ('PFE','PAL','PSI','PTI','PCA','PMG','PK','PMN','PMOTHR') ) a 
			GROUP BY a.profile_id;
		INSERT INTO tmp_camxpm_splits
			(profile_id, eminv_poll, aqm_poll, fraction)
			SELECT profile_id,'PM2_5','FPRM',sum_pct
			FROM tmp_sums;

		INSERT INTO tmp_camxpm_splits 
			(profile_id, eminv_poll, aqm_poll, fraction)
			SELECT  
			profile_id, eminv_poll, aqm_poll, fraction
			FROM tmp_pm_splits
			WHERE aqm_poll IN ('PEC','PH2O','PNH4','PSO4','PNO3','PCL','POC'); 

		INSERT INTO tmp_camxpm_splits 
			(profile_id, eminv_poll, aqm_poll, fraction)
			SELECT  
			profile_id, eminv_poll, 'NA', fraction
			FROM tmp_pm_splits
			WHERE aqm_poll = 'PNA';  

		--  for a subset of profiles change the FPRM to FCRS 
		FOR prfRow IN
			SELECT profile_id from tbl_camx_fcrs
		LOOP    
			UPDATE tmp_camxpm_splits
			SET aqm_poll = 'FCRS'
			WHERE tmp_camxpm_splits.profile_id = prfRow.profile_id
			AND tmp_camxpm_splits.aqm_poll = 'FPRM'; 
		END LOOP;

		-- replace the table
		TRUNCATE tmp_pm_splits;
		INSERT INTO tmp_pm_splits (profile_id, eminv_poll, aqm_poll, fraction)
			SELECT profile_id, eminv_poll, aqm_poll, fraction
			FROM tmp_camxpm_splits;
	END IF; -- CAMXPM
  -----------------------------------------------------------------------------------------
	-- Make profile adjustments for VBS SVOC --
	IF ( runType LIKE vbs ) THEN
		RAISE NOTICE '...checking VBS based profiles' ;

	-- verify that all PM profiles are specified in VBS factors list ---
	SELECT INTO tmpInteger COUNT(*) 
	FROM tmp_profile_list l 
	LEFT JOIN tbl_vbs_svoc_factors v on l.profile_id = v.profile_id
	WHERE v.bin0 IS NULL;

	IF ( tmpInteger > 0 )  THEN
		RAISE NOTICE 'ERROR review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'ERROR: The following profiles are not specified in the VBS SVOC file. ' ;
		RAISE NOTICE 'ERROR: All PM profiles must be defined in the VBS SVOC factor file for a VBS run.' ;

		FOR prfRow IN 
	                SELECT l.profile_id
                	FROM tmp_profile_list l 
                        LEFT JOIN tbl_vbs_svoc_factors v  ON l.profile_id = v.profile_id
			WHERE  v.bin0 IS NULL
		LOOP    
			RAISE NOTICE 'ERROR:    PROFILE  % ', prfRow.profile_id;
		END LOOP;
		RAISE NOTICE 'ERROR review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
                INSERT INTO tmp_error(error,description)
                       VALUES ('ERROR','Missing PM profile IDs from tbl_vbs_svoc_factors.');
		RETURN;
	END IF;

	-- verify that the SVOC factors sum to 1.0 --
	TRUNCATE tmp_sums;
	INSERT INTO tmp_sums (profile_id,sum_pct)
		SELECT profile_id,(bin0+bin1+bin2+bin3+bin4)
		FROM tbl_vbs_svoc_factors;

	SELECT INTO tmpInteger COUNT(*)
	FROM tmp_sums
	WHERE sum_pct != 1.0;

	IF ( tmpInteger > 0 )  THEN
		RAISE NOTICE 'ERROR review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'ERROR: The following VBS SVOC factors do not sum to 1.0.';

		FOR prfRow IN
			SELECT profile_id
			FROM tmp_sums
			WHERE sum_pct != 1.0
		LOOP
			RAISE NOTICE 'ERROR:    PROFILE  % ', prfRow.profile_id;
		END LOOP;
		RAISE NOTICE 'ERROR review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
                INSERT INTO tmp_error(error,description)
                       VALUES ('ERROR','VBS SVOC fractions do not sum to 1.0.');
		RETURN;
	END IF;

	-- insert svocname/factors to temporary table
	RAISE NOTICE '...preparing VBS based profiles' ;
	FOR prfRow IN
		SELECT * 
		FROM tbl_vbs_svoc_factors
	LOOP
		IF ( runAQM = cmaq ) THEN
			svocname := prfRow.cmaq_svocname;
		ELSE
			svocname := prfRow.camx_svocname;
		END IF;
		nameout := svocname || '0';
		INSERT INTO tmp_vbs_svoc_factors (profile_id,aqm_poll,fraction)
		VALUES (prfRow.profile_id,nameout,prfRow.bin0);
		nameout := svocname || '1';
		INSERT INTO tmp_vbs_svoc_factors (profile_id,aqm_poll,fraction)
		VALUES (prfRow.profile_id,nameout,prfRow.bin1);
		nameout := svocname || '2';
		INSERT INTO tmp_vbs_svoc_factors (profile_id,aqm_poll,fraction)
		VALUES (prfRow.profile_id,nameout,prfRow.bin2);
		nameout := svocname || '3';
		INSERT INTO tmp_vbs_svoc_factors (profile_id,aqm_poll,fraction)
		VALUES (prfRow.profile_id,nameout,prfRow.bin3);
		nameout := svocname || '4';
		INSERT INTO tmp_vbs_svoc_factors (profile_id,aqm_poll,fraction)
		VALUES (prfRow.profile_id,nameout,prfRow.bin4);
	END LOOP;

	-- delete records with fraction = 0.0
	DELETE FROM tmp_vbs_svoc_factors
		WHERE fraction = 0;

	-- generate SVOC species from POA
	RAISE NOTICE '...generating VBS SVOC components';

		IF ( runAQM = camx ) THEN
			FOR prfRow IN
				SELECT * 
				FROM tmp_pm_splits
				WHERE aqm_poll = 'POA'
			LOOP
				FOR facRow IN
					SELECT * 
					FROM tmp_vbs_svoc_factors f
					WHERE profile_id = prfRow.profile_id
				LOOP
				  INSERT INTO tmp_pm_splits
						(profile_id, eminv_poll,aqm_poll,fraction)
				  VALUES (prfRow.profile_id,prfrow.eminv_poll,facRow.aqm_poll,prfRow.fraction*facRow.fraction);
				END LOOP;  --facRow
			END LOOP; --prfRow
			DELETE FROM tmp_pm_splits
				WHERE aqm_poll = 'POA';

		ELSE -- assume CMAQ
			TRUNCATE tmp_sums;
        		INSERT INTO tmp_sums (profile_id, sum_pct)
			SELECT DISTINCT  profile_id, SUM(fraction)
			FROM tmp_pm_splits
			WHERE aqm_poll = 'PNCOM' or aqm_poll = 'POC'
			GROUP BY profile_id;
			
			FOR prfRow IN
				SELECT * 
				FROM tmp_sums
			LOOP
				FOR facRow IN
					SELECT * 
					FROM tmp_vbs_svoc_factors f
					WHERE profile_id = prfRow.profile_id
				LOOP
				  INSERT INTO tmp_pm_splits
						(profile_id, eminv_poll,aqm_poll,fraction)
				  VALUES (prfRow.profile_id,'PM2_5',facRow.aqm_poll,prfRow.sum_pct*facRow.fraction);
				END LOOP;  --facRow
			END LOOP; --prfRow
			DELETE FROM tmp_pm_splits
				WHERE aqm_poll = 'PNCOM' or aqm_poll = 'POC';
		END IF; -- camx/cmaq
	RAISE NOTICE '...finished generating VBS SVOC components';
	END IF; -- VBS

  RAISE NOTICE '...completed generating PM profiles';
END IF;  -- PM case
RETURN;
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION Calcs_CreateTempPMTables() RETURNS INTEGER AS
$$
DECLARE
    runName               TEXT;

BEGIN

     -- get the run name from the control table --
	SELECT  INTO runName dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'RUN_NAME';

    -- Table tmp_raw_profiles, copy of either tbl_pm_profile_weights or tbl_user_profile_wts
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

    -- Table tmp_pm_splits to carry the profile weight fractions
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_pm_splits'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_pm_splits;
    END IF;
    CREATE TABLE tmp_pm_splits
    (
        profile_id         VARCHAR(20), 
	eminv_poll         VARCHAR(20),
        aqm_poll           VARCHAR(20), 
        fraction           NUMERIC(17,10)
    );

    CREATE UNIQUE INDEX idx_tmp_pm_splits
           ON tmp_pm_splits (profile_id, eminv_poll, aqm_poll);

    -- Table tmp_mechanism to carry the run mechanism definition, non-computed
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_mechanism'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_mechanism;
    END IF;
    CREATE TABLE tmp_mechanism
    (
        mechanism          VARCHAR(20), 
        specie_id          VARCHAR(20), 
        aqm_poll           VARCHAR(20),
	qualify            BOOLEAN
    );

    CREATE UNIQUE INDEX idx_tmp_mechanism
           ON tmp_mechanism (mechanism, specie_id, aqm_poll);

    -- Table tmp_camxpm_splits to carry the profile weight fractions for CAMx adjusted profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_camxpm_splits'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_camxpm_splits;
    END IF;
    CREATE TABLE tmp_camxpm_splits
    (
        profile_id         VARCHAR(20), 
	eminv_poll         VARCHAR(20),
        aqm_poll           VARCHAR(20), 
        fraction           NUMERIC(17,10)
    );

    CREATE UNIQUE INDEX idx_tmp_camxpm_splits
           ON tmp_camxpm_splits (profile_id, eminv_poll, aqm_poll);

    -- Table tmp_profile_list
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_profile_list'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_profile_list;
    END IF;
    CREATE TABLE tmp_profile_list
    (
        profile_id         VARCHAR(20)
    );
    CREATE UNIQUE INDEX idx_tmp_profile_list
           ON tmp_profile_list (profile_id);

    -- Table tmp_vbs_svoc_factors to carry the VBS SVOC factors by AQM pollutant
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_vbs_svoc_factors'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_vbs_svoc_factors;
    END IF;
    CREATE TABLE tmp_vbs_svoc_factors
    (
        profile_id         VARCHAR(20), 
        aqm_poll           VARCHAR(20), 
        fraction           NUMERIC(17,10)
    );

    CREATE UNIQUE INDEX idx_tmp_vbs_svoc_factors
           ON tmp_vbs_svoc_factors (profile_id, aqm_poll);

    -- Table tmp_sums
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_sums'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_sums;
    END IF;
    CREATE TABLE tmp_sums
    (
        profile_id         VARCHAR(20),
        sum_pct            NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_sums
           ON tmp_sums (profile_id);


     CREATE TABLE tmp_error (error VARCHAR(20),description VARCHAR(200));
    RETURN 0;
END;
$$
LANGUAGE plpgsql;

