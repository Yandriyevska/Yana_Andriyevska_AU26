--Part 1: Write SQL queries to retrieve the following data. 

/*
 1. The marketing team needs a list of animation movies between 2017 and 2019 to promote family-friendly content in an upcoming season in stores. 
Show all animation movies released during this period with rate more than 1, sorted alphabetically 
*/

--I've provided ID in the result in case of appearance movies with the same title

--JOIN
SELECT f.film_id, 
       f.title,
       f.rental_rate 
FROM public.film f JOIN public.film_category fc ON f.film_id = fc.film_id 
  JOIN public.category cat ON fc.category_id = cat.category_id
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND LOWER(cat."name") = 'animation' -- I've checked that we have only one animation category, and if there will be error in future than we have duplicated data
ORDER BY f.title ;

--Subquery
SELECT f.film_id, 
       f.title,
       f.rental_rate 
FROM public.film f
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND f.film_id IN (
                   SELECT fc.film_id 
                   FROM film_category fc 
                   WHERE fc.category_id =
				                        (
				                        SELECT cat.category_id 
				                        FROM public.category cat 
				                        WHERE LOWER(cat."name") = 'animation'
				                        )
				   )
ORDER BY f.title ;


--CTE
WITH animation_category AS 
(
 SELECT cat.category_id 
 FROM public.category cat 
 WHERE LOWER(cat."name") = 'animation'
),
animation_film AS
(
 SELECT fc.film_id 
 FROM film_category fc, animation_category an_cat
 WHERE fc.category_id = an_cat.category_id
)
SELECT f.film_id, 
       f.title,
       f.rental_rate 
FROM public.film f, animation_film an_f
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND f.film_id = an_f.film_id 
ORDER BY f.title ;



--in my solution I would combine JOIN and subquery to make it more readable
SELECT f.film_id, 
       f.title,
       f.rental_rate 
FROM public.film f JOIN public.film_category fc 
ON f.film_id = fc.film_id 
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND fc.category_id = (
                        SELECT cat.category_id 
                        FROM public.category cat
                        WHERE LOWER(cat."name") = 'animation'
                        )
ORDER BY f.title ;



/*
 2.The finance department requires a report on store performance to assess profitability and plan resource allocation for stores after March 2017. 
 Calculate the revenue earned by each rental store after March 2017 (since April) (include columns: address and address2 – as one column, revenue)
 */


--CTE (preferable)
WITH store_revenue AS
(
	SELECT i.store_id,
	       SUM(p.amount) revenue
	FROM public.payment p
	JOIN public.rental r ON p.rental_id = r.rental_id
	JOIN public.inventory i ON r.inventory_id = i.inventory_id
	WHERE p.payment_date >= DATE '2017-04-01'
	GROUP BY i.store_id
)
SELECT RTRIM(a.address || ' ' || COALESCE(a.address2, '')) store_address,
       COALESCE(sr.revenue, 0) revenue
FROM public.store s
JOIN public.address a ON s.address_id = a.address_id
LEFT JOIN store_revenue sr ON s.store_id = sr.store_id ;   --if we have stores without revenue


--JOIN  
SELECT RTRIM(a.address || ' ' || COALESCE(a.address2, '')) store_address,
       COALESCE(SUM(p.amount), 0) revenue
FROM public.store s
JOIN public.address a ON s.address_id = a.address_id
LEFT JOIN public.inventory i ON i.store_id = s.store_id
LEFT JOIN public.rental r ON r.inventory_id = i.inventory_id
LEFT JOIN public.payment p ON p.rental_id = r.rental_id
                   AND p.payment_date >= DATE '2017-04-01'  --date is in ON, because if I put it in WHERE the left join becomes inner
GROUP BY RTRIM(a.address || ' ' || COALESCE(a.address2, '')) ;


--Subquery(not convenient)
SELECT RTRIM(a.address || ' ' || COALESCE(a.address2, '')) store_address,
       COALESCE((SELECT SUM(p.amount)
                 FROM public.payment p
                 WHERE p.payment_date >= DATE '2017-04-01'
                   AND p.rental_id IN (SELECT r.rental_id
                                       FROM public.rental r
                                       WHERE r.inventory_id IN (SELECT i.inventory_id
                                                                FROM public.inventory i
                                                                WHERE i.store_id = s.store_id))), 0) revenue
FROM public.store s
JOIN public.address a ON s.address_id = a.address_id ;


