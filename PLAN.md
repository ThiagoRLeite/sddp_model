# Model v8 — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar `model_v8.jl` que compara política SDDP com 3 políticas fixas em 2 meses (mar/jul), com 1000 simulações cada e indicadores comparativos, gerando tabelas/PNGs/CSVs organizados em `Model SDDP - 19-05-26/outputs/`.

**Architecture:** Um arquivo único Julia (`model_v8.jl`) modularizado em funções puras. O modelo SDDP é reaproveitado idêntico ao v7. Políticas fixas são simuladas via Monte Carlo manual (sem SDDP), usando Common Random Numbers (CRN) para comparação justa entre as 3 fixas. Loop principal itera ["mar", "jul"] e gera outputs por mês.

**Tech Stack:** Julia, SDDP.jl, HiGHS, JuMP, Distributions, HypothesisTests, StatsPlots, StatsBase (novo dep para `sample`/`Weights`), CSV, DataFrames.

**Spec de referência:** [SPEC.md](SPEC.md)

**Validação contínua:** A cada task, o `model_v8.jl` deve continuar rodável (`julia "model_v8.jl"`) e produzir o output esperado descrito no step de smoke test. Commits a cada task concluída.

---

## File Structure

**Arquivo único:**

- **Create:** `Model SDDP - 19-05-26/model_v8.jl` — ~700 linhas, todas as funções e o `main()`

**Outputs gerados (não criados manualmente, gerados pelo código):**

- `Model SDDP - 19-05-26/outputs/v8_<mes>_*.png` (5 PNGs × 2 meses = 10)
- `Model SDDP - 19-05-26/outputs/v8_<mes>_*.csv` (3 CSVs × 2 meses = 6)

**Dependências externas (read-only):**

- `03-03-2026 - model_v1/Processamento Santos/processados_2025.csv` (input)
- `03-03-2026 - model_v1/model_v7_04_05_2026.jl` (referência, intocado)

---

## Task 1 — Setup inicial do `model_v8.jl`

**Files:**
- Create: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 1.1 — Criar arquivo com cabeçalho e Pkg.add**

Conteúdo inicial:

```julia
import Pkg
Pkg.add([
    "CSV",
    "DataFrames",
    "Distributions",
    "HypothesisTests",
    "SDDP",
    "HiGHS",
    "StatsPlots",
    "StatsBase",
])

using CSV, DataFrames, Statistics, Printf, Random
using Distributions, HypothesisTests
using SDDP, HiGHS, JuMP
using StatsPlots
using StatsBase: sample, Weights

# ============================================================
# MODELO v8 — COMPARACAO SDDP vs POLITICAS FIXAS
# ============================================================
# - 2 meses (mar + jul) × 4 politicas × 1000 replicas
# - Outputs em Model SDDP - 19-05-26/outputs/
# - Spec: SPEC.md
# ============================================================
```

- [ ] **Step 1.2 — Adicionar constantes (espelho do v7)**

```julia
# Parametros do modelo (identicos ao v7)
const NUM_DIAS = 30
const CAP_ECOPATIO = 1200
const MAX_VAGAS = 4000

const C_SPILLOVER = 16211.0
const C_OCIOSO = 1753.0
const C_FILA = 2790.0
const R_RECEITA_PROC = 42000.0
const C_OCIOSO_TOTAL = C_OCIOSO + R_RECEITA_PROC

const FILA_INICIAL = 1200
const ADMITIDOS_INICIAL = 3000

# Parametros do v8
const N_SIM = 1000
const MESES = ["mar", "jul"]
const SDDP_ITERATIONS = 200
const N_CENARIOS_DISC = 100
const SERVICE_LEVEL_FILA_THRESHOLD = 2000  # corte para service level
const SEED_BASE = 42

# Paths
const ROOT = @__DIR__
const CSV_PATH = joinpath(ROOT, "..", "03-03-2026 - model_v1", "Processamento Santos", "processados_2025.csv")
const OUTPUT_DIR = joinpath(ROOT, "outputs")
isdir(OUTPUT_DIR) || mkpath(OUTPUT_DIR)

@printf("-- model v8 iniciando --\n")
@printf("  CSV_PATH = %s\n", CSV_PATH)
@printf("  OUTPUT_DIR = %s\n", OUTPUT_DIR)
@printf("  C_OCIOSO_TOTAL = R\$ %.1f\n", C_OCIOSO_TOTAL)
@printf("  N_SIM = %d | MESES = %s\n\n", N_SIM, MESES)
```

- [ ] **Step 1.3 — Adicionar `main()` placeholder e chamá-lo**

```julia
function main()
    println("[main] placeholder — Task 1 OK")
end

main()
```

- [ ] **Step 1.4 — Smoke test: rodar o arquivo**

```
julia --project=. "Model SDDP - 19-05-26/model_v8.jl"
```

**Esperado:** instala pacotes (primeira vez), imprime os 4 prints de header + "[main] placeholder — Task 1 OK", **sem erros**. Pacotes baixados podem demorar alguns minutos na primeira execução.

- [ ] **Step 1.5 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl" "Model SDDP - 19-05-26/SPEC.md" "Model SDDP - 19-05-26/PLAN.md"
git commit -m "feat(v8): setup inicial model_v8.jl com constantes e pacotes"
```

---

## Task 2 — Função `ler_mes(mes)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl` (adicionar função antes do `main()`)

- [ ] **Step 2.1 — Implementar `ler_mes`**

Espelha lógica das linhas 62-94 do v7 (normalização de cabeçalho + extração).

```julia
"""
    ler_mes(mes::String) -> Vector{Float64}

Le os primeiros NUM_DIAS=30 valores da coluna do mes (case-insensitive)
no CSV de processados. Retorna vetor Float64.
"""
function ler_mes(mes::String)
    if !isfile(CSV_PATH)
        error("CSV nao encontrado em: $(CSV_PATH)")
    end
    df = CSV.read(CSV_PATH, DataFrame)
    col_names = names(df)
    col_idx = findfirst(n -> lowercase(strip(String(n))) == lowercase(mes), col_names)
    if isnothing(col_idx)
        error("Coluna do mes '$(mes)' nao encontrada. Cabecalhos: $(String.(col_names))")
    end
    mes_sym = col_names[col_idx]
    raw = collect(skipmissing(df[!, mes_sym]))
    data = Float64.(raw)
    if length(data) < NUM_DIAS
        error("Mes '$(mes)' tem menos de $(NUM_DIAS) observacoes validas.")
    end
    return data[1:NUM_DIAS]
