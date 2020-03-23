-- Filename   : make_pm_splits.sql
-- Author     : Michele Jimenez, ENVIRON International Corp. 
-- Version    : Speciation Tool 5.0 alpha
-- Release    : 28 Sep 2018
--
--  Generate and fill the temporary tables used to determine
--  the PM2.5 split factors.  Notices are displayed indicating the progress
--  of execution.
--
--   Updates:	June 2016 	Support CAMx PM mechanism CF
--              Sep 2016	Add VBS (Volatility Basis Set) SVOC option
--              Sep 2018        Process all PM2.5 profiles - make AE6-ready
--                              if necessary
--              Mar 2020        Accommodate new SPECIATE5.0 data structure
--                              Change the order of priorities within species gap filling
--                              Add functionality to determine OM/OC ratio and PH2O values without external files
--                                 
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

-- variables for generating AE6-ready 'on the fly'
    poc                      VARCHAR(20);
    sulfate                  VARCHAR(20);
    sulfur                   VARCHAR(20);
    ammonium                 VARCHAR(20);
    strPH2O                  VARCHAR(20);
    pncom                    VARCHAR(20);
    ion                      VARCHAR(20);
    atom                     VARCHAR(20);
    oxide                    VARCHAR(20);
    MO_unadjusted            FLOAT;
    N_sulfate                FLOAT;
    nonN_sulfate             FLOAT;
    MO_adjust                FLOAT;
    sumAdj                   FLOAT;
    facAdj                   FLOAT;

----------------------------------------------------------------------------------

BEGIN

        version := 'Speciation Tool v5.0 alpha';

 -- check to proceed PM speciation -- 
     -- get the list of output requirements from the control table --
        SELECT  INTO runOut dataval
        FROM  tbl_run_control
        WHERE tbl_run_control.keyword = 'OUTPUT';
        runOut := UPPER(runOut);

 -- initialize species IDs for AE6 calculations
        sulfate  := '699';
        sulfur   := '700';
        ammonium := '784';
        poc      := '626';
        strPH2O  := '2668';
        pncom    := '2669';

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
        
        IF ( runMechanism = 'AE7' ) THEN
            CREATE TABLE tbl_pm_profiles AS
            SELECT p.* FROM tbl_profiles p
            WHERE p.profile_type IN ('PM','PM-AE6','PM-VBS');
            
            INSERT INTO tmp_vbs_profiles (profile_id)
            SELECT DISTINCT p.profile_id
            FROM tbl_pm_profiles p
            WHERE p.profile_type = 'PM-VBS';

            RAISE NOTICE ' PM Profiles imported ';

        ELSE
            CREATE TABLE tbl_pm_profiles AS
            SELECT p.* FROM tbl_profiles p
            WHERE p.profile_type IN ('PM','PM-AE6'); 
            RAISE NOTICE ' PM Profiles imported ';

        END IF;   

        CREATE TABLE tbl_pm_profile_weights AS
        SELECT w.profile_id, w.specie_id, w.percent, w.uncertainty, w.unc_method, w.analytic_method
        FROM tbl_pm_profiles p INNER JOIN tbl_profile_weights w
        ON p.profile_id = w.profile_id;

        RAISE NOTICE ' PM Species imported ';


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

	-- generate only the PM2.5 profiles --
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

-----------------------------------------------------------------------------------------
        INSERT INTO tmp_profile_list (profile_id)
                        SELECT DISTINCT profile_id
                        FROM tbl_pm_profiles
                        WHERE profile_type <> 'PM-Simplified';


