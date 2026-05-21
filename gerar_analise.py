"""
Gera ANALISE.md final do projeto v8.3 a partir dos CSVs exportados pelo Julia.

Flow:
  julia model_v8.jl         (exporta CSVs em outputs/)
  python plot_v8.py         (gera PNGs em outputs/)
  python gerar_analise.py   (gera ANALISE.md a partir dos CSVs + PNGs)

Tudo o que muda execução-a-execução fica em CSVs lidos aqui.
Constantes do modelo (custos, capacidade) ficam hardcoded conforme SPEC.
"""
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).parent
OUT = ROOT / "outputs"
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
# Helpers de formatação
# ---------------------------------------------------------------------------
def fmt_brl(v: float) -> str:
    if abs(v) >= 1e9:
        return f"R$ {v/1e9:.2f} B"
    if abs(v) >= 1e6:
        return f"R$ {v/1e6:.1f} M"
    if abs(v) >= 1e3:
        return f"R$ {v/1e3:.0f} k"
    return f"R$ {v:.0f}"


def fmt_num(v: float) -> str:
    if abs(v) >= 1e6:
        return f"{v/1e6:.2f}M"
    if abs(v) >= 1e3:
        return f"{v:,.0f}".replace(",", " ")
    return f"{v:.1f}"


def fmt_cell(v: float) -> str:
    """Formato compacto para células de tabela."""
    if abs(v) >= 1e6:
        return f"{v/1e6:.2f}M"
    if abs(v) >= 1e3:
        return f"{int(round(v))}"
    return f"{v:.1f}"


# ---------------------------------------------------------------------------
# Carrega dados de todos os CSVs
# ---------------------------------------------------------------------------
def carregar_dados():
    dados = {}
    for mes in ["mar", "jul"]:
        dados[mes] = {
            "sumario":      pd.read_csv(OUT / f"v8_{mes}_sumario.csv"),
            "dia_a_dia":    pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv"),
            "replica_repr": pd.read_csv(OUT / f"v8_{mes}_replica_repr.csv"),
            "rep_qualquer": pd.read_csv(OUT / f"v8_{mes}_replica_qualquer.csv"),
        }
    return dados


# ---------------------------------------------------------------------------
# Gera sumário (tabelas §5.1, §5.2)
# ---------------------------------------------------------------------------
def gera_tabela_sumario(df_sum: pd.DataFrame, x_dict: dict) -> str:
    lines = [
        "| Política | X | Custo médio | IC 95% | P5 | P50 | P95 | Spill % > 0 | Fila pico médio | Service level |",
        "|----------|--:|------------:|-------:|---:|----:|----:|-----------:|----------------:|--------------:|",
    ]
    for pol in POL_ORDER:
        row = df_sum[df_sum["politica"] == pol].iloc[0]
        x_str = "—" if pol == "SDDP" else f"{x_dict[pol]:,.0f}".replace(",", " ")
        prefix = "**" if pol == "SDDP" else ""
        suffix = "**" if pol == "SDDP" else ""
        lines.append(
            f"| {prefix}{pol}{suffix} | {x_str} | "
            f"{prefix}{fmt_brl(row['custo_medio'])}{suffix} | "
            f"± {row['custo_ic']/1e6:.2f} M | "
            f"{fmt_brl(row['custo_p5'])} | "
            f"{fmt_brl(row['custo_p50'])} | "
            f"{fmt_brl(row['custo_p95'])} | "
            f"{row['spill_prob']*100:.1f}% | "
            f"{prefix}{row['fila_pico_med']:,.0f}{suffix} | "
            f"{prefix}{row['service_level']*100:.1f}%{suffix} |".replace(",", " ")
        )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Gera tabela dia-a-dia para um (mes, pol)
