-- O cadastro do PMO: é o de-para da integração (codigo_ferramenta → projeto_id).
CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida EXPECT (data_inicio IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_valida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro de projetos do PMO, tipado. ferramenta normalizada (excel/clickup/msproject) e codigo_ferramenta é a chave do de-para com as tarefas.'
AS SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  CASE
    WHEN lower(trim(ferramenta)) IN ('excel', 'planilha') THEN 'excel'
    WHEN lower(trim(ferramenta)) = 'clickup' THEN 'clickup'
    WHEN lower(trim(ferramenta)) IN ('ms project', 'msproject', 'project') THEN 'msproject'
  END AS ferramenta,
  ferramenta AS ferramenta_como_veio,
  nullif(trim(codigo_ferramenta), '') AS codigo_ferramenta,
  CAST(valor_contrato AS DECIMAL(18, 2)) AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(18, 2)) AS orcamento_custo,
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'), try_to_date(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
  to_date(data_fim_baseline) AS data_fim_baseline,
  status,
  gerente_projeto
FROM projetoprisma.bronze.projetos;
