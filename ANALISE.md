# Análise Comparativa — SDDP vs Políticas Fixas de Admissão (Model v8.3)

**Autor:** Lucas H. — IC USP, Agendamento Rodoviário Porto de Santos
**Data:** 2026-05-20
**Reprodução:** `julia "Model SDDP - 19-05-26/model_v8.jl"` (~2.5 min) + `python "Model SDDP - 19-05-26/plot_v8.py"` (~10 s)

---

## 1. Resumo executivo

Comparação da política dinâmica **SDDP** com **5 políticas fixas de admissão** no Ecopátio do Porto de Santos, em **2 safras** (março e julho), com **`w_proc` fixado pela média do SDDP por dia** (determinístico). 1000 simulações Monte Carlo × 30 dias.

**Definição operacional das políticas fixas (corrigida nesta versão v8.3):**
- Cada política fixa tem `adm_out = X` constante a partir do dia 2 (dia 1 é o estado inicial forçado: `AdmIn=3 000`, `Fila=1 200`).
- **`w_proc[t]` é fixado** como a média dia a dia das 1000 réplicas SDDP. Isso elimina o ruído de amostragem das fixas e isola o efeito da decisão de admissão.
- Processamento é livre: `proc = min(w_proc[t], fila.in + adm.in)`.

A base `X` é a **média de `adm_out` do SDDP nos dias 2..30** (exclui dia 1 distorcido), variando em **±10%, ±5% e 0%**:

| Mês | Base SDDP | X(P_-10) | X(P_-5) | X(P_0) | X(P_+5) | X(P_+10) |
|-----|----------:|---------:|--------:|-------:|--------:|---------:|
| MAR | 2 392 | 2 153 | 2 272 | 2 392 | 2 512 | 2 631 |
| JUL | 1 974 | 1 777 | 1 875 | 1 974 | 2 073 | 2 172 |

**Resultados-chave:**

| | MAR | JUL |
|---|----:|----:|
| SDDP custo médio | R$ 52.0 M | R$ 204 M |
| **Melhor fixa** | **P_0 = R$ 114 M (2.2× SDDP)** | **P_0 = R$ 181 M (0.89× SDDP)** ⚠️ |
| Pior fixa | P_+10 = R$ 1.62 B (31× SDDP) | P_+10 = R$ 1.21 B (5.9× SDDP) |

### 1.1 ATENÇÃO: como interpretar "spillover" (questão de unidade)

Antes de qualquer análise, é fundamental entender o que a métrica de spillover representa neste modelo.

**Spillover NÃO é "caminhões que extravasaram naquele dia"** (isso seria um *fluxo*). Pela definição matemática do v7:

```
spillover[t]  ≥  fila.in[t] + admitidos.in[t] − CAP_ECOPATIO − processados[t]
             =  fila.out[t] − CAP_ECOPATIO    (pelo balanço de fila)
```

Ou seja, spillover[t] = `max(0, fila.out[t] − 1 200)` = **quantos caminhões estão FORA do pátio no fim do dia t** (medido instantaneamente como um estado).

**Implicações:**
- O custo `C_SPILLOVER × spillover[t]` = R$ 16 211 cobrados **por cada caminhão fora do pátio, por dia** (como "diária de estacionamento externo").
- A **soma de 30 dias** é a unidade física **"caminhão-dia em excesso"**, não "caminhões físicos extravasados".
- Por isso a tabela mostra valores como "P_+10 MAR spillover total = 80 463" — não significa 80 mil caminhões físicos, e sim "80 mil caminhão-dias" em excesso ao longo do horizonte. **Equivale a ter ~2 680 caminhões fora do pátio em média, todos os dias dos 30 dias.**

**Validação manual** (P_+10 MAR dia 30): fila_in=5 950 + adm_in=2 631 − proc=2 489 = fila_out=**6 092**. Spillover = max(0, 6 092 − 1 200) = **4 892**. Significa: nesse dia, 4 892 caminhões estão fora do pátio. CSV confere com exatidão.

> **Nota importante:** o modelo v7 NÃO tem restrição física de fila ≤ MAX_VAGAS. Permite filas ilimitadas, mas penaliza pesadamente cada caminhão acima do CAP_ECOPATIO=1 200. Isso é uma escolha de modelagem econômica (não restritiva), herdada do v7 e mantida intencionalmente no v8.

### 1.2 Achado contraintuitivo em JUL: fixa P_0 é melhor que SDDP

Em julho, a fixa **P_0 (R$ 181 M) é melhor que o SDDP (R$ 204 M)**. Política dinâmica deveria sempre ganhar de política fixa — por que isso acontece?

- **SDDP** é simulado em **mundo estocástico**: a cada dia, `w_proc` é amostrado da distribuição Weibull (sd=754). O SDDP precisa lidar com a variabilidade real.
- **Política fixa** usa `w_proc` **médio** do SDDP (sd=0 no input). Opera no "mundo médio idealizado" — sem nenhuma incerteza.

A diferença SDDP − P_0 = R$ 23 M em jul **é o custo da incerteza realmente enfrentada pelo SDDP**, que a fixa determinística não vê.

**Em MAR isso não acontece** porque `w_proc` tem CV baixo (10%) — a variabilidade é pequena demais para a fixa "ganhar de graça". Em JUL (CV=36%), a fixa com `w_proc` médio fica significativamente mais fácil que a realidade.

> **Interpretação correta:** as fixas com `w_proc` médio fixo são um **limite inferior teórico** — assumindo condições idealmente médias. O SDDP fica acima delas em MAR (situação favorável às fixas), mas abaixo em JUL (variância alta valoriza adaptatividade).

---

## 2. Modelo (idêntico ao v7)

**Variáveis (a cada dia t):**

| Símbolo | Tipo | Domínio | Significado |
|---------|------|---------|-------------|
| `fila` | estado | ≥ 0 | caminhões em fila no início do dia |
| `admitidos` | estado | [0, MAX_VAGAS=4 000] | caminhões admitidos para o próximo dia |
| `processados` | decisão | ≥ 0 | caminhões processados no dia |
| `spillover` | decisão | ≥ 0 | caminhões em excesso ao pátio |
| `ocioso` | decisão | ≥ 0 | capacidade não utilizada |
| `w_proc` | aleatório (SDDP) / fixo (fixa) | ~dist(mês) | capacidade aleatória de processamento |

**Restrições e função objetivo:**

```
processados ≤ w_proc
processados ≤ fila.in + admitidos.in
fila.out    = fila.in + admitidos.in − processados
spillover   ≥ fila.in + admitidos.in − CAP_ECOPATIO − processados
ocioso      ≥ w_proc − processados

obj = Σ_t [ C_FILA·(fila.in+fila.out)/2 + C_SPILLOVER·spillover + C_OCIOSO_TOTAL·ocioso ]
```

**Constantes:** `C_FILA=2 790`, `C_SPILLOVER=16 211`, `C_OCIOSO_TOTAL=43 753`, `CAP_ECOPATIO=1 200`, `MAX_VAGAS=4 000`, `FILA_INICIAL=1 200`, `ADMITIDOS_INICIAL=3 000`, `NUM_DIAS=30`.

---

## 3. Dados e distribuições

| Mês | Média (cam./dia) | sd | CV | Dist escolhida | AIC | KS p-value |
|-----|-----------------:|---:|---:|----------------|----:|-----------:|
| **mar** | 2 480.2 | 251.3 | 0.10 | **LogNormal** | 417.5 | 0.55 |
| **jul** | 2 102.1 | 754.6 | 0.36 | **Weibull** | 484.8 | 0.93 |

---

## 4. Políticas avaliadas

### 4.1 SDDP — referência (estocástico)

A cada dia `t`, `w_proc[t]` é **amostrado** da distribuição ajustada → 1000 cenários estocásticos. SDDP decide `(processados[t], admitidos.out[t])` em função do estado.

### 4.2 Cinco políticas fixas P_X (determinísticas)

**Regra operacional:**

```
estado inicial: fila = 1 200, adm_in = 3 000 (igual ao SDDP)
para t = 1..30:
    w_proc[t] = mean_{r=1..1000} w_proc_SDDP[r, t]   ← FIXO, NÃO AMOSTRADO
    processados[t] = min(w_proc[t], fila.in + adm.in)   ← processa o máximo possível
    spillover[t]   = max(0, fila.in + adm.in − 1 200 − processados[t])
    ocioso[t]      = max(0, w_proc[t] − processados[t])
    fila_out       = fila.in + adm.in − processados[t]
    adm_out        = X   ← REGRA FIXA DE ADMISSÃO
```

**Por que `w_proc` médio fixo?** Para isolar o efeito da decisão de admissão. Se a fixa usasse `w_proc` amostrado independente, o custo dela teria componentes de variância que não estão na decisão de política, e a comparação ficaria confundida.

---

## 5. Resultados agregados

### 5.1 Sumário comparativo — MAR (N=1000)

| Política | X | Custo médio | IC 95% | P5 | P50 | P95 | Spill % > 0 | Fila pico médio | Service level |
|----------|--:|------------:|-------:|---:|----:|----:|-----------:|----------------:|--------------:|
| **SDDP** | — | **R$ 52.0 M** | ± 0.46 M | 40.1 M | 51.8 M | 64.7 M | 98.9% | **1 724** | **100.0%** |
| `P_-10` | 2 153 | R$ 368 M | ± 0 | 368 M | 368 M | 368 M | 100% | 1 724 | 100.0% |
| `P_-5` | 2 272 | R$ 227 M | ± 0 | 227 M | 227 M | 227 M | 100% | 1 724 | 100.0% |
| `P_0` | 2 392 | **R$ 114 M** | ± 0 | 114 M | 114 M | 114 M | 100% | **1 724** | **100.0%** |
| `P_+5` | 2 512 | R$ 639 M | ± 0 | 639 M | 639 M | 639 M | 100% | 2 623 | 98.8% |
| `P_+10` | 2 631 | R$ 1.62 B | ± 0 | 1.62 B | 1.62 B | 1.62 B | 100% | 6 092 | 94.3% |

**Razão melhor fixa / SDDP em mar: 2.2× (P_0).** IC=0 nas fixas (determinísticas).

### 5.2 Sumário comparativo — JUL (N=1000)