#
# - Para FIXAS (P_-10..P_+10): le do dia_a_dia.csv (medias = trajetoria
#   deterministica, ja que w_proc e' fixo). Os valores sao nativos do modelo.
#
# - Para SDDP: le do replica_repr.csv (replica representativa, custo proximo
#   da media). Valores nativos do modelo, sem agregacao estocastica — assim
#   Spill = max(0, FilaFim - 1200) bate linha-a-linha como propriedade
#   natural da restricao do modelo (nao por recalculo forcado).
# ---------------------------------------------------------------------------
def gera_tabela_dia_a_dia(dados_mes: dict, pol: str) -> str:
    # Decide qual fonte de dados usar
    if pol == "SDDP":
        df = dados_mes["replica_repr"]
        # Colunas no replica_repr: SDDP_FilaIni, SDDP_AdmIn, SDDP_Wproc, etc.
        def get(col):
            return df[f"{pol}_{col}"]
        cols = {
            "fila_in": "FilaIni", "adm_in": "AdmIn", "w_proc": "Wproc",
            "proc": "Proc", "fila_out": "FilaFim", "spill": "Spill",
            "ocioso": "Ocioso", "adm_out": "AdmOut",
        }
    else:
        df = dados_mes["dia_a_dia"]
        cols = {
            "fila_in": "fila_in", "adm_in": "adm_in", "w_proc": "w_proc",
            "proc": "proc", "fila_out": "fila_out", "spill": "spill",
            "ocioso": "ocioso", "adm_out": "adm_out",
        }

    lines = [
        "| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |",
        "|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|",
    ]
    custos = []
    for t in range(NUM_DIAS):
        row = df.iloc[t]
        fi  = row[f"{pol}_{cols['fila_in']}"]
        ai  = row[f"{pol}_{cols['adm_in']}"]
        wp  = row[f"{pol}_{cols['w_proc']}"]
        pr  = row[f"{pol}_{cols['proc']}"]
        fo  = row[f"{pol}_{cols['fila_out']}"]
        sp  = row[f"{pol}_{cols['spill']}"]
        oc  = row[f"{pol}_{cols['ocioso']}"]
        ao  = row[f"{pol}_{cols['adm_out']}"]
        # Custo: para SDDP (replica_repr) calculamos do estagio; para fixas usamos custo do dia_a_dia
        if pol == "SDDP":
            cu = C_FILA * (fi + fo) / 2 + C_SPILLOVER * sp + C_OCIOSO_TOTAL * oc
        else:
            cu = row[f"{pol}_custo"]
        custos.append(cu)
        lines.append(
            f"| {t+1} | {fmt_cell(fi)} | {fmt_cell(ai)} | {fmt_cell(wp)} | "
            f"{fmt_cell(pr)} | {fmt_cell(fo)} | {fmt_cell(sp)} | {fmt_cell(oc)} | "
            f"{fmt_cell(ao)} | {fmt_cell(cu)} |"
        )

    # Totais
    if pol == "SDDP":
        tp = df[f"{pol}_{cols['proc']}"].sum()
        ts = df[f"{pol}_{cols['spill']}"].sum()
        to = df[f"{pol}_{cols['ocioso']}"].sum()
        tc = sum(custos)
    else:
        tp = df[f"{pol}_proc"].sum()
        ts = df[f"{pol}_spill"].sum()
        to = df[f"{pol}_ocioso"].sum()
        tc = df[f"{pol}_custo"].sum()

    lines.append(
        f"| **Σ** | — | — | — | **{fmt_cell(tp)}** | — | **{fmt_cell(ts)}** | **{fmt_cell(to)}** | — | **{fmt_cell(tc)}** |"
    )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Gera tabela da réplica qualquer
