
--TRANSACTION is already opened

SELECT table_name, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name  = 'last_update' ;

SELECT * FROM public.film f 
WHERE f.title IN ('ATONEMENT', 'BACK TO THE FUTURE', 'MULAN') ;

--Every INSERT, UPDATE and DELETE in separate transaction so a failure rolls back only these rows; 
--NOT EXISTS prevents duplicates, and ids come from JOINs/subqueries, so foreign keys always point to existing rows.

INSERT INTO public.film (title, release_year, language_id, rental_duration, rental_rate)
SELECT v.title,
       v.release_year,
       (SELECT MIN(l.language_id) FROM public.language l WHERE l.name = 'English'),
       v.rental_duration,
       v.rental_rate
FROM (VALUES
    ('ATONEMENT',          2007, 1, 4.99),
    ('BACK TO THE FUTURE', 1985, 2, 9.99),
    ('MULAN',              1998, 3, 19.99)
) AS v(title, release_year, rental_duration, rental_rate)
WHERE NOT EXISTS (
    SELECT 1
    FROM public.film f
    WHERE UPPER(f.title) = v.title
      AND f.release_year = v.release_year
)
RETURNING *;

SELECT * FROM public.film f ;

COMMIT ;


INSERT INTO public.actor (first_name, last_name)
SELECT v.first_name, v.last_name
FROM (VALUES                      --VALUES creates a temporary table from rows directly within the query
    ('KEIRA', 'KNIGHTLEY'),
    ('JAMES', 'MCAVOY'),
    ('MICHAEL J.', 'FOX'),
    ('CHRISTOPHER', 'LLOYD'),
    ('MING-NA', 'WEN'),
    ('EDDIE', 'MURPHY')
) AS v(first_name, last_name)     --give the names to columns
WHERE NOT EXISTS (
    SELECT 1 FROM public.actor act
    WHERE UPPER(act.first_name) = v.first_name
      AND UPPER(act.last_name)  = v.last_name
)
RETURNING actor_id, first_name, last_name ;

SELECT * FROM public.actor a ;

COMMIT ;

INSERT INTO public.film_actor (actor_id, film_id)
SELECT act.actor_id, f.film_id
FROM (VALUES
    ('KEIRA',       'KNIGHTLEY', 'ATONEMENT',         2007),       --preventing hardcoding (autoincrement id usage in filters)
    ('JAMES',       'MCAVOY',    'ATONEMENT',         2007),
    ('MICHAEL J.',  'FOX',       'BACK TO THE FUTURE', 1985),
    ('CHRISTOPHER', 'LLOYD',     'BACK TO THE FUTURE', 1985),
    ('MING-NA',     'WEN',       'MULAN',             1998),
    ('EDDIE',       'MURPHY',    'MULAN',             1998)
) AS v(first_name, last_name, title, release_year)
JOIN public.actor act ON UPPER(act.first_name) = v.first_name
              AND UPPER(act.last_name)  = v.last_name
JOIN public.film f    ON UPPER(f.title) = v.title
              AND f.release_year = v.release_year
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor fa
    WHERE fa.actor_id = act.actor_id
      AND fa.film_id  = f.film_id
)
RETURNING actor_id, film_id ;
   		      

SELECT * FROM public.film_actor fa ;

COMMIT ;

INSERT INTO public.inventory (film_id, store_id)
SELECT f.film_id, (SELECT MAX(s.store_id) FROM public.store s) --last store
FROM (VALUES
    ('ATONEMENT',         2007),
    ('BACK TO THE FUTURE', 1985),
    ('MULAN',             1998)
) AS v(title, release_year)
JOIN public.film f ON UPPER(f.title) = v.title
                  AND f.release_year = v.release_year
WHERE NOT EXISTS (
    	SELECT 1 FROM public.inventory i
   		WHERE i.film_id  = f.film_id
     	  AND i.store_id = (SELECT MAX(s.store_id) FROM public.store s) --preventing duplication
                 )
RETURNING inventory_id, film_id, store_id ;

SELECT * FROM public.inventory i ;

COMMIT;


SELECT c.customer_id
FROM public.customer c
WHERE (SELECT COUNT(*) FROM public.rental  r WHERE r.customer_id = c.customer_id) >= 43
  AND (SELECT COUNT(*) FROM public.payment p WHERE p.customer_id = c.customer_id) >= 43
ORDER BY c.customer_id
LIMIT 1 ;

SELECT * FROM public.address a ;  