--  Make AE6-ready
--  Select all PM2.5 profiles that are NOT AE6-ready and compute
--  compounds required for AE6 processing.
--  Per Reff etal paper: "Supporting information for: Emissions
--  Inventory of PM2:5 Trace Elements across the United States"

        INSERT INTO tmp_makeae6_list (profile_id)
                SELECT DISTINCT r.profile_id
                FROM tmp_raw_profiles r
                INNER JOIN tbl_pm_profiles p ON p.profile_id = r.profile_id
                WHERE p.profile_type = 'PM';

        RAISE NOTICE '      determined list to make AE6-ready... ';

        -- compute sulfate --------------------------------------------------------------
        -- prior to computing any compounds first determine if sulfate exists, if not set to fraction of sulfur

        INSERT INTO tmp_so4_profiles (profile_id)
                SELECT p.profile_id
                FROM tmp_profile_list p
                INNER JOIN tmp_raw_profiles r ON p.profile_id = r.profile_id
                WHERE r.specie_id = sulfate;

        INSERT INTO tmp_s_profiles (profile_id, wtpct)
                SELECT p.profile_id, r.percent
                FROM tmp_profile_list p
                INNER JOIN tmp_raw_profiles r ON p.profile_id = r.profile_id
                WHERE r.specie_id = sulfur;

        FOR prfRow IN
                SELECT profile_id
                FROM tmp_so4_profiles
        LOOP
                DELETE
                FROM tmp_s_profiles
                WHERE prfRow.profile_id = tmp_s_profiles.profile_id;
        END LOOP;

        INSERT INTO tmp_raw_profiles (profile_id,specie_id,percent)
                SELECT s.profile_id, sulfate, s.wtpct * (96./32.)
                FROM tmp_s_profiles s;

        RAISE NOTICE '      computed sulfate ... ';

        -- compute H2O -----------------------------------------------

        INSERT INTO tbl_zero_ph2o (profile_id)
                SELECT p.profile_id
                FROM tbl_pm_profiles p
                WHERE p.gen_mechanism = 'Combustion';
        INSERT INTO tmp_h2o (profile_id, ph2o)
                SELECT m.profile_id, SUM(p.percent)*.24
                FROM tmp_makeae6_list m
                LEFT JOIN tmp_raw_profiles p
                ON m.profile_id = p.profile_id
                WHERE p.specie_id = sulfate OR p.specie_id = ammonium
                GROUP BY m.profile_id;
        UPDATE tmp_h2o
           SET ph2o = 0.0
        FROM tbl_zero_ph2o
        WHERE tbl_zero_ph2o.profile_id = tmp_h2o.profile_id;

        -- delete records where H2O is zero (either calculated or defined set)
        DELETE FROM tmp_h2o
        WHERE ph2o = 0.0;

        -- delete records where PH2O already exists
        DELETE FROM tmp_h2o
        WHERE profile_id IN
              (SELECT m.profile_id FROM tmp_makeae6_list m
               INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id
               WHERE p.specie_id = strPH2O);

        INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
               SELECT  h.profile_id, strPH2O, h.ph2o
               FROM tmp_h2o h;

        RAISE NOTICE '      computed PH2O ... ';

        -- compute MO ------------------------------------------------

        FOR prfRow IN
           SELECT profile_id
           FROM tmp_makeae6_list
        LOOP

           SELECT INTO MO_unadjusted
                SUM(tmp_raw_profiles.percent * tbl_o2m_ratios.o2m_ratio)
           FROM tmp_raw_profiles, tbl_o2m_ratios
           WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
             AND tmp_raw_profiles.specie_id = tbl_o2m_ratios.specie_id;
           IF ( MO_unadjusted IS NULL ) THEN
              MO_unadjusted := 0.0;
           END IF;

           SELECT INTO N_sulfate ((0.5 * 96) / 18 * percent )
           FROM tmp_raw_profiles
           WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
             AND tmp_raw_profiles.specie_id = ammonium;
           IF ( N_sulfate IS NULL ) THEN
              N_sulfate := 0.0;
           END IF;

           SELECT INTO nonN_sulfate (percent - N_sulfate)
           FROM tmp_raw_profiles
           WHERE tmp_raw_Profiles.profile_id = prfRow.profile_id
             AND tmp_raw_profiles.specie_id = sulfate;
           IF ( nonN_sulfate IS NULL ) THEN
              nonN_sulfate := 0.0;
           END IF;

           IF ( nonN_sulfate <= 0.0 )  THEN
                MO_adjust = MO_unadjusted;
           ELSE
                MO_adjust = MO_unadjusted - (nonN_sulfate * 16/96.);
           END IF;
           IF ( MO_adjust < 0.0 )  THEN
                MO_adjust = 0.0;
           END IF;
           
           INSERT INTO tmp_mo ( profile_id, unadjusted_mo, sulfate_n,
                                            sulfate_nonn, adjusted_mo )
           VALUES (prfRow.profile_id,MO_unadjusted,N_sulfate,nonN_sulfate,MO_adjust);

           INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
           VALUES  ( prfRow.profile_id, '2670', MO_adjust );

        END LOOP;

        RAISE NOTICE '      computed MO ... ';

        -- compute NCOM -----------------------------------------------
        INSERT INTO tbl_pncom_facs (profile_id, gen_mechanism, sec_equipment, fuel_product,pncom_fac)
               SELECT p.profile_id, p.gen_mechanism, p.sec_equipment, p.fuel_product, .4
               FROM tbl_pm_profiles p;
        UPDATE tbl_pncom_facs
           SET pncom_fac = .25
        WHERE  tbl_pncom_facs.gen_mechanism = 'Combustion'
          AND  tbl_pncom_facs.sec_equipment LIKE '%Mobile%' ;

        UPDATE tbl_pncom_facs
           SET pncom_fac = .7
        WHERE  tbl_pncom_facs.sec_equipment LIKE '%biomass burning%'
          AND  tbl_pncom_facs.sec_equipment NOT LIKE '%boiler%';


        CREATE TABLE tmp_pncom AS
        SELECT m.profile_id, p.percent, 0.0 AS factor
        FROM tmp_makeae6_list m
        INNER JOIN tmp_raw_profiles p
        ON m.profile_id = p.profile_id
        WHERE p.specie_id = poc;

        UPDATE tmp_pncom
           SET factor = tbl_pncom_facs.pncom_fac
        FROM tbl_pncom_facs
        WHERE tmp_pncom.profile_id = tbl_pncom_facs.profile_id;

        UPDATE tmp_pncom
           SET factor = .4
        WHERE factor = 0.;

        INSERT INTO tmp_raw_profiles (profile_id, specie_id, percent)
               SELECT  p.profile_id, pncom, p.percent * p.factor
               FROM tmp_pncom p;

        RAISE NOTICE '      computed PNCOM ... ';

        -- RENORMALIZE profiles where weight percent sum > 101 ---------------------------------------------
        -- a list of species to be dropped from renormalization are set in tmp_dropspecies
        -- exclude sulfur, as it would be double counting w computed PSO4

        -- drop list of species per EPA, would be double counting
        DELETE FROM tmp_raw_profiles
        WHERE specie_id IN (SELECT d.specie_id FROM tmp_dropspecies d);

        -- drop atom if ion exists > 0. | reassign atom to ion specie_id if atom >0 and not ion ------
        -- for the pairs K/K ion, NA/NA ion, CL/ CL ion --
        -- potassium pair --
        ion := '2302';
        atom := '669';
        DELETE FROM tmp_raw_profiles WHERE specie_id = ion and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = atom and percent = 0;
        TRUNCATE tmp_ion_profiles; 
        TRUNCATE tmp_atom_profiles; 
        INSERT INTO tmp_ion_profiles (profile_id) 
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = ion and p.percent > 0.0;
        INSERT INTO tmp_atom_profiles (profile_id) 
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = atom and p.percent > 0.0;

        DELETE FROM tmp_atom_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w );
	FOR prfRow IN
		SELECT p.profile_id
		FROM tmp_atom_profiles p
	LOOP

		UPDATE tmp_raw_profiles
		SET specie_id = ion
		WHERE prfRow.profile_id = tmp_raw_profiles.profile_id
		AND tmp_raw_profiles.specie_id = atom;
	END LOOP;
        
        RAISE NOTICE '      computed K ... ';


        -- sodium pair --
        ion := '785';
        atom := '696';
        DELETE FROM tmp_raw_profiles WHERE specie_id = ion and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = atom and percent = 0;
        TRUNCATE tmp_ion_profiles; 
        TRUNCATE tmp_atom_profiles; 
        INSERT INTO tmp_ion_profiles (profile_id) 
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = ion and p.percent > 0.0;
        INSERT INTO tmp_atom_profiles (profile_id) 
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = atom and p.percent > 0.0;

        DELETE FROM tmp_atom_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w );

        FOR prfRow IN
                SELECT p.profile_id
                FROM tmp_atom_profiles p
        LOOP

                UPDATE tmp_raw_profiles
                SET specie_id = ion
                WHERE prfRow.profile_id = tmp_raw_profiles.profile_id
                AND tmp_raw_profiles.specie_id = atom;
        END LOOP;

        RAISE NOTICE '      computed Na ... ';


        -- chlorine pair --
        ion := '337';
        atom := '795';
        DELETE FROM tmp_raw_profiles WHERE specie_id = ion and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = atom and percent = 0;
        TRUNCATE tmp_ion_profiles; 
        TRUNCATE tmp_atom_profiles; 
        INSERT INTO tmp_ion_profiles (profile_id) 
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = ion and p.percent > 0.0;
        INSERT INTO tmp_atom_profiles (profile_id) 
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = atom and p.percent > 0.0;

        DELETE FROM tmp_atom_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w );

        FOR prfRow IN
                SELECT p.profile_id
                FROM tmp_atom_profiles p
        LOOP

                UPDATE tmp_raw_profiles
                SET specie_id = ion
                WHERE prfRow.profile_id = tmp_raw_profiles.profile_id
                AND tmp_raw_profiles.specie_id = atom;
        END LOOP;

        RAISE NOTICE '      computed Cl ... ';


        -- drop atom if ion exists > 0. | reassign ion to atom specie_id | use atom if atom >0 and not ion ------
        -- If neither atom nor ion exists, but metal oxide exists >1, calculate based on fraction ----
        -- for the pairs Ca/Ca ion/CaO, Mg/Mg ion/MgO --

        -- Calcium pair --
        ion := '2303';
        atom := '329';
        oxide := '2847';
        RAISE NOTICE '      Ca oxide ... ';

        DELETE FROM tmp_raw_profiles WHERE specie_id = ion and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = atom and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = oxide and percent = 0;
        RAISE NOTICE '      Ca percent=0 removed ... ';

        TRUNCATE tmp_ion_profiles;
        TRUNCATE tmp_atom_profiles;
        INSERT INTO tmp_ion_profiles (profile_id)
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = ion and p.percent > 0.0;
        INSERT INTO tmp_atom_profiles (profile_id)
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = atom and p.percent > 0.0;
        INSERT INTO tmp_oxide_profiles (profile_id, wtpct)
               SELECT p.profile_id, p.percent FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = oxide and p.percent > 0.0;
        RAISE NOTICE '      Ca tmp profiles created ... ';

        DELETE FROM tmp_atom_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w );
        FOR prfRow IN
                SELECT p.profile_id
                FROM tmp_atom_profiles p
        LOOP

                UPDATE tmp_raw_profiles
                SET specie_id = ion
                WHERE prfRow.profile_id = tmp_raw_profiles.profile_id
                AND tmp_raw_profiles.specie_id = atom;
        END LOOP;

        RAISE NOTICE '      Ca atom duplicates removed ... ';

        DELETE FROM tmp_oxide_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w )
        OR    profile_id IN ( SELECT a.profile_id FROM tmp_atom_profiles a );
        RAISE NOTICE '      Ca oxide duplicates removed ... ';

        INSERT INTO tmp_raw_profiles (profile_id,specie_id,percent)
                SELECT s.profile_id, ion, s.wtpct * (40./56.)
                FROM tmp_oxide_profiles s;
        RAISE NOTICE '      computed Ca ... ';

        -- Magnesium pair --
        ion := '2772';
        atom := '525';
        oxide := '2852';
        DELETE FROM tmp_raw_profiles WHERE specie_id = ion and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = atom and percent = 0;
        DELETE FROM tmp_raw_profiles WHERE specie_id = oxide and percent = 0;
        TRUNCATE tmp_ion_profiles;
        TRUNCATE tmp_atom_profiles;
        TRUNCATE tmp_oxide_profiles;
        INSERT INTO tmp_ion_profiles (profile_id)
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = ion and p.percent > 0.0;
        INSERT INTO tmp_atom_profiles (profile_id)
               SELECT p.profile_id FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = atom and p.percent > 0.0;
        INSERT INTO tmp_oxide_profiles (profile_id, wtpct)
               SELECT p.profile_id, p.percent FROM tmp_profile_list m INNER JOIN tmp_raw_profiles p ON m.profile_id = p.profile_id where p.specie_id = oxide and p.percent > 0.0;

        DELETE FROM tmp_atom_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w );

        FOR prfRow IN
                SELECT p.profile_id
                FROM tmp_atom_profiles p
        LOOP
                UPDATE tmp_raw_profiles
                SET specie_id = ion
                WHERE prfRow.profile_id = tmp_raw_profiles.profile_id
                AND tmp_raw_profiles.specie_id = atom;
        END LOOP;

        DELETE FROM tmp_oxide_profiles
        WHERE profile_id IN ( SELECT w.profile_id FROM tmp_ion_profiles w )
        OR    profile_id IN ( SELECT a.profile_id FROM tmp_atom_profiles a );

        INSERT INTO tmp_raw_profiles (profile_id,specie_id,percent)
                SELECT s.profile_id, ion, s.wtpct * (24./40.)
                FROM tmp_oxide_profiles s;


        -- delete atoms to avoid double counting in 
        FOR prfRow IN
           SELECT profile_id
           FROM tmp_profile_list
        LOOP
            DELETE FROM tmp_raw_profiles 
            WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
             AND tmp_raw_profiles.specie_id IN ('329','525','669','696','795','2847','2852');
	END LOOP;
        -- end of atom/ion selections and reassignments                                         ------

        INSERT INTO tmp_sums_makeae6 (profile_id, sum_pct)
                SELECT DISTINCT  p.profile_id, SUM(p.percent)
                FROM tmp_makeae6_list m
                INNER JOIN tmp_raw_profiles p ON p.profile_id = m.profile_id
                WHERE p.specie_id <> sulfur
                GROUP BY p.profile_id;

        FOR prfRow IN
           SELECT profile_id, sum_pct
           FROM tmp_sums_makeae6
           WHERE sum_pct > 101.
        LOOP

           -- case I - adjust POC and PNCOM by the same factor in order to acheive total profile wtpct sum = 100.
           --          This can only occur if POC exists in the profile and the 
           --          sum of POC + PNCOM >  total profile wtpct sum - 100
           SELECT INTO sumAdj SUM(p.percent)
           FROM tmp_raw_profiles p
           WHERE p.profile_id = prfRow.profile_id
             AND (p.specie_id = poc OR p.specie_id = pncom)
           GROUP BY p.profile_id;

           facAdj:= 0.0;
           IF ( sumAdj > 0 ) THEN
              facAdj:= (100. - (prfRow.sum_pct - sumAdj))/sumAdj;
           END IF;

           IF ( sumAdj > 0. AND facAdj > 0. ) THEN
              UPDATE tmp_raw_profiles
              SET percent = tmp_raw_profiles.percent * facAdj
              WHERE tmp_raw_profiles.profile_id = prfRow.profile_id
              AND (tmp_raw_profiles.specie_id = poc OR tmp_raw_profiles.specie_id = pncom);
           ELSE
           -- case II - adjust all components of profile to acheive total profile wtpct sum = 100.
              RAISE NOTICE '... WARNING entire profile renormalized %',prfRow.profile_id;

              UPDATE tmp_raw_profiles
              SET percent = (tmp_raw_profiles.percent / prfRow.sum_pct) * 100.
              FROM tmp_sums_makeae6
              WHERE tmp_raw_profiles.profile_id = prfRow.profile_id;
           END IF;

        END LOOP;

        RAISE NOTICE '      renormalized profiles not AE6-ready ... ';

  RAISE NOTICE '...completed make AE6-ready ';

