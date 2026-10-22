-- AS TRÊS FERRAMENTAS VIRAM UMA: uma temp view por ferramenta, todas com as mesmas colunas,
-- na mesma ordem (o UNION ALL é por posição).

CREATE TEMPORARY VIEW tarefas_excel AS
WITH x AS (
  SELECT
    -- de-para pelo arquivo; sem código ou com o nome sem acento, o PRJ-xxx do nome do arquivo
    coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
    e.*
  FROM projetoprisma.bronze.excel_tarefas e
  LEFT JOIN projetos p ON p.codigo_ferramenta = e.arquivo
  WHERE e.tarefa <> 'TOTAL'
)
SELECT
  projeto_id,
  'excel' AS ferramenta,
  CAST(id AS STRING) AS id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  -- data com '/' é dd/MM/yyyy; sem '/' é o número de série do Excel
  CASE WHEN inicio_previsto LIKE '%/%' THEN to_date(inicio_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(nullif(inicio_previsto, '') AS INT)) END AS inicio_baseline,
  CASE WHEN termino_previsto LIKE '%/%' THEN to_date(termino_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(nullif(termino_previsto, '') AS INT)) END AS fim_baseline,
  CASE WHEN inicio_real LIKE '%/%' THEN to_date(inicio_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(nullif(inicio_real, '') AS INT)) END AS inicio_real,
  CASE WHEN termino_real LIKE '%/%' THEN to_date(termino_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(nullif(termino_real, '') AS INT)) END AS fim_real,
  -- '45%' / '10,5%' → número; sem '%' é fração (0.45 → 45)
  CASE WHEN contains(pct_concluido, '%') THEN CAST(replace(replace(pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(nullif(pct_concluido, '') AS DOUBLE) * 100 END AS pct_como_veio,
  CAST(replace(horas_previstas, 'h', '') AS DOUBLE) AS horas,
  CAST(NULL AS STRING) AS status_na_ferramenta
FROM x;

CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  -- de-para pelo list_id; sem código, pelo nome da lista
  coalesce(p.projeto_id, pn.projeto_id) AS projeto_id,
  'clickup' AS ferramenta,
  c.id AS id_na_ferramenta,
  filter(c.custom_fields, f -> f.name = 'Fase')[0].value AS fase,
  c.name AS tarefa,
  c.assignees[0].username AS responsavel,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))) AS inicio_baseline,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT))) AS fim_baseline,
  to_date(timestamp_millis(CAST(nullif(c.start_date, '') AS BIGINT))) AS inicio_real,
  to_date(timestamp_millis(CAST(nullif(c.date_done, '') AS BIGINT))) AS fim_real,
  CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE) AS pct_como_veio,
  c.time_estimate / 3600000 AS horas,
  CASE
    WHEN lower(trim(c.status.status)) IN ('done', 'closed', 'concluído') THEN 'concluida'
    WHEN lower(trim(c.status.status)) IN ('to do', 'backlog', 'a fazer') THEN 'a_fazer'
    WHEN lower(trim(c.status.status)) IN ('in progress', 'em andamento', 'doing', 'review') THEN 'em_andamento'
  END AS status_na_ferramenta
FROM projetoprisma.bronze.clickup_tarefas c
LEFT JOIN projetos p ON p.codigo_ferramenta = c.list_id
LEFT JOIN projetos pn ON pn.nome_projeto = c.list_name AND pn.ferramenta = 'clickup';

CREATE TEMPORARY VIEW tarefas_msproject AS
WITH m AS (
  SELECT
    *,
    -- a fase é a última tarefa-resumo de nível 1 antes da tarefa
    last_value(CASE WHEN OutlineLevel = 1 THEN Name END, true) OVER (PARTITION BY arquivo ORDER BY UID) AS fase
  FROM projetoprisma.bronze.msproject_tarefas
)
SELECT
  p.projeto_id,
  'msproject' AS ferramenta,
  CAST(m.UID AS STRING) AS id_na_ferramenta,
  m.fase,
  m.Name AS tarefa,
  CAST(NULL AS STRING) AS responsavel,
  to_date(m.Baseline.Start) AS inicio_baseline,
  to_date(m.Baseline.Finish) AS fim_baseline,
  to_date(m.ActualStart) AS inicio_real,
  to_date(m.ActualFinish) AS fim_real,
  CAST(m.PercentComplete AS DOUBLE) AS pct_como_veio,
  CAST(regexp_extract(m.Work, 'PT([0-9]+)H', 1) AS DOUBLE) AS horas,   -- 'PT40H0M0S' → 40
  CAST(NULL AS STRING) AS status_na_ferramenta
FROM m
LEFT JOIN projetos p ON p.codigo_ferramenta = m.arquivo
WHERE m.Summary = 0;   -- as tarefas-resumo somam as de baixo

CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto EXPECT (projeto_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100) ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas EXPECT (horas > 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Tarefas de Excel, ClickUp e MS Project integradas num só formato. tarefa_id = projeto-ferramenta-id; pct_concluido limitado a 100 (pct_veio_acima_de_100 sinaliza).'
AS SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  *,
  least(pct_como_veio, 100) AS pct_concluido,
  pct_como_veio > 100 AS pct_veio_acima_de_100
FROM (
  SELECT * FROM tarefas_excel
  UNION ALL SELECT * FROM tarefas_clickup
  UNION ALL SELECT * FROM tarefas_msproject
);