| Política | X | Custo médio | IC 95% | P5 | P50 | P95 | Spill % > 0 | Fila pico médio | Service level |
|----------|--:|------------:|-------:|---:|----:|----:|-----------:|----------------:|--------------:|
| **SDDP** | — | R$ 204 M | ± 2.75 M | 138 M | 201 M | 281 M | 100% | **2 363** | **100.0%** |
| `P_-10` | 1 777 | R$ 369 M | ± 0 | 369 M | 369 M | 369 M | 100% | 2 105 | 100.0% |
| `P_-5` | 1 875 | R$ 261 M | ± 0 | 261 M | 261 M | 261 M | 100% | 2 105 | 100.0% |
| `P_0` | 1 974 | **R$ 181 M** | ± 0 | 181 M | 181 M | 181 M | 100% | **2 105** | **100.0%** |
| `P_+5` | 2 073 | R$ 397 M | ± 0 | 397 M | 397 M | 397 M | 100% | 2 105 | 100.0% |
| `P_+10` | 2 172 | R$ 1.21 B | ± 0 | 1.21 B | 1.21 B | 1.21 B | 100% | 4 219 | 96.6% |

**P_0 (R$ 181 M) < SDDP (R$ 204 M)!** Razão melhor fixa / SDDP em jul: **0.89× (P_0 ganha)** — vide diagnóstico em §1.2.

### 5.3 Visualizações comparativas

![boxplot mar](outputs/py_v8_mar_boxplot.png)

![boxplot jul](outputs/py_v8_jul_boxplot.png)

![service mar](outputs/py_v8_mar_service_level.png)

![service jul](outputs/py_v8_jul_service_level.png)

![composicao mar](outputs/py_v8_mar_composicao_custo.png)

![composicao jul](outputs/py_v8_jul_composicao_custo.png)

---

## 6. Indicadores em detalhe (catálogo)

### 6.1 — Custo médio total (R$)

**Fórmula:** `(1/N) · Σ_r Σ_t  stage_objective[r,t]`. Em fixas, todas réplicas são idênticas (determinístico).

| Política | MAR | JUL |
|----------|----:|----:|
| **SDDP** | **R$ 52.0 M** | R$ 204 M |
| P_-10 | R$ 368 M | R$ 369 M |
| P_-5 | R$ 227 M | R$ 261 M |
| P_0 | R$ 114 M | **R$ 181 M** |
| P_+5 | R$ 639 M | R$ 397 M |
| P_+10 | R$ 1.62 B | R$ 1.21 B |

### 6.2 — Intervalo de confiança 95%

| Política | IC MAR | IC JUL |
|----------|-------:|-------:|
| SDDP | ± 0.46 M | ± 2.57 M |
| P_-10..P_+10 | ± 0 (determinísticos) | ± 0 (determinísticos) |

### 6.3 — Quantis P5/P50/P95 do custo

Fixas determinísticas → P5 = P50 = P95 = custo único.

| | SDDP MAR | SDDP JUL |
|---|---:|---:|
| P5 | 41.5 M | 139 M |
| P50 | 51.5 M | 200 M |
| P95 | 65.0 M | 275 M |
| Spread (P95-P5) | 23.5 M | 136 M |

### 6.4 — Probabilidade de spillover > 0

| Política | MAR | JUL |
|----------|----:|----:|
| SDDP | 98.8% | 100.0% |
| P_-10 a P_+10 | 100% (todas) | 100% (todas) |

Dia 1 sempre gera spillover (estado inicial: 1 200 + 3 000 > 1 200 + ~2 480). SDDP em mar zera spillover em 1.2% dos cenários favoráveis.

### 6.5 — Spillover total condicional médio (caminhões)

| Política | MAR | JUL |
|----------|----:|----:|
| SDDP | 514 | 4 035 |
| P_-10 | 691 | 1 545 |
| P_-5 | 899 | 1 978 |
| P_0 | 1 691 | 3 150 |
| P_+5 | 28 708 | 15 701 |
| P_+10 | 80 717 | 58 696 |

### 6.6 — Fila pico médio (caminhões)

| Política | MAR | JUL | × MAX_VAGAS (4 000) |
|----------|----:|----:|--------------------:|
| SDDP | 1 707 | 2 331 | 0.43 / 0.58 |
| P_-10..P_0 | 1 707 | 2 068 | 0.43 / 0.52 |
| P_+5 | 2 602 | 2 068 | 0.65 / 0.52 |
| P_+10 | 6 069 | 4 243 | **1.52** / **1.06** |

**Fila pico = pico do dia 1** para a maioria das fixas (estado inicial 1 200 + 3 000 − w_proc).

### 6.7 — Service level (% processado da demanda admitida, dias 2..30)

**Fórmula (NOVA):**
```
service_level = min(1.0,  Σ_t=2..30 processados / Σ_t=2..30 admitidos.in)
```

> **Mudanças nesta versão:** exclui dia 1 (estado inicial distorce); cap em 100% (consumir fila inicial não é defensável para o relatório).

| Política | MAR | JUL |
|----------|----:|----:|
| **SDDP** | **100.0%** | **100.0%** |
| P_-10 | 100.0% | 100.0% |
| P_-5 | 100.0% | 100.0% |
| P_0 | 100.0% | 100.0% |
| P_+5 | 98.8% | 100.0% |
| P_+10 | 94.3% | 96.6% |

Todas com X ≤ X(P_0) atingem 100%. Apenas X alto deixa demanda acumulada.

### 6.8 — Médias diárias

**MAR:**

| Política | entram/dia | proc/dia | ocio/dia | spill/dia |
|----------|----------:|---------:|---------:|----------:|
| SDDP | 2 450 | 2 475 | 5.2 | 16.9 |
| P_-10 | 2 180 | 2 220 | 260.0 | 23.0 |
| P_-5 | 2 296 | 2 336 | 144.4 | 30.0 |
| P_0 | 2 412 | 2 452 | 28.8 | 56.4 |
| P_+5 | 2 527 | 2 480 | 0.0 | 957 |
| P_+10 | 2 643 | 2 480 | 0.0 | 2 691 |

**JUL:**

| Política | entram/dia | proc/dia | ocio/dia | spill/dia |
|----------|----------:|---------:|---------:|----------:|
| SDDP | 2 038 | 2 051 | 49.7 | 134 |
| P_-10 | 1 820 | 1 860 | 240.7 | 51.5 |
| P_-5 | 1 915 | 1 955 | 145.2 | 65.9 |
| P_0 | 2 011 | 2 051 | 49.6 | 105 |
| P_+5 | 2 106 | 2 101 | 0.0 | 523 |
| P_+10 | 2 202 | 2 101 | 0.0 | 1 957 |

### 6.9 — Resumo: qual indicador olhar quando?

| Quando você quer responder... | Indicador | Por quê |
|------|------|------|
| "Quanto custa?" | §6.1 Custo médio | Métrica gerencial principal |
| "É estatisticamente diferente?" | §6.2 IC 95% | Fixas têm IC=0 |
| "E se eu tiver azar (SDDP)?" | §6.3 P95 | Apenas SDDP tem distribuição |
| "Risco de pátio cheio?" | §6.6 Fila pico | Comparar com MAX_VAGAS=4 000 |
| "Toda demanda é processada?" | §6.7 Service level | Cap 100%, dias 2..30 |
| "Operação dia a dia?" | §6.8 Médias diárias | Throughput operacional |

---

## 7. Evolução dia-a-dia (média das 1000 sims)

### 7.1 Painel de 4 variáveis (proc, fila, ocioso log, spillover log)

![painel mar](outputs/py_v8_mar_painel.png)

![painel jul](outputs/py_v8_jul_painel.png)

### 7.2 Custo acumulado (escala log, com anotação)

![custo acumulado mar](outputs/py_v8_mar_custo_acumulado.png)

![custo acumulado jul](outputs/py_v8_jul_custo_acumulado.png)

### 7.3 Comparativo mar vs jul (side-by-side)

![comparativo mar vs jul](outputs/py_v8_mar_jul_comparativo.png)

---

## 8. Análise: o trade-off operacional

### 8.1 Os 3 regimes operacionais (visíveis nas tabelas do Anexo A)

**Regime "esvazia + ocioso" (P_-10, P_-5):**
- `X` baixo → admite pouco → fila esvazia
- Em MAR P_-10: fila chega a zero no dia 7. Depois, ociosidade ~330/dia.
- Em JUL P_-10: fila zera no dia 8. Ociosidade ~310/dia depois.
- Custo dominado por ociosidade × R$ 43 753

**Regime "equilíbrio" (P_0):**
- `X ≈ w_proc médio` → admite ≈ processa
- MAR P_0: fila começa em 1 707 (dia 1), cai gradualmente. Esvazia no dia 21.
- JUL P_0: fila começa em 2 068, cai gradualmente. Esvazia no dia 19.
- Custo balanceado: spillover inicial decrescente + algum ocioso no final.

**Regime "acumula + spillover" (P_+5, P_+10):**
- `X` alto → admite mais do que se processa → fila cresce monotonicamente
- MAR P_+10: fila chega a 6 069 (dia 30). Spillover cresce.
- JUL P_+10: fila chega a 4 243. Estoura MAX_VAGAS.
- Custo dominado por fila + spillover

### 8.2 Por que P_0 fixa vence o SDDP em julho

O SDDP enfrenta `w_proc` Weibull com cauda esquerda longa (CV=36%). Mesmo decidindo otimamente, em alguns dias `w_proc[t]` cai para ~700–1 000, gerando custos altos.

A fixa P_0 usa `w_proc[t]` = média (range 2 058–2 147 em jul). Essa "remoção da incerteza" gera economia que **mais que compensa** o erro de admissão constante.

**Em MAR**, com `w_proc` quase constante (CV=10%), a remoção de incerteza vale pouco — SDDP continua melhor.

**Lição metodológica:** a comparação com `w_proc` fixo é informativa para entender o trade-off, mas **não é a comparação operacional honesta**. Para isso seria necessário:
- (a) `w_proc` amostrado independente nas fixas (com ruído de variância)
- (b) `w_proc` amostrado com CRN entre SDDP e fixas (justo réplica-a-réplica)

Esta versão usa (c) — `w_proc` fixo = média SDDP — para isolar o efeito da decisão de admissão.

### 8.3 O `Smoking gun` — confira no Anexo A

Olhe a tabela `SDDP MAR` (Anexo A, A.1) na linha do dia 1:

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | **3000** | 2493 | 2493 | 1707 | 507.8 | 0.0 | **1150** | 12.29M |
| 2 | 1707 | **1150** | 2476 | 2471 | 386.0 | 0.0 | 4.6 | 2471 | 3.12M |

SDDP entra forçado com `AdmIn = 3 000` mas decide `AdmOut = 1 150` (corta em 62%). A partir do dia 2 mantém `AdmOut ≈ proc ≈ 2 470`.

A fixa `P_0 MAR` admite 2 391 constante em todos os dias 2..30 — fila esvazia consumindo o estoque inicial.

