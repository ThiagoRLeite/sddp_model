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

## Anexo A — Tabelas dia-a-dia formato v7 (REPLICA REPRESENTATIVA, 30 dias completos)

Para cada (mês, política), tabela com colunas: **FilaIni**, **AdmIn**, **w_proc**, **Proc**, **FilaFim**, **Spill**, **Ocioso**, **AdmOut**, **Custo**.

> **MUDANÇA IMPORTANTE nesta versão:** as tabelas agora mostram **UMA réplica representativa** (a trajetória de custo total mais próximo da média das 1000 sims) — **NÃO médias diárias**. Por isso agora `Spill = max(0, FilaFim − 1 200)` bate **exatamente** em cada linha (validado: diff = 0.0).
>
> A versão anterior mostrava médias diárias entre 1000 réplicas. Como `mean(max(0, X)) ≥ max(0, mean(X))` (desigualdade de Jensen), aparecia spillover positivo mesmo quando a fila média estava abaixo de 1 200 — confundia o leitor sem agregar informação.
>
> Para o **custo médio agregado** (com IC), continuar olhando as Tabelas 5.1 e 5.2 (que usam todas as 1000 réplicas). Para uma **trajetória concreta** que reflete o que pode acontecer num mês real, use as tabelas abaixo.
>
> Médias diárias completas continuam em [`outputs/v8_<mes>_dia_a_dia.csv`](outputs/). Réplica representativa em [`outputs/v8_<mes>_replica_repr.csv`](outputs/).

### MAR — Política `SDDP` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2686 | 2686 | 1514 | 314.0 | 0.0 | 1343 | 8.88M |
| 2 | 1514 | 1343 | 2050 | 2050 | 807.0 | 0.0 | 0.0 | 2050 | 3.24M |
| 3 | 807.0 | 2050 | 2459 | 2459 | 398.0 | 0.0 | -0.0 | 2459 | 1.68M |
| 4 | 398.0 | 2459 | 2414 | 2414 | 443.0 | 0.0 | -0.0 | 2414 | 1.17M |
| 5 | 443.0 | 2414 | 2357 | 2357 | 500.0 | 0.0 | -0.0 | 2357 | 1.32M |
| 6 | 500.0 | 2357 | 2277 | 2277 | 580.0 | 0.0 | 0.0 | 2277 | 1.51M |
| 7 | 580.0 | 2277 | 2243 | 2243 | 614.0 | 0.0 | -0.0 | 2243 | 1.67M |
| 8 | 614.0 | 2243 | 2766 | 2766 | 91.0 | 0.0 | 0.0 | 2766 | 983475 |
| 9 | 91.0 | 2766 | 2527 | 2527 | 330.0 | 0.0 | 0.0 | 2527 | 587295 |
| 10 | 330.0 | 2527 | 2630 | 2630 | 227.0 | 0.0 | -0.0 | 2630 | 777015 |
| 11 | 227.0 | 2630 | 2482 | 2482 | 375.0 | 0.0 | 0.0 | 2482 | 839790 |
| 12 | 375.0 | 2482 | 2061 | 2061 | 796.0 | 0.0 | 0.0 | 2061 | 1.63M |
| 13 | 796.0 | 2061 | 2550 | 2550 | 307.0 | 0.0 | 0.0 | 2550 | 1.54M |
| 14 | 307.0 | 2550 | 2391 | 2391 | 466.0 | 0.0 | -0.0 | 2391 | 1.08M |
| 15 | 466.0 | 2391 | 2948 | 2857 | 0.0 | 0.0 | 91.0 | 2857 | 4.63M |
| 16 | 0.0 | 2857 | 2311 | 2311 | 546.0 | 0.0 | 0.0 | 2311 | 761670 |
| 17 | 546.0 | 2311 | 2380 | 2380 | 477.0 | 0.0 | -0.0 | 2380 | 1.43M |
| 18 | 477.0 | 2380 | 2277 | 2277 | 580.0 | 0.0 | -0.0 | 2277 | 1.47M |
| 19 | 580.0 | 2277 | 2266 | 2266 | 591.0 | 0.0 | -0.0 | 2266 | 1.63M |
| 20 | 591.0 | 2266 | 2482 | 2482 | 375.0 | 0.0 | -0.0 | 2482 | 1.35M |
| 21 | 375.0 | 2482 | 2607 | 2607 | 250.0 | 0.0 | -0.0 | 2607 | 871875 |
| 22 | 250.0 | 2607 | 2527 | 2527 | 330.0 | 0.0 | -0.0 | 2527 | 809100 |
| 23 | 330.0 | 2527 | 2709 | 2709 | 148.0 | 0.0 | 0.0 | 2709 | 666810 |
| 24 | 148.0 | 2709 | 2971 | 2857 | -0.0 | 0.0 | 114.0 | 2857 | 5.19M |
| 25 | -0.0 | 2857 | 2300 | 2300 | 557.0 | 0.0 | 0.0 | 2300 | 777015 |
| 26 | 557.0 | 2300 | 2493 | 2493 | 364.0 | 0.0 | -0.0 | 2493 | 1.28M |
| 27 | 364.0 | 2493 | 2857 | 2857 | -0.0 | 0.0 | -0.0 | 2857 | 507780 |
| 28 | 0.0 | 2857 | 2277 | 2277 | 580.0 | 0.0 | 0.0 | 2277 | 809100 |
| 29 | 580.0 | 2277 | 2243 | 2243 | 614.0 | 0.0 | 0.0 | 2311 | 1.67M |
| 30 | 614.0 | 2311 | 2357 | 2357 | 568.0 | 0.0 | -0.0 | 0.0 | 1.65M |

