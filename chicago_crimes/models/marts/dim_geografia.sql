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

-- Ward e community_area não são funcionalmente determinados pelo beat
-- (as fronteiras se cruzam). Elege-se o valor predominante por beat,
-- apenas como atributo informativo da dimensão.
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
        {{ dbt_utils.generate_surrogate_key(['s.beat', 's.dbt_valid_from']) }}::text as sk_geografia,

        s.beat                                  as beat,
        lpad(s.beat::text, 4, '0')              as beat_formatado,

        -- Distrito HISTÓRICO: o que de fato cobria o beat à época do registro.
        -- A fonte perdeu essa informação ao aplicar SCD Tipo 1; o snapshot a recupera.
        s.district                              as district,
        lpad(s.district::text, 3, '0')          as district_formatado,
        'Distrito ' || s.district::text         as nome_district,

        -- Distrito ATUAL: para comparações sob a estrutura organizacional vigente.
        d.district_atual                        as district_atual,

        -- Recortes administrativos alternativos (não aninhados)
        a.ward                                  as ward,
        'Ward ' || a.ward::text                 as nome_ward,
        a.community_area                        as community_area,

        -- Sinaliza os beats afetados pela consolidação de 2012.
        (s.district <> d.district_atual)        as flag_distrito_reorganizado,

        -- Controle SCD Tipo 2
        --
        -- BACKDATING DA VERSÃO INAUGURAL: ver comentário em dim_crime.sql.
        -- O dbt carimba dbt_valid_from com o instante da execução do snapshot.
        -- Sem retroagir a primeira versão, nenhuma ocorrência histórica casaria
        -- no join temporal do fato.
        case
            when s.dbt_valid_from = v.primeira_execucao
                then '1900-01-01'::timestamp
            else s.dbt_valid_from
        end                                     as valido_de,

        coalesce(s.dbt_valid_to, '9999-12-31'::timestamp) as valido_ate,
        (s.dbt_valid_to is null)                as flag_versao_atual

    from snapshot_geo s
    left join distrito_corrente d
        on s.beat = d.beat
    left join atributos_predominantes a
        on s.beat = a.beat
    cross join (
        select min(dbt_valid_from) as primeira_execucao
        from snapshot_geo
    ) v

)

select * from dimensao

union all

-- Membro substituto. Absorve os 47 registros sem district e as ocorrências
-- sem beat. NÃO descartar essas linhas do fato — descartá-las subestimaria
-- as contagens totais.
select
    '-1', -1, 'N/D', -1, 'N/D', 'Não informado', -1,
    -1, 'Não informado', -1,
    false,
    '1900-01-01'::timestamp, '9999-12-31'::timestamp, true