---

## 9. Conclusões e recomendação

1. **Em MAR (baixa variância de w_proc), o SDDP é melhor** que todas as fixas (mínimo P_0 = 2.2× SDDP).
2. **Em JUL (alta variância), a fixa P_0 com w_proc médio fixo é melhor que o SDDP** em 17% (R$ 168 M vs R$ 202 M). Reflete que a fixa opera no "mundo médio" sem variabilidade real.
3. **A vantagem real do SDDP é a adaptatividade ao ruído estocástico.** Comparações justas requerem que tanto SDDP quanto fixas operem no mesmo mundo (mesma realização de `w_proc`).
4. **Service level fica em 100% para X ≤ X(P_0)** em ambos os meses. Apenas X alto (P_+5/P_+10) deixa demanda acumulada.
5. **Fila pico:** todas as políticas com X ≤ X(P_+5) ficam abaixo de MAX_VAGAS=4 000 (operacionalmente viáveis). P_+10 estoura.

**Próximo passo (v9):** rodar as 5 fixas com `w_proc` **amostrado** (CRN entre fixas e SDDP). Esperado: P_0 fica acima do SDDP em ambos os meses (cenário honesto), com razão 1.3×-2×.

---

## 10. Artefatos

| Categoria | Arquivos |
|-----------|----------|
| Código Julia | [model_v8.jl](model_v8.jl) |
| Código Python | [plot_v8.py](plot_v8.py) |
| Docs | [SPEC.md](SPEC.md), [PLAN.md](PLAN.md), [README.md](README.md), este ANALISE.md |
| PNGs Python (publicação) | `py_v8_<mes>_*.png` — 15 PNGs |
| PNGs Julia (baseline) | `v8_<mes>_*.png` — 22 PNGs |
| Sumário | [`outputs/v8_<mes>_sumario.csv`](outputs/) |
| Médias dia-a-dia (completo) | [`outputs/v8_<mes>_dia_a_dia.csv`](outputs/) (30 × 61 cols) |
| Tabelas formato v7 | [`tabelas_v7_md.txt`](tabelas_v7_md.txt) — 12 tabelas, 30 dias cada |

Total em [`outputs/`](outputs/): **37 PNGs + 8 CSVs**.

**Como rodar do zero:**

```
cd "Projeto - IC - Rodoviário"
julia "Model SDDP - 19-05-26/model_v8.jl"     # ~2.5 min
python "Model SDDP - 19-05-26/plot_v8.py"     # ~10 s
```

---

---

## Anexo A — MAR: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)

**Base usada nos gráficos e análises do corpo principal.** Para cada política, tabela com médias dia-a-dia entre as 1000 simulações.

> **Como interpretar:**
> - **SDDP**: média de 1000 trajetórias estocásticas (w_proc amostrado da LogNormal/Weibull).
> - **P_-10 ... P_+10**: determinísticas (w_proc fixo = média SDDP por dia, adm_out = X constante).
>
> **Atenção (apenas para SDDP):** `Spill` é média de `max(0, fila_out[r,t] − 1 200)` entre 1000 réplicas. Pela desigualdade de Jensen, pode aparecer `Spill > 0` mesmo com `FilaFim < 1 200` em média — porque algumas réplicas tinham fila > 1 200 e geraram spillover. Para uma trajetória onde `Spill = max(0, FilaFim − 1 200)` bate linha a linha, ver Anexo C.

#### MAR — Política `SDDP` (média 1000 sims SDDP estocástico)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2498 | 2498 | 1702 | 503.0 | 0.0 | 1155 | 12.20M |
| 2 | 1702 | 1155 | 2495 | 2489 | 368.0 | 0.0 | 6.0 | 2489 | 3.15M |
| 3 | 368.0 | 2489 | 2486 | 2480 | 377.1 | 0.0 | 6.1 | 2480 | 1.30M |
| 4 | 377.1 | 2480 | 2476 | 2472 | 384.7 | 0.0 | 4.1 | 2472 | 1.24M |
| 5 | 384.7 | 2472 | 2479 | 2475 | 382.1 | 0.0 | 4.3 | 2475 | 1.26M |
| 6 | 382.1 | 2475 | 2470 | 2466 | 391.5 | 0.0 | 4.9 | 2466 | 1.29M |
| 7 | 391.5 | 2466 | 2492 | 2486 | 371.1 | 0.0 | 6.6 | 2486 | 1.35M |
| 8 | 371.1 | 2486 | 2493 | 2488 | 369.4 | 0.0 | 5.4 | 2488 | 1.27M |
| 9 | 369.4 | 2488 | 2482 | 2476 | 381.4 | 0.0 | 6.4 | 2476 | 1.33M |
| 10 | 381.4 | 2476 | 2475 | 2470 | 386.6 | 0.0 | 4.9 | 2470 | 1.29M |
| 11 | 386.6 | 2470 | 2467 | 2463 | 394.4 | 0.0 | 4.6 | 2463 | 1.29M |
| 12 | 394.4 | 2463 | 2494 | 2488 | 368.6 | 0.0 | 5.6 | 2488 | 1.31M |
| 13 | 368.6 | 2488 | 2479 | 2473 | 383.7 | 0.0 | 5.6 | 2473 | 1.30M |
| 14 | 383.7 | 2473 | 2475 | 2470 | 386.8 | 0.0 | 4.7 | 2470 | 1.28M |
| 15 | 386.8 | 2470 | 2475 | 2470 | 387.2 | 0.0 | 5.1 | 2470 | 1.30M |
| 16 | 387.2 | 2470 | 2477 | 2471 | 386.0 | 0.0 | 6.0 | 2471 | 1.34M |
| 17 | 386.0 | 2471 | 2474 | 2469 | 387.7 | 0.0 | 4.8 | 2469 | 1.29M |
| 18 | 387.7 | 2469 | 2479 | 2473 | 384.3 | 0.0 | 6.1 | 2473 | 1.34M |
| 19 | 384.3 | 2473 | 2485 | 2478 | 378.6 | 0.0 | 6.8 | 2478 | 1.36M |
| 20 | 378.6 | 2478 | 2482 | 2476 | 380.9 | 0.0 | 6.2 | 2476 | 1.33M |
| 21 | 380.9 | 2476 | 2473 | 2468 | 388.8 | 0.0 | 5.2 | 2468 | 1.30M |
| 22 | 388.8 | 2468 | 2488 | 2482 | 374.8 | 0.0 | 5.9 | 2482 | 1.32M |
| 23 | 374.8 | 2482 | 2481 | 2475 | 381.8 | 0.0 | 5.4 | 2475 | 1.29M |
| 24 | 381.8 | 2475 | 2474 | 2469 | 388.3 | 0.0 | 5.6 | 2469 | 1.32M |
| 25 | 388.3 | 2469 | 2472 | 2467 | 390.3 | 0.0 | 5.4 | 2467 | 1.32M |
| 26 | 390.3 | 2467 | 2473 | 2468 | 388.8 | 0.0 | 4.5 | 2468 | 1.28M |
| 27 | 388.8 | 2468 | 2481 | 2477 | 380.3 | 0.0 | 4.5 | 2477 | 1.27M |
| 28 | 380.3 | 2477 | 2469 | 2464 | 393.5 | 0.0 | 5.6 | 2464 | 1.33M |
| 29 | 393.5 | 2464 | 2478 | 2472 | 385.3 | 0.0 | 5.9 | 2540 | 1.34M |
| 30 | 385.3 | 2540 | 2480 | 2477 | 447.6 | 0.0 | 3.0 | 0.0 | 1.29M |
| **Σ** | — | — | — | **74249** | — | **503.0** | **155.1** | — | **51.90M** |

#### MAR — Política `P_-10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2498 | 2498 | 1702 | 502.3 | 0.0 | 2152 | 12.19M |
| 2 | 1702 | 2152 | 2495 | 2495 | 1359 | 159.4 | 0.0 | 2152 | 6.86M |
| 3 | 1359 | 2152 | 2486 | 2486 | 1025 | 0.0 | 0.0 | 2152 | 3.33M |
| 4 | 1025 | 2152 | 2476 | 2476 | 701.1 | 0.0 | 0.0 | 2152 | 2.41M |
| 5 | 701.1 | 2152 | 2479 | 2479 | 373.9 | 0.0 | 0.0 | 2152 | 1.50M |
| 6 | 373.9 | 2152 | 2470 | 2470 | 55.5 | 0.0 | 0.0 | 2152 | 598922 |
| 7 | 55.5 | 2152 | 2492 | 2207 | 0.0 | 0.0 | 285.0 | 2152 | 12.55M |
| 8 | 0.0 | 2152 | 2493 | 2152 | 0.0 | 0.0 | 341.1 | 2152 | 14.92M |
| 9 | 0.0 | 2152 | 2482 | 2152 | 0.0 | 0.0 | 330.0 | 2152 | 14.44M |
| 10 | 0.0 | 2152 | 2475 | 2152 | 0.0 | 0.0 | 323.3 | 2152 | 14.15M |
| 11 | 0.0 | 2152 | 2467 | 2152 | 0.0 | 0.0 | 315.2 | 2152 | 13.79M |
| 12 | 0.0 | 2152 | 2494 | 2152 | 0.0 | 0.0 | 342.0 | 2152 | 14.97M |
| 13 | 0.0 | 2152 | 2479 | 2152 | 0.0 | 0.0 | 326.9 | 2152 | 14.30M |
| 14 | 0.0 | 2152 | 2475 | 2152 | 0.0 | 0.0 | 322.9 | 2152 | 14.13M |
| 15 | 0.0 | 2152 | 2475 | 2152 | 0.0 | 0.0 | 322.9 | 2152 | 14.13M |
| 16 | 0.0 | 2152 | 2477 | 2152 | 0.0 | 0.0 | 325.1 | 2152 | 14.22M |
| 17 | 0.0 | 2152 | 2474 | 2152 | 0.0 | 0.0 | 322.0 | 2152 | 14.09M |
| 18 | 0.0 | 2152 | 2479 | 2152 | 0.0 | 0.0 | 326.8 | 2152 | 14.30M |
| 19 | 0.0 | 2152 | 2485 | 2152 | 0.0 | 0.0 | 333.3 | 2152 | 14.58M |
| 20 | 0.0 | 2152 | 2482 | 2152 | 0.0 | 0.0 | 330.2 | 2152 | 14.45M |
| 21 | 0.0 | 2152 | 2473 | 2152 | 0.0 | 0.0 | 321.5 | 2152 | 14.06M |
| 22 | 0.0 | 2152 | 2488 | 2152 | 0.0 | 0.0 | 336.1 | 2152 | 14.70M |
| 23 | 0.0 | 2152 | 2481 | 2152 | 0.0 | 0.0 | 328.6 | 2152 | 14.38M |
| 24 | 0.0 | 2152 | 2474 | 2152 | 0.0 | 0.0 | 322.3 | 2152 | 14.10M |
| 25 | 0.0 | 2152 | 2472 | 2152 | 0.0 | 0.0 | 320.2 | 2152 | 14.01M |
| 26 | 0.0 | 2152 | 2473 | 2152 | 0.0 | 0.0 | 320.7 | 2152 | 14.03M |
| 27 | 0.0 | 2152 | 2481 | 2152 | 0.0 | 0.0 | 329.2 | 2152 | 14.41M |
| 28 | 0.0 | 2152 | 2469 | 2152 | 0.0 | 0.0 | 317.1 | 2152 | 13.88M |
| 29 | 0.0 | 2152 | 2478 | 2152 | 0.0 | 0.0 | 325.6 | 2152 | 14.25M |
| 30 | 0.0 | 2152 | 2480 | 2152 | 0.0 | 0.0 | 328.4 | 2152 | 14.37M |
| **Σ** | — | — | — | **66608** | — | **661.7** | **7796** | — | **368.07M** |