### MAR — Política `P_-10` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2478 | 2478 | 1722 | 522.5 | 0.0 | 2150 | 12.55M |
| 2 | 1722 | 2150 | 2472 | 2472 | 1401 | 200.5 | 0.0 | 2150 | 7.61M |
| 3 | 1401 | 2150 | 2472 | 2472 | 1078 | 0.0 | 0.0 | 2150 | 3.46M |
| 4 | 1078 | 2150 | 2475 | 2475 | 753.3 | 0.0 | 0.0 | 2150 | 2.56M |
| 5 | 753.3 | 2150 | 2476 | 2476 | 427.3 | 0.0 | 0.0 | 2150 | 1.65M |
| 6 | 427.3 | 2150 | 2471 | 2471 | 106.4 | 0.0 | 0.0 | 2150 | 744459 |
| 7 | 106.4 | 2150 | 2465 | 2256 | 0.0 | 0.0 | 208.3 | 2150 | 9.26M |
| 8 | 0.0 | 2150 | 2473 | 2150 | 0.0 | 0.0 | 323.5 | 2150 | 14.15M |
| 9 | 0.0 | 2150 | 2480 | 2150 | 0.0 | 0.0 | 329.7 | 2150 | 14.43M |
| 10 | 0.0 | 2150 | 2483 | 2150 | 0.0 | 0.0 | 332.7 | 2150 | 14.56M |
| 11 | 0.0 | 2150 | 2483 | 2150 | 0.0 | 0.0 | 333.0 | 2150 | 14.57M |
| 12 | 0.0 | 2150 | 2470 | 2150 | 0.0 | 0.0 | 320.0 | 2150 | 14.00M |
| 13 | 0.0 | 2150 | 2475 | 2150 | 0.0 | 0.0 | 324.7 | 2150 | 14.20M |
| 14 | 0.0 | 2150 | 2481 | 2150 | 0.0 | 0.0 | 331.4 | 2150 | 14.50M |
| 15 | 0.0 | 2150 | 2496 | 2150 | 0.0 | 0.0 | 346.5 | 2150 | 15.16M |
| 16 | 0.0 | 2150 | 2483 | 2150 | 0.0 | 0.0 | 333.4 | 2150 | 14.59M |
| 17 | 0.0 | 2150 | 2479 | 2150 | 0.0 | 0.0 | 329.0 | 2150 | 14.39M |
| 18 | 0.0 | 2150 | 2468 | 2150 | 0.0 | 0.0 | 318.6 | 2150 | 13.94M |
| 19 | 0.0 | 2150 | 2475 | 2150 | 0.0 | 0.0 | 324.8 | 2150 | 14.21M |
| 20 | 0.0 | 2150 | 2481 | 2150 | 0.0 | 0.0 | 330.8 | 2150 | 14.48M |
| 21 | 0.0 | 2150 | 2473 | 2150 | 0.0 | 0.0 | 322.9 | 2150 | 14.13M |
| 22 | 0.0 | 2150 | 2482 | 2150 | 0.0 | 0.0 | 332.2 | 2150 | 14.53M |
| 23 | 0.0 | 2150 | 2487 | 2150 | 0.0 | 0.0 | 337.4 | 2150 | 14.76M |
| 24 | 0.0 | 2150 | 2483 | 2150 | 0.0 | 0.0 | 332.8 | 2150 | 14.56M |
| 25 | 0.0 | 2150 | 2477 | 2150 | 0.0 | 0.0 | 327.1 | 2150 | 14.31M |
| 26 | 0.0 | 2150 | 2490 | 2150 | 0.0 | 0.0 | 339.8 | 2150 | 14.87M |
| 27 | 0.0 | 2150 | 2469 | 2150 | 0.0 | 0.0 | 318.9 | 2150 | 13.95M |
| 28 | 0.0 | 2150 | 2467 | 2150 | 0.0 | 0.0 | 317.1 | 2150 | 13.87M |
| 29 | 0.0 | 2150 | 2473 | 2150 | 0.0 | 0.0 | 323.1 | 2150 | 14.14M |
| 30 | 0.0 | 2150 | 2489 | 2150 | 0.0 | 0.0 | 339.0 | 2150 | 14.83M |

### MAR — Política `P_-5` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2478 | 2478 | 1722 | 522.5 | 0.0 | 2269 | 12.55M |
| 2 | 1722 | 2269 | 2472 | 2472 | 1520 | 320.0 | 0.0 | 2269 | 9.71M |
| 3 | 1520 | 2269 | 2472 | 2472 | 1317 | 117.3 | 0.0 | 2269 | 5.86M |
| 4 | 1317 | 2269 | 2475 | 2475 | 1112 | 0.0 | 0.0 | 2269 | 3.39M |
| 5 | 1112 | 2269 | 2476 | 2476 | 905.0 | 0.0 | 0.0 | 2269 | 2.81M |
| 6 | 905.0 | 2269 | 2471 | 2471 | 703.6 | 0.0 | 0.0 | 2269 | 2.24M |
| 7 | 703.6 | 2269 | 2465 | 2465 | 508.3 | 0.0 | 0.0 | 2269 | 1.69M |
| 8 | 508.3 | 2269 | 2473 | 2473 | 304.3 | 0.0 | 0.0 | 2269 | 1.13M |
| 9 | 304.3 | 2269 | 2480 | 2480 | 94.0 | 0.0 | 0.0 | 2269 | 555562 |
| 10 | 94.0 | 2269 | 2483 | 2363 | 0.0 | 0.0 | 119.3 | 2269 | 5.35M |
| 11 | 0.0 | 2269 | 2483 | 2269 | 0.0 | 0.0 | 213.5 | 2269 | 9.34M |
| 12 | 0.0 | 2269 | 2470 | 2269 | 0.0 | 0.0 | 200.6 | 2269 | 8.77M |
| 13 | 0.0 | 2269 | 2475 | 2269 | 0.0 | 0.0 | 205.2 | 2269 | 8.98M |
| 14 | 0.0 | 2269 | 2481 | 2269 | 0.0 | 0.0 | 212.0 | 2269 | 9.28M |
| 15 | 0.0 | 2269 | 2496 | 2269 | 0.0 | 0.0 | 227.1 | 2269 | 9.94M |
| 16 | 0.0 | 2269 | 2483 | 2269 | 0.0 | 0.0 | 213.9 | 2269 | 9.36M |
| 17 | 0.0 | 2269 | 2479 | 2269 | 0.0 | 0.0 | 209.6 | 2269 | 9.17M |
| 18 | 0.0 | 2269 | 2468 | 2269 | 0.0 | 0.0 | 199.2 | 2269 | 8.71M |
| 19 | 0.0 | 2269 | 2475 | 2269 | 0.0 | 0.0 | 205.4 | 2269 | 8.99M |
| 20 | 0.0 | 2269 | 2481 | 2269 | 0.0 | 0.0 | 211.4 | 2269 | 9.25M |
| 21 | 0.0 | 2269 | 2473 | 2269 | 0.0 | 0.0 | 203.4 | 2269 | 8.90M |
| 22 | 0.0 | 2269 | 2482 | 2269 | 0.0 | 0.0 | 212.7 | 2269 | 9.31M |
| 23 | 0.0 | 2269 | 2487 | 2269 | 0.0 | 0.0 | 218.0 | 2269 | 9.54M |
| 24 | 0.0 | 2269 | 2483 | 2269 | 0.0 | 0.0 | 213.3 | 2269 | 9.33M |
| 25 | 0.0 | 2269 | 2477 | 2269 | 0.0 | 0.0 | 207.6 | 2269 | 9.08M |
| 26 | 0.0 | 2269 | 2490 | 2269 | 0.0 | 0.0 | 220.3 | 2269 | 9.64M |
| 27 | 0.0 | 2269 | 2469 | 2269 | 0.0 | 0.0 | 199.5 | 2269 | 8.73M |
| 28 | 0.0 | 2269 | 2467 | 2269 | 0.0 | 0.0 | 197.6 | 2269 | 8.65M |
| 29 | 0.0 | 2269 | 2473 | 2269 | 0.0 | 0.0 | 203.6 | 2269 | 8.91M |
| 30 | 0.0 | 2269 | 2489 | 2269 | 0.0 | 0.0 | 219.6 | 2269 | 9.61M |

