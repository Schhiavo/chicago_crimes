{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['id_ocorrencia'], 'unique': True},
            {'columns': ['iucr']},
            {'columns': ['beat']},
            {'columns': ['data_ocorrencia']}
        ]
    )
}}

with fonte as (

    select * from {{ source('raw', 'crimes_raw') }}

),

convertido as (

    select
        id::bigint                                          as id_ocorrencia,
        nullif(trim(case_number), '')                       as case_number,

        to_timestamp(date, 'MM/DD/YYYY HH12:MI:SS AM')      as data_hora_ocorrencia,
        to_timestamp(date, 'MM/DD/YYYY HH12:MI:SS AM')::date as data_ocorrencia,
        extract(hour from to_timestamp(date, 'MM/DD/YYYY HH12:MI:SS AM'))::int as hora_ocorrencia,
        to_timestamp(updated_on, 'MM/DD/YYYY HH12:MI:SS AM') as data_atualizacao_fonte,

        upper(trim(iucr))                                   as iucr,
        upper(trim(primary_type))                           as primary_type,
        upper(trim(description))                            as description,
        upper(trim(fbi_code))                               as fbi_code,

        nullif(regexp_replace(beat,     '\D', '', 'g'), '')::int as beat,
        nullif(regexp_replace(district, '\D', '', 'g'), '')::int as district,
        nullif(regexp_replace(ward,     '\D', '', 'g'), '')::int as ward,
        nullif(regexp_replace(community_area, '\D', '', 'g'), '')::int as community_area,

        nullif(upper(trim(location_description)), '')       as location_description,
        nullif(trim(block), '')                             as block,

        nullif(trim(latitude),  '')::numeric(12,8)          as latitude,
        nullif(trim(longitude), '')::numeric(12,8)          as longitude,

        (upper(trim(arrest))   = 'TRUE')                    as flag_prisao,
        (upper(trim(domestic)) = 'TRUE')                    as flag_domestico

    from fonte
    where id is not null
      and date is not null

)

select * from convertido
