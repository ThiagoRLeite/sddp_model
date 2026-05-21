import Pkg
Pkg.add([
    "CSV",
    "DataFrames",
    "Distributions",
    "HypothesisTests",
    "SDDP",
    "HiGHS",
    "StatsBase",
])

using CSV, DataFrames, Statistics, Printf, Random
using Distributions, HypothesisTests
using SDDP, HiGHS, JuMP
using StatsBase: sample, Weights

# ============================================================
# MODELO v8 — COMPARACAO SDDP vs POLITICAS FIXAS
# ============================================================
# - 2 meses (mar + jul) × 4 politicas × 1000 replicas
# - Outputs em Model SDDP - 19-05-26/outputs/
# - Spec: SPEC.md
# ============================================================

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
const SERVICE_LEVEL_FILA_THRESHOLD = 2000
const SEED_BASE = 42

# Paths (v8.5: outputs reorganizados em csvs/, graficos/, terminal/)
const ROOT = @__DIR__
const CSV_PATH = joinpath(ROOT, "..", "03-03-2026 - model_v1", "Processamento Santos", "processados_2025.csv")
const OUTPUT_DIR  = joinpath(ROOT, "outputs")
const CSVS_DIR    = joinpath(OUTPUT_DIR, "csvs")
const PLOTS_DIR   = joinpath(OUTPUT_DIR, "graficos")    # apenas PNGs do Python publicacao-ready
const TERMINAL_DIR = joinpath(OUTPUT_DIR, "terminal")
for d in (OUTPUT_DIR, CSVS_DIR, PLOTS_DIR, TERMINAL_DIR)
    isdir(d) || mkpath(d)
end

@printf("-- model v8 iniciando --\n")
@printf("  CSV_PATH = %s\n", CSV_PATH)
@printf("  CSVS_DIR = %s\n", CSVS_DIR)
@printf("  C_OCIOSO_TOTAL = R\$ %.1f\n", C_OCIOSO_TOTAL)
@printf("  N_SIM = %d | MESES = %s\n\n", N_SIM, MESES)

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
        k = length(params(dist))
        aic = 2k - 2ll
        ks_p = pvalue(ApproximateOneSampleKSTest(data, dist))
        return (name = name, dist = dist, loglik = ll, aic = aic, ks_p = ks_p)
    end
    results = [_score(n, d) for (n, d) in candidates]
    sort!(results, by = r -> r.aic)
    valid = filter(r -> r.ks_p >= 0.05, results)
    escolhida = isempty(valid) ? results[1] : sort(valid, by = r -> r.aic)[1]
    return (escolhida = escolhida, ranking = results)
end

# (v8.5) plot_fit removido — graficos de fit eram redundantes com o ranking AIC/KS
# impresso no terminal e nao eram usados em ANALISE.md.

"""
    discretizar_por_bins(dist::Distribution; n_cenarios=100, q_low=0.01, q_high=0.99)
        -> (omega::Vector{Float64}, probs::Vector{Float64})

Particiona [quantil(q_low), quantil(q_high)] em n_cenarios bins de igual largura.
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

"""
    treinar_sddp(omega::Vector{Float64}, probs::Vector{Float64}) -> SDDP.PolicyGraph

Constroi e treina (SDDP_ITERATIONS iteracoes) o modelo identico ao v7. Retorna o grafo.
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