-----------------------------------------------------------------------------------------

	-- determine the unique set of profiles to process --
        -- and the weight percent sum of each profile for all non-computed mechanism compounds -- 
	RAISE NOTICE '...calculating weight percent sum of mechanism compounds' ;
        INSERT INTO tmp_sums (profile_id, sum_pct)
                      SELECT DISTINCT  p.profile_id, SUM(w.percent)
                      FROM tmp_mechanism m
                      INNER JOIN tmp_raw_profiles w ON m.specie_id = w.specie_id
                      INNER JOIN tmp_profile_list p ON p.profile_id = w.profile_id
                      GROUP BY p.profile_id;
--
	--  warning if weight profiles exceed 100 percent for the non-computed compounds --
	SELECT INTO tmpInteger COUNT(*) 
		FROM tmp_sums
                WHERE TRUNC(sum_pct) > 100.
                  AND profile_id NOT IN (SELECT w.profile_id FROM tmp_vbs_profiles w);

	IF ( tmpInteger > 0 )  THEN
		RAISE NOTICE 'WARNING review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
		RAISE NOTICE 'WARNING: The following profiles are invalid and will be excluded from processing.  ' ;
		RAISE NOTICE 'WARNING: Total weight percent of qualifying compounds is greater than 100 percent.' ;

		FOR prfRow IN 
			SELECT t.*, substring(p.profile_name from 1 for 50) AS profile_name
                            FROM tmp_sums t, tbl_pm_profiles p
                            WHERE t.profile_id = p.profile_id
                              AND TRUNC(sum_pct) > 100. 
                              AND p.profile_type NOT LIKE 'PM-VBS'
		LOOP    
			RAISE NOTICE 'WARNING: PROFILE  %  Percent %  %', prfRow.profile_id, prfRow.sum_pct, prfRow.profile_name;

		END LOOP;
		RAISE NOTICE 'WARNING review and correct   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv ' ;
