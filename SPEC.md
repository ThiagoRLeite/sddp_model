# Model v8 — Comparação SDDP vs Políticas Fixas

**Data:** 2026-05-19
**Autor:** Lucas (IC USP — Agendamento Rodoviário Porto de Santos)
**Arquivo principal:** `model_v8.jl`
**Pasta:** `Model SDDP - 19-05-26/`

---

## 1. Contexto

O projeto de IC modela o processamento diário de caminhões no Ecopátio do Porto de Santos via SDDP (Stochastic Dual Dynamic Programming) em Julia/JuMP. O modelo v7 atual (`03-03-2026 - model_v1/model_v7_04_05_2026.jl`) roda 30 dias, ajusta uma distribuição (Normal / LogNormal / Gamma / Weibull) à série diária do mês escolhido via AIC + KS, discretiza em 100 cenários e simula a política SDDP com 500 réplicas.

O professor pediu para o v8:

1. Comparar a política "inteligente" do SDDP com **3 políticas fixas** próximas (não muito divergentes) do resultado SDDP.
2. Apresentar para cada política: **uma réplica representativa** (tabela 30 dias) + **média das 1000 simulações**.
3. Subir N_SIM de 500 → **1000**.
4. Rodar para **2 meses** de maior processamento — definidos como **março** (maior média, 2471/dia) e **julho** (maior desvio, sd=742).
5. Verificar a distribuição ajustada de cada mês.
6. Trazer indicadores mais ricos do que apenas custo médio.

## 2. Objetivo

Entregar o `model_v8.jl` que rode os 2 meses, treine o SDDP, simule 4 políticas (SDDP + 3 fixas) com 1000 réplicas cada, calcule indicadores comparativos e produza tabelas, PNGs e CSVs organizados na pasta `Model SDDP - 19-05-26/outputs/`.

## 3. Escopo

### In-scope

- Análise de 2 meses (mar, jul) — fit AIC+KS + PNGs do fit
- Treinamento SDDP idêntico ao v7 (mesmas variáveis, restrições e custos)
- Simulação de 4 políticas × 1000 réplicas × 2 meses
- 7 indicadores comparativos (lista na seção 7)
- 3 tabelas no terminal (sumário, dia-a-dia, réplica representativa)
- 3 PNGs comparativos por mês (boxplot custo, ECDF custo, barras indicadores)
- 3 CSVs por mês (resultados réplica-a-réplica, sumário, tabela representativa)

### Out-of-scope

- Reformulação do modelo SDDP (variáveis, restrições, custos ficam idênticos ao v7)
- Adição de admissão como decisão controlável separada (admitidos.out = 3000 constante na política fixa)
- Outros meses além de mar/jul (jul é o segundo escolhido; dezembro descartado)
- CVaR como indicador (não foi selecionado pelo usuário)
- Análise de sensibilidade a custos (C_SPILLOVER, C_FILA, etc.)
- Otimização do hiperparâmetro `iteration_limit` do SDDP (mantém 200, ajusta se bound não convergir)

## 4. Decisões de design

| # | Decisão | Justificativa |
|---|---------|---------------|
| D1 | Política fixa = "processar X constante (clip por w_proc e fila.in + admitidos.in)" | Mantém compatibilidade com restrições do v7 (`processados <= w_proc`, `processados <= fila.in + admitidos.in`) |
| D2 | 3 níveis fixos = média_mês × {0.9, 1.0, 1.1} | Fácil de justificar para o professor, centrado na média observada do mês, e garante "próximo do SDDP" sem depender de rodar o SDDP primeiro |
| D3 | Meses = março + julho | Maior média (mar) + maior desvio (jul) cobrem dois regimes diferentes |
| D4 | N_SIM = 1000 | Solicitado pelo usuário; ~2× o atual (500) |
| D5 | Indicadores = quantis custo + spillover prob/cond + fila pico + service level + métricas v7 | Selecionados pelo usuário via multi-choice |
| D6 | Output = tabelas terminal + PNGs comparativos + CSVs | Selecionado pelo usuário; suporta inclusão no relatório do IC |
| D7 | Admissão na política fixa = ADMITIDOS_INICIAL (3000) constante | "Demanda cheia" simétrica entre políticas; isola a comparação na decisão de processamento |
| D8 | Arquitetura = 1 arquivo `model_v8.jl` modularizado em funções | Mantém ergonomia do v7 sem virar monolítico |
| D9 | Modelo SDDP = idêntico ao v7 | Não há mudança estrutural pedida; só muda o entorno |
| D10 | CRN (Common Random Numbers) na política fixa | Mesma seed por réplica nas 3 fixas para comparação justa. SDDP usa amostragem própria (não controlamos a seed interna; aceitamos variância maior na comparação SDDP vs fixa e anotamos no relatório) |

