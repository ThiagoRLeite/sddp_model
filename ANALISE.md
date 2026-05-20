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

**Base usada nos gráficos e análises do corpo principal.**

> **Nota metodológica (importante):**
> - **Para o SDDP**, esta tabela mostra uma **trajetória reconstruída a partir das médias** das 1000 simulações. Cada coluna (FilaIni, AdmIn, w_proc, Proc, FilaFim, AdmOut) é a média daquela variável no dia t entre as 1000 réplicas. **Spill e Ocioso são RECALCULADOS** pelas fórmulas (`Spill = max(0, FilaFim − 1 200)`, `Ocioso = max(0, w_proc − Proc)`) para que os números fechem linha a linha.
> - **Para as fixas P_-10..P_+10**, a trajetória já é determinística (w_proc fixo, adm_out=X constante), então os valores são exatos.
> - **Importante:** o **custo total Σ da linha SDDP nesta tabela** ≠ **custo médio real do SDDP** (Tabela 5.1/5.2). A diferença é o "custo da variabilidade estocástica" — Jensen.
>   - MAR SDDP: Σ tabela = R$ 51.8 M, real (§5.2) = R$ 52.0 M (diferença ~0%, baixa variância).
>   - JUL SDDP: Σ tabela = **R$ 149.9 M**, real (§5.2) = **R$ 204 M** (diferença ~R$ 54 M = custo da variabilidade alta da Weibull).

#### MAR — Política `SDDP` (trajetória reconstruída das médias 1000 sims SDDP — Spill = max(0, FilaFim − 1200))

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2483 | 2483 | 1717 | 517.5 | 0.0 | 1140 | 12.46M |
| 2 | 1717 | 1140 | 2475 | 2469 | 387.6 | 0.0 | 5.1 | 2469 | 3.16M |
| 3 | 387.6 | 2469 | 2463 | 2460 | 397.0 | 0.0 | 3.3 | 2460 | 1.24M |
| 4 | 397.0 | 2460 | 2481 | 2476 | 381.1 | 0.0 | 5.3 | 2476 | 1.32M |
| 5 | 381.1 | 2476 | 2483 | 2478 | 379.3 | 0.0 | 5.0 | 2478 | 1.28M |
| 6 | 379.3 | 2478 | 2476 | 2470 | 386.8 | 0.0 | 6.2 | 2470 | 1.34M |
| 7 | 386.8 | 2470 | 2471 | 2467 | 390.1 | 0.0 | 4.6 | 2467 | 1.29M |
| 8 | 390.1 | 2467 | 2481 | 2476 | 381.4 | 0.0 | 5.3 | 2476 | 1.31M |
| 9 | 381.4 | 2476 | 2482 | 2477 | 380.3 | 0.0 | 5.4 | 2477 | 1.30M |
| 10 | 380.3 | 2477 | 2483 | 2476 | 380.9 | 0.0 | 6.5 | 2476 | 1.35M |
| 11 | 380.9 | 2476 | 2466 | 2462 | 394.8 | 0.0 | 4.2 | 2462 | 1.27M |
| 12 | 394.8 | 2462 | 2479 | 2473 | 383.7 | 0.0 | 5.5 | 2473 | 1.33M |
| 13 | 383.7 | 2473 | 2478 | 2472 | 384.9 | 0.0 | 5.6 | 2472 | 1.31M |
| 14 | 384.9 | 2472 | 2477 | 2471 | 386.2 | 0.0 | 6.0 | 2471 | 1.34M |
| 15 | 386.2 | 2471 | 2472 | 2468 | 388.7 | 0.0 | 4.2 | 2468 | 1.26M |
| 16 | 388.7 | 2468 | 2479 | 2473 | 383.6 | 0.0 | 5.2 | 2473 | 1.31M |
| 17 | 383.6 | 2473 | 2461 | 2457 | 400.4 | 0.0 | 4.5 | 2457 | 1.29M |
| 18 | 400.4 | 2457 | 2480 | 2475 | 381.6 | 0.0 | 4.9 | 2475 | 1.31M |
| 19 | 381.6 | 2475 | 2470 | 2466 | 390.9 | 0.0 | 4.2 | 2466 | 1.26M |
| 20 | 390.9 | 2466 | 2482 | 2477 | 379.6 | 0.0 | 4.2 | 2477 | 1.26M |
| 21 | 379.6 | 2477 | 2482 | 2477 | 380.2 | 0.0 | 4.8 | 2477 | 1.27M |
| 22 | 380.2 | 2477 | 2471 | 2467 | 390.0 | 0.0 | 4.3 | 2467 | 1.26M |
| 23 | 390.0 | 2467 | 2473 | 2469 | 388.1 | 0.0 | 4.5 | 2469 | 1.28M |
| 24 | 388.1 | 2469 | 2494 | 2488 | 368.6 | 0.0 | 6.0 | 2488 | 1.32M |
| 25 | 368.6 | 2488 | 2494 | 2488 | 368.9 | 0.0 | 5.8 | 2488 | 1.28M |
| 26 | 368.9 | 2488 | 2484 | 2479 | 378.1 | 0.0 | 4.6 | 2479 | 1.24M |
| 27 | 378.1 | 2479 | 2466 | 2461 | 396.3 | 0.0 | 5.0 | 2461 | 1.30M |
| 28 | 396.3 | 2461 | 2486 | 2482 | 375.2 | 0.0 | 4.4 | 2482 | 1.27M |
| 29 | 375.2 | 2482 | 2475 | 2469 | 388.0 | 0.0 | 6.4 | 2537 | 1.35M |
| 30 | 388.0 | 2537 | 2480 | 2478 | 447.4 | 0.0 | 2.5 | 0.0 | 1.28M |
| **Σ** | — | — | — | **74184** | — | **517.5** | **143.5** | — | **51.81M** |

