# porky - Purge or kindly yield 
Porky is a tool to manage BPEL instance cleanup. 

When running BPEL components in Oracle® SOA Suite, a lot of audit data will be saved to metadata tables the \<prefix>_SOAINFRA. The amount of metadata depends on which Audit Level that has been configured on the composite or its BPEL components. The Audit Level is also set globally on the SOA server, but the deployed composited can override this. 

The tree Audit Levels are:
* Development (used ad hoc for DEBUG purposed)
* Production (recommended)
* Off

It is paramount to have a strategy in place to purge this metadata on a regular basis. By default a generic purging rule is enabled on the server, but if you want something more fine grained: Enter Porky.

Every project and developer submitting new composites must reflect on how often their metadata should be purged. Please note that only metadata for Terminated or Failed will be purged. Any asynchronous composite that is still in any form of RUNNING or waiting state will not be purged. This is taken care of by Porky's use of the standard purge API.

##Installation
An installation of Oracle SOA Suite will contain an API for purging instance metadata. Utilizing this API, I have written a custom wrapper called porky_purge_api, which can help control what to purge, how to purge, and when to purge.

1. Connect to the database as the user that owns the SOA database metadata. This user has a name on the format \<prefix>_SOAINFRA. For instance: SOA_SOAINFRA
2. Once connected to the \<prefix>_SOAINFRA schema, run the build_porky.sql script

If this is the first time you run the installation, you will get some errors when trying to drop tables:

<code>ORA-00942: table or view does not exist</code>

This error can be ignored. Any other error needs to be investigated and dealt with.

## Configuration
When a new composite has been deployed, the developer needs to configure purging rules for his/her composite. This is done in the porky_purge_tbl, and every value is compliant with the corresponding argument in the official purge API.

1. **Should the metadata for the new composite be purged on a regular basis?** The answer to this question should only very rarely be ‘no’. The only time where it makes sense to answer ‘no’ and not continue this reflection, is it the audit data for the composite contains actual data that you rely on for further use. The name of the parameter is “purgeable” ”, and it expects a numeric value of 0 for NO or 1 for YES.
2. **How many minutes every day should be spent on purging?** You should pick a number that ensures that you purge at least the same as-, or more- metadata for your composite that the daily growth. At the same time you need to consider which other composites runs on the server, and make sure you take your fair share compared to the others. Finally purging should only take place after business hours as it comes with a performance impact. Choosing 30 minutes is probably a good starting point, and it can be adjusted later if needed. Please note that the value you choose here serves only as a guiding principle to the API. For instance if the API spends 50 minutes on running through the first batch of records to purge, it will note that 50 minutes is lesser than your desired 60 minutes and it will start a new batch. If there are enough records to purge, the API will continue for another 50 minutes resulting in spending 1 hour 40 minutes on a job you only wanted to spend 60 minutes on. The name of the parameter is “max_runtime”, and it expects a numeric value to contain the number of minutes you want it to run.
3. **What should the retention period be?** This means that it must be considered for how long audit data should be kept after the composite has finished running its instances. A higher retention period means a lot more metadata will be kept, and it also means that it will take longer time to perform the daily purge due to the higher volume of data. Unless there is a specific business case that says otherwise, it should be set to 7 days. The name of the parameter is “retention_period” ”, and it expects a numeric value to contain the number of days to keep.
4. **What should the batch size be?** Just as max_runtime mentioned above, this is just a guideline to the purge API. This tells the API how many records it should delete before issuing a COMMIT. A too small batch size will have a performance impact as a COMMIT results in costly I/O. On the other hand, a too large batch size will have a performance impact if something goes wrong and the database needs to ROLLBACK, and as mentioned in the same context as max_runtime, it can skew the overall time spent on purging. Keeping the default batch size of 20000 is usually a good idea. The name of the parameter is “batch_size”, and it expects a numeric value.
5. **Should we ignore instance state? Can we purge instance that are still RUNNING?** This might sound like a strange question, but in some very rare cases it makes sense to purge running composites as well. For instance if you have some really long running asynchronous instances, where the data it contain already has become obsolete. For 99% of all composites, the answer to this question should be a load ‘NO!’ The name of the parameter is “batch_size”, and it expects a numeric value of 0 for NO or 1 for YES.
6. **Who should be the contact for issues related to purging the new composite?** The name of this parameter is contact_name, which expects an alphanumeric value containing an email address.

In addition to the questions above, you will also need the name of the composite and the name of the partition that the composite was deployed to.

##Prepare
Connect to the database schema \<prefix>_SOAINFRA. For instance: SOA_SOAINFRA

##Syntax
```sql
INSERT INTO porky_purge_tbl VALUES (
composite_name, 
soa_partition_name, 
purgeable, 
max_runtime, 
retention_period, 
batch_size, 
ignore_state,
contact_name)
/

COMMIT
/
```

##Example
```sql
INSERT INTO porky_purge_tbl VALUES ('MyNewComposite','MyCoolProject',1,10,7,20000,0,'dummy@dummy')
/

COMMIT
/
```

##Manual purging
After connecting to the \<prefix>_SOAINFRA schema, run the following to do start a manual purge:
```sql
SET serveroutput ON
BEGIN
	porky_purge_api.purge;
END;
/
```

##Automatic purging
During the installation of this custom wrapper on top of the official purge API, automated scheduling of purging has already been configured to run every day at 18.00 UTC for ever.
After connecting to the \<prefix>_SOAINFRA schema, run the following to see how this automated job has been configured:

```sql
SELECT * FROM dba_scheduler_jobs  
WHERE owner=USER  
AND job_name='PORKY_SOA_PURGE_SCHEDULED_JOB'  
/  
```

##Reschedule
If you prefer that purging starts at different time than 18.00 UTC, you can use the following block of code to change it, for instance to 20.30 UTC, connect to the \<prefix>_SOAINFRA schema, and run the following block of code:

```sql
BEGIN
  DBMS_SCHEDULER.set_attribute (
    name      => 'porky_soa_purge_scheduled_job',  
    attribute => 'repeat_interval',  
    value     => 'freq=daily; byhour=20; byminute=30; bysecond=0');  
END;  
/
```

##Auditing
Every time the custom wrapper for the SOA purge is run, it will log its execution statistics to a log file. This is useful for a several purposes:

* How long did it take to purge instance data for each composite?
* Do we need to adjust the number of minutes spent on purging?
* How many records in the CUBE_INSTANCE table were purged?
* After connecting to the \<prefix>_SOAINFRA schema, run the following query to look at the log:

```sql
SELECT * FROM porky_purge_log_tbl ORDER BY PURGE_DATE DESC
/
```

##Error logging
If something goes wrong during purging, the errors are saved to an error log table. To view this table, connect to the \<prefix>_SOAINFRA schema and run the following query:

```sql
SELECT * FROM porky_purge_err_tbl ORDER BY ERROR_DATE DESC 
/
```