## 5. Arquitetura

### 5.1 Estrutura de pastas

```
Projeto - IC - Rodoviário/
└── Model SDDP - 19-05-26/
    ├── SPEC.md                          ← este documento
    ├── model_v8.jl                       ← arquivo principal
    ├── PLAN.md                          ← plano de implementação (próximo passo)
    └── outputs/
        ├── v8_mar_fit_histograma.png
        ├── v8_mar_fit_ecdf.png
        ├── v8_mar_custo_boxplot.png
        ├── v8_mar_custo_ecdf.png
        ├── v8_mar_indicadores_bar.png
        ├── v8_mar_resultados.csv         ← 4000 linhas (4 pol × 1000 rep)
        ├── v8_mar_sumario.csv            ← 4 linhas (1 por política)
        ├── v8_mar_replica_repr.csv       ← 30 linhas × 4 políticas em colunas
        └── (mesmo conjunto para jul)
```

CSV de input: `../03-03-2026 - model_v1/Processamento Santos/processados_2025.csv` (path relativo).

### 5.2 Funções do `model_v8.jl`

> **Nota:** as assinaturas abaixo são a intenção de design. O **PLAN.md** é a fonte de verdade para as assinaturas exatas usadas na implementação (pode haver ajustes pontuais para evitar argumentos não usados).

```julia
# Constantes (mesmas do v7 + N_SIM=1000, MESES=["mar","jul"])

# Bloco 1 — Análise de mês
ler_mes(mes::String) :: Vector{Float64}
fit_distribuicoes(data::Vector{Float64}) :: (escolhida, ranking)
plot_fit(mes, data, escolhida, ranking)

# Bloco 2 — Discretização
discretizar_por_bins(dist; n_cenarios=100, q_low=0.01, q_high=0.99) :: (omega, probs)

# Bloco 3 — Política SDDP
treinar_sddp(omega, probs) :: SDDP.PolicyGraph
simular_sddp(model, N) :: Vector{Vector{Dict}}

# Bloco 4 — Política fixa
simular_fixa(X::Float64, omega, probs, N; seed=42) :: Vector{Vector{NamedTuple}}

# Bloco 5 — Indicadores
calcular_indicadores(sims, label::String) :: NamedTuple

# Bloco 6 — Outputs
gerar_tabelas_terminal(mes, indicadores_4pol, sims_4pol)
gerar_pngs(mes, sims_4pol)
gerar_csvs(mes, sims_4pol, indicadores_4pol)

# Orquestração
analisar_mes(mes::String)
main()
```

### 5.3 Fluxo de execução

```
PARA cada mes em ["mar", "jul"]:
  1. data = ler_mes(mes)                           # 30 dias do CSV
  2. (dist_escolhida, ranking) = fit_distribuicoes(data)
  3. plot_fit(mes, data, dist_escolhida, ranking)   # gera 2 PNGs
  4. (omega, probs) = discretizar_por_bins(dist_escolhida)
  5. model = treinar_sddp(omega, probs)             # 200 iterações
  6. sims_sddp = simular_sddp(model, 1000)
  7. media_mes = mean(data)
  8. X1, X2, X3 = media_mes * 0.9, media_mes, media_mes * 1.1
  9. sims_p1 = simular_fixa(X1, omega, probs, 1000; seed=42)
 10. sims_p2 = simular_fixa(X2, omega, probs, 1000; seed=42)
 11. sims_p3 = simular_fixa(X3, omega, probs, 1000; seed=42)
 12. PARA cada (sims, label) em [(sims_sddp,"SDDP"), (sims_p1,"P_X1"), ...]:
       indicadores[label] = calcular_indicadores(sims, label)
 13. gerar_tabelas_terminal(mes, indicadores, sims_4pol)
 14. gerar_pngs(mes, sims_4pol)
 15. gerar_csvs(mes, sims_4pol, indicadores)
```

**Tempo estimado:** 2 meses × (treino SDDP ~30-60s + 4 simulações ~10s + geração outputs ~5s) ≈ 3-5 min total em CPU.

