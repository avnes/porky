CONNECT SOA_SOAINFRA/password@service_name

SET serveroutput ON

BEGIN
	porky_purge_api.purge;
END;
/

COMMIT;

SELECT composite_name, soa_partition_name, purgeable, max_runtime, retention_period, batch_size, ignore_state, cube_num_rec, purge_phase, purge_date 
FROM porky_purge_log_tbl 
WHERE TRUNC(purge_date)=TRUNC(SYSTIMESTAMP)
/

EXIT;