end
```

- [ ] **Step 2.2 — Atualizar `main()` para smoke**

```julia
function main()
    for mes in MESES
        data = ler_mes(mes)
        @printf("[%s] %d dias | min=%.0f mean=%.1f max=%.0f sd=%.2f\n",
            uppercase(mes), length(data), minimum(data), mean(data), maximum(data), std(data))
    end
end

main()
```

- [ ] **Step 2.3 — Rodar e validar**

```
julia --project=. "Model SDDP - 19-05-26/model_v8.jl"
```

**Esperado:** duas linhas — uma para MAR (mean ≈ 2471) e uma para JUL (mean ≈ ~1500). Sem erros.

- [ ] **Step 2.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): ler_mes le 30 dias do CSV por nome de coluna"
```

---

## Task 3 — Função `fit_distribuicoes(data)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 3.1 — Implementar `fit_candidates` + `model_score` + `fit_distribuicoes`**

Espelha lógica das linhas 106-148 do v7. Empacotada em uma função pura que retorna `(escolhida, ranking)`.

```julia
"""
    fit_distribuicoes(data::Vector{Float64})
       -> (escolhida::NamedTuple, ranking::Vector{NamedTuple})

Ajusta Normal, LogNormal, Gamma, Weibull. Ranqueia por AIC.
Escolhe: menor AIC entre os que passam no KS (p >= 0.05); se nenhum
passar, menor AIC global.
"""
function fit_distribuicoes(data::Vector{Float64})
    candidates = Dict{String,Distribution}(
        "Normal"    => fit_mle(Normal,    data),
        "LogNormal" => fit_mle(LogNormal, data),
        "Gamma"     => fit_mle(Gamma,     data),
        "Weibull"   => fit_mle(Weibull,   data),
    )
    function _score(name, dist)
        ll = sum(logpdf.(Ref(dist), data))
        aic = 2 * 2 - 2 * ll
        ks_p = pvalue(ApproximateOneSampleKSTest(data, dist))
        return (name = name, dist = dist, loglik = ll, aic = aic, ks_p = ks_p)
    end
    results = [_score(n, d) for (n, d) in candidates]
    sort!(results, by = r -> r.aic)
    valid = filter(r -> r.ks_p >= 0.05, results)
    escolhida = isempty(valid) ? results[1] : sort(valid, by = r -> r.aic)[1]
    return (escolhida = escolhida, ranking = results)
end
```

- [ ] **Step 3.2 — Atualizar `main()` para smoke**

```julia
function main()
    for mes in MESES
        data = ler_mes(mes)
        fit = fit_distribuicoes(data)
        @printf("[%s] escolhida=%s | AIC=%.2f | KS_p=%.4f | dist=%s\n",
            uppercase(mes), fit.escolhida.name, fit.escolhida.aic, fit.escolhida.ks_p, fit.escolhida.dist)
    end
end

main()
```

- [ ] **Step 3.3 — Rodar e validar**

**Esperado:** uma linha por mês com nome da distribuição escolhida + AIC + KS p-value. Em março, esperar Normal ou LogNormal com KS_p > 0.05.

- [ ] **Step 3.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): fit_distribuicoes (Normal/LogN/Gamma/Weibull) por AIC+KS"
```

---

## Task 4 — Função `plot_fit(mes, data, ranking)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 4.1 — Implementar `plot_fit`**

Espelha lógica das linhas 152-193 do v7, mas salva em `OUTPUT_DIR`.

```julia
"""
    plot_fit(mes::String, data::Vector{Float64}, ranking::Vector)

Salva 2 PNGs em OUTPUT_DIR:
- v8_<mes>_fit_histograma.png (histograma + 4 PDFs)
- v8_<mes>_fit_ecdf.png       (ECDF + 4 CDFs)
"""
function plot_fit(mes::String, data::Vector{Float64}, ranking)
    default(legend = :topright, size = (1000, 600))
    out_hist = joinpath(OUTPUT_DIR, "v8_$(mes)_fit_histograma.png")
    out_ecdf = joinpath(OUTPUT_DIR, "v8_$(mes)_fit_ecdf.png")

    p1 = histogram(data;
        bins = 10, normalize = :pdf, alpha = 0.35,
        label = "Dados $(uppercase(mes)) (30d)",
        title = "$(uppercase(mes)) — Histograma e PDFs ajustadas",
        xlabel = "Processados/dia", ylabel = "Densidade")
    xgrid = range(max(1.0, minimum(data) * 0.8), maximum(data) * 1.2, length = 400)
    for r in ranking
        plot!(p1, xgrid, pdf.(Ref(r.dist), xgrid), lw = 2, label = r.name)
    end
    savefig(p1, out_hist)

    p2 = plot(title = "$(uppercase(mes)) — ECDF vs CDFs",
              xlabel = "Processados/dia", ylabel = "Prob. acumulada")
    x_sorted = sort(data)
    y_ecdf = (1:length(x_sorted)) ./ length(x_sorted)
    scatter!(p2, x_sorted, y_ecdf, ms = 4, alpha = 0.8, label = "ECDF")
    for r in ranking
        plot!(p2, xgrid, cdf.(Ref(r.dist), xgrid), lw = 2, label = r.name)
    end
    savefig(p2, out_ecdf)

    @printf("  PNGs salvos: %s, %s\n", basename(out_hist), basename(out_ecdf))
end
```

