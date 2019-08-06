-- Filename   : prep_out.sql
-- Author     : Michele Jimenez, ENVIRON International Corp.
-- Version    : Speciation Tool 4.0
-- Description: Populate tables for output
-- Release    : 12 Sep 2016
--
--  Generate and fill the output tables for smoke
--
--  Modified September 2007
--  Added 'haplist' as run_type to process VOC HAPs that define the calculation of NONHAPVOC 
--  Added metadata header 
--  Enhanced POC to POA conversion assuming poafactor of 0.2 
--  Added VOC-to-VOC entries for QA
--
--  Modified May 2011
--  Extensively modified PM processing; removed POA calculation option, reference
--  tables generated in the make_pm_splits.sql module.
--
--  Modified Sep 2016
--  Enhanced support to CAMx PM processing
--  Enhancements to support VBS IVOC and SVOC compounds
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

SET search_path=shared;

CREATE OR REPLACE FUNCTION PrepOut() RETURNS VOID AS
$$
DECLARE

    prfRow                   RECORD;
    procRow                  RECORD;

    tmpChar                  TEXT;
    runMechanism             TEXT; 
    flagMech                 TEXT;
    runType                  TEXT;
    runAQM                   TEXT;
    runPM                    TEXT;
    runPROC                  TEXT;
    runOut                   TEXT;
    runUsrProf               TEXT;
    aqmPoll                  TEXT;
    fromSpec                 TEXT;
    toSpec                   TEXT;
    poafactor                FLOAT;
    sumTog                   FLOAT;
    sumVoc                   FLOAT;
    factor                   FLOAT;
    tolerance                FLOAT;
    minTol                   FLOAT;
    maxTol                   FLOAT;
    tmpInteger               INTEGER;
    tmpNum                   FLOAT;

BEGIN

        RAISE NOTICE ' Preparing output tables ... '; 
  ----------------------------------------------------------------------------------------
--   Set up the temporary tables required for the calculation
--     tmpInteger := gspro_createtemptables();

  ----------------------------------------------------------------------------------------
--   get the run type from the control table --
	SELECT  INTO runType dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'RUN_TYPE';
	runType := UPPER(runType);

--   get the run air quality model (AQM) from the control table --
	SELECT  INTO runAQM dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'AQM';
	runAQM := UPPER(runAQM);

     -- get the mechanism basis for this run --
	SELECT  INTO runMechanism dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'MECH_BASIS';
	runMechanism := UPPER(runMechanism);

--   get the process mode table --
	SELECT  INTO runPROC dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'PROC_FILE';

--   get the list of output requirements from the control table --
	SELECT  INTO runOut dataval
	FROM  tbl_run_control
	WHERE tbl_run_control.keyword = 'OUTPUT';
	runOut := UPPER(runOut);

     -- determine if user specified profile weights --
        SELECT  INTO runUsrProf dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'PRO_FILE';

     -- get the user specified profile weights tolerance --
        SELECT  INTO tmpChar dataval 
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'TOLERANCE';

        IF ( tmpChar ISNULL )  THEN 
                tolerance := 5.; 
        ELSE    
                tolerance := TO_NUMBER(tmpChar,'99.9');
        END IF; 
        minTol := 100. - tolerance; 
        maxTol := 100. + tolerance; 

    -- get the mechanism database flag 
	SELECT INTO flagMech nonsoaflag 
	FROM tbl_mechanism_description
        WHERE tbl_mechanism_description.mechanism = runMechanism; 

  ----------------------------------------------------------------------------------------
--   generate the table for output to SMOKE GSPRO --     split factors

	IF ( runOut ISNULL OR runOut LIKE '%VOC%')  THEN

	  IF ( runType = 'HAPLIST') THEN
--   		now add the HAPS
		INSERT INTO tmp_gspro
			(profile_id, eminv_poll, aqm_poll, split_factor, divisor, mass_fraction)
			SELECT profile_id, eminv_poll, aqm_poll,
				moles_per_gram*avg_mw, avg_mw, moles_per_gram*avg_mw
			FROM tmp_calcs_haps;

                RAISE NOTICE '    ...completed HAP'; 

	  ELSE
		INSERT INTO tmp_gspro 
			(profile_id, aqm_poll, split_factor, divisor, mass_fraction)
			SELECT profile_id, aqm_poll,
				moles_per_gram*avg_mw, avg_mw, moles_per_gram*avg_mw
			FROM tmp_calcs_byaqm;

		IF ( runType = 'INTEGRATE' )  THEN
			aqmPoll := 'NONHAPTOG';
		ELSE
			aqmPoll := 'TOG';
		END IF;

		UPDATE tmp_gspro
			SET eminv_poll = aqmPoll;

                RAISE NOTICE '    ...completed nonHAP'; 

