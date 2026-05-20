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

"""
    plot_fit(mes::String, data::Vector{Float64}, ranking)

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

Monte Carlo da politica fixa "processar X constante (clip por w_proc e fila+adm)".
NOVA REGRA (v8.3): w_proc dia a dia e' FIXO = media do SDDP no mesmo dia.
Politica fixa fica DETERMINISTICA — todas as N replicas sao identicas.
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
    gerar_tabelas_terminal(mes::String, sims_4pol::Dict, ind_4pol::Dict)

Imprime 3 tabelas no terminal: A (sumario), B (dia-a-dia), C (replica representativa).
Espera dicts com chaves POL_ORDER.
"""
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

"""
    gerar_pngs(mes::String, ind_4pol::Dict)

Gera 3 PNGs em OUTPUT_DIR: boxplot do custo, ECDF do custo, barras de indicadores.
"""
function gerar_pngs(mes::String, ind_4pol::Dict)
    default(legend = :topright, size = (1000, 600))

    # 1) Boxplot custo total (escala log) — usar posicoes numericas + xticks
    #    para preservar a ordem do POL_ORDER (boxplot por string ordena alfa).
    pos_flat = reduce(vcat,
        [fill(i, length(ind_4pol[pol].custos)) for (i, pol) in enumerate(POL_ORDER)])
    custos_flat = reduce(vcat, [ind_4pol[pol].custos for pol in POL_ORDER])
    p_box = boxplot(
        pos_flat, custos_flat;
        legend = false,
        title = "$(uppercase(mes)) — Custo total das $N_SIM simulacoes (escala log)",
        ylabel = "Custo total (R\$, log10)",
        yscale = :log10,
        xticks = (1:length(POL_ORDER), POL_ORDER),
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

    # 3) Barras agrupadas de indicadores (FilaPico/MAX_VAGAS pode passar de 1.0
    #     nas politicas fixas — indica violacao do limite de patio MAX_VAGAS)
    metrics = ["Spill%>0", "FilaPico/MAX_VAGAS", "ServLvl"]
    vals = zeros(length(metrics), length(POL_ORDER))
    for (j, pol) in enumerate(POL_ORDER)
        i = ind_4pol[pol]
        vals[:, j] = [i.spill_prob, i.fila_pico_med / MAX_VAGAS, i.service_level]
    end
    p_bar = groupedbar(
        metrics, vals;
        bar_position = :dodge,
        title = "$(uppercase(mes)) — Indicadores normalizados (FilaPico>1 = estourou patio)",
        ylabel = "Valor (0..1, exceto FilaPico se >1)",
        label = reshape(POL_ORDER, 1, :),
    )
    out_bar = joinpath(OUTPUT_DIR, "v8_$(mes)_indicadores_bar.png")
    savefig(p_bar, out_bar)

    @printf("  PNGs salvos: %s, %s, %s\n",
        basename(out_box), basename(out_ecdf), basename(out_bar))
end

"""
    gerar_pngs_evolucao(mes::String, sims_4pol::Dict)

Gera 6 PNGs de evolucao dia-a-dia (media nas 1000 sims, 1 linha por politica):
- v8_<mes>_proc_dia.png       — processados/dia (linear)
- v8_<mes>_ocioso_dia.png     — ocioso/dia (log)
- v8_<mes>_spillover_dia.png  — spillover/dia (log)
- v8_<mes>_fila_dia.png       — fila.out/dia (linear)
- v8_<mes>_custo_dia.png      — stage_objective/dia (log)
- v8_<mes>_custo_acumulado.png— soma cumulativa do custo (log)
"""
function gerar_pngs_evolucao(mes::String, sims_4pol::Dict)
    default(legend = :outerright, size = (1100, 600))
    dias = collect(1:NUM_DIAS)

    function _medias_dia(sims, key, in_or_out=nothing)
        return [
            mean(in_or_out === nothing ? sim[t][key] : getproperty(sim[t][key], in_or_out)
                 for sim in sims)
            for t in dias
        ]
    end

    # series[pol][var] = vetor de 30 medias
    series = Dict{String,Any}()
    for pol in POL_ORDER
        sims = sims_4pol[pol]
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
        series[pol][:custo_acum] = cumsum(series[pol][:custo])
    end

    plotar = function(var::Symbol, ylab, fname, logy::Bool)
        p = plot(title = "$(uppercase(mes)) — $ylab (media 1000 sims)",
                 xlabel = "Dia", ylabel = ylab,
                 yscale = logy ? :log10 : :identity)
        for pol in POL_ORDER
            y = series[pol][var]
            # para escala log, evita zero
            ylog = logy ? max.(y, 1e-3) : y
            plot!(p, dias, ylog, lw = pol == "SDDP" ? 3 : 2,
                  label = pol, marker = pol == "SDDP" ? :circle : :none, ms = 3)
        end
        savefig(p, joinpath(OUTPUT_DIR, "v8_$(mes)_$(fname).png"))
    end

    plotar(:proc,       "Processados / dia",          "proc_dia",        false)
    plotar(:ocioso,     "Ocioso / dia",               "ocioso_dia",      true)
    plotar(:spill,      "Spillover / dia",            "spillover_dia",   true)
    plotar(:fila_out,   "Fila ao fim do dia",         "fila_dia",        false)
    plotar(:custo,      "Custo / dia (R\$)",          "custo_dia",       true)
    plotar(:custo_acum, "Custo acumulado (R\$)",      "custo_acumulado", true)

    @printf("  PNGs evolucao salvos: v8_%s_{proc_dia,ocioso_dia,spillover_dia,fila_dia,custo_dia,custo_acumulado}.png\n", mes)
    return series
end

"""
    gerar_csv_dia_a_dia(mes::String, series::Dict) -> nothing

CSV com medias dia-a-dia (30 linhas) das variaveis para cada politica.

NOTA IMPORTANTE — para o SDDP (estocastico), recalculamos Spill, Ocioso e Custo
em cima das medias para que a tabela seja COERENTE LINHA-A-LINHA:
  Spill[t]  = max(0, FilaFim_media[t] - CAP_ECOPATIO)
  Ocioso[t] = max(0, w_proc_media[t]  - Proc_media[t])
  Custo[t]  = C_FILA*(FilaIni+FilaFim)/2 + C_SPILLOVER*Spill + C_OCIOSO_TOTAL*Ocioso

A media estocastica real de Spill (= mean(max(0, fila_out[r,t]-CAP)) entre 1000
replicas) pode ser maior que max(0, mean(fila_out) - CAP) por causa da
desigualdade de Jensen. O custo total reportado em §5.2 do ANALISE.md usa a
media estocastica real. Esta tabela usa a versao recalculada para coerencia
visual — a diferenca e' o "custo da variabilidade" capturado pelo modelo.

Para as politicas fixas P_-10..P_+10, sao deterministicas (w_proc fixo,
adm_out=X constante), entao os valores ja batem linha-a-linha sem recalculo.
"""
function gerar_csv_dia_a_dia(mes::String, series::Dict)
    df = DataFrame(dia = collect(1:NUM_DIAS))
    for pol in POL_ORDER
        fila_in  = copy(series[pol][:fila_in])
        adm_in   = copy(series[pol][:adm_in])
        w_proc   = copy(series[pol][:w_proc])
        proc     = copy(series[pol][:proc])
        fila_out = copy(series[pol][:fila_out])
        adm_out  = copy(series[pol][:adm_out])

        # Apenas SDDP precisa de recalculo (politicas fixas ja sao coerentes)
        if pol == "SDDP"
            spill  = [max(0.0, fila_out[t] - CAP_ECOPATIO) for t in 1:NUM_DIAS]
            ocioso = [max(0.0, w_proc[t]   - proc[t])      for t in 1:NUM_DIAS]
            custo  = [C_FILA * (fila_in[t] + fila_out[t]) / 2 +
                      C_SPILLOVER    * spill[t] +
                      C_OCIOSO_TOTAL * ocioso[t]            for t in 1:NUM_DIAS]
        else
            spill  = series[pol][:spill]
            ocioso = series[pol][:ocioso]
            custo  = series[pol][:custo]
        end
        custo_acum = cumsum(custo)

        df[!, Symbol("$(pol)_fila_in")]    = fila_in
        df[!, Symbol("$(pol)_adm_in")]     = adm_in
        df[!, Symbol("$(pol)_w_proc")]     = w_proc
        df[!, Symbol("$(pol)_proc")]       = proc
        df[!, Symbol("$(pol)_fila_out")]   = fila_out
        df[!, Symbol("$(pol)_spill")]      = spill
        df[!, Symbol("$(pol)_ocioso")]     = ocioso
        df[!, Symbol("$(pol)_adm_out")]    = adm_out
        df[!, Symbol("$(pol)_custo")]      = custo
        df[!, Symbol("$(pol)_custo_acum")] = custo_acum
    end
    CSV.write(joinpath(OUTPUT_DIR, "v8_$(mes)_dia_a_dia.csv"), df)
    @printf("  CSV dia-a-dia salvo: v8_%s_dia_a_dia.csv (SDDP com recalculo coerente)\n", mes)
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
    CSV.write(joinpath(OUTPUT_DIR, "v8_$(mes)_replica_qualquer.csv"), df)
    @printf("  CSV replica qualquer (idx=%d) salvo: v8_%s_replica_qualquer.csv\n", idx_repl, mes)
end

"""
    gerar_csvs(mes::String, sims_4pol::Dict, ind_4pol::Dict)

Gera 3 CSVs em OUTPUT_DIR:
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
    CSV.write(joinpath(OUTPUT_DIR, "v8_$(mes)_replica_repr.csv"), df_rep)

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
    plot_fit(mes, data, fit.ranking)

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

    gerar_tabelas_terminal(mes, sims_4pol, ind_4pol)
    gerar_pngs(mes, ind_4pol)
    gerar_csvs(mes, sims_4pol, ind_4pol)
    series = gerar_pngs_evolucao(mes, sims_4pol)
    gerar_csv_dia_a_dia(mes, series)
    gerar_csv_replica_qualquer(mes, sims_sddp, 42)  # replica arbitraria r=42

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