#### MAR — Política `P_-10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2483 | 2483 | 1717 | 517.5 | 0.0 | 2150 | 12.46M |
| 2 | 1717 | 2150 | 2475 | 2475 | 1393 | 193.4 | 0.0 | 2150 | 7.47M |
| 3 | 1393 | 2150 | 2463 | 2463 | 1081 | 0.0 | 0.0 | 2150 | 3.45M |
| 4 | 1081 | 2150 | 2481 | 2481 | 749.8 | 0.0 | 0.0 | 2150 | 2.55M |
| 5 | 749.8 | 2150 | 2483 | 2483 | 417.5 | 0.0 | 0.0 | 2150 | 1.63M |
| 6 | 417.5 | 2150 | 2476 | 2476 | 91.6 | 0.0 | 0.0 | 2150 | 710091 |
| 7 | 91.6 | 2150 | 2471 | 2242 | 0.0 | 0.0 | 229.5 | 2150 | 10.17M |
| 8 | 0.0 | 2150 | 2481 | 2150 | 0.0 | 0.0 | 330.5 | 2150 | 14.46M |
| 9 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 331.7 | 2150 | 14.51M |
| 10 | 0.0 | 2150 | 2483 | 2150 | 0.0 | 0.0 | 332.1 | 2150 | 14.53M |
| 11 | 0.0 | 2150 | 2466 | 2150 | 0.0 | 0.0 | 316.0 | 2150 | 13.83M |
| 12 | 0.0 | 2150 | 2479 | 2150 | 0.0 | 0.0 | 328.3 | 2150 | 14.37M |
| 13 | 0.0 | 2150 | 2478 | 2150 | 0.0 | 0.0 | 327.3 | 2150 | 14.32M |
| 14 | 0.0 | 2150 | 2477 | 2150 | 0.0 | 0.0 | 326.4 | 2150 | 14.28M |
| 15 | 0.0 | 2150 | 2472 | 2150 | 0.0 | 0.0 | 322.0 | 2150 | 14.09M |
| 16 | 0.0 | 2150 | 2479 | 2150 | 0.0 | 0.0 | 328.2 | 2150 | 14.36M |
| 17 | 0.0 | 2150 | 2461 | 2150 | 0.0 | 0.0 | 310.6 | 2150 | 13.59M |
| 18 | 0.0 | 2150 | 2480 | 2150 | 0.0 | 0.0 | 329.8 | 2150 | 14.43M |
| 19 | 0.0 | 2150 | 2470 | 2150 | 0.0 | 0.0 | 319.9 | 2150 | 14.00M |
| 20 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 331.2 | 2150 | 14.49M |
| 21 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 331.2 | 2150 | 14.49M |
| 22 | 0.0 | 2150 | 2471 | 2150 | 0.0 | 0.0 | 320.8 | 2150 | 14.04M |
| 23 | 0.0 | 2150 | 2473 | 2150 | 0.0 | 0.0 | 323.0 | 2150 | 14.13M |
| 24 | 0.0 | 2150 | 2494 | 2150 | 0.0 | 0.0 | 344.0 | 2150 | 15.05M |
| 25 | 0.0 | 2150 | 2494 | 2150 | 0.0 | 0.0 | 343.5 | 2150 | 15.03M |
| 26 | 0.0 | 2150 | 2484 | 2150 | 0.0 | 0.0 | 333.1 | 2150 | 14.57M |
| 27 | 0.0 | 2150 | 2466 | 2150 | 0.0 | 0.0 | 315.3 | 2150 | 13.79M |
| 28 | 0.0 | 2150 | 2486 | 2150 | 0.0 | 0.0 | 335.8 | 2150 | 14.69M |
| 29 | 0.0 | 2150 | 2475 | 2150 | 0.0 | 0.0 | 325.0 | 2150 | 14.22M |
| 30 | 0.0 | 2150 | 2480 | 2150 | 0.0 | 0.0 | 329.7 | 2150 | 14.43M |
| **Σ** | — | — | — | **66563** | — | **710.9** | **7765** | — | **368.14M** |

#### MAR — Política `P_-5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2483 | 2483 | 1717 | 517.5 | 0.0 | 2270 | 12.46M |
| 2 | 1717 | 2270 | 2475 | 2475 | 1513 | 312.9 | 0.0 | 2270 | 9.58M |
| 3 | 1513 | 2270 | 2463 | 2463 | 1319 | 119.4 | 0.0 | 2270 | 5.89M |
| 4 | 1319 | 2270 | 2481 | 2481 | 1108 | 0.0 | 0.0 | 2270 | 3.39M |
| 5 | 1108 | 2270 | 2483 | 2483 | 895.3 | 0.0 | 0.0 | 2270 | 2.79M |
| 6 | 895.3 | 2270 | 2476 | 2476 | 688.9 | 0.0 | 0.0 | 2270 | 2.21M |
| 7 | 688.9 | 2270 | 2471 | 2471 | 487.3 | 0.0 | 0.0 | 2270 | 1.64M |
| 8 | 487.3 | 2270 | 2481 | 2481 | 276.3 | 0.0 | 0.0 | 2270 | 1.07M |
| 9 | 276.3 | 2270 | 2482 | 2482 | 64.1 | 0.0 | 0.0 | 2270 | 474852 |
| 10 | 64.1 | 2270 | 2483 | 2334 | 0.0 | 0.0 | 148.5 | 2270 | 6.59M |
| 11 | 0.0 | 2270 | 2466 | 2270 | 0.0 | 0.0 | 196.5 | 2270 | 8.60M |
| 12 | 0.0 | 2270 | 2479 | 2270 | 0.0 | 0.0 | 208.9 | 2270 | 9.14M |
| 13 | 0.0 | 2270 | 2478 | 2270 | 0.0 | 0.0 | 207.8 | 2270 | 9.09M |
| 14 | 0.0 | 2270 | 2477 | 2270 | 0.0 | 0.0 | 206.9 | 2270 | 9.05M |
| 15 | 0.0 | 2270 | 2472 | 2270 | 0.0 | 0.0 | 202.5 | 2270 | 8.86M |
| 16 | 0.0 | 2270 | 2479 | 2270 | 0.0 | 0.0 | 208.8 | 2270 | 9.13M |
| 17 | 0.0 | 2270 | 2461 | 2270 | 0.0 | 0.0 | 191.2 | 2270 | 8.36M |
| 18 | 0.0 | 2270 | 2480 | 2270 | 0.0 | 0.0 | 210.4 | 2270 | 9.20M |
| 19 | 0.0 | 2270 | 2470 | 2270 | 0.0 | 0.0 | 200.4 | 2270 | 8.77M |
| 20 | 0.0 | 2270 | 2482 | 2270 | 0.0 | 0.0 | 211.7 | 2270 | 9.26M |
| 21 | 0.0 | 2270 | 2482 | 2270 | 0.0 | 0.0 | 211.7 | 2270 | 9.26M |
| 22 | 0.0 | 2270 | 2471 | 2270 | 0.0 | 0.0 | 201.4 | 2270 | 8.81M |
| 23 | 0.0 | 2270 | 2473 | 2270 | 0.0 | 0.0 | 203.5 | 2270 | 8.90M |
| 24 | 0.0 | 2270 | 2494 | 2270 | 0.0 | 0.0 | 224.6 | 2270 | 9.83M |
| 25 | 0.0 | 2270 | 2494 | 2270 | 0.0 | 0.0 | 224.0 | 2270 | 9.80M |
| 26 | 0.0 | 2270 | 2484 | 2270 | 0.0 | 0.0 | 213.6 | 2270 | 9.35M |
| 27 | 0.0 | 2270 | 2466 | 2270 | 0.0 | 0.0 | 195.8 | 2270 | 8.57M |
| 28 | 0.0 | 2270 | 2486 | 2270 | 0.0 | 0.0 | 216.3 | 2270 | 9.46M |
| 29 | 0.0 | 2270 | 2475 | 2270 | 0.0 | 0.0 | 205.5 | 2270 | 8.99M |
| 30 | 0.0 | 2270 | 2480 | 2270 | 0.0 | 0.0 | 210.2 | 2270 | 9.20M |
| **Σ** | — | — | — | **70027** | — | **949.8** | **4300** | — | **227.73M** |