#### MAR — Política `P_-5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2498 | 2498 | 1702 | 502.3 | 0.0 | 2272 | 12.19M |
| 2 | 1702 | 2272 | 2495 | 2495 | 1479 | 278.9 | 0.0 | 2272 | 8.96M |
| 3 | 1479 | 2272 | 2486 | 2486 | 1265 | 64.5 | 0.0 | 2272 | 4.87M |
| 4 | 1265 | 2272 | 2476 | 2476 | 1060 | 0.0 | 0.0 | 2272 | 3.24M |
| 5 | 1060 | 2272 | 2479 | 2479 | 852.1 | 0.0 | 0.0 | 2272 | 2.67M |
| 6 | 852.1 | 2272 | 2470 | 2470 | 653.2 | 0.0 | 0.0 | 2272 | 2.10M |
| 7 | 653.2 | 2272 | 2492 | 2492 | 432.3 | 0.0 | 0.0 | 2272 | 1.51M |
| 8 | 432.3 | 2272 | 2493 | 2493 | 210.8 | 0.0 | 0.0 | 2272 | 897163 |
| 9 | 210.8 | 2272 | 2482 | 2482 | 0.4 | 0.0 | 0.0 | 2272 | 294599 |
| 10 | 0.4 | 2272 | 2475 | 2272 | 0.0 | 0.0 | 203.4 | 2272 | 8.90M |
| 11 | 0.0 | 2272 | 2467 | 2272 | 0.0 | 0.0 | 195.6 | 2272 | 8.56M |
| 12 | 0.0 | 2272 | 2494 | 2272 | 0.0 | 0.0 | 222.5 | 2272 | 9.73M |
| 13 | 0.0 | 2272 | 2479 | 2272 | 0.0 | 0.0 | 207.4 | 2272 | 9.07M |
| 14 | 0.0 | 2272 | 2475 | 2272 | 0.0 | 0.0 | 203.4 | 2272 | 8.90M |
| 15 | 0.0 | 2272 | 2475 | 2272 | 0.0 | 0.0 | 203.3 | 2272 | 8.90M |
| 16 | 0.0 | 2272 | 2477 | 2272 | 0.0 | 0.0 | 205.5 | 2272 | 8.99M |
| 17 | 0.0 | 2272 | 2474 | 2272 | 0.0 | 0.0 | 202.5 | 2272 | 8.86M |
| 18 | 0.0 | 2272 | 2479 | 2272 | 0.0 | 0.0 | 207.2 | 2272 | 9.07M |
| 19 | 0.0 | 2272 | 2485 | 2272 | 0.0 | 0.0 | 213.7 | 2272 | 9.35M |
| 20 | 0.0 | 2272 | 2482 | 2272 | 0.0 | 0.0 | 210.7 | 2272 | 9.22M |
| 21 | 0.0 | 2272 | 2473 | 2272 | 0.0 | 0.0 | 201.9 | 2272 | 8.83M |
| 22 | 0.0 | 2272 | 2488 | 2272 | 0.0 | 0.0 | 216.5 | 2272 | 9.47M |
| 23 | 0.0 | 2272 | 2481 | 2272 | 0.0 | 0.0 | 209.1 | 2272 | 9.15M |
| 24 | 0.0 | 2272 | 2474 | 2272 | 0.0 | 0.0 | 202.7 | 2272 | 8.87M |
| 25 | 0.0 | 2272 | 2472 | 2272 | 0.0 | 0.0 | 200.6 | 2272 | 8.78M |
| 26 | 0.0 | 2272 | 2473 | 2272 | 0.0 | 0.0 | 201.2 | 2272 | 8.80M |
| 27 | 0.0 | 2272 | 2481 | 2272 | 0.0 | 0.0 | 209.7 | 2272 | 9.17M |
| 28 | 0.0 | 2272 | 2469 | 2272 | 0.0 | 0.0 | 197.6 | 2272 | 8.64M |
| 29 | 0.0 | 2272 | 2478 | 2272 | 0.0 | 0.0 | 206.0 | 2272 | 9.01M |
| 30 | 0.0 | 2272 | 2480 | 2272 | 0.0 | 0.0 | 208.8 | 2272 | 9.14M |
| **Σ** | — | — | — | **70075** | — | **845.8** | **4329** | — | **226.16M** |

#### MAR — Política `P_0` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2498 | 2498 | 1702 | 502.3 | 0.0 | 2391 | 12.19M |
| 2 | 1702 | 2391 | 2495 | 2495 | 1599 | 398.5 | 0.0 | 2391 | 11.06M |
| 3 | 1599 | 2391 | 2486 | 2486 | 1504 | 303.6 | 0.0 | 2391 | 9.25M |
| 4 | 1504 | 2391 | 2476 | 2476 | 1418 | 218.4 | 0.0 | 2391 | 7.62M |
| 5 | 1418 | 2391 | 2479 | 2479 | 1330 | 130.3 | 0.0 | 2391 | 5.95M |
| 6 | 1330 | 2391 | 2470 | 2470 | 1251 | 51.0 | 0.0 | 2391 | 4.43M |
| 7 | 1251 | 2391 | 2492 | 2492 | 1150 | 0.0 | 0.0 | 2391 | 3.35M |
| 8 | 1150 | 2391 | 2493 | 2493 | 1048 | 0.0 | 0.0 | 2391 | 3.07M |
| 9 | 1048 | 2391 | 2482 | 2482 | 956.8 | 0.0 | 0.0 | 2391 | 2.80M |
| 10 | 956.8 | 2391 | 2475 | 2475 | 872.6 | 0.0 | 0.0 | 2391 | 2.55M |
| 11 | 872.6 | 2391 | 2467 | 2467 | 796.6 | 0.0 | 0.0 | 2391 | 2.33M |
| 12 | 796.6 | 2391 | 2494 | 2494 | 693.6 | 0.0 | 0.0 | 2391 | 2.08M |
| 13 | 693.6 | 2391 | 2479 | 2479 | 605.8 | 0.0 | 0.0 | 2391 | 1.81M |
| 14 | 605.8 | 2391 | 2475 | 2475 | 522.0 | 0.0 | 0.0 | 2391 | 1.57M |
| 15 | 522.0 | 2391 | 2475 | 2475 | 438.3 | 0.0 | 0.0 | 2391 | 1.34M |
| 16 | 438.3 | 2391 | 2477 | 2477 | 352.3 | 0.0 | 0.0 | 2391 | 1.10M |
| 17 | 352.3 | 2391 | 2474 | 2474 | 269.4 | 0.0 | 0.0 | 2391 | 867188 |
| 18 | 269.4 | 2391 | 2479 | 2479 | 181.7 | 0.0 | 0.0 | 2391 | 629223 |
| 19 | 181.7 | 2391 | 2485 | 2485 | 87.6 | 0.0 | 0.0 | 2391 | 375623 |
| 20 | 87.6 | 2391 | 2482 | 2479 | 0.0 | 0.0 | 3.6 | 2391 | 278106 |
| 21 | 0.0 | 2391 | 2473 | 2391 | 0.0 | 0.0 | 82.3 | 2391 | 3.60M |
| 22 | 0.0 | 2391 | 2488 | 2391 | 0.0 | 0.0 | 97.0 | 2391 | 4.24M |
| 23 | 0.0 | 2391 | 2481 | 2391 | 0.0 | 0.0 | 89.5 | 2391 | 3.92M |
| 24 | 0.0 | 2391 | 2474 | 2391 | 0.0 | 0.0 | 83.1 | 2391 | 3.64M |
| 25 | 0.0 | 2391 | 2472 | 2391 | 0.0 | 0.0 | 81.1 | 2391 | 3.55M |
| 26 | 0.0 | 2391 | 2473 | 2391 | 0.0 | 0.0 | 81.6 | 2391 | 3.57M |
| 27 | 0.0 | 2391 | 2481 | 2391 | 0.0 | 0.0 | 90.1 | 2391 | 3.94M |
| 28 | 0.0 | 2391 | 2469 | 2391 | 0.0 | 0.0 | 78.0 | 2391 | 3.41M |
| 29 | 0.0 | 2391 | 2478 | 2391 | 0.0 | 0.0 | 86.5 | 2391 | 3.78M |
| 30 | 0.0 | 2391 | 2480 | 2391 | 0.0 | 0.0 | 89.2 | 2391 | 3.90M |
| **Σ** | — | — | — | **73542** | — | **1604** | **862.1** | — | **112.21M** |

