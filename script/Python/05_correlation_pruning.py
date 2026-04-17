"""
Step A — Correlation-based pruning
- Carica le 31 feature LOGO-selected
- Matrice di correlazione su TRAIN
- Pruning greedy: ordina per importanza LOGO-CV (desc),
  per ogni feature rimuove quelle successive con |ρ| > soglia
- Output: corr_matrix.png, corr_pruned_features.txt, corr_pruning_report.csv
"""

import pandas as pd
import numpy as np
from sklearn.impute import SimpleImputer
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE   = "TRAIN_FEATURES.csv"
LOGO_FILE    = "logo_selected_features.txt"
LOGO_IMP_FILE= "logo_feature_importance.csv"
OUT_FEATS    = "corr_pruned_features.txt"
OUT_REPORT   = "corr_pruning_report.csv"
CORR_THRESH  = 0.90   # |ρ| > soglia → ridondante
# ──────────────────────────────────────────────────────────────────────────────

# ── Carica feature LOGO-selected ──────────────────────────────────────────────
with open(LOGO_FILE) as f:
    logo_feats = [l.strip() for l in f if l.strip() and not l.startswith("#")]
print(f"Feature LOGO-selected in input: {len(logo_feats)}")

# ── Carica ranking importanza da LOGO-CV ──────────────────────────────────────
imp_df = pd.read_csv(LOGO_IMP_FILE, sep=";")
# Mantieni solo le feature LOGO-selected, ordinate per importanza decrescente
imp_df = imp_df[imp_df["Feature"].isin(logo_feats)].sort_values(
    "MeanImportance", ascending=False
).reset_index(drop=True)
features_ranked = imp_df["Feature"].tolist()

# ── Carica training set e calcola correlazione ────────────────────────────────
df    = pd.read_csv(TRAIN_FILE, sep=";")
X_raw = df[features_ranked].values
X     = SimpleImputer(strategy="median").fit_transform(X_raw)

corr_matrix = pd.DataFrame(
    np.corrcoef(X.T),
    index=features_ranked,
    columns=features_ranked
)

# ── Correlation pruning greedy ────────────────────────────────────────────────
# Scorre le feature in ordine di importanza (dalla più alla meno importante).
# Tiene una feature se non è troppo correlata (|ρ| > soglia) con nessuna
# di quelle già tenute. In questo modo si preservano sempre le più importanti.
kept    = []
removed = []
reason  = {}   # feature → (correlata con, valore ρ)

for feat in features_ranked:
    if not kept:
        kept.append(feat)
        continue
    corrs = corr_matrix.loc[feat, kept].abs()
    max_corr = corrs.max()
    if max_corr <= CORR_THRESH:
        kept.append(feat)
    else:
        corr_partner = corrs.idxmax()
        removed.append(feat)
        reason[feat] = (corr_partner, round(corr_matrix.loc[feat, corr_partner], 4))

print(f"\nSoglia correlazione: |ρ| > {CORR_THRESH}")
print(f"Feature mantenute: {len(kept)}")
print(f"Feature rimosse:   {len(removed)}")

# ── Report ────────────────────────────────────────────────────────────────────
print(f"\n{'':=<60}")
print(f"  FEATURE MANTENUTE ({len(kept)})")
print(f"{'':=<60}")
for i, feat in enumerate(kept):
    imp = imp_df[imp_df["Feature"]==feat]["MeanImportance"].values[0]
    print(f"  {i+1:>2}. {feat:<15}  imp={imp:.5f}")

print(f"\n  FEATURE RIMOSSE ({len(removed)}) — troppo correlate con una più importante:")
for feat in removed:
    partner, rho = reason[feat]
    imp = imp_df[imp_df["Feature"]==feat]["MeanImportance"].values[0]
    print(f"  {feat:<15}  imp={imp:.5f}  |ρ|={rho:.3f}  con {partner}")

# ── Plot matrice di correlazione (feature mantenute) ─────────────────────────
corr_kept = corr_matrix.loc[kept, kept]
n = len(kept)
fig, ax = plt.subplots(figsize=(max(8, n*0.5), max(7, n*0.45)))
mask = np.triu(np.ones_like(corr_kept, dtype=bool), k=1)
sns.heatmap(corr_kept, mask=mask, annot=n<=20, fmt=".2f",
            cmap="RdBu_r", vmin=-1, vmax=1, center=0,
            linewidths=0.4, ax=ax,
            annot_kws={"size": 7})
ax.set_title(f"Correlazione — {n} feature post-pruning (|ρ|≤{CORR_THRESH})", fontsize=12)
plt.tight_layout()
plt.savefig("corr_matrix_kept.png", dpi=150)
plt.close()
print(f"\n✓  corr_matrix_kept.png")

# Plot completo (tutte le 31, con evidenza delle rimosse)
fig2, ax2 = plt.subplots(figsize=(max(10, len(features_ranked)*0.45),
                                   max(9, len(features_ranked)*0.40)))
mask2 = np.triu(np.ones_like(corr_matrix, dtype=bool), k=1)
sns.heatmap(corr_matrix, mask=mask2,
            cmap="RdBu_r", vmin=-1, vmax=1, center=0,
            linewidths=0.3, ax=ax2, annot=False)
ax2.set_title(f"Correlazione — tutte le 31 feature LOGO-selected", fontsize=11)
plt.tight_layout()
plt.savefig("corr_matrix_full.png", dpi=150)
plt.close()
print(f"✓  corr_matrix_full.png")

# ── Salva report CSV ──────────────────────────────────────────────────────────
rows = []
for feat in features_ranked:
    imp = imp_df[imp_df["Feature"]==feat]["MeanImportance"].values[0]
    if feat in kept:
        rows.append({"Feature": feat, "Status": "Kept",
                     "MeanImportance": imp, "RemovedDueTo": "", "MaxCorr": ""})
    else:
        partner, rho = reason[feat]
        rows.append({"Feature": feat, "Status": "Removed",
                     "MeanImportance": imp, "RemovedDueTo": partner, "MaxCorr": rho})

report_df = pd.DataFrame(rows)
report_df.to_csv(OUT_REPORT, sep=";", index=False)
print(f"✓  {OUT_REPORT}")

# ── Salva lista feature mantenute ─────────────────────────────────────────────
with open(OUT_FEATS, "w") as f:
    f.write(f"# Correlation pruning — soglia |ρ|={CORR_THRESH}\n")
    f.write(f"# Input: {len(logo_feats)} feature  →  Output: {len(kept)} feature\n\n")
    for feat in kept:
        f.write(feat + "\n")
print(f"✓  {OUT_FEATS}")