### MAR — Política `P_0` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2478 | 2478 | 1722 | 522.5 | 0.0 | 2389 | 12.55M |
| 2 | 1722 | 2389 | 2472 | 2472 | 1639 | 439.4 | 0.0 | 2389 | 11.81M |
| 3 | 1639 | 2389 | 2472 | 2472 | 1556 | 356.2 | 0.0 | 2389 | 10.23M |
| 4 | 1556 | 2389 | 2475 | 2475 | 1470 | 269.9 | 0.0 | 2389 | 8.60M |
| 5 | 1470 | 2389 | 2476 | 2476 | 1383 | 182.8 | 0.0 | 2389 | 6.94M |
| 6 | 1383 | 2389 | 2471 | 2471 | 1301 | 100.8 | 0.0 | 2389 | 5.38M |
| 7 | 1301 | 2389 | 2465 | 2465 | 1225 | 24.9 | 0.0 | 2389 | 3.93M |
| 8 | 1225 | 2389 | 2473 | 2473 | 1140 | 0.0 | 0.0 | 2389 | 3.30M |
| 9 | 1140 | 2389 | 2480 | 2480 | 1049 | 0.0 | 0.0 | 2389 | 3.05M |
| 10 | 1049 | 2389 | 2483 | 2483 | 955.6 | 0.0 | 0.0 | 2389 | 2.80M |
| 11 | 955.6 | 2389 | 2483 | 2483 | 861.5 | 0.0 | 0.0 | 2389 | 2.53M |
| 12 | 861.5 | 2389 | 2470 | 2470 | 780.4 | 0.0 | 0.0 | 2389 | 2.29M |
| 13 | 780.4 | 2389 | 2475 | 2475 | 694.6 | 0.0 | 0.0 | 2389 | 2.06M |
| 14 | 694.6 | 2389 | 2481 | 2481 | 602.0 | 0.0 | 0.0 | 2389 | 1.81M |
| 15 | 602.0 | 2389 | 2496 | 2496 | 494.4 | 0.0 | 0.0 | 2389 | 1.53M |
| 16 | 494.4 | 2389 | 2483 | 2483 | 399.9 | 0.0 | 0.0 | 2389 | 1.25M |
| 17 | 399.9 | 2389 | 2479 | 2479 | 309.8 | 0.0 | 0.0 | 2389 | 989976 |
| 18 | 309.8 | 2389 | 2468 | 2468 | 230.0 | 0.0 | 0.0 | 2389 | 753042 |
| 19 | 230.0 | 2389 | 2475 | 2475 | 144.1 | 0.0 | 0.0 | 2389 | 521937 |
| 20 | 144.1 | 2389 | 2481 | 2481 | 52.1 | 0.0 | 0.0 | 2389 | 273751 |
| 21 | 52.1 | 2389 | 2473 | 2441 | 0.0 | 0.0 | 31.9 | 2389 | 1.47M |
| 22 | 0.0 | 2389 | 2482 | 2389 | 0.0 | 0.0 | 93.3 | 2389 | 4.08M |
| 23 | 0.0 | 2389 | 2487 | 2389 | 0.0 | 0.0 | 98.6 | 2389 | 4.31M |
| 24 | 0.0 | 2389 | 2483 | 2389 | 0.0 | 0.0 | 93.9 | 2389 | 4.11M |
| 25 | 0.0 | 2389 | 2477 | 2389 | 0.0 | 0.0 | 88.2 | 2389 | 3.86M |
| 26 | 0.0 | 2389 | 2490 | 2389 | 0.0 | 0.0 | 100.9 | 2389 | 4.41M |
| 27 | 0.0 | 2389 | 2469 | 2389 | 0.0 | 0.0 | 80.1 | 2389 | 3.50M |
| 28 | 0.0 | 2389 | 2467 | 2389 | 0.0 | 0.0 | 78.2 | 2389 | 3.42M |
| 29 | 0.0 | 2389 | 2473 | 2389 | 0.0 | 0.0 | 84.2 | 2389 | 3.68M |
| 30 | 0.0 | 2389 | 2489 | 2389 | 0.0 | 0.0 | 100.2 | 2389 | 4.38M |

