"""
Gera graficos publicacao-ready com matplotlib/seaborn a partir dos CSVs v8.
Rodar apos o pipeline Julia ter gerado os outputs:
    python "Model SDDP - 19-05-26/plot_v8.py"
"""
from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick
import seaborn as sns

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
sns.set_theme(style="whitegrid", context="notebook", font_scale=1.05)
plt.rcParams.update({
    "figure.dpi": 110,
    "savefig.dpi": 150,
    "savefig.bbox": "tight",
    "axes.titlesize": 14,
    "axes.titleweight": "bold",
    "axes.labelsize": 12,
    "legend.frameon": True,
    "legend.framealpha": 0.92,
    "font.family": "DejaVu Sans",
})

ROOT = Path(__file__).parent
OUT = ROOT / "outputs"
MESES = ["mar", "jul"]
POL_ORDER = ["SDDP", "P_-10", "P_-5", "P_0", "P_+5", "P_+10"]

# Paleta: SDDP em azul escuro destaque; fixas em gradiente vermelho->verde
PALETTE = {
    "SDDP":  "#0d47a1",
    "P_-10": "#c62828",
    "P_-5":  "#ef6c00",
    "P_0":   "#9e9d24",
    "P_+5":  "#558b2f",
    "P_+10": "#1b5e20",
}

LINESTYLE = {pol: ("-" if pol == "SDDP" else "-") for pol in POL_ORDER}
LINEWIDTH = {pol: (3.0 if pol == "SDDP" else 1.8) for pol in POL_ORDER}
MARKER = {pol: ("o" if pol == "SDDP" else None) for pol in POL_ORDER}


def _fmt_brl(x, _pos=None):
    if abs(x) >= 1e9:
        return f"R$ {x/1e9:.1f} B"
    if abs(x) >= 1e6:
        return f"R$ {x/1e6:.0f} M"
    if abs(x) >= 1e3:
        return f"R$ {x/1e3:.0f} k"
    return f"R$ {x:.0f}"


def _add_pol_lines(ax, df, var_suffix, ylabel, logy=False):
    """Plota linha por politica usando colunas {pol}_{var_suffix}."""
    for pol in POL_ORDER:
        col = f"{pol}_{var_suffix}"
        ax.plot(df["dia"], df[col],
                color=PALETTE[pol], linestyle=LINESTYLE[pol],
                linewidth=LINEWIDTH[pol], marker=MARKER[pol], markersize=4.5,
                label=pol)
    ax.set_xlabel("Dia")
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.35)
    if logy:
        ax.set_yscale("log")
    ax.legend(loc="best", ncol=2, fontsize=9)


