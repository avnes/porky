DROP TABLE porky_purge_tbl
/

CREATE TABLE porky_purge_tbl (
	composite_name VARCHAR2(500) NOT NULL,
	soa_partition_name VARCHAR2(50) DEFAULT 'default' NOT NULL,
	purgeable NUMBER(1) DEFAULT 0 CONSTRAINT porky_purge_tbl_purgeable_ck CHECK (purgeable IN (0,1)) NOT NULL,
	max_runtime NUMBER DEFAULT 60 NOT NULL,
	retention_period NUMBER DEFAULT 7 NOT NULL,
	batch_size NUMBER DEFAULT 20000 NOT NULL,
	ignore_state NUMBER(1) DEFAULT 0 CONSTRAINT porky_purge_tbl_ignore_state_ck CHECK (ignore_state IN (0,1)) NOT NULL,
	contact_name VARCHAR2(128) NOT NULL
)
/

ALTER TABLE porky_purge_tbl ADD CONSTRAINT porky_purge_tbl_uq UNIQUE (composite_name, soa_partition_name)
/

INSERT INTO porky_purge_tbl VALUES ('SimpleApproval','default',1,10,7,20000,0,'dummy@dummy')
/

DROP TABLE porky_purge_log_tbl
/

CREATE TABLE porky_purge_log_tbl (
	composite_name VARCHAR2(500) NOT NULL,
	soa_partition_name VARCHAR2(50) NOT NULL,
	purgeable NUMBER(1) NOT NULL,
	max_runtime NUMBER NOT NULL,
	retention_period NUMBER NOT NULL,
	batch_size NUMBER NOT NULL,
	ignore_state NUMBER NOT NULL,
	cube_num_rec NUMBER NOT NULL,
	purge_phase VARCHAR2(16) NOT NULL,
	purge_date TIMESTAMP(6) NOT NULL
)
/

DROP TABLE porky_purge_err_tbl
/

CREATE TABLE porky_purge_err_tbl (
	error_code VARCHAR2(16) NOT NULL,
	error_text VARCHAR2(128) NOT NULL,
	error_scope VARCHAR2(16) NOT NULL,
	error_date TIMESTAMP NOT NULL
)
/

CREATE OR REPLACE PACKAGE porky_purge_api AS
	-- Will purge BPEL runtime audit data
	PROCEDURE purge;
END porky_purge_api;
/

CREATE OR REPLACE PACKAGE BODY porky_purge_api AS
	g_code NUMBER;
	g_errm VARCHAR2(128);

	FUNCTION getBoolean(p_num_value IN NUMBER) RETURN BOOLEAN IS
	BEGIN
		RETURN p_num_value = 1
	EXCEPTION
		WHEN OTHERS THEN
			g_code := SQLCODE;
			g_errm := SUBSTR(SQLERRM, 1 , 64);
			INSERT INTO porky_purge_err_tbl VALUES (g_code, g_errm, 'getBoolean', SYSTIMESTAMP);
	END;

	PROCEDURE purge IS
		v_cube_num_rec NUMBER;
		CURSOR c_purge_rules IS SELECT * FROM porky_purge_tbl WHERE purgeable=1 ORDER BY 1,2 ASC;
	BEGIN
		FOR l_purge_rules IN c_purge_rules LOOP
			SELECT COUNT(*) INTO v_cube_num_rec FROM cube_instance WHERE composite_name = l_purge_rules.composite_name AND domain_name = l_purge_rules.soa_partition_name;
			INSERT INTO porky_purge_log_tbl VALUES(l_purge_rules.composite_name,l_purge_rules.soa_partition_name,l_purge_rules.purgeable,l_purge_rules.max_runtime,l_purge_rules.retention_period,l_purge_rules.batch_size,l_purge_rules.ignore_state,v_cube_num_rec,'Start',SYSTIMESTAMP);
			soa.delete_instances(
				min_creation_date => SYSTIMESTAMP - INTERVAL '5' YEAR,
				max_creation_date => SYSTIMESTAMP - NUMTODSINTERVAL(l_purge_rules.retention_period,'day'),
				batch_size => l_purge_rules.batch_size,
				max_runtime => l_purge_rules.max_runtime,
				retention_period => SYSTIMESTAMP - NUMTODSINTERVAL(l_purge_rules.retention_period,'day'),
				purge_partitioned_component => false,
				ignore_state => getBoolean(l_purge_rules.ignore_state),
				composite_name => l_purge_rules.composite_name,
				soa_partition_name => l_purge_rules.soa_partition_name);
			SELECT COUNT(*) INTO v_cube_num_rec FROM cube_instance WHERE composite_name = l_purge_rules.composite_name AND domain_name = l_purge_rules.soa_partition_name;
			INSERT INTO porky_purge_log_tbl VALUES(l_purge_rules.composite_name,l_purge_rules.soa_partition_name,l_purge_rules.purgeable,l_purge_rules.max_runtime,l_purge_rules.retention_period,l_purge_rules.batch_size,l_purge_rules.ignore_state,v_cube_num_rec,'Stop',SYSTIMESTAMP);			
		END LOOP;
		COMMIT;
	EXCEPTION
		WHEN OTHERS THEN
			g_code := SQLCODE;
			g_errm := SUBSTR(SQLERRM, 1 , 64);
			INSERT INTO porky_purge_err_tbl VALUES (g_code, g_errm, 'purge', SYSTIMESTAMP);
	END;

END porky_purge_api;
/

COMMIT
/

SELECT * FROM porky_purge_tbl
/

BEGIN
  DBMS_SCHEDULER.create_job (
    job_name        => 'porky_soa_purge_scheduled_job',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN porky_purge_api.purge; END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'freq=daily; byhour=18; byminute=0; bysecond=0',
    end_date        => NULL,
    enabled         => TRUE,
    comments        => 'Repeats daily at 18.00 UTC for ever.');
END;
/

SELECT * FROM dba_scheduler_jobs WHERE owner=USER AND job_name='PORKY_SOA_PURGE_SCHEDULED_JOB'
/

-- The following code can be used to change when to run the job. For instance change the 'byhour' value.
BEGIN
    DBMS_SCHEDULER.set_attribute (
    name      => 'porky_soa_purge_scheduled_job',
    attribute => 'repeat_interval',
    value     => 'freq=daily; byhour=18; byminute=0; bysecond=0');
END;
/
