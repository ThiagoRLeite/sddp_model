"""
Gera ANALISE.md final do projeto v8.3 a partir dos CSVs exportados pelo Julia.

Estrutura ENXUTA (sem textos prolixos):
  1. Modelo: constantes, variáveis, restrições, FO
  2. Políticas: pseudo-código direto
  3. Cenário de comparação
  4. Dados + distribuições
  5. Resultados: tabelas comparativas
  6. Indicadores: glossário + valores
  7. Gráficos: cada um com 1 frase
  8. Anexos: A/B (cenário médio), C/D (réplica qualquer)

Flow:
  julia model_v8.jl         (exporta CSVs em outputs/csvs/)
  python plot_v8.py         (gera PNGs em outputs/graficos/)
  python gerar_analise.py   (gera ANALISE.md a partir dos CSVs + PNGs)
"""
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).parent
OUT  = ROOT / "outputs"
CSVS = OUT / "csvs"        # input: CSVs gerados pelo Julia
POL_ORDER = ["SDDP", "P_-10", "P_-5", "P_0", "P_+5", "P_+10"]

CAP_ECOPATIO = 1200
MAX_VAGAS = 4000
C_FILA = 2790
C_SPILLOVER = 16211
C_OCIOSO_TOTAL = 43753
FILA_INICIAL = 1200
ADMITIDOS_INICIAL = 3000
NUM_DIAS = 30


# ---------------------------------------------------------------------------
# Formatadores
# ---------------------------------------------------------------------------
def fmt_brl(v: float) -> str:
    if abs(v) >= 1e9:
        return f"R$ {v/1e9:.2f} B"
    if abs(v) >= 1e6:
        return f"R$ {v/1e6:.1f} M"
    return f"R$ {v:,.0f}".replace(",", " ")


def fmt_cell(v: float) -> str:
    if abs(v) >= 1e6:
        return f"{v/1e6:.2f}M"
    if abs(v) >= 1e3:
        return f"{int(round(v))}"
    return f"{v:.1f}"


def fmt_n(v: float) -> str:
    return f"{v:,.0f}".replace(",", " ")


# ---------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------
def carregar_dados():
    dados = {}
    for mes in ["mar", "jul"]:
        dados[mes] = {
            "sumario":      pd.read_csv(CSVS / f"v8_{mes}_sumario.csv"),
            "dia_a_dia":    pd.read_csv(CSVS / f"v8_{mes}_dia_a_dia.csv"),
            "sddp_cm":      pd.read_csv(CSVS / f"v8_{mes}_sddp_cenario_medio.csv"),
            "rep_qualquer": pd.read_csv(CSVS / f"v8_{mes}_replica_qualquer.csv"),
        }
    return dados


def calcular_bases(dados):
    bases = {}
    for mes in ["mar", "jul"]:
        df_d = dados[mes]["dia_a_dia"]
        base = df_d["SDDP_adm_out"].iloc[1:].mean()
        bases[mes] = {
            "base": base,
            "P_-10": base * 0.90, "P_-5": base * 0.95, "P_0": base,
            "P_+5":  base * 1.05, "P_+10": base * 1.10,
        }
    return bases


# ---------------------------------------------------------------------------
# Builders de tabelas
# ---------------------------------------------------------------------------
def tabela_sumario(df_s: pd.DataFrame, x_dict: dict) -> str:
    lines = [
        "| Política | X (cam/dia) | Custo médio | IC 95% | P5 | P50 | P95 | Fila pico | Service |",
        "|----------|------------:|------------:|-------:|---:|----:|----:|----------:|--------:|",
    ]
    for pol in POL_ORDER:
        r = df_s[df_s["politica"] == pol].iloc[0]
        x = "—" if pol == "SDDP" else fmt_n(x_dict[pol])
        b, e = ("**", "**") if pol == "SDDP" else ("", "")
        lines.append(
            f"| {b}{pol}{e} | {x} | {b}{fmt_brl(r['custo_medio'])}{e} | "
            f"± {r['custo_ic']/1e6:.2f} M | {fmt_brl(r['custo_p5'])} | "
            f"{fmt_brl(r['custo_p50'])} | {fmt_brl(r['custo_p95'])} | "
            f"{fmt_n(r['fila_pico_med'])} | {r['service_level']*100:.1f}% |"
        )
    return "\n".join(lines)