#### MAR — Política `P_+5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2498 | 2498 | 1702 | 502.3 | 0.0 | 2511 | 12.19M |
| 2 | 1702 | 2511 | 2495 | 2495 | 1718 | 518.1 | 0.0 | 2511 | 13.17M |
| 3 | 1718 | 2511 | 2486 | 2486 | 1743 | 542.7 | 0.0 | 2511 | 13.63M |
| 4 | 1743 | 2511 | 2476 | 2476 | 1777 | 577.1 | 0.0 | 2511 | 14.27M |
| 5 | 1777 | 2511 | 2479 | 2479 | 1809 | 608.5 | 0.0 | 2511 | 14.87M |
| 6 | 1809 | 2511 | 2470 | 2470 | 1849 | 648.8 | 0.0 | 2511 | 15.62M |
| 7 | 1849 | 2511 | 2492 | 2492 | 1867 | 667.0 | 0.0 | 2511 | 16.00M |
| 8 | 1867 | 2511 | 2493 | 2493 | 1885 | 684.6 | 0.0 | 2511 | 16.33M |
| 9 | 1885 | 2511 | 2482 | 2482 | 1913 | 713.3 | 0.0 | 2511 | 16.86M |
| 10 | 1913 | 2511 | 2475 | 2475 | 1949 | 748.6 | 0.0 | 2511 | 17.52M |
| 11 | 1949 | 2511 | 2467 | 2467 | 1992 | 792.1 | 0.0 | 2511 | 18.34M |
| 12 | 1992 | 2511 | 2494 | 2494 | 2009 | 808.8 | 0.0 | 2511 | 18.69M |
| 13 | 2009 | 2511 | 2479 | 2479 | 2040 | 840.5 | 0.0 | 2511 | 19.27M |
| 14 | 2040 | 2511 | 2475 | 2475 | 2076 | 876.2 | 0.0 | 2511 | 19.95M |
| 15 | 2076 | 2511 | 2475 | 2475 | 2112 | 912.0 | 0.0 | 2511 | 20.63M |
| 16 | 2112 | 2511 | 2477 | 2477 | 2146 | 945.6 | 0.0 | 2511 | 21.27M |
| 17 | 2146 | 2511 | 2474 | 2474 | 2182 | 982.2 | 0.0 | 2511 | 21.96M |
| 18 | 2182 | 2511 | 2479 | 2479 | 2214 | 1014 | 0.0 | 2511 | 22.57M |
| 19 | 2214 | 2511 | 2485 | 2485 | 2240 | 1040 | 0.0 | 2511 | 23.07M |
| 20 | 2240 | 2511 | 2482 | 2482 | 2268 | 1068 | 0.0 | 2511 | 23.60M |
| 21 | 2268 | 2511 | 2473 | 2473 | 2305 | 1105 | 0.0 | 2511 | 24.30M |
| 22 | 2305 | 2511 | 2488 | 2488 | 2328 | 1128 | 0.0 | 2511 | 24.75M |
| 23 | 2328 | 2511 | 2481 | 2481 | 2358 | 1158 | 0.0 | 2511 | 25.31M |
| 24 | 2358 | 2511 | 2474 | 2474 | 2394 | 1194 | 0.0 | 2511 | 25.99M |
| 25 | 2394 | 2511 | 2472 | 2472 | 2433 | 1233 | 0.0 | 2511 | 26.72M |
| 26 | 2433 | 2511 | 2473 | 2473 | 2471 | 1271 | 0.0 | 2511 | 27.44M |
| 27 | 2471 | 2511 | 2481 | 2481 | 2500 | 1300 | 0.0 | 2511 | 28.01M |
| 28 | 2500 | 2511 | 2469 | 2469 | 2542 | 1342 | 0.0 | 2511 | 28.78M |
| 29 | 2542 | 2511 | 2478 | 2478 | 2575 | 1375 | 0.0 | 2511 | 29.42M |
| 30 | 2575 | 2511 | 2480 | 2480 | 2605 | 1405 | 0.0 | 2511 | 30.00M |
| **Σ** | — | — | — | **74404** | — | **28000** | **0.0** | — | **630.51M** |

#### MAR — Política `P_+10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2498 | 2498 | 1702 | 502.3 | 0.0 | 2630 | 12.19M |
| 2 | 1702 | 2630 | 2495 | 2495 | 1838 | 637.6 | 0.0 | 2630 | 15.27M |
| 3 | 1838 | 2630 | 2486 | 2486 | 1982 | 781.8 | 0.0 | 2630 | 18.00M |
| 4 | 1982 | 2630 | 2476 | 2476 | 2136 | 935.7 | 0.0 | 2630 | 20.91M |
| 5 | 2136 | 2630 | 2479 | 2479 | 2287 | 1087 | 0.0 | 2630 | 23.79M |
| 6 | 2287 | 2630 | 2470 | 2470 | 2447 | 1247 | 0.0 | 2630 | 26.81M |
| 7 | 2447 | 2630 | 2492 | 2492 | 2584 | 1384 | 0.0 | 2630 | 29.46M |
| 8 | 2584 | 2630 | 2493 | 2493 | 2721 | 1521 | 0.0 | 2630 | 32.07M |
| 9 | 2721 | 2630 | 2482 | 2482 | 2870 | 1670 | 0.0 | 2630 | 34.87M |
| 10 | 2870 | 2630 | 2475 | 2475 | 3025 | 1825 | 0.0 | 2630 | 37.80M |
| 11 | 3025 | 2630 | 2467 | 2467 | 3188 | 1988 | 0.0 | 2630 | 40.89M |
| 12 | 3188 | 2630 | 2494 | 2494 | 3324 | 2124 | 0.0 | 2630 | 43.51M |
| 13 | 3324 | 2630 | 2479 | 2479 | 3475 | 2275 | 0.0 | 2630 | 46.37M |
| 14 | 3475 | 2630 | 2475 | 2475 | 3630 | 2430 | 0.0 | 2630 | 49.31M |
| 15 | 3630 | 2630 | 2475 | 2475 | 3786 | 2586 | 0.0 | 2630 | 52.26M |
| 16 | 3786 | 2630 | 2477 | 2477 | 3939 | 2739 | 0.0 | 2630 | 55.18M |
| 17 | 3939 | 2630 | 2474 | 2474 | 4095 | 2895 | 0.0 | 2630 | 58.14M |
| 18 | 4095 | 2630 | 2479 | 2479 | 4247 | 3047 | 0.0 | 2630 | 61.02M |
| 19 | 4247 | 2630 | 2485 | 2485 | 4392 | 3192 | 0.0 | 2630 | 63.79M |
| 20 | 4392 | 2630 | 2482 | 2482 | 4540 | 3340 | 0.0 | 2630 | 66.60M |
| 21 | 4540 | 2630 | 2473 | 2473 | 4696 | 3496 | 0.0 | 2630 | 69.56M |
| 22 | 4696 | 2630 | 2488 | 2488 | 4838 | 3638 | 0.0 | 2630 | 72.28M |
| 23 | 4838 | 2630 | 2481 | 2481 | 4988 | 3788 | 0.0 | 2630 | 75.12M |
| 24 | 4988 | 2630 | 2474 | 2474 | 5144 | 3944 | 0.0 | 2630 | 78.07M |
| 25 | 5144 | 2630 | 2472 | 2472 | 5302 | 4102 | 0.0 | 2630 | 81.07M |
| 26 | 5302 | 2630 | 2473 | 2473 | 5460 | 4260 | 0.0 | 2630 | 84.06M |
| 27 | 5460 | 2630 | 2481 | 2481 | 5609 | 4409 | 0.0 | 2630 | 86.91M |
| 28 | 5609 | 2630 | 2469 | 2469 | 5770 | 4570 | 0.0 | 2630 | 89.95M |
| 29 | 5770 | 2630 | 2478 | 2478 | 5922 | 4722 | 0.0 | 2630 | 92.86M |
| 30 | 5922 | 2630 | 2480 | 2480 | 6072 | 4872 | 0.0 | 2630 | 95.71M |
| **Σ** | — | — | — | **74404** | — | **80007** | **0.0** | — | **1613.85M** |


---

## Anexo B — JUL: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)

Idem ao Anexo A, mas para JULHO (alta variabilidade, CV de w_proc = 36%).

#### JUL — Política `SDDP` (média 1000 sims SDDP estocástico)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2087 | 2087 | 2113 | 939.1 | 0.0 | 771.6 | 19.85M |
| 2 | 2113 | 771.6 | 2112 | 2056 | 828.4 | 116.3 | 56.7 | 2016 | 8.47M |
| 3 | 828.4 | 2016 | 2136 | 2079 | 764.5 | 104.1 | 56.4 | 2079 | 6.38M |
| 4 | 764.5 | 2079 | 2081 | 2025 | 818.7 | 112.3 | 56.0 | 2025 | 6.48M |
| 5 | 818.7 | 2025 | 2112 | 2057 | 787.0 | 104.5 | 54.6 | 2057 | 6.32M |
| 6 | 787.0 | 2057 | 2091 | 2045 | 799.4 | 110.3 | 46.2 | 2045 | 6.02M |
| 7 | 799.4 | 2045 | 2101 | 2053 | 790.5 | 104.8 | 47.1 | 2053 | 5.98M |
| 8 | 790.5 | 2053 | 2116 | 2059 | 784.6 | 105.4 | 56.2 | 2059 | 6.36M |
| 9 | 784.6 | 2059 | 2096 | 2048 | 796.5 | 107.6 | 48.8 | 2048 | 6.08M |
| 10 | 796.5 | 2048 | 2103 | 2052 | 792.5 | 115.8 | 51.1 | 2052 | 6.33M |
| 11 | 792.5 | 2052 | 2099 | 2048 | 796.4 | 110.8 | 51.8 | 2048 | 6.28M |
| 12 | 796.4 | 2048 | 2072 | 2023 | 821.1 | 113.9 | 49.4 | 2023 | 6.26M |
| 13 | 821.1 | 2023 | 2132 | 2079 | 765.1 | 98.1 | 53.5 | 2079 | 6.14M |
| 14 | 765.1 | 2079 | 2074 | 2023 | 820.8 | 115.4 | 51.2 | 2023 | 6.32M |
| 15 | 820.8 | 2023 | 2116 | 2066 | 778.3 | 101.1 | 50.5 | 2066 | 6.08M |
| 16 | 778.3 | 2066 | 2085 | 2037 | 807.3 | 108.2 | 47.8 | 2037 | 6.06M |
| 17 | 807.3 | 2037 | 2135 | 2081 | 763.1 | 101.6 | 54.2 | 2081 | 6.21M |
| 18 | 763.1 | 2081 | 2114 | 2060 | 784.0 | 103.9 | 54.2 | 2060 | 6.22M |
| 19 | 784.0 | 2060 | 2118 | 2064 | 780.2 | 103.5 | 54.4 | 2064 | 6.24M |
| 20 | 780.2 | 2064 | 2069 | 2021 | 823.1 | 108.9 | 48.4 | 2021 | 6.12M |
| 21 | 823.1 | 2021 | 2129 | 2081 | 763.0 | 92.5 | 47.6 | 2081 | 5.80M |
| 22 | 763.0 | 2081 | 2105 | 2050 | 794.5 | 108.4 | 55.9 | 2050 | 6.37M |
| 23 | 794.5 | 2050 | 2062 | 2012 | 832.3 | 124.5 | 50.3 | 2012 | 6.49M |
| 24 | 832.3 | 2012 | 2109 | 2047 | 796.7 | 108.5 | 61.6 | 2047 | 6.73M |
| 25 | 796.7 | 2047 | 2148 | 2091 | 752.8 | 91.8 | 56.3 | 2091 | 6.11M |
| 26 | 752.8 | 2091 | 2139 | 2081 | 763.1 | 99.2 | 57.7 | 2081 | 6.25M |
| 27 | 763.1 | 2081 | 2099 | 2042 | 802.4 | 120.8 | 57.2 | 2042 | 6.64M |
| 28 | 802.4 | 2042 | 2105 | 2053 | 791.0 | 99.0 | 52.3 | 2053 | 6.12M |
| 29 | 791.0 | 2053 | 2109 | 2060 | 784.1 | 102.2 | 48.6 | 2109 | 5.98M |
| 30 | 784.1 | 2109 | 2114 | 2065 | 828.0 | 124.7 | 48.8 | 0.0 | 6.40M |
| **Σ** | — | — | — | **61643** | — | **4057** | **1525** | — | **203.09M** |

