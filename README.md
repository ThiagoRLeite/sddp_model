# Model SDDP — Comparação SDDP vs Políticas Fixas de Admissão

![Julia](https://img.shields.io/badge/Julia-1.12-9558B2?logo=julia)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![Status](https://img.shields.io/badge/status-v8.3-success)

Pipeline de **otimização estocástica multi-estágio (SDDP)** comparado com **5 políticas fixas de admissão** para agendamento rodoviário no Ecopátio do Porto de Santos.

> Trabalho de Iniciação Científica — USP, sob orientação do professor. Modela a operação diária do pátio em horizonte de 30 dias, com `w_proc` (capacidade aleatória de processamento) ajustado a dados reais de 2025.

---

## TL;DR — Resultados-chave (1000 sims × 2 meses)

| | MAR | JUL |
|---|---:|---:|
| **SDDP** (política dinâmica) | R$ 52.0 M | R$ 204 M |
| **Melhor fixa** | P_0 = R$ 114 M (**2.2×** SDDP) | **P_0 = R$ 181 M (0.89× SDDP)** ⚠️ |
| **Pior fixa** | P_+10 = R$ 1.62 B (31×) | P_+10 = R$ 1.21 B (5.9×) |

**Achado contraintuitivo em JUL:** a fixa P_0 vence o SDDP. Isso reflete que a fixa opera no "mundo médio" (`w_proc` fixo = média SDDP), enquanto o SDDP enfrenta a variabilidade real da Weibull (CV=36%). Análise completa em [ANALISE.md §1.2](ANALISE.md).

---

## Como rodar

```bash
cd "Projeto - IC - Rodoviário"

julia "Model SDDP - 19-05-26/model_v8.jl"     # ~2.5 min — gera CSVs + 22 PNGs
python "Model SDDP - 19-05-26/plot_v8.py"     # ~10 s — gera 15 PNGs publicação
```

**Primeira execução:** o Julia instala pacotes automaticamente (~5-10 min). Execuções subsequentes: ~2.5 min.

**Dependências:**
- Julia 1.12+ com: SDDP.jl, HiGHS, JuMP, Distributions, HypothesisTests, StatsPlots, StatsBase, CSV, DataFrames
- Python 3.11+ com: pandas, matplotlib, seaborn

---

## Estrutura do repositório

```
Model SDDP - 19-05-26/
├── ANALISE.md            ← análise completa (~1300 linhas, 10 seções + 2 anexos)
├── SPEC.md               ← design do modelo (12 seções)
├── PLAN.md               ← plano de implementação (15 tasks)
├── README.md             ← este arquivo
├── model_v8.jl           ← código Julia/SDDP (~600 linhas)
├── plot_v8.py            ← gerador de gráficos publicação-ready (~300 linhas)
├── tabelas_v7_md.txt     ← 12 tabelas formato v7 (30 dias × 6 políticas × 2 meses)
└── outputs/              ← gerado automaticamente
    ├── py_v8_*.png       ← 15 PNGs publicação (matplotlib + seaborn)
    ├── v8_*.png          ← 22 PNGs baseline (Julia/StatsPlots)
    └── v8_*.csv          ← 8 CSVs (sumário, resultados, dia-a-dia, etc.)
```

---

## O que esse modelo faz

**Modelo (idêntico ao v7):**
- Estado: `fila`, `admitidos`. Decisão: `processados`, `spillover`, `ocioso`.
- Choque estocástico: `w_proc` ~ distribuição ajustada (LogNormal em mar, Weibull em jul).
- Função objetivo: minimizar custo (fila + spillover + ociosidade) ao longo de 30 dias.

**6 políticas comparadas:**
1. **SDDP** (referência) — decide `(processados, admitidos.out)` dinamicamente em função do estado.
2. **5 políticas fixas P_X** — admissão constante `adm_out = X`, processa o máximo possível. Variam em ±10%, ±5%, 0% sobre a base SDDP.

**Base das fixas:** `mean(adm_out SDDP, dias 2..30)` — exclui o dia 1 distorcido pelo estado inicial.

| Mês | Base | X(P_-10) | X(P_-5) | X(P_0) | X(P_+5) | X(P_+10) |
|-----|-----:|---------:|--------:|-------:|--------:|---------:|
| MAR | 2 392 | 2 153 | 2 272 | 2 392 | 2 512 | 2 631 |
| JUL | 1 974 | 1 777 | 1 875 | 1 974 | 2 073 | 2 172 |

---

## Indicadores principais

| Indicador | O que mede | Valores típicos |
|-----------|------------|-----------------|
| **Custo médio** | Custo total esperado dos 30 dias | R$ 52 M (SDDP MAR) — R$ 1.21 B (P_+10 JUL) |
| **Service level** | % processado da demanda admitida (dias 2..30, cap 100%) | 94-100% |
| **Fila pico médio** | Máximo da fila por réplica (limite MAX_VAGAS=4 000) | 1 700-6 000 |
| **Spillover total** | Caminhão-dia em excesso ao pátio (ver §1.1 do ANALISE.md) | 525 (SDDP MAR) — 80 463 (P_+10 MAR) |

> ⚠️ **Cuidado interpretativo:** spillover é um **estado** (caminhões fora do pátio nesse dia), não fluxo. Detalhes em [ANALISE.md §1.1](ANALISE.md).

---

## Documentação

- **[ANALISE.md](ANALISE.md)** — análise completa com diagnóstico, indicadores, anexos e tabelas dia-a-dia (10 seções + 2 anexos, ~1300 linhas)
- **[SPEC.md](SPEC.md)** — design contract do modelo
- **[PLAN.md](PLAN.md)** — plano de implementação task-by-task
- **[tabelas_v7_md.txt](tabelas_v7_md.txt)** — 12 tabelas formato v7 (6 políticas × 2 meses × 30 dias)

---

## Próximos passos (v9)

Comparação atual usa `w_proc` médio determinístico nas fixas. Para uma comparação "honesta" — onde tanto SDDP quanto fixas enfrentam a mesma realização aleatória — rodar:

- **v9a:** fixas com `w_proc` amostrado independente (com ruído de variância)
- **v9b:** fixas com `w_proc` amostrado **com CRN** entre SDDP e fixas (justo réplica-a-réplica)

Esperado: P_0 fica acima do SDDP em ambos os meses (cenário honesto), com razão SDDP/P_0 em ~1.3×-2× — alinhado com a expectativa do professor de "comparação não muito divergente".

---

## Histórico de versões

- **v8.3** (atual) — política fixa = admissão fixa + `w_proc` médio SDDP por dia (determinístico). Service level cap 100%, dias 2..30.
- **v8.2** — política fixa com admissão fixa + `w_proc` amostrado (CRN).
- **v8.1** — política fixa fixava processamento (interpretação errada — corrigido).
- **v8.0** — primeira versão com 3 fixas baseadas na média do mês.

---

## Reprodutibilidade

- **Sistema:** Windows 11, Julia 1.12.4, Python 3.11.9
- **Sementes:** `SEED_BASE = 42` (CRN), SDDP usa amostragem interna
- **Tempo de execução:** ~2.5 min (Julia) + ~10 s (Python) em CPU
- **Validações:** V1-V4 documentadas no Anexo B do [ANALISE.md](ANALISE.md)
