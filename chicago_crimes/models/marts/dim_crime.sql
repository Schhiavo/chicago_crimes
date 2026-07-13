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

    -- A redação vigente de cada IUCR: a versão do snapshot ainda aberta.
    select
        iucr,
        primary_type as primary_type_atual,
        description  as description_atual
    from snapshot_crime
    where dbt_valid_to is null

),

dimensao as (

    select
        {{ dbt_utils.generate_surrogate_key(['s.iucr', 's.dbt_valid_from']) }}::text as sk_crime,

        s.iucr                                  as iucr,

        -- Atributos históricos (como constavam à época)
        s.primary_type                          as primary_type,
        s.description                           as description,
        s.fbi_code                              as fbi_code,

        -- Atributos correntes (para agregação estável ao longo do tempo)
        c.primary_type_atual                    as primary_type_atual,
        c.description_atual                     as description_atual,

        -- Agrupamento analítico: crimes contra a pessoa vs. contra o patrimônio.
        -- Recorte de negócio, não presente na fonte.
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

        -- Controle SCD Tipo 2
        --
        -- BACKDATING DA VERSÃO INAUGURAL:
        -- O dbt carimba dbt_valid_from com o INSTANTE DA EXECUÇÃO do snapshot,
        -- não com a data histórica do registro. Na carga inicial isso significa
        -- valido_de = 2026 (hoje), e nenhuma ocorrência anterior casaria no join
        -- temporal do fato (data_hora >= valido_de seria sempre falso).
        --
        -- A versão inaugural de cada chave é, portanto, retroagida ao início da
        -- série. Prática padrão em carga inicial de DW: a primeira versão de um
        -- registro dimensional vale desde sempre, não desde o momento em que o
        -- pipeline rodou pela primeira vez.
        --
        -- Versões SUBSEQUENTES (geradas por execuções futuras do snapshot, quando
        -- a fonte mudar) mantêm a data real da mudança — é aí que o SCD Tipo 2
        -- passa a registrar histórico de verdade.
        case
            when s.dbt_valid_from = v.primeira_execucao
                then '1900-01-01'::timestamp
            else s.dbt_valid_from
        end                                     as valido_de,

        coalesce(s.dbt_valid_to, '9999-12-31'::timestamp) as valido_ate,
        (s.dbt_valid_to is null)                as flag_versao_atual

    from snapshot_crime s
    left join descricao_corrente c
        on s.iucr = c.iucr
    cross join (
        select min(dbt_valid_from) as primeira_execucao
        from snapshot_crime
    ) v

)

select * from dimensao

union all

-- Membro substituto para ocorrências sem IUCR válido.
select
    '-1', 'N/D', 'Não informado', 'Não informado', 'N/D',
    'Não informado', 'Não informado', 'Não informado',
    '1900-01-01'::timestamp, '9999-12-31'::timestamp, true