--		now add the fake 100% active toxics profiles
		IF ( flagMech = 'Y' ) THEN
		IF ( runType = 'INTEGRATE' )  THEN
			aqmPoll := 'NONHAPTOG';
		ELSE
			aqmPoll := 'TOG';
		END IF;

		FOR prfRow IN
			SELECT DISTINCT profile_id
			FROM tmp_actox
		LOOP
		INSERT INTO tmp_gspro
			(profile_id, eminv_poll, aqm_poll, split_factor, divisor, mass_fraction)
                VALUES 
			(prfRow.profile_id, aqmPoll, 'VOC', 0.0, 1.0, 0.0);
		END LOOP;

                RAISE NOTICE '    ...completed 100 percent active toxics'; 
		END IF;

--		now add the voc-to-voc profiles for QA

		IF ( (runtype = 'CRITERIA' OR runtype = 'VBS') AND flagMech = 'Y')  THEN
		--IF (( runType = 'INTEGRATE' OR runtype = 'CRITERIA') AND flagMech = 'Y')  THEN
		FOR prfRow IN
			SELECT DISTINCT profile_id
			FROM tmp_gspro
		LOOP
			INSERT INTO tmp_gspro
			(profile_id, eminv_poll, aqm_poll, split_factor, divisor, mass_fraction)
                VALUES 
			(prfRow.profile_id, 'VOC','VOC', 1.0, 1.0, 1.0);
		END LOOP;

                RAISE NOTICE '    ...completed VOC-to-VOC'; 
	        END IF;
	END IF;  -- end haplist 

      END IF;  -- end VOC

-- process the particulates
-- the particulates are processed in module make_pm_splits.sql

	IF ( runOut LIKE '%PM%')  THEN

		   INSERT INTO tmp_gspro 
			(profile_id, eminv_poll, aqm_poll, split_factor, divisor, mass_fraction)
			SELECT 
                             profile_id, eminv_poll, aqm_poll, fraction, 1.0, fraction
			FROM tmp_pm_splits;

	END IF; -- end PM

--  now add the static profiles
	IF ( runOut LIKE '%STATIC%')  THEN
		INSERT INTO tmp_gspro
			(profile_id, eminv_poll, aqm_poll, split_factor, divisor, mass_fraction)
			SELECT profile_id, eminv_poll, aqm_poll,
				split_factor, divisor, mass_fraction
			FROM tbl_static
			WHERE aq_model ISNULL OR aq_model = ' ' OR aq_model = runAQM;
                RAISE NOTICE '    ...completed static'; 
	END IF;

--  overwrite the aqm name depending on AQM and mechanism
	RAISE NOTICE '    ...rename output AQM pollutants ';
	FOR prfRow IN
	    SELECT * FROM tbl_rename_species
	    WHERE tbl_rename_species.aq_model = runAQM
	      AND tbl_rename_species.mechanism = runMechanism  
	LOOP
		UPDATE tmp_gspro
			SET aqm_poll = prfRow.aqm_poll 
			WHERE aqm_poll = prfRow.eminv_poll;
	END LOOP;

	IF ( flagMech = 'N') THEN
		DELETE FROM tmp_gspro
			WHERE aqm_poll = 'UNK'
			   OR aqm_poll = 'NONSOA';
	END IF;	

  ----------------------------------------------------------------------------------------
--   generate the table for output to SMOKE GSCNV --    tog-voc conversion factors
--      (not needed for STATIC outputs)
      IF ( runOut ISNULL OR runOut LIKE '%VOC%')  THEN

--      use the tmp_prfwts table for the integrate case, where we have renormalized
      IF ( runType != 'HAPLIST' ) THEN
	IF ( runType = 'INTEGRATE' )  THEN

		FOR prfRow IN
			SELECT DISTINCT profile_id
			FROM tmp_raw_profiles
		LOOP

			SELECT INTO sumTog SUM(percent)
			FROM tmp_prfwts
			WHERE tmp_prfwts.profile_id = prfRow.profile_id;

			SELECT INTO sumVoc SUM(percent)
			FROM tmp_prfwts, tbl_species
			WHERE tmp_prfwts.profile_id = prfRow.profile_id
		  	  AND tmp_prfwts.specie_id = tbl_species.specie_id
			  AND NOT tbl_species.non_voctog ;

			IF ( sumVoc ISNULL ) THEN 
				factor = 0.0;
			ELSE 
				factor = sumTog/sumVoc;
			END IF;
			INSERT INTO tmp_gscnv ( from_specie, to_specie, profile_id, cnv_factor )
			VALUES ('NONHAPVOC', 'NONHAPTOG', prfRow.profile_id, factor);
		END LOOP;

	ELSE
