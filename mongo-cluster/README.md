   This sample describes Mongo database creation and backup and restore mechanism, 
   which can be integrated with NetBackup Client container (Refer k8s-nbu-client sample). 
 
   This is used to manage Mongo database. All the sharded replica
   sets mount the dump volume '<user-name>-nb-dump-pvc' (mounted as
   /mnt/dump inside the container) along with unique data volumes.

   Example:
   mongo.sh create -u <user-name>-mongo-demo -r <user-name>-router \
       -csrs <user-name>-cfg -srs <user-name>-data-1,<user-name>-data-2
   This creates a sample mongodb cluster with:
   i)   1 router
   ii)  1 Config Server Replica Set (with 2 replicas)
   iii) 2 Sharded Replica Set (each with 2 replicas)
   The script also creates a collection and add data to it.

   mongo.sh backup -u <user-name>-mongo-demo -r <user-name>-router
       -csrs <user-name>-cfg -srs <user-name>-data-1,<user-name>-data-2
   This creates a mongo dump of the mongo installation. The dump is stored
   in /mnt/dump/mongo/<shard-name>/dump-<data-string>.

   This command on success, should print a unique restore id.
   Unique ID for restore is <unique-restore-id>.

   To restore stop the existing instance using 'mongo.sh delete'.

   mongo.sh restore -ru <unique-restore-id> -u <user-name>-mongo-demo \
       -r <user-name>-router -csrs <user-name>-cfg \
       -srs <user-name>-data-1,<user-name>-data-2
   This creates an identical mongo cluster that was backed up earlier.