"""
    simular_fixa(X::Float64, omega::Vector{Float64}, probs::Vector{Float64}, N::Int;
                 seed_base::Int = SEED_BASE)
        -> Vector{Vector{Dict}}

Simulacao deterministica da politica fixa "admitir X constante (proc clip por w_proc e fila+adm)".
NOVA REGRA (v8.3): w_proc dia a dia e' FIXO = media do SDDP no mesmo dia.
Politica fixa e' DETERMINISTICA (NAO e' Monte Carlo) — todas as N replicas sao identicas
porque nao ha amostragem aleatoria: w_proc fixo + adm_out fixo => uma unica trajetoria possivel.
- X = admissao constante (adm_out = X)
- proc = min(w_proc_medio_diario[t], fila.in + adm.in)

Saida: lista de N replicas. Cada replica = lista de NUM_DIAS estagios.
Cada estagio = Dict com chaves compativeis com o SDDP.
"""
function simular_fixa(X::Float64, w_proc_medio_diario::Vector{Float64}, N::Int)
    @assert length(w_proc_medio_diario) == NUM_DIAS

    sims = Vector{Vector{Dict{Symbol,Any}}}(undef, N)
    for r in 1:N
        # Deterministico: todas as N replicas serao identicas.
        # Mantemos N=1000 para compatibilidade estrutural com sims_sddp.
        fila_in_t = Float64(FILA_INICIAL)
        adm_in_t  = Float64(ADMITIDOS_INICIAL)
        sim_r = Vector{Dict{Symbol,Any}}(undef, NUM_DIAS)
        for t in 1:NUM_DIAS
            w_t = w_proc_medio_diario[t]   # w_proc FIXO = media SDDP dia t

            proc_t  = min(w_t, fila_in_t + adm_in_t)
            spill_t = max(0.0, fila_in_t + adm_in_t - CAP_ECOPATIO - proc_t)
            ocio_t  = max(0.0, w_t - proc_t)
            fila_out_t = fila_in_t + adm_in_t - proc_t
            adm_out_t  = X

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

"""
    calcular_indicadores(sims, label::String) -> NamedTuple

Calcula os 7 indicadores I1-I7 do SPEC. Funciona para sims_sddp e sims_fixa
(estruturas compativeis: lista de replicas, cada replica = lista de estagios).

Retorna NamedTuple com escalares + vetores brutos (custos, spill_total, ...)
para uso downstream em plots e CSVs.
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
    # I3 prob spillover total > 0 (algum dia teve spill)
    spill_prob = mean(spill_total .> 0)
    # I4 spillover total condicional (media nos casos com spill > 0)
    pos = spill_total[spill_total .> 0]
    spill_cond = isempty(pos) ? 0.0 : mean(pos)
    # I5 fila pico medio
    fila_pico_med = mean(fila_pico)
    # I6 service level (throughput): total processado / total admitido nos dias 2..30.
    # Excluimos o dia 1 porque o estado inicial (AdmIn=3000 forcado, FilaInicial=1200)
    # distorce a metrica. Cap em 100% — service maior que 100% (consumindo fila inicial)
    # nao tem significado operacional defensavel para o relatorio.
    proc_d2_d30 = [sum(s[:processados] for s in sim[2:end]) for sim in sims]
    adm_d2_d30  = [sum(s[:admitidos].in for s in sim[2:end]) for sim in sims]
    service = min(1.0, mean(proc_d2_d30) / mean(adm_d2_d30))
    # I7 metricas v7 (medias diarias agregadas)
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

const POL_ORDER = ["SDDP", "P_-10", "P_-5", "P_0", "P_+5", "P_+10"]
const PCT_OFFSETS = [-0.10, -0.05, 0.00, +0.05, +0.10]   # base = media de adm_out(SDDP) excluindo dia 1

"""
    gerar_tabelas_terminal(mes, sims_4pol, ind_4pol, sim_sddp_cen_medio)

Imprime no terminal:
  TABELA A — Sumario comparativo (1000 sims)
  TABELA B — ANEXO cenario medio deterministico (mesmas tabelas dos Anexos A/B do ANALISE.md)
  TABELA C — Replica representativa estocastica (SDDP 1000 sims)
