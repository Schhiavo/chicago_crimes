{#
    SCD Tipo 2 — dim_geografia

    Justificativa empírica: em 2012 o CPD desativou os distritos 13, 21 e 23 e
    redistribuiu seus beats entre os distritos vizinhos. A verificação da
    hierarquia District ⊃ Beat encontrou 337.269 registros inconsistentes
    (3,9% da base), dos quais 333.941 (99%) se concentram em apenas cinco
    pares distrito/beat, todos terminando exatamente em 2012:

        district 012 ← beats 13xx   (124.808 registros, 2001–2012)
        district 019 ← beats 23xx   ( 96.175 registros, 2001–2012)
        district 002 ← beats 21xx   ( 87.287 registros, 2001–2012)
        district 001 ← beats 21xx   ( 17.634 registros, 2001–2012)
        district 009 ← beats 21xx   (  8.037 registros, 2001–2012)

    Este é o caso mais forte do modelo. A FONTE JÁ APLICOU SCD TIPO 1:
    sobrescreveu o district antigo pelo atual nos registros históricos,
    perdendo o histórico. O modelo dimensional recupera essa informação.

    Sem SCD Tipo 2, um crime ocorrido em 2010 no beat 1311 seria reportado no
    distrito 12 — que em 2010 não o cobria. Isso reescreveria a história
    geográfica de Chicago e invalidaria qualquer série temporal por distrito.

    A chave natural é o beat.
#}

{% snapshot snap_geografia %}

{{
    config(
        target_schema='snapshots',
        unique_key='beat',
        strategy='check',
        check_cols=['district']
    )
}}

with versao_vigente as (

    select distinct on (beat)
        beat,
        district
    from {{ ref('stg_crimes') }}
    where beat is not null
      and district is not null
    order by beat, data_hora_ocorrencia desc

)

select * from versao_vigente

{% endsnapshot %}