- [ ] **Step 4.2 — Atualizar `main()` para smoke**

```julia
function main()
    for mes in MESES
        data = ler_mes(mes)
        fit = fit_distribuicoes(data)
        plot_fit(mes, data, fit.ranking)
    end
end
main()
```

- [ ] **Step 4.3 — Rodar e validar**

**Esperado:** 4 PNGs gerados em `Model SDDP - 19-05-26/outputs/` (`v8_mar_fit_histograma.png`, `v8_mar_fit_ecdf.png`, `v8_jul_*`). Verificar visualmente: histograma sobreposto com curvas das 4 distribuições.

- [ ] **Step 4.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): plot_fit gera histograma + ECDF por mes em outputs/"
```

---

## Task 5 — Função `discretizar_por_bins(dist)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 5.1 — Implementar `discretizar_por_bins`**

Espelha as linhas 213-236 do v7.

```julia
"""
    discretizar_por_bins(dist::Distribution; n_cenarios=100, q_low=0.01, q_high=0.99)
        -> (omega::Vector{Float64}, probs::Vector{Float64})

Particiona [quantil(q_low), quantil(q_high)] em n_cenarios bins de igual largura.
Para cada bin: ponto = quantil do CDF medio do bin (round, >=0); prob = CDF(b) - CDF(a).
Probabilidades normalizadas para somar 1.
"""
function discretizar_por_bins(dist::Distribution; n_cenarios::Int = N_CENARIOS_DISC,
                              q_low::Float64 = 0.01, q_high::Float64 = 0.99)
    edges = range(quantile(dist, q_low), quantile(dist, q_high), length = n_cenarios + 1)
    pontos = Float64[]
    probs  = Float64[]
    for i in 1:n_cenarios
        a, b = edges[i], edges[i+1]
        p = cdf(dist, b) - cdf(dist, a)
        qmid = (cdf(dist, a) + cdf(dist, b)) / 2
        push!(pontos, max(0.0, round(quantile(dist, qmid))))
        push!(probs,  p)
    end
    total = sum(probs)
    if total > 0
        probs ./= total
    end
    return pontos, probs
end
```

- [ ] **Step 5.2 — Atualizar `main()` para smoke**

```julia
function main()
    for mes in MESES
        data = ler_mes(mes)
        fit = fit_distribuicoes(data)
        omega, probs = discretizar_por_bins(fit.escolhida.dist)
        @printf("[%s] omega: n=%d, min=%.0f, max=%.0f, sum_probs=%.4f\n",
            uppercase(mes), length(omega), minimum(omega), maximum(omega), sum(probs))
    end
end
main()
```

- [ ] **Step 5.3 — Rodar e validar**

**Esperado:** `n=100, sum_probs ≈ 1.0000` para os dois meses.

- [ ] **Step 5.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): discretizar_por_bins (100 bins, q_low=0.01, q_high=0.99)"
```

---

## Task 6 — Função `treinar_sddp(omega, probs)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 6.1 — Implementar `treinar_sddp`**

Espelha definição do modelo (linhas 251-298 do v7). Apenas envolto em função para receber `omega/probs`.

```julia
"""
    treinar_sddp(omega::Vector{Float64}, probs::Vector{Float64}) -> SDDP.PolicyGraph

Constroi e treina (SDDP_ITERATIONS) o modelo idêntico ao v7. Retorna o grafo.
"""
function treinar_sddp(omega::Vector{Float64}, probs::Vector{Float64})
    model = SDDP.LinearPolicyGraph(
        stages = NUM_DIAS,
        sense = :Min,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do sp, t
        @variable(sp, fila >= 0, SDDP.State, initial_value = FILA_INICIAL)
        @variable(sp, 0 <= admitidos <= MAX_VAGAS, SDDP.State, initial_value = ADMITIDOS_INICIAL)
        @variable(sp, processados >= 0)
        @variable(sp, spillover >= 0)
        @variable(sp, ocioso >= 0)
        @variable(sp, w_proc >= 0)
        JuMP.fix(w_proc, omega[1]; force = true)

        @constraint(sp, processados <= w_proc)
        @constraint(sp, processados <= fila.in + admitidos.in)
        @constraint(sp, fila.out == fila.in + admitidos.in - processados)
        @constraint(sp, spillover >= fila.in + admitidos.in - CAP_ECOPATIO - processados)
        @constraint(sp, ocioso >= w_proc - processados)

        SDDP.parameterize(sp, omega, probs) do p
            JuMP.fix(w_proc, p; force = true)
            @stageobjective(sp,
                C_FILA * (fila.in + fila.out) / 2 +
                C_SPILLOVER * spillover +
                C_OCIOSO_TOTAL * ocioso
            )
        end
    end
    SDDP.train(model; iteration_limit = SDDP_ITERATIONS, print_level = 1, log_frequency = 50)
    return model
end
```

- [ ] **Step 6.2 — Atualizar `main()` para smoke (somente março, para economia de tempo)**

```julia
function main()
    mes = "mar"
    data = ler_mes(mes)
    fit = fit_distribuicoes(data)
    omega, probs = discretizar_por_bins(fit.escolhida.dist)
    model = treinar_sddp(omega, probs)
    bound = SDDP.calculate_bound(model)
    @printf("[%s] SDDP treinado | bound=%.1f\n", uppercase(mes), bound)
end
main()
```

- [ ] **Step 6.3 — Rodar e validar**

**Esperado:** logs do SDDP (~200 iterações, ~30-60s), e print final com `bound=` algum valor positivo (esperado ~1e7 ordem de grandeza, similar ao v7).

- [ ] **Step 6.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): treinar_sddp constroi modelo identico ao v7"
```

---

## Task 7 — Função `simular_sddp(model, N)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 7.1 — Implementar `simular_sddp`**

