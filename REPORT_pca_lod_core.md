# Rilevamento di anomalie olfattive con PCA
## Perché il LOD su PC₁ supera le soglie sui segnali grezzi

**Progetto:** ELLONA — Electronic Nose per monitoraggio odori  
**Impianto:** Trattamento acque reflue, Nord Italia  
**Dataset:** marzo–dicembre 2025 (9 mesi, 2 069 099 campioni a 10s)  
**Autore:** Marco Calì — PoliMi, Aprile 2026

---

## 1. Il sensore MOX come trasduttore non selettivo

Un sensore a ossido metallico (MOX) misura la variazione di resistenza elettrica del suo strato sensibile quando viene esposto a gas. Il problema fondamentale è che questa resistenza **non è selettiva**: cambia in risposta a qualunque stimolo chimico o fisico presente nell'aria, non solo agli odori target.

Il segnale grezzo di un singolo sensore cmos_i è quindi una miscela di contributi:

$$x_i(t) = \underbrace{f_i^{odore}(t)}_{\text{ciò che vogliamo}} + \underbrace{f_i^T(t) + f_i^{RH}(t)}_{\text{confounders ambientali}} + \underbrace{f_i^{aging}(t)}_{\text{deriva sensore}} + \underbrace{\varepsilon_i(t)}_{\text{rumore}}$$

In un impianto di trattamento acque reflue in Italia, l'intervallo termico stagionale è tipicamente 5–35 °C e l'umidità relativa 40–95 %. Ciascuno di questi range produce variazioni di resistenza nei sensori MOX **dello stesso ordine di grandezza** della risposta agli odori target. Definire una soglia di allerta sul segnale grezzo $x_i(t)$ significa esporre il rilevatore a una quantità enorma di falsi positivi stagionali.

---

## 2. Il fallimento della soglia sul segnale grezzo

### 2.1 Il problema della dimensionalità

Il sistema ELLONA monta quattro sensori (cmos1–cmos4). Per costruire un LOD sul grezzo servono **quattro soglie separate**, una per sensore. Ma un odore causa una risposta *correlata* su tutti e quattro: come si combinano i quattro risultati booleani in un'unica decisione?

- **AND logico**: l'evento scatta solo se tutti e quattro superano la soglia → alta specificità, bassa sensibilità (basta che un sensore non risponda per perdere l'evento)
- **OR logico**: l'evento scatta se almeno uno supera la soglia → alta sensibilità, molti falsi positivi
- **Soglia su media**: perde l'informazione differenziale tra i sensori

Nessuna di queste regole è ottimale perché tutte trattano i quattro sensori come ugualmente informativi e ignorano la struttura di correlazione del sistema.

### 2.2 Il problema dei confounders: evidenza empirica

Il confronto diretto tra LOD sui segnali grezzi e LOD su PC₁ — con la **stessa identica selezione di baseline** (IQR [P25,P75] su tutti i sensori) — produce i seguenti risultati sul dataset ELLONA (2 069 099 campioni, 9 mesi):

| Metodo | % eventi | r con T | FP esclusivi | FP / totale |
|---|---|---|---|---|
| cmos1 (grezzo) | 12.62% | **+0.508** | 12.32% | **97.6%** |
| cmos2 (grezzo) | 1.86% | −0.205 | 1.60% | 86.0% |
| cmos3 (grezzo) | 14.15% | −0.313 | 13.77% | **97.3%** |
| cmos4 (grezzo) | 0.32% | −0.366 | 0.32% | 100% |
| media z-norm. | 12.02% | −0.101 | 11.73% | **97.6%** |
| **PC₁** | **3.67%** | **+0.033** | **0.00%** | **—** |

*"FP esclusivi" = eventi rilevati dal metodo ma non confermati da PC₁.*

I risultati mostrano tre patologie distinte dei LOD sul grezzo:

**a) Tasso eventi gonfiato (97% falsi positivi)**  
cmos1 rileva il 12.62% di eventi, ma solo lo 0.31% coincide con gli eventi di PC₁. Il 97.6% degli eventi di cmos1 non è confermato da nessun'altra sorgente indipendente — sono falsi positivi. Stessa situazione per cmos3 (97.3%) e per la media z-normalizzata (97.6%).

**b) Correlazione con la temperatura**  
cmos1 ha correlazione di Pearson r = +0.508 tra tasso eventi settimanale e temperatura media settimanale. Questo significa che quasi metà della variazione del tasso di eventi di cmos1 nel tempo è spiegata dalla sola temperatura — non da odori. PC₁ ha r = +0.033, statisticamente indistinguibile da zero: i suoi eventi non dipendono dalla stagione termica.