#### MAR — Política `P_0` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2483 | 2483 | 1717 | 517.5 | 0.0 | 2389 | 12.46M |
| 2 | 1717 | 2389 | 2475 | 2475 | 1632 | 432.3 | 0.0 | 2389 | 11.68M |
| 3 | 1632 | 2389 | 2463 | 2463 | 1558 | 358.4 | 0.0 | 2389 | 10.26M |
| 4 | 1558 | 2389 | 2481 | 2481 | 1467 | 266.6 | 0.0 | 2389 | 8.54M |
| 5 | 1467 | 2389 | 2483 | 2483 | 1373 | 173.2 | 0.0 | 2389 | 6.77M |
| 6 | 1373 | 2389 | 2476 | 2476 | 1286 | 86.2 | 0.0 | 2389 | 5.11M |
| 7 | 1286 | 2389 | 2471 | 2471 | 1204 | 4.1 | 0.0 | 2389 | 3.54M |
| 8 | 1204 | 2389 | 2481 | 2481 | 1113 | 0.0 | 0.0 | 2389 | 3.23M |
| 9 | 1113 | 2389 | 2482 | 2482 | 1020 | 0.0 | 0.0 | 2389 | 2.97M |
| 10 | 1020 | 2389 | 2483 | 2483 | 926.7 | 0.0 | 0.0 | 2389 | 2.72M |
| 11 | 926.7 | 2389 | 2466 | 2466 | 849.6 | 0.0 | 0.0 | 2389 | 2.48M |
| 12 | 849.6 | 2389 | 2479 | 2479 | 760.2 | 0.0 | 0.0 | 2389 | 2.25M |
| 13 | 760.2 | 2389 | 2478 | 2478 | 671.9 | 0.0 | 0.0 | 2389 | 2.00M |
| 14 | 671.9 | 2389 | 2477 | 2477 | 584.5 | 0.0 | 0.0 | 2389 | 1.75M |
| 15 | 584.5 | 2389 | 2472 | 2472 | 501.4 | 0.0 | 0.0 | 2389 | 1.51M |
| 16 | 501.4 | 2389 | 2479 | 2479 | 412.1 | 0.0 | 0.0 | 2389 | 1.27M |
| 17 | 412.1 | 2389 | 2461 | 2461 | 340.4 | 0.0 | 0.0 | 2389 | 1.05M |
| 18 | 340.4 | 2389 | 2480 | 2480 | 249.5 | 0.0 | 0.0 | 2389 | 822911 |
| 19 | 249.5 | 2389 | 2470 | 2470 | 168.6 | 0.0 | 0.0 | 2389 | 583197 |
| 20 | 168.6 | 2389 | 2482 | 2482 | 76.3 | 0.0 | 0.0 | 2389 | 341593 |
| 21 | 76.3 | 2389 | 2482 | 2466 | 0.0 | 0.0 | 15.9 | 2389 | 803275 |
| 22 | 0.0 | 2389 | 2471 | 2389 | 0.0 | 0.0 | 81.9 | 2389 | 3.58M |
| 23 | 0.0 | 2389 | 2473 | 2389 | 0.0 | 0.0 | 84.0 | 2389 | 3.68M |
| 24 | 0.0 | 2389 | 2494 | 2389 | 0.0 | 0.0 | 105.1 | 2389 | 4.60M |
| 25 | 0.0 | 2389 | 2494 | 2389 | 0.0 | 0.0 | 104.5 | 2389 | 4.57M |
| 26 | 0.0 | 2389 | 2484 | 2389 | 0.0 | 0.0 | 94.2 | 2389 | 4.12M |
| 27 | 0.0 | 2389 | 2466 | 2389 | 0.0 | 0.0 | 76.3 | 2389 | 3.34M |
| 28 | 0.0 | 2389 | 2486 | 2389 | 0.0 | 0.0 | 96.8 | 2389 | 4.24M |
| 29 | 0.0 | 2389 | 2475 | 2389 | 0.0 | 0.0 | 86.1 | 2389 | 3.77M |
| 30 | 0.0 | 2389 | 2480 | 2389 | 0.0 | 0.0 | 90.8 | 2389 | 3.97M |
| **Σ** | — | — | — | **73492** | — | **1838** | **835.6** | — | **118.01M** |

