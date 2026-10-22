# Projeto Farol · Torre de Controle da Vértice Tecnologia

Pipeline de dados e dashboard que responde às quatro perguntas do dono da Vértice
sobre o portfólio de 60 projetos (R$ 305 mi de carteira):

1. Quais projetos estão atrasados, e de quais clientes? (SPI, CPI, situação)
2. Quanto esse atraso vai custar? (EAC, estouro previsto, margem)
3. Há gente parada enquanto outro projeto pede gente? (utilização do timesheet)
4. O que vai dar errado no próximo mês? (entregas de fornecedor e bloqueios, com IA)

O problema de origem: cada gerente acompanha o projeto em uma ferramenta diferente
(20 planilhas Excel, 25 listas no ClickUp e 15 arquivos do MS Project), e ninguém
consegue dizer quais projetos estão atrasados.

**Dashboard publicado:** "Projeto Farol · Portfólio" (Databricks AI/BI).
Ver `resources/dashboard.dashboard.yml`.

---

## Arquitetura

```
job vertice_farol · toda segunda, 6h (America/Sao_Paulo)

ingestao_feriados ──┐
                    ├── conferencia_bronze ── medalhao (pipeline) ──┬── testes_de_qualidade
ingestao_data_lake ─┘       sql_task            silver → gold       └── status_com_ia
                                                                        (IA)

dashboard_portfolio  →  lê a camada gold
```

| Camada | Schema | Conteúdo |
|---|---|---|
| Bronze | `projetoprisma.bronze` | 9 tabelas carregadas da fonte, com a sujeira original, mais `feriados` |
| Silver | `projetoprisma.silver` | Dados limpos e integrados: projetos, tarefas (as 3 ferramentas num modelo só), status, custos, pessoas, fornecedores |
| Gold | `projetoprisma.gold` | Métricas prontas para consumo: histórico semanal, situação atual por projeto, utilização de pessoas, status estruturado pela IA |

A bronze é a única entrada da silver. Nunca é alterada à mão.

---

## Etapas do projeto

### 1. Bundle do Databricks
Estrutura como Declarative Automation Bundle (`databricks.yml`), com targets `dev`
(agendamento pausado) e `prod`. Os recursos ficam em `resources/`.

### 2. Ingestão (bronze)
- **`src/ingestao/Ingestao_api.ipynb`**: grava `bronze.feriados` a partir da BrasilAPI.
- **`src/ingestao/Ingestao_boto3.ipynb`**: baixa os arquivos do Supabase Storage pelo
  protocolo S3 (boto3), grava no volume `bronze.raw` e recria as 9 tabelas com `read_files`.

As chaves de acesso ficam no secret scope `supabase` e são lidas com `dbutils.secrets.get`.
Nenhuma credencial está no repositório.

### 3. Conferência da bronze
`src/conferencia/00-conferencia-bronze.sql` confere a contagem de linhas de cada tabela
contra o valor esperado. Se algo não bater, o job para antes da silver.

### 4. Silver: limpeza e integração
Pipeline declarativo Lakeflow (SQL, serverless) em `src/silver/`. Principais tratamentos:

- datas em dois formatos, percentuais escritos de formas diferentes, horas com sufixo `h`;
- datas do Excel como texto ou número de série, e datas do ClickUp em milissegundos;
- campos customizados do ClickUp e fases do MS Project, que não vinham na tarefa;
- status com grafias diferentes, normalizados para três valores;
- vírgula decimal em valores de custo (sem isso, R$ 5,4 mi sumiriam em silêncio);
- estornos mantidos como valor negativo e sinalizados;
- fornecedor com quatro grafias unificadas;
- colaborador cadastrado duas vezes, com um único registro;
- status vazios mantidos e sinalizados, não descartados.

Regra de conferência: o custo total da silver precisa bater com o da bronze.

### 5. Gold: métricas
Em `src/gold/`:

- **`fato_projeto_semana`**: avanço semana a semana, a partir do status de cada sexta-feira.
- **`projeto_situacao_atual`**: fotografia de hoje de cada projeto, com SPI, CPI, EAC,
  estouro previsto, margem projetada e farol calculado.
- **`utilizacao_pessoa_semana`**: uso de cada pessoa por semana (horas apontadas ÷ disponíveis).

Regras de corte: SPI ou CPI abaixo de 0,9 = atenção; abaixo de 0,8 = crítico.
O "hoje" do dataset é fixo em 16/10/2026, para que os números sejam reproduzíveis.

### 6. Testes de qualidade
`src/testes/testes.sql` valida a silver e a gold (totais, integridade e regras de negócio).
Roda como tarefa do job depois do pipeline.

### 7. IA sobre os status com bloqueio
`src/ia/status_estruturado.sql` usa `ai_classify` e `ai_extract` (funções de IA do
Databricks) nos status com bloqueio dos últimos 90 dias. Para cada texto, extrai a
causa, quem destrava e os dias de impacto declarados, com JSON schema tipado.

### 8. Job de orquestração
`resources/vertice.job.yml` (`vertice_farol`) encadeia as etapas acima. As duas
ingestões rodam em paralelo; `max_concurrent_runs: 1` impede execuções simultâneas,
que apagariam a bronze uma da outra.

### 9. Dashboard
- `scripts/gerar_dashboard.py` gera `resources/dashboard-portfolio.lvdash.json`.
- `resources/dashboard.dashboard.yml` publica o dashboard como recurso do bundle,
  lendo a camada gold.

---

## Como executar

Pré-requisitos: Databricks CLI, `uv` e um perfil de autenticação configurado.

```bash
# Instalar dependências de desenvolvimento
uv sync --dev

# Implantar no ambiente de desenvolvimento
databricks bundle deploy --target dev --profile <perfil>

# Rodar o job completo
databricks bundle run vertice_farol --profile <perfil>

# Testes locais
uv run pytest

# Regerar o JSON do dashboard
python scripts/gerar_dashboard.py
```

Sempre passe `--profile` explicitamente nos comandos `databricks`.

---

## Estrutura do repositório

```
databricks.yml             bundle, variáveis e targets
resources/                 job, pipeline e dashboard (YAML + JSON gerado)
src/ingestao/              notebooks de ingestão (bronze)
src/conferencia/           conferência da bronze
src/silver/                limpeza e integração
src/gold/                  métricas
src/ia/                    status estruturado com IA
src/testes/                testes de qualidade
scripts/                   geração do dashboard e execução de SQL
llm/                       prompts usados na construção, passo a passo
tests/                     testes locais (pytest + Databricks Connect)
```

---

## Notas

- Fonte dos dados: dataset sintético, gerado com seed 42. O "hoje" do projeto é 16/10/2026.
- Ambiente de referência: Databricks Free Edition, com Serverless Starter Warehouse.
- O agendamento de segunda vem pausado no target `dev`; ative-o apenas em `prod`.
