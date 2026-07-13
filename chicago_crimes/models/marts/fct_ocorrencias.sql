{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['sk_data']},
            {'columns': ['sk_crime']},
            {'columns': ['sk_geografia']},
            {'columns': ['id_ocorrencia'], 'unique': True}
        ]
    )
}}

{#
    Fato P1 — Ocorrências criminais.
    Grão: uma linha por ocorrência reportada, identificada por `id_ocorrencia`.
    Fato transacional. ~8,59 milhões de linhas.

    PONTO CRÍTICO — join temporal nas dimensões SCD Tipo 2:
    dim_crime e dim_geografia contêm múltiplas versões da mesma chave natural.
    O join NÃO pode ser feito apenas pela chave: precisa selecionar a versão
    VIGENTE NA DATA DA OCORRÊNCIA, via BETWEEN valido_de AND valido_ate.

    Sem isso, um crime de 2010 no beat 1311 seria associado ao distrito 12
    (vigente hoje) em vez do distrito 13 (vigente em 2010) — reescrevendo a
    história. É exatamente o erro que o SCD Tipo 2 existe para evitar.

    TRATAMENTO DE NULOS:
    Todos os joins são LEFT, com coalesce para a chave substituta (-1).
    Nenhuma ocorrência é descartada por ter dimensão ausente — descartá-las
    subestimaria as contagens (ex.: os 614.813 registros sem ward).
#}

with ocorrencias as (

    select * from {{ ref('stg_crimes') }}

),

fato as (

    select
        o.id_ocorrencia                         as sk_ocorrencia,

        o.id_ocorrencia                         as id_ocorrencia,
        o.case_number                           as case_number,

        -- Chaves estrangeiras
        coalesce(d.sk_data,      -1)            as sk_data,
        coalesce(h.sk_hora,      -1)            as sk_hora,
        coalesce(c.sk_crime,     -1)            as sk_crime,
        coalesce(g.sk_geografia, -1)            as sk_geografia,
        coalesce(l.sk_local,     -1)            as sk_local,
        f.sk_flags                              as sk_flags,

        o.latitude                              as latitude,
        o.longitude                             as longitude,
        o.data_hora_ocorrencia                  as data_hora_ocorrencia,


        1                                       as qtd_ocorrencia,
        case when o.flag_prisao    then 1 else 0 end as qtd_prisao,
        case when o.flag_domestico then 1 else 0 end as qtd_domestico

    from ocorrencias o

    left join {{ ref('dim_data') }} d
        on o.data_ocorrencia = d.data_completa

    left join {{ ref('dim_hora') }} h
        on o.hora_ocorrencia = h.sk_hora

    left join {{ ref('dim_local') }} l
        on o.location_description = l.descricao_local

    left join {{ ref('dim_flags') }} f
        on o.flag_prisao    = f.flag_prisao
       and o.flag_domestico = f.flag_domestico

    left join {{ ref('dim_crime') }} c
        on  o.iucr = c.iucr
        and o.data_hora_ocorrencia >= c.valido_de
        and o.data_hora_ocorrencia <  c.valido_ate

    left join {{ ref('dim_geografia') }} g
        on  o.beat = g.beat
        and o.data_hora_ocorrencia >= g.valido_de
        and o.data_hora_ocorrencia <  g.valido_ate

)

select * from fato
