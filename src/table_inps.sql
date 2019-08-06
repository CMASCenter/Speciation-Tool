-- Filename   : table_inps.sql
-- Author     : M Jimenez, ENVIRON International Corp.
-- Version    : Speciation Tool 4.0
-- Description: Create tables for scenario inputs
-- Release    : 12 Sep 2016
--
--   Sql script to create speciation tool tables for input files.
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
--c 		-- moved tbl_haps to temporary table in makesplit
--c		-- process mode table is now a user input 
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

CREATE OR REPLACE FUNCTION Inputs_CreateTables() RETURNS VOID AS
'
BEGIN

-- run control table
--IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = "tbl_run_control") > 0) THEN 
--	DROP TABLE tbl_run_control;
--END IF; 
CREATE TABLE tbl_run_control
(
    keyword              VARCHAR(20)   NOT NULL,
    dataval              VARCHAR       NOT NULL
) WITHOUT OIDS;

-- process_pollutant list for VOCs
CREATE TABLE tbl_gas_process
(
    profile_id          VARCHAR(20)     NOT NULL,
    process             VARCHAR(20)     NOT NULL
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_gas_process
  ON tbl_gas_process (profile_id, process);

-- toxics table
--IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = "tbl_toxics") > 0) THEN 
--	DROP TABLE tbl_toxics;
--END IF; 
-- primary_pollutant list for toxic 

CREATE TABLE tbl_primary
(
    aqminv_poll          VARCHAR(20)   NOT NULL,
    aqm_add              VARCHAR(20)   NOT NULL,
    split_factor         NUMERIC(12,8)   NOT NULL,
    writeflag            VARCHAR(1)    NOT NULL
) WITHOUT OIDS;

CREATE INDEX idx_primary
  ON tbl_primary (aqminv_poll, aqm_add, split_factor, writeflag);

CREATE TABLE tbl_toxics
(
    aqm_model             VARCHAR(20)   NOT NULL,
    specie_id            VARCHAR(20)   NOT NULL,
    aqm_poll             VARCHAR(20)   NOT NULL,
    num_carbons          NUMERIC(6,3),
    active               VARCHAR(1)
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_toxics
  ON tbl_toxics (aqm_model, specie_id, aqm_poll);

-- user specified weight profiles table
--IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = "tbl_user_profile_wts" > 0) THEN 
--	DROP TABLE tbl_user_profile_wts;
--END IF; 
CREATE TABLE tbl_user_profile_wts
(
    profile_id          VARCHAR(20)     NOT NULL,
    specie_id           VARCHAR(20)     NOT NULL,
    percent             NUMERIC(10,6)   NOT NULL
) WITHOUT OIDS;

CREATE UNIQUE INDEX idx_user_profile_wts
  ON tbl_user_profile_wts (profile_id, specie_id );

RETURN;
END;
'
LANGUAGE plpgsql;

