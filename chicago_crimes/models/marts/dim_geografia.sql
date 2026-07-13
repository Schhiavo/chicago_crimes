{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['sk_geografia'], 'unique': True},
            {'columns': ['beat']}
        ]
    )
}}

{#
    Dimensão Geografia — grão: beat × versão. SCD Tipo 2.

    Consome snap_geografia, que capturou a consolidação distrital de 2012
    (desativação dos distritos 13, 21 e 23).

    Hierarquia principal (drill-down no Power BI):
        District → Beat

    Ward e Community Area são recortes administrativos ALTERNATIVOS: suas
    fronteiras cruzam as dos distritos policiais, logo NÃO se aninham na
    hierarquia acima. São caminhos de drill-down paralelos.

    Cobertura de Ward/Community Area: ausente em 2001 (99,1%) e parcial em 2002
    (27,3%). Análises por esses atributos devem filtrar a partir de 2003 —
    caso contrário, a queda aparente em 2001 é artefato da fonte, não da realidade.
#}

with snapshot_geo as (

    select * from {{ ref('snap_geografia') }}

),

distrito_corrente as (

    select
        beat,
        district as district_atual
    from snapshot_geo
    where dbt_valid_to is null

),

atributos_predominantes as (

    select distinct on (beat)
        beat,
        ward,
        community_area
    from {{ ref('stg_crimes') }}
    where beat is not null
      and ward is not null
      and community_area is not null
    order by beat, data_hora_ocorrencia desc

),

dimensao as (

    select
        {{ dbt_utils.generate_surrogate_key(['s.beat', 's.dbt_valid_from']) }}::bigint as sk_geografia,

        s.beat                                  as beat,
        lpad(s.beat::text, 4, '0')              as beat_formatado,

        s.district                              as district,
        lpad(s.district::text, 3, '0')          as district_formatado,
        'Distrito ' || s.district::text         as nome_district,

        d.district_atual                        as district_atual,

        a.ward                                  as ward,
        'Ward ' || a.ward::text                 as nome_ward,
        a.community_area                        as community_area,

        (s.district <> d.district_atual)        as flag_distrito_reorganizado,

        s.dbt_valid_from                        as valido_de,
        coalesce(s.dbt_valid_to, '9999-12-31'::timestamp) as valido_ate,
        (s.dbt_valid_to is null)                as flag_versao_atual

    from snapshot_geo s
    left join distrito_corrente d
        on s.beat = d.beat
    left join atributos_predominantes a
        on s.beat = a.beat

)

select * from dimensao

union all

-- Membro substituto. Absorve os 47 registros sem district e as ocorrências
-- sem beat. NÃO descartar essas linhas do fato — descartá-las subestimaria
-- as contagens totais.
select
    -1, -1, 'N/D', -1, 'N/D', 'Não informado', -1,
    -1, 'Não informado', -1,
    false,
    '1900-01-01'::timestamp, '9999-12-31'::timestamp, true
