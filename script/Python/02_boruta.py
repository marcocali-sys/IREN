"""
Boruta feature selection — ELLONA/IREN
- Input:  TRAIN_FEATURES.csv
- Output: boruta_results.csv  (status per ogni feature)
          boruta_selected_features.txt  (lista feature confermate)
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from boruta import BorutaPy

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE    = "TRAIN_FEATURES.csv"
RESULTS_FILE  = "boruta_results.csv"
SELECTED_FILE = "boruta_selected_features.txt"
RANDOM_SEED   = 42
N_ESTIMATORS  = 500    # alberi nel RF interno a Boruta
MAX_ITER      = 100    # iterazioni massime Boruta
ALPHA         = 0.05   # soglia significatività
PERC          = 100    # percentile shadow (100 = max shadow, come originale)
# ──────────────────────────────────────────────────────────────────────────────

# ── Colonne da escludere ───────────────────────────────────────────────────────
META_COLS = [
    "Data.analisi", "Classe", "Classe2", "Diluizione", "Cod",
    "Step1", "Step2", "Step3", "Sample.ID", "Sample.number",
    "Datetime_inizio", "Datetime_fine"
]
PID_COLS = ["D3", "N3"]   # PID = 0 ovunque, da escludere a priori

# ── Carica dati ───────────────────────────────────────────────────────────────
df = pd.read_csv(TRAIN_FILE, sep=";")
print(f"Training set caricato: {df.shape[0]} campioni, {df.shape[1]} colonne")

y = df["Classe2"].values
feature_cols = [c for c in df.columns if c not in META_COLS + PID_COLS]
X_raw = df[feature_cols].values

print(f"Feature iniziali: {len(feature_cols)}  (escluse meta + PID)")
print(f"NA presenti:      {np.isnan(X_raw).sum()} valori")

# ── Imputazione NA (mediana per colonna) ──────────────────────────────────────
imputer = SimpleImputer(strategy="median")
X = imputer.fit_transform(X_raw)

# ── Boruta ────────────────────────────────────────────────────────────────────
rf = RandomForestClassifier(
    n_estimators=N_ESTIMATORS,
    max_features="sqrt",
    n_jobs=-1,
    random_state=RANDOM_SEED
)

selector = BorutaPy(
    estimator=rf,
    n_estimators="auto",
    max_iter=MAX_ITER,
    alpha=ALPHA,
    perc=PERC,
    verbose=2,
    random_state=RANDOM_SEED
)

print(f"\nAvvio Boruta (max_iter={MAX_ITER}, alpha={ALPHA})...\n")
selector.fit(X, y)

# ── Raccolta risultati ─────────────────────────────────────────────────────────
status_map = {True: "Confirmed", False: "Rejected"}
tentative   = ~selector.support_ & ~selector.support_weak_
status = []
for i in range(len(feature_cols)):
    if selector.support_[i]:
        status.append("Confirmed")
    elif tentative[i]:
        status.append("Tentative")
    else:
        status.append("Rejected")

results_df = pd.DataFrame({
    "Feature": feature_cols,
    "Status":  status,
    "Ranking": selector.ranking_,
}).sort_values(["Status", "Ranking"])

# ── Report console ─────────────────────────────────────────────────────────────
for s in ["Confirmed", "Tentative", "Rejected"]:
    subset = results_df[results_df["Status"] == s]
    print(f"\n{s.upper()} ({len(subset)}):")
    if s != "Rejected":
        for _, row in subset.iterrows():
            print(f"  {row['Feature']:<12}  rank={int(row['Ranking'])}")
    else:
        print(f"  {len(subset)} feature rifiutate")

confirmed = results_df[results_df["Status"] == "Confirmed"]["Feature"].tolist()
tentative_list = results_df[results_df["Status"] == "Tentative"]["Feature"].tolist()

print(f"\n{'':=<50}")
print(f"  Confirmed:  {len(confirmed)}")
print(f"  Tentative:  {len(tentative_list)}")
print(f"  Rejected:   {len(results_df[results_df['Status']=='Rejected'])}")
print(f"{'':=<50}")

# ── Salva ─────────────────────────────────────────────────────────────────────
results_df.to_csv(RESULTS_FILE, sep=";", index=False)

with open(SELECTED_FILE, "w") as f:
    f.write("# Boruta — Feature Confirmed\n")
    for feat in confirmed:
        f.write(feat + "\n")
    if tentative_list:
        f.write("\n# Tentative (valuta manualmente)\n")
        for feat in tentative_list:
            f.write(feat + "\n")

print(f"\n✓  Salvato: {RESULTS_FILE}")
print(f"✓  Salvato: {SELECTED_FILE}")