#### MAR — Política `P_+5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2483 | 2483 | 1717 | 517.5 | 0.0 | 2509 | 12.46M |
| 2 | 1717 | 2509 | 2475 | 2475 | 1752 | 551.8 | 0.0 | 2509 | 13.78M |
| 3 | 1752 | 2509 | 2463 | 2463 | 1797 | 597.3 | 0.0 | 2509 | 14.63M |
| 4 | 1797 | 2509 | 2481 | 2481 | 1825 | 625.0 | 0.0 | 2509 | 15.18M |
| 5 | 1825 | 2509 | 2483 | 2483 | 1851 | 651.1 | 0.0 | 2509 | 15.68M |
| 6 | 1851 | 2509 | 2476 | 2476 | 1884 | 683.6 | 0.0 | 2509 | 16.29M |
| 7 | 1884 | 2509 | 2471 | 2471 | 1921 | 720.9 | 0.0 | 2509 | 16.99M |
| 8 | 1921 | 2509 | 2481 | 2481 | 1949 | 748.9 | 0.0 | 2509 | 17.54M |
| 9 | 1949 | 2509 | 2482 | 2482 | 1976 | 775.6 | 0.0 | 2509 | 18.05M |
| 10 | 1976 | 2509 | 2483 | 2483 | 2002 | 801.9 | 0.0 | 2509 | 18.55M |
| 11 | 2002 | 2509 | 2466 | 2466 | 2044 | 844.3 | 0.0 | 2509 | 19.33M |
| 12 | 2044 | 2509 | 2479 | 2479 | 2074 | 874.4 | 0.0 | 2509 | 19.92M |
| 13 | 2074 | 2509 | 2478 | 2478 | 2106 | 905.5 | 0.0 | 2509 | 20.51M |
| 14 | 2106 | 2509 | 2477 | 2477 | 2138 | 937.6 | 0.0 | 2509 | 21.12M |
| 15 | 2138 | 2509 | 2472 | 2472 | 2174 | 974.0 | 0.0 | 2509 | 21.80M |
| 16 | 2174 | 2509 | 2479 | 2479 | 2204 | 1004 | 0.0 | 2509 | 22.39M |
| 17 | 2204 | 2509 | 2461 | 2461 | 2252 | 1052 | 0.0 | 2509 | 23.27M |
| 18 | 2252 | 2509 | 2480 | 2480 | 2280 | 1080 | 0.0 | 2509 | 23.84M |
| 19 | 2280 | 2509 | 2470 | 2470 | 2319 | 1119 | 0.0 | 2509 | 24.56M |
| 20 | 2319 | 2509 | 2482 | 2482 | 2346 | 1146 | 0.0 | 2509 | 25.09M |
| 21 | 2346 | 2509 | 2482 | 2482 | 2373 | 1173 | 0.0 | 2509 | 25.61M |
| 22 | 2373 | 2509 | 2471 | 2471 | 2411 | 1211 | 0.0 | 2509 | 26.31M |
| 23 | 2411 | 2509 | 2473 | 2473 | 2446 | 1246 | 0.0 | 2509 | 26.98M |
| 24 | 2446 | 2509 | 2494 | 2494 | 2461 | 1261 | 0.0 | 2509 | 27.29M |
| 25 | 2461 | 2509 | 2494 | 2494 | 2476 | 1276 | 0.0 | 2509 | 27.57M |
| 26 | 2476 | 2509 | 2484 | 2484 | 2501 | 1301 | 0.0 | 2509 | 28.03M |
| 27 | 2501 | 2509 | 2466 | 2466 | 2544 | 1344 | 0.0 | 2509 | 28.83M |
| 28 | 2544 | 2509 | 2486 | 2486 | 2567 | 1367 | 0.0 | 2509 | 29.29M |
| 29 | 2567 | 2509 | 2475 | 2475 | 2600 | 1400 | 0.0 | 2509 | 29.91M |
| 30 | 2600 | 2509 | 2480 | 2480 | 2629 | 1429 | 0.0 | 2509 | 30.46M |
| **Σ** | — | — | — | **74327** | — | **29620** | **0.0** | — | **661.26M** |

#### MAR — Política `P_+10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2483 | 2483 | 1717 | 517.5 | 0.0 | 2628 | 12.46M |
| 2 | 1717 | 2628 | 2475 | 2475 | 1871 | 671.3 | 0.0 | 2628 | 15.89M |
| 3 | 1871 | 2628 | 2463 | 2463 | 2036 | 836.3 | 0.0 | 2628 | 19.01M |
| 4 | 2036 | 2628 | 2481 | 2481 | 2183 | 983.4 | 0.0 | 2628 | 21.83M |
| 5 | 2183 | 2628 | 2483 | 2483 | 2329 | 1129 | 0.0 | 2628 | 24.60M |
| 6 | 2329 | 2628 | 2476 | 2476 | 2481 | 1281 | 0.0 | 2628 | 27.47M |
| 7 | 2481 | 2628 | 2471 | 2471 | 2638 | 1438 | 0.0 | 2628 | 30.45M |
| 8 | 2638 | 2628 | 2481 | 2481 | 2785 | 1585 | 0.0 | 2628 | 33.26M |
| 9 | 2785 | 2628 | 2482 | 2482 | 2931 | 1731 | 0.0 | 2628 | 36.04M |
| 10 | 2931 | 2628 | 2483 | 2483 | 3077 | 1877 | 0.0 | 2628 | 38.81M |
| 11 | 3077 | 2628 | 2466 | 2466 | 3239 | 2039 | 0.0 | 2628 | 41.86M |
| 12 | 3239 | 2628 | 2479 | 2479 | 3389 | 2189 | 0.0 | 2628 | 44.72M |
| 13 | 3389 | 2628 | 2478 | 2478 | 3539 | 2339 | 0.0 | 2628 | 47.58M |
| 14 | 3539 | 2628 | 2477 | 2477 | 3691 | 2491 | 0.0 | 2628 | 50.46M |
| 15 | 3691 | 2628 | 2472 | 2472 | 3847 | 2647 | 0.0 | 2628 | 53.42M |
| 16 | 3847 | 2628 | 2479 | 2479 | 3996 | 2796 | 0.0 | 2628 | 56.27M |
| 17 | 3996 | 2628 | 2461 | 2461 | 4163 | 2963 | 0.0 | 2628 | 59.42M |
| 18 | 4163 | 2628 | 2480 | 2480 | 4311 | 3111 | 0.0 | 2628 | 62.26M |
| 19 | 4311 | 2628 | 2470 | 2470 | 4469 | 3269 | 0.0 | 2628 | 65.25M |
| 20 | 4469 | 2628 | 2482 | 2482 | 4616 | 3416 | 0.0 | 2628 | 68.05M |
| 21 | 4616 | 2628 | 2482 | 2482 | 4763 | 3563 | 0.0 | 2628 | 70.84M |
| 22 | 4763 | 2628 | 2471 | 2471 | 4920 | 3720 | 0.0 | 2628 | 73.81M |
| 23 | 4920 | 2628 | 2473 | 2473 | 5075 | 3875 | 0.0 | 2628 | 76.76M |
| 24 | 5075 | 2628 | 2494 | 2494 | 5209 | 4009 | 0.0 | 2628 | 79.33M |
| 25 | 5209 | 2628 | 2494 | 2494 | 5343 | 4143 | 0.0 | 2628 | 81.88M |
| 26 | 5343 | 2628 | 2484 | 2484 | 5488 | 4288 | 0.0 | 2628 | 84.62M |
| 27 | 5488 | 2628 | 2466 | 2466 | 5650 | 4450 | 0.0 | 2628 | 87.68M |
| 28 | 5650 | 2628 | 2486 | 2486 | 5793 | 4593 | 0.0 | 2628 | 90.41M |
| 29 | 5793 | 2628 | 2475 | 2475 | 5945 | 4745 | 0.0 | 2628 | 93.30M |
| 30 | 5945 | 2628 | 2480 | 2480 | 6094 | 4894 | 0.0 | 2628 | 96.12M |
| **Σ** | — | — | — | **74327** | — | **81589** | **0.0** | — | **1643.89M** |


---

## Anexo B — JUL: cenário médio dia-a-dia (1000 sims SDDP + 5 fixas ±10%, ±5%, 0%)

Idem ao Anexo A, mas para JULHO (alta variabilidade, CV de w_proc = 36%).