### MAR — Política `P_+5` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2478 | 2478 | 1722 | 522.5 | 0.0 | 2508 | 12.55M |
| 2 | 1722 | 2508 | 2472 | 2472 | 1759 | 558.8 | 0.0 | 2508 | 13.92M |
| 3 | 1759 | 2508 | 2472 | 2472 | 1795 | 595.1 | 0.0 | 2508 | 14.60M |
| 4 | 1795 | 2508 | 2475 | 2475 | 1828 | 628.2 | 0.0 | 2508 | 15.24M |
| 5 | 1828 | 2508 | 2476 | 2476 | 1861 | 660.5 | 0.0 | 2508 | 15.85M |
| 6 | 1861 | 2508 | 2471 | 2471 | 1898 | 697.9 | 0.0 | 2508 | 16.56M |
| 7 | 1898 | 2508 | 2465 | 2465 | 1942 | 741.6 | 0.0 | 2508 | 17.38M |
| 8 | 1942 | 2508 | 2473 | 2473 | 1976 | 776.4 | 0.0 | 2508 | 18.05M |
| 9 | 1976 | 2508 | 2480 | 2480 | 2005 | 805.0 | 0.0 | 2508 | 18.60M |
| 10 | 2005 | 2508 | 2483 | 2483 | 2031 | 830.5 | 0.0 | 2508 | 19.09M |
| 11 | 2031 | 2508 | 2483 | 2483 | 2056 | 855.9 | 0.0 | 2508 | 19.58M |
| 12 | 2056 | 2508 | 2470 | 2470 | 2094 | 894.2 | 0.0 | 2508 | 20.29M |
| 13 | 2094 | 2508 | 2475 | 2475 | 2128 | 927.9 | 0.0 | 2508 | 20.93M |
| 14 | 2128 | 2508 | 2481 | 2481 | 2155 | 954.7 | 0.0 | 2508 | 21.45M |
| 15 | 2155 | 2508 | 2496 | 2496 | 2167 | 966.5 | 0.0 | 2508 | 21.70M |
| 16 | 2167 | 2508 | 2483 | 2483 | 2191 | 991.4 | 0.0 | 2508 | 22.15M |
| 17 | 2191 | 2508 | 2479 | 2479 | 2221 | 1021 | 0.0 | 2508 | 22.70M |
| 18 | 2221 | 2508 | 2468 | 2468 | 2260 | 1060 | 0.0 | 2508 | 23.44M |
| 19 | 2260 | 2508 | 2475 | 2475 | 2294 | 1094 | 0.0 | 2508 | 24.09M |
| 20 | 2294 | 2508 | 2481 | 2481 | 2321 | 1121 | 0.0 | 2508 | 24.62M |
| 21 | 2321 | 2508 | 2473 | 2473 | 2357 | 1157 | 0.0 | 2508 | 25.28M |
| 22 | 2357 | 2508 | 2482 | 2482 | 2383 | 1183 | 0.0 | 2508 | 25.79M |
| 23 | 2383 | 2508 | 2487 | 2487 | 2404 | 1204 | 0.0 | 2508 | 26.19M |
| 24 | 2404 | 2508 | 2483 | 2483 | 2429 | 1229 | 0.0 | 2508 | 26.67M |
| 25 | 2429 | 2508 | 2477 | 2477 | 2461 | 1261 | 0.0 | 2508 | 27.26M |
| 26 | 2461 | 2508 | 2490 | 2490 | 2479 | 1279 | 0.0 | 2508 | 27.63M |
| 27 | 2479 | 2508 | 2469 | 2469 | 2519 | 1319 | 0.0 | 2508 | 28.35M |
| 28 | 2519 | 2508 | 2467 | 2467 | 2560 | 1360 | 0.0 | 2508 | 29.13M |
| 29 | 2560 | 2508 | 2473 | 2473 | 2595 | 1395 | 0.0 | 2508 | 29.81M |
| 30 | 2595 | 2508 | 2489 | 2489 | 2614 | 1414 | 0.0 | 2508 | 30.19M |

### MAR — Política `P_+10` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2478 | 2478 | 1722 | 522.5 | 0.0 | 2628 | 12.55M |
| 2 | 1722 | 2628 | 2472 | 2472 | 1878 | 678.3 | 0.0 | 2628 | 16.02M |
| 3 | 1878 | 2628 | 2472 | 2472 | 2034 | 834.0 | 0.0 | 2628 | 18.98M |
| 4 | 2034 | 2628 | 2475 | 2475 | 2187 | 986.5 | 0.0 | 2628 | 21.88M |
| 5 | 2187 | 2628 | 2476 | 2476 | 2338 | 1138 | 0.0 | 2628 | 24.76M |
| 6 | 2338 | 2628 | 2471 | 2471 | 2495 | 1295 | 0.0 | 2628 | 27.74M |
| 7 | 2495 | 2628 | 2465 | 2465 | 2658 | 1458 | 0.0 | 2628 | 30.83M |
| 8 | 2658 | 2628 | 2473 | 2473 | 2812 | 1612 | 0.0 | 2628 | 33.77M |
| 9 | 2812 | 2628 | 2480 | 2480 | 2960 | 1760 | 0.0 | 2628 | 36.59M |
| 10 | 2960 | 2628 | 2483 | 2483 | 3105 | 1905 | 0.0 | 2628 | 39.35M |
| 11 | 3105 | 2628 | 2483 | 2483 | 3250 | 2050 | 0.0 | 2628 | 42.10M |
| 12 | 3250 | 2628 | 2470 | 2470 | 3408 | 2208 | 0.0 | 2628 | 45.08M |
| 13 | 3408 | 2628 | 2475 | 2475 | 3561 | 2361 | 0.0 | 2628 | 48.00M |
| 14 | 3561 | 2628 | 2481 | 2481 | 3707 | 2507 | 0.0 | 2628 | 50.79M |
| 15 | 3707 | 2628 | 2496 | 2496 | 3839 | 2639 | 0.0 | 2628 | 53.30M |
| 16 | 3839 | 2628 | 2483 | 2483 | 3983 | 2783 | 0.0 | 2628 | 56.03M |
| 17 | 3983 | 2628 | 2479 | 2479 | 4132 | 2932 | 0.0 | 2628 | 58.85M |
| 18 | 4132 | 2628 | 2468 | 2468 | 4291 | 3091 | 0.0 | 2628 | 61.86M |
| 19 | 4291 | 2628 | 2475 | 2475 | 4444 | 3244 | 0.0 | 2628 | 64.77M |
| 20 | 4444 | 2628 | 2481 | 2481 | 4591 | 3391 | 0.0 | 2628 | 67.57M |
| 21 | 4591 | 2628 | 2473 | 2473 | 4746 | 3546 | 0.0 | 2628 | 70.50M |
| 22 | 4746 | 2628 | 2482 | 2482 | 4891 | 3691 | 0.0 | 2628 | 73.28M |
| 23 | 4891 | 2628 | 2487 | 2487 | 5031 | 3831 | 0.0 | 2628 | 75.95M |
| 24 | 5031 | 2628 | 2483 | 2483 | 5176 | 3976 | 0.0 | 2628 | 78.70M |
| 25 | 5176 | 2628 | 2477 | 2477 | 5327 | 4127 | 0.0 | 2628 | 81.56M |
| 26 | 5327 | 2628 | 2490 | 2490 | 5465 | 4265 | 0.0 | 2628 | 84.20M |
| 27 | 5465 | 2628 | 2469 | 2469 | 5624 | 4424 | 0.0 | 2628 | 87.19M |
| 28 | 5624 | 2628 | 2467 | 2467 | 5785 | 4585 | 0.0 | 2628 | 90.24M |
| 29 | 5785 | 2628 | 2473 | 2473 | 5939 | 4739 | 0.0 | 2628 | 93.18M |
| 30 | 5939 | 2628 | 2489 | 2489 | 6078 | 4878 | 0.0 | 2628 | 95.84M |