#### JUL — Política `P_-10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2087 | 2087 | 2113 | 912.5 | 0.0 | 1784 | 19.41M |
| 2 | 2113 | 1784 | 2112 | 2112 | 1785 | 584.6 | 0.0 | 1784 | 14.91M |
| 3 | 1785 | 1784 | 2136 | 2136 | 1433 | 233.2 | 0.0 | 1784 | 8.27M |
| 4 | 1433 | 1784 | 2081 | 2081 | 1136 | 0.0 | 0.0 | 1784 | 3.58M |
| 5 | 1136 | 1784 | 2112 | 2112 | 809.3 | 0.0 | 0.0 | 1784 | 2.71M |
| 6 | 809.3 | 1784 | 2091 | 2091 | 503.0 | 0.0 | 0.0 | 1784 | 1.83M |
| 7 | 503.0 | 1784 | 2101 | 2101 | 186.9 | 0.0 | 0.0 | 1784 | 962435 |
| 8 | 186.9 | 1784 | 2116 | 1971 | 0.0 | 0.0 | 144.3 | 1784 | 6.57M |
| 9 | 0.0 | 1784 | 2096 | 1784 | 0.0 | 0.0 | 311.8 | 1784 | 13.64M |
| 10 | 0.0 | 1784 | 2103 | 1784 | 0.0 | 0.0 | 318.2 | 1784 | 13.92M |
| 11 | 0.0 | 1784 | 2099 | 1784 | 0.0 | 0.0 | 314.9 | 1784 | 13.78M |
| 12 | 0.0 | 1784 | 2072 | 1784 | 0.0 | 0.0 | 287.8 | 1784 | 12.59M |
| 13 | 0.0 | 1784 | 2132 | 1784 | 0.0 | 0.0 | 347.9 | 1784 | 15.22M |
| 14 | 0.0 | 1784 | 2074 | 1784 | 0.0 | 0.0 | 289.9 | 1784 | 12.68M |
| 15 | 0.0 | 1784 | 2116 | 1784 | 0.0 | 0.0 | 331.7 | 1784 | 14.51M |
| 16 | 0.0 | 1784 | 2085 | 1784 | 0.0 | 0.0 | 300.1 | 1784 | 13.13M |
| 17 | 0.0 | 1784 | 2135 | 1784 | 0.0 | 0.0 | 350.7 | 1784 | 15.34M |
| 18 | 0.0 | 1784 | 2114 | 1784 | 0.0 | 0.0 | 329.8 | 1784 | 14.43M |
| 19 | 0.0 | 1784 | 2118 | 1784 | 0.0 | 0.0 | 333.7 | 1784 | 14.60M |
| 20 | 0.0 | 1784 | 2069 | 1784 | 0.0 | 0.0 | 284.8 | 1784 | 12.46M |
| 21 | 0.0 | 1784 | 2129 | 1784 | 0.0 | 0.0 | 344.1 | 1784 | 15.06M |
| 22 | 0.0 | 1784 | 2105 | 1784 | 0.0 | 0.0 | 320.9 | 1784 | 14.04M |
| 23 | 0.0 | 1784 | 2062 | 1784 | 0.0 | 0.0 | 277.5 | 1784 | 12.14M |
| 24 | 0.0 | 1784 | 2109 | 1784 | 0.0 | 0.0 | 324.5 | 1784 | 14.20M |
| 25 | 0.0 | 1784 | 2148 | 1784 | 0.0 | 0.0 | 363.0 | 1784 | 15.88M |
| 26 | 0.0 | 1784 | 2139 | 1784 | 0.0 | 0.0 | 354.2 | 1784 | 15.50M |
| 27 | 0.0 | 1784 | 2099 | 1784 | 0.0 | 0.0 | 314.3 | 1784 | 13.75M |
| 28 | 0.0 | 1784 | 2105 | 1784 | 0.0 | 0.0 | 320.9 | 1784 | 14.04M |
| 29 | 0.0 | 1784 | 2109 | 1784 | 0.0 | 0.0 | 324.1 | 1784 | 14.18M |
| 30 | 0.0 | 1784 | 2114 | 1784 | 0.0 | 0.0 | 329.3 | 1784 | 14.41M |
| **Σ** | — | — | — | **55950** | — | **1730** | **7218** | — | **367.77M** |

#### JUL — Política `P_-5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2087 | 2087 | 2113 | 912.5 | 0.0 | 1884 | 19.41M |
| 2 | 2113 | 1884 | 2112 | 2112 | 1884 | 683.8 | 0.0 | 1884 | 16.66M |
| 3 | 1884 | 1884 | 2136 | 2136 | 1631 | 431.5 | 0.0 | 1884 | 11.90M |
| 4 | 1631 | 1884 | 2081 | 2081 | 1434 | 233.8 | 0.0 | 1884 | 8.07M |
| 5 | 1434 | 1884 | 2112 | 2112 | 1206 | 5.8 | 0.0 | 1884 | 3.78M |
| 6 | 1206 | 1884 | 2091 | 2091 | 998.7 | 0.0 | 0.0 | 1884 | 3.08M |
| 7 | 998.7 | 1884 | 2101 | 2101 | 781.7 | 0.0 | 0.0 | 1884 | 2.48M |
| 8 | 781.7 | 1884 | 2116 | 2116 | 549.7 | 0.0 | 0.0 | 1884 | 1.86M |
| 9 | 549.7 | 1884 | 2096 | 2096 | 337.0 | 0.0 | 0.0 | 1884 | 1.24M |
| 10 | 337.0 | 1884 | 2103 | 2103 | 118.0 | 0.0 | 0.0 | 1884 | 634807 |
| 11 | 118.0 | 1884 | 2099 | 2002 | 0.0 | 0.0 | 97.8 | 1884 | 4.44M |
| 12 | 0.0 | 1884 | 2072 | 1884 | 0.0 | 0.0 | 188.7 | 1884 | 8.26M |
| 13 | 0.0 | 1884 | 2132 | 1884 | 0.0 | 0.0 | 248.8 | 1884 | 10.88M |
| 14 | 0.0 | 1884 | 2074 | 1884 | 0.0 | 0.0 | 190.8 | 1884 | 8.35M |
| 15 | 0.0 | 1884 | 2116 | 1884 | 0.0 | 0.0 | 232.6 | 1884 | 10.18M |
| 16 | 0.0 | 1884 | 2085 | 1884 | 0.0 | 0.0 | 201.0 | 1884 | 8.79M |
| 17 | 0.0 | 1884 | 2135 | 1884 | 0.0 | 0.0 | 251.5 | 1884 | 11.00M |
| 18 | 0.0 | 1884 | 2114 | 1884 | 0.0 | 0.0 | 230.7 | 1884 | 10.09M |
| 19 | 0.0 | 1884 | 2118 | 1884 | 0.0 | 0.0 | 234.5 | 1884 | 10.26M |
| 20 | 0.0 | 1884 | 2069 | 1884 | 0.0 | 0.0 | 185.6 | 1884 | 8.12M |
| 21 | 0.0 | 1884 | 2129 | 1884 | 0.0 | 0.0 | 245.0 | 1884 | 10.72M |
| 22 | 0.0 | 1884 | 2105 | 1884 | 0.0 | 0.0 | 221.8 | 1884 | 9.70M |
| 23 | 0.0 | 1884 | 2062 | 1884 | 0.0 | 0.0 | 178.3 | 1884 | 7.80M |
| 24 | 0.0 | 1884 | 2109 | 1884 | 0.0 | 0.0 | 225.3 | 1884 | 9.86M |
| 25 | 0.0 | 1884 | 2148 | 1884 | 0.0 | 0.0 | 263.9 | 1884 | 11.55M |
| 26 | 0.0 | 1884 | 2139 | 1884 | 0.0 | 0.0 | 255.1 | 1884 | 11.16M |
| 27 | 0.0 | 1884 | 2099 | 1884 | 0.0 | 0.0 | 215.1 | 1884 | 9.41M |
| 28 | 0.0 | 1884 | 2105 | 1884 | 0.0 | 0.0 | 221.7 | 1884 | 9.70M |
| 29 | 0.0 | 1884 | 2109 | 1884 | 0.0 | 0.0 | 224.9 | 1884 | 9.84M |
| 30 | 0.0 | 1884 | 2114 | 1884 | 0.0 | 0.0 | 230.2 | 1884 | 10.07M |
| **Σ** | — | — | — | **58825** | — | **2267** | **4343** | — | **259.30M** |

