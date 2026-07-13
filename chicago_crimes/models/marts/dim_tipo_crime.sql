{{ config(materialized='table') }}

{#
    Dimensão Tipo de Crime — SHRUNKEN CONFORMED DIMENSION de dim_crime.
    Grão: primary_type. SCD Tipo 1.

    Por que não reutilizar dim_crime?
    dim_crime tem grão IUCR (~418 linhas, com versões SCD 2). O fato P2 tem grão
    PRIMARY TYPE (~34). O join pelo grão errado multiplicaria as medidas.

    Usa primary_type_atual (não o histórico): no grão agregado, o objetivo é
    comparabilidade da série temporal. Agrupar por primary_type histórico
    partiria "CRIM SEXUAL ASSAULT" e "CRIMINAL SEXUAL ASSAULT" em duas séries,
    quando são o mesmo crime sob nomes diferentes.
#}

with tipos as (

    select distinct
        primary_type_atual  as primary_type,
        categoria_analitica
    from {{ ref('dim_crime') }}
    where sk_crime <> -1
      and primary_type_atual is not null
      and primary_type_atual <> 'Não informado'

)

select
    {{ dbt_utils.generate_surrogate_key(['primary_type']) }}::bigint as sk_tipo_crime,
    primary_type                            as primary_type,
    initcap(primary_type)                   as nome_tipo_crime,
    categoria_analitica                     as categoria_analitica,
    (categoria_analitica = 'Crime violento') as flag_crime_violento
from tipos

union all

select -1, 'N/D', 'Não informado', 'Não informado', false
