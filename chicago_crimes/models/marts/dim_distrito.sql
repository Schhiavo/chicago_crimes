{{ config(materialized='table') }}

{#
    Dimensão Distrito — SHRUNKEN CONFORMED DIMENSION de dim_geografia.
    Grão: distrito × versão. SCD Tipo 2.

    Por que não reutilizar dim_geografia?
    dim_geografia tem grão BEAT (~305 linhas). O fato P2 tem grão DISTRITO
    (~25). Ligá-los multiplicaria cada linha do fato pelo número de beats do
    distrito (~12×), corrompendo todas as medidas.

    Mantém SCD Tipo 2 porque o próprio conjunto de distritos mudou em 2012
    (desativação do 13, 21 e 23). Um relatório de série histórica por distrito
    precisa saber que o distrito 13 existiu até 2012 e deixou de existir depois.
#}

with distritos as (

    select distinct
        district,
        valido_de,
        valido_ate,
        flag_versao_atual
    from {{ ref('dim_geografia') }}
    where sk_geografia <> '-1'
      and district is not null

),

-- Um distrito pode aparecer em várias versões de beat com as mesmas datas.
-- Consolida para o grão distrital.
consolidado as (

    select
        district,
        min(valido_de)              as valido_de,
        max(valido_ate)             as valido_ate,
        bool_or(flag_versao_atual)  as flag_versao_atual
    from distritos
    group by district

)

select
    {{ dbt_utils.generate_surrogate_key(['district', 'valido_de']) }}::text as sk_distrito,
    district                                as district,
    lpad(district::text, 3, '0')            as district_formatado,
    'Distrito ' || district::text           as nome_district,

    -- Distritos desativados na consolidação de 2012.
    (district in (13, 21, 23))              as flag_distrito_desativado,

    valido_de                               as valido_de,
    valido_ate                              as valido_ate,
    flag_versao_atual                       as flag_versao_atual
from consolidado

union all

select '-1', -1, 'N/D', 'Não informado', false,
       '1900-01-01'::timestamp, '9999-12-31'::timestamp, true