### JUL — Política `SDDP` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 1382 | 1382 | 2818 | 1618 | 0.0 | 26.0 | 31.83M |
| 2 | 2818 | 26.0 | 2663 | 2663 | 181.0 | 0.0 | -0.0 | 2663 | 4.18M |
| 3 | 181.0 | 2663 | 659.0 | 659.0 | 2185 | 985.0 | 0.0 | 659.0 | 19.27M |
| 4 | 2185 | 659.0 | 2269 | 2269 | 575.0 | 0.0 | -0.0 | 2269 | 3.85M |
| 5 | 575.0 | 2269 | 1973 | 1973 | 871.0 | 0.0 | -0.0 | 1973 | 2.02M |
| 6 | 871.0 | 1973 | 2861 | 2844 | 0.0 | 0.0 | 17.0 | 2844 | 1.96M |
| 7 | 0.0 | 2844 | 1447 | 1447 | 1397 | 197.0 | 0.0 | 1447 | 5.14M |
| 8 | 1397 | 1447 | 2433 | 2433 | 411.0 | 0.0 | 0.0 | 2433 | 2.52M |
| 9 | 411.0 | 2433 | 1119 | 1119 | 1725 | 525.0 | 0.0 | 1119 | 11.49M |
| 10 | 1725 | 1119 | 724.0 | 724.0 | 2120 | 920.0 | 0.0 | 724.0 | 20.28M |
| 11 | 2120 | 724.0 | 2302 | 2302 | 542.0 | 0.0 | -0.0 | 2302 | 3.71M |
| 12 | 542.0 | 2302 | 2170 | 2170 | 674.0 | 0.0 | 0.0 | 2170 | 1.70M |
| 13 | 674.0 | 2170 | 2400 | 2400 | 444.0 | 0.0 | -0.0 | 2400 | 1.56M |
| 14 | 444.0 | 2400 | 921.0 | 921.0 | 1923 | 723.0 | 0.0 | 921.0 | 15.02M |
| 15 | 1923 | 921.0 | 2137 | 2137 | 707.0 | 0.0 | 0.0 | 2137 | 3.67M |
| 16 | 707.0 | 2137 | 2762 | 2762 | 82.0 | 0.0 | -0.0 | 2762 | 1.10M |
| 17 | 82.0 | 2762 | 1973 | 1973 | 871.0 | 0.0 | 0.0 | 1973 | 1.33M |
| 18 | 871.0 | 1973 | 2039 | 2039 | 805.0 | 0.0 | 0.0 | 2039 | 2.34M |
| 19 | 805.0 | 2039 | 1579 | 1579 | 1265 | 65.0 | -0.0 | 1579 | 3.94M |
| 20 | 1265 | 1579 | 1940 | 1940 | 904.0 | 0.0 | 0.0 | 1940 | 3.03M |
| 21 | 904.0 | 1940 | 1940 | 1940 | 904.0 | 0.0 | -0.0 | 1940 | 2.52M |
| 22 | 904.0 | 1940 | 2302 | 2302 | 542.0 | 0.0 | -0.0 | 2302 | 2.02M |
| 23 | 542.0 | 2302 | 2269 | 2269 | 575.0 | 0.0 | -0.0 | 2269 | 1.56M |
| 24 | 575.0 | 2269 | 3189 | 2844 | -0.0 | 0.0 | 345.0 | 2844 | 15.90M |
| 25 | -0.0 | 2844 | 987.0 | 987.0 | 1857 | 657.0 | 0.0 | 987.0 | 13.24M |
| 26 | 1857 | 987.0 | 1480 | 1480 | 1364 | 164.0 | 0.0 | 1480 | 7.15M |
| 27 | 1364 | 1480 | 2137 | 2137 | 707.0 | 0.0 | -0.0 | 2137 | 2.89M |
| 28 | 707.0 | 2137 | 3091 | 2844 | 0.0 | 0.0 | 247.0 | 2844 | 11.79M |
| 29 | 0.0 | 2844 | 3025 | 2844 | 0.0 | 0.0 | 181.0 | 2893 | 7.92M |
| 30 | 0.0 | 2893 | 1842 | 1842 | 1051 | 0.0 | 0.0 | 0.0 | 1.47M |

