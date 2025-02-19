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
FROM 'C:\Temp\cars.csv'
DELIMITER ','
CSV HEADER;

/*
 * Нормализация данных (создание схемы car_shop)
 */

CREATE SCHEMA IF NOT EXISTS car_shop;

-- Таблица брендов
CREATE TABLE IF NOT EXISTS car_shop.brands (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE, -- Уникальное название бренда
    country TEXT NOT NULL      -- Страна происхождения
);

-- Таблица моделей
CREATE TABLE IF NOT EXISTS car_shop.models (
    id SERIAL PRIMARY KEY,
    brand_id INT REFERENCES car_shop.brands(id),
    name TEXT NOT NULL UNIQUE -- Уникальное название модели
);

-- Таблица цветов
CREATE TABLE IF NOT EXISTS car_shop.colors (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE -- Цвет автомобиля
);

-- Таблица автомобилей
CREATE TABLE IF NOT EXISTS car_shop.cars (
    id SERIAL PRIMARY KEY,
    model_id INT REFERENCES car_shop.models(id),
    price NUMERIC(10,2) NOT NULL,
    gasoline_consumption NUMERIC(4,1), -- Может быть NULL
    sale_date DATE NOT NULL,
    discount INT DEFAULT 0
);

-- Таблица связи автомобилей и цветов (многие-ко-многим)
CREATE TABLE IF NOT EXISTS car_shop.car_colors (
    car_id INT REFERENCES car_shop.cars(id),
    color_id INT REFERENCES car_shop.colors(id),
    PRIMARY KEY (car_id, color_id)
);

-- Таблица клиентов
CREATE TABLE IF NOT EXISTS car_shop.customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT UNIQUE -- Телефон должен быть уникальным
);

-- Таблица продаж
CREATE TABLE IF NOT EXISTS car_shop.sales (
    id SERIAL PRIMARY KEY,
    car_id INT REFERENCES car_shop.cars(id),
    customer_id INT REFERENCES car_shop.customers(id),
    sale_date DATE NOT NULL
);

/*
 * Выбор форматов данных и комментарии
 * brands.name - TEXT NOT NULL UNIQUE -> названия брендов уникальные.
 * models.name - TEXT NOT NULL UNIQUE -> названия моделей уникальные.
 * colors.name - TEXT NOT NULL UNIQUE -> цвета уникальны.
 * cars.price - NUMERIC(10,2) -> цена важна до сотых.
 * cars.gasoline_consumption - NUMERIC(4,1) -> расход топлива может содержать десятые.
 * customers.phone - TEXT UNIQUE -> телефоны уникальны, но в разных форматах.
 * sales.sale_date - DATE NOT NULL -> даты продаж обязательны.
 */

/*
 * Заполнение таблиц
 */

-- Заполнение таблицы брендов
INSERT INTO car_shop.brands (name, country)
SELECT DISTINCT SPLIT_PART(auto, ' ', 1), brand_origin
FROM raw_data.sales
WHERE brand_origin IS NOT NULL;

-- Заполнение таблицы моделей
INSERT INTO car_shop.models (brand_id, name)
SELECT DISTINCT b.id, 
    TRIM(SUBSTRING(auto FROM POSITION(' ' IN auto) + 1 FOR POSITION(',' IN auto) - POSITION(' ' IN auto) - 1))
FROM raw_data.sales r
JOIN car_shop.brands b ON SPLIT_PART(r.auto, ' ', 1) = b.name;

-- Заполнение таблицы цветов
INSERT INTO car_shop.colors (name)
SELECT DISTINCT TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 2), ' ', 2))
FROM raw_data.sales;

-- Заполнение таблицы автомобилей
INSERT INTO car_shop.cars (model_id, price, gasoline_consumption, sale_date, discount)
SELECT m.id, r.price, r.gasoline_consumption, r.date, r.discount
FROM raw_data.sales r
JOIN car_shop.models m ON TRIM(SUBSTRING(auto FROM POSITION(' ' IN auto) + 1 FOR POSITION(',' IN auto) - POSITION(' ' IN auto) - 1)) = m.name;

-- Заполнение таблицы цветов автомобилей
INSERT INTO car_shop.car_colors (car_id, color_id)
SELECT c.id, col.id
FROM raw_data.sales r
JOIN car_shop.cars c ON r.price = c.price
JOIN car_shop.colors col ON TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 2), ' ', 2)) = col.name;

-- Заполнение таблицы клиентов
INSERT INTO car_shop.customers (name, phone)
SELECT DISTINCT person_name, phone
FROM raw_data.sales;

-- Заполнение таблицы продаж
INSERT INTO car_shop.sales (car_id, customer_id, sale_date)
SELECT c.id, cu.id, r.date
FROM raw_data.sales r
JOIN car_shop.cars c ON r.price = c.price
JOIN car_shop.customers cu ON r.person_name = cu.name;

/*
 * Создание выборок
 */

-- Задание 1: Процент моделей без расхода топлива
SELECT 
    (COUNT(*) FILTER (WHERE gasoline_consumption IS NULL) * 100.0 / COUNT(*)) 
    AS nulls_percentage_gasoline_consumption
FROM car_shop.cars;

-- Задание 2: Средняя цена бренда по годам (учёт скидки)
SELECT 
    b.name AS brand_name,
    EXTRACT(YEAR FROM c.sale_date) AS year,
    ROUND(AVG(c.price * (1 - c.discount / 100.0)), 2) AS price_avg
FROM car_shop.cars c
JOIN car_shop.models m ON c.model_id = m.id
JOIN car_shop.brands b ON m.brand_id = b.id
GROUP BY b.name, year
ORDER BY b.name, year;

-- Задание 3: Средняя цена по месяцам в 2022 году (учёт скидки)
SELECT 
    EXTRACT(MONTH FROM c.sale_date) AS month,
    EXTRACT(YEAR FROM c.sale_date) AS year,
    ROUND(AVG(c.price * (1 - c.discount / 100.0)), 2) AS price_avg
FROM car_shop.cars c
WHERE EXTRACT(YEAR FROM c.sale_date) = 2022
GROUP BY month, year
ORDER BY month;

-- Задание 4: Список купленных машин у каждого пользователя
SELECT 
    cu.name AS person,
    STRING_AGG(CONCAT(b.name, ' ', m.name), ', ') AS cars
FROM car_shop.sales s
JOIN car_shop.cars c ON s.car_id = c.id
JOIN car_shop.models m ON c.model_id = m.id
JOIN car_shop.brands b ON m.brand_id = b.id
JOIN car_shop.customers cu ON s.customer_id = cu.id
GROUP BY cu.name
ORDER BY cu.name;

-- Задание 5: Максимальная и минимальная цена по странам
SELECT 
    b.country AS brand_origin,
    MAX(c.price) AS price_max,
    MIN(c.price) AS price_min
FROM car_shop.cars c
JOIN car_shop.models m ON c.model_id = m.id
JOIN car_shop.brands b ON m.brand_id = b.id
GROUP BY b.country
ORDER BY price_max DESC;

-- Задание 6: Число пользователей из США
SELECT 
    COUNT(*) AS persons_from_usa_count
FROM car_shop.customers
WHERE phone LIKE '+1%';