# ---------------------------------------------------------------------------
# 1) Custo acumulado (line plot, escala log) — money plot
# ---------------------------------------------------------------------------
def plot_custo_acumulado(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv")
    fig, ax = plt.subplots(figsize=(12, 6.5))
    for pol in POL_ORDER:
        ax.plot(df["dia"], df[f"{pol}_custo_acum"],
                color=PALETTE[pol], linewidth=LINEWIDTH[pol],
                marker=MARKER[pol], markersize=4.5, label=pol)
    ax.set_yscale("log")
    ax.set_xlabel("Dia")
    ax.set_ylabel("Custo acumulado (R$, escala log)")
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(_fmt_brl))
    ax.grid(True, alpha=0.35, which="both")
    ax.set_title(f"Custo acumulado dia a dia — {mes.upper()} (média 1000 sims)")
    # Legenda à direita fora do plot — não conflita com anotação
    ax.legend(loc="center left", bbox_to_anchor=(1.01, 0.5), fontsize=10, frameon=True)
    # anotação valor final no canto inferior direito do plot
    sddp_fim = df["SDDP_custo_acum"].iloc[-1]
    best_fix = min(df[f"{p}_custo_acum"].iloc[-1] for p in POL_ORDER if p != "SDDP")
    worst_fix = max(df[f"{p}_custo_acum"].iloc[-1] for p in POL_ORDER if p != "SDDP")
    ratio_b = best_fix / sddp_fim
    ratio_w = worst_fix / sddp_fim
    ax.text(0.02, 0.02,
            f"Após 30 dias:\nSDDP: {_fmt_brl(sddp_fim)}\nMelhor fixa: {_fmt_brl(best_fix)} ({ratio_b:.0f}×)\nPior fixa: {_fmt_brl(worst_fix)} ({ratio_w:.0f}×)",
            transform=ax.transAxes, va="bottom", ha="left",
            bbox=dict(boxstyle="round,pad=0.5", facecolor="white", edgecolor="gray", alpha=0.95),
            fontsize=10)
    fig.savefig(OUT / f"py_v8_{mes}_custo_acumulado.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 2) Fila ao fim do dia (linear)
# ---------------------------------------------------------------------------
def plot_fila(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv")
    fig, ax = plt.subplots(figsize=(11, 6))
    _add_pol_lines(ax, df, "fila_out", "Fila ao fim do dia (caminhões)")
    ax.set_title(f"Evolução da fila — {mes.upper()} (média 1000 sims)")
    ax.axhline(4000, color="crimson", linestyle="--", linewidth=1, alpha=0.5,
               label="MAX_VAGAS = 4 000")
    ax.axhline(2000, color="darkorange", linestyle=":", linewidth=1, alpha=0.6,
               label="Threshold conforto = 2 000")
    ax.legend(loc="upper left", ncol=2, fontsize=9)
    fig.savefig(OUT / f"py_v8_{mes}_fila.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 3) Spillover por dia (log) — bem separado de fila por causa da magnitude
# ---------------------------------------------------------------------------
def plot_spillover(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv")
    fig, ax = plt.subplots(figsize=(11, 6))
    for pol in POL_ORDER:
        y = df[f"{pol}_spill"].clip(lower=1e-2)  # piso para log
        ax.plot(df["dia"], y, color=PALETTE[pol], linewidth=LINEWIDTH[pol],
                marker=MARKER[pol], markersize=4.5, label=pol)
    ax.set_yscale("log")
    ax.set_xlabel("Dia")
    ax.set_ylabel("Spillover do dia (caminhões, log)")
    ax.set_title(f"Spillover dia a dia — {mes.upper()} (média 1000 sims)")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(loc="lower right", ncol=2, fontsize=9)
    fig.savefig(OUT / f"py_v8_{mes}_spillover.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 4) Boxplot do custo total (escala log) — distribuição completa N=1000
# ---------------------------------------------------------------------------
def plot_boxplot_custo(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_resultados.csv")
    df["politica"] = pd.Categorical(df["politica"], categories=POL_ORDER, ordered=True)
    fig, ax = plt.subplots(figsize=(11, 6))
    # Usa matplotlib direto (seaborn 0.13 tem bug com hue+legend=False)
    data_por_pol = [df.loc[df["politica"] == p, "custo_total"].values for p in POL_ORDER]
    bp = ax.boxplot(data_por_pol, labels=POL_ORDER, patch_artist=True, widths=0.55,
                    flierprops=dict(marker="o", markersize=3, alpha=0.5))
    for patch, pol in zip(bp["boxes"], POL_ORDER):
        patch.set_facecolor(PALETTE[pol])
        patch.set_edgecolor("black")
        patch.set_alpha(0.85)
    for med in bp["medians"]:
        med.set_color("black")
        med.set_linewidth(1.5)
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(_fmt_brl))
    ax.set_xlabel("Política")
    ax.set_ylabel("Custo total (R$, escala log)")
    ax.set_title(f"Distribuição do custo total nas 1000 sims — {mes.upper()}")
    ax.grid(True, axis="y", alpha=0.35)
    fig.savefig(OUT / f"py_v8_{mes}_boxplot.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 5) Service level (% processado da demanda admitida) — bar chart com anotação
# ---------------------------------------------------------------------------
def plot_service_level(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_sumario.csv")
    df["politica"] = pd.Categorical(df["politica"], categories=POL_ORDER, ordered=True)
    df = df.sort_values("politica")
    fig, ax = plt.subplots(figsize=(10, 5.5))
    bars = ax.bar(df["politica"], df["service_level"] * 100,
                  color=[PALETTE[p] for p in df["politica"]],
                  edgecolor="black", linewidth=0.8)
    ax.set_ylabel("Service level (% da demanda processada)")
    ax.set_xlabel("Política")
    ax.set_title(f"Service level = processados / admitidos — {mes.upper()}")
    ax.axhline(100, color="black", linestyle="--", linewidth=0.8, alpha=0.6,
               label="100% (todo o admitido foi processado)")
    ymax = max(df["service_level"]) * 100
    ax.set_ylim(0, max(110, ymax * 1.1))
    for bar, val in zip(bars, df["service_level"] * 100):
        ax.text(bar.get_x() + bar.get_width() / 2, val + 1.5,
                f"{val:.1f}%", ha="center", va="bottom", fontsize=10, fontweight="bold")
    ax.legend(loc="lower right", fontsize=9)
    ax.grid(True, axis="y", alpha=0.3)
    fig.savefig(OUT / f"py_v8_{mes}_service_level.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 6) Painel 2x2 — visão geral do mês (proc/ocioso/spill/fila)
# ---------------------------------------------------------------------------
def plot_painel(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv")
    fig, axes = plt.subplots(2, 2, figsize=(15, 9))
    cfg = [
        ("proc",     "Processados / dia",          False, axes[0, 0]),
        ("fila_out", "Fila ao fim do dia",         False, axes[0, 1]),
        ("ocioso",   "Ocioso / dia (log)",         True,  axes[1, 0]),
        ("spill",    "Spillover / dia (log)",      True,  axes[1, 1]),
    ]
    for suf, ylabel, logy, ax in cfg:
        for pol in POL_ORDER:
            y = df[f"{pol}_{suf}"]
            if logy:
                y = y.clip(lower=1e-2)
            ax.plot(df["dia"], y, color=PALETTE[pol],
                    linewidth=LINEWIDTH[pol], marker=MARKER[pol], markersize=3.5,
                    label=pol)
        ax.set_xlabel("Dia")
        ax.set_ylabel(ylabel)
        if logy:
            ax.set_yscale("log")
        ax.grid(True, alpha=0.3, which="both")
    # Legenda compartilhada
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=6,
               frameon=True, fontsize=11, bbox_to_anchor=(0.5, -0.02))
    fig.suptitle(f"Painel de evolução dia a dia — {mes.upper()} (média 1000 sims)",
                 fontsize=15, fontweight="bold", y=1.0)
    fig.tight_layout()
    fig.savefig(OUT / f"py_v8_{mes}_painel.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 7) Composição do custo (stacked bar) — fila vs spillover vs ocioso
# ---------------------------------------------------------------------------
C_FILA = 2790.0
C_SPILLOVER = 16211.0
C_OCIOSO_TOTAL = 1753.0 + 42000.0


def plot_composicao_custo(mes: str):
    df = pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv")
    # custo agregado por componente, por politica, ao longo de 30 dias
    rows = []
    for pol in POL_ORDER:
        # Custo de fila = C_FILA * (fila_in + fila_out) / 2, integrado nos 30 dias
        c_fila = C_FILA * ((df[f"{pol}_fila_in"] + df[f"{pol}_fila_out"]) / 2).sum()
        c_spill = C_SPILLOVER * df[f"{pol}_spill"].sum()
        c_ocioso = C_OCIOSO_TOTAL * df[f"{pol}_ocioso"].sum()
        rows.append({"politica": pol, "Fila": c_fila, "Spillover": c_spill, "Ocioso": c_ocioso})
    comp = pd.DataFrame(rows).set_index("politica").loc[POL_ORDER]
    fig, ax = plt.subplots(figsize=(11, 6))
    comp.plot(kind="bar", stacked=True, ax=ax,
              color=["#5c6bc0", "#ef5350", "#ffa726"], edgecolor="black", linewidth=0.5,
              width=0.7)
    ax.set_ylabel("Custo total (R$, escala log)")
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(_fmt_brl))
    ax.set_xlabel("Política")
    ax.set_title(f"Composição do custo total — {mes.upper()}")
    plt.setp(ax.get_xticklabels(), rotation=0)
    ax.legend(title="Componente", loc="best")
    ax.grid(True, axis="y", alpha=0.3, which="both")
    fig.savefig(OUT / f"py_v8_{mes}_composicao_custo.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# 8) Comparação mar vs jul (painel side-by-side do custo acumulado)
# ---------------------------------------------------------------------------
def plot_mar_jul_side_by_side():
    fig, axes = plt.subplots(1, 2, figsize=(16, 6), sharey=True)
    for ax, mes in zip(axes, MESES):
        df = pd.read_csv(OUT / f"v8_{mes}_dia_a_dia.csv")
        for pol in POL_ORDER:
            ax.plot(df["dia"], df[f"{pol}_custo_acum"],
                    color=PALETTE[pol], linewidth=LINEWIDTH[pol],
                    marker=MARKER[pol], markersize=3.5, label=pol)
        ax.set_yscale("log")
        ax.set_xlabel("Dia")
        ax.set_title(f"{mes.upper()}")
        ax.grid(True, alpha=0.3, which="both")
        ax.yaxis.set_major_formatter(mtick.FuncFormatter(_fmt_brl))
    axes[0].set_ylabel("Custo acumulado (R$, escala log)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=6,
               frameon=True, fontsize=11, bbox_to_anchor=(0.5, -0.04))
    fig.suptitle("Custo acumulado — comparação MAR vs JUL",
                 fontsize=15, fontweight="bold", y=1.02)
    fig.tight_layout()
    fig.savefig(OUT / "py_v8_mar_jul_comparativo.png")
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Gerando graficos publicacao-ready...")
    for mes in MESES:
        print(f"  [{mes.upper()}]")
        plot_custo_acumulado(mes)
        plot_fila(mes)
        plot_spillover(mes)
        plot_boxplot_custo(mes)
        plot_service_level(mes)
        plot_painel(mes)
        plot_composicao_custo(mes)
    plot_mar_jul_side_by_side()
    print("Pronto.")
    pngs = sorted(OUT.glob("py_v8_*.png"))
    print(f"\n{len(pngs)} PNGs gerados em {OUT}:")
    for p in pngs:
        print(f"  {p.name}")


if __name__ == "__main__":
    main()
