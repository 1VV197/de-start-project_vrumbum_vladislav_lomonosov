/*
 * Создание схемы raw_data и таблицы sales
 */

CREATE SCHEMA IF NOT EXISTS raw_data;

CREATE TABLE IF NOT EXISTS raw_data.sales (
    id SERIAL PRIMARY KEY,          -- Уникальный идентификатор строки
    auto TEXT,             			-- Название автомобиля (бренд, модель, цвет)
    gasoline_consumption NUMERIC(4,1), -- Расход топлива, может содержать NULL
    price NUMERIC(10,2),   -- Цена автомобиля
    date DATE,        -- Дата продажи
    person_name TEXT,      -- Имя покупателя
    phone TEXT,                     -- Контактный номер телефона
    discount INT DEFAULT 0,         -- Скидка в процентах, если нет, то 0
    brand_origin TEXT               -- Страна происхождения бренда
);

/*
 * Загрузка данных из CSV-файла
 */

COPY raw_data.sales(auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin)
FROM 'C:\\Temp\\cars.csv'
DELIMITER ','
NULL 'null'
CSV HEADER;

/*
 * Нормализация данных (создание схемы car_shop)
 */

CREATE SCHEMA IF NOT EXISTS car_shop;

-- Таблица стран (новая таблица для нормализации страны бренда)
CREATE TABLE IF NOT EXISTS car_shop.countries (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE  -- Название страны должно быть уникальным
);

-- Таблица брендов (country теперь внешний ключ)
CREATE TABLE IF NOT EXISTS car_shop.brands (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,  -- Уникальное название бренда
    country_id INT REFERENCES car_shop.countries(id)  -- Внешний ключ на таблицу стран
);

-- Таблица моделей (добавлен расход топлива как характеристика модели)
CREATE TABLE IF NOT EXISTS car_shop.models (
    id SERIAL PRIMARY KEY,
    brand_id INT REFERENCES car_shop.brands(id),
    name TEXT NOT NULL UNIQUE,  -- Уникальное название модели
    gasoline_consumption NUMERIC(4,1)  -- Перемещён из таблицы автомобилей
);

-- Таблица цветов (без изменений)
CREATE TABLE IF NOT EXISTS car_shop.colors (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE  -- Цвет автомобиля
);

-- Таблица связи моделей и цветов (суррогатный ключ вместо составного PK)
CREATE TABLE IF NOT EXISTS car_shop.model_colors (
    id SERIAL PRIMARY KEY,  -- Уникальный ID для удобства
    model_id INT REFERENCES car_shop.models(id),
    color_id INT REFERENCES car_shop.colors(id)
);

-- Таблица клиентов (без изменений)
CREATE TABLE IF NOT EXISTS car_shop.customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT UNIQUE  -- Телефон должен быть уникальным
);

-- Таблица продаж (перемещение цены, даты и скидки из таблицы cars сюда)
CREATE TABLE IF NOT EXISTS car_shop.sales (
    id SERIAL PRIMARY KEY,
    model_color_id INT REFERENCES car_shop.model_colors(id),  -- Внешний ключ для модели с цветом
    customer_id INT REFERENCES car_shop.customers(id),
    sale_date DATE NOT NULL,  -- Дата продажи
    price NUMERIC(10,2) NOT NULL,  -- Цена продажи
    discount INT DEFAULT 0  -- Скидка на продажу
);

/*
 * Выбор форматов данных и комментарии
 * countries.name - TEXT UNIQUE -> название страны уникально, может содержать пробелы и специальные символы.
 * brands.name - TEXT NOT NULL UNIQUE -> названия брендов уникальны.
 * brands.country_id - INT REFERENCES countries(id) -> внешний ключ для связи с таблицей стран.
 * models.name - TEXT NOT NULL UNIQUE -> названия моделей уникальны.
 * models.gasoline_consumption - NUMERIC(4,1) -> расход топлива имеет точность до десятых.
 * colors.name - TEXT NOT NULL UNIQUE -> цвета автомобилей уникальны.
 * model_colors.id - SERIAL PRIMARY KEY -> уникальный ID для удобства работы с отношением "модель-цвет".
 * customers.phone - TEXT UNIQUE -> телефоны уникальны и могут быть записаны в разных форматах.
 * sales.model_color_id - INT REFERENCES model_colors(id) -> внешний ключ для связи с конкретной моделью и цветом.
 * sales.sale_date - DATE NOT NULL -> дата продажи обязательна и фиксируется без времени.
 * sales.price - NUMERIC(10,2) NOT NULL -> цена продажи с точностью до сотых.
 * sales.discount - INT DEFAULT 0 -> процент скидки, по умолчанию 0.
 */


/*
 * Заполнение таблиц
 */

-- Вставляем все уникальные страны, включая NULL как отдельную строку
INSERT INTO car_shop.countries (name)
SELECT DISTINCT brand_origin
FROM raw_data.sales;

-- Заполнение таблицы брендов с учётом NULL в таблице стран
INSERT INTO car_shop.brands (name, country_id)
SELECT DISTINCT
    SPLIT_PART(auto, ' ', 1) AS brand_name,
    c.id AS country_id