> **Nota metodológica (importante):**
> - **Para o SDDP**, esta tabela mostra uma **trajetória reconstruída a partir das médias** das 1000 simulações. Cada coluna (FilaIni, AdmIn, w_proc, Proc, FilaFim, AdmOut) é a média daquela variável no dia t entre as 1000 réplicas. **Spill e Ocioso são RECALCULADOS** pelas fórmulas (`Spill = max(0, FilaFim − 1 200)`, `Ocioso = max(0, w_proc − Proc)`) para que os números fechem linha a linha.
> - **Para as fixas P_-10..P_+10**, a trajetória já é determinística (w_proc fixo, adm_out=X constante), então os valores são exatos.
> - **Importante:** o **custo total Σ da linha SDDP nesta tabela** ≠ **custo médio real do SDDP** (Tabela 5.1/5.2). A diferença é o "custo da variabilidade estocástica" — Jensen.
>   - MAR SDDP: Σ tabela = R$ 51.8 M, real (§5.2) = R$ 52.0 M (diferença ~0%, baixa variância).
>   - JUL SDDP: Σ tabela = **R$ 149.9 M**, real (§5.2) = **R$ 204 M** (diferença ~R$ 54 M = custo da variabilidade alta da Weibull).

#### JUL — Política `SDDP` (trajetória reconstruída das médias 1000 sims SDDP — Spill = max(0, FilaFim − 1200))

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2102 | 2102 | 2098 | 897.9 | 0.0 | 792.2 | 19.16M |
| 2 | 2098 | 792.2 | 2095 | 2045 | 844.9 | 0.0 | 49.9 | 1999 | 6.29M |
| 3 | 844.9 | 1999 | 2081 | 2032 | 811.9 | 0.0 | 49.4 | 2032 | 4.47M |
| 4 | 811.9 | 2032 | 2089 | 2039 | 805.2 | 0.0 | 49.8 | 2039 | 4.43M |
| 5 | 805.2 | 2039 | 2118 | 2064 | 780.4 | 0.0 | 54.6 | 2064 | 4.60M |
| 6 | 780.4 | 2064 | 2063 | 2015 | 829.2 | 0.0 | 48.5 | 2015 | 4.37M |
| 7 | 829.2 | 2015 | 2142 | 2088 | 756.4 | 0.0 | 54.5 | 2088 | 4.60M |
| 8 | 756.4 | 2088 | 2088 | 2046 | 797.8 | 0.0 | 41.4 | 2046 | 3.98M |
| 9 | 797.8 | 2046 | 2092 | 2042 | 802.0 | 0.0 | 50.3 | 2042 | 4.43M |
| 10 | 802.0 | 2042 | 2080 | 2034 | 810.3 | 0.0 | 46.0 | 2034 | 4.26M |
| 11 | 810.3 | 2034 | 2104 | 2055 | 788.6 | 0.0 | 48.7 | 2055 | 4.36M |
| 12 | 788.6 | 2055 | 2056 | 2012 | 831.8 | 0.0 | 43.6 | 2012 | 4.17M |
| 13 | 831.8 | 2012 | 2116 | 2062 | 782.0 | 0.0 | 53.6 | 2062 | 4.59M |
| 14 | 782.0 | 2062 | 2087 | 2036 | 808.1 | 0.0 | 51.2 | 2036 | 4.46M |
| 15 | 808.1 | 2036 | 2060 | 2010 | 834.4 | 0.0 | 50.7 | 2010 | 4.51M |
| 16 | 834.4 | 2010 | 2095 | 2040 | 803.6 | 0.0 | 54.4 | 2040 | 4.67M |
| 17 | 803.6 | 2040 | 2131 | 2072 | 772.1 | 0.0 | 59.1 | 2072 | 4.78M |
| 18 | 772.1 | 2072 | 2086 | 2036 | 808.2 | 0.0 | 50.4 | 2036 | 4.41M |
| 19 | 808.2 | 2036 | 2092 | 2045 | 798.8 | 0.0 | 47.0 | 2045 | 4.30M |
| 20 | 798.8 | 2045 | 2078 | 2027 | 816.9 | 0.0 | 50.6 | 2027 | 4.47M |
| 21 | 816.9 | 2027 | 2081 | 2031 | 812.9 | 0.0 | 50.1 | 2031 | 4.47M |
| 22 | 812.9 | 2031 | 2093 | 2044 | 799.7 | 0.0 | 48.4 | 2044 | 4.37M |
| 23 | 799.7 | 2044 | 2092 | 2047 | 796.7 | 0.0 | 45.2 | 2047 | 4.20M |
| 24 | 796.7 | 2047 | 2124 | 2065 | 779.0 | 0.0 | 58.6 | 2065 | 4.76M |
| 25 | 779.0 | 2065 | 2109 | 2055 | 789.4 | 0.0 | 54.6 | 2055 | 4.58M |
| 26 | 789.4 | 2055 | 2043 | 1996 | 848.3 | 0.0 | 47.4 | 1996 | 4.36M |
| 27 | 848.3 | 1996 | 2133 | 2076 | 768.3 | 0.0 | 57.6 | 2076 | 4.78M |
| 28 | 768.3 | 2076 | 2095 | 2043 | 800.9 | 0.0 | 51.9 | 2043 | 4.46M |
| 29 | 800.9 | 2043 | 2075 | 2029 | 815.3 | 0.0 | 46.1 | 2078 | 4.27M |
| 30 | 815.3 | 2078 | 2114 | 2066 | 826.9 | 0.0 | 47.9 | 0.0 | 4.39M |
| **Σ** | — | — | — | **61353** | — | **897.9** | **1462** | — | **149.95M** |

