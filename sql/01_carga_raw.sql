CREATE SCHEMA IF NOT EXISTS raw;

DROP TABLE IF EXISTS raw.crimes_raw;

CREATE TABLE raw.crimes_raw (
    id                   TEXT,
    case_number          TEXT,
    date                 TEXT,
    block                TEXT,
    iucr                 TEXT,
    primary_type         TEXT,
    description          TEXT,
    location_description TEXT,
    arrest               TEXT,
    domestic             TEXT,
    beat                 TEXT,
    district             TEXT,
    ward                 TEXT,
    community_area       TEXT,
    fbi_code             TEXT,
    x_coordinate         TEXT,   
    y_coordinate         TEXT,
    year                 TEXT,
    updated_on           TEXT,
    latitude             TEXT,
    longitude            TEXT,
    location             TEXT
);

CREATE INDEX IF NOT EXISTS idx_crimes_raw_id   ON raw.crimes_raw (id);
CREATE INDEX IF NOT EXISTS idx_crimes_raw_year ON raw.crimes_raw (year);

ANALYZE raw.crimes_raw;

SELECT count(*) AS total_registros
FROM raw.crimes_raw;

SELECT year, count(*) AS qtd
FROM raw.crimes_raw
GROUP BY year
ORDER BY year;

SELECT count(DISTINCT primary_type)         AS tipos,
       count(DISTINCT iucr)                 AS iucr,
       count(DISTINCT description)          AS descricoes,
       count(DISTINCT fbi_code)             AS fbi,
       count(DISTINCT location_description) AS locais,
       count(DISTINCT beat)                 AS beats,
       count(DISTINCT district)             AS distritos,
       count(DISTINCT ward)                 AS wards,
       count(DISTINCT community_area)       AS areas
FROM raw.crimes_raw;

SELECT count(*) - count(DISTINCT id)                        AS ids_duplicados,
       count(*) FILTER (WHERE latitude IS NULL)             AS sem_coord,
       count(*) FILTER (WHERE district IS NULL)             AS sem_distrito,
       count(*) FILTER (WHERE ward IS NULL)                 AS sem_ward,
       count(*) FILTER (WHERE community_area IS NULL)       AS sem_area,
       count(*) FILTER (WHERE location_description IS NULL) AS sem_local_desc
FROM raw.crimes_raw;

SELECT year,
       count(*) FILTER (WHERE ward IS NULL) AS sem_ward,
       count(*)                             AS total
FROM raw.crimes_raw
GROUP BY year
HAVING count(*) FILTER (WHERE ward IS NULL) > 0
ORDER BY year;

SELECT count(*) AS iucr_com_mais_de_uma_combinacao
FROM (
    SELECT iucr
    FROM raw.crimes_raw
    GROUP BY iucr
    HAVING count(DISTINCT primary_type || '|' || description || '|' || fbi_code) > 1
) t;

SELECT count(*) FILTER (WHERE n_primary > 1) AS iucr_varia_primary_type,
       count(*) FILTER (WHERE n_desc    > 1) AS iucr_varia_description,
       count(*) FILTER (WHERE n_fbi     > 1) AS iucr_varia_fbi_code
FROM (
    SELECT iucr,
           count(DISTINCT primary_type) AS n_primary,
           count(DISTINCT description)  AS n_desc,
           count(DISTINCT fbi_code)     AS n_fbi
    FROM raw.crimes_raw
    GROUP BY iucr
) t;

SELECT iucr, primary_type, description, fbi_code,
       min(year) AS primeiro_ano,
       max(year) AS ultimo_ano,
       count(*)  AS qtd
FROM raw.crimes_raw
WHERE iucr IN (
    SELECT iucr
    FROM raw.crimes_raw
    GROUP BY iucr
    HAVING count(DISTINCT description) > 1
)
GROUP BY iucr, primary_type, description, fbi_code
ORDER BY iucr, primeiro_ano
LIMIT 30;

SELECT count(*) AS beats_inconsistentes
FROM raw.crimes_raw
WHERE district ~ '^\d+$'
  AND beat     ~ '^\d+$'
  AND district::int <> beat::int / 100;


SELECT district,
       substring(lpad(beat, 4, '0') FROM 1 FOR 2) AS prefixo_beat,
       min(year) AS primeiro_ano,
       max(year) AS ultimo_ano,
       count(*)  AS qtd
FROM raw.crimes_raw
WHERE district ~ '^\d+$'
  AND beat     ~ '^\d+$'
  AND district::int <> beat::int / 100
GROUP BY district, prefixo_beat
ORDER BY qtd DESC
LIMIT 20;
