--
-- Filename   : drop_table.sql
-- Version    : Speciation Tool 4.0
-- Description: Routine to drop database tables
-- Release    : 12 Sep 2016
--
-- This stored procedure quietly drops a table without those silly error messages
-- when the table does not exist.
--
--ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
--c Copyright (C) 2016  Ramboll Environ
--c Copyright (C) 2007  ENVIRON International Corporation
--c
--c Developed by:  
--c
--c       Michele Jimenez   <mjimenez@environcorp.com>    415.899.0700
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
CREATE OR REPLACE FUNCTION DROP_TABLE(VARCHAR) RETURNS VOID AS
$$
DECLARE
    tname ALIAS FOR $1;
BEGIN
    IF ((SELECT COUNT(*) FROM pg_tables WHERE tablename = tname) > 0) THEN
        EXECUTE 'DROP TABLE ' || tname;
    END IF;
    RETURN;
END;
$$
LANGUAGE 'plpgsql';