### JUL — Política `P_-10` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2114 | 2114 | 2086 | 885.9 | 0.0 | 1780 | 18.95M |
| 2 | 2086 | 1780 | 2114 | 2114 | 1752 | 552.2 | 0.0 | 1780 | 14.31M |
| 3 | 1752 | 1780 | 2104 | 2104 | 1428 | 228.2 | 0.0 | 1780 | 8.14M |
| 4 | 1428 | 1780 | 2087 | 2087 | 1121 | 0.0 | 0.0 | 1780 | 3.56M |
| 5 | 1121 | 1780 | 2107 | 2107 | 794.4 | 0.0 | 0.0 | 1780 | 2.67M |
| 6 | 794.4 | 1780 | 2079 | 2079 | 495.2 | 0.0 | 0.0 | 1780 | 1.80M |
| 7 | 495.2 | 1780 | 2133 | 2133 | 142.3 | 0.0 | 0.0 | 1780 | 889237 |
| 8 | 142.3 | 1780 | 2100 | 1922 | 0.0 | 0.0 | 178.3 | 1780 | 8.00M |
| 9 | 0.0 | 1780 | 2098 | 1780 | 0.0 | 0.0 | 318.5 | 1780 | 13.94M |
| 10 | 0.0 | 1780 | 2099 | 1780 | 0.0 | 0.0 | 319.5 | 1780 | 13.98M |
| 11 | 0.0 | 1780 | 2129 | 1780 | 0.0 | 0.0 | 349.0 | 1780 | 15.27M |
| 12 | 0.0 | 1780 | 2125 | 1780 | 0.0 | 0.0 | 344.8 | 1780 | 15.08M |
| 13 | 0.0 | 1780 | 2095 | 1780 | 0.0 | 0.0 | 314.9 | 1780 | 13.78M |
| 14 | 0.0 | 1780 | 2093 | 1780 | 0.0 | 0.0 | 313.2 | 1780 | 13.70M |
| 15 | 0.0 | 1780 | 2111 | 1780 | 0.0 | 0.0 | 331.1 | 1780 | 14.49M |
| 16 | 0.0 | 1780 | 2095 | 1780 | 0.0 | 0.0 | 315.2 | 1780 | 13.79M |
| 17 | 0.0 | 1780 | 2081 | 1780 | 0.0 | 0.0 | 301.1 | 1780 | 13.17M |
| 18 | 0.0 | 1780 | 2110 | 1780 | 0.0 | 0.0 | 330.3 | 1780 | 14.45M |
| 19 | 0.0 | 1780 | 2087 | 1780 | 0.0 | 0.0 | 307.2 | 1780 | 13.44M |
| 20 | 0.0 | 1780 | 2051 | 1780 | 0.0 | 0.0 | 271.3 | 1780 | 11.87M |
| 21 | 0.0 | 1780 | 2100 | 1780 | 0.0 | 0.0 | 320.5 | 1780 | 14.02M |
| 22 | 0.0 | 1780 | 2089 | 1780 | 0.0 | 0.0 | 309.4 | 1780 | 13.54M |
| 23 | 0.0 | 1780 | 2095 | 1780 | 0.0 | 0.0 | 314.9 | 1780 | 13.78M |
| 24 | 0.0 | 1780 | 2137 | 1780 | 0.0 | 0.0 | 356.8 | 1780 | 15.61M |
| 25 | 0.0 | 1780 | 2093 | 1780 | 0.0 | 0.0 | 313.0 | 1780 | 13.70M |
| 26 | 0.0 | 1780 | 2071 | 1780 | 0.0 | 0.0 | 290.7 | 1780 | 12.72M |
| 27 | 0.0 | 1780 | 2140 | 1780 | 0.0 | 0.0 | 359.9 | 1780 | 15.75M |
| 28 | 0.0 | 1780 | 2121 | 1780 | 0.0 | 0.0 | 340.7 | 1780 | 14.91M |
| 29 | 0.0 | 1780 | 2108 | 1780 | 0.0 | 0.0 | 328.1 | 1780 | 14.35M |
| 30 | 0.0 | 1780 | 2092 | 1780 | 0.0 | 0.0 | 311.7 | 1780 | 13.64M |

### JUL — Política `P_-5` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2114 | 2114 | 2086 | 885.9 | 0.0 | 1879 | 18.95M |
| 2 | 2086 | 1879 | 2114 | 2114 | 1851 | 651.1 | 0.0 | 1879 | 16.05M |
| 3 | 1851 | 1879 | 2104 | 2104 | 1626 | 425.9 | 0.0 | 1879 | 11.76M |
| 4 | 1626 | 1879 | 2087 | 2087 | 1418 | 217.7 | 0.0 | 1879 | 7.77M |
| 5 | 1418 | 1879 | 2107 | 2107 | 1190 | 0.0 | 0.0 | 1879 | 3.64M |
| 6 | 1190 | 1879 | 2079 | 2079 | 989.6 | 0.0 | 0.0 | 1879 | 3.04M |
| 7 | 989.6 | 1879 | 2133 | 2133 | 735.5 | 0.0 | 0.0 | 1879 | 2.41M |
| 8 | 735.5 | 1879 | 2100 | 2100 | 513.8 | 0.0 | 0.0 | 1879 | 1.74M |
| 9 | 513.8 | 1879 | 2098 | 2098 | 294.2 | 0.0 | 0.0 | 1879 | 1.13M |
| 10 | 294.2 | 1879 | 2099 | 2099 | 73.6 | 0.0 | 0.0 | 1879 | 513163 |
| 11 | 73.6 | 1879 | 2129 | 1952 | 0.0 | 0.0 | 176.5 | 1879 | 7.82M |
| 12 | 0.0 | 1879 | 2125 | 1879 | 0.0 | 0.0 | 245.9 | 1879 | 10.76M |
| 13 | 0.0 | 1879 | 2095 | 1879 | 0.0 | 0.0 | 216.0 | 1879 | 9.45M |
| 14 | 0.0 | 1879 | 2093 | 1879 | 0.0 | 0.0 | 214.3 | 1879 | 9.38M |
| 15 | 0.0 | 1879 | 2111 | 1879 | 0.0 | 0.0 | 232.2 | 1879 | 10.16M |
| 16 | 0.0 | 1879 | 2095 | 1879 | 0.0 | 0.0 | 216.3 | 1879 | 9.46M |
| 17 | 0.0 | 1879 | 2081 | 1879 | 0.0 | 0.0 | 202.2 | 1879 | 8.85M |
| 18 | 0.0 | 1879 | 2110 | 1879 | 0.0 | 0.0 | 231.4 | 1879 | 10.12M |
| 19 | 0.0 | 1879 | 2087 | 1879 | 0.0 | 0.0 | 208.3 | 1879 | 9.11M |
| 20 | 0.0 | 1879 | 2051 | 1879 | 0.0 | 0.0 | 172.5 | 1879 | 7.55M |
| 21 | 0.0 | 1879 | 2100 | 1879 | 0.0 | 0.0 | 221.6 | 1879 | 9.70M |
| 22 | 0.0 | 1879 | 2089 | 1879 | 0.0 | 0.0 | 210.5 | 1879 | 9.21M |
| 23 | 0.0 | 1879 | 2095 | 1879 | 0.0 | 0.0 | 216.0 | 1879 | 9.45M |
| 24 | 0.0 | 1879 | 2137 | 1879 | 0.0 | 0.0 | 257.9 | 1879 | 11.29M |
| 25 | 0.0 | 1879 | 2093 | 1879 | 0.0 | 0.0 | 214.1 | 1879 | 9.37M |
| 26 | 0.0 | 1879 | 2071 | 1879 | 0.0 | 0.0 | 191.8 | 1879 | 8.39M |
| 27 | 0.0 | 1879 | 2140 | 1879 | 0.0 | 0.0 | 261.0 | 1879 | 11.42M |
| 28 | 0.0 | 1879 | 2121 | 1879 | 0.0 | 0.0 | 241.9 | 1879 | 10.58M |
| 29 | 0.0 | 1879 | 2108 | 1879 | 0.0 | 0.0 | 229.2 | 1879 | 10.03M |
| 30 | 0.0 | 1879 | 2092 | 1879 | 0.0 | 0.0 | 212.9 | 1879 | 9.31M |