--                INSERT INTO tmp_error(error,description)
--                       VALUES ('warning','Profiles dropped with total weight percent > 100.');
	END IF;

--	-- delete records from profile list if weight percent sums exceed 100 percent --
	DELETE FROM tmp_sums
		WHERE TRUNC(sum_pct,0) > 100
                  AND profile_id NOT IN (SELECT w.profile_id FROM tmp_vbs_profiles w);

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
--                INSERT INTO tmp_error(error,description)
--                       VALUES ('warning','Profiles dropped containing a component with a negative weight percent.');
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
LANGUAGE plpgsql;

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


    -- Table tmp_vbs_profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_vbs_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_vbs_profiles;
    END IF;
    CREATE TABLE tmp_vbs_profiles
    (
        profile_id         VARCHAR(20)
    );
    CREATE UNIQUE INDEX idx_tmp_vbs_profiles
           ON tmp_vbs_profiles (profile_id);




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

    -- Table tmp_atom_profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_atom_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_atom_profiles;
    END IF;
    CREATE TABLE tmp_atom_profiles
    (
        profile_id         VARCHAR(20)
    );
    CREATE UNIQUE INDEX idx_tmp_atom_profiles
           ON tmp_atom_profiles (profile_id);

    -- Table tmp_ion_profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_ion_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_ion_profiles;
    END IF;
    CREATE TABLE tmp_ion_profiles
    (
        profile_id         VARCHAR(20)
    );
    CREATE UNIQUE INDEX idx_tmp_ion_profiles
           ON tmp_ion_profiles (profile_id);

    -- Table tmp_oxide_profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_oxide_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_oxide_profiles;
    END IF;
    CREATE TABLE tmp_oxide_profiles
    (
        profile_id         VARCHAR(20),
        wtpct              NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_oxide_profiles
           ON tmp_oxide_profiles (profile_id);


    CREATE TABLE tmp_error (error VARCHAR(20),description VARCHAR(200));

    -- Table tmp_makeae6_list
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_makeae6_list'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_makeae6_list;
    END IF;
    CREATE TABLE tmp_makeae6_list
    (
        profile_id         VARCHAR(20),
        sum_pct            NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_makeae6_list
           ON tmp_makeae6_list (profile_id);

    -- Table tmp_so4_profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_so4_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_so4_profiles;
    END IF;
    CREATE TABLE tmp_so4_profiles
    (
        profile_id         VARCHAR(20)
    );
    CREATE UNIQUE INDEX idx_tmp_so4_profiles
           ON tmp_so4_profiles (profile_id);

    -- Table tmp_s_profiles
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_s_profiles'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_s_profiles;
    END IF;
    CREATE TABLE tmp_s_profiles
    (
        profile_id         VARCHAR(20),
        wtpct              NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_s_profiles
           ON tmp_s_profiles (profile_id);

    -- Table tmp_h2o
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_h2o'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_h2o;
    END IF;
    CREATE TABLE tmp_h2o
    (
        profile_id         VARCHAR(20),
        ph2o               NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_h2o
           ON tmp_h2o (profile_id);

-- List of profile ids where PH2O is set to zero when creating AE6-ready
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tbl_zero_ph2o'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tbl_zero_ph2o;
    END IF;
    CREATE TABLE tbl_zero_ph2o
    (
            profile_id          VARCHAR(20)     
    );
    CREATE UNIQUE INDEX idx_zero_ph2o
           ON tbl_zero_ph2o(profile_id);

-- Table tbl_pncom_facs
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tbl_pncom_facs'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tbl_pncom_facs;
    END IF;
    CREATE TABLE tbl_pncom_facs
    (
            profile_id          VARCHAR(20),
            gen_mechanism       VARCHAR(100),
            sec_equipment       VARCHAR(100),
            fuel_product        VARCHAR(100),
            pncom_fac           NUMERIC(10,6)
    );
    CREATE UNIQUE INDEX idx_pncom_facs
           ON tbl_pncom_facs(profile_id);



    -- Table tmp_mo
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_mo'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_mo;
    END IF;
    CREATE TABLE tmp_mo
    (
        profile_id         VARCHAR(20),
        unadjusted_mo      NUMERIC(15,8),
        sulfate_n          NUMERIC(15,8),
        sulfate_nonn       NUMERIC(15,8),
        adjusted_mo        NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_mo
           ON tmp_mo (profile_id);

    -- Table tmp_sums_makeae6
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_sums_makeae6'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_sums_makeae6;
    END IF;
    CREATE TABLE tmp_sums_makeae6
    (
        profile_id         VARCHAR(20),
        sum_pct            NUMERIC(15,8)
    );
    CREATE UNIQUE INDEX idx_tmp_sums_makeae6
           ON tmp_sums_makeae6 (profile_id);

    -- Table tmp_dropspecies
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = 'tmp_dropspecies'
                                                AND schemaname = runName) > 0) THEN
        DROP TABLE tmp_dropspecies;
    END IF;
    CREATE TABLE tmp_dropspecies
    (
        specie_id          VARCHAR(20), 
        name               VARCHAR(20) 
    );
    CREATE UNIQUE INDEX idx_tmp_dropspecies
           ON tmp_dropspecies (specie_id);
    -- Insert list of species that are dropped before profile weights are renormalized
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('294','NH3');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('436','TC');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('665','PO4');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('788','CO3=');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('789','OC2');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('790','OC3');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('791','OC4');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('794','EC1');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('796','EC3');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('830','SO2');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('831','H2S');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('1183','OC1 ');
           INSERT INTO tmp_dropspecies(specie_id,name) VALUES ('1190','EC2');

    RETURN 0;
END;
$$
LANGUAGE plpgsql;

