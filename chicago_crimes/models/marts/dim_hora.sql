{{ config(materialized='table') }}

{#
    Dimensão Hora — grão: hora do dia (0–23). SCD Tipo 1.
    Separada de dim_data por princípio Kimball: combinar dia e hora numa única
    dimensão a faria crescer 24× (9.500 × 24 = 228 mil linhas) sem ganho analítico.
    Separadas, permitem a pergunta "em que horário ocorrem mais crimes?"
    independentemente da data.
#}

with horas as (

    select generate_series(0, 23) as hora

),

atributos as (

    select
        hora                                     as sk_hora,
        hora                                     as hora_do_dia,
        lpad(hora::text, 2, '0') || ':00'        as hora_formatada,

        case
            when hora between  0 and  5 then 'Madrugada'
            when hora between  6 and 11 then 'Manhã'
            when hora between 12 and 17 then 'Tarde'
            else                             'Noite'
        end                                      as periodo_do_dia,

        case
            when hora between 22 and 23 or hora between 0 and 3 then 'Horário noturno crítico'
            when hora between 4 and 6                            then 'Madrugada'
            else                                                      'Horário diurno'
        end                                      as faixa_operacional,

        (hora between 22 and 23 or hora between 0 and 5) as flag_noturno

    from horas

)

select * from atributos

union all

select -1, -1, 'Não informado', 'Não informado', 'Não informado', false
