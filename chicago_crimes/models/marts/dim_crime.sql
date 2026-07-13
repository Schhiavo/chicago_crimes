{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['sk_crime'], 'unique': True},
            {'columns': ['iucr']}
        ]
    )
}}

{#
    Dimensão Crime — grão: IUCR × versão. SCD Tipo 2.

    Consome snap_crime, que capturou a padronização de nomenclatura de 2019–2020.
    Cada linha é uma VERSÃO de um código IUCR, delimitada por valido_de/valido_ate.

    Ponto crítico de uso:
      - `description`         = redação vigente à época do registro (fidelidade histórica)
      - `description_atual`   = redação corrente do mesmo IUCR (agregação consistente)

    Agrupar por `description` parte o mesmo crime em duas linhas
    ("ARMED: HANDGUN" e "ARMED - HANDGUN"). Os relatórios devem agregar por
    `description_atual` ou por `iucr`, e usar `description` apenas quando a
    fidelidade ao registro original importar.
#}

with snapshot_crime as (

    select * from {{ ref('snap_crime') }}

),

descricao_corrente as (

    select
        iucr,
        primary_type as primary_type_atual,
        description  as description_atual
    from snapshot_crime
    where dbt_valid_to is null

),

dimensao as (

    select
        {{ dbt_utils.generate_surrogate_key(['s.iucr', 's.dbt_valid_from']) }}::bigint as sk_crime,

        s.iucr                                  as iucr,

        s.primary_type                          as primary_type,
        s.description                           as description,
        s.fbi_code                              as fbi_code,

        c.primary_type_atual                    as primary_type_atual,
        c.description_atual                     as description_atual,

        case
            when s.primary_type in (
                'HOMICIDE', 'CRIM SEXUAL ASSAULT', 'CRIMINAL SEXUAL ASSAULT',
                'ASSAULT', 'BATTERY', 'ROBBERY', 'KIDNAPPING',
                'OFFENSE INVOLVING CHILDREN', 'HUMAN TRAFFICKING',
                'INTIMIDATION', 'STALKING', 'SEX OFFENSE'
            ) then 'Crime violento'
            when s.primary_type in (
                'THEFT', 'BURGLARY', 'MOTOR VEHICLE THEFT', 'ARSON',
                'CRIMINAL DAMAGE', 'CRIMINAL TRESPASS', 'DECEPTIVE PRACTICE'
            ) then 'Crime patrimonial'
            when s.primary_type in ('NARCOTICS', 'OTHER NARCOTIC VIOLATION')
                then 'Entorpecentes'
            when s.primary_type in ('WEAPONS VIOLATION', 'CONCEALED CARRY LICENSE VIOLATION')
                then 'Armas'
            else 'Outros'
        end                                     as categoria_analitica,

        s.dbt_valid_from                        as valido_de,
        coalesce(s.dbt_valid_to, '9999-12-31'::timestamp) as valido_ate,
        (s.dbt_valid_to is null)                as flag_versao_atual

    from snapshot_crime s
    left join descricao_corrente c
        on s.iucr = c.iucr

)

select * from dimensao

union all

select
    -1, 'N/D', 'Não informado', 'Não informado', 'N/D',
    'Não informado', 'Não informado', 'Não informado',
    '1900-01-01'::timestamp, '9999-12-31'::timestamp, true