FROM raw_data.sales r
LEFT JOIN car_shop.countries c ON r.brand_origin IS NOT DISTINCT FROM c.name;

-- Заполнение таблицы моделей (теперь расход топлива перемещён сюда)
INSERT INTO car_shop.models (brand_id, name, gasoline_consumption)
SELECT DISTINCT
    b.id AS brand_id,
    TRIM(SUBSTRING(auto FROM POSITION(' ' IN auto) + 1 FOR POSITION(',' IN auto) - POSITION(' ' IN auto) - 1)) AS model_name,
    r.gasoline_consumption
FROM raw_data.sales r
JOIN car_shop.brands b ON SPLIT_PART(r.auto, ' ', 1) = b.name;

-- Заполнение таблицы цветов
INSERT INTO car_shop.colors (name)
SELECT DISTINCT
    TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 2), ' ', 2))
FROM raw_data.sales;

-- Заполнение таблицы связи модели и цвета
INSERT INTO car_shop.model_colors (model_id, color_id)
SELECT DISTINCT
    m.id AS model_id,
    col.id AS color_id
FROM raw_data.sales r
JOIN car_shop.models m ON TRIM(SUBSTRING(auto FROM POSITION(' ' IN auto) + 1 FOR POSITION(',' IN auto) - POSITION(' ' IN auto) - 1)) = m.name
JOIN car_shop.colors col ON TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 2), ' ', 2)) = col.name;

-- Заполнение таблицы клиентов
INSERT INTO car_shop.customers (name, phone)
SELECT DISTINCT
    person_name,
    phone
FROM raw_data.sales;

-- Заполнение таблицы продаж
INSERT INTO car_shop.sales (model_color_id, customer_id, sale_date, price, discount)
SELECT
    mc.id AS model_color_id,
    cu.id AS customer_id,
    r.date AS sale_date,
    r.price AS price,
    r.discount AS discount
FROM raw_data.sales r
JOIN car_shop.models m ON TRIM(SUBSTRING(auto FROM POSITION(' ' IN auto) + 1 FOR POSITION(',' IN auto) - POSITION(' ' IN auto) - 1)) = m.name
JOIN car_shop.colors col ON TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 2), ' ', 2)) = col.name
JOIN car_shop.model_colors mc ON mc.model_id = m.id AND mc.color_id = col.id
JOIN car_shop.customers cu ON r.person_name = cu.name;

/*
 * Создание выборок
 */

-- Задание 1: Процент моделей без расхода топлива
SELECT
    (COUNT(*) FILTER (WHERE gasoline_consumption IS NULL) * 100.0 / COUNT(*)) 
    AS nulls_percentage_gasoline_consumption
FROM car_shop.models;

-- Задание 2: Средняя цена бренда по годам (учёт скидки)
SELECT
    b.name AS brand_name,
    EXTRACT(YEAR FROM s.sale_date) AS year,
    ROUND(AVG(s.price), 2) AS price_avg
FROM car_shop.sales s
JOIN car_shop.model_colors mc ON s.model_color_id = mc.id
JOIN car_shop.models m ON mc.model_id = m.id
JOIN car_shop.brands b ON m.brand_id = b.id
GROUP BY b.name, year
ORDER BY b.name, year;

-- Задание 3: Средняя цена по месяцам в 2022 году (учёт скидки)
SELECT
    EXTRACT(MONTH FROM s.sale_date) AS month,
    EXTRACT(YEAR FROM s.sale_date) AS year,
    ROUND(AVG(s.price), 2) AS price_avg
FROM car_shop.sales s
WHERE EXTRACT(YEAR FROM s.sale_date) = 2022
GROUP BY month, year
ORDER BY month;

-- Задание 4: Список купленных машин у каждого пользователя
SELECT
    cu.name AS person,
    STRING_AGG(CONCAT(b.name, ' ', m.name), ', ') AS cars
FROM car_shop.sales s
JOIN car_shop.customers cu ON s.customer_id = cu.id
JOIN car_shop.model_colors mc ON s.model_color_id = mc.id
JOIN car_shop.models m ON mc.model_id = m.id
JOIN car_shop.brands b ON m.brand_id = b.id
GROUP BY cu.name
ORDER BY cu.name;

-- Задание 5: Максимальная и минимальная цена по странам (без учёта скидки)
SELECT  
    COALESCE(cn.name, 'Unknown') AS brand_origin,  -- Страна бренда, если NULL, то Unknown
    MAX(ROUND(s.price / (1 - s.discount / 100.0), 2)) AS price_max,  -- Максимальная цена без учёта скидки
    MIN(ROUND(s.price / (1 - s.discount / 100.0), 2)) AS price_min   -- Минимальная цена без учёта скидки
FROM car_shop.sales s
JOIN car_shop.model_colors mc ON s.model_color_id = mc.id
JOIN car_shop.models m ON mc.model_id = m.id
JOIN car_shop.brands b ON m.brand_id = b.id
LEFT JOIN car_shop.countries cn ON b.country_id = cn.id
GROUP BY cn.name
ORDER BY price_max DESC;


-- Задание 6: Число пользователей из США
SELECT
    COUNT(*) AS persons_from_usa_count
FROM car_shop.customers
WHERE phone LIKE '+1%';