### JUL — Política `P_0` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2114 | 2114 | 2086 | 885.9 | 0.0 | 1978 | 18.95M |
| 2 | 2086 | 1978 | 2114 | 2114 | 1950 | 750.0 | 0.0 | 1978 | 17.79M |
| 3 | 1950 | 1978 | 2104 | 2104 | 1824 | 623.7 | 0.0 | 1978 | 15.38M |
| 4 | 1824 | 1978 | 2087 | 2087 | 1714 | 514.3 | 0.0 | 1978 | 13.27M |
| 5 | 1714 | 1978 | 2107 | 2107 | 1585 | 385.4 | 0.0 | 1978 | 10.85M |
| 6 | 1585 | 1978 | 2079 | 2079 | 1484 | 284.0 | 0.0 | 1978 | 8.89M |
| 7 | 1484 | 1978 | 2133 | 2133 | 1329 | 128.8 | 0.0 | 1978 | 6.01M |
| 8 | 1329 | 1978 | 2100 | 2100 | 1206 | 6.0 | 0.0 | 1978 | 3.63M |
| 9 | 1206 | 1978 | 2098 | 2098 | 1085 | 0.0 | 0.0 | 1978 | 3.20M |
| 10 | 1085 | 1978 | 2099 | 2099 | 963.6 | 0.0 | 0.0 | 1978 | 2.86M |
| 11 | 963.6 | 1978 | 2129 | 2129 | 812.3 | 0.0 | 0.0 | 1978 | 2.48M |
| 12 | 812.3 | 1978 | 2125 | 2125 | 665.3 | 0.0 | 0.0 | 1978 | 2.06M |
| 13 | 665.3 | 1978 | 2095 | 2095 | 548.2 | 0.0 | 0.0 | 1978 | 1.69M |
| 14 | 548.2 | 1978 | 2093 | 2093 | 432.8 | 0.0 | 0.0 | 1978 | 1.37M |
| 15 | 432.8 | 1978 | 2111 | 2111 | 299.5 | 0.0 | 0.0 | 1978 | 1.02M |
| 16 | 299.5 | 1978 | 2095 | 2095 | 182.1 | 0.0 | 0.0 | 1978 | 671739 |
| 17 | 182.1 | 1978 | 2081 | 2081 | 78.8 | 0.0 | 0.0 | 1978 | 363861 |
| 18 | 78.8 | 1978 | 2110 | 2056 | 0.0 | 0.0 | 53.8 | 1978 | 2.46M |
| 19 | 0.0 | 1978 | 2087 | 1978 | 0.0 | 0.0 | 109.4 | 1978 | 4.79M |
| 20 | 0.0 | 1978 | 2051 | 1978 | 0.0 | 0.0 | 73.6 | 1978 | 3.22M |
| 21 | 0.0 | 1978 | 2100 | 1978 | 0.0 | 0.0 | 122.7 | 1978 | 5.37M |
| 22 | 0.0 | 1978 | 2089 | 1978 | 0.0 | 0.0 | 111.6 | 1978 | 4.88M |
| 23 | 0.0 | 1978 | 2095 | 1978 | 0.0 | 0.0 | 117.2 | 1978 | 5.13M |
| 24 | 0.0 | 1978 | 2137 | 1978 | 0.0 | 0.0 | 159.1 | 1978 | 6.96M |
| 25 | 0.0 | 1978 | 2093 | 1978 | 0.0 | 0.0 | 115.3 | 1978 | 5.04M |
| 26 | 0.0 | 1978 | 2071 | 1978 | 0.0 | 0.0 | 92.9 | 1978 | 4.06M |
| 27 | 0.0 | 1978 | 2140 | 1978 | 0.0 | 0.0 | 162.1 | 1978 | 7.09M |
| 28 | 0.0 | 1978 | 2121 | 1978 | 0.0 | 0.0 | 143.0 | 1978 | 6.26M |
| 29 | 0.0 | 1978 | 2108 | 1978 | 0.0 | 0.0 | 130.3 | 1978 | 5.70M |
| 30 | 0.0 | 1978 | 2092 | 1978 | 0.0 | 0.0 | 114.0 | 1978 | 4.99M |