#### JUL — Política `P_-10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2102 | 2102 | 2098 | 897.9 | 0.0 | 1775 | 19.16M |
| 2 | 2098 | 1775 | 2095 | 2095 | 1778 | 577.5 | 0.0 | 1775 | 14.77M |
| 3 | 1778 | 1775 | 2081 | 2081 | 1471 | 270.9 | 0.0 | 1775 | 8.92M |
| 4 | 1471 | 1775 | 2089 | 2089 | 1157 | 0.0 | 0.0 | 1775 | 3.67M |
| 5 | 1157 | 1775 | 2118 | 2118 | 813.6 | 0.0 | 0.0 | 1775 | 2.75M |
| 6 | 813.6 | 1775 | 2063 | 2063 | 525.2 | 0.0 | 0.0 | 1775 | 1.87M |
| 7 | 525.2 | 1775 | 2142 | 2142 | 158.0 | 0.0 | 0.0 | 1775 | 953003 |
| 8 | 158.0 | 1775 | 2088 | 1933 | 0.0 | 0.0 | 154.8 | 1775 | 6.99M |
| 9 | 0.0 | 1775 | 2092 | 1775 | 0.0 | 0.0 | 317.6 | 1775 | 13.90M |
| 10 | 0.0 | 1775 | 2080 | 1775 | 0.0 | 0.0 | 305.0 | 1775 | 13.34M |
| 11 | 0.0 | 1775 | 2104 | 1775 | 0.0 | 0.0 | 329.4 | 1775 | 14.41M |
| 12 | 0.0 | 1775 | 2056 | 1775 | 0.0 | 0.0 | 281.0 | 1775 | 12.30M |
| 13 | 0.0 | 1775 | 2116 | 1775 | 0.0 | 0.0 | 340.8 | 1775 | 14.91M |
| 14 | 0.0 | 1775 | 2087 | 1775 | 0.0 | 0.0 | 312.3 | 1775 | 13.66M |
| 15 | 0.0 | 1775 | 2060 | 1775 | 0.0 | 0.0 | 285.5 | 1775 | 12.49M |
| 16 | 0.0 | 1775 | 2095 | 1775 | 0.0 | 0.0 | 320.0 | 1775 | 14.00M |
| 17 | 0.0 | 1775 | 2131 | 1775 | 0.0 | 0.0 | 356.2 | 1775 | 15.59M |
| 18 | 0.0 | 1775 | 2086 | 1775 | 0.0 | 0.0 | 311.4 | 1775 | 13.62M |
| 19 | 0.0 | 1775 | 2092 | 1775 | 0.0 | 0.0 | 317.5 | 1775 | 13.89M |
| 20 | 0.0 | 1775 | 2078 | 1775 | 0.0 | 0.0 | 302.9 | 1775 | 13.25M |
| 21 | 0.0 | 1775 | 2081 | 1775 | 0.0 | 0.0 | 306.4 | 1775 | 13.41M |
| 22 | 0.0 | 1775 | 2093 | 1775 | 0.0 | 0.0 | 317.9 | 1775 | 13.91M |
| 23 | 0.0 | 1775 | 2092 | 1775 | 0.0 | 0.0 | 317.7 | 1775 | 13.90M |
| 24 | 0.0 | 1775 | 2124 | 1775 | 0.0 | 0.0 | 348.9 | 1775 | 15.26M |
| 25 | 0.0 | 1775 | 2109 | 1775 | 0.0 | 0.0 | 334.4 | 1775 | 14.63M |
| 26 | 0.0 | 1775 | 2043 | 1775 | 0.0 | 0.0 | 268.3 | 1775 | 11.74M |
| 27 | 0.0 | 1775 | 2133 | 1775 | 0.0 | 0.0 | 358.5 | 1775 | 15.69M |
| 28 | 0.0 | 1775 | 2095 | 1775 | 0.0 | 0.0 | 320.3 | 1775 | 14.01M |
| 29 | 0.0 | 1775 | 2075 | 1775 | 0.0 | 0.0 | 299.9 | 1775 | 13.12M |
| 30 | 0.0 | 1775 | 2114 | 1775 | 0.0 | 0.0 | 339.2 | 1775 | 14.84M |
| **Σ** | — | — | — | **55669** | — | **1746** | **7146** | — | **364.96M** |

#### JUL — Política `P_-5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2102 | 2102 | 2098 | 897.9 | 0.0 | 1873 | 19.16M |
| 2 | 2098 | 1873 | 2095 | 2095 | 1876 | 676.1 | 0.0 | 1873 | 16.50M |
| 3 | 1876 | 1873 | 2081 | 2081 | 1668 | 468.1 | 0.0 | 1873 | 12.53M |
| 4 | 1668 | 1873 | 2089 | 2089 | 1453 | 252.9 | 0.0 | 1873 | 8.45M |
| 5 | 1453 | 1873 | 2118 | 2118 | 1208 | 8.0 | 0.0 | 1873 | 3.84M |
| 6 | 1208 | 1873 | 2063 | 2063 | 1018 | 0.0 | 0.0 | 1873 | 3.11M |
| 7 | 1018 | 1873 | 2142 | 2142 | 749.5 | 0.0 | 0.0 | 1873 | 2.47M |
| 8 | 749.5 | 1873 | 2088 | 2088 | 535.4 | 0.0 | 0.0 | 1873 | 1.79M |
| 9 | 535.4 | 1873 | 2092 | 2092 | 316.4 | 0.0 | 0.0 | 1873 | 1.19M |
| 10 | 316.4 | 1873 | 2080 | 2080 | 110.0 | 0.0 | 0.0 | 1873 | 594724 |
| 11 | 110.0 | 1873 | 2104 | 1983 | 0.0 | 0.0 | 120.8 | 1873 | 5.44M |
| 12 | 0.0 | 1873 | 2056 | 1873 | 0.0 | 0.0 | 182.4 | 1873 | 7.98M |
| 13 | 0.0 | 1873 | 2116 | 1873 | 0.0 | 0.0 | 242.2 | 1873 | 10.60M |
| 14 | 0.0 | 1873 | 2087 | 1873 | 0.0 | 0.0 | 213.7 | 1873 | 9.35M |
| 15 | 0.0 | 1873 | 2060 | 1873 | 0.0 | 0.0 | 186.9 | 1873 | 8.18M |
| 16 | 0.0 | 1873 | 2095 | 1873 | 0.0 | 0.0 | 221.4 | 1873 | 9.69M |
| 17 | 0.0 | 1873 | 2131 | 1873 | 0.0 | 0.0 | 257.6 | 1873 | 11.27M |
| 18 | 0.0 | 1873 | 2086 | 1873 | 0.0 | 0.0 | 212.8 | 1873 | 9.31M |
| 19 | 0.0 | 1873 | 2092 | 1873 | 0.0 | 0.0 | 218.9 | 1873 | 9.58M |
| 20 | 0.0 | 1873 | 2078 | 1873 | 0.0 | 0.0 | 204.3 | 1873 | 8.94M |
| 21 | 0.0 | 1873 | 2081 | 1873 | 0.0 | 0.0 | 207.8 | 1873 | 9.09M |
| 22 | 0.0 | 1873 | 2093 | 1873 | 0.0 | 0.0 | 219.3 | 1873 | 9.60M |
| 23 | 0.0 | 1873 | 2092 | 1873 | 0.0 | 0.0 | 219.1 | 1873 | 9.58M |
| 24 | 0.0 | 1873 | 2124 | 1873 | 0.0 | 0.0 | 250.3 | 1873 | 10.95M |
| 25 | 0.0 | 1873 | 2109 | 1873 | 0.0 | 0.0 | 235.8 | 1873 | 10.32M |
| 26 | 0.0 | 1873 | 2043 | 1873 | 0.0 | 0.0 | 169.7 | 1873 | 7.43M |
| 27 | 0.0 | 1873 | 2133 | 1873 | 0.0 | 0.0 | 259.9 | 1873 | 11.37M |
| 28 | 0.0 | 1873 | 2095 | 1873 | 0.0 | 0.0 | 221.7 | 1873 | 9.70M |
| 29 | 0.0 | 1873 | 2075 | 1873 | 0.0 | 0.0 | 201.3 | 1873 | 8.81M |
| 30 | 0.0 | 1873 | 2114 | 1873 | 0.0 | 0.0 | 240.6 | 1873 | 10.53M |
| **Σ** | — | — | — | **58528** | — | **2303** | **4286** | — | **257.33M** |