"""
function gerar_tabelas_terminal(mes::String, sims_4pol::Dict, ind_4pol::Dict, sim_sddp_cen_medio)
    sep_thick = "=" ^ 120
    sep_thin  = "-" ^ 120

    # ============ TABELA A ============
    println("\n", sep_thick)
    println("  TABELA A — SUMARIO COMPARATIVO ($(uppercase(mes)), N=$(N_SIM) sims) ")
    println(sep_thick)
    @printf("  %-6s | %14s | %10s | %14s | %14s | %14s | %8s | %10s | %10s | %8s\n",
        "Pol", "CustoMed", "IC95±", "P5", "P50", "P95", "Spill%>0", "SpillCond", "FilaPico", "ServLvl")
    println("  ", sep_thin)
    for pol in POL_ORDER
        i = ind_4pol[pol]
        @printf("  %-6s | %14.1f | %10.1f | %14.1f | %14.1f | %14.1f | %7.2f%% | %10.1f | %10.1f | %7.2f%%\n",
            pol, i.custo_medio, i.custo_ic, i.custo_p5, i.custo_p50, i.custo_p95,
            100*i.spill_prob, i.spill_cond_med, i.fila_pico_med, 100*i.service_level)
    end

    # ============ TABELA B — ANEXO cenario medio ============
    # Helper: imprime 30 dias + linha Σ. Para SDDP, usa sim_sddp_cen_medio (SDDP.Historical).
    # Para as fixas, usa sims_4pol[pol][1] (primeira replica — todas identicas, deterministicas).
    function _imprime_tabela_anexo(pol, sim)
        println("\n  [$pol]  Σ Custo = R\$ $(round(sum(sim[t][:stage_objective] for t in 1:NUM_DIAS) / 1e6, digits=2))M")
        @printf("  %3s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %10s\n",
            "Dia", "FilaIni", "AdmIn", "w_proc", "Proc", "FilaFim", "Spill", "Ocioso", "AdmOut", "Custo(R\$)")
        println("  ", "-"^110)
        soma = Dict(:proc=>0.0, :spill=>0.0, :ocioso=>0.0, :custo=>0.0)
        for t in 1:NUM_DIAS
            s = sim[t]
            @printf("  %3d | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %10.0f\n",
                t, s[:fila].in, s[:admitidos].in, s[:w_proc], s[:processados],
                s[:fila].out, s[:spillover], s[:ocioso], s[:admitidos].out, s[:stage_objective])
            soma[:proc]   += s[:processados]
            soma[:spill]  += s[:spillover]
            soma[:ocioso] += s[:ocioso]
            soma[:custo]  += s[:stage_objective]
        end
        println("  ", "-"^110)
        @printf("  %3s | %8s | %8s | %8s | %8.0f | %8s | %8.1f | %8.1f | %8s | %10.0f   (= R\$ %.2fM)\n",
            "Σ", "—", "—", "—", soma[:proc], "—", soma[:spill], soma[:ocioso], "—",
            soma[:custo], soma[:custo]/1e6)
    end

    println("\n", sep_thick)
    println("  TABELA B — ANEXO cenario medio deterministico ($(uppercase(mes)), 1 trajetoria, 30 dias)")
    println("           SDDP via SDDP.Historical, fixas com adm_out fixo. Comparacao 100% justa.")
    println("           Σ Custo bate EXATO com o grafico de custo acumulado dia 30.")
    println(sep_thick)
    _imprime_tabela_anexo("SDDP", sim_sddp_cen_medio)
    for pol in ["P_-10", "P_-5", "P_0", "P_+5", "P_+10"]
        _imprime_tabela_anexo(pol, sims_4pol[pol][1])  # 1a replica = todas identicas (det.)
    end

    # ============ TABELA C — replica representativa estocastica ============
    println("\n", sep_thick)
    println("  TABELA C — REPLICA REPRESENTATIVA ESTOCASTICA ($(uppercase(mes)), SDDP nas 1000 sims)")
    println("           (apenas SDDP — fixas sao deterministicas, ja mostradas na Tabela B)")
    println(sep_thick)
    i = ind_4pol["SDDP"]
    idx_repr = argmin(abs.(i.custos .- i.custo_medio))
    sim_repr = sims_4pol["SDDP"][idx_repr]
    println("\n  [SDDP estocastico]  replica idx=$idx_repr  custo=R\$ $(round(i.custos[idx_repr]/1e6, digits=2))M  (proximo da media R\$ $(round(i.custo_medio/1e6, digits=2))M)")
    @printf("  %3s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %10s\n",
        "Dia", "FilaIni", "AdmIn", "w_proc", "Proc", "FilaFim", "Spill", "Ocioso", "AdmOut", "Custo(R\$)")
    println("  ", "-"^110)
    soma_c = 0.0
    for t in 1:NUM_DIAS
        s = sim_repr[t]
        @printf("  %3d | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %10.0f\n",
            t, s[:fila].in, s[:admitidos].in, s[:w_proc], s[:processados],
            s[:fila].out, s[:spillover], s[:ocioso], s[:admitidos].out, s[:stage_objective])
        soma_c += s[:stage_objective]
    end
    println("  ", "-"^110)
    @printf("  %3s | Σ Custo = R\$ %.0f   (= R\$ %.2fM)\n", "Σ", soma_c, soma_c/1e6)
    println()
end

# (v8.5) gerar_pngs (boxplot/ECDF/barras Julia) removido — plot_v8.py gera versoes
# publicacao-ready (matplotlib+seaborn) em outputs/graficos/.

"""
    construir_series(sims_4pol::Dict, sim_sddp_cen_medio) -> Dict