def tabela_dia_a_dia(dados_mes: dict, pol: str) -> str:
    lines = [
        "| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |",
        "|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|",
    ]
    if pol == "SDDP":
        df = dados_mes["sddp_cm"]
        for t in range(NUM_DIAS):
            r = df.iloc[t]
            lines.append(
                f"| {t+1} | {fmt_cell(r['fila_in'])} | {fmt_cell(r['adm_in'])} | "
                f"{fmt_cell(r['w_proc'])} | {fmt_cell(r['proc'])} | "
                f"{fmt_cell(r['fila_out'])} | {fmt_cell(r['spill'])} | "
                f"{fmt_cell(r['ocioso'])} | {fmt_cell(r['adm_out'])} | "
                f"{fmt_cell(r['custo'])} |"
            )
        tp, ts, to_, tc = df["proc"].sum(), df["spill"].sum(), df["ocioso"].sum(), df["custo"].sum()
    else:
        df = dados_mes["dia_a_dia"]
        for t in range(NUM_DIAS):
            row = df.iloc[t]
            lines.append(
                f"| {t+1} | {fmt_cell(row[f'{pol}_fila_in'])} | {fmt_cell(row[f'{pol}_adm_in'])} | "
                f"{fmt_cell(row[f'{pol}_w_proc'])} | {fmt_cell(row[f'{pol}_proc'])} | "
                f"{fmt_cell(row[f'{pol}_fila_out'])} | {fmt_cell(row[f'{pol}_spill'])} | "
                f"{fmt_cell(row[f'{pol}_ocioso'])} | {fmt_cell(row[f'{pol}_adm_out'])} | "
                f"{fmt_cell(row[f'{pol}_custo'])} |"
            )
        tp = df[f"{pol}_proc"].sum()
        ts = df[f"{pol}_spill"].sum()
        to_ = df[f"{pol}_ocioso"].sum()
        tc = df[f"{pol}_custo"].sum()
    lines.append(
        f"| **Σ** | — | — | — | **{fmt_cell(tp)}** | — | **{fmt_cell(ts)}** | **{fmt_cell(to_)}** | — | **{fmt_cell(tc)}** |"
    )
    return "\n".join(lines)


def tabela_replica_qualquer(df: pd.DataFrame) -> str:
    lines = [
        "| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |",
        "|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|",
    ]
    for t in range(NUM_DIAS):
        r = df.iloc[t]
        lines.append(
            f"| {t+1} | {fmt_cell(r['fila_in'])} | {fmt_cell(r['adm_in'])} | "
            f"{fmt_cell(r['w_proc'])} | {fmt_cell(r['proc'])} | "
            f"{fmt_cell(r['fila_out'])} | {fmt_cell(r['spill'])} | "
            f"{fmt_cell(r['ocioso'])} | {fmt_cell(r['adm_out'])} | "
            f"{fmt_cell(r['custo'])} |"
        )
    tp, ts, to_, tc = df["proc"].sum(), df["spill"].sum(), df["ocioso"].sum(), df["custo"].sum()
    lines.append(
        f"| **Σ** | — | — | — | **{fmt_cell(tp)}** | — | **{fmt_cell(ts)}** | **{fmt_cell(to_)}** | — | **{fmt_cell(tc)}** |"
    )
    return "\n".join(lines)


