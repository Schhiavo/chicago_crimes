# Chicago Crimes — Data Warehouse Dimensional

Data warehouse dimensional (arquitetura Kimball) sobre a base pública de crimes de Chicago, com ETL em dbt-core e camada analítica em Power BI.

**Fonte:** [Crimes 2001 to Present](https://catalog.data.gov/dataset/crimes-2001-to-present) — Chicago Police Department
**Volume:** 8.591.649 ocorrências (2001–2026)
**Stack:** PostgreSQL · dbt-core (dbt-postgres) · Power BI Desktop · Power BI Report Builder

---

## Arquitetura

```
raw.crimes_raw   →   stg_crimes   →   snapshots   →   marts   →   Power BI
(fonte)              (cast/limpeza)   (SCD Tipo 2)    (estrela)
```

### Processos de negócio

| # | Processo | Grão | Fato | Linhas |
|---|---|---|---|---|
| P1 | Ocorrência criminal reportada | 1 ocorrência | `fct_ocorrencias` | 8.591.649 |
| P2 | Desempenho operacional mensal | mês × distrito × tipo | `fct_desempenho_mensal` | 147.845 |

### Bus matrix

| Processo | data | hora | crime | geografia | local | flags | mes | distrito | tipo_crime |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **P1 — Ocorrências** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — |
| **P2 — Desempenho** | — | — | — | — | — | — | ✅ | ✅ | ✅ |

As dimensões de P2 são **conformadas encolhidas** (*shrunken conformed dimensions*): mesma semântica das de P1, em grão superior. Isso permite *drill-across* entre os fatos e evita o erro de ligar um fato agregado a uma dimensão de grão atômico o que multiplicaria as medidas.

---

## Dimensões de mudança lenta (SCD Tipo 2)

Duas dimensões usam snapshots do dbt, ambas justificadas por mudanças reais encontradas na fonte:

| Dimensão | Mudança capturada | Evidência |
|---|---|---|
| `dim_crime` | Padronização de nomenclatura do CPD em 2019–2020 | 180 dos 418 IUCRs mudaram a redação de `description` (`ARMED: HANDGUN` → `ARMED - HANDGUN`). O `fbi_code` permaneceu estável (0 divergências) é mudança de rótulo, não de classificação. |
| `dim_geografia` | Consolidação distrital de 2012 | Desativação dos distritos 13, 21 e 23. 333.941 registros têm beat de distrito extinto associado ao sucessor, todos terminando em 2012. |

**Nota importante sobre `dim_geografia`:** a fonte aplicou SCD Tipo 1 e sobrescreveu o distrito histórico. Sem o snapshot, um crime de 2010 no beat `1311` seria reportado no distrito 12,  que em 2010 não o cobria. O modelo recupera a informação que a origem descartou.

### Backdating da versão inaugural

O dbt carimba `dbt_valid_from` com o **instante da execução** do snapshot. Na carga inicial isso significa `valido_de = 2026`, e nenhum fato histórico casaria no join temporal (`data_hora >= valido_de` seria sempre falso).

A versão inaugural de cada chave é, portanto, retroagida a `1900-01-01`. Prática padrão em carga inicial de DW: a primeira versão de um registro dimensional vale desde sempre.

---

## Pré-requisitos

- PostgreSQL 14+
- Python 3.9+
- dbt-core e dbt-postgres (`pip install -r requirements.txt`)
- Driver ODBC PostgreSQL (psqlODBC) — apenas para os relatórios paginados

---

## Execução

### 1. Carga da fonte

Baixe o CSV do portal e execute o script de carga:

```bash
psql -U postgres -c "CREATE DATABASE chicago_crimes;"
psql -U postgres -d chicago_crimes -f sql/01_carga_raw.sql
```

Depois, dentro do `psql`:

```sql
\copy raw.crimes_raw FROM 'caminho/Crimes_-_2001_to_Present.csv' WITH (FORMAT csv, HEADER true, QUOTE '"', ESCAPE '"', NULL '')
```

> **Por que todas as colunas são `TEXT`?** O CSV tem campos vazios em colunas numéricas e valores com zeros à esquerda (`district` = `004`, `beat` = `0421`). Tipagem estrita quebraria o `COPY`. O cast fica na camada de staging, mantendo a *landing zone* fiel à origem.

### 2. Configurar o dbt

```bash
cp chicago_crimes/profiles.yml.example ~/.dbt/profiles.yml
```

Ajuste as credenciais. A senha é lida da variável de ambiente:

```bash
export DBT_PG_PASSWORD='sua_senha'     # Linux/macOS
$env:DBT_PG_PASSWORD = 'sua_senha'     # Windows PowerShell
```

### 3. Rodar o pipeline

```bash
cd chicago_crimes

dbt deps
dbt debug

dbt run --select staging     # ~7 min (8,59M linhas, cast e limpeza)
dbt snapshot                 # ~1 min
dbt run --select marts       # ~3 min
dbt test                     # 66 testes, ~1,5 min
```

**A ordem importa:** os snapshots dependem do staging, e as dimensões SCD 2 dependem dos snapshots.

Em execuções subsequentes, rode `dbt snapshot` **antes** dos marts, para que novas versões das dimensões sejam capturadas.

### 4. Documentação

```bash
dbt docs generate
dbt docs serve
```

Abre em `localhost:8080` com o grafo de linhagem completo.

---

## Testes

66 testes automatizados, todos aprovados:

| Tipo | Cobertura |
|---|---|
| `unique` + `not_null` | Todas as chaves naturais e substitutas |
| `relationships` | Todas as 9 FKs dos dois fatos |
| `accepted_values` | Medidas do fato (domínio 0/1) |
| `unique_combination_of_columns` | Grão de `fct_desempenho_mensal` |

---

## Achados da análise exploratória

Decisões de modelagem fundamentadas em verificação empírica:

| Achado | Consequência |
|---|---|
| `ID` sem duplicatas (0 em 8,59M) | Confirma o grão do fato P1 |
| `IUCR` → `FBI Code`: 0 divergências | Confirma `dim_crime` com grão IUCR |
| `Description`: 180 IUCRs com múltiplas grafias | Motiva SCD Tipo 2 em `dim_crime` |
| `District` ⊃ `Beat`: 99% dos desvios terminam em 2012 | Motiva SCD Tipo 2 em `dim_geografia` |
| `Ward`/`Community Area`: 99,1% nulos em 2001 | Relatórios por esses atributos devem filtrar a partir de 2003 |
| 2026 com 113.835 registros (ano em curso) | `flag_ano_parcial` em `dim_data` e `dim_mes` |
| 97.005 ocorrências sem coordenada (1,13%) | Membro substituto; mapas cobrem 98,9% |

---

## Estrutura do repositório

```
.
├── README.md
├── requirements.txt
├── sql/
│   └── 01_carga_raw.sql          Carga da fonte + validações
├── chicago_crimes/               Projeto dbt
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── profiles.yml.example
│   ├── models/
│   │   ├── staging/
│   │   │   ├── _sources.yml      Declaração da fonte
│   │   │   ├── _staging.yml      Testes e documentação
│   │   │   └── stg_crimes.sql    Cast, limpeza, padronização
│   │   └── marts/
│   │       ├── _marts.yml        Testes e documentação
│   │       ├── dim_data.sql            Dia          · SCD 1
│   │       ├── dim_hora.sql            Hora         · SCD 1
│   │       ├── dim_crime.sql           IUCR         · SCD 2
│   │       ├── dim_geografia.sql       Beat         · SCD 2
│   │       ├── dim_local.sql           Tipo local   · SCD 1
│   │       ├── dim_flags.sql           Junk         · SCD 1
│   │       ├── dim_mes.sql             Shrunken de dim_data
│   │       ├── dim_distrito.sql        Shrunken de dim_geografia · SCD 2
│   │       ├── dim_tipo_crime.sql      Shrunken de dim_crime
│   │       ├── fct_ocorrencias.sql        Fato P1 (transacional)
│   │       └── fct_desempenho_mensal.sql  Fato P2 (agregado)
│   └── snapshots/
│       ├── snap_crime.sql        SCD 2 — padronização de 2019–2020
│       └── snap_geografia.sql    SCD 2 — consolidação distrital de 2012
└── powerbi/
    ├── relatorio_ocorrencias.rdl     Relatório paginado — P1
    └── relatorio_desempenho.rdl      Relatório paginado — P2
```

### Arquivos não versionados

Os `.pbix` excedem o limite de 100 MB do GitHub (~520 MB cada, por conta dos 8,59M de registros importados) e estão no `.gitignore`:

- `modelo_semantico.pbix` — modelo semântico (Passo 3)
- `relatorios.pbix` — relatórios e dashboards (Passos 4.2 e 5)

---

## Camada analítica (Power BI)

**Modelo semântico:** 11 tabelas, 9 relações (todas ∗:1, filtro único), 6 hierarquias, 19 medidas DAX.

**Relatórios paginados** (Report Builder, via ODBC): dois relatórios `.rdl`, um por processo, cada um com três parâmetros (dois campos de texto + um dropdown populado por consulta).

**Relatórios interativos e dashboards** (Desktop): 5 páginas — 3 de relatório (com drill-down, drill-through e cross-filter) e 2 dashboards.
