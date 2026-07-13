{#
    SCD Tipo 2 — dim_crime

    Justificativa empírica: o CPD padronizou a nomenclatura das descrições
    por volta de 2019–2020. 180 dos 418 códigos IUCR (43%) apresentam mais de
    uma grafia de `description`, e 13 apresentam mais de um `primary_type`.

    Exemplo (IUCR 031A):
      "ARMED: HANDGUN"  → registros de 2001 a 2020
      "ARMED - HANDGUN" → registros de 2001 a 2026

    O código IUCR e o fbi_code permanecem estáveis (0 divergências), o que
    confirma que a mudança é de rótulo, não de classificação. Sem SCD Tipo 2,
    a redação atual sobrescreveria a histórica e um crime de 2015 passaria a
    ser exibido com terminologia que não existia à época.

    A chave natural é o IUCR. A estratégia `check` compara os atributos
    descritivos; ao detectar mudança, encerra a versão vigente e abre outra.
#}

{% snapshot snap_crime %}

{{
    config(
        target_schema='snapshots',
        unique_key='iucr',
        strategy='check',
        check_cols=['primary_type', 'description', 'fbi_code']
    )
}}

with versao_vigente as (

    select distinct on (iucr)
        iucr,
        primary_type,
        description,
        fbi_code
    from {{ ref('stg_crimes') }}
    where iucr is not null
    order by iucr, data_hora_ocorrencia desc

)

select * from versao_vigente

{% endsnapshot %}