```julia
"""
    simular_sddp(model, N::Int) -> Vector{Vector{Dict}}

Wrapper em torno de SDDP.simulate. Rastreia fila, admitidos, processados,
spillover, ocioso, w_proc. Retorna a estrutura nativa do SDDP.
"""
function simular_sddp(model, N::Int)
    return SDDP.simulate(
        model,
        N,
        [:fila, :admitidos, :processados, :spillover, :ocioso, :w_proc],
    )
end
```

- [ ] **Step 7.2 — Atualizar `main()` para smoke (testar com N pequeno)**

```julia
function main()
    mes = "mar"
    data = ler_mes(mes)
    fit = fit_distribuicoes(data)
    omega, probs = discretizar_por_bins(fit.escolhida.dist)
    model = treinar_sddp(omega, probs)
    sims = simular_sddp(model, 50)  # smoke com 50, sera 1000 depois
    custos = [sum(s[:stage_objective] for s in sim) for sim in sims]
    @printf("[%s] sims=%d | custo medio=%.1f | custo std=%.1f\n",
        uppercase(mes), length(sims), mean(custos), std(custos))
end
main()
```

- [ ] **Step 7.3 — Rodar e validar**

**Esperado:** print com 50 simulações, custo médio comparável ao do v7 (mar ~5e7-1e8 dependendo da distribuição).

- [ ] **Step 7.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): simular_sddp envelopa SDDP.simulate"
```

---

## Task 8 — Função `simular_fixa(X, omega, probs, N; seed)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 8.1 — Implementar `simular_fixa`**

Monte Carlo manual com CRN (Random.seed!(SEED_BASE + r) em cada réplica). Estrutura de saída deve ser **compatível** com `simular_sddp` para facilitar indicadores comuns.

```julia
"""
    simular_fixa(X::Float64, omega::Vector{Float64}, probs::Vector{Float64}, N::Int;
                 seed_base::Int = SEED_BASE)
        -> Vector{Vector{Dict}}

Monte Carlo da politica fixa "processar X constante (clip por w_proc e fila+adm)".
Admitidos.out = ADMITIDOS_INICIAL constante (regra D7 do SPEC).
CRN: seed = seed_base + r para cada replica r.

Saida: lista de N replicas. Cada replica = lista de NUM_DIAS estagios.
Cada estagio = Dict com chaves compativeis com o SDDP:
  :fila => (in=..., out=...) ; :admitidos => (in=..., out=...) ;
  :processados, :spillover, :ocioso, :w_proc, :stage_objective.
"""
function simular_fixa(X::Float64, omega::Vector{Float64}, probs::Vector{Float64}, N::Int;
                      seed_base::Int = SEED_BASE)
    w_idx_range = 1:length(omega)
    w_weights = Weights(probs)

    sims = Vector{Vector{Dict{Symbol,Any}}}(undef, N)
    for r in 1:N
        Random.seed!(seed_base + r)
        fila_in_t = Float64(FILA_INICIAL)
        adm_in_t  = Float64(ADMITIDOS_INICIAL)
        sim_r = Vector{Dict{Symbol,Any}}(undef, NUM_DIAS)
        for t in 1:NUM_DIAS
            idx_w = sample(w_idx_range, w_weights)
            w_t = omega[idx_w]

            proc_t  = min(X, w_t, fila_in_t + adm_in_t)
            spill_t = max(0.0, fila_in_t + adm_in_t - CAP_ECOPATIO - proc_t)
            ocio_t  = max(0.0, w_t - proc_t)
            fila_out_t = fila_in_t + adm_in_t - proc_t
            adm_out_t  = Float64(ADMITIDOS_INICIAL)

            custo_t = C_FILA * (fila_in_t + fila_out_t) / 2 +
                      C_SPILLOVER * spill_t +
                      C_OCIOSO_TOTAL * ocio_t

            sim_r[t] = Dict{Symbol,Any}(
                :fila        => (in = fila_in_t, out = fila_out_t),
                :admitidos   => (in = adm_in_t,  out = adm_out_t),
                :processados => proc_t,
                :spillover   => spill_t,
                :ocioso      => ocio_t,
                :w_proc      => w_t,
                :stage_objective => custo_t,
            )

            fila_in_t = fila_out_t
            adm_in_t  = adm_out_t
        end
        sims[r] = sim_r
    end
    return sims
end
```

- [ ] **Step 8.2 — Atualizar `main()` para smoke (compara 3 fixas em mar)**

```julia
function main()
    mes = "mar"
    data = ler_mes(mes)
    fit = fit_distribuicoes(data)
    omega, probs = discretizar_por_bins(fit.escolhida.dist)
    media = mean(data)
    @printf("[%s] media=%.1f | X1=%.0f X2=%.0f X3=%.0f\n",
        uppercase(mes), media, media*0.9, media, media*1.1)
    for (label, X) in [("P_X1", media*0.9), ("P_X2", media), ("P_X3", media*1.1)]
        sims = simular_fixa(X, omega, probs, 100)
        custos = [sum(s[:stage_objective] for s in sim) for sim in sims]
        @printf("  [%s X=%.0f] sims=%d | custo medio=%.1f\n", label, X, length(sims), mean(custos))
    end
end
main()
```

- [ ] **Step 8.3 — Rodar e validar**

**Esperado:** 3 linhas (P_X1, P_X2, P_X3), custos crescendo conforme análise: X1 baixo → mais spillover/fila; X3 alto → mais ociosidade. Ordem de grandeza ≈ custo SDDP. **Sanidade:** rodar 2 vezes e verificar que custos são IDÊNTICOS (CRN funcionando).

- [ ] **Step 8.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): simular_fixa (Monte Carlo) com CRN, output compativel SDDP"
```

---

## Task 9 — Função `calcular_indicadores(sims, label)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 9.1 — Implementar `calcular_indicadores`**

Implementa os 7 indicadores I1-I7 da seção 7 do SPEC.

