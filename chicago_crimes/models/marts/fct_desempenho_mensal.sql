{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['sk_mes']},
            {'columns': ['sk_distrito']},
            {'columns': ['sk_tipo_crime']}
        ]
    )
}}

{#
    Fato P2 — Desempenho operacional mensal.
    Grão: uma linha por mês × distrito × tipo primário de crime.
    Fato agregado (periodic snapshot). ~250 mil linhas.

    Processo de negócio: acompanhar a taxa de esclarecimento (prisão) e o volume
    de ocorrências por distrito ao longo do tempo, apoiando decisões de alocação
    de efetivo policial.

    Construído por agregação do fato P1 — garante consistência entre os dois
    (drill-across válido).

    ATENÇÃO — MEDIDAS NÃO-ADITIVAS:
    `taxa_prisao` NÃO é armazenada aqui. Taxas não podem ser somadas: a média
    das taxas de dois distritos não é a taxa do conjunto. Armazená-la levaria o
    Power BI a somá-la em qualquer agregação, produzindo valores absurdos
    (ex.: taxa de 340%).
    A taxa deve ser calculada em DAX, no momento da consulta:
        Taxa de prisão = DIVIDE(SUM(qtd_prisoes), SUM(qtd_ocorrencias))
    Os numeradores e denominadores — esses sim aditivos — são o que se armazena.
#}

with ocorrencias as (

    select
        f.sk_data,
        f.sk_crime,
        f.sk_geografia,
        f.qtd_ocorrencia,
        f.qtd_prisao,
        f.qtd_domestico
    from {{ ref('fct_ocorrencias') }} f

),

rebaixado as (

    select
        (d.ano * 100 + d.numero_mes)            as sk_mes_natural,
        g.district                              as district_natural,
        c.primary_type_atual                    as tipo_crime_natural,

        o.qtd_ocorrencia,
        o.qtd_prisao,
        o.qtd_domestico

    from ocorrencias o

    inner join {{ ref('dim_data') }} d
        on o.sk_data = d.sk_data
    inner join {{ ref('dim_geografia') }} g
        on o.sk_geografia = g.sk_geografia
    inner join {{ ref('dim_crime') }} c
        on o.sk_crime = c.sk_crime

    where d.sk_data <> -1

),

agregado as (

    select
        sk_mes_natural,
        district_natural,
        tipo_crime_natural,

        sum(qtd_ocorrencia)::int                as qtd_ocorrencias,
        sum(qtd_prisao)::int                    as qtd_prisoes,
        sum(qtd_domestico)::int                 as qtd_domesticos,
        sum(qtd_ocorrencia - qtd_prisao)::int   as qtd_sem_prisao

    from rebaixado
    group by 1, 2, 3

)

select
    coalesce(m.sk_mes,        -1)               as sk_mes,
    coalesce(dt.sk_distrito,  -1)               as sk_distrito,
    coalesce(tc.sk_tipo_crime, -1)              as sk_tipo_crime,

    a.qtd_ocorrencias                           as qtd_ocorrencias,
    a.qtd_prisoes                               as qtd_prisoes,
    a.qtd_domesticos                            as qtd_domesticos,
    a.qtd_sem_prisao                            as qtd_sem_prisao

from agregado a

left join {{ ref('dim_mes') }} m
    on a.sk_mes_natural = m.sk_mes

left join {{ ref('dim_distrito') }} dt
    on  a.district_natural = dt.district
    and dt.flag_versao_atual = true

left join {{ ref('dim_tipo_crime') }} tc
    on a.tipo_crime_natural = tc.primary_type
