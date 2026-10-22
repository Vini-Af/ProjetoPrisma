"""Gera resources/dashboard-portfolio.lvdash.json (AI/BI, GRID_V1).

Tabelas da gold com o nome PURO (catálogo e schema vêm do recurso do bundle:
dataset_catalog / dataset_schema). A silver.entregas_fornecedor vai com o nome completo.

Uso: python scripts/gerar_dashboard.py
"""
import json
from pathlib import Path

SAIDA = Path(__file__).resolve().parent.parent / "resources" / "dashboard-portfolio.lvdash.json"

CRITICO, ATENCAO, OK = "#FF5F46", "#F6C344", "#22C2F4"
BRL = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
       "decimalPlaces": {"type": "max", "places": 2}}
INDICE = {"type": "number-plain", "decimalPlaces": {"type": "exact", "places": 2}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}
CORES_SITUACAO = {"type": "categorical", "mappings": [
    {"value": "crítico", "color": CRITICO},
    {"value": "atenção", "color": ATENCAO},
    {"value": "ok", "color": OK},
]}


def ds(nome, titulo, sql, columns=None):
    d = {"name": nome, "displayName": titulo, "queryLines": [l + "\n" for l in sql.strip().splitlines()]}
    if columns:
        d["columns"] = columns
    return d


DATASETS = [
    ds("ds_carteira", "Carteira em andamento", """
SELECT projeto_id, projeto, cliente, segmento, ferramenta, gerente_projeto,
       valor_contrato, orcamento, pv, ev, ac, eac, spi, cpi, estouro_previsto,
       situacao, farol_do_gerente, farol_calculado,
       CASE WHEN melancia THEN 'sim' ELSE '' END AS melancia,
       CASE WHEN melancia THEN 1 ELSE 0 END AS e_melancia,
       CASE WHEN situacao IN ('atenção', 'crítico') THEN 1 ELSE 0 END AS em_risco,
       CASE WHEN situacao = 'crítico' THEN 1 ELSE 0 END AS e_critico
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC
""", columns=[
        {"displayName": "SPI da carteira", "expression": "SUM(`ev`) / SUM(`pv`)"},
        {"displayName": "CPI da carteira", "expression": "SUM(`ev`) / SUM(`ac`)"},
    ]),
    ds("ds_semanal", "SPI e CPI semanais da carteira", """
SELECT semana,
       try_divide(SUM(ev), SUM(pv)) AS spi,
       try_divide(SUM(ev), SUM(ac)) AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana
"""),
    ds("ds_top_ociosos", "Top 15 custo da hora parada", """
SELECT concat(nome, ' (', papel, ')') AS pessoa,
       SUM(custo_ocioso) AS custo_ocioso,
       SUM(horas_ociosas) AS horas_ociosas
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY nome, papel
ORDER BY custo_ocioso DESC
LIMIT 15
"""),
    ds("ds_utilizacao", "Utilização por pessoa e projeto", """
SELECT colaborador_id, nome, papel, senioridade, projeto_id,
       SUM(horas_disponiveis) AS horas_disponiveis,
       SUM(horas_apontadas) AS horas_apontadas,
       SUM(horas_ociosas) AS horas_ociosas,
       try_divide(SUM(horas_apontadas), SUM(horas_disponiveis)) AS utilizacao,
       SUM(custo_ocioso) AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY utilizacao ASC
"""),
    ds("ds_causas", "Causas de bloqueio (90 dias)", """
SELECT projeto_id, causa_bloqueio, COUNT(*) AS status
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
ORDER BY projeto_id
"""),
    ds("ds_fornecedores", "Fornecedores", """
SELECT fornecedor,
       COUNT(DISTINCT fornecedor_como_veio) AS grafias,
       COUNT(*) AS entregas,
       try_divide(SUM(prazo_real_dias), SUM(CASE WHEN NOT em_aberto THEN prazo_prometido_dias END)) AS prazo_real_sobre_prometido,
       try_divide(COUNT_IF(NOT em_aberto AND dias_de_atraso_na_entrega <= 0), COUNT_IF(NOT em_aberto)) AS pct_no_prazo,
       COUNT_IF(em_atraso) AS em_atraso_hoje
FROM projetoprisma.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY em_atraso_hoje DESC, prazo_real_sobre_prometido DESC
"""),
    ds("ds_atrasadas", "Entregas em atraso hoje", """
SELECT entrega_id, projeto_id, fornecedor, item, valor, data_pedido, data_prometida,
       datediff(DATE'2026-10-16', data_prometida) AS dias_em_atraso
FROM projetoprisma.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_em_atraso DESC
"""),
]