Constroi o dicionario series usado no CSV dia-a-dia.

CONSISTENCIA com Anexos: SDDP usa a TRAJETORIA do cenario medio deterministico
(via SDDP.Historical) — bate exato com os Anexos A/B do ANALISE.md.
Fixas seguem deterministicas (1000 sims identicas, primeira replica = todas).
Banda estocastica do SDDP (P5/P95 + media 1000 sims) eh exportada como SDDP_estoc_*.
"""
function construir_series(sims_4pol::Dict, sim_sddp_cen_medio)
    dias = collect(1:NUM_DIAS)

    function _medias_dia(sims, key, in_or_out=nothing)
        return [
            mean(in_or_out === nothing ? sim[t][key] : getproperty(sim[t][key], in_or_out)
                 for sim in sims)
            for t in dias
        ]
    end

    function _quantil_dia(sims, key, q::Float64, in_or_out=nothing)
        return [
            quantile([in_or_out === nothing ? sim[t][key] : getproperty(sim[t][key], in_or_out)
                      for sim in sims], q)
            for t in dias
        ]
    end

    # series[pol][var] = vetor de 30 valores
    series = Dict{String,Any}()
    for pol in POL_ORDER
        sims = sims_4pol[pol]
        if pol == "SDDP"
            # SDDP usa a trajetoria do cenario medio deterministico (consistente com Anexo)
            series[pol] = Dict(
                :fila_in  => [sim_sddp_cen_medio[t][:fila].in       for t in dias],
                :adm_in   => [sim_sddp_cen_medio[t][:admitidos].in  for t in dias],
                :w_proc   => [sim_sddp_cen_medio[t][:w_proc]        for t in dias],
                :proc     => [sim_sddp_cen_medio[t][:processados]   for t in dias],
                :ocioso   => [sim_sddp_cen_medio[t][:ocioso]        for t in dias],
                :spill    => [sim_sddp_cen_medio[t][:spillover]     for t in dias],
                :fila_out => [sim_sddp_cen_medio[t][:fila].out      for t in dias],
                :adm_out  => [sim_sddp_cen_medio[t][:admitidos].out for t in dias],
                :custo    => [sim_sddp_cen_medio[t][:stage_objective] for t in dias],
            )
        else
            # Fixas: media das 1000 sims (identicas, pois deterministicas)
            series[pol] = Dict(
                :fila_in  => _medias_dia(sims, :fila, :in),
                :adm_in   => _medias_dia(sims, :admitidos, :in),
                :w_proc   => _medias_dia(sims, :w_proc),
                :proc     => _medias_dia(sims, :processados),
                :ocioso   => _medias_dia(sims, :ocioso),
                :spill    => _medias_dia(sims, :spillover),
                :fila_out => _medias_dia(sims, :fila, :out),
                :adm_out  => _medias_dia(sims, :admitidos, :out),
                :custo    => _medias_dia(sims, :stage_objective),
            )
        end
        series[pol][:custo_acum] = cumsum(series[pol][:custo])
    end

    # Banda estocastica do SDDP (1000 sims) — usada no grafico de custo acumulado
    sims_sddp = sims_4pol["SDDP"]
    custo_por_replica = [[sim[t][:stage_objective] for t in dias] for sim in sims_sddp]
    custo_acum_por_replica = [cumsum(c) for c in custo_por_replica]
    cum_matrix = reduce(hcat, custo_acum_por_replica)  # 30 x N_SIM
    series["SDDP_estoc"] = Dict(
        :custo_mean      => _medias_dia(sims_sddp, :stage_objective),
        :custo_p5        => _quantil_dia(sims_sddp, :stage_objective, 0.05),
        :custo_p95       => _quantil_dia(sims_sddp, :stage_objective, 0.95),
        :custo_acum_mean => [mean(cum_matrix[t, :]) for t in dias],
        :custo_acum_p5   => [quantile(cum_matrix[t, :], 0.05) for t in dias],
        :custo_acum_p95  => [quantile(cum_matrix[t, :], 0.95) for t in dias],
    )

    return series
end

"""
    gerar_csv_dia_a_dia(mes::String, series::Dict) -> nothing