```julia
"""
    calcular_indicadores(sims, label::String) -> NamedTuple

Calcula os 7 indicadores I1-I7 do SPEC. Funciona para sims_sddp e sims_fixa
(estruturas compativeis: lista de replicas, cada replica = lista de estagios).
"""
function calcular_indicadores(sims, label::String)
    N = length(sims)
    custos       = [sum(s[:stage_objective] for s in sim) for sim in sims]
    spill_total  = [sum(s[:spillover]       for s in sim) for sim in sims]
    ocio_total   = [sum(s[:ocioso]          for s in sim) for sim in sims]
    proc_total   = [sum(s[:processados]     for s in sim) for sim in sims]
    fila_pico    = [maximum(s[:fila].out    for s in sim) for sim in sims]

    # I1 custo medio + IC95
    mu = mean(custos); sdc = std(custos); ic = 1.96 * sdc / sqrt(N)
    # I2 quantis
    q5, q50, q95 = quantile(custos, [0.05, 0.5, 0.95])
    # I3 prob spillover > 0 (em alguma data)
    spill_prob = mean(spill_total .> 0)
    # I4 spillover total condicional
    spill_cond = isempty(spill_total[spill_total .> 0]) ? 0.0 : mean(spill_total[spill_total .> 0])
    # I5 fila pico medio
    fila_pico_med = mean(fila_pico)
    # I6 service level: fracao de dias com fila.out < threshold, media nas replicas
    service = mean(mean(s[:fila].out < SERVICE_LEVEL_FILA_THRESHOLD for s in sim) for sim in sims)
    # I7 metricas v7 (medias diarias)
    entram_d = mean(sum(s[:admitidos].in for s in sim) for sim in sims) / NUM_DIAS
    proc_d   = mean(proc_total) / NUM_DIAS
    ocio_d   = mean(ocio_total) / NUM_DIAS
    spill_d  = mean(spill_total) / NUM_DIAS

    return (
        label = label,
        N = N,
        custo_medio = mu, custo_ic = ic,
        custo_p5 = q5, custo_p50 = q50, custo_p95 = q95,
        spill_prob = spill_prob, spill_cond_med = spill_cond,
        fila_pico_med = fila_pico_med, service_level = service,
        entram_dia = entram_d, proc_dia = proc_d,
        ocio_dia = ocio_d, spill_dia = spill_d,
        custos = custos, spill_total = spill_total,
        proc_total = proc_total, fila_pico = fila_pico,
    )
end
```

- [ ] **Step 9.2 — Atualizar `main()` para smoke**

```julia
function main()
    mes = "mar"
    data = ler_mes(mes)
    fit = fit_distribuicoes(data)
    omega, probs = discretizar_por_bins(fit.escolhida.dist)
    media = mean(data)
    sims = simular_fixa(media, omega, probs, 200)
    ind = calcular_indicadores(sims, "P_X2")
    @printf("[%s P_X2] custo medio=%.1f IC=±%.1f | P5=%.1f P50=%.1f P95=%.1f\n",
        uppercase(mes), ind.custo_medio, ind.custo_ic, ind.custo_p5, ind.custo_p50, ind.custo_p95)
    @printf("  spill_prob=%.3f | spill_cond=%.1f | fila_pico=%.1f | service=%.3f\n",
        ind.spill_prob, ind.spill_cond_med, ind.fila_pico_med, ind.service_level)
end
main()
```

- [ ] **Step 9.3 — Rodar e validar**

**Esperado:** 2 linhas com todos os indicadores. P5 < P50 < P95. spill_prob ∈ [0,1]. service ∈ [0,1].

- [ ] **Step 9.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): calcular_indicadores (I1-I7 do SPEC)"
```

---

## Task 10 — Função `gerar_tabelas_terminal(mes, sims_4pol, ind_4pol)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 10.1 — Implementar `gerar_tabelas_terminal`**

Imprime Tabela A (sumário), Tabela B (dia-a-dia médio das 1000 sims, 4 sub-tabelas), Tabela C (réplica representativa, 4 sub-tabelas). Estrutura `sims_4pol` e `ind_4pol` = dicionários `Dict{String,_}` com chaves `["SDDP", "P_X1", "P_X2", "P_X3"]` na ordem.

```julia
const POL_ORDER = ["SDDP", "P_X1", "P_X2", "P_X3"]

function gerar_tabelas_terminal(mes::String, sims_4pol::Dict, ind_4pol::Dict)
    sep = "=" ^ 110
    println("\n", sep)
    println("  TABELA A — SUMARIO COMPARATIVO ($(uppercase(mes)), N=$(N_SIM))")
    println(sep)
    @printf("  %-6s | %12s | %10s | %12s | %12s | %12s | %8s | %10s | %10s | %8s\n",
        "Pol", "CustoMed", "IC95±", "P5", "P50", "P95", "Spill%>0", "SpillCond", "FilaPico", "ServLvl")
    println("  ", "-"^110)
    for pol in POL_ORDER
        i = ind_4pol[pol]
        @printf("  %-6s | %12.1f | %10.1f | %12.1f | %12.1f | %12.1f | %7.2f%% | %10.1f | %10.1f | %7.2f%%\n",
            pol, i.custo_medio, i.custo_ic, i.custo_p5, i.custo_p50, i.custo_p95,
            100*i.spill_prob, i.spill_cond_med, i.fila_pico_med, 100*i.service_level)
    end

    println("\n", sep)
    println("  TABELA B — OPERACAO DIA A DIA (media das $N_SIM sims) — $(uppercase(mes))")
    println(sep)
    for pol in POL_ORDER
        sims = sims_4pol[pol]
        println("\n  [$pol]")
        @printf("  %3s | %8s | %8s | %8s | %8s | %8s | %8s | %8s\n",
            "Dia", "FilaIni", "AdmitIn", "Proc", "FilaFim", "Spill", "Ocioso", "AdmitOut")
        println("  ", "-"^80)
        for t in 1:NUM_DIAS
            m_fila_in = mean(sim[t][:fila].in for sim in sims)
            m_adm_in  = mean(sim[t][:admitidos].in for sim in sims)
            m_proc    = mean(sim[t][:processados] for sim in sims)
            m_fila_out= mean(sim[t][:fila].out for sim in sims)
            m_spill   = mean(sim[t][:spillover] for sim in sims)
            m_ocio    = mean(sim[t][:ocioso] for sim in sims)
            m_adm_out = mean(sim[t][:admitidos].out for sim in sims)
            @printf("  %3d | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f\n",
                t, m_fila_in, m_adm_in, m_proc, m_fila_out, m_spill, m_ocio, m_adm_out)
        end
    end

    println("\n", sep)
    println("  TABELA C — REPLICA REPRESENTATIVA (mais proxima da media) — $(uppercase(mes))")
    println(sep)
    for pol in POL_ORDER
        sims = sims_4pol[pol]
        i    = ind_4pol[pol]
        idx_repr = argmin(abs.(i.custos .- i.custo_medio))
        sim_repr = sims[idx_repr]
        println("\n  [$pol]  replica idx=$idx_repr  custo=R\$ $(round(i.custos[idx_repr], digits=1))")
        @printf("  %3s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s\n",
            "Dia", "FilaIni", "AdmitIn", "ProcCap", "Proc", "FilaFim", "Spill", "Ocioso", "AdmitOut")
        println("  ", "-"^90)
        for t in 1:NUM_DIAS
            s = sim_repr[t]
            @printf("  %3d | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f\n",
                t, s[:fila].in, s[:admitidos].in, s[:w_proc],
                s[:processados], s[:fila].out, s[:spillover], s[:ocioso], s[:admitidos].out)
        end
    end
    println()
end
```