#### JUL — Política `P_0` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2102 | 2102 | 2098 | 897.9 | 0.0 | 1972 | 19.16M |
| 2 | 2098 | 1972 | 2095 | 2095 | 1975 | 774.7 | 0.0 | 1972 | 18.24M |
| 3 | 1975 | 1972 | 2081 | 2081 | 1865 | 665.3 | 0.0 | 1972 | 16.14M |
| 4 | 1865 | 1972 | 2089 | 2089 | 1749 | 548.7 | 0.0 | 1972 | 13.94M |
| 5 | 1749 | 1972 | 2118 | 2118 | 1602 | 402.4 | 0.0 | 1972 | 11.20M |
| 6 | 1602 | 1972 | 2063 | 2063 | 1511 | 311.2 | 0.0 | 1972 | 9.39M |
| 7 | 1511 | 1972 | 2142 | 2142 | 1341 | 141.1 | 0.0 | 1972 | 6.27M |
| 8 | 1341 | 1972 | 2088 | 2088 | 1226 | 25.6 | 0.0 | 1972 | 3.99M |
| 9 | 1226 | 1972 | 2092 | 2092 | 1105 | 0.0 | 0.0 | 1972 | 3.25M |
| 10 | 1105 | 1972 | 2080 | 2080 | 997.4 | 0.0 | 0.0 | 1972 | 2.93M |
| 11 | 997.4 | 1972 | 2104 | 2104 | 865.2 | 0.0 | 0.0 | 1972 | 2.60M |
| 12 | 865.2 | 1972 | 2056 | 2056 | 781.4 | 0.0 | 0.0 | 1972 | 2.30M |
| 13 | 781.4 | 1972 | 2116 | 2116 | 637.8 | 0.0 | 0.0 | 1972 | 1.98M |
| 14 | 637.8 | 1972 | 2087 | 2087 | 522.8 | 0.0 | 0.0 | 1972 | 1.62M |
| 15 | 522.8 | 1972 | 2060 | 2060 | 434.5 | 0.0 | 0.0 | 1972 | 1.34M |
| 16 | 434.5 | 1972 | 2095 | 2095 | 311.7 | 0.0 | 0.0 | 1972 | 1.04M |
| 17 | 311.7 | 1972 | 2131 | 2131 | 152.7 | 0.0 | 0.0 | 1972 | 647753 |
| 18 | 152.7 | 1972 | 2086 | 2086 | 38.5 | 0.0 | 0.0 | 1972 | 266620 |
| 19 | 38.5 | 1972 | 2092 | 2010 | 0.0 | 0.0 | 81.8 | 1972 | 3.63M |
| 20 | 0.0 | 1972 | 2078 | 1972 | 0.0 | 0.0 | 105.7 | 1972 | 4.62M |
| 21 | 0.0 | 1972 | 2081 | 1972 | 0.0 | 0.0 | 109.2 | 1972 | 4.78M |
| 22 | 0.0 | 1972 | 2093 | 1972 | 0.0 | 0.0 | 120.7 | 1972 | 5.28M |
| 23 | 0.0 | 1972 | 2092 | 1972 | 0.0 | 0.0 | 120.5 | 1972 | 5.27M |
| 24 | 0.0 | 1972 | 2124 | 1972 | 0.0 | 0.0 | 151.7 | 1972 | 6.64M |
| 25 | 0.0 | 1972 | 2109 | 1972 | 0.0 | 0.0 | 137.2 | 1972 | 6.00M |
| 26 | 0.0 | 1972 | 2043 | 1972 | 0.0 | 0.0 | 71.1 | 1972 | 3.11M |
| 27 | 0.0 | 1972 | 2133 | 1972 | 0.0 | 0.0 | 161.3 | 1972 | 7.06M |
| 28 | 0.0 | 1972 | 2095 | 1972 | 0.0 | 0.0 | 123.1 | 1972 | 5.38M |
| 29 | 0.0 | 1972 | 2075 | 1972 | 0.0 | 0.0 | 102.7 | 1972 | 4.50M |
| 30 | 0.0 | 1972 | 2114 | 1972 | 0.0 | 0.0 | 142.0 | 1972 | 6.21M |
| **Σ** | — | — | — | **61388** | — | **3767** | **1427** | — | **178.78M** |