CSV com medias dia-a-dia (30 linhas) das variaveis para cada politica.

VALORES NATIVOS DO MODELO — sem nenhum recalculo. Para o SDDP, cada coluna
e' a media direta entre as 1000 replicas estocasticas; nao aplicamos nenhuma
formula em cima das medias. Para as fixas, sao trajetorias deterministicas.

NOTA: para o SDDP, a media estocastica de Spill (= mean(max(0, fila_out[r,t]-CAP)))
pode ser positiva mesmo quando a media de fila_out estiver abaixo de CAP, por
causa da desigualdade de Jensen (mean(max(0, X)) >= max(0, mean(X))). Isso
NAO E BUG — e' propriedade matematica esperada quando se agrega trajetorias
estocasticas. Para uma TRAJETORIA INDIVIDUAL do SDDP (onde a formula bate
linha-a-linha), use o CSV v8_<mes>_replica_repr.csv (replica de custo
proximo da media) ou v8_<mes>_replica_qualquer.csv (replica idx=42).
"""
function gerar_csv_dia_a_dia(mes::String, series::Dict)
    df = DataFrame(dia = collect(1:NUM_DIAS))
    for pol in POL_ORDER
        df[!, Symbol("$(pol)_fila_in")]    = series[pol][:fila_in]
        df[!, Symbol("$(pol)_adm_in")]     = series[pol][:adm_in]
        df[!, Symbol("$(pol)_w_proc")]     = series[pol][:w_proc]
        df[!, Symbol("$(pol)_proc")]       = series[pol][:proc]
        df[!, Symbol("$(pol)_fila_out")]   = series[pol][:fila_out]
        df[!, Symbol("$(pol)_spill")]      = series[pol][:spill]
        df[!, Symbol("$(pol)_ocioso")]     = series[pol][:ocioso]
        df[!, Symbol("$(pol)_adm_out")]    = series[pol][:adm_out]
        df[!, Symbol("$(pol)_custo")]      = series[pol][:custo]
        df[!, Symbol("$(pol)_custo_acum")] = series[pol][:custo_acum]
    end
    # Banda estocastica do SDDP (1000 sims) — para overlay no grafico
    if haskey(series, "SDDP_estoc")
        df[!, :SDDP_estoc_custo_mean]      = series["SDDP_estoc"][:custo_mean]
        df[!, :SDDP_estoc_custo_p5]        = series["SDDP_estoc"][:custo_p5]
        df[!, :SDDP_estoc_custo_p95]       = series["SDDP_estoc"][:custo_p95]
        df[!, :SDDP_estoc_custo_acum_mean] = series["SDDP_estoc"][:custo_acum_mean]
        df[!, :SDDP_estoc_custo_acum_p5]   = series["SDDP_estoc"][:custo_acum_p5]
        df[!, :SDDP_estoc_custo_acum_p95]  = series["SDDP_estoc"][:custo_acum_p95]
    end
    CSV.write(joinpath(CSVS_DIR, "v8_$(mes)_dia_a_dia.csv"), df)
    @printf("  CSV dia-a-dia salvo: v8_%s_dia_a_dia.csv (SDDP=cenario medio + banda P5/P95 estoc)\n", mes)
end

"""
    gerar_csv_replica_qualquer(mes::String, sims_sddp, idx_repl::Int) -> nothing

CSV com 1 replica QUALQUER do SDDP (estocastico) — trajetoria real onde
Spill = max(0, FilaFim - CAP_ECOPATIO) bate exato linha a linha.
"""
function gerar_csv_replica_qualquer(mes::String, sims_sddp, idx_repl::Int)
    sim = sims_sddp[idx_repl]
    df = DataFrame(
        dia        = collect(1:NUM_DIAS),
        fila_in    = [sim[t][:fila].in for t in 1:NUM_DIAS],
        adm_in     = [sim[t][:admitidos].in for t in 1:NUM_DIAS],
        w_proc     = [sim[t][:w_proc] for t in 1:NUM_DIAS],
        proc       = [sim[t][:processados] for t in 1:NUM_DIAS],
        fila_out   = [sim[t][:fila].out for t in 1:NUM_DIAS],
        spill      = [sim[t][:spillover] for t in 1:NUM_DIAS],
        ocioso     = [sim[t][:ocioso] for t in 1:NUM_DIAS],
        adm_out    = [sim[t][:admitidos].out for t in 1:NUM_DIAS],
        custo      = [sim[t][:stage_objective] for t in 1:NUM_DIAS],
    )
    CSV.write(joinpath(CSVS_DIR, "v8_$(mes)_replica_qualquer.csv"), df)
    @printf("  CSV replica qualquer (idx=%d) salvo: v8_%s_replica_qualquer.csv\n", idx_repl, mes)
end

"""
    gerar_csvs(mes::String, sims_4pol::Dict, ind_4pol::Dict)

