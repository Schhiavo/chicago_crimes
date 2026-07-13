{{ config(materialized='table') }}

{#
    Dimensão Local — grão: tipo de local. SCD Tipo 1.
    218 valores distintos em location_description.
    16.309 ocorrências (0,19%) não têm o atributo preenchido → membro substituto.
#}

with locais as (

    select distinct
        location_description
    from {{ ref('stg_crimes') }}
    where location_description is not null

),

dimensao as (

    select
        {{ dbt_utils.generate_surrogate_key(['location_description']) }}::text as sk_local,

        location_description                    as descricao_local,

        -- Agrupamento analítico: reduz 218 valores a poucas categorias de negócio,
        -- viabilizando gráficos legíveis. Recorte não presente na fonte.
        case
            when location_description like '%RESIDENCE%'
              or location_description like '%APARTMENT%'
              or location_description like '%HOUSE%'
              or location_description like '%PORCH%'
              or location_description like '%YARD%'
                then 'Residencial'

            when location_description like '%STREET%'
              or location_description like '%SIDEWALK%'
              or location_description like '%ALLEY%'
              or location_description like '%HIGHWAY%'
              or location_description like '%BRIDGE%'
                then 'Via pública'

            when location_description like '%STORE%'
              or location_description like '%RESTAURANT%'
              or location_description like '%BAR%'
              or location_description like '%COMMERCIAL%'
              or location_description like '%GAS STATION%'
              or location_description like '%BANK%'
              or location_description like '%HOTEL%'
                then 'Comercial'

            when location_description like '%SCHOOL%'
              or location_description like '%COLLEGE%'
              or location_description like '%UNIVERSITY%'
                then 'Educacional'

            when location_description like '%CTA%'
              or location_description like '%TRAIN%'
              or location_description like '%BUS%'
              or location_description like '%AIRPORT%'
              or location_description like '%TAXI%'
                then 'Transporte público'

            when location_description like '%PARK%'
              or location_description like '%LAKEFRONT%'
                then 'Área de lazer'

            when location_description like '%VEHICLE%'
              or location_description like '%AUTO%'
              or location_description like '%PARKING%'
                then 'Veículo / estacionamento'

            else 'Outros'
        end                                     as categoria_local,

        -- Locais fechados tendem a ter subnotificação distinta dos abertos.
        (location_description like '%STREET%'
         or location_description like '%SIDEWALK%'
         or location_description like '%ALLEY%'
         or location_description like '%PARK%')  as flag_local_publico

    from locais

)

select * from dimensao

union all

select '-1', 'Não informado', 'Não informado', false