--      use the raw profile weights for the nointegrate and allcriteria cases --
		FOR prfRow IN
			SELECT DISTINCT profile_id
			FROM tmp_raw_profiles
		LOOP

			SELECT INTO sumTog SUM(percent)
			FROM tmp_raw_profiles
			WHERE tmp_raw_profiles.profile_id = prfRow.profile_id;

			SELECT INTO sumVoc SUM(percent)
			FROM tmp_raw_profiles, tmp_species
			WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
		  	  AND tmp_raw_profiles.specie_id = tmp_species.specie_id
			  AND NOT tmp_species.non_voctog ;

			IF ( sumVoc ISNULL OR sumVoc = 0.) THEN 
				factor = 0.0;
			ELSE 
				factor = sumTog/sumVoc;
			END IF;
		        
			INSERT INTO tmp_gscnv ( from_specie, to_specie, profile_id, cnv_factor )
			VALUES ('VOC', 'TOG', prfRow.profile_id, factor);
		END LOOP;

	END IF;  -- runtype integrate
      END IF; -- runtype not haplist
      END IF; -- voc gscnv output

-- now append the process__pollutant codes
	IF (( runOut ISNULL OR runOut LIKE '%VOC%') AND ( runPROC IS NOT NULL)) THEN
	
	FOR prfRow IN
		SELECT *
                  FROM tbl_gas_process, tmp_gscnv
                  WHERE tbl_gas_process.profile_id = tmp_gscnv.profile_id
	LOOP

	     FOR procRow IN
		SELECT DISTINCT mode
		FROM tbl_invtable
	     LOOP
		IF (prfRow.process = procRow.mode) THEN
		   fromSpec = prfRow.process || '__' || prfRow.from_specie;
		   toSpec = prfRow.process || '__' || prfRow.to_specie;

		    INSERT INTO tmp_gscnv ( from_specie, to_specie, profile_id, cnv_factor )
			VALUES ( fromSpec, toSpec, prfRow.profile_id, prfRow.cnv_factor );
		END IF;
	     END LOOP;
	END LOOP;

	END IF;

