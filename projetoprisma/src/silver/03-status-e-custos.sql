CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_valido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal dos projetos. farol em minúsculas; status_vazio sinaliza texto vazio, N/A ou "ver ata da reunião" (a linha fica).'
AS SELECT
  projeto_id,
  to_date(data_status) AS data_status,
  gerente,
  lower(trim(farol)) AS farol,
  CAST(pct_concluido AS INT) AS pct_concluido,
  texto_status,
  coalesce(trim(texto_status), '') IN ('', 'N/A', 'ver ata da reunião') AS status_vazio
FROM projetoprisma.bronze.status_semanal;

CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo. valor com vírgula decimal corrigido antes do CAST; estornos (negativos) ficam, sinalizados em estorno. semana = sexta da semana.'
AS SELECT
  lancamento_id,
  projeto_id,
  to_date(data) AS data,
  date_add(date_trunc('WEEK', to_date(data)), 4) AS semana,
  categoria,
  descricao,
  CAST(replace(valor, ',', '.') AS DECIMAL(18, 2)) AS valor,   -- nunca try_cast: descartaria valores em silêncio
  CAST(replace(valor, ',', '.') AS DECIMAL(18, 2)) < 0 AS estorno,
  centro_custo
FROM projetoprisma.bronze.custos;