**c) Inconsistenza tra sensori**  
I quattro sensori grezzi producono tassi di eventi completamente diversi (0.32%–14.15%) sullo stesso dataset, con la stessa metodologia. Non esiste una soglia "giusta" sul grezzo — ogni sensore risponde a stimoli fisici diversi (il range di cmos4 è 90 442 ± 29 011, quello di cmos3 è 152 ± 7) e non sono direttamente confrontabili.

Anche con il baseline globale (senza finestra settimanale, PCA inclusa) il tasso di eventi è del **13.27%** — un ulteriore indicatore che la varianza stagionale non rimossa dalla PCA gonfia i falsi positivi.

| Approccio baseline su PC₁ | % eventi |
|---|---|
| Globale (deriva non corretta) | 13.27% |
| Mensile | 6.48% |
| **Settimanale (ottimale)** | **3.67%** |
| Giornaliero (troppo adattivo) | 0.27% |

---

## 3. Il principio dell'array: sfruttare la struttura di correlazione

L'intuizione alla base di un electronic nose è che odori diversi producono **pattern diversi** sulla risposta dell'array. Temperatura e umidità, invece, producono uno spostamento **comune** su tutti i sensori (common-mode shift): tutti i sensori salgono o scendono proporzionalmente perché il meccanismo di trasporto dei gas cambia in modo non specifico.

Questa distinzione è sfruttabile matematicamente attraverso la **Principal Component Analysis (PCA)**.

### 3.1 La PCA come separatore di sorgenti

Dato il vettore dei quattro segnali z-normalizzati $\tilde{\mathbf{x}}(t) \in \mathbb{R}^4$, la PCA trova la decomposizione:

$$\tilde{\mathbf{x}}(t) = \sum_{k=1}^{4} s_k(t) \cdot \mathbf{p}_k$$

dove $\mathbf{p}_k$ sono i vettori di loading (autovettori della matrice di covarianza) e $s_k(t)$ sono gli score. I loading sono ordinati per varianza spiegata decrescente: PC₁ cattura la direzione di massima variabilità.

**Cosa finisce in PC₁:**  
La direzione di massima variabilità nel dataset ELLONA è quella che separa i pattern di risposta differenziale tra i sensori — ovvero la firma specifica degli odori target. 

**Cosa rimane fuori da PC₁:**  
Lo spostamento common-mode (T, RH) tende a proiettarsi sugli assi successivi (PC₂, PC₃) perché la PCA, avendo trovato in PC₁ la direzione di massima varianza differenziale, spinge la componente comune nelle dimensioni residue.

Il risultato è uno **scalare** $s_1(t) = $ PC₁$(t)$ che sintetizza la risposta dell'intero array in un singolo numero, calibrato sulla struttura di correlazione del sistema.

---

## 4. Evidenze empiriche nel dataset ELLONA

### 4.1 Il loading plot

I pesi con cui ciascun sensore contribuisce a PC₁ nel modello ELLONA sono:

| Sensore | Loading su PC₁ | Segno |
|---|---|---|
| cmos1 | +0.528 | positivo |
| cmos2 | +0.669 | positivo (dominante) |
| cmos3 | +0.401 | positivo |
| **cmos4** | **−0.336** | **negativo** |

Il fatto che cmos4 carichi **negativamente** mentre gli altri caricano positivamente è la firma di una risposta **differenziale**: PC₁ non è la media dei sensori, è un asse che sale quando cmos1/2/3 salgono e cmos4 scende (o viceversa). Nessun fenomeno puramente common-mode (temperatura, umidità) produce questo pattern — produrrebbe tutti i segni concordi. Solo una risposta chimica specifica, che interagisce diversamente con i materiali sensibili dei quattro sensori, genera questo profilo.

### 4.2 Correlazione con T e RH

Il plot `PC1_vs_TRH_correlation.png` (output ELLONA_08) mostra la relazione tra PC₁ e le variabili ambientali temperatura e umidità relativa misurate in situ. La decorrelazione di PC₁ da T e RH è la verifica empirica diretta del fatto che la PCA ha separato la risposta olfattiva dai confounders ambientali.

### 4.3 La variabilità stagionale in PC₁ è reale, non un artefatto

L'analisi rolling LOD ha mostrato che:

$$\sigma^2_{global} = \underbrace{\sigma^2_{noise}}_{\approx 0.19 \;\;(14\%)} + \underbrace{\sigma^2_{stagionale}}_{\approx 1.58 \;\;(89\%)}$$

