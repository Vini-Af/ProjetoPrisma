CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'Cadastro de colaboradores, um por colaborador_id (COL0102, COL0257 e COL0433 vinham duplicados em CAIXA ALTA); papel em minúsculas.'
AS SELECT
  colaborador_id,
  nome,
  lower(papel) AS papel,
  senioridade,
  CAST(custo_hora AS DECIMAL(10, 2)) AS custo_hora,
  to_date(data_admissao) AS data_admissao,
  to_date(nullif(data_desligamento, '')) AS data_desligamento
FROM (
  SELECT *,
         -- fica o cadastro com papel já em minúsculas
         row_number() OVER (PARTITION BY colaborador_id ORDER BY papel = lower(papel) DESC) AS rn
  FROM projetoprisma.bronze.colaboradores
)
WHERE rn = 1;

CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Horas apontadas por colaborador, projeto e semana. semana = sexta (semana_inicio + 4).'
AS SELECT
  colaborador_id,
  projeto_id,
  to_date(semana_inicio) AS semana_inicio,
  date_add(to_date(semana_inicio), 4) AS semana,
  CAST(horas_disponiveis AS DOUBLE) AS horas_disponiveis,
  CAST(horas_apontadas AS DOUBLE) AS horas_apontadas
FROM projetoprisma.bronze.apontamentos;