/*
 3.The marketing department in our stores aims to identify the most successful actors since 2015 to boost customer interest in their films. 
 Show top-5 actors by number of movies (released since 2015) they took part in 
 (columns: first_name, last_name, number_of_movies, sorted by number_of_movies in descending order)
 */

--Subquery
SELECT act.first_name, act.last_name, count(fa.film_id) number_of_movies
FROM public.actor act 
JOIN public.film_actor fa ON  act.actor_id = fa.actor_id 
WHERE fa.film_id IN (
					SELECT f.film_id 
					FROM public.film f
					WHERE f.release_year >= 2015)
GROUP BY act.actor_id, act.first_name, act.last_name
ORDER BY number_of_movies DESC, act.last_name, act.first_name
FETCH FIRST 5 ROWS WITH TIES; --if several actors have the number of movies result we can't choose randomly 


--JOIN
SELECT act.first_name,
       act.last_name,
       COUNT(f.film_id) number_of_movies
FROM public.actor act
JOIN public.film_actor fa ON act.actor_id = fa.actor_id
JOIN public.film f ON fa.film_id = f.film_id
WHERE f.release_year >= 2015
GROUP BY act.actor_id, act.first_name, act.last_name
ORDER BY number_of_movies DESC
FETCH FIRST 5 ROWS WITH TIES;


--CTE we can do but it doesn't make sense 
WITH actor_movies AS
(
	SELECT act.first_name,
	       act.last_name,
	       COUNT(f.film_id) number_of_movies
	FROM public.actor act
	JOIN public.film_actor fa ON act.actor_id = fa.actor_id
	JOIN public.film f ON fa.film_id = f.film_id
	WHERE f.release_year >= 2015
	GROUP BY act.actor_id, act.first_name, act.last_name
)
SELECT first_name, last_name, number_of_movies
FROM actor_movies
ORDER BY number_of_movies DESC
FETCH FIRST 5 ROWS WITH TIES;



/*
4.The marketing team needs to track the production trends of Drama, Travel, and Documentary films to inform genre-specific marketing strategies. 
Show number of Drama, Travel, Documentary per year (include columns: release_year, number_of_drama_movies, number_of_travel_movies, number_of_documentary_movies),
sorted by release year in descending order. Dealing with NULL values is encouraged)
*/


--CTE
WITH chosen_categories AS 
(
 SELECT cat.category_id, cat."name" category_name
 FROM public.category cat 
 WHERE LOWER(cat."name") IN ('drama', 'travel', 'documentary')
),
chosen_films AS
(
 SELECT fc.film_id, ch_cat.category_id , ch_cat.category_name
 FROM public.film_category fc 
 JOIN chosen_categories ch_cat ON fc.category_id = ch_cat.category_id
 )
 SELECT f.release_year,
        SUM(CASE WHEN LOWER(ch_f.category_name) = 'drama' THEN 1 ELSE 0	END) number_of_drama_movies, --null values are not possible with 0 condition
        SUM(CASE WHEN LOWER(ch_f.category_name) = 'travel' THEN 1 ELSE 0 END) number_of_travel_movies,
        SUM(CASE WHEN LOWER(ch_f.category_name) = 'documentary' THEN 1 ELSE 0 END) number_of_documentary_movies
 FROM public.film f
 LEFT JOIN chosen_films ch_f  ON f.film_id = ch_f.film_id
 GROUP BY f.release_year
 ORDER BY f.release_year DESC

 

 --JOIN
 SELECT f.release_year,
       SUM(CASE WHEN LOWER(cat."name") = 'drama' THEN 1 ELSE 0 END) number_of_drama_movies,
       SUM(CASE WHEN LOWER(cat."name") = 'travel' THEN 1 ELSE 0 END) number_of_travel_movies,
       SUM(CASE WHEN LOWER(cat."name") = 'documentary' THEN 1 ELSE 0 END) number_of_documentary_movies
