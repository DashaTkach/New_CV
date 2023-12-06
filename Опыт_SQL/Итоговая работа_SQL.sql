-- Итоговая работа по курсу "SQL и анализ данных"

-- 1.	В каких городах больше одного аэропорта?

-- логика: обращаемся к таблице airports и берём две колонки city и airport_code, 
-- считаем количество аэропортов относительно каждого города с помощью аггрегации и group by
-- задаём условие к группировке с помощью having, чтобы вывести ответ на вопрос 

select city "Город", count(airport_code) "Количество аэропортов" 
from airports a 
group by city 
having count(airport_name) > 1
order by city

-- 2.	В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета? (подзапрос)

-- посредством подзапроса выбираем самолёт с максимальной дальностью полёта
-- на основе этого выводим уникальные номера и названия аэропортов, в которых есть рейсы данного самолёта

select distinct airport_code, airport_name, t.aircraft_code, "range"
from (
	select *
	from aircrafts a 
	order by "range" desc   
	limit 1
	) t
join flights f on t.aircraft_code = f.aircraft_code
join airports a2 on f.departure_airport = a2.airport_code
order by airport_name

-- 3.	Вывести 10 рейсов с максимальным временем задержки вылета

-- считаем время задеджки: фактическое - планируемое -> ереводим в тип времени (часы, минуты, секунды)
-- убираем неизвестные значения (nul)
-- сортируем ль большего к меньшему
-- выбираем первые 10 строк - рейсов

select flight_no, (actual_departure::time  - scheduled_departure::time) as "Время задержки"
from flights
where (actual_departure::time  - scheduled_departure::time) is not null
order by (actual_departure::time  - scheduled_departure::time) desc
limit 10

-- Подсказка для себя:
-- scheduled_departure - время по расписанию
-- actual_departure - факт 

-- 4.	Были ли брони, по которым не были получены посадочные талоны?	Верный тип JOIN

select distinct b.book_ref "Номер бронирования", bp.seat_no "Номер места"  -- мы его узнаём по посадочному талону
from bookings b                                                   -- т.е. те, у кого нет места, не получали посадочные талоны
inner join tickets t on b.book_ref = t.book_ref -- inner можно не использовать
full outer join boarding_passes bp  on bp.ticket_no  = t.ticket_no  -- полное объединение, чтобы увидеть, у кого нет места в посадочном талоне
where bp.seat_no is null -- выбираем только незаполненнные (null)

-- 5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете. 
-- Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого 
-- аэропорта на каждый день. 
-- Т. е. в этом столбце должна отражаться накопительная сумма - сколько человек уже 
-- вылетело из данного аэропорта на этом или более ранних рейсах в течении дня	

--Оконная функция; подзапросы или/и cte

--Логика: для начала я считаю свободных мест. Для этого: считаю в первом сте полное количество мест на каждом из рейсов, потом, во втором сте, 
--дополняю информацию по местам, которые на самом деле были заняты. А далее вычитаю из общего кол-ва мест занятые и получаю свободные места.
--Следующее: % отношение к общему. рассчитываю с помощью уже имеющихся данных сразу в сте2 (до задания с накопительным итогом это была основная 
--часть запроса) Ну и накопительный итог: сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах в течении дня. Значит, 
--из данного аэропорта (присоединяем таблицу airports, дополняя для этого стешки нужными данными) и формируем накопительный итог.

with cte1 as (
    select flight_id, count(s.seat_no) as was, actual_departure::date, departure_airport 
    from seats s
    join flights f  on s.aircraft_code = f.aircraft_code
    group by flight_id
    order by flight_id), 
cte2 as (
    select distinct bp.flight_id, was, cte1.actual_departure::date, cte1.departure_airport, count(bp.seat_no) as became
    , was - count(bp.seat_no) as free_places
    , round((was - count(bp.seat_no))::numeric/was::numeric,2)*100 as pro
    from cte1
    join boarding_passes bp  on bp.flight_id = cte1.flight_id
    group by bp.flight_id, was, cte1.actual_departure::date, cte1.departure_airport
    )
select flight_id, was, became, free_places, pro, cte2.actual_departure::date, cte2.departure_airport, sum(cte2.became) over 
(partition by date_part('day', cte2.actual_departure::date), cte2.departure_airport order by flight_id, date_part('day', cte2.actual_departure::date))
from cte2 
order by flight_id

