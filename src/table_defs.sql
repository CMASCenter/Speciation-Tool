-- Filename   : table_defs.sql
-- Author     : M Jimenez, ENVIRON International Corp.
-- Version    : Speciation Tool 4.5
-- Description: Create shared database tables
-- Release    : 30 Sep 2017
--
--   Sql script to create speciation tool tables.
--   Execute on an installation basis to create or recreate the tables to
--   hold the speciation data.
--
--   Modified 28June2016
--   Defined table for determining which profiles have FCRS instead of
--   FPRM for CAMx modeling
--
--   Modified 18Aug2016 --   Defined tables to support VBS
--   Modified Sep 2018 - Defined tables to support PM AE6-ready
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
--c       Uarporn Nopmongcol <unopmongcol@environcorp.com> Sep, 2007 
--c		- enhanced to prepare invtable
--c		- enhanced to prepare metadata 
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

-- mechanism table
SELECT DROP_TABLE('tbl_mechanism');
CREATE TABLE tbl_mechanism
(
    mechanism            VARCHAR(20)   NOT NULL,
    specie_id            VARCHAR(20)   NOT NULL,
    aqm_poll             VARCHAR(20)   NOT NULL,
    moles_per_mole       NUMERIC(20,12)
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_mechansim
  ON tbl_mechanism (mechanism, specie_id, aqm_poll);

-- PM mechanism table
SELECT DROP_TABLE('tbl_pm_mechanism');
CREATE TABLE tbl_pm_mechanism
(
    mechanism            VARCHAR(20)   NOT NULL,
    specie_id            VARCHAR(20),
    aqm_poll             VARCHAR(20)   NOT NULL,
    qualify              BOOLEAN,
    compute              BOOLEAN
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_pm_mechansim
  ON tbl_pm_mechanism (mechanism, specie_id, aqm_poll);

-- mechanism desciption table
SELECT DROP_TABLE('tbl_mechanism_description');
CREATE TABLE tbl_mechanism_description
(
    mechanism          VARCHAR(20)   NOT NULL,
    description        VARCHAR(256),
    nonsoaflag         VARCHAR(1),
    origin             VARCHAR(300),
    reference          VARCHAR(100),
    comment            VARCHAR(500)
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_mechansim_description
  ON tbl_mechanism_description (mechanism);

-- invtable 
SELECT DROP_TABLE('tbl_invtable');
CREATE TABLE tbl_invtable
(
    eminv_poll          VARCHAR(12)    NOT NULL,
    mode                VARCHAR(3),      
    poll_code           VARCHAR(16),
    specie_id           VARCHAR(20)    NOT NULL,
    reactivity          VARCHAR(20), 
    keep                VARCHAR(20), 
    factor              VARCHAR(20),
    voc                 VARCHAR(20), 
    model               VARCHAR(20), 
    explicit            VARCHAR(20), 
    activity            VARCHAR(20), 
    nti                 VARCHAR(20), 
    unit                VARCHAR(20), 
    description         VARCHAR(50), 
    cas_description     VARCHAR(50) 
) WITHOUT OIDS;

-- number of carbons table
SELECT DROP_TABLE('tbl_carbons');
CREATE TABLE tbl_carbons
(
   mechanism          VARCHAR(20)   NOT NULL,
   aqm_poll           VARCHAR(20)   NOT NULL,
   num_carbons        NUMERIC(5,2)  NOT NULL
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_carbons
  ON tbl_carbons (mechanism, aqm_poll);

-- species
SELECT DROP_TABLE('tbl_species');
CREATE TABLE tbl_species
(
    specie_id          VARCHAR(20)    NOT NULL,
    specie_name        VARCHAR(500),
    cas                VARCHAR(50),
    epaid              VARCHAR(50),
    saroad             VARCHAR(10),
    pams               BOOLEAN,
    haps               BOOLEAN,
    symbol             VARCHAR(10),
    molecular_weight   NUMERIC(20,12),
    non_voctog         BOOLEAN,
    non_vol_wt         VARCHAR(20),
    unknown_wt         VARCHAR(20),
    unassign_wt        VARCHAR(20),
    exempt_wt          VARCHAR(20),
    volatile_mw        NUMERIC(20,12),
    num_carbons        NUMERIC(20,12),
    epa_itn            VARCHAR(20),
    comment            VARCHAR(50) 
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_specie
  ON tbl_species (specie_id);

-- profiles
SELECT DROP_TABLE('tbl_profiles');
CREATE TABLE tbl_profiles
(
    profile_id          VARCHAR(20)     NOT NULL,
    profile_name        VARCHAR(200),
    profile_type        VARCHAR(20),
    master_poll         VARCHAR(20),
    total               NUMERIC(10,5),
    norm_basis          VARCHAR(100),
    composite           VARCHAR(2),
    standard            BOOLEAN,
    incl_gas            BOOLEAN,
    test_year           VARCHAR(50),
    j_rating            NUMERIC(10,2),
    v_rating            NUMERIC(10,2),
    d_rating            NUMERIC(10,2),
    region              VARCHAR(100),
    samples             VARCHAR(100),
    lower_size          NUMERIC(10,4),
    upper_size          NUMERIC(10,4),
    sibling             VARCHAR(100),
    version             VARCHAR(5),
    voc_to_tog          NUMERIC(12,7),
    t_sample            NUMERIC(10,2),
    rh_sample           NUMERIC(10,2),
    p_loading           NUMERIC(10,2),
    o_loading           NUMERIC(10,2),
    gen_mechanism       VARCHAR(100),
    sec_equipment       VARCHAR(100),
    fuel_product        VARCHAR(100),
    ms_poll_rate        NUMERIC(10,2),
    ms_poll_unit        VARCHAR(10),
    om_to_oc            NUMERIC(10,2),
    mass_overage_pct    NUMERIC(15,12)

) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_profiles
  ON tbl_profiles(profile_id);

-- pm profiles
-- SELECT DROP_TABLE('tbl_pm_profiles');
-- CREATE TABLE tbl_pm_profiles
-- (
--     profile_id          VARCHAR(20)     NOT NULL,
--     profile_name        VARCHAR(200),
--     profile_type        VARCHAR(20),
--     master_poll         VARCHAR(20),
--     total               NUMERIC(10,5),
--     norm_basis          VARCHAR(100),
--     composite           VARCHAR(2),
--     standard            BOOLEAN,
--     incl_gas            BOOLEAN,
--     test_year           VARCHAR(50),
--     j_rating            NUMERIC(10,2),
--     v_rating            NUMERIC(10,2),
--     d_rating            NUMERIC(10,2),
--     region              VARCHAR(100),
--     samples             VARCHAR(100),
--     lower_size          NUMERIC(10,4),
--     upper_size          NUMERIC(10,4),
--     sibling             VARCHAR(20),
--     version             VARCHAR(5),
--     voc_to_tog          NUMERIC(12,7),
--     t_sample            NUMERIC(10,2),
--     rh_sample           NUMERIC(10,2),
--     p_loading           NUMERIC(10,2),
--     o_loading           NUMERIC(10,2),
--     gen_mechanism       VARCHAR(50),
--     sec_equipment       VARCHAR(100),
--     fuel_product        VARCHAR(100),
--     ms_poll_rate        NUMERIC(10,2),
--     ms_poll_unit        VARCHAR(10),
--     om_to_oc            NUMERIC(10,2),
--     mass_overage_pct    NUMERIC(15,12)
-- 
-- ) WITHOUT OIDS;
-- 
-- CREATE UNIQUE INDEX idx_pm_profiles
--   ON tbl_pm_profiles(profile_id);
-- 
-- -- gas profiles
-- SELECT DROP_TABLE('tbl_gas_profiles');
-- CREATE TABLE tbl_gas_profiles
-- (
--     profile_id          VARCHAR(20)     NOT NULL,
--     profile_name        VARCHAR(200),
--     profile_type        VARCHAR(20),
--     master_poll         VARCHAR(20),
--     total               NUMERIC(10,5),
--     norm_basis          VARCHAR(100),
--     composite           VARCHAR(2),
--     standard            BOOLEAN,
--     incl_gas            BOOLEAN,
--     test_year           VARCHAR(50),
--     j_rating            NUMERIC(10,2),
--     v_rating            NUMERIC(10,2),
--     d_rating            NUMERIC(10,2),
--     region              VARCHAR(100),
--     samples             VARCHAR(100),
--     lower_size          NUMERIC(10,4),
--     upper_size          NUMERIC(10,4),
--     sibling             VARCHAR(100),
--     version             VARCHAR(5),
--     voc_to_tog          NUMERIC(12,7),
--     t_sample            NUMERIC(10,2),
--     rh_sample           NUMERIC(10,2),
--     p_loading           NUMERIC(10,2),
--     o_loading           NUMERIC(10,2),
--     gen_mechanism       VARCHAR(100),
--     sec_equipment       VARCHAR(100),
--     fuel_product        VARCHAR(100),
--     ms_poll_rate        NUMERIC(10,2),
--     ms_poll_unit        VARCHAR(20),
--     om_to_oc            NUMERIC(10,2),
--     mass_overage_pct    NUMERIC(15,12)
-- 
-- ) WITHOUT OIDS;
-- 
-- CREATE UNIQUE INDEX idx_gas_profiles
--   ON tbl_gas_profiles(profile_id);

-- profile weights
SELECT DROP_TABLE('tbl_profile_weights');
CREATE TABLE tbl_profile_weights
(
    profile_id          VARCHAR(20)     NOT NULL,
    specie_id           VARCHAR(20)     NOT NULL,
    percent             NUMERIC(12,6)   NOT NULL,
    uncertainty         NUMERIC(12,6),
    unc_method          VARCHAR(100),
    analytic_method     VARCHAR(500)
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_profile_weights
  ON tbl_profile_weights(profile_id, specie_id);

-- profile weights
-- SELECT DROP_TABLE('tbl_pm_profile_weights');
-- CREATE TABLE tbl_pm_profile_weights
-- (
--     profile_id          VARCHAR(20)     NOT NULL,
--     specie_id           VARCHAR(20)     NOT NULL,
--     percent             NUMERIC(10,6)   NOT NULL,
--     uncertainty         NUMERIC(10,6),
--     unc_method          VARCHAR(100),
--     analytic_method     VARCHAR(500)
-- ) WITHOUT OIDS;
-- 
-- CREATE UNIQUE INDEX idx_pm_profile_weights
--   ON tbl_pm_profile_weights(profile_id, specie_id);
-- 
-- -- profile weights
-- SELECT DROP_TABLE('tbl_gas_profile_weights');
-- CREATE TABLE tbl_gas_profile_weights
-- (
--     profile_id          VARCHAR(20)     NOT NULL,
--     specie_id           VARCHAR(20)     NOT NULL,
--     percent             NUMERIC(10,6)   NOT NULL,
--     uncertainty         NUMERIC(10,6),
--     unc_method          VARCHAR(100),
--     analytic_method     VARCHAR(500)
-- ) WITHOUT OIDS;
-- 
-- CREATE UNIQUE INDEX idx_gas_profile_weights
--   ON tbl_gas_profile_weights(profile_id, specie_id);
-- 

-- static split factors
SELECT DROP_TABLE('tbl_static');
CREATE TABLE tbl_static
(
    profile_id          VARCHAR(20)     NOT NULL,
    eminv_poll          VARCHAR(20)     NOT NULL,
    aqm_poll            VARCHAR(20)     NOT NULL,
    split_factor        NUMERIC(20,10),
    divisor             NUMERIC(20,10),
    mass_fraction       NUMERIC(20,10),
    aq_model            VARCHAR(10)
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_static
  ON tbl_static(profile_id, eminv_poll, aqm_poll, aq_model);

-- no longer needed, part of tbl_pm_mechanism
-- particulate AQM pollutant names
--SELECT DROP_TABLE('tbl_pm_species');
--CREATE TABLE tbl_pm_species
--(
--    specie_id          VARCHAR(20)     NOT NULL,
--    pm_eminv_poll      VARCHAR(20)     NOT NULL,
--    pm_aqm_poll        VARCHAR(20)     NOT NULL,
--    aq_model           VARCHAR(10)     NOT NULL
--) WITHOUT OIDS;
--
--CREATE UNIQUE INDEX idx_pm_species
--  ON tbl_pm_species(specie_id, pm_eminv_poll, pm_aqm_poll, aq_model);

-- Override mechanism pollutant names in order to support different AQMs
SELECT DROP_TABLE('tbl_rename_species');
CREATE TABLE tbl_rename_species
(
    aq_model        VARCHAR(10)     NOT NULL,
    mechanism       VARCHAR(20)     NOT NULL,
    eminv_poll      VARCHAR(20)     NOT NULL,
    aqm_poll        VARCHAR(20)     NOT NULL
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_rename_species
  ON tbl_rename_species(aq_model, mechanism, eminv_poll, aqm_poll);

-- List of profile ids where PH2O is set to zero when creating AE6-ready
SELECT DROP_TABLE('tbl_zero_ph2o');
CREATE TABLE tbl_zero_ph2o
(
	profile_id          VARCHAR(20)     NOT NULL,
        profile_name        VARCHAR(255)
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_zero_ph2o
  ON tbl_zero_ph2o(profile_id);

-- List of profile ids and factors for computing PNCOM when creating AE6-ready
SELECT DROP_TABLE('tbl_pncom_facs');
CREATE TABLE tbl_pncom_facs
(
	profile_id          VARCHAR(20)     NOT NULL,
        profile_name        VARCHAR(255),
	pncom_frac          NUMERIC(10,6)   NOT NULL
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_pncom_facs
  ON tbl_pncom_facs(profile_id);

-- List of species with oxygen to metal ratios
SELECT DROP_TABLE('tbl_o2m_ratios');
CREATE TABLE tbl_o2m_ratios
(
	specie_id           VARCHAR(20)     NOT NULL,
	symbol              VARCHAR(20)     NOT NULL,
	o2m_ratio           NUMERIC(10,6)   NOT NULL
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_o2m_ratios
  ON tbl_o2m_ratios(specie_id);

-- List of profile ids for which CAMx want FPRM to be named FCRS
SELECT DROP_TABLE('tbl_camx_fcrs');
CREATE TABLE tbl_camx_fcrs
(
	profile_id          VARCHAR(20)     NOT NULL
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_camx_fcrs
  ON tbl_camx_fcrs(profile_id);

-- VBS SVOC factors by profile id
SELECT DROP_TABLE('tbl_vbs_svoc_factors');
CREATE TABLE tbl_vbs_svoc_factors
(
	profile_id	VARCHAR(20)	NOT NULL,
	cmaq_svocname	VARCHAR(20)	NOT NULL,
	camx_svocname	VARCHAR(20)	NOT NULL,
	bin0		NUMERIC(10,6)	NOT NULL,
	bin1		NUMERIC(10,6)	NOT NULL,
	bin2		NUMERIC(10,6)	NOT NULL,
	bin3		NUMERIC(10,6)	NOT NULL,
	bin4		NUMERIC(10,6)	NOT NULL
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_vbs_svoc_factors
  ON tbl_vbs_svoc_factors(profile_id);

-- VBS IVOC factors by profile id
SELECT DROP_TABLE('tbl_vbs_ivoc_nmogfactors');
CREATE TABLE tbl_vbs_ivoc_nmogfactors
(
	profile_id	VARCHAR(20)	NOT NULL,
	cmaq_ivocname	VARCHAR(20)	NOT NULL,
	camx_ivocname	VARCHAR(20)	NOT NULL,
	nmogfraction	NUMERIC(10,6)	NOT NULL
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_vbs_ivoc_nmogfactors
  ON tbl_vbs_ivoc_nmogfactors(profile_id);

-- VBS IVOC molecular weights
SELECT DROP_TABLE('tbl_vbs_ivoc_species');
CREATE TABLE tbl_vbs_ivoc_species
(
	aqm		VARCHAR(20)	NOT NULL,
	specie_id	VARCHAR(20)	NOT NULL,
	molwt		NUMERIC(10,6)   NOT NULL
) WITHOUT OIDS;
CREATE UNIQUE INDEX idx_vbs_ivoc_species
  ON tbl_vbs_ivoc_species(specie_id);

-- metadata 
SELECT DROP_TABLE('tbl_metadata');
CREATE TABLE tbl_metadata
(
    keyword          VARCHAR(20)     NOT NULL,
    dataval          VARCHAR(256)    NOT NULL,
    version          VARCHAR(20)     
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_metadata
  ON tbl_metadata(keyword);

INSERT INTO tbl_metadata (keyword, dataval) VALUES ('AQM','Not Applicable');
INSERT INTO tbl_metadata (keyword, dataval) VALUES ('MECH','Not Applicable');
INSERT INTO tbl_metadata (keyword, dataval) VALUES ('RUN_TYPE','Not Applicable');
INSERT INTO tbl_metadata (keyword, dataval) VALUES ('PROCESS','Not Applicable');