FROM public.film f
LEFT JOIN public.film_category fc ON f.film_id = fc.film_id
LEFT JOIN public.category cat ON fc.category_id = cat.category_id
                      AND LOWER(cat."name") IN ('drama', 'travel', 'documentary') --condition in ON clause because of left join (we don't want filtering all rows with no match)
GROUP BY f.release_year
ORDER BY f.release_year DESC ;


--Subquery doesn't make sense here, because count films for each year of every genre with a separate subquery is inefficient
SELECT y.release_year,
       (SELECT COUNT(*)
        FROM public.film f
        WHERE f.release_year = y.release_year
          AND f.film_id IN (SELECT fc.film_id
                            FROM public.film_category fc
                            WHERE fc.category_id IN (SELECT cat.category_id
                                                     FROM public.category cat
                                                     WHERE LOWER(cat."name") = 'drama'))) number_of_drama_movies,
       (SELECT COUNT(*)
        FROM public.film f
        WHERE f.release_year = y.release_year
          AND f.film_id IN (SELECT fc.film_id
                            FROM public.film_category fc
                            WHERE fc.category_id IN (SELECT cat.category_id
                                                     FROM public.category cat
                                                     WHERE LOWER(cat."name") = 'travel'))) number_of_travel_movies,
       (SELECT COUNT(*)
        FROM public.film f
        WHERE f.release_year = y.release_year
          AND f.film_id IN (SELECT fc.film_id
                            FROM public.film_category fc
                            WHERE fc.category_id IN (SELECT cat.category_id
                                                     FROM public.category cat
                                                     WHERE LOWER(cat."name") = 'documentary'))) number_of_documentary_movies
FROM (SELECT DISTINCT release_year FROM film) y
ORDER BY y.release_year DESC ;

 
--Part 2: Solve the following problems using SQL

/*
 1.The HR department aims to reward top-performing employees in 2017 with bonuses to recognize their contribution to stores revenue. 
Show which three employees generated the most revenue in 2017? 
Assumptions: 
staff could work in several stores in a year, please indicate which store the staff worked in (the last one);
if staff processed the payment then he works in the same store; 
take into account only payment_date
*/


WITH payments_2017 AS
(
	SELECT p.payment_id, p.staff_id, p.rental_id, p.amount, p.payment_date
	FROM public.payment p
	WHERE p.payment_date >= DATE '2017-01-01'
	  AND p.payment_date <  DATE '2018-01-01'
),
staff_revenue AS
(
	SELECT pay_yr.staff_id,
	       SUM(pay_yr.amount) revenue
	FROM payments_2017 pay_yr
	GROUP BY staff_id
),
last_store AS
(
	SELECT DISTINCT ON (pay_yr.staff_id)
	       pay_yr.staff_id,
	       i.store_id
	FROM payments_2017 pay_yr
	JOIN public.rental r ON pay_yr.rental_id = r.rental_id
	JOIN public.inventory i ON r.inventory_id = i.inventory_id
	ORDER BY pay_yr.staff_id, pay_yr.payment_date DESC, pay_yr.payment_id DESC   --only last employee's payment defines store
)
SELECT s.staff_id,
       s.first_name,
       s.last_name,
       ls.store_id,
       sr.revenue
FROM public.staff s
JOIN staff_revenue sr ON s.staff_id = sr.staff_id
LEFT JOIN last_store ls ON s.staff_id = ls.staff_id
ORDER BY sr.revenue DESC
LIMIT 3;      --I assume that exactly same revenue is impossible

--JOIN
--I didn't find the way to perform the task without CTE ot subquery

--Sunquery
-- revenue is a subquery, store of the last 2017 payment is found by another subquery
SELECT s.staff_id,
       s.first_name,
       s.last_name,
       (SELECT i.store_id
        FROM public.inventory i
        WHERE i.inventory_id IN (SELECT r.inventory_id
                                 FROM public.rental r
                                 WHERE r.rental_id = (SELECT p.rental_id
                                                      FROM public.payment p
                                                      WHERE p.staff_id = s.staff_id
                                                        AND p.payment_date >= DATE '2017-01-01'
                                                        AND p.payment_date <  DATE '2018-01-01'
                                                      ORDER BY p.payment_date DESC, p.payment_id DESC
                                                      LIMIT 1))) store_id,
       (SELECT SUM(p.amount)
        FROM public.payment p
        WHERE p.staff_id = s.staff_id
          AND p.payment_date >= DATE '2017-01-01'
          AND p.payment_date <  DATE '2018-01-01') revenue
FROM public.staff s
WHERE EXISTS (SELECT 1
              FROM public.payment p
              WHERE p.staff_id = s.staff_id
                AND p.payment_date >= DATE '2017-01-01'
                AND p.payment_date <  DATE '2018-01-01')
ORDER BY revenue DESC, s.staff_id
LIMIT 3;


/*
 2. The management team wants to identify the most popular movies and their target audience age groups to optimize marketing efforts. 
 Show which 5 movies were rented more than others (number of rentals), and what's the expected age of the audience for these movies? 
 */

--CTE
WITH film_rentals AS
(
	SELECT f.film_id,
	       f.title,
	       f.rating,
	       COUNT(r.rental_id) number_of_rentals
	FROM public.film f
	JOIN public.inventory i ON f.film_id = i.film_id
	JOIN public.rental r ON i.inventory_id = r.inventory_id
	GROUP BY f.film_id, f.title, f.rating
)
SELECT title,
       number_of_rentals,
       rating,
       (CASE rating::text 
       		 WHEN 'G'     THEN 'All ages'
             WHEN 'PG'    THEN 'All ages, parental guidance suggested'
             WHEN 'PG-13' THEN '13+'
             WHEN 'R'     THEN '17+ (younger only with an adult)'
             WHEN 'NC-17' THEN '18+'
             ELSE 'Unknown'
             END) expected_age
FROM film_rentals
ORDER BY number_of_rentals DESC
FETCH FIRST 5 ROWS WITH TIES;




--Part 3. Which actors/actresses didn't act for a longer period of time than the others? 
/*
The stores’ marketing team wants to analyze actors' inactivity periods to select those with notable career breaks for targeted promotional campaigns, 
highlighting their comebacks or consistent appearances to engage customers with nostalgic or reliable film stars
The task can be interpreted in various ways, and here are a few options (provide solutions for each one):
V1: gap between the latest release_year and current year per each actor;
V2: gaps between sequential films per each actor;
 */

--V1

--JOIN
SELECT act.first_name,
       act.last_name,
       MAX(f.release_year) last_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE) - MAX(f.release_year) years_inactive