- [ ] **Step 10.2 — Smoke test simplificado** — pular o smoke isolado dessa task (precisa de todas as 4 políticas). Validar no smoke da Task 13.

- [ ] **Step 10.3 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): gerar_tabelas_terminal (3 tabelas A/B/C, 4 politicas)"
```

---

## Task 11 — Função `gerar_pngs(mes, sims_4pol, ind_4pol)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 11.1 — Implementar `gerar_pngs`**

3 PNGs: boxplot custo, ECDF custo, barras de indicadores.

```julia
function gerar_pngs(mes::String, ind_4pol::Dict)
    default(legend = :topright, size = (1000, 600))

    # 1) Boxplot custo total
    custos_mat = [ind_4pol[pol].custos for pol in POL_ORDER]
    p_box = boxplot(
        POL_ORDER, custos_mat;
        legend = false,
        title = "$(uppercase(mes)) — Custo total das $N_SIM simulacoes",
        ylabel = "Custo total (R\$)",
    )
    out_box = joinpath(OUTPUT_DIR, "v8_$(mes)_custo_boxplot.png")
    savefig(p_box, out_box)

    # 2) ECDFs sobrepostas do custo total
    p_ecdf = plot(
        title = "$(uppercase(mes)) — ECDF do custo total ($N_SIM sims)",
        xlabel = "Custo total (R\$)", ylabel = "Prob. acumulada",
    )
    for pol in POL_ORDER
        c = sort(ind_4pol[pol].custos)
        y = (1:length(c)) ./ length(c)
        plot!(p_ecdf, c, y, lw = 2, label = pol)
    end
    out_ecdf = joinpath(OUTPUT_DIR, "v8_$(mes)_custo_ecdf.png")
    savefig(p_ecdf, out_ecdf)

    # 3) Barras agrupadas de indicadores
    metrics = ["Spill%>0", "FilaPico/MAX_VAGAS", "ServLvl"]
    vals = zeros(length(metrics), length(POL_ORDER))
    for (j, pol) in enumerate(POL_ORDER)
        i = ind_4pol[pol]
        vals[:, j] = [i.spill_prob, i.fila_pico_med / MAX_VAGAS, i.service_level]
    end
    p_bar = groupedbar(
        metrics, vals;
        bar_position = :dodge,
        title = "$(uppercase(mes)) — Indicadores normalizados",
        ylabel = "Valor (0..1)",
        label = reshape(POL_ORDER, 1, :),
    )
    out_bar = joinpath(OUTPUT_DIR, "v8_$(mes)_indicadores_bar.png")
    savefig(p_bar, out_bar)

    @printf("  PNGs salvos: %s, %s, %s\n",
        basename(out_box), basename(out_ecdf), basename(out_bar))
end
```

- [ ] **Step 11.2 — Smoke** — também validado no smoke da Task 13.

