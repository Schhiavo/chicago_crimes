{{ config(materialized='table') }}

{#
    Dimensão Data — grão: dia. SCD Tipo 1.
    Intervalo definido pela cobertura observada na fonte: 2001-01-01 a 2026-12-31.
    Gerada por generate_series, não extraída do fato — garante dias sem ocorrência
    (necessário para séries temporais sem lacunas no Power BI).
#}

with calendario as (

    select generate_series(
        '2001-01-01'::date,
        '2026-12-31'::date,
        '1 day'::interval
    )::date as data

),

atributos as (

    select
        to_char(data, 'YYYYMMDD')::int      as sk_data,
        data                                 as data_completa,
        extract(year    from data)::int      as ano,
        extract(quarter from data)::int      as trimestre,
        extract(month   from data)::int      as numero_mes,
        extract(day     from data)::int      as dia_do_mes,
        extract(doy     from data)::int      as dia_do_ano,
        extract(week    from data)::int      as semana_do_ano,
        extract(isodow  from data)::int      as numero_dia_semana,

        to_char(data, 'YYYY-MM')             as ano_mes,
        'T' || extract(quarter from data)    as nome_trimestre,

        case extract(month from data)
            when  1 then 'Janeiro'   when  2 then 'Fevereiro' when  3 then 'Março'
            when  4 then 'Abril'     when  5 then 'Maio'      when  6 then 'Junho'
            when  7 then 'Julho'     when  8 then 'Agosto'    when  9 then 'Setembro'
            when 10 then 'Outubro'   when 11 then 'Novembro'  when 12 then 'Dezembro'
        end                                  as nome_mes,

        case extract(isodow from data)
            when 1 then 'Segunda-feira' when 2 then 'Terça-feira'
            when 3 then 'Quarta-feira'  when 4 then 'Quinta-feira'
            when 5 then 'Sexta-feira'   when 6 then 'Sábado'
            when 7 then 'Domingo'
        end                                  as nome_dia_semana,

        (extract(isodow from data) in (6, 7)) as flag_fim_de_semana,

        (extract(year from data) = 2026)      as flag_ano_parcial

    from calendario

)

select * from atributos