FROM public.actor act
JOIN public.film_actor fa ON act.actor_id = fa.actor_id
JOIN public.film f ON fa.film_id = f.film_id
GROUP BY act.actor_id, act.first_name, act.last_name
ORDER BY years_inactive DESC, act.last_name, act.first_name;


--CTE
WITH actor_last_film AS
(
	SELECT act.actor_id,
	       act.first_name,
	       act.last_name,
	       MAX(f.release_year) last_release_year
	FROM public.actor act
	JOIN public.film_actor fa ON act.actor_id = fa.actor_id
	JOIN public.film f ON fa.film_id = f.film_id
	GROUP BY act.actor_id, act.first_name, act.last_name
)
SELECT first_name,
       last_name,
       last_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE) - last_release_year years_inactive
FROM actor_last_film
ORDER BY years_inactive DESC, last_name, first_name;


--V2
-- gaps between sequential films over 5(optional) years in one cte, then for each actor keep only the most recent one
WITH actor_years AS
(
	SELECT DISTINCT fa.actor_id,
	       f.release_year
	FROM public.film_actor fa
	JOIN public.film f ON fa.film_id = f.film_id
),
actor_gaps AS
(
	SELECT ay1.actor_id,
	       ay1.release_year,
	       MIN(ay2.release_year) next_release_year
	FROM actor_years ay1
	JOIN actor_years ay2 ON ay1.actor_id = ay2.actor_id
	                    AND ay2.release_year > ay1.release_year
	GROUP BY ay1.actor_id, ay1.release_year
),
big_gaps AS
(
	SELECT actor_id,
	       release_year,
	       next_release_year,
	       next_release_year - release_year gap_years
	FROM actor_gaps
	WHERE next_release_year - release_year >= 5   --with notable career breaks only (I would check the period with the team) 
),
last_big_gap AS
(
	SELECT actor_id,
	       MAX(release_year) release_year
	FROM big_gaps
	GROUP BY actor_id
)
SELECT act.first_name,
       act.last_name,
       bg.release_year,
       bg.next_release_year,
       bg.gap_years
FROM last_big_gap lbg
JOIN big_gaps bg ON lbg.actor_id = bg.actor_id
                AND lbg.release_year = bg.release_year
JOIN public.actor act ON bg.actor_id = act.actor_id
ORDER BY  bg.gap_years DESC





--select * from public.film f;
--select * from public.inventory i ;
--select * from public.rental r ;
--select * from public.payment i ;
--select * from public.category cat ;
--select * from public.address a ;
--select * from public.actor act ;