- [ ] **Step 11.3 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): gerar_pngs (boxplot, ECDF, barras de indicadores)"
```

---

## Task 12 — Função `gerar_csvs(mes, sims_4pol, ind_4pol)`

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 12.1 — Implementar `gerar_csvs`**

3 CSVs por mês: resultados (4×1000 linhas), sumário (4 linhas), réplica representativa (30 linhas × 4 sub-tabelas).

```julia
function gerar_csvs(mes::String, sims_4pol::Dict, ind_4pol::Dict)
    # 1) resultados (1 linha por (politica, replica))
    df_res = DataFrame(
        politica = String[], replica = Int[],
        custo_total = Float64[], spillover_total = Float64[],
        ocioso_total = Float64[], processados_total = Float64[],
        fila_pico = Float64[], service_level_repl = Float64[],
    )
    for pol in POL_ORDER
        sims = sims_4pol[pol]
        for (r, sim) in enumerate(sims)
            push!(df_res, (
                pol, r,
                sum(s[:stage_objective] for s in sim),
                sum(s[:spillover] for s in sim),
                sum(s[:ocioso] for s in sim),
                sum(s[:processados] for s in sim),
                maximum(s[:fila].out for s in sim),
                mean(s[:fila].out < SERVICE_LEVEL_FILA_THRESHOLD for s in sim),
            ))
        end
    end
    CSV.write(joinpath(OUTPUT_DIR, "v8_$(mes)_resultados.csv"), df_res)

    # 2) sumario (1 linha por politica)
    df_sum = DataFrame(
        politica = String[], n = Int[],
        custo_medio = Float64[], custo_ic = Float64[],
        custo_p5 = Float64[], custo_p50 = Float64[], custo_p95 = Float64[],
        spill_prob = Float64[], spill_cond_med = Float64[],
        fila_pico_med = Float64[], service_level = Float64[],
        entram_dia = Float64[], proc_dia = Float64[],
        ocio_dia = Float64[], spill_dia = Float64[],
    )
    for pol in POL_ORDER
        i = ind_4pol[pol]
        push!(df_sum, (
            pol, i.N, i.custo_medio, i.custo_ic,
            i.custo_p5, i.custo_p50, i.custo_p95,
            i.spill_prob, i.spill_cond_med,
            i.fila_pico_med, i.service_level,
            i.entram_dia, i.proc_dia, i.ocio_dia, i.spill_dia,
        ))
    end
    CSV.write(joinpath(OUTPUT_DIR, "v8_$(mes)_sumario.csv"), df_sum)

    # 3) replica representativa (1 linha por dia, colunas por politica)
    df_rep = DataFrame(dia = collect(1:NUM_DIAS))
    for pol in POL_ORDER
        sims = sims_4pol[pol]
        i = ind_4pol[pol]
        idx = argmin(abs.(i.custos .- i.custo_medio))
        sim = sims[idx]
        df_rep[!, Symbol("$(pol)_FilaIni")]  = [sim[t][:fila].in for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_AdmIn")]    = [sim[t][:admitidos].in for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_Wproc")]    = [sim[t][:w_proc] for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_Proc")]     = [sim[t][:processados] for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_FilaFim")]  = [sim[t][:fila].out for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_Spill")]    = [sim[t][:spillover] for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_Ocioso")]   = [sim[t][:ocioso] for t in 1:NUM_DIAS]
        df_rep[!, Symbol("$(pol)_AdmOut")]   = [sim[t][:admitidos].out for t in 1:NUM_DIAS]
    end
    CSV.write(joinpath(OUTPUT_DIR, "v8_$(mes)_replica_repr.csv"), df_rep)

    @printf("  CSVs salvos: v8_%s_{resultados,sumario,replica_repr}.csv\n", mes)
end
```

- [ ] **Step 12.2 — Smoke** — validado na Task 13.

- [ ] **Step 12.3 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl"
git commit -m "feat(v8): gerar_csvs (resultados, sumario, replica representativa)"
```

---

## Task 13 — Função `analisar_mes(mes)` + `main()` final

**Files:**
- Modify: `Model SDDP - 19-05-26/model_v8.jl`

- [ ] **Step 13.1 — Implementar `analisar_mes` e `main()` final**

```julia
"""
    analisar_mes(mes::String)

Pipeline completo para 1 mes: ler -> fit -> plot fit -> discretizar ->
treinar SDDP -> simular 4 politicas -> calcular indicadores ->
gerar tabelas/PNGs/CSVs.
"""
function analisar_mes(mes::String)
    println("\n", "#"^110)
    @printf("# ANALISANDO MES: %s (N_SIM=%d)\n", uppercase(mes), N_SIM)
    println("#"^110)

    data = ler_mes(mes)
    @printf("[%s] data: n=%d media=%.1f sd=%.2f\n",
        uppercase(mes), length(data), mean(data), std(data))

    fit = fit_distribuicoes(data)
    @printf("[%s] dist escolhida: %s | AIC=%.2f | KS_p=%.4f\n",
        uppercase(mes), fit.escolhida.name, fit.escolhida.aic, fit.escolhida.ks_p)
    plot_fit(mes, data, fit.ranking)

    omega, probs = discretizar_por_bins(fit.escolhida.dist)
    @printf("[%s] discretizado em %d cenarios\n", uppercase(mes), length(omega))

    println("\n[$(uppercase(mes))] treinando SDDP...")
    model = treinar_sddp(omega, probs)
    bound = SDDP.calculate_bound(model)
    @printf("[%s] bound SDDP=%.1f\n", uppercase(mes), bound)

    println("\n[$(uppercase(mes))] simulando 4 politicas x $N_SIM replicas...")
    media = mean(data)
    X1, X2, X3 = media * 0.9, media, media * 1.1
    @printf("[%s] X1=%.0f X2=%.0f X3=%.0f\n", uppercase(mes), X1, X2, X3)

    sims_sddp = simular_sddp(model, N_SIM)
    sims_p1 = simular_fixa(X1, omega, probs, N_SIM)
    sims_p2 = simular_fixa(X2, omega, probs, N_SIM)
    sims_p3 = simular_fixa(X3, omega, probs, N_SIM)

    sims_4pol = Dict("SDDP" => sims_sddp, "P_X1" => sims_p1, "P_X2" => sims_p2, "P_X3" => sims_p3)
    ind_4pol  = Dict(pol => calcular_indicadores(sims_4pol[pol], pol) for pol in POL_ORDER)

    gerar_tabelas_terminal(mes, sims_4pol, ind_4pol)
    gerar_pngs(mes, ind_4pol)
    gerar_csvs(mes, sims_4pol, ind_4pol)

    return ind_4pol
end

function main()
    resultados_globais = Dict{String,Any}()
    t_inicio = time()
    for mes in MESES
        resultados_globais[mes] = analisar_mes(mes)
    end
    t_total = time() - t_inicio
    @printf("\n[FIM] tempo total: %.1f s (%.1f min)\n", t_total, t_total/60)
    return resultados_globais
end

main()
```

- [ ] **Step 13.2 — Rodar pipeline completo**

```
julia --project=. "Model SDDP - 19-05-26/model_v8.jl"
```