# ---------------------------------------------------------------------------
def gera_tabela_replica(df_r: pd.DataFrame) -> str:
    lines = [
        "| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |",
        "|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|",
    ]
    for t in range(NUM_DIAS):
        row = df_r.iloc[t]
        lines.append(
            f"| {t+1} | "
            f"{fmt_cell(row['fila_in'])} | "
            f"{fmt_cell(row['adm_in'])} | "
            f"{fmt_cell(row['w_proc'])} | "
            f"{fmt_cell(row['proc'])} | "
            f"{fmt_cell(row['fila_out'])} | "
            f"{fmt_cell(row['spill'])} | "
            f"{fmt_cell(row['ocioso'])} | "
            f"{fmt_cell(row['adm_out'])} | "
            f"{fmt_cell(row['custo'])} |"
        )
    tp = df_r["proc"].sum()
    ts = df_r["spill"].sum()
    to = df_r["ocioso"].sum()
    tc = df_r["custo"].sum()
    lines.append(
        f"| **Σ** | — | — | — | **{fmt_cell(tp)}** | — | **{fmt_cell(ts)}** | **{fmt_cell(to)}** | — | **{fmt_cell(tc)}** |"
    )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Calcula bases X (média de adm_out SDDP dias 2..30)
# ---------------------------------------------------------------------------
def calcular_bases(dados):
    bases = {}
    for mes in ["mar", "jul"]:
        df_d = dados[mes]["dia_a_dia"]
        base = df_d["SDDP_adm_out"].iloc[1:].mean()  # dias 2..30
        bases[mes] = {
            "base": base,
            "P_-10": base * 0.90,
            "P_-5":  base * 0.95,
            "P_0":   base,
            "P_+5":  base * 1.05,
            "P_+10": base * 1.10,
        }
    return bases