def texto(nome, linhas, y, h=2):
    return {"widget": {"name": nome, "multilineTextboxSpec": {"lines": linhas}},
            "position": {"x": 0, "y": y, "width": 12, "height": h}}


def widget(nome, dataset, fields, spec, pos, disaggregated=False):
    return {"widget": {"name": nome,
                       "queries": [{"name": "main_query", "query": {
                           "datasetName": dataset,
                           "fields": [{"name": n, "expression": e} for n, e in fields],
                           "disaggregated": disaggregated}}],
                       "spec": spec},
            "position": dict(zip(("x", "y", "width", "height"), pos))}


def contador(nome, dataset, campo, expr, titulo, fmt, pos):
    value = {"fieldName": campo, "displayName": titulo}
    if fmt:
        value["format"] = fmt
    return widget(nome, dataset, [(campo, expr)], {
        "version": 2, "widgetType": "counter",
        "encodings": {"value": value},
        "frame": {"showTitle": True, "title": titulo}}, pos)


def tabela(nome, dataset, colunas, titulo, pos):
    """colunas: lista de (campo, título, formato ou None)."""
    cols = []
    for campo, tit, fmt in colunas:
        c = {"fieldName": campo, "displayName": tit}
        if fmt:
            c["format"] = fmt
        cols.append(c)
    return widget(nome, dataset, [(c, f"`{c}`") for c, _, _ in colunas], {
        "version": 2, "widgetType": "table",
        "encodings": {"columns": cols},
        "frame": {"showTitle": True, "title": titulo}}, pos, disaggregated=True)