## 6. Política fixa — definição operacional

Para cada réplica `r` de 1 a 1000:

```julia
Random.seed!(seed_base + r)  # CRN: mesma sequência para P_X1, P_X2, P_X3

fila_in = FILA_INICIAL                # 1200
adm_in  = ADMITIDOS_INICIAL           # 3000

for t in 1:NUM_DIAS                    # 30 dias
    idx       = sample(1:length(omega), Weights(probs))
    w_proc_t  = omega[idx]

    processados_t = min(X, w_proc_t, fila_in + adm_in)
    spillover_t   = max(0, fila_in + adm_in - CAP_ECOPATIO - processados_t)
    ocioso_t      = max(0, w_proc_t - processados_t)
    fila_out      = fila_in + adm_in - processados_t
    adm_out       = ADMITIDOS_INICIAL  # regra fixa (D7)

    custo_t = C_FILA*(fila_in + fila_out)/2 +
              C_SPILLOVER*spillover_t +
              C_OCIOSO_TOTAL*ocioso_t

    # armazena (t, fila_in, adm_in, w_proc_t, processados_t, fila_out, spillover_t, ocioso_t, adm_out, custo_t)

    fila_in, adm_in = fila_out, adm_out
end
```

**Saída:** estrutura compatível com `sims_sddp` (lista de réplicas, cada réplica = lista de 30 estágios) para que `calcular_indicadores`, `gerar_pngs` e `gerar_csvs` tratem ambas igualmente.

> **Nota sobre assimetria SDDP vs fixa:** no v7, `admitidos` é estado SDDP cujo `admitidos.out` é endógeno (o solver decide quanto admitir, limitado por MAX_VAGAS=4000). Na política fixa, `adm_out` é pinado em 3000. Portanto a comparação é "SDDP decide admissão + processamento" vs "fixa só decide processamento (admissão fixada)". Isolar a diferença em processamento é justamente o objetivo do estudo, mas o relatório do IC deve mencionar essa assimetria explicitamente.

## 7. Indicadores

Por política × mês:

| # | Indicador | Fórmula |
|---|-----------|---------|
| I1 | Custo médio + IC 95% | `mean(custos)`, `± 1.96 * sd(custos) / sqrt(N)` |
| I2 | Custo P5 / P50 / P95 | `quantile(custos, [0.05, 0.5, 0.95])` |
| I3 | Prob(spillover > 0 em algum dia) | `mean(any(s.spillover .> 0) for s in sims)` |
| I4 | Spillover total condicional | `mean(sum(s.spillover) for s in sims if sum(s.spillover) > 0)` |
| I5 | Fila pico médio | `mean(maximum(s.fila_out) for s in sims)` |
| I6 | Service level | `mean(mean(s.fila_out .< 2000) for s in sims)` |
| I7 | Métricas v7 (médias diárias) | `mean(s.entram[t])`, `mean(s.proc[t])`, `mean(s.ocioso[t])`, `mean(s.spill[t])` para cada `t` — exatamente as 4 médias diárias que o v7 imprime na tabela "OPERACAO DIA A DIA" |

**Threshold do service level (2000):** justificativa = 50% da capacidade de vagas (MAX_VAGAS=4000), valor operacionalmente confortável. **Ajustável** — se o professor pedir, troca para outro corte.

## 8. Outputs detalhados

### 8.1 Terminal (3 tabelas por mês)

**Tabela A — Sumário comparativo:**
```
Mês: MAR
Pol     | CustoMéd  | IC95     | P5      | P50     | P95     | Spill%>0 | SpillCondMéd | FilaPico | ServLvl
SDDP    | ...
P_X1    | ...
P_X2    | ...
P_X3    | ...
```

**Tabela B — Operação dia-a-dia (4 sub-tabelas, uma por política):**
```
[SDDP] (mar, média 1000 sims)
Dia | FilaIni | AdmitIn | Demanda | Entram | Proc | FilaFim | Spill | AdmitOut
...
```

**Tabela C — Réplica representativa (4 sub-tabelas, réplica de custo mais próximo da média de cada política — `argmin(abs.(custos .- mean(custos)))`, mesma regra do v7):**
```
[SDDP] (mar, réplica idx=NNN, custo mais próximo da média R$ X.X)
Dia | FilaIni | AdmitIn | Demanda | ProcCap | Entram | Proc | FilaFim | Spill | AdmitOut
...
```