σ_roll su qualsiasi finestra ≤ 30 giorni converge a ~0.44–0.54, mentre σ_global = 1.33. Il 89% della varianza totale di PC₁ non è visibile su scale settimanali o mensili — esiste solo guardando l'intero arco di 9 mesi.

Questa variabilità stagionale **non è un residuo di temperatura non rimosso dalla PCA**. Se fosse T/RH residua, sarebbe periodica e correlata con le stagioni astronomiche. Il dataset mostra invece un picco di eventi concentrato in **agosto–settembre**, coerente con il picco di attività biologica dell'impianto (metabolismo dei fanghi in estate) e non con il semplice calendario termico. La PCA ha quindi correttamente separato la variabilità olfattiva da quella termica: ciò che resta in PC₁ è un segnale di odore, non un artefatto.

---

## 5. La costruzione del LOD su PC₁

### 5.1 Selezione del baseline

Non tutti i campioni di PC₁ rappresentano condizioni normali: alcuni corrispondono già a eventi olfattivi. Usarli tutti per stimare μ e σ produrrebbe una LOD distorta.

La selezione del baseline utilizza un filtro IQR sui segnali MOX grezzi: vengono mantenuti solo i campioni in cui **tutti e quattro** i sensori ricadono nella banda [P25, P75] della propria distribuzione. Questo rimuove i picchi intensi lasciando le condizioni di fondo.

Con baseline **settimanale** (finestra 7 giorni scorrevole sulla selezione):

| Parametro | Valore |
|---|---|
| N campioni baseline | 341 820 / 2 069 099  (16.5%) |
| μ_BL | 0.0000 |
| σ_BL | 1.3292 |
| PC₁ spiegata nel baseline | 44.2% |

### 5.2 La soglia LOD

Con k = 3 (equivalente a 3σ, livello di confidenza ~99.7% su distribuzione normale):

$$\text{LOD}^- = \mu_{BL} - k \cdot \sigma_{BL} = -3.988$$

Solo il limite inferiore è operativo: la resistenza MOX **cala** in presenza di gas riducenti (odori tipici di impianti di trattamento). Un evento è definito come:

$$\text{evento}(t) \equiv \text{PC}_1(t) < \text{LOD}^-$$

Tasso eventi: **3.67%** dei 2 069 099 campioni.

### 5.3 Perché k = 3

Abbassare k aumenta la sensibilità ma anche i falsi positivi. L'analisi di sensibilità mostra che a k < 1.5 la differenza tra LOD fisso e rolling diventa rilevante (discordanza > 8%) e il tasso eventi supera il 20% — il rilevatore perde significato discriminante. k = 3 è il valore che garantisce:
- Meno del 5% di falsi positivi attesi su distribuzione normale
- Sensibilità sufficiente per eventi intensi (picchi a PC₁ < −50 in agosto)
- Robustezza alla scelta della finestra rolling

---

## 6. Il LOD rolling: correggere la deriva mantenendo la calibrazione

### 6.1 Il problema della deriva di μ

Il baseline μ_BL non è strettamente costante nel tempo: l'invecchiamento dei sensori, le variazioni stagionali di temperatura ambiente e la composizione dell'aria di fondo producono una deriva lenta. Se il LOD è costruito una volta sola su μ_global = 0, e il baseline reale a dicembre è μ_reale = −0.2, la soglia LOD⁻ = −3.99 è leggermente spostata rispetto alla condizione reale.

### 6.2 La soluzione: μ rolling + σ globale

$$\boxed{\text{LOD}(t) = \mu_{roll}(t) \pm k \cdot \sigma_{global}}$$

- **μ_roll(t)**: ricalcolato ogni giorno sull'ultima settimana con lo stesso filtro IQR → segue la deriva lenta
- **σ_global**: rimane fisso → calibrato sull'intera stagionalità

**Perché σ deve restare globale** è il punto critico. L'analisi con finestre 7d, 14d, 30d ha mostrato:

| Finestra | σ_roll | % di σ_global |
|---|---|---|
| 7d | 0.443 | 33% |
| 14d | 0.476 | 36% |
| 30d | 0.542 | 41% |
| **globale** | **1.329** | **100%** |

σ_roll non converge a σ_global nemmeno a 30 giorni perché, all'interno di qualsiasi finestra locale, la variabilità stagionale appare come un offset costante (catturata da μ_roll) e non come dispersione. Una finestra di 30 giorni vede solo il 41% della variabilità totale del sistema.

