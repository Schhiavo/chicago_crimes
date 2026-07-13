{{ config(materialized='table') }}

{#
    Dimensão Flags (junk dimension) — grão: combinação de flags. SCD Tipo 1.

    Técnica Kimball: atributos booleanos de baixa cardinalidade, sem afinidade
    com nenhuma outra dimensão, são consolidados numa única dimensão de
    2 × 2 = 4 linhas — em vez de poluírem o fato com colunas soltas ou
    gerarem duas dimensões degeneradas de duas linhas cada.

    As flags também permanecem como medidas (0/1) no fato, para permitir
    cálculo de taxas via SUM. Aqui elas servem como eixo de FILTRO,
    com rótulos legíveis ao usuário final.
#}

with combinacoes as (

    select
        prisao,
        domestico
    from (values (true), (false)) as p(prisao)
    cross join (values (true), (false)) as d(domestico)

),

dimensao as (

    select
        {{ dbt_utils.generate_surrogate_key(['prisao', 'domestico']) }}::text as sk_flags,

        prisao                                  as flag_prisao,
        domestico                               as flag_domestico,

        case when prisao    then 'Com prisão'      else 'Sem prisão'      end as descricao_prisao,
        case when domestico then 'Violência doméstica' else 'Não doméstico' end as descricao_domestico,

        case
            when     prisao and     domestico then 'Doméstico com prisão'
            when     prisao and not domestico then 'Não doméstico com prisão'
            when not prisao and     domestico then 'Doméstico sem prisão'
            else                                   'Não doméstico sem prisão'
        end                                     as descricao_combinada

    from combinacoes

)

select * from dimensao