UPDATE public.customer
SET first_name = 'YANA',
    last_name = 'ANDRIYEVSKA',
    address_id = (SELECT MIN(ad.address_id)
                  FROM public.address ad
                  WHERE ad.address = '48 Maracabo Place'),
    email = NULL,
    last_update = NOW()
WHERE customer_id = (SELECT c.customer_id
                     FROM public.customer c
                     WHERE (SELECT COUNT(*) FROM public.rental  r WHERE r.customer_id = c.customer_id) >= 43
                       AND (SELECT COUNT(*) FROM public.payment p WHERE p.customer_id = c.customer_id) >= 43
                     ORDER BY c.customer_id
                     LIMIT 1)
  AND NOT EXISTS (SELECT 1
                  FROM public.customer x
                  WHERE x.first_name = 'YANA'
                    AND x.last_name  = 'ANDRIYEVSKA')
RETURNING * ;

SELECT * FROM public.customer c ;

COMMIT ;
    

SELECT * 
FROM public.payment pay
WHERE pay.customer_id = (SELECT c.customer_id
                         FROM public.customer c 
                         WHERE first_name = 'YANA'
                           AND last_name = 'ANDRIYEVSKA') ;


DELETE FROM public.payment                                 --a rerun also deletes the previous run's rows;
WHERE customer_id = (SELECT c.customer_id
                  	 FROM public.customer c 
              		 WHERE first_name = 'YANA'
                       AND last_name = 'ANDRIYEVSKA')
RETURNING * ;


COMMIT ;


SELECT * 
FROM public.rental r 
WHERE customer_id = (SELECT c.customer_id
                     FROM public.customer c 
                     WHERE first_name = 'YANA'
                       AND last_name = 'ANDRIYEVSKA') ;


DELETE FROM public.rental                             --a rerun also deletes the previous run's rows; the INSERTs below recreate them, so the final state is always the same.
WHERE customer_id = (SELECT c.customer_id
                     FROM public.customer c 
                     WHERE first_name = 'YANA'
                       AND last_name = 'ANDRIYEVSKA')
RETURNING * ;

                  
COMMIT ;
  


CREATE TABLE IF NOT EXISTS public.payment_p2026_11 PARTITION OF public.payment
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01'); 

CREATE TABLE IF NOT EXISTS public.payment_p2026_12 PARTITION OF public.payment
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01'); 

SELECT inhrelid::regclass AS partition_name
FROM pg_inherits
WHERE inhparent = 'public.payment'::regclass;

COMMIT ;


SELECT * FROM public.staff st ;


INSERT INTO public.rental (rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT NOW(),
       i.inventory_id,
       c.customer_id,
       NOW() + f.rental_duration * INTERVAL '1 day',
       (SELECT MIN(st.staff_id)
        FROM public.staff st
        WHERE st.store_id = i.store_id)
FROM (VALUES
         ('ATONEMENT',          2007),
         ('BACK TO THE FUTURE', 1985),
         ('MULAN',              1998)
     ) AS v(title, release_year)
JOIN public.film f ON UPPER(f.title) = v.title
                   AND f.release_year = v.release_year
JOIN public.inventory i ON i.inventory_id = (SELECT MIN(i2.inventory_id)
                                             FROM public.inventory i2
                                             WHERE i2.film_id = f.film_id)
JOIN public.customer c  ON c.customer_id = (SELECT MAX(c2.customer_id)
                                            FROM public.customer c2
                                            WHERE c2.first_name = 'YANA'
                                              AND c2.last_name  = 'ANDRIYEVSKA')
WHERE NOT EXISTS (
    SELECT 1
    FROM public.rental r
    JOIN public.inventory i3 ON i3.inventory_id = r.inventory_id
    WHERE r.customer_id = c.customer_id
      AND i3.film_id    = f.film_id
)
RETURNING *;

SELECT *
FROM public.rental ;

COMMIT ;



INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT r.customer_id,
       r.staff_id,
       r.rental_id,
       f.rental_rate,
       NOW()
FROM public.rental r
JOIN public.inventory i ON i.inventory_id = r.inventory_id
JOIN public.film f      ON f.film_id      = i.film_id
WHERE r.customer_id = (SELECT MAX(c.customer_id)
                       FROM public.customer c
                       WHERE c.first_name = 'YANA'
                         AND c.last_name  = 'ANDRIYEVSKA')
  AND NOT EXISTS (
      SELECT 1
      FROM public.payment p
      WHERE p.rental_id = r.rental_id
  )
RETURNING *;


SELECT * FROM public.payment p 
ORDER BY p.payment_date DESC ;

COMMIT ;