### 8.2 PNGs (3 por mês + 2 do fit)

| Arquivo | Conteúdo |
|---------|----------|
| `v8_<mes>_fit_histograma.png` | Histograma 30 dias + 4 PDFs ajustadas (igual v7) |
| `v8_<mes>_fit_ecdf.png` | ECDF dados + 4 CDFs (igual v7) |
| `v8_<mes>_custo_boxplot.png` | Boxplot do custo total das 1000 sims, 4 caixas lado a lado |
| `v8_<mes>_custo_ecdf.png` | 4 ECDFs sobrepostas do custo total |
| `v8_<mes>_indicadores_bar.png` | Barras agrupadas: Spill%, FilaPico (normalizado), ServLvl |

### 8.3 CSVs (3 por mês)

**`v8_<mes>_resultados.csv`** — 1 linha por (política, réplica):
```
politica,replica,custo_total,spillover_total,ocioso_total,processados_total,fila_pico,service_level_repl
SDDP,1,...
SDDP,2,...
...
P_X3,1000,...
```

**`v8_<mes>_sumario.csv`** — 1 linha por política, todas as métricas I1-I7.

**`v8_<mes>_replica_repr.csv`** — 30 linhas, colunas multi-índice (uma seção por política):
```
dia,SDDP_FilaIni,SDDP_AdmIn,SDDP_Proc,SDDP_FilaFim,SDDP_Spill,P_X1_FilaIni,...,P_X3_Spill
```

## 9. Validação

- **V1 — Reprodutibilidade do v7:** rodar v8 com `mes="mar"` e comparar custo SDDP médio com o do v7 (ambos com mesma dist e omega). Diferença esperada: **≤ ±5% para março**, **≤ ±10% para julho** (julho tem maior desvio, então tolerância maior é razoável; variação vem de N_SIM=1000 vs 500 e seed).
- **V2 — Sanidade da política fixa:** se X1 << média_w_proc → spillover deve ser alto. Se X3 >> média_w_proc → ociosidade alta. Conferir no boxplot.
- **V3 — CRN funciona:** ao rodar duas vezes com mesma seed, as 3 políticas fixas devem produzir custos idênticos réplica a réplica.
- **V4 — Bound SDDP:** depois do treino, `SDDP.calculate_bound(model)` deve ser ≤ custo médio simulado (já que é minimização e o bound é inferior). Se violar, há bug ou bound não convergiu.

## 10. Riscos

| # | Risco | Mitigação |
|---|-------|-----------|
| R1 | Bound SDDP não converge em julho (alta variância) | Se gap > 5% após 200 iterações, aumentar para 400 |
| R2 | Tempo de execução > 10 min | Reduzir n_cenarios da discretização de 100 → 50 ou número de iterações SDDP |
| R3 | Memória explode com 4000 sims armazenadas | Cada sim ocupa ~5KB × 4000 = 20MB; aceitável. Se virar problema, salvar incrementalmente em CSV |
| R4 | CRN não fica perfeito entre SDDP e fixa (SDDP tem amostragem interna) | Documentar limitação no relatório; comparação SDDP vs fixa terá variância levemente maior, mas comparação entre as 3 fixas será limpa |

## 11. Critérios de aceite

1. ✅ `julia model_v8.jl` roda do início ao fim sem erro
2. ✅ Gera 5 PNGs e 3 CSVs para cada mês (10 PNGs + 6 CSVs total)
3. ✅ Imprime 3 tabelas no terminal para cada mês
4. ✅ Custo médio do SDDP em março fica dentro de ±5% do v7 (validação V1)
5. ✅ Tabela A mostra claramente qual política tem menor custo médio + qual tem maior risco (P95) + qual tem maior spillover
6. ✅ Tempo total ≤ 10 min em CPU
7. ✅ Código modular: funções nomeadas, cada uma com docstring de 1-2 linhas

## 12. Não-decisões (deixadas para o autor implementar com bom senso)

- Cores do boxplot e estilo dos plots (manter padrão do StatsPlots, igual v7)
- Largura exata das colunas das tabelas no terminal
- Casas decimais (manter padrão do v7: %.1f para valores grandes)
- Ordem das políticas nas tabelas (SDDP primeiro, depois P_X1/P_X2/P_X3 em ordem crescente)
- Se incluir `Pkg.add(...)` no topo (manter como no v7, com `StatsBase` adicionado para `sample`/`Weights`)