portfolio = [
    texto("titulo_portfolio", ["## Quais projetos estão atrasados, e quanto esse atraso vai custar?\n", "\n",
                               "Carteira em andamento na fotografia de 16/10/2026. Crítico: SPI ou CPI < 0,8 · atenção: < 0,9."], 0),
    contador("kpi_carteira", "ds_carteira", "sum(valor_contrato)", "SUM(`valor_contrato`)", "Carteira", BRL, (0, 2, 3, 3)),
    contador("kpi_spi", "ds_carteira", "measure(SPI da carteira)", "MEASURE(`SPI da carteira`)", "SPI", INDICE, (3, 2, 3, 3)),
    contador("kpi_cpi", "ds_carteira", "measure(CPI da carteira)", "MEASURE(`CPI da carteira`)", "CPI", INDICE, (6, 2, 3, 3)),
    contador("kpi_estouro", "ds_carteira", "sum(estouro_previsto)", "SUM(`estouro_previsto`)", "Estouro previsto", BRL, (9, 2, 3, 3)),
    contador("kpi_risco", "ds_carteira", "sum(em_risco)", "SUM(`em_risco`)", "Projetos em risco", None, (0, 5, 4, 3)),
    contador("kpi_criticos", "ds_carteira", "sum(e_critico)", "SUM(`e_critico`)", "Críticos", None, (4, 5, 4, 3)),
    contador("kpi_melancias", "ds_carteira", "sum(e_melancia)", "SUM(`e_melancia`)", "Melancias (farol verde, SPI < 0,9)", None, (8, 5, 4, 3)),
    widget("estouro_por_projeto", "ds_carteira",
           [("projeto_id", "`projeto_id`"), ("situacao", "`situacao`"), ("sum(estouro_previsto)", "SUM(`estouro_previsto`)")],
           {"version": 3, "widgetType": "bar",
            "encodings": {
                "x": {"fieldName": "projeto_id", "scale": {"type": "categorical"},
                      "displayName": "Projeto"},
                "y": {"fieldName": "sum(estouro_previsto)", "scale": {"type": "quantitative"},
                      "displayName": "Estouro previsto", "format": BRL},
                "color": {"fieldName": "situacao", "scale": CORES_SITUACAO, "displayName": "Situação"}},
            "frame": {"showTitle": True, "title": "Estouro previsto por projeto"}},
           (0, 8, 6, 6)),
    widget("spi_x_cpi", "ds_carteira",
           [("spi", "`spi`"), ("cpi", "`cpi`"), ("situacao", "`situacao`"), ("projeto", "`projeto`")],
           {"version": 3, "widgetType": "scatter",
            "encodings": {
                "x": {"fieldName": "spi", "scale": {"type": "quantitative"}, "displayName": "SPI"},
                "y": {"fieldName": "cpi", "scale": {"type": "quantitative"}, "displayName": "CPI"},
                "color": {"fieldName": "situacao", "scale": CORES_SITUACAO, "displayName": "Situação"},
                "extra": [{"fieldName": "projeto", "displayName": "Projeto"}]},
            "frame": {"showTitle": True, "title": "SPI × CPI (um ponto por projeto)"}},
           (6, 8, 6, 6), disaggregated=True),
    widget("spi_cpi_semanal", "ds_semanal",
           [("semana", "`semana`"), ("spi", "`spi`"), ("cpi", "`cpi`")],
           {"version": 3, "widgetType": "line",
            "encodings": {
                "x": {"fieldName": "semana", "scale": {"type": "temporal"}, "displayName": "Semana"},
                "y": {"scale": {"type": "quantitative"}, "format": INDICE,
                      "fields": [{"fieldName": "spi", "displayName": "SPI"},
                                 {"fieldName": "cpi", "displayName": "CPI"}]}},
            "annotations": [{"type": "horizontal-line",
                             "encodings": {"y": {"dataValue": "0.9", "dataType": "DOUBLE"},
                                           "label": {"value": "atenção (0,9)"},
                                           "color": {"value": ATENCAO}}}],
            "frame": {"showTitle": True, "title": "SPI e CPI semanais da carteira"}},
           (0, 14, 12, 6), disaggregated=True),
    tabela("tabela_projetos", "ds_carteira", [
        ("projeto", "Projeto", None), ("cliente", "Cliente", None), ("gerente_projeto", "Gerente", None),
        ("situacao", "Situação", None), ("spi", "SPI", INDICE), ("cpi", "CPI", INDICE),
        ("farol_do_gerente", "Farol do gerente", None), ("farol_calculado", "Farol pelo número", None),
        ("melancia", "Melancia", None), ("estouro_previsto", "Estouro previsto", BRL),
    ], "Projetos em andamento: o farol do gerente ao lado do farol pelo número", (0, 20, 12, 8)),
]

