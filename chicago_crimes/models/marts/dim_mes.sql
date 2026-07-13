{{ config(materialized='table') }}

{#
    Dimensão Mês — SHRUNKEN CONFORMED DIMENSION de dim_data.
    Grão: mês. SCD Tipo 1.

    Por que não reutilizar dim_data?
    O fato P2 tem grão MENSAL. Ligá-lo a uma dimensão de grão DIÁRIO produziria
    um join inválido: cada linha mensal do fato casaria com ~30 linhas da
    dimensão, multiplicando as medidas por 30. É precisamente o erro que o
    enunciado adverte ("não reutilizar dimensões para fatos com granularidades
    diferentes").

    A conformidade é preservada: os atributos (ano, trimestre, nome do mês) têm
    exatamente a mesma semântica e os mesmos valores de dim_data — o que permite
    drill-across entre os dois fatos.
#}

with meses as (

    select distinct
        ano,
        numero_mes,
        trimestre,
        nome_mes,
        ano_mes,
        nome_trimestre,
        flag_ano_parcial
    from {{ ref('dim_data') }}
    where sk_data <> -1

)

select
    (ano * 100 + numero_mes)                as sk_mes,
    ano_mes                                 as ano_mes,
    ano                                     as ano,
    trimestre                               as trimestre,
    numero_mes                              as numero_mes,
    nome_mes                                as nome_mes,
    nome_trimestre                          as nome_trimestre,
    nome_mes || '/' || ano::text            as descricao_mes,
    make_date(ano, numero_mes, 1)           as primeiro_dia_mes,
    flag_ano_parcial                        as flag_ano_parcial
from meses