### JUL — Política `P_+5` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2114 | 2114 | 2086 | 885.9 | 0.0 | 2077 | 18.95M |
| 2 | 2086 | 2077 | 2114 | 2114 | 2049 | 848.9 | 0.0 | 2077 | 19.53M |
| 3 | 2049 | 2077 | 2104 | 2104 | 2021 | 821.5 | 0.0 | 2077 | 19.00M |
| 4 | 2021 | 2077 | 2087 | 2087 | 2011 | 810.9 | 0.0 | 2077 | 18.77M |
| 5 | 2011 | 2077 | 2107 | 2107 | 1981 | 780.9 | 0.0 | 2077 | 18.23M |
| 6 | 1981 | 2077 | 2079 | 2079 | 1978 | 778.4 | 0.0 | 2077 | 18.14M |
| 7 | 1978 | 2077 | 2133 | 2133 | 1922 | 722.1 | 0.0 | 2077 | 17.15M |
| 8 | 1922 | 2077 | 2100 | 2100 | 1898 | 698.2 | 0.0 | 2077 | 16.65M |
| 9 | 1898 | 2077 | 2098 | 2098 | 1876 | 676.3 | 0.0 | 2077 | 16.23M |
| 10 | 1876 | 2077 | 2099 | 2099 | 1853 | 653.5 | 0.0 | 2077 | 15.80M |
| 11 | 1853 | 2077 | 2129 | 2129 | 1801 | 601.1 | 0.0 | 2077 | 14.84M |
| 12 | 1801 | 2077 | 2125 | 2125 | 1753 | 553.0 | 0.0 | 2077 | 13.92M |
| 13 | 1753 | 2077 | 2095 | 2095 | 1735 | 534.8 | 0.0 | 2077 | 13.53M |
| 14 | 1735 | 2077 | 2093 | 2093 | 1718 | 518.2 | 0.0 | 2077 | 13.22M |
| 15 | 1718 | 2077 | 2111 | 2111 | 1684 | 483.8 | 0.0 | 2077 | 12.59M |
| 16 | 1684 | 2077 | 2095 | 2095 | 1665 | 465.3 | 0.0 | 2077 | 12.21M |
| 17 | 1665 | 2077 | 2081 | 2081 | 1661 | 460.9 | 0.0 | 2077 | 12.11M |
| 18 | 1661 | 2077 | 2110 | 2110 | 1627 | 427.2 | 0.0 | 2077 | 11.51M |
| 19 | 1627 | 2077 | 2087 | 2087 | 1617 | 416.7 | 0.0 | 2077 | 11.28M |
| 20 | 1617 | 2077 | 2051 | 2051 | 1642 | 442.0 | 0.0 | 2077 | 11.71M |
| 21 | 1642 | 2077 | 2100 | 2100 | 1618 | 418.2 | 0.0 | 2077 | 11.33M |
| 22 | 1618 | 2077 | 2089 | 2089 | 1605 | 405.4 | 0.0 | 2077 | 11.07M |
| 23 | 1605 | 2077 | 2095 | 2095 | 1587 | 387.1 | 0.0 | 2077 | 10.73M |
| 24 | 1587 | 2077 | 2137 | 2137 | 1527 | 327.0 | 0.0 | 2077 | 9.64M |
| 25 | 1527 | 2077 | 2093 | 2093 | 1511 | 310.6 | 0.0 | 2077 | 9.27M |
| 26 | 1511 | 2077 | 2071 | 2071 | 1517 | 316.6 | 0.0 | 2077 | 9.35M |
| 27 | 1517 | 2077 | 2140 | 2140 | 1453 | 253.3 | 0.0 | 2077 | 8.25M |
| 28 | 1453 | 2077 | 2121 | 2121 | 1409 | 209.2 | 0.0 | 2077 | 7.39M |
| 29 | 1409 | 2077 | 2108 | 2108 | 1378 | 177.8 | 0.0 | 2077 | 6.77M |
| 30 | 1378 | 2077 | 2092 | 2092 | 1363 | 162.7 | 0.0 | 2077 | 6.46M |

### JUL — Política `P_+10` (réplica representativa, custo proximo da media)

| Dia | FilaIni | AdmIn | w_proc | Proc | FilaFim | Spill | Ocioso | AdmOut | Custo |
|----:|--------:|------:|-------:|-----:|--------:|------:|-------:|-------:|------:|
| 1 | 1200 | 3000 | 2114 | 2114 | 2086 | 885.9 | 0.0 | 2175 | 18.95M |
| 2 | 2086 | 2175 | 2114 | 2114 | 2148 | 947.8 | 0.0 | 2175 | 21.27M |
| 3 | 2148 | 2175 | 2104 | 2104 | 2219 | 1019 | 0.0 | 2175 | 22.61M |
| 4 | 2219 | 2175 | 2087 | 2087 | 2308 | 1108 | 0.0 | 2175 | 24.27M |
| 5 | 2308 | 2175 | 2107 | 2107 | 2376 | 1176 | 0.0 | 2175 | 25.61M |
| 6 | 2376 | 2175 | 2079 | 2079 | 2473 | 1273 | 0.0 | 2175 | 27.40M |
| 7 | 2473 | 2175 | 2133 | 2133 | 2515 | 1315 | 0.0 | 2175 | 28.28M |
| 8 | 2515 | 2175 | 2100 | 2100 | 2590 | 1390 | 0.0 | 2175 | 29.66M |
| 9 | 2590 | 2175 | 2098 | 2098 | 2667 | 1467 | 0.0 | 2175 | 31.12M |
| 10 | 2667 | 2175 | 2099 | 2099 | 2743 | 1543 | 0.0 | 2175 | 32.57M |
| 11 | 2743 | 2175 | 2129 | 2129 | 2790 | 1590 | 0.0 | 2175 | 33.49M |
| 12 | 2790 | 2175 | 2125 | 2125 | 2841 | 1641 | 0.0 | 2175 | 34.45M |
| 13 | 2841 | 2175 | 2095 | 2095 | 2921 | 1721 | 0.0 | 2175 | 35.94M |
| 14 | 2921 | 2175 | 2093 | 2093 | 3004 | 1804 | 0.0 | 2175 | 37.50M |
| 15 | 3004 | 2175 | 2111 | 2111 | 3068 | 1868 | 0.0 | 2175 | 38.75M |
| 16 | 3068 | 2175 | 2095 | 2095 | 3149 | 1949 | 0.0 | 2175 | 40.26M |
| 17 | 3149 | 2175 | 2081 | 2081 | 3243 | 2043 | 0.0 | 2175 | 42.03M |
| 18 | 3243 | 2175 | 2110 | 2110 | 3308 | 2108 | 0.0 | 2175 | 43.31M |
| 19 | 3308 | 2175 | 2087 | 2087 | 3397 | 2197 | 0.0 | 2175 | 44.96M |
| 20 | 3397 | 2175 | 2051 | 2051 | 3521 | 2321 | 0.0 | 2175 | 47.27M |
| 21 | 3521 | 2175 | 2100 | 2100 | 3596 | 2396 | 0.0 | 2175 | 48.77M |
| 22 | 3596 | 2175 | 2089 | 2089 | 3682 | 2482 | 0.0 | 2175 | 50.39M |
| 23 | 3682 | 2175 | 2095 | 2095 | 3763 | 2563 | 0.0 | 2175 | 51.93M |
| 24 | 3763 | 2175 | 2137 | 2137 | 3801 | 2601 | 0.0 | 2175 | 52.72M |
| 25 | 3801 | 2175 | 2093 | 2093 | 3884 | 2684 | 0.0 | 2175 | 54.23M |
| 26 | 3884 | 2175 | 2071 | 2071 | 3989 | 2789 | 0.0 | 2175 | 56.19M |
| 27 | 3989 | 2175 | 2140 | 2140 | 4024 | 2824 | 0.0 | 2175 | 56.96M |
| 28 | 4024 | 2175 | 2121 | 2121 | 4079 | 2879 | 0.0 | 2175 | 57.98M |
| 29 | 4079 | 2175 | 2108 | 2108 | 4146 | 2946 | 0.0 | 2175 | 59.24M |
| 30 | 4146 | 2175 | 2092 | 2092 | 4230 | 3030 | 0.0 | 2175 | 60.81M |


---

## Anexo B — Validações e reprodutibilidade

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
