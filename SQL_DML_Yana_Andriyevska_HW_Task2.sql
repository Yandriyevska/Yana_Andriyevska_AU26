               CREATE TABLE table_to_delete AS
               SELECT 'veeeeeeery_long_string' || x AS col
               FROM generate_series(1,(10^7)::int) x; -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)
               
               COMMIT ;
               
               --SELECT * FROM table_to_delete ;
               
               SELECT *, pg_size_pretty(total_bytes) AS total,
                                    pg_size_pretty(index_bytes) AS INDEX,
                                    pg_size_pretty(toast_bytes) AS toast,
                                    pg_size_pretty(table_bytes) AS TABLE
               FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
                               FROM (SELECT c.oid,nspname AS table_schema,
                                                               relname AS TABLE_NAME,
                                                              c.reltuples AS row_estimate,
                                                              pg_total_relation_size(c.oid) AS total_bytes,
                                                              pg_indexes_size(c.oid) AS index_bytes,
                                                              pg_total_relation_size(reltoastrelid) AS toast_bytes
                                              FROM pg_class c
                                              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
                                              WHERE relkind = 'r'
                                              ) a
                                    ) a
               WHERE table_name LIKE '%table_to_delete%';
               
              --total_bytes 602415104
              --total 575 MB
               
               DELETE FROM table_to_delete
               WHERE REPLACE(col, 'veeeeeeery_long_string','')::int % 3 = 0; -- removes 1/3 of all rows
               
               --almost 6 seconds

               COMMIT ;
               

                SELECT *, pg_size_pretty(total_bytes) AS total,
                                    pg_size_pretty(index_bytes) AS INDEX,
                                    pg_size_pretty(toast_bytes) AS toast,
                                    pg_size_pretty(table_bytes) AS TABLE
               FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
                               FROM (SELECT c.oid,nspname AS table_schema,
                                                               relname AS TABLE_NAME,
                                                              c.reltuples AS row_estimate,
                                                              pg_total_relation_size(c.oid) AS total_bytes,
                                                              pg_indexes_size(c.oid) AS index_bytes,
                                                              pg_total_relation_size(reltoastrelid) AS toast_bytes
                                              FROM pg_class c
                                              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
                                              WHERE relkind = 'r'
                                              ) a
                                    ) a
               WHERE table_name LIKE '%table_to_delete%';
               
                
               -- yet total 575 MB
                /* DELETE works row by row only marks rows as dead (dead tuples). 
                 They stay in the file, so the table size is the same (575 MB).*/
                
                
                COMMIT ;
                VACUUM FULL VERBOSE table_to_delete ;
              --vacuuming "public.table_to_delete"
              --"public.table_to_delete": found 150434 removable, 6666667 nonremovable row versions in 73536 pages
              -- Execute time	4.758s       
                
              --VACUUM FULL rewrites the table into a new file with live rows only and removes the dead ones. 
              -- 2/3 of rows left, so the size became 383 MB (≈ 2/3 of 575 MB). It locks the table while running.    

                
               SELECT *, pg_size_pretty(total_bytes) AS total,
                                    pg_size_pretty(index_bytes) AS INDEX,
                                    pg_size_pretty(toast_bytes) AS toast,
                                    pg_size_pretty(table_bytes) AS TABLE
               FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
                               FROM (SELECT c.oid,nspname AS table_schema,
                                                               relname AS TABLE_NAME,
                                                              c.reltuples AS row_estimate,
                                                              pg_total_relation_size(c.oid) AS total_bytes,
                                                              pg_indexes_size(c.oid) AS index_bytes,
                                                              pg_total_relation_size(reltoastrelid) AS toast_bytes
                                              FROM pg_class c
                                              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
                                              WHERE relkind = 'r'
                                              ) a
                                    ) a
               WHERE table_name LIKE '%table_to_delete%';
                
              -- now total: 383 MB
                
               
               DROP TABLE table_to_delete ;
               
               CREATE TABLE table_to_delete AS
               SELECT 'veeeeeeery_long_string' || x AS col
               FROM generate_series(1,(10^7)::int) x; -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)
                
               
               COMMIT ;
               
               TRUNCATE table_to_delete ;
               
               --Execute time	0.002s
               /* TRUNCATE doesn’t remove rows one by one. 
                It replaces the table’s file with a new empty one, so it’s instant and no dead tuples*/
               
               COMMIT ;
               
               SELECT *, pg_size_pretty(total_bytes) AS total,
                                    pg_size_pretty(index_bytes) AS INDEX,
                                    pg_size_pretty(toast_bytes) AS toast,
                                    pg_size_pretty(table_bytes) AS TABLE
               FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
                               FROM (SELECT c.oid,nspname AS table_schema,
                                                               relname AS TABLE_NAME,
                                                              c.reltuples AS row_estimate,
                                                              pg_total_relation_size(c.oid) AS total_bytes,
                                                              pg_indexes_size(c.oid) AS index_bytes,
                                                              pg_total_relation_size(reltoastrelid) AS toast_bytes
                                              FROM pg_class c
                                              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
                                              WHERE relkind = 'r'
                                              ) a
                                    ) a
               WHERE table_name LIKE '%table_to_delete%';
               
               --total: 8192 bytes
               
               
               
               --DELETE is slow on big tables, and needs VACUUM later. It is good for deleting special rows with WHERE clause.
               --VACUUM FULL gives space back, but is slow and blocks the table.
               --TRUNCATE is the fastest and cleanest way to remove all rows, but it can’t use WHERE and is dangerous to use, especially with cascade 
               --also not every database allow TRUNCATE inside transaction (to use rollback if needed)
               
               
               