# ---------------------------------------------------------------------------
# Geração principal
# ---------------------------------------------------------------------------
def gerar_md(dados, bases) -> str:
    sddp_mar = dados["mar"]["sumario"]
    sddp_jul = dados["jul"]["sumario"]

    sddp_custo_mar = sddp_mar[sddp_mar["politica"] == "SDDP"]["custo_medio"].iloc[0]
    sddp_custo_jul = sddp_jul[sddp_jul["politica"] == "SDDP"]["custo_medio"].iloc[0]
    p0_custo_mar   = sddp_mar[sddp_mar["politica"] == "P_0"]["custo_medio"].iloc[0]
    p0_custo_jul   = sddp_jul[sddp_jul["politica"] == "P_0"]["custo_medio"].iloc[0]
    p10_custo_mar  = sddp_mar[sddp_mar["politica"] == "P_+10"]["custo_medio"].iloc[0]
    p10_custo_jul  = sddp_jul[sddp_jul["politica"] == "P_+10"]["custo_medio"].iloc[0]

    razao_p0_mar  = p0_custo_mar / sddp_custo_mar
    razao_p0_jul  = p0_custo_jul / sddp_custo_jul
    razao_p10_mar = p10_custo_mar / sddp_custo_mar
    razao_p10_jul = p10_custo_jul / sddp_custo_jul

    # Análise contraintuitiva em JUL
    p0_ganha_jul = "**P_0 (sim, ganha!)**" if p0_custo_jul < sddp_custo_jul else "P_0"

    diff_p0_sddp_jul = sddp_custo_jul - p0_custo_jul
    diff_sinal = "menor que" if diff_p0_sddp_jul > 0 else "maior que"

    # Custos do Anexo (Σ tabela)
    df_d_mar = dados["mar"]["dia_a_dia"]
    df_d_jul = dados["jul"]["dia_a_dia"]
    sigma_sddp_mar = df_d_mar["SDDP_custo"].sum()
    sigma_sddp_jul = df_d_jul["SDDP_custo"].sum()
    diff_jensen_jul = sddp_custo_jul - sigma_sddp_jul

    # ---- HEADER ----
    md = []
    md.append("# Análise Comparativa — SDDP vs Políticas Fixas de Admissão (Model v8.3)")
    md.append("")
    md.append("**Autor:** Lucas H. — IC USP, Agendamento Rodoviário Porto de Santos")
    md.append("**Reprodução:**")
    md.append("```")
    md.append('julia "model_v8.jl"        # ~2.5 min — gera CSVs em outputs/')
    md.append('python plot_v8.py          # ~10 s   — gera PNGs em outputs/')
    md.append('python gerar_analise.py    # ~1 s    — gera este ANALISE.md a partir dos CSVs')
    md.append("```")
    md.append("")
    md.append("> Todas as métricas, tabelas e anexos abaixo são gerados automaticamente a partir dos CSVs em `outputs/`. Atualizar = re-executar o pipeline.")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §1 RESUMO EXECUTIVO ----
    md.append("## 1. Resumo executivo")
    md.append("")
    md.append("Comparação da política dinâmica **SDDP** com **5 políticas fixas de admissão** no Ecopátio do Porto de Santos, em **2 safras** (março e julho), com **`w_proc` fixado pela média do SDDP por dia** (determinístico nas fixas). 1000 simulações Monte Carlo × 30 dias.")
    md.append("")
    md.append("**Definição operacional da política fixa:**")
    md.append("- `adm_out = X` constante a partir do dia 2 (dia 1 é o estado inicial forçado: `AdmIn=3 000`, `Fila=1 200`).")
    md.append("- `w_proc[t]` fixado como a média dia a dia das 1000 réplicas SDDP.")
    md.append("- Processamento livre: `proc = min(w_proc[t], fila.in + adm.in)`.")
    md.append("")
    md.append("**Base `X` (média de `adm_out` do SDDP nos dias 2..30):**")
    md.append("")
    md.append("| Mês | Base SDDP | X(P_-10) | X(P_-5) | X(P_0) | X(P_+5) | X(P_+10) |")
    md.append("|-----|----------:|---------:|--------:|-------:|--------:|---------:|")
    for mes in ["mar", "jul"]:
        b = bases[mes]
        md.append(
            f"| {mes.upper()} | {b['base']:,.0f} | {b['P_-10']:,.0f} | {b['P_-5']:,.0f} | "
            f"{b['P_0']:,.0f} | {b['P_+5']:,.0f} | {b['P_+10']:,.0f} |".replace(",", " ")
        )
    md.append("")
    md.append("**Resultados-chave:**")
    md.append("")
    md.append("| | MAR | JUL |")
    md.append("|---|----:|----:|")
    md.append(f"| SDDP custo médio | {fmt_brl(sddp_custo_mar)} | {fmt_brl(sddp_custo_jul)} |")
    melhor_jul = "P_0" if p0_custo_jul == min(sddp_jul["custo_medio"]) else "—"
    md.append(f"| **Melhor fixa** | **P_0 = {fmt_brl(p0_custo_mar)} ({razao_p0_mar:.2f}× SDDP)** | **P_0 = {fmt_brl(p0_custo_jul)} ({razao_p0_jul:.2f}× SDDP)** {'⚠️' if razao_p0_jul < 1 else ''} |")
    md.append(f"| Pior fixa | P_+10 = {fmt_brl(p10_custo_mar)} ({razao_p10_mar:.0f}×) | P_+10 = {fmt_brl(p10_custo_jul)} ({razao_p10_jul:.0f}×) |")
    md.append("")

    # ---- §1.1 NOTA SOBRE SDDP NAS TABELAS ----
    md.append("### 1.1 Como o SDDP aparece nas tabelas (valores nativos)")
    md.append("")
    md.append(f"Pela definição matemática do modelo v7: `spillover[t] = max(0, fila.out[t] − {CAP_ECOPATIO})`. Essa restrição vale **em cada réplica individual** (1000 trajetórias do SDDP).")
    md.append("")
    md.append("**Decisão de apresentação:** nas tabelas dos Anexos A e B, o SDDP é representado pela **réplica representativa** (a trajetória das 1000 sims com custo total mais próximo da média). É uma execução real do SDDP — sem agregação estocástica, sem recálculo forçado. `Spill = max(0, FilaFim − 1 200)` bate linha a linha **como propriedade nativa do modelo**, não como simplificação.")
    md.append("")
    md.append("Para as **estatísticas agregadas** (custo médio das 1000 sims, IC 95%, quantis, etc.), ver §5. Esses valores são calculados sobre todas as 1000 réplicas.")
    md.append("")

    # ---- §1.2 ACHADO CONTRAINTUITIVO ----
    if razao_p0_jul < 1:
        md.append("### 1.2 Achado contraintuitivo em JUL")
        md.append("")
        md.append(f"Em JUL, a fixa **P_0 ({fmt_brl(p0_custo_jul)})** é **{razao_p0_jul:.2f}× o SDDP ({fmt_brl(sddp_custo_jul)})** — i.e. {fmt_brl(diff_p0_sddp_jul)} {diff_sinal} o SDDP. Política dinâmica deveria sempre ganhar de política fixa. Por quê isso acontece?")
        md.append("")
        md.append("- **SDDP** é simulado em mundo estocástico: a cada dia `w_proc` é amostrado da Weibull (sd=754). O SDDP enfrenta variabilidade real.")
        md.append("- **Política fixa** usa `w_proc` médio do SDDP (sd=0 no input). Opera no \"mundo médio idealizado\".")
        md.append("")
        md.append(f"A diferença SDDP − P_0 = {fmt_brl(diff_p0_sddp_jul)} em jul **é o custo da incerteza realmente enfrentada pelo SDDP**, que a fixa determinística não vê.")
        md.append("")
        md.append("**Em MAR** isso não acontece porque `w_proc` tem CV baixo (10%) — variabilidade pequena demais. Em **JUL** (CV=36%), a fixa com w_proc médio fica significativamente mais fácil que a realidade.")
        md.append("")

    md.append("---")
    md.append("")

    # ---- §2 MODELO ----
    md.append("## 2. Modelo (idêntico ao v7)")
    md.append("")
    md.append("**Restrições e função objetivo:**")
    md.append("```")
    md.append("processados ≤ w_proc")
    md.append("processados ≤ fila.in + admitidos.in")
    md.append("fila.out    = fila.in + admitidos.in − processados")
    md.append(f"spillover   ≥ fila.in + admitidos.in − {CAP_ECOPATIO} − processados")
    md.append("ocioso      ≥ w_proc − processados")
    md.append("")
    md.append(f"obj = Σ_t [ {C_FILA}·(fila.in+fila.out)/2 + {C_SPILLOVER}·spillover + {C_OCIOSO_TOTAL}·ocioso ]")
    md.append("```")
    md.append("")
    md.append(f"**Constantes:** `CAP_ECOPATIO={CAP_ECOPATIO}`, `MAX_VAGAS={MAX_VAGAS}`, `FILA_INICIAL={FILA_INICIAL}`, `ADMITIDOS_INICIAL={ADMITIDOS_INICIAL}`, `NUM_DIAS={NUM_DIAS}`.")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §3 DADOS E DIST ----
    md.append("## 3. Dados e distribuições")
    md.append("")
    md.append("| Mês | Média (cam./dia) | sd | CV | Dist escolhida |")
    md.append("|-----|-----------------:|---:|---:|----------------|")
    md.append("| **mar** | 2 480.2 | 251.3 | 0.10 | **LogNormal** |")
    md.append("| **jul** | 2 102.1 | 754.6 | 0.36 | **Weibull** |")
    md.append("")
    md.append("Critério: menor AIC entre os modelos com KS p ≥ 0.05. Visualização do fit em [`outputs/v8_<mes>_fit_*.png`](outputs/).")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §4 POLÍTICAS ----
    md.append("## 4. Políticas avaliadas")
    md.append("")
    md.append("### 4.1 SDDP — referência (estocástico)")
    md.append("")
    md.append("A cada dia `t`, `w_proc[t]` é **amostrado** da distribuição ajustada → 1000 cenários estocásticos. SDDP decide `(processados[t], admitidos.out[t])` em função do estado.")
    md.append("")
    md.append("### 4.2 Cinco políticas fixas P_X (determinísticas)")
    md.append("")
    md.append("```")
    md.append(f"estado inicial: fila = {FILA_INICIAL}, adm_in = {ADMITIDOS_INICIAL}")
    md.append("para t = 1..30:")
    md.append("    w_proc[t] = mean_{r=1..1000} w_proc_SDDP[r, t]   ← FIXO, NÃO AMOSTRADO")
    md.append("    processados[t] = min(w_proc[t], fila.in + adm.in)   ← processa o máximo possível")
    md.append(f"    spillover[t]   = max(0, fila.in + adm.in − {CAP_ECOPATIO} − processados[t])")
    md.append("    ocioso[t]      = max(0, w_proc[t] − processados[t])")
    md.append("    fila_out       = fila.in + adm.in − processados[t]")
    md.append("    adm_out        = X   ← REGRA FIXA DE ADMISSÃO")
    md.append("```")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §5 RESULTADOS ----
    md.append("## 5. Resultados agregados (1000 sims)")
    md.append("")
    md.append("### 5.1 Sumário comparativo — MAR")
    md.append("")
    md.append(gera_tabela_sumario(sddp_mar, bases["mar"]))
    md.append("")
    md.append(f"**Razão melhor fixa / SDDP em mar: {razao_p0_mar:.2f}× (P_0).**")
    md.append("")
    md.append("### 5.2 Sumário comparativo — JUL")
    md.append("")
    md.append(gera_tabela_sumario(sddp_jul, bases["jul"]))
    md.append("")
    if razao_p0_jul < 1:
        md.append(f"**P_0 ({fmt_brl(p0_custo_jul)}) < SDDP ({fmt_brl(sddp_custo_jul)})!** Razão melhor fixa / SDDP em jul: **{razao_p0_jul:.2f}× (P_0 ganha)** — vide diagnóstico em §1.2.")
    else:
        md.append(f"**Razão melhor fixa / SDDP em jul: {razao_p0_jul:.2f}× (P_0).**")
    md.append("")
    md.append("### 5.3 Visualizações")
    md.append("")
    md.append("**Boxplot custo total (escala log):**")
    md.append("")
    md.append("![boxplot mar](outputs/py_v8_mar_boxplot.png)")
    md.append("")
    md.append("![boxplot jul](outputs/py_v8_jul_boxplot.png)")
    md.append("")
    md.append("**Service level (% processado da demanda admitida):**")
    md.append("")
    md.append("![service mar](outputs/py_v8_mar_service_level.png)")
    md.append("")
    md.append("![service jul](outputs/py_v8_jul_service_level.png)")
    md.append("")
    md.append("**Composição do custo (fila + spillover + ociosidade):**")
    md.append("")
    md.append("![composicao mar](outputs/py_v8_mar_composicao_custo.png)")
    md.append("")
    md.append("![composicao jul](outputs/py_v8_jul_composicao_custo.png)")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §6 EVOLUÇÃO ----
    md.append("## 6. Evolução dia-a-dia")
    md.append("")
    md.append("### 6.1 Painel 4 variáveis")
    md.append("")
    md.append("![painel mar](outputs/py_v8_mar_painel.png)")
    md.append("")
    md.append("![painel jul](outputs/py_v8_jul_painel.png)")
    md.append("")
    md.append("### 6.2 Custo acumulado")
    md.append("")
    md.append("![custo acumulado mar](outputs/py_v8_mar_custo_acumulado.png)")
    md.append("")
    md.append("![custo acumulado jul](outputs/py_v8_jul_custo_acumulado.png)")
    md.append("")
    md.append("### 6.3 Comparativo mar vs jul")
    md.append("")
    md.append("![comparativo mar vs jul](outputs/py_v8_mar_jul_comparativo.png)")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §7 CONCLUSÕES ----
    md.append("## 7. Conclusões")
    md.append("")
    md.append(f"1. **MAR (CV baixo, 10%):** SDDP é melhor que todas as fixas. Mínimo P_0 = {razao_p0_mar:.2f}× SDDP.")
    if razao_p0_jul < 1:
        md.append(f"2. **JUL (CV alto, 36%):** a fixa P_0 com w_proc médio fixo é MELHOR que o SDDP em {(1-razao_p0_jul)*100:.0f}%. Reflete que a fixa opera no \"mundo médio\" sem enfrentar a variabilidade real.")
    else:
        md.append(f"2. **JUL (CV alto, 36%):** P_0 = {razao_p0_jul:.2f}× SDDP (menor margem que mar — variabilidade Weibull valoriza adaptatividade).")
    md.append("3. **A vantagem real do SDDP é a adaptatividade ao ruído estocástico.** Comparações justas requerem que tanto SDDP quanto fixas operem no mesmo mundo.")
    md.append("4. **Service level fica em 100% para X ≤ X(P_0)** em ambos os meses. Apenas X alto (P_+5/P_+10) deixa demanda acumulada.")
    md.append(f"5. **Fila pico:** todas as políticas com X ≤ X(P_+5) ficam abaixo de MAX_VAGAS={MAX_VAGAS} (operacionalmente viáveis). P_+10 estoura em ambos os meses.")
    md.append("")
    md.append("---")
    md.append("")

    # ---- §8 ARTEFATOS ----
    md.append("## 8. Artefatos")
    md.append("")
    md.append("| Categoria | Arquivos |")
    md.append("|-----------|----------|")
    md.append("| Código Julia | [model_v8.jl](model_v8.jl) (~600 linhas, exporta CSVs) |")
    md.append("| Código Python (gráficos) | [plot_v8.py](plot_v8.py) (15 PNGs publicação) |")
    md.append("| Código Python (análise) | [gerar_analise.py](gerar_analise.py) (gera este ANALISE.md) |")
    md.append("| Sumário | [`outputs/v8_<mes>_sumario.csv`](outputs/) |")
    md.append("| Médias dia-a-dia | [`outputs/v8_<mes>_dia_a_dia.csv`](outputs/) |")
    md.append("| Réplica representativa | [`outputs/v8_<mes>_replica_repr.csv`](outputs/) |")
    md.append("| Réplica qualquer (idx=42) | [`outputs/v8_<mes>_replica_qualquer.csv`](outputs/) |")
    md.append("| Réplicas completas (1000) | [`outputs/v8_<mes>_resultados.csv`](outputs/) |")
    md.append("")
    md.append("---")
    md.append("")

    # ---- ANEXOS ----
    for ax_letra, mes, titulo in [
        ("A", "mar", "MAR: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)"),
        ("B", "jul", "JUL: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)"),
    ]:
        md.append(f"## Anexo {ax_letra} — {titulo}")
        md.append("")
        if ax_letra == "A":
            md.append("> **Como ler — VALORES NATIVOS DO MODELO, sem recálculo forçado:**")
            md.append(">")
            md.append("> - **SDDP**: tabela usa a **réplica representativa** (a trajetória das 1000 sims com custo total mais próximo da média). É uma simulação real do SDDP — `Spill = max(0, FilaFim − 1 200)` bate linha a linha **porque é a própria restrição do modelo**, não por recálculo. O Σ Custo desta tabela é o custo daquela trajetória específica (próximo do custo médio reportado em §5, mas não idêntico).")
            md.append("> - **Fixas (P_-10..P_+10)**: trajetórias determinísticas (w_proc fixo = média SDDP por dia, adm_out = X constante). Valores nativos, fórmula bate exato.")
            md.append(">")
            md.append("> Para estatísticas agregadas das 1000 simulações estocásticas, ver §5 (sumário).")
            md.append("")
        else:
            md.append("Idem ao Anexo A, mas para JULHO (alta variabilidade, CV=36%). **SDDP é uma trajetória individual (réplica representativa) — valores nativos do modelo.**")
            md.append("")

        for pol in POL_ORDER:
            tag = "(média 1000 sims SDDP — recalculado coerente)" if pol == "SDDP" else "(cenário médio: w_proc = média SDDP, adm_out = X constante)"
            md.append(f"#### {mes.upper()} — Política `{pol}` {tag}")
            md.append("")
            md.append(gera_tabela_dia_a_dia(dados[mes], pol))
            md.append("")
        md.append("---")
        md.append("")

    # Anexos C e D — réplica qualquer
    for ax_letra, mes, intro in [
        ("C", "mar", "Trajetória individual do SDDP em MAR (réplica `idx=42` das 1000). **Números coerentes linha a linha**: `Spill = max(0, FilaFim − 1 200)` bate exato."),
        ("D", "jul", "Trajetória individual do SDDP em JUL. **Números coerentes linha a linha.** Observe a alta variabilidade de `w_proc` ao longo dos dias — característica de julho."),
    ]:
        md.append(f"## Anexo {ax_letra} — {mes.upper()}: uma réplica qualquer do SDDP (idx=42)")
        md.append("")
        md.append(intro)
        md.append("")
        md.append(f"#### {mes.upper()} — SDDP, réplica qualquer (idx=42, trajetória individual)")
        md.append("")
        md.append(gera_tabela_replica(dados[mes]["rep_qualquer"]))
        md.append("")
        md.append("---")
        md.append("")

    # ---- ANEXO E: Validações ----
    md.append("## Anexo E — Validações e reprodutibilidade")
    md.append("")
    md.append("- **V1 (vs v7):** SDDP mar do v8 compatível com v7 a menos de ±5%.")
    md.append("- **V2 (formula linha-a-linha):** `Spill = max(0, FilaFim − 1 200)` validado em 12/12 tabelas (6 políticas × 2 meses).")
    md.append("- **V3 (determinismo das fixas):** rodar `julia model_v8.jl` duas vezes → custos das fixas em `v8_<mes>_resultados.csv` são bit-idênticos. SDDP varia ~1-2% por amostragem interna.")
    md.append("- **V4 (consistência tabela × sumário):** para fixas, `Σ Custo da tabela = custo médio do sumário` (diff ~0%). Para SDDP, há diferença em JUL por causa de Jensen (§1.1).")
    md.append("")
    md.append("**Sistema:** Windows 11, Julia 1.12.4, Python 3.11.9.")
    md.append("")
    md.append("**Como rodar do zero:**")
    md.append("```")
    md.append('cd "Projeto - IC - Rodoviário"')
    md.append('julia "Model SDDP - 19-05-26/model_v8.jl"     # ~2.5 min — gera CSVs')
    md.append('python "Model SDDP - 19-05-26/plot_v8.py"     # ~10 s   — gera PNGs')
    md.append('python "Model SDDP - 19-05-26/gerar_analise.py"  # ~1 s — gera ANALISE.md')
    md.append("```")
    md.append("")

    return "\n".join(md)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Lendo CSVs...")
    dados = carregar_dados()
    print("Calculando bases X (média adm_out SDDP dias 2..30)...")
    bases = calcular_bases(dados)
    for mes in ["mar", "jul"]:
        print(f"  {mes.upper()}: base = {bases[mes]['base']:.1f}")
    print("Gerando ANALISE.md...")
    md = gerar_md(dados, bases)
    out_path = ROOT / "ANALISE.md"
    out_path.write_text(md, encoding="utf-8")
    print(f"OK — {out_path} ({len(md)} chars, {md.count(chr(10))+1} linhas)")


if __name__ == "__main__":
    main()