pessoas = [
    texto("titulo_pessoas", ["## Tenho gente parada enquanto outro projeto pede gente?\n", "\n",
                             "Timesheet das últimas 12 semanas e as causas de bloqueio dos últimos 90 dias."], 0),
    widget("top_ociosos", "ds_top_ociosos",
           [("pessoa", "`pessoa`"), ("custo_ocioso", "`custo_ocioso`")],
           {"version": 3, "widgetType": "bar",
            "encodings": {
                "x": {"fieldName": "custo_ocioso", "scale": {"type": "quantitative"},
                      "displayName": "Custo da hora parada", "format": BRL},
                "y": {"fieldName": "pessoa", "scale": {"type": "categorical"},
                      "displayName": "Pessoa"}},
            "frame": {"showTitle": True, "title": "Top 15 pessoas por custo da hora parada"}},
           (0, 2, 6, 7), disaggregated=True),
    widget("causas_por_projeto", "ds_causas",
           [("projeto_id", "`projeto_id`"), ("causa_bloqueio", "`causa_bloqueio`"), ("sum(status)", "SUM(`status`)")],
           {"version": 3, "widgetType": "bar",
            "encodings": {
                "x": {"fieldName": "projeto_id", "scale": {"type": "categorical"}, "displayName": "Projeto"},
                "y": {"fieldName": "sum(status)", "scale": {"type": "quantitative"}, "displayName": "Status com bloqueio"},
                "color": {"fieldName": "causa_bloqueio", "scale": {"type": "categorical"}, "displayName": "Causa"}},
            "frame": {"showTitle": True, "title": "Causas de bloqueio por projeto (últimos 90 dias)"}},
           (6, 2, 6, 7)),
    tabela("tabela_utilizacao", "ds_utilizacao", [
        ("nome", "Pessoa", None), ("papel", "Papel", None), ("senioridade", "Senioridade", None),
        ("projeto_id", "Projeto", None), ("horas_disponiveis", "Horas disponíveis", None),
        ("horas_apontadas", "Horas apontadas", None), ("utilizacao", "Utilização", PCT),
        ("custo_ocioso", "Custo da hora parada", BRL),
    ], "Utilização por pessoa e projeto (da mais parada à mais ocupada)", (0, 9, 12, 8)),
]

fornecedores = [
    texto("titulo_fornecedores", ["## O que vai dar errado no próximo mês?\n", "\n",
                                  "Entregas das consultorias: prometido × entregue, e o que está em atraso hoje (16/10/2026)."], 0),
    tabela("tabela_fornecedores", "ds_fornecedores", [
        ("fornecedor", "Fornecedor", None), ("grafias", "Grafias no cadastro", None),
        ("entregas", "Entregas", None), ("prazo_real_sobre_prometido", "Prazo real ÷ prometido", INDICE),
        ("pct_no_prazo", "% no prazo", PCT), ("em_atraso_hoje", "Em atraso hoje", None),
    ], "Fornecedores", (0, 2, 12, 6)),
    tabela("tabela_atrasadas", "ds_atrasadas", [
        ("entrega_id", "Entrega", None), ("projeto_id", "Projeto", None), ("fornecedor", "Fornecedor", None),
        ("item", "Item", None), ("valor", "Valor", BRL), ("data_prometida", "Prometida para", None),
        ("dias_em_atraso", "Dias em atraso", None),
    ], "Entregas em atraso hoje", (0, 8, 12, 6)),
]


def pagina(nome, titulo, layout):
    return {"name": nome, "displayName": titulo, "pageType": "PAGE_TYPE_CANVAS",
            "layoutVersion": "GRID_V1", "layout": layout}


dashboard = {
    "datasets": DATASETS,
    "pages": [pagina("portfolio", "Portfólio", portfolio),
              pagina("pessoas", "Pessoas", pessoas),
              pagina("fornecedores", "Fornecedores", fornecedores)],
    "uiSettings": {"theme": {
        "canvasBackgroundColor": {"light": "#F7F8FA", "dark": "#14141A"},
        "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1C1C24"},
        "widgetBorderColor": {"light": "#FFFFFF", "dark": "#1C1C24"},
        "fontColor": {"light": "#14141A", "dark": "#EDEFF5"},
        "selectionColor": {"light": "#0059DB", "dark": "#22C2F4"},
        "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF5F46", "#8B5CF6", "#14B8A6", "#F472B6", "#94A3B8"],
        "widgetHeaderAlignment": "LEFT",
    }},
}

if __name__ == "__main__":
    SAIDA.write_text(json.dumps(dashboard, ensure_ascii=False, indent=2), encoding="utf-8")
    widgets = sum(len(p["layout"]) for p in dashboard["pages"])
    print(f"{SAIDA.name}: {len(DATASETS)} datasets, {len(dashboard['pages'])} páginas, {widgets} widgets")