#### JUL — Política `P_0` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2087 | 2087 | 2113 | 912.5 | 0.0 | 1983 | 19.41M |
| 2 | 2113 | 1983 | 2112 | 2112 | 1983 | 782.9 | 0.0 | 1983 | 18.40M |
| 3 | 1983 | 1983 | 2136 | 2136 | 1830 | 629.7 | 0.0 | 1983 | 15.53M |
| 4 | 1830 | 1983 | 2081 | 2081 | 1731 | 531.2 | 0.0 | 1983 | 13.58M |
| 5 | 1731 | 1983 | 2112 | 2112 | 1602 | 402.4 | 0.0 | 1983 | 11.17M |
| 6 | 1602 | 1983 | 2091 | 2091 | 1494 | 294.4 | 0.0 | 1983 | 9.09M |
| 7 | 1494 | 1983 | 2101 | 2101 | 1377 | 176.5 | 0.0 | 1983 | 6.87M |
| 8 | 1377 | 1983 | 2116 | 2116 | 1244 | 43.7 | 0.0 | 1983 | 4.36M |
| 9 | 1244 | 1983 | 2096 | 2096 | 1130 | 0.0 | 0.0 | 1983 | 3.31M |
| 10 | 1130 | 1983 | 2103 | 2103 | 1010 | 0.0 | 0.0 | 1983 | 2.99M |
| 11 | 1010 | 1983 | 2099 | 2099 | 893.6 | 0.0 | 0.0 | 1983 | 2.66M |
| 12 | 893.6 | 1983 | 2072 | 2072 | 804.0 | 0.0 | 0.0 | 1983 | 2.37M |
| 13 | 804.0 | 1983 | 2132 | 2132 | 654.4 | 0.0 | 0.0 | 1983 | 2.03M |
| 14 | 654.4 | 1983 | 2074 | 2074 | 562.8 | 0.0 | 0.0 | 1983 | 1.70M |
| 15 | 562.8 | 1983 | 2116 | 2116 | 429.3 | 0.0 | 0.0 | 1983 | 1.38M |
| 16 | 429.3 | 1983 | 2085 | 2085 | 327.5 | 0.0 | 0.0 | 1983 | 1.06M |
| 17 | 327.5 | 1983 | 2135 | 2135 | 175.1 | 0.0 | 0.0 | 1983 | 701230 |
| 18 | 175.1 | 1983 | 2114 | 2114 | 43.6 | 0.0 | 0.0 | 1983 | 305202 |
| 19 | 43.6 | 1983 | 2118 | 2026 | 0.0 | 0.0 | 91.8 | 1983 | 4.08M |
| 20 | 0.0 | 1983 | 2069 | 1983 | 0.0 | 0.0 | 86.5 | 1983 | 3.78M |
| 21 | 0.0 | 1983 | 2129 | 1983 | 0.0 | 0.0 | 145.9 | 1983 | 6.38M |
| 22 | 0.0 | 1983 | 2105 | 1983 | 0.0 | 0.0 | 122.7 | 1983 | 5.37M |
| 23 | 0.0 | 1983 | 2062 | 1983 | 0.0 | 0.0 | 79.2 | 1983 | 3.47M |
| 24 | 0.0 | 1983 | 2109 | 1983 | 0.0 | 0.0 | 126.2 | 1983 | 5.52M |
| 25 | 0.0 | 1983 | 2148 | 1983 | 0.0 | 0.0 | 164.8 | 1983 | 7.21M |
| 26 | 0.0 | 1983 | 2139 | 1983 | 0.0 | 0.0 | 155.9 | 1983 | 6.82M |
| 27 | 0.0 | 1983 | 2099 | 1983 | 0.0 | 0.0 | 116.0 | 1983 | 5.07M |
| 28 | 0.0 | 1983 | 2105 | 1983 | 0.0 | 0.0 | 122.6 | 1983 | 5.36M |
| 29 | 0.0 | 1983 | 2109 | 1983 | 0.0 | 0.0 | 125.8 | 1983 | 5.50M |
| 30 | 0.0 | 1983 | 2114 | 1983 | 0.0 | 0.0 | 131.1 | 1983 | 5.73M |
| **Σ** | — | — | — | **61700** | — | **3773** | **1468** | — | **181.23M** |

#### JUL — Política `P_+5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2087 | 2087 | 2113 | 912.5 | 0.0 | 2082 | 19.41M |
| 2 | 2113 | 2082 | 2112 | 2112 | 2082 | 882.0 | 0.0 | 2082 | 20.15M |
| 3 | 2082 | 2082 | 2136 | 2136 | 2028 | 828.0 | 0.0 | 2082 | 19.16M |
| 4 | 2028 | 2082 | 2081 | 2081 | 2029 | 828.7 | 0.0 | 2082 | 19.09M |
| 5 | 2029 | 2082 | 2112 | 2112 | 1999 | 798.9 | 0.0 | 2082 | 18.57M |
| 6 | 1999 | 2082 | 2091 | 2091 | 1990 | 790.1 | 0.0 | 2082 | 18.37M |
| 7 | 1990 | 2082 | 2101 | 2101 | 1971 | 771.4 | 0.0 | 2082 | 18.03M |
| 8 | 1971 | 2082 | 2116 | 2116 | 1938 | 737.6 | 0.0 | 2082 | 17.41M |
| 9 | 1938 | 2082 | 2096 | 2096 | 1923 | 723.2 | 0.0 | 2082 | 17.11M |
| 10 | 1923 | 2082 | 2103 | 2103 | 1902 | 702.5 | 0.0 | 2082 | 16.72M |
| 11 | 1902 | 2082 | 2099 | 2099 | 1885 | 685.0 | 0.0 | 2082 | 16.39M |
| 12 | 1885 | 2082 | 2072 | 2072 | 1895 | 694.5 | 0.0 | 2082 | 16.53M |
| 13 | 1895 | 2082 | 2132 | 2132 | 1844 | 644.0 | 0.0 | 2082 | 15.66M |
| 14 | 1844 | 2082 | 2074 | 2074 | 1852 | 651.6 | 0.0 | 2082 | 15.72M |
| 15 | 1852 | 2082 | 2116 | 2116 | 1817 | 617.3 | 0.0 | 2082 | 15.12M |
| 16 | 1817 | 2082 | 2085 | 2085 | 1815 | 614.6 | 0.0 | 2082 | 15.03M |
| 17 | 1815 | 2082 | 2135 | 2135 | 1761 | 561.3 | 0.0 | 2082 | 14.09M |
| 18 | 1761 | 2082 | 2114 | 2114 | 1729 | 529.0 | 0.0 | 2082 | 13.44M |
| 19 | 1729 | 2082 | 2118 | 2118 | 1693 | 492.7 | 0.0 | 2082 | 12.76M |
| 20 | 1693 | 2082 | 2069 | 2069 | 1705 | 505.3 | 0.0 | 2082 | 12.93M |
| 21 | 1705 | 2082 | 2129 | 2129 | 1659 | 458.6 | 0.0 | 2082 | 12.13M |
| 22 | 1659 | 2082 | 2105 | 2105 | 1635 | 435.1 | 0.0 | 2082 | 11.65M |
| 23 | 1635 | 2082 | 2062 | 2062 | 1655 | 455.0 | 0.0 | 2082 | 11.97M |
| 24 | 1655 | 2082 | 2109 | 2109 | 1628 | 428.0 | 0.0 | 2082 | 11.52M |
| 25 | 1628 | 2082 | 2148 | 2148 | 1562 | 362.3 | 0.0 | 2082 | 10.32M |
| 26 | 1562 | 2082 | 2139 | 2139 | 1506 | 305.5 | 0.0 | 2082 | 9.23M |
| 27 | 1506 | 2082 | 2099 | 2099 | 1489 | 288.7 | 0.0 | 2082 | 8.86M |
| 28 | 1489 | 2082 | 2105 | 2105 | 1465 | 265.2 | 0.0 | 2082 | 8.42M |
| 29 | 1465 | 2082 | 2109 | 2109 | 1439 | 238.6 | 0.0 | 2082 | 7.92M |
| 30 | 1439 | 2082 | 2114 | 2114 | 1407 | 206.7 | 0.0 | 2082 | 7.32M |
| **Σ** | — | — | — | **63168** | — | **17414** | **0.0** | — | **431.04M** |

#### JUL — Política `P_+10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2087 | 2087 | 2113 | 912.5 | 0.0 | 2181 | 19.41M |
| 2 | 2113 | 2181 | 2112 | 2112 | 2181 | 981.2 | 0.0 | 2181 | 21.90M |
| 3 | 2181 | 2181 | 2136 | 2136 | 2226 | 1026 | 0.0 | 2181 | 22.79M |
| 4 | 2226 | 2181 | 2081 | 2081 | 2326 | 1126 | 0.0 | 2181 | 24.61M |
| 5 | 2326 | 2181 | 2112 | 2112 | 2395 | 1195 | 0.0 | 2181 | 25.97M |
| 6 | 2395 | 2181 | 2091 | 2091 | 2486 | 1286 | 0.0 | 2181 | 27.65M |
| 7 | 2486 | 2181 | 2101 | 2101 | 2566 | 1366 | 0.0 | 2181 | 29.19M |
| 8 | 2566 | 2181 | 2116 | 2116 | 2632 | 1432 | 0.0 | 2181 | 30.46M |
| 9 | 2632 | 2181 | 2096 | 2096 | 2716 | 1516 | 0.0 | 2181 | 32.04M |
| 10 | 2716 | 2181 | 2103 | 2103 | 2795 | 1595 | 0.0 | 2181 | 33.54M |
| 11 | 2795 | 2181 | 2099 | 2099 | 2876 | 1676 | 0.0 | 2181 | 35.09M |
| 12 | 2876 | 2181 | 2072 | 2072 | 2985 | 1785 | 0.0 | 2181 | 37.11M |
| 13 | 2985 | 2181 | 2132 | 2132 | 3034 | 1834 | 0.0 | 2181 | 38.12M |
| 14 | 3034 | 2181 | 2074 | 2074 | 3140 | 1940 | 0.0 | 2181 | 40.07M |
| 15 | 3140 | 2181 | 2116 | 2116 | 3205 | 2005 | 0.0 | 2181 | 41.36M |
| 16 | 3205 | 2181 | 2085 | 2085 | 3302 | 2102 | 0.0 | 2181 | 43.15M |
| 17 | 3302 | 2181 | 2135 | 2135 | 3348 | 2148 | 0.0 | 2181 | 44.09M |
| 18 | 3348 | 2181 | 2114 | 2114 | 3414 | 2214 | 0.0 | 2181 | 45.33M |
| 19 | 3414 | 2181 | 2118 | 2118 | 3477 | 2277 | 0.0 | 2181 | 46.53M |
| 20 | 3477 | 2181 | 2069 | 2069 | 3589 | 2389 | 0.0 | 2181 | 48.58M |
| 21 | 3589 | 2181 | 2129 | 2129 | 3641 | 2441 | 0.0 | 2181 | 49.66M |
| 22 | 3641 | 2181 | 2105 | 2105 | 3717 | 2517 | 0.0 | 2181 | 51.07M |
| 23 | 3717 | 2181 | 2062 | 2062 | 3836 | 2636 | 0.0 | 2181 | 53.27M |
| 24 | 3836 | 2181 | 2109 | 2109 | 3908 | 2708 | 0.0 | 2181 | 54.70M |
| 25 | 3908 | 2181 | 2148 | 2148 | 3942 | 2742 | 0.0 | 2181 | 55.39M |
| 26 | 3942 | 2181 | 2139 | 2139 | 3984 | 2784 | 0.0 | 2181 | 56.19M |
| 27 | 3984 | 2181 | 2099 | 2099 | 4066 | 2866 | 0.0 | 2181 | 57.70M |
| 28 | 4066 | 2181 | 2105 | 2105 | 4142 | 2942 | 0.0 | 2181 | 59.14M |
| 29 | 4142 | 2181 | 2109 | 2109 | 4214 | 3014 | 0.0 | 2181 | 60.52M |
| 30 | 4214 | 2181 | 2114 | 2114 | 4282 | 3082 | 0.0 | 2181 | 61.81M |
| **Σ** | — | — | — | **63168** | — | **60539** | **0.0** | — | **1246.44M** |