**Esperado (tempo total 3-8 min):**
- Treina SDDP para mar (~30-60s), simula 4 políticas, gera tabelas/PNGs/CSVs
- Treina SDDP para jul (~30-60s), idem
- Total: 5 PNGs × 2 = 10 PNGs em outputs/
- Total: 3 CSVs × 2 = 6 CSVs em outputs/
- Tabelas A/B/C impressas no terminal para cada mês

- [ ] **Step 13.3 — Validação visual**

Inspecionar visualmente:
1. `outputs/v8_mar_custo_boxplot.png` — caixas das 4 políticas; SDDP deve ter mediana ≤ a melhor fixa
2. `outputs/v8_mar_custo_ecdf.png` — curvas das 4 políticas; SDDP deve estar à esquerda (custos menores)
3. `outputs/v8_mar_indicadores_bar.png` — 3 grupos de barras
4. `outputs/v8_mar_sumario.csv` — abrir, conferir que todos os campos têm valores razoáveis

- [ ] **Step 13.4 — Commit**

```
git add "Model SDDP - 19-05-26/model_v8.jl" "Model SDDP - 19-05-26/outputs/"
git commit -m "feat(v8): pipeline completo (analisar_mes + main + outputs gerados)"
```

---

## Task 14 — Validações V1-V4

**Files:**
- Inspeção manual + comparação com v7

- [ ] **Step 14.1 — V1: Reproducibilidade vs v7 (março)**

Rodar o v7 (`julia "03-03-2026 - model_v1/model_v7_04_05_2026.jl"`) e anotar o custo médio do SDDP em março. Comparar com `v8_mar_sumario.csv` linha SDDP.

**Esperado:** diferença ≤ ±5% (variação devida a N_SIM 500→1000 + seed). Se ultrapassar, investigar; provavelmente é seed e está OK.

- [ ] **Step 14.2 — V1b: V1 em julho com tolerância maior**

Copiar o `model_v7_04_05_2026.jl` para um arquivo temporário (ex: `model_v7_jul.jl`), trocar `const MES_ESCOLHIDO = "mar"` por `"jul"`, rodar essa cópia e anotar o custo médio SDDP de julho. Comparar com `v8_jul_sumario.csv` linha SDDP. Apagar a cópia temporária depois.

**Esperado:** diferença ≤ ±10% (julho tem maior variância).

- [ ] **Step 14.3 — V2: Sanidade das políticas fixas**

No boxplot `v8_<mes>_custo_boxplot.png`:
- **X1 baixo** (90% da média) → esperado: mais spillover/fila, então custo médio **maior** que X2
- **X3 alto** (110% da média) → esperado: mais ociosidade, custo médio **maior** que X2
- **X2** (média) → custo intermediário, possivelmente competitivo com SDDP

Se algum desses padrões não se verifica, investigar a fórmula de `simular_fixa`.

- [ ] **Step 14.4 — V3: CRN funcionando**

Rodar `julia "Model SDDP - 19-05-26/model_v8.jl"` duas vezes seguidas. Os custos das **políticas fixas** (P_X1/P_X2/P_X3) na coluna `custo_total` do `v8_mar_resultados.csv` devem ser **idênticos** entre as duas execuções (pois usam seed determinística). Os custos do SDDP podem variar (amostragem interna).

**Comando para diff (PowerShell):**
```
fc Model SDDP - 19-05-26/outputs/v8_mar_resultados.csv Model SDDP - 19-05-26/outputs/v8_mar_resultados_run2.csv
```
(salve cópia antes da segunda execução)

- [ ] **Step 14.5 — V4: Bound SDDP ≤ custo médio simulado**

No print do `main()` durante o run, conferir que `bound` ≤ `custo_medio` da linha SDDP no sumário. Se violar, há bug (improvável; mais comum: bound não convergiu — gap grande).

- [ ] **Step 14.6 — Commit (apenas se houve correção)**

Caso V1-V4 indiquem necessidade de ajuste, fazer correção pontual e commit `fix(v8): <descricao>`.

---

## Task 15 — Cleanup e documentação final

**Files:**
- Modify: `Model SDDP - 19-05-26/SPEC.md` (opcional, anotar achados)
- Create: `Model SDDP - 19-05-26/README.md` (opcional)

- [ ] **Step 15.1 — Adicionar README curto**

```markdown
# Model SDDP - 19-05-26

Comparação de política SDDP vs 3 políticas fixas para agendamento rodoviário no Ecopátio do Porto de Santos.

## Como rodar

```bash
julia --project=. model_v8.jl
```

Tempo estimado: 3-8 min.

## Outputs

Tudo em `outputs/`:
- `v8_<mes>_fit_*.png` — análise da distribuição ajustada
- `v8_<mes>_custo_boxplot.png` — comparação visual das 4 políticas
- `v8_<mes>_custo_ecdf.png` — ECDFs sobrepostas
- `v8_<mes>_indicadores_bar.png` — barras de indicadores
- `v8_<mes>_resultados.csv` — réplica a réplica
- `v8_<mes>_sumario.csv` — 1 linha por política, todos os indicadores
- `v8_<mes>_replica_repr.csv` — réplica representativa, 30 dias × 4 políticas

## Arquivos

- [SPEC.md](SPEC.md) — design do modelo
- [PLAN.md](PLAN.md) — plano de implementação
- [model_v8.jl](model_v8.jl) — código
```

- [ ] **Step 15.2 — Commit final**

```
git add "Model SDDP - 19-05-26/README.md"
git commit -m "docs(v8): README com instrucoes de uso"
```

- [ ] **Step 15.3 — Resumo final (para o usuário)**

Reportar:
- ✅ Pasta `Model SDDP - 19-05-26/` com `SPEC.md`, `PLAN.md`, `README.md`, `model_v8.jl`
- ✅ `outputs/` com 10 PNGs + 6 CSVs
- ✅ Tempo total da execução
- ✅ Resultado-chave: qual política venceu em mar e em jul, e qual indicador foi mais discriminante
- ⚠️ Limitações conhecidas (CRN imperfeito entre SDDP vs fixa, assimetria de admissão)
