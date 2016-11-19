CONNECT SOA_SOAINFRA/password@service_name

SET serveroutput ON

BEGIN
	porky_purge_api.purge;
END;
/

COMMIT;

SELECT * FROM porky_purge_log_tbl WHERE TRUNC(purge_date)=TRUNC(SYSTIMESTAMP)
/

EXIT;