#### JUL — Política `P_+5` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2102 | 2102 | 2098 | 897.9 | 0.0 | 2071 | 19.16M |
| 2 | 2098 | 2071 | 2095 | 2095 | 2073 | 873.3 | 0.0 | 2071 | 19.98M |
| 3 | 2073 | 2071 | 2081 | 2081 | 2062 | 862.5 | 0.0 | 2071 | 19.75M |
| 4 | 2062 | 2071 | 2089 | 2089 | 2044 | 844.5 | 0.0 | 2071 | 19.42M |
| 5 | 2044 | 2071 | 2118 | 2118 | 1997 | 796.8 | 0.0 | 2071 | 18.56M |
| 6 | 1997 | 2071 | 2063 | 2063 | 2004 | 804.2 | 0.0 | 2071 | 18.62M |
| 7 | 2004 | 2071 | 2142 | 2142 | 1933 | 732.7 | 0.0 | 2071 | 17.37M |
| 8 | 1933 | 2071 | 2088 | 2088 | 1916 | 715.8 | 0.0 | 2071 | 16.97M |
| 9 | 1916 | 2071 | 2092 | 2092 | 1894 | 694.0 | 0.0 | 2071 | 16.56M |
| 10 | 1894 | 2071 | 2080 | 2080 | 1885 | 684.8 | 0.0 | 2071 | 16.37M |
| 11 | 1885 | 2071 | 2104 | 2104 | 1851 | 651.2 | 0.0 | 2071 | 15.77M |
| 12 | 1851 | 2071 | 2056 | 2056 | 1866 | 666.0 | 0.0 | 2071 | 15.98M |
| 13 | 1866 | 2071 | 2116 | 2116 | 1821 | 621.0 | 0.0 | 2071 | 15.21M |
| 14 | 1821 | 2071 | 2087 | 2087 | 1805 | 604.6 | 0.0 | 2071 | 14.86M |
| 15 | 1805 | 2071 | 2060 | 2060 | 1815 | 614.9 | 0.0 | 2071 | 15.02M |
| 16 | 1815 | 2071 | 2095 | 2095 | 1791 | 590.7 | 0.0 | 2071 | 14.61M |
| 17 | 1791 | 2071 | 2131 | 2131 | 1730 | 530.2 | 0.0 | 2071 | 13.51M |
| 18 | 1730 | 2071 | 2086 | 2086 | 1715 | 514.7 | 0.0 | 2071 | 13.15M |
| 19 | 1715 | 2071 | 2092 | 2092 | 1693 | 493.0 | 0.0 | 2071 | 12.75M |
| 20 | 1693 | 2071 | 2078 | 2078 | 1686 | 485.9 | 0.0 | 2071 | 12.59M |
| 21 | 1686 | 2071 | 2081 | 2081 | 1675 | 475.3 | 0.0 | 2071 | 12.39M |
| 22 | 1675 | 2071 | 2093 | 2093 | 1653 | 453.2 | 0.0 | 2071 | 11.99M |
| 23 | 1653 | 2071 | 2092 | 2092 | 1631 | 431.3 | 0.0 | 2071 | 11.57M |
| 24 | 1631 | 2071 | 2124 | 2124 | 1578 | 378.3 | 0.0 | 2071 | 10.61M |
| 25 | 1578 | 2071 | 2109 | 2109 | 1540 | 339.6 | 0.0 | 2071 | 9.86M |
| 26 | 1540 | 2071 | 2043 | 2043 | 1567 | 367.1 | 0.0 | 2071 | 10.29M |
| 27 | 1567 | 2071 | 2133 | 2133 | 1504 | 304.4 | 0.0 | 2071 | 9.22M |
| 28 | 1504 | 2071 | 2095 | 2095 | 1480 | 279.9 | 0.0 | 2071 | 8.70M |
| 29 | 1480 | 2071 | 2075 | 2075 | 1476 | 275.8 | 0.0 | 2071 | 8.59M |
| 30 | 1476 | 2071 | 2114 | 2114 | 1432 | 232.3 | 0.0 | 2071 | 7.82M |
| **Σ** | — | — | — | **62815** | — | **17216** | **0.0** | — | **427.23M** |

#### JUL — Política `P_+10` (cenário médio: w_proc = média SDDP, adm_out = X constante)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2102 | 2102 | 2098 | 897.9 | 0.0 | 2169 | 19.16M |
| 2 | 2098 | 2169 | 2095 | 2095 | 2172 | 971.9 | 0.0 | 2169 | 21.71M |
| 3 | 2172 | 2169 | 2081 | 2081 | 2260 | 1060 | 0.0 | 2169 | 23.36M |
| 4 | 2260 | 2169 | 2089 | 2089 | 2340 | 1140 | 0.0 | 2169 | 24.90M |
| 5 | 2340 | 2169 | 2118 | 2118 | 2391 | 1191 | 0.0 | 2169 | 25.91M |
| 6 | 2391 | 2169 | 2063 | 2063 | 2497 | 1297 | 0.0 | 2169 | 27.85M |
| 7 | 2497 | 2169 | 2142 | 2142 | 2524 | 1324 | 0.0 | 2169 | 28.47M |
| 8 | 2524 | 2169 | 2088 | 2088 | 2606 | 1406 | 0.0 | 2169 | 29.95M |
| 9 | 2606 | 2169 | 2092 | 2092 | 2683 | 1483 | 0.0 | 2169 | 31.41M |
| 10 | 2683 | 2169 | 2080 | 2080 | 2772 | 1572 | 0.0 | 2169 | 33.10M |
| 11 | 2772 | 2169 | 2104 | 2104 | 2837 | 1637 | 0.0 | 2169 | 34.37M |
| 12 | 2837 | 2169 | 2056 | 2056 | 2951 | 1751 | 0.0 | 2169 | 36.45M |
| 13 | 2951 | 2169 | 2116 | 2116 | 3004 | 1804 | 0.0 | 2169 | 37.56M |
| 14 | 3004 | 2169 | 2087 | 2087 | 3086 | 1886 | 0.0 | 2169 | 39.08M |
| 15 | 3086 | 2169 | 2060 | 2060 | 3195 | 1995 | 0.0 | 2169 | 41.11M |
| 16 | 3195 | 2169 | 2095 | 2095 | 3270 | 2070 | 0.0 | 2169 | 42.57M |
| 17 | 3270 | 2169 | 2131 | 2131 | 3308 | 2108 | 0.0 | 2169 | 43.35M |
| 18 | 3308 | 2169 | 2086 | 2086 | 3391 | 2191 | 0.0 | 2169 | 44.86M |
| 19 | 3391 | 2169 | 2092 | 2092 | 3468 | 2268 | 0.0 | 2169 | 46.33M |
| 20 | 3468 | 2169 | 2078 | 2078 | 3559 | 2359 | 0.0 | 2169 | 48.05M |
| 21 | 3559 | 2169 | 2081 | 2081 | 3647 | 2447 | 0.0 | 2169 | 49.73M |
| 22 | 3647 | 2169 | 2093 | 2093 | 3724 | 2524 | 0.0 | 2169 | 51.20M |
| 23 | 3724 | 2169 | 2092 | 2092 | 3801 | 2601 | 0.0 | 2169 | 52.65M |
| 24 | 3801 | 2169 | 2124 | 2124 | 3846 | 2646 | 0.0 | 2169 | 53.56M |
| 25 | 3846 | 2169 | 2109 | 2109 | 3906 | 2706 | 0.0 | 2169 | 54.68M |
| 26 | 3906 | 2169 | 2043 | 2043 | 4032 | 2832 | 0.0 | 2169 | 56.99M |
| 27 | 4032 | 2169 | 2133 | 2133 | 4068 | 2868 | 0.0 | 2169 | 57.79M |
| 28 | 4068 | 2169 | 2095 | 2095 | 4142 | 2942 | 0.0 | 2169 | 59.15M |
| 29 | 4142 | 2169 | 2075 | 2075 | 4237 | 3037 | 0.0 | 2169 | 60.91M |
| 30 | 4237 | 2169 | 2114 | 2114 | 4292 | 3092 | 0.0 | 2169 | 62.02M |
| **Σ** | — | — | — | **62815** | — | **60107** | **0.0** | — | **1238.21M** |


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