Gera 3 CSVs em CSVS_DIR:
- v8_<mes>_resultados.csv (1 linha por (politica, replica))
- v8_<mes>_sumario.csv     (1 linha por politica)
- v8_<mes>_replica_repr.csv (30 dias × colunas por politica)
"""
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
    CSV.write(joinpath(CSVS_DIR, "v8_$(mes)_resultados.csv"), df_res)

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
    CSV.write(joinpath(CSVS_DIR, "v8_$(mes)_sumario.csv"), df_sum)

    # 3) replica representativa (30 linhas × colunas por politica)
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
    CSV.write(joinpath(CSVS_DIR, "v8_$(mes)_replica_repr.csv"), df_rep)

    @printf("  CSVs salvos: v8_%s_{resultados,sumario,replica_repr}.csv\n", mes)
end

"""
    analisar_mes(mes::String) -> Dict{String,NamedTuple}

Pipeline completo para 1 mes:
  1) ler CSV -> 2) fit dist -> 3) discretizar -> 4) treinar SDDP ->
  5) simular SDDP -> 6) usar proc_dia(SDDP) como BASE -> 7) simular 5
  pol fixas em base*(1+offset) com offsets [-10%, -5%, 0%, +5%, +10%]
  -> 8) calcular indicadores das 6 politicas -> 9) tabelas/PNGs/CSVs.
Retorna dict (6 chaves) de indicadores.
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
    @printf("[%s] ranking AIC/KS_p: %s\n", uppercase(mes),
        join(["$(r.name):AIC=$(round(r.aic,digits=1)),KS=$(round(r.ks_p,digits=3))" for r in fit.ranking], " | "))

    omega, probs = discretizar_por_bins(fit.escolhida.dist)
    @printf("[%s] discretizado em %d cenarios\n", uppercase(mes), length(omega))

    println("\n[$(uppercase(mes))] treinando SDDP...")
    model = treinar_sddp(omega, probs)
    bound = SDDP.calculate_bound(model)
    @printf("[%s] bound SDDP=%.1f\n", uppercase(mes), bound)

    # 1) Simula SDDP primeiro — extrai:
    #    a) base de admissao = media(adm_out(SDDP), dias 2..30)
    #    b) w_proc medio por dia = media(w_proc(SDDP) por dia t)
    #       — usado para alimentar a politica fixa (cenario determinista)
    println("\n[$(uppercase(mes))] simulando SDDP x $N_SIM replicas...")
    sims_sddp = simular_sddp(model, N_SIM)
    ind_sddp  = calcular_indicadores(sims_sddp, "SDDP")

    # base: media de adm_out do SDDP nos dias 2..30 (exclui dia 1 distorcido)
    adm_out_por_dia = [mean(sim[t][:admitidos].out for sim in sims_sddp) for t in 2:NUM_DIAS]
    base = mean(adm_out_por_dia)
    @printf("[%s] base = mean(adm_out(SDDP), dias 2..%d) = %.1f caminhoes/dia\n",
        uppercase(mes), NUM_DIAS, base)

    # w_proc medio por dia das 1000 sims SDDP — politica fixa usa este vetor fixo
    w_proc_medio_diario = [mean(sim[t][:w_proc] for sim in sims_sddp) for t in 1:NUM_DIAS]
    @printf("[%s] w_proc medio SDDP por dia: min=%.0f mean=%.0f max=%.0f\n",
        uppercase(mes), minimum(w_proc_medio_diario), mean(w_proc_medio_diario), maximum(w_proc_medio_diario))

    # 2) Define 5 politicas fixas em torno da base SDDP
    pol_fixas_nomes = ["P_-10", "P_-5", "P_0", "P_+5", "P_+10"]
    Xs = base .* (1.0 .+ PCT_OFFSETS)
    for (n, x) in zip(pol_fixas_nomes, Xs)
        @printf("  %-6s X=%.1f (base * %+.0f%%)\n", n, x, 100*(x/base - 1))
    end

    # 3) Simula as 5 politicas fixas (deterministico, w_proc = media SDDP por dia)
    println("\n[$(uppercase(mes))] simulando 5 politicas fixas (deterministico, w_proc=media SDDP)...")
    sims_4pol = Dict{String,Any}("SDDP" => sims_sddp)
    for (nome, x) in zip(pol_fixas_nomes, Xs)
        sims_4pol[nome] = simular_fixa(x, w_proc_medio_diario, N_SIM)
    end

    # 4) Indicadores das 6 politicas (SDDP ja calculado acima — reaproveita)
    ind_4pol = Dict{String,Any}("SDDP" => ind_sddp)
    for pol in pol_fixas_nomes
        ind_4pol[pol] = calcular_indicadores(sims_4pol[pol], pol)
    end

    # SDDP no CENARIO MEDIO determinisitico (w_proc fixo = media SDDP por dia)
    # Mesmo cenario usado pelas politicas fixas — comparacao 100% justa.
    # Esta sim e' usada nas tabelas do terminal e no grafico de custo acumulado.
    sim_sddp_cen_medio = gerar_csv_sddp_cenario_medio(mes, model, w_proc_medio_diario)

    gerar_tabelas_terminal(mes, sims_4pol, ind_4pol, sim_sddp_cen_medio)
    gerar_csvs(mes, sims_4pol, ind_4pol)

    series = construir_series(sims_4pol, sim_sddp_cen_medio)
    gerar_csv_dia_a_dia(mes, series)
    gerar_csv_replica_qualquer(mes, sims_sddp, 42)  # replica arbitraria r=42

    return ind_4pol