Usare σ_roll per la banda significherebbe costruire una soglia che considera normale solo la variabilità della settimana in corso — ignorerebbe che il sensore, nel corso dell'anno, attraversa regimi operativi con PC₁ sistematicamente diversi. Il risultato sarebbe un'esplosione di falsi positivi (23% eventi nella versione errata con σ_roll).

### 6.3 Risultati del LOD rolling

| Metrica | LOD fisso | Rolling 7d | Rolling 14d | Rolling 30d |
|---|---|---|---|---|
| % eventi | 3.67% | 3.36% | 3.24% | 3.33% |
| Concordanza con fisso | — | 98.5% | 98.6% | 98.9% |
| Solo LOD fisso | — | 0.90% | 0.89% | 0.74% |
| Solo LOD rolling | — | 0.59% | 0.46% | 0.40% |

La concordanza ≥ 98.5% per tutte le finestre conferma che la deriva di μ nel dataset ELLONA è contenuta (9 mesi). Il rolling LOD è lo strumento corretto per un deployment pluriennale.

---

## 7. Sintesi del percorso metodologico

```
Segnali grezzi cmos1–4
        │
        │  z-normalizzazione per canale
        │
        ▼
   Matrice X̃ (N×4)
        │
        │  PCA (addestrata sul baseline globale)
        │  → rimozione confounders common-mode (T, RH)
        │  → compressione 4D → 1D
        ▼
      PC₁(t)                       ← segnale olfattivo purificato
        │
        │  Selezione baseline IQR [P25,P75] su tutti i MOX
        │  → rimozione campioni con eventi attivi
        ▼
   Baseline PC₁_BL
        │
        │  μ_BL, σ_BL              ← statistiche del "normale"
        │
        │  [opzionale: μ rolling settimanale per correzione deriva]
        ▼
   LOD⁻ = μ_BL − k·σ_global       k = 3
        │
        ▼
   Evento(t)  ←→  PC₁(t) < LOD⁻   (3.67% dei campioni)
```

---

## 8. Conclusioni

La scelta di costruire il LOD su PC₁ invece che sui segnali grezzi si basa su tre argomenti convergenti:

**1. Riduzione della dimensionalità con preservazione dell'informazione**  
Quattro segnali correlati vengono compressi in uno score univoco che sintetizza la risposta dell'intero array secondo la sua struttura di covarianza. Non è una media arbitraria: è la proiezione sulla direzione di massima varianza differenziale, ovvero la direzione più informativa per discriminare tra condizioni normali e anomale.

**2. Decorrelazione dai confounders ambientali**  
La risposta common-mode di T e RH, che sposterebbe tutti i sensori nella stessa direzione, viene proiettata sulle componenti successive (PC₂, PC₃). PC₁ mantiene la risposta differenziale specifica agli odori. La verifica empirica è la scarsa correlazione di PC₁ con T e RH misurata nel dataset ELLONA, e il pattern di loading con cmos4 di segno opposto agli altri tre sensori.

**3. Calibrazione statistica robusta del LOD**  
σ_global cattura l'intera variabilità stagionale del sistema (89% della varianza totale di PC₁). Nessuna stima locale (finestre ≤ 30 giorni) può replicarla. Questo significa che la banda LOD = μ ± k·σ_global è calibrata su tutti i regimi operativi reali osservati, non solo su quello della settimana corrente. Il risultato è un rilevatore con comportamento consistente in ogni stagione.

---

---

## 9. Numeri chiave (da citare in tesi)

| Affermazione | Valore | Fonte |
|---|---|---|
| Tasso eventi LOD su PC₁ (k=3, baseline weekly) | **3.67%** | ELLONA_08 |
| Tasso eventi LOD su cmos1 grezzo (stesso baseline) | **12.62%** | ELLONA_12 |
| Falsi positivi di cmos1 non confermati da PC₁ | **97.6%** | ELLONA_12 |
| Correlazione r(cmos1 eventi, T) | **+0.508** | ELLONA_12 |
| Correlazione r(PC₁ eventi, T) | **+0.033** | ELLONA_12 |
| Varianza stagionale in σ_global di PC₁ | **89%** | ELLONA_11 |
| Concordanza LOD fisso vs rolling (k=3, 7d) | **98.5%** | ELLONA_11 |
| Loading cmos4 su PC₁ (segno opposto agli altri) | **−0.336** | ELLONA_08 |

---

*File di riferimento: `ELLONA_08_pca_baseline_lod.m`, `ELLONA_11_rolling_lod.m`, `ELLONA_12_raw_vs_pca_lod.m`, `ellona_rolling_lod.m`*  
*Output di riferimento: `output/event_detection/`, `output/rolling_lod/`, `output/raw_vs_pca/`*