-- 6.	Найдите процентное соотношение перелетов по типам самолетов от общего количества

-- Подзапрос или окно; оператор ROUND 

--Логика: рассчёты производятся за счет участия в них подзапроса. Он нужен для того, чтобы посчитать общее количество перелётов вне группировки по 
-- идентификатору самолёта. За счёт этого мы можем посчитать отношение количества доли к общему.

select a.aircraft_code, count(f.flight_id), round(count(f.flight_id)::numeric / (select count(f2.flight_id) from flights f2)::numeric, 2)*100 as pro
from flights f 
join aircrafts a  on f.aircraft_code = a.aircraft_code
group by a.aircraft_code

-- 7.	Были ли города, в которые можно добраться бизнес-классом дешевле, чем эконом-классом в рамках перелета?	
-- CTE

--сте используем для разделения логики

with cte1 as (
	select *, row_number () over (partition by flight_id order by fare_conditions) -- выбираем рейсы только по бизнес-классу
	from ticket_flights tf 
	where fare_conditions = 'Business'),
cte2 as (select tf1.flight_id, cte1.amount as "Бизнес", tf1.amount as "Эконом" -- добавляем к ним эконом и выводим только те рейсы, 
	from cte1                                                                 --  которые подходят заданному нам условию
	join ticket_flights tf1 on cte1.ticket_no = tf1.ticket_no 
	where cte1.amount < tf1.amount),
cte3 as (select cte2.flight_id, a.city
	from cte2                                                       -- соответстенно рейсам выводим города
	join flights f on f.flight_id = cte2.flight_id
	join airports a  on f.arrival_airport = a.airport_code) --  (в которые можно добраться, т.е arrival_airport)
select distinct cte3.city 
from cte3


-- 8.	Между какими городами нет прямых рейсов?	
	
-- Декартово произведение в предложении FROM; самостоятельно созданные представления 
-- ; оператор EXCEPT
                                                              -- (except)
				-- Все города со всеми возможными рейсами (декарт) - города, в которые есть прямые рейсы
create view task_8 as				
	select distinct a.city as "Город отправления", a2.city as "Город прибытия"
	from airports a, airports a2 
	where a.city != a2.city  -- без повторения!
	except --(-)
	select distinct a.city as "Город отправления", a2.city as "Город прибытия"
	from flights f 
	join airports a on f.arrival_airport = a.airport_code
	join airports a2 on f.departure_airport = a2.airport_code 


-- 9.	Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной 
-- дальностью перелетов в самолетах, обслуживающих эти рейсы

--Оператор RADIANS или использование sind/cosd; CASE

--Кратчайшее расстояние между двумя точками A и B на земной поверхности (если принять ее за сферу) определяется зависимостью:
--d = arccos {sin(latitude_a)·sin(latitude_b) + cos(latitude_a)·cos(latitude_b)·cos(longitude_a - longitude_b)}, где latitude_a 
--и latitude_b — широты, longitude_a, longitude_b — долготы данных пунктов, d — расстояние между пунктами измеряется в радианах
--длиной дуги большого круга земного шара. Расстояние между пунктами, измеряемое в километрах, определяется по формуле:
--L = d·R, где R = 6371 км — средний радиус земного шара.

	
	select distinct departure_airport as A, arrival_airport as B, a.longitude as A_dolgota, a.latitude as A_shirota, a2.longitude B_dolgota
	, a2.latitude B_shirota, acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 
	as short_lehgth, a3.range as maximum, case 
			when acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 < 0.25*a3.range then 'Очень которкий перелёт'
			when acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 < 0.5*a3.range 
			and acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 > 0.25*a3.range then 'Короткий перелет'
			when acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 > 0.5*a3.range 
			and acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 < 0.75*a3.range then 'Средний перелёт'
			else 'Длинный перелёт'
		end	
	from flights f 
	join airports a  on f.departure_airport = a.airport_code
	join airports a2  on f.arrival_airport = a2.airport_code
	join aircrafts a3 on f.aircraft_code = a3.aircraft_code 

-- Логика:
-- расчитываем расстояние по формуле (все функции из документации) в радианах и умнодаем на 6372 км - для перевода расстояния в км
-- берем из другой таблицы (с помощью присоединения) максимальную дальность полёта 
-- и относительно нее рассматриваем, сравниваем с ней величины, которые мы получили посредством формулы
-- офрмляем как проверку условий в case