end

"""
    gerar_csv_sddp_cenario_medio(mes, model, w_proc_medio_diario) -> nothing

Simula UMA trajetoria do SDDP no CENARIO MEDIO DETERMINISTICO:
  w_proc[t] = mean(w_proc(SDDP), dias 1..30 das 1000 sims)

Usa SDDP.Historical sampling scheme para forcar w_proc na sequencia exata.
Resultado: trajetoria do SDDP onde Spill = max(0, FilaFim-1200) bate exato
(valores nativos do modelo, sem agregacao estocastica). MESMO cenario que
as politicas fixas usam — comparacao 100% justa.

Saida: v8_<mes>_sddp_cenario_medio.csv
"""
function gerar_csv_sddp_cenario_medio(mes::String, model, w_proc_medio_diario::Vector{Float64})
    # Cria scheme historico: forca w_proc fixo por estagio
    # Sintaxe SDDP.jl: cada tupla = (node_index, noise_value)
    historical = SDDP.Historical([
        (t, w_proc_medio_diario[t]) for t in 1:NUM_DIAS
    ])

    sims = SDDP.simulate(
        model, 1,
        [:fila, :admitidos, :processados, :spillover, :ocioso, :w_proc];
        sampling_scheme = historical,
    )
    sim = sims[1]

    df = DataFrame(
        dia      = collect(1:NUM_DIAS),
        fila_in  = [sim[t][:fila].in       for t in 1:NUM_DIAS],
        adm_in   = [sim[t][:admitidos].in  for t in 1:NUM_DIAS],
        w_proc   = [sim[t][:w_proc]        for t in 1:NUM_DIAS],
        proc     = [sim[t][:processados]   for t in 1:NUM_DIAS],
        fila_out = [sim[t][:fila].out      for t in 1:NUM_DIAS],
        spill    = [sim[t][:spillover]     for t in 1:NUM_DIAS],
        ocioso   = [sim[t][:ocioso]        for t in 1:NUM_DIAS],
        adm_out  = [sim[t][:admitidos].out for t in 1:NUM_DIAS],
        custo    = [sim[t][:stage_objective] for t in 1:NUM_DIAS],
    )
    CSV.write(joinpath(CSVS_DIR, "v8_$(mes)_sddp_cenario_medio.csv"), df)
    @printf("  CSV SDDP cenario medio salvo: v8_%s_sddp_cenario_medio.csv\n", mes)
    return sim
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
