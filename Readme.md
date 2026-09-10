# FYI!: В миграции для заполнения БД снизил количество записей в таблице заказов до с 10_000_000 до 1_000_000 - выданный сервер не справлялся с нагрузкой: https://github.com/estronnom/cloud-services-engineer-dbops-project/actions/runs/34540458192/job/103081709002

# dbops-project
Исходный репозиторий для выполнения проекта дисциплины "DBOps"

## Выдача прав пользователю миграций и автотестов
```sql
CREATE DATABASE store;
CREATE ROLE cicduser WITH LOGIN PASSWORD '...';

\c store

GRANT ALL ON SCHEMA public TO cicduser;

GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO cicduser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cicduser;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES    TO cicduser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO cicduser;
```

## SQL-запрос, который показывает, какое количество сосисок было продано за предыдущую неделю
```sql
-- Вариант без разбивки по дате
select 
    sum(op.quantity) 
from orders o 
join order_product op on o.id = op.order_id 
where 
    o.status = 'shipped' 
    and 
    o.date_created > NOW() - INTERVAL '7 days';

   sum   
---------
 7476815
(1 row)

-- Вариант с разбивкой по дате
select 
    o.date_created, sum(op.quantity) 
from orders o 
join order_product op on o.id = op.order_id 
where 
    o.status = 'shipped' 
    and 
    o.date_created > NOW() - INTERVAL '7 days'
group by o.date_created;

 date_created |  sum   
--------------+--------
 2026-09-04   | 946875
 2026-09-05   | 944512
 2026-09-06   | 947003
 2026-09-07   | 946329
 2026-09-08   | 946884
 2026-09-09   | 948908
 2026-09-10   | 853274

-- Вариант с разбивкой по виду сосиски
with weekly_stats as (
    select 
        op.product_id, sum(op.quantity) total
    from orders o 
    join order_product op on o.id = op.order_id
    where 
        o.status = 'shipped' 
        and 
        o.date_created > NOW() - INTERVAL '7 days'
    group by op.product_id
)
select p.name, ws.total 
    from weekly_stats ws
    join product p on p.id = ws.product_id;

     name      |  total  
---------------+---------
 Сливочная     | 1245890
 Особая        | 1238483
 Молочная      | 1253877
 Нюренбергская | 1244835
 Мюнхенская    | 1247153
 Русская       | 1246577

```

## Сравнение производительности до и после добавления индексов
```sql
-- Проверяем на запросе без группировок
explain analyze select sum(quantity) from orders o join order_product op on o.id = op.order_id where o.status = 'shipped' and o.date_created > NOW()-INTERVAL '7 days';

-- План до создания индекса
Finalize Aggregate  (cost=265929.28..265929.29 rows=1 width=8) (actual time=4412.847..4417.680 rows=1 loops=1)
  ->  Gather  (cost=265929.06..265929.27 rows=2 width=8) (actual time=4411.861..4417.654 rows=3 loops=1)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial Aggregate  (cost=264929.06..264929.07 rows=1 width=8) (actual time=4380.161..4380.163 rows=1 loops=3)
              ->  Parallel Hash Join  (cost=148363.13..264662.30 rows=106706 width=4) (actual time=2394.200..4367.839 rows=85400 loops=3)
                    Hash Cond: (op.order_id = o.id)
                    ->  Parallel Seq Scan on order_product op  (cost=0.00..105361.67 rows=4166667 width=12) (actual time=0.034..561.361 rows=3333333 loops=3)
                    ->  Parallel Hash  (cost=147029.29..147029.29 rows=106707 width=8) (actual time=2392.624..2392.625 rows=85400 loops=3)
                          Buckets: 262144  Batches: 1  Memory Usage: 12128kB
                          ->  Parallel Seq Scan on orders o  (cost=0.00..147029.29 rows=106707 width=8) (actual time=14.008..2342.696 rows=85400 loops=3)
                                Filter: (((status)::text = 'shipped'::text) AND (date_created > (now() - '7 days'::interval)))
                                Rows Removed by Filter: 3247934
Planning Time: 0.357 ms
JIT:
  Functions: 44
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 6.546 ms, Inlining 0.000 ms, Optimization 1.070 ms, Emission 40.945 ms, Total 48.560 ms
Execution Time: 4418.707 ms
(19 rows)

-- План после создания индекса
Finalize Aggregate  (cost=184044.16..184044.17 rows=1 width=8) (actual time=675.153..684.739 rows=1 loops=1)
  ->  Gather  (cost=184043.95..184044.16 rows=2 width=8) (actual time=675.142..684.730 rows=3 loops=1)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial Aggregate  (cost=183043.95..183043.96 rows=1 width=8) (actual time=644.133..644.135 rows=1 loops=3)
              ->  Nested Loop  (cost=3509.87..182777.18 rows=106706 width=4) (actual time=22.139..634.143 rows=85400 loops=3)
                    ->  Parallel Bitmap Heap Scan on orders o  (cost=3509.43..69338.58 rows=106707 width=8) (actual time=22.072..165.099 rows=85400 loops=3)
                          Recheck Cond: (((status)::text = 'shipped'::text) AND (date_created > (now() - '7 days'::interval)))
                          Heap Blocks: exact=24374
                          ->  Bitmap Index Scan on idx_orders_status_date  (cost=0.00..3445.41 rows=256097 width=0) (actual time=30.066..30.067 rows=256199 loops=1)
                                Index Cond: (((status)::text = 'shipped'::text) AND (date_created > (now() - '7 days'::interval)))
                    ->  Index Only Scan using idx_order_product_order_id_qty on order_product op  (cost=0.43..1.05 rows=1 width=12) (actual time=0.005..0.005 rows=1 loops=256199)
                          Index Cond: (order_id = o.id)
                          Heap Fetches: 0
Planning Time: 0.495 ms
JIT:
  Functions: 32
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 1.870 ms, Inlining 0.000 ms, Optimization 0.845 ms, Emission 24.614 ms, Total 27.329 ms
Execution Time: 685.864 ms
(20 rows)
```