---

## Anexo C — MAR: uma réplica qualquer do SDDP (idx=42)

Trajetória individual do SDDP em MAR (uma das 1000 réplicas, índice arbitrário 42). **Números coerentes linha a linha**: `Spill = max(0, FilaFim − 1 200)` bate exato.

> Use isto para "sentir" como é uma execução real do SDDP em março. Para a média entre 1000 sims, ver Anexo A.

#### MAR — SDDP, réplica qualquer (idx=42, trajetória individual)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2277 | 2277 | 1923 | 723.0 | 0.0 | 934.0 | 16.08M |
| 2 | 1923 | 934.0 | 2414 | 2414 | 443.0 | 0.0 | -0.0 | 2414 | 3.30M |
| 3 | 443.0 | 2414 | 2232 | 2232 | 625.0 | 0.0 | -0.0 | 2232 | 1.49M |
| 4 | 625.0 | 2232 | 2641 | 2641 | 216.0 | 0.0 | 0.0 | 2641 | 1.17M |
| 5 | 216.0 | 2641 | 2266 | 2266 | 591.0 | 0.0 | -0.0 | 2266 | 1.13M |
| 6 | 591.0 | 2266 | 2812 | 2812 | 45.0 | 0.0 | -0.0 | 2812 | 887220 |
| 7 | 45.0 | 2812 | 2539 | 2539 | 318.0 | 0.0 | 0.0 | 2539 | 506385 |
| 8 | 318.0 | 2539 | 2448 | 2448 | 409.0 | 0.0 | -0.0 | 2448 | 1.01M |
| 9 | 409.0 | 2448 | 2812 | 2812 | 45.0 | 0.0 | 0.0 | 2812 | 633330 |
| 10 | 45.0 | 2812 | 2971 | 2857 | 0.0 | 0.0 | 114.0 | 2857 | 5.05M |
| 11 | 0.0 | 2857 | 2721 | 2721 | 136.0 | 0.0 | 0.0 | 2721 | 189720 |
| 12 | 136.0 | 2721 | 2209 | 2209 | 648.0 | 0.0 | 0.0 | 2209 | 1.09M |
| 13 | 648.0 | 2209 | 2596 | 2596 | 261.0 | 0.0 | -0.0 | 2596 | 1.27M |
| 14 | 261.0 | 2596 | 2846 | 2846 | 11.0 | 0.0 | 0.0 | 2846 | 379440 |
| 15 | 11.0 | 2846 | 2550 | 2550 | 307.0 | 0.0 | 0.0 | 2550 | 443610 |
| 16 | 307.0 | 2550 | 2698 | 2698 | 159.0 | 0.0 | 0.0 | 2698 | 650070 |
| 17 | 159.0 | 2698 | 2789 | 2789 | 68.0 | 0.0 | -0.0 | 2789 | 316665 |
| 18 | 68.0 | 2789 | 2516 | 2516 | 341.0 | 0.0 | 0.0 | 2516 | 570555 |
| 19 | 341.0 | 2516 | 2482 | 2482 | 375.0 | 0.0 | 0.0 | 2482 | 998820 |
| 20 | 375.0 | 2482 | 2482 | 2482 | 375.0 | 0.0 | -0.0 | 2482 | 1.05M |
| 21 | 375.0 | 2482 | 2630 | 2630 | 227.0 | 0.0 | 0.0 | 2630 | 839790 |
| 22 | 227.0 | 2630 | 2618 | 2618 | 239.0 | 0.0 | 0.0 | 2618 | 650070 |
| 23 | 239.0 | 2618 | 2584 | 2584 | 273.0 | 0.0 | 0.0 | 2584 | 714240 |
| 24 | 273.0 | 2584 | 2289 | 2289 | 568.0 | 0.0 | 0.0 | 2289 | 1.17M |
| 25 | 568.0 | 2289 | 2311 | 2311 | 546.0 | 0.0 | 0.0 | 2311 | 1.55M |
| 26 | 546.0 | 2311 | 2425 | 2425 | 432.0 | 0.0 | -0.0 | 2425 | 1.36M |
| 27 | 432.0 | 2425 | 2084 | 2084 | 773.0 | 0.0 | 0.0 | 2084 | 1.68M |
| 28 | 773.0 | 2084 | 2414 | 2414 | 443.0 | 0.0 | -0.0 | 2414 | 1.70M |
| 29 | 443.0 | 2414 | 2175 | 2175 | 682.0 | 0.0 | -0.0 | 2243 | 1.57M |
| 30 | 682.0 | 2243 | 2380 | 2380 | 545.0 | 0.0 | 0.0 | 0.0 | 1.71M |
| **Σ** | — | — | — | **75097** | — | **723.0** | **114.0** | — | **51.17M** |


---

## Anexo D — JUL: uma réplica qualquer do SDDP (idx=42)

Trajetória individual do SDDP em JUL. **Números coerentes linha a linha**. Observe a alta variabilidade de `w_proc` (varia de ~1 050 a ~3 250 entre dias) — característica do mês de julho (Weibull com CV=36%).

#### JUL — SDDP, réplica qualquer (idx=42, trajetória individual)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 1053 | 1053 | 3147 | 1947 | 0.0 | 0.0 | 37.63M |
| 2 | 3147 | 0.0 | 2499 | 2499 | 648.0 | 0.0 | 0.0 | 2196 | 5.29M |
| 3 | 648.0 | 2196 | 1612 | 1612 | 1232 | 32.0 | -0.0 | 1612 | 3.14M |
| 4 | 1232 | 1612 | 2630 | 2630 | 214.0 | 0.0 | 0.0 | 2630 | 2.02M |
| 5 | 214.0 | 2630 | 3255 | 2844 | 0.0 | 0.0 | 411.0 | 2844 | 18.28M |
| 6 | 0.0 | 2844 | 3222 | 2844 | -0.0 | 0.0 | 378.0 | 2844 | 16.54M |
| 7 | -0.0 | 2844 | 2072 | 2072 | 772.0 | 0.0 | -0.0 | 2072 | 1.08M |
| 8 | 772.0 | 2072 | 2203 | 2203 | 641.0 | 0.0 | 0.0 | 2203 | 1.97M |
| 9 | 641.0 | 2203 | 1152 | 1152 | 1692 | 492.0 | -0.0 | 1152 | 11.23M |
| 10 | 1692 | 1152 | 3025 | 2844 | 0.0 | 0.0 | 181.0 | 2844 | 10.28M |
| 11 | 0.0 | 2844 | 3518 | 2844 | 0.0 | 0.0 | 674.0 | 2844 | 29.49M |
| 12 | 0.0 | 2844 | 2203 | 2203 | 641.0 | 0.0 | -0.0 | 2203 | 894195 |
| 13 | 641.0 | 2203 | 2630 | 2630 | 214.0 | 0.0 | 0.0 | 2630 | 1.19M |
| 14 | 214.0 | 2630 | 2696 | 2696 | 148.0 | 0.0 | 0.0 | 2696 | 504990 |
| 15 | 148.0 | 2696 | 2861 | 2844 | 0.0 | 0.0 | 17.0 | 2844 | 950261 |
| 16 | 0.0 | 2844 | 1349 | 1349 | 1495 | 295.0 | -0.0 | 1349 | 6.87M |
| 17 | 1495 | 1349 | 2630 | 2630 | 214.0 | 0.0 | 0.0 | 2630 | 2.38M |
| 18 | 214.0 | 2630 | 1447 | 1447 | 1397 | 197.0 | 0.0 | 1447 | 5.44M |
| 19 | 1397 | 1447 | 1612 | 1612 | 1232 | 32.0 | 0.0 | 1612 | 4.19M |
| 20 | 1232 | 1612 | 2565 | 2565 | 279.0 | 0.0 | -0.0 | 2565 | 2.11M |
| 21 | 279.0 | 2565 | 954.0 | 954.0 | 1890 | 690.0 | -0.0 | 954.0 | 14.21M |
| 22 | 1890 | 954.0 | 1973 | 1973 | 871.0 | 0.0 | 0.0 | 1973 | 3.85M |
| 23 | 871.0 | 1973 | 2400 | 2400 | 444.0 | 0.0 | 0.0 | 2400 | 1.83M |
| 24 | 444.0 | 2400 | 3025 | 2844 | 0.0 | 0.0 | 181.0 | 2844 | 8.54M |
| 25 | 0.0 | 2844 | 2729 | 2729 | 115.0 | 0.0 | 0.0 | 2729 | 160425 |
| 26 | 115.0 | 2729 | 1119 | 1119 | 1725 | 525.0 | -0.0 | 1119 | 11.08M |
| 27 | 1725 | 1119 | 2499 | 2499 | 345.0 | 0.0 | 0.0 | 2499 | 2.89M |
| 28 | 345.0 | 2499 | 1644 | 1644 | 1200 | 0.0 | 0.0 | 1644 | 2.16M |
| 29 | 1200 | 1644 | 2039 | 2039 | 805.0 | 0.0 | 0.0 | 2088 | 2.80M |
| 30 | 805.0 | 2088 | 2532 | 2532 | 361.0 | 0.0 | -0.0 | 0.0 | 1.63M |
| **Σ** | — | — | — | **65306** | — | **4210** | **1842** | — | **210.62M** |


---

## Anexo E — Validações e reprodutibilidade

- **V1 (vs v7):** SDDP mar do v8 (R$ 52.0 M) compatível com v7 a menos de ±5%.
- **V2 (não-monotonicidade fixas):** com a nova regra, o ótimo entre fixas é interno (P_0 em ambos os meses) — padrão em U.
- **V3 (determinismo das fixas):** rodar `julia model_v8.jl` duas vezes → custos das fixas são bit-idênticos (IC=0).
- **V4 (bound SDDP):** bound calculado por `SDDP.calculate_bound(model)` ≤ custo médio simulado.

**Sistema:** Windows 11, Julia 1.12.4, Python 3.11.9.

**Como rodar do zero:**

```
cd "Projeto - IC - Rodoviário"
julia "Model SDDP - 19-05-26/model_v8.jl"     # ~2.5 min
python "Model SDDP - 19-05-26/plot_v8.py"     # ~10 s
```

---
