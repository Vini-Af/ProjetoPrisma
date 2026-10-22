CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas de fornecedores. CodeForge normalizada (4 grafias; fornecedor_como_veio guarda a original). data_entrega vazia = em aberto; em_atraso = em aberto com prazo antes de 2026-10-16.'
AS SELECT
  entrega_id,
  projeto_id,
  CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%' THEN 'CodeForge Consultoria Ltda'
       ELSE fornecedor END AS fornecedor,
  fornecedor AS fornecedor_como_veio,
  item,
  valor,
  data_pedido,
  data_prometida,
  data_entrega,
  prazo_contratado_dias,
  status,
  datediff(data_prometida, data_pedido) AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido) AS prazo_real_dias,
  datediff(data_entrega, data_prometida) AS dias_de_atraso_na_entrega,
  data_entrega IS NULL AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16' AS em_atraso
FROM (
  SELECT
    entrega_id, projeto_id, fornecedor, item, status,
    CAST(valor AS DECIMAL(18, 2)) AS valor,
    to_date(data_pedido) AS data_pedido,
    to_date(data_prometida) AS data_prometida,
    to_date(nullif(data_entrega, '')) AS data_entrega,
    CAST(prazo_contratado_dias AS INT) AS prazo_contratado_dias
  FROM projetoprisma.bronze.entregas_fornecedor
);