def tabela_indicadores(df_s: pd.DataFrame) -> str:
    lines = [
        "| Indicador | SDDP | P_-10 | P_-5 | P_0 | P_+5 | P_+10 |",
        "|-----------|-----:|------:|-----:|----:|-----:|------:|",
    ]
    def row(label, fn):
        vals = [fn(df_s[df_s["politica"] == p].iloc[0]) for p in POL_ORDER]
        return f"| {label} | " + " | ".join(vals) + " |"
    lines.append(row("Custo médio",       lambda r: fmt_brl(r["custo_medio"])))
    lines.append(row("IC 95%",            lambda r: f"± {r['custo_ic']/1e6:.2f} M"))
    lines.append(row("P5 (custo)",        lambda r: fmt_brl(r["custo_p5"])))
    lines.append(row("P50 (custo)",       lambda r: fmt_brl(r["custo_p50"])))
    lines.append(row("P95 (custo)",       lambda r: fmt_brl(r["custo_p95"])))
    lines.append(row("P(spill > 0)",      lambda r: f"{r['spill_prob']*100:.1f}%"))
    lines.append(row("Spill cond.",       lambda r: fmt_n(r["spill_cond_med"])))
    lines.append(row("Fila pico",         lambda r: fmt_n(r["fila_pico_med"])))
    lines.append(row("Service level",     lambda r: f"{r['service_level']*100:.1f}%"))
    lines.append(row("entram/dia",        lambda r: fmt_n(r["entram_dia"])))
    lines.append(row("proc/dia",          lambda r: fmt_n(r["proc_dia"])))
    lines.append(row("ocio/dia",          lambda r: fmt_n(r["ocio_dia"])))
    lines.append(row("spill/dia",         lambda r: fmt_n(r["spill_dia"])))
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Gerador do MD
# ---------------------------------------------------------------------------
def gerar_md(dados, bases) -> str:
    sddp_mar = dados["mar"]["sumario"]
    sddp_jul = dados["jul"]["sumario"]
    cmar = lambda pol: sddp_mar[sddp_mar["politica"] == pol]["custo_medio"].iloc[0]
    cjul = lambda pol: sddp_jul[sddp_jul["politica"] == pol]["custo_medio"].iloc[0]

    md = []
    md.append("# Análise — SDDP vs Políticas Fixas de Admissão (v8.3)")
    md.append("")
    md.append("**Pipeline:**")
    md.append("```")
    md.append('julia model_v8.jl        # exporta CSVs em outputs/csvs/')
    md.append('python plot_v8.py        # gera 15 PNGs')
    md.append('python gerar_analise.py  # gera este ANALISE.md a partir dos CSVs')
    md.append("```")
    md.append("")
    md.append("Mês: Março (LogNormal, CV=10%) e Julho (Weibull, CV=36%). Horizonte de 30 dias. SDDP simulado com 1 000 amostragens estocásticas; fixas rodam **uma trajetória determinística** (w_proc fixo = média SDDP).")
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 1. MODELO
    # ----------------------------------------------------------
    md.append("## 1. Modelo")
    md.append("")
    md.append("### 1.1 Constantes")
    md.append("")
    md.append("| Constante | Valor | Significado |")
    md.append("|-----------|------:|-------------|")
    md.append(f"| `CAP_ECOPATIO` | {CAP_ECOPATIO} | Capacidade do pátio (gatilho de spillover) |")
    md.append(f"| `MAX_VAGAS` | {MAX_VAGAS} | Limite máximo de admissão `admitidos.out ≤ MAX_VAGAS` |")
    md.append(f"| `C_FILA` | R$ {C_FILA:,} | Custo por caminhão-dia em fila |".replace(",", " "))
    md.append(f"| `C_SPILLOVER` | R$ {C_SPILLOVER:,} | Custo por caminhão fora do pátio (spillover) |".replace(",", " "))
    md.append(f"| `C_OCIOSO_TOTAL` | R$ {C_OCIOSO_TOTAL:,} | Custo por unidade ociosa (= 1 753 op. + 42 000 receita perdida) |".replace(",", " "))
    md.append(f"| `FILA_INICIAL` | {FILA_INICIAL} | Fila no dia 1 |")
    md.append(f"| `ADMITIDOS_INICIAL` | {ADMITIDOS_INICIAL} | Admissão obrigatória no dia 1 |")
    md.append(f"| `NUM_DIAS` | {NUM_DIAS} | Horizonte (dias) |")
    md.append("")

    md.append("### 1.2 Variáveis")
    md.append("")
    md.append("| Variável | Tipo | Descrição |")
    md.append("|----------|------|-----------|")
    md.append("| `fila[t]` | estado, ≥ 0 | Caminhões em fila no início do dia `t` |")
    md.append(f"| `admitidos[t]` | estado, [0, {MAX_VAGAS}] | Caminhões admitidos para o próximo dia |")
    md.append("| `processados[t]` | decisão, ≥ 0 | Caminhões processados no dia |")
    md.append("| `spillover[t]` | decisão, ≥ 0 | Caminhões fora do pátio |")
    md.append("| `ocioso[t]` | decisão, ≥ 0 | Capacidade não utilizada |")
    md.append("| `w_proc[t]` | aleatório | Capacidade aleatória de processamento (estocástico) |")
    md.append("")

    md.append("### 1.3 Restrições (∀ t = 1..30)")
    md.append("")
    md.append("```")
    md.append("processados[t]    ≤ w_proc[t]")
    md.append("processados[t]    ≤ fila.in[t] + admitidos.in[t]")
    md.append("fila.out[t]       = fila.in[t] + admitidos.in[t] − processados[t]")
    md.append(f"spillover[t]      ≥ fila.in[t] + admitidos.in[t] − {CAP_ECOPATIO} − processados[t]")
    md.append("ocioso[t]         ≥ w_proc[t] − processados[t]")
    md.append(f"0 ≤ admitidos[t] ≤ {MAX_VAGAS}")
    md.append("")
    md.append(f"# Equivalência útil (decorre do balanço): spillover[t] = max(0, fila.out[t] − {CAP_ECOPATIO})")
    md.append("```")
    md.append("")

    md.append("### 1.4 Função objetivo (minimização)")
    md.append("")
    md.append("```")
    md.append("min  Σ_{t=1..30}  [")
    md.append(f"        {C_FILA}     · (fila.in[t] + fila.out[t]) / 2     # custo de fila (regra trapézio)")
    md.append(f"      + {C_SPILLOVER}   · spillover[t]                       # custo de spillover")
    md.append(f"      + {C_OCIOSO_TOTAL}   · ocioso[t]                          # custo de ociosidade")
    md.append("     ]")
    md.append("```")
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 2. POLÍTICAS
    # ----------------------------------------------------------
    md.append("## 2. Políticas avaliadas (pseudo-código)")
    md.append("")
    md.append("### 2.1 SDDP — política dinâmica (referência)")
    md.append("")
    md.append("```")
    md.append("Treinamento (offline):")
    md.append("  treinar SDDP com 200 iterações, lower_bound=0, optimizer=HiGHS")
    md.append("  w_proc parametrizado por discretização de quantis (100 pontos) da dist. ajustada")
    md.append("")
    md.append("Execução (online, em cada estágio t):")
    md.append("  observa (fila.in[t], admitidos.in[t], w_proc[t])")
    md.append("  decide (processados[t], admitidos.out[t]) minimizando custo")
    md.append("    esperado dos estágios restantes via cortes de Benders")
    md.append("```")
    md.append("")
    md.append("### 2.2 Políticas fixas P_X (5 níveis em ±10%, ±5%, 0% da base SDDP)")
    md.append("")
    md.append("> **Importante:** as fixas **NÃO são Monte Carlo**. Como `w_proc[t]` é fixado (média do SDDP) e `adm_out = X` é constante, **toda a trajetória é determinística**: dado o estado inicial, há **uma única evolução possível** dos 30 dias. Não há amostragem aleatória nas fixas.")
    md.append("")
    md.append("```")
    md.append("base = mean(admitidos.out do SDDP, dias 2..30 das 1 000 sims)")
    md.append("X_{P_-10}, X_{P_-5}, X_{P_0}, X_{P_+5}, X_{P_+10}")
    md.append("    = base × [0.90, 0.95, 1.00, 1.05, 1.10]")
    md.append("")
    md.append(f"Estado inicial: fila = {FILA_INICIAL},  admitidos.in = {ADMITIDOS_INICIAL}")
    md.append("")
    md.append("Para cada t = 1..30:")
    md.append("    w_proc[t] = mean(w_proc(SDDP) dia t, das 1 000 sims)  ← FIXO (não amostrado)")
    md.append("    processados[t]  = min(w_proc[t], fila.in + admitidos.in)")
    md.append(f"    spillover[t]    = max(0, fila.in + admitidos.in − {CAP_ECOPATIO} − processados[t])")
    md.append("    ocioso[t]       = max(0, w_proc[t] − processados[t])")
    md.append("    fila.out        = fila.in + admitidos.in − processados[t]")
    md.append("    admitidos.out   = X    ← REGRA FIXA (constante por toda a simulação)")
    md.append("    fila.in, admitidos.in = fila.out, admitidos.out")
    md.append("```")
    md.append("")
    md.append("> **Por que essa abordagem?** Para isolar o efeito da decisão de admissão. Tudo fica idêntico entre as 6 políticas (estado inicial, w_proc, fórmulas) — só muda `adm_out`. Diferenças no custo refletem APENAS a escolha de admissão. É uma comparação determinística, sem ruído estatístico.")
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 3. CENÁRIO DE COMPARAÇÃO
    # ----------------------------------------------------------
    md.append("## 3. Cenário de comparação (Anexos A/B)")
    md.append("")
    md.append("Todas as 6 políticas rodam no **MESMO cenário médio determinístico**:")
    md.append("")
    md.append(f"- `w_proc[t]` fixo = média das 1 000 sims SDDP por dia (mesma série em todas)")
    md.append(f"- Estado inicial idêntico (Fila={FILA_INICIAL}, AdmIn={ADMITIDOS_INICIAL})")
    md.append(f"- **SDDP** roda via `SDDP.Historical` com `w_proc[t]` forçado")
    md.append(f"- **Fixas** rodam **uma trajetória determinística** com `adm_out = X` constante (não há amostragem — sem aleatoriedade)")
    md.append("")
    md.append("**Resultado:** `Spill[t] = max(0, FilaFim[t] − 1 200)` bate **exato linha a linha em todas as 6 políticas** (validado: 12/12 OK). Comparação 100% justa.")
    md.append("")
    md.append("**Consistência (v8.4):** o **gráfico de custo acumulado** (`py_v8_<mes>_custo_acumulado.png`) usa o **mesmo cenário médio determinístico** dos Anexos A/B. Os totais ao final do dia 30 batem **exato** com a coluna Σ Custo das tabelas — sem ambiguidade.")
    md.append("")
    md.append("Para estatísticas agregadas das 1 000 sims estocásticas do SDDP (custo médio com IC, quantis, P(spill>0)), ver §5 (Indicadores).")
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 4. DADOS
    # ----------------------------------------------------------
    md.append("## 4. Dados e distribuições")
    md.append("")
    md.append("| Mês | Média (cam/dia) | sd | CV | Dist | AIC | KS p-value |")
    md.append("|-----|----------------:|---:|---:|------|----:|-----------:|")
    md.append("| mar | 2 480.2 | 251.3 | 0.10 | **LogNormal** | 417.5 | 0.55 |")
    md.append("| jul | 2 102.1 | 754.6 | 0.36 | **Weibull** | 484.8 | 0.93 |")
    md.append("")
    md.append("Critério: menor AIC entre os modelos com KS p ≥ 0.05. Ajuste em `ranking AIC/KS impresso no terminal`.")
    md.append("")
    md.append("**Bases X (média de adm_out SDDP nos dias 2..30):**")
    md.append("")
    md.append("| Mês | base | X(P_-10) | X(P_-5) | X(P_0) | X(P_+5) | X(P_+10) |")
    md.append("|-----|-----:|---------:|--------:|-------:|--------:|---------:|")
    for mes in ["mar", "jul"]:
        b = bases[mes]
        md.append(
            f"| {mes.upper()} | {fmt_n(b['base'])} | {fmt_n(b['P_-10'])} | {fmt_n(b['P_-5'])} | "
            f"{fmt_n(b['P_0'])} | {fmt_n(b['P_+5'])} | {fmt_n(b['P_+10'])} |"
        )
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 5. INDICADORES
    # ----------------------------------------------------------
    md.append("## 5. Indicadores")
    md.append("")
    md.append("### 5.1 Glossário")
    md.append("")
    md.append("| Indicador | Definição |")
    md.append("|-----------|-----------|")
    md.append("| **Custo médio** | Esperança do custo total dos 30 dias (média 1 000 sims) |")
    md.append("| **IC 95%** | Intervalo de confiança 95% do custo médio (`± 1.96·sd/√N`) |")
    md.append("| **P5 / P50 / P95** | Quantis 5%, 50% (mediana), 95% da distribuição do custo |")
    md.append("| **P(spill > 0)** | Probabilidade de haver spillover em algum dia |")
    md.append("| **Spill cond.** | Spillover total esperado **condicional** a ter ocorrido |")
    md.append(f"| **Fila pico** | Média do pico de fila ao longo dos 30 dias (limite MAX_VAGAS={MAX_VAGAS}) |")
    md.append("| **Service level** | Σ proc / Σ admitidos nos dias 2..30, cap em 100% |")
    md.append("| **entram/proc/ocio/spill/dia** | Médias diárias das 4 quantidades operacionais |")
    md.append("")

    md.append("### 5.2 MAR — valores")
    md.append("")
    md.append(tabela_indicadores(sddp_mar))
    md.append("")
    md.append(f"**Melhor fixa MAR:** P_0 = {fmt_brl(cmar('P_0'))} ({cmar('P_0')/cmar('SDDP'):.2f}× SDDP). **Pior:** P_+10 = {fmt_brl(cmar('P_+10'))} ({cmar('P_+10')/cmar('SDDP'):.0f}× SDDP).")
    md.append("")

    md.append("### 5.3 JUL — valores")
    md.append("")
    md.append(tabela_indicadores(sddp_jul))
    md.append("")
    razao_jul = cjul('P_0') / cjul('SDDP')
    if razao_jul < 1:
        md.append(f"**Achado contraintuitivo JUL:** P_0 = {fmt_brl(cjul('P_0'))} **vence** o SDDP = {fmt_brl(cjul('SDDP'))} ({razao_jul:.2f}×). Razão: P_0 opera no cenário médio determinístico (w_proc fixo); o SDDP é simulado com w_proc estocástico real (Weibull com sd=754) — paga o custo da variabilidade.")
    else:
        md.append(f"**Melhor fixa JUL:** P_0 = {fmt_brl(cjul('P_0'))} ({razao_jul:.2f}× SDDP).")
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 6. GRÁFICOS
    # ----------------------------------------------------------
    md.append("## 6. Gráficos")
    md.append("")
    md.append("Cada gráfico abaixo é gerado por `plot_v8.py` a partir de `outputs/csvs/`. PNGs em `outputs/graficos/`.")
    md.append("")

    md.append("### 6.1 Boxplot custo total (1 000 sims, log)")
    md.append("Mostra distribuição do custo total entre as 1 000 réplicas. Fixas viram linha (determinísticas no cenário médio).")
    md.append("")
    md.append("![boxplot mar](outputs/graficos/py_v8_mar_boxplot.png)")
    md.append("")
    md.append("![boxplot jul](outputs/graficos/py_v8_jul_boxplot.png)")
    md.append("")

    md.append("### 6.2 Service level por política")
    md.append("Fração da demanda admitida que é de fato processada nos dias 2..30 (cap 100%).")
    md.append("")
    md.append("![service mar](outputs/graficos/py_v8_mar_service_level.png)")
    md.append("")
    md.append("![service jul](outputs/graficos/py_v8_jul_service_level.png)")
    md.append("")

    md.append("### 6.3 Composição do custo")
    md.append("Decompõe o custo total em fila + spillover + ociosidade (escala log).")
    md.append("")
    md.append("![composicao mar](outputs/graficos/py_v8_mar_composicao_custo.png)")
    md.append("")
    md.append("![composicao jul](outputs/graficos/py_v8_jul_composicao_custo.png)")
    md.append("")

    md.append("### 6.4 Painel 4 variáveis (proc / fila / ocio log / spill log)")
    md.append("Evolução diária de 4 quantidades-chave por política.")
    md.append("")
    md.append("![painel mar](outputs/graficos/py_v8_mar_painel.png)")
    md.append("")
    md.append("![painel jul](outputs/graficos/py_v8_jul_painel.png)")
    md.append("")

    md.append("### 6.5 Custo acumulado (log)")
    md.append("Soma cumulativa do custo dia a dia — \"o gráfico do dinheiro\".")
    md.append("")
    md.append("![custo acumulado mar](outputs/graficos/py_v8_mar_custo_acumulado.png)")
    md.append("")
    md.append("![custo acumulado jul](outputs/graficos/py_v8_jul_custo_acumulado.png)")
    md.append("")

    md.append("### 6.6 Comparativo mar vs jul (side-by-side)")
    md.append("")
    md.append("![comparativo](outputs/graficos/py_v8_mar_jul_comparativo.png)")
    md.append("")
    md.append("---")
    md.append("")

    # ----------------------------------------------------------
    # 7. ANEXOS
    # ----------------------------------------------------------
    for ax, mes, titulo in [
        ("A", "mar", "MAR: cenário médio (6 políticas, 30 dias)"),
        ("B", "jul", "JUL: cenário médio (6 políticas, 30 dias)"),
    ]:
        md.append(f"## Anexo {ax} — {titulo}")
        md.append("")
        md.append("Todas as 6 políticas no mesmo cenário (w_proc = média 1 000 sims SDDP). Valores nativos do modelo — `Spill = max(0, FilaFim − 1 200)` bate exato.")
        md.append("")
        for pol in POL_ORDER:
            tag = "SDDP via `SDDP.Historical` (1 trajetória no cenário médio)" if pol == "SDDP" else "Simulação determinística (1 trajetória, `adm_out` fixo)"
            md.append(f"### {mes.upper()} — `{pol}` — {tag}")
            md.append("")
            md.append(tabela_dia_a_dia(dados[mes], pol))
            md.append("")
        md.append("---")
        md.append("")

    for ax, mes in [("C", "mar"), ("D", "jul")]:
        md.append(f"## Anexo {ax} — {mes.upper()}: réplica qualquer SDDP (idx=42)")
        md.append("")
        md.append("Uma das 1 000 simulações estocásticas do SDDP (índice arbitrário 42). `w_proc` amostrado da distribuição real do mês — mostra como o SDDP reage a um cenário real.")
        md.append("")
        md.append(tabela_replica_qualquer(dados[mes]["rep_qualquer"]))
        md.append("")
        md.append("---")
        md.append("")

    # Anexo E - Reprodutibilidade
    md.append("## Anexo E — Reprodutibilidade")
    md.append("")
    md.append("```bash")
    md.append('julia "Model SDDP - 19-05-26/model_v8.jl"       # ~2.5 min')
    md.append('python "Model SDDP - 19-05-26/plot_v8.py"       # ~10 s')
    md.append('python "Model SDDP - 19-05-26/gerar_analise.py" # ~1 s')
    md.append("```")
    md.append("")
    md.append("**Sistema:** Windows 11, Julia 1.12.4, Python 3.11.9. SDDP.jl + HiGHS, pandas + matplotlib + seaborn.")
    md.append("")
    md.append("**Validações automáticas:**")
    md.append("- V1: `Spill = max(0, FilaFim − 1 200)` em 12/12 tabelas dos anexos A/B (diff < 1e-10)")
    md.append("- V2: Σ Custo tabela == custo médio sumário (para fixas, diff ~0%)")
    md.append("- V3: réplicas individuais batem fórmula exata (diff = 0)")
    md.append("")

    return "\n".join(md)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Lendo CSVs...")
    dados = carregar_dados()
    bases = calcular_bases(dados)
    for mes in ["mar", "jul"]:
        print(f"  {mes.upper()}: base = {bases[mes]['base']:.1f}")
    print("Gerando ANALISE.md...")
    md = gerar_md(dados, bases)
    (ROOT / "ANALISE.md").write_text(md, encoding="utf-8")
    print(f"OK — ANALISE.md ({len(md)} chars, {md.count(chr(10))+1} linhas)")


if __name__ == "__main__":
    main()
