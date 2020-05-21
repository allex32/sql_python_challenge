declare @start_date as date
declare @end_date as date
declare @revenue_boundary as float

--Границы окна (в качестве примера)
set @start_date = '2020-01-02'
set @end_date = '2020-01-09';

set @revenue_boundary = 0;

-- Общий подход:
--1) Пересчитываем min и max для окна.
--2) Для min : 
-- a) обрезаем хранящуюся витрину по крайней левой границе временного окна. (<=). 
-- Оставшиеся в витрине min - гарантированные min, т.к. вычисленны по гарантированно неизменяемым данных.
-- б) Добавляем все min, которые вычислены в рамках окна и при этом отсутствуют в усеченной витрине.
---
-- 3) Для max:
--	а) Высчитываем и храним max для неизменяемых данных
--	б) Высчитываем max для окна
--	в) Union (а) и (б) с последующим group by по pub_id и вычислением max(dt_max)

-- 4) join min и max значений по pub_id. Количество строк должно быть идентичным.
-- 5) Очистка витрины и перегрузка полученных на шаге (4) значений. Как альтернатива - UPSERT/MERGE.

--Вместо временной следует использовать обычную таблицу. 
--Необходимо хранить max-значения для неизменяемых данных и обновлять каждый раз при смещении границы окна.
--CREATE TABLE #Unchanged_Max
--(
--	pub_id INT,
--	max_dt DATE
--);

--CREATE TABLE #Unchanged_Max_Tmp
--(
--	pub_id INT,
--	max_dt DATE
--);
truncate table #Unchanged_Max
truncate table #Unchanged_Max_Tmp

--Начальная инициализация (для примера). Выполняется только один раз.
INSERT INTO #Unchanged_Max
SELECT pub_id, CAST(date_time AS DATE) as dt
	FROM [test].[dbo].[test]
	WHERE date_time < @start_date
	GROUP BY CAST(date_time AS DATE), pub_id
	HAVING SUM(revenue) >= @revenue_boundary

--Итеративное обновление при каждом запуске.
--Обновляем Unchanged_Max (добавляя в него левую границу окна, которая не будет изменяться на следующий день)
--Подлежит сохранению и переиспользованию при последующих запусках. В качестве примера используется временная таблица
INSERT INTO #Unchanged_Max_Tmp 
SELECT pub_id, max(max_dt) max_dt 
FROM (
	SELECT * FROM #Unchanged_Max
	UNION
	SELECT pub_id, CAST(date_time AS DATE) as dt
		FROM [test].[dbo].[test]
		WHERE CAST(date_time AS DATE) = @start_date
		GROUP BY CAST(date_time AS DATE), pub_id
		HAVING SUM(revenue) >= @revenue_boundary
	) tmp
GROUP BY pub_id

--Изначальное состояние витрины (для примера). Построено по границам окна, смещенным на один день в прошлое.
;With Previous_Agg
AS(
	SELECT pub_id, min(dt) min_dt, max(dt) max_dt 
	FROM (
		SELECT CAST(date_time AS DATE) as dt, pub_id, sum(revenue) revenue_sum
		FROM [test].[dbo].[test]
	    WHERE date_time >= DATEADD(day, -1, @start_date) AND date_time < DATEADD(day, -1, @end_date)
	    GROUP BY CAST(date_time AS DATE), pub_id
	    HAVING sum(revenue) >= @revenue_boundary) tmp
	GROUP BY pub_id
),
--Вычисление min и max для изменяемых данных в пределах "окна"
Window_Agg 
AS(
	SELECT pub_id, min(dt) min_dt, max(dt) max_dt 
	FROM (
		SELECT CAST(date_time AS DATE) as dt, pub_id, sum(revenue) revenue_sum
		FROM [test].[dbo].[test]
		WHERE date_time >= @start_date and date_time < @end_date
		GROUP BY CAST(date_time AS DATE), pub_id
		HAVING sum(revenue) >= @revenue_boundary
		) tmp
	GROUP BY pub_id
),
--Определяем набор pub_id, для которых min_dt не будет изменяться.
Unchanged_Min 
AS(
	SELECT * 
	FROM Previous_Agg
	WHERE min_dt < @start_date
)

--------------------------------------------------------------------------------------------
----Вычисление dt_max и dt_min
---- Объединяем dt_max, вычисленные на основе неизменяемых данных и на основе данных окна.
SELECT mn_dt.pub_id, mn_dt.min_dt, mx_dt.max_dt
FROM
	(SELECT pub_id, max(max_dt) max_dt
	FROM (	
		SELECT * FROM #Unchanged_Max_Tmp
		UNION
		SELECT pub_id, max_dt FROM Window_Agg) tmp
	GROUP BY pub_id
	) mx_dt
INNER JOIN
	(SELECT pub_id, min_dt 
	FROM Unchanged_Min
	UNION
	--Выбрасываем из окна те pub_id, для которых минимум посчитан на основе неизменяемых данных (вне окна)
	SELECT w.pub_id, w.min_dt 
	FROM Window_Agg w
	LEFT JOIN Unchanged_Min um 
		ON w.pub_id = um.pub_id
	WHERE um.pub_id is null) mn_dt
ON mx_dt.pub_id = mn_dt.pub_id
ORDER BY min_dt