-- create metadata header	
	INSERT INTO tmp_metadataset (keyword, dataval)
	SELECT tbl_metadata.keyword, 'Not Applicable'
	FROM tbl_metadata;

	UPDATE tmp_metadataset 
	SET dataval = runAQM 
	WHERE keyword = 'AQM';
	
	UPDATE tmp_metadataset 
	SET dataval = runMechanism 
	WHERE keyword = 'MECH';
	
        UPDATE tmp_metadataset 
	SET dataval = tbl_metadata.dataval
        FROM tbl_metadata
	WHERE tbl_metadata.keyword = 'INVTABLE'
	  AND tbl_metadata.keyword = tmp_metadataset.keyword;

	IF ( runOut ISNULL OR runOut LIKE '%VOC%')  THEN
	   UPDATE tmp_metadataset 
	   SET dataval = runType 
	   WHERE keyword = 'RUN_TYPE';

	   IF ( runType != 'HAPLIST' ) THEN
              IF ( runUsrProf ISNULL ) THEN
	 	UPDATE tmp_metadataset 
		SET dataval = tbl_metadata.dataval 
                FROM tbl_metadata
		WHERE tbl_metadata.keyword = 'GAS_PROFILES'
	  	AND tbl_metadata.keyword = tmp_metadataset.keyword;
              ELSE
	 	UPDATE tmp_metadataset 
		SET dataval = runUsrProf
		WHERE tmp_metadataset.keyword = 'GAS_PROFILES';
              END IF;
	   END IF;

	   UPDATE tmp_metadataset 
	   SET dataval = tbl_metadata.dataval
           FROM tbl_metadata
	   WHERE tbl_metadata.keyword = 'CARBONS'
	     AND tbl_metadata.keyword = tmp_metadataset.keyword;

	   IF ( runType = 'VBS' ) THEN
	 	UPDATE tmp_metadataset 
		SET dataval = tbl_metadata.dataval 
                FROM tbl_metadata
		WHERE tbl_metadata.keyword = 'VBS_IVOC_FACTORS'
	  	AND tbl_metadata.keyword = tmp_metadataset.keyword;
           END IF;
	END IF;  -- like VOC

	IF ( runOut LIKE '%PM%')  THEN
	   IF ( runType ISNULL ) THEN
		runType := 'CRITERIA';
	   END IF;
	   UPDATE tmp_metadataset 
	   SET dataval = runType 
	   WHERE keyword = 'RUN_TYPE';

	   UPDATE tmp_metadataset 
	   SET dataval = tbl_metadata.dataval 
	   FROM tbl_metadata
	   WHERE tbl_metadata.keyword = 'PM_PROFILES'
	     AND tbl_metadata.keyword = tmp_metadataset.keyword;

	   IF ( runMechanism = 'AE6' AND runAQM = 'CAMX' )  THEN
	   	UPDATE tmp_metadataset 
	   	SET dataval = tbl_metadata.dataval 
		FROM tbl_metadata
	   	WHERE tbl_metadata.keyword = 'CAMX_FCRS'
	   	  AND tbl_metadata.keyword = tmp_metadataset.keyword;

	   	INSERT INTO tmp_metadataset (keyword, dataval)
	   	SELECT 'NOTE', 'PM CAMx CF carries additional POC compound for model performance evaluation';
	   END IF;
	   IF ( runType = 'VBS' ) THEN
		 UPDATE tmp_metadataset 
		 SET dataval = tbl_metadata.dataval 
		 FROM tbl_metadata
		 WHERE tbl_metadata.keyword = 'VBS_SVOC_FACTORS'
	  	   AND tbl_metadata.keyword = tmp_metadataset.keyword;
	   END IF;
	END IF;

	IF ( runOut LIKE '%STATIC%')  THEN
		UPDATE tmp_metadataset 
		SET dataval = tbl_metadata.dataval 
	        FROM tbl_metadata
		WHERE tbl_metadata.keyword = 'STATIC'
		  AND tbl_metadata.keyword = tmp_metadataset.keyword;
	END IF;

	IF ( flagMech = 'N') THEN
		INSERT INTO tmp_metadataset (keyword, dataval)
		SELECT 'NOTE', SUBSTRING(tbl_mechanism_description.comment,1,250) 
		FROM tbl_mechanism_description
		WHERE mechanism = runMechanism;
	END IF;

	IF (( runOut ISNULL OR runOut LIKE '%VOC%') AND ( runPROC IS NOT NULL)) THEN
		UPDATE tmp_metadataset 
		SET dataval = runPROC 
		WHERE keyword = 'PROCESS';
	END IF;

RETURN;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION gspro_CreateTempTables() RETURNS INTEGER AS
$$
DECLARE
	runName      TEXT;

BEGIN

     -- get the run name from the control table --
        SELECT  INTO runName dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'RUN_NAME';

    -- Table tmp_gspro carries splits 
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_gspro'
                                          AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_gspro;
    END IF;
    CREATE TABLE tmp_gspro
    (
        profile_id         VARCHAR(20), 
        eminv_poll         VARCHAR(20),
        aqm_poll           VARCHAR(20),
        split_factor       NUMERIC(15,10),
        divisor            NUMERIC(12,8),
        mass_fraction      NUMERIC(15,10)
    );

    CREATE UNIQUE INDEX idx_tmp_gspro
           ON tmp_gspro (profile_id, eminv_poll, aqm_poll);

    -- Table tmp_gscnv conversion factors
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_gscnv'
                                          AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_gscnv;
    END IF;
    CREATE TABLE tmp_gscnv
    (
        from_specie        VARCHAR(20),
        to_specie          VARCHAR(20),
        profile_id         VARCHAR(20), 
        cnv_factor         NUMERIC(15,10)
    );


--    -- Table tmp_oc carries organic and other PM  
--    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_oc'
--                                          AND schemaname = runName) > 0) THEN
--        DROP TABLE tmp_oc;
--    END IF;
--    CREATE TABLE tmp_oc
--    (
--        profile_id         VARCHAR(20), 
--        poc		   NUMERIC(12,8),
--        poa           	   NUMERIC(12,8),
--        pmfine         	   NUMERIC(12,8)
--    );

    -- Table metadata  
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_metadataset'
                                          AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_metadataset;
    END IF;
    CREATE TABLE tmp_metadataset
   (
   	keyword          VARCHAR(20),
    	dataval          VARCHAR(256),
    	version          VARCHAR(20)     
   );

    RETURN 0;
END;
$$
LANGUAGE plpgsql;

