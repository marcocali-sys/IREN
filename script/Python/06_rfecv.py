"""
Step C — RFECV con LOGO-CV
- Carica le feature post correlation-pruning
- Recursive Feature Elimination con Cross-Validation
- CV: LeaveOneGroupOut (gruppi = Sample.ID)
- Base estimator: RandomForestClassifier
- Trova il numero ottimale di feature massimizzando balanced_accuracy
- Output: rfecv_results.png, rfecv_selected_features.txt, rfecv_report.csv
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.feature_selection import RFECV
from sklearn.impute import SimpleImputer
from sklearn.model_selection import LeaveOneGroupOut
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE  = "TRAIN_FEATURES.csv"
INPUT_FEATS = "corr_pruned_features.txt"
OUT_FEATS   = "rfecv_selected_features.txt"
OUT_REPORT  = "rfecv_report.csv"
OUT_PLOT    = "rfecv_results.png"
RANDOM_SEED = 42
N_TREES     = 300
SCORING     = "balanced_accuracy"   # robusto con classi sbilanciate
MIN_FEATS   = 3
# ──────────────────────────────────────────────────────────────────────────────

# ── Carica feature post-pruning ───────────────────────────────────────────────
with open(INPUT_FEATS) as f:
    feats = [l.strip() for l in f if l.strip() and not l.startswith("#")]
print(f"Feature in input (post correlation pruning): {len(feats)}")

# ── Carica training set ───────────────────────────────────────────────────────
df     = pd.read_csv(TRAIN_FILE, sep=";")
groups = df["Sample.ID"].values
y      = df["Classe2"].values
X_raw  = df[feats].values

X = SimpleImputer(strategy="median").fit_transform(X_raw)
print(f"Training set: {X.shape[0]} campioni, {X.shape[1]} feature")
print(f"Gruppi LOGO: {len(np.unique(groups))} fold")

# ── RFECV ─────────────────────────────────────────────────────────────────────
rf = RandomForestClassifier(
    n_estimators=N_TREES,
    max_features="sqrt",
    class_weight="balanced",
    n_jobs=-1,
    random_state=RANDOM_SEED
)

logo = LeaveOneGroupOut()

selector = RFECV(
    estimator=rf,
    step=1,
    cv=logo,
    scoring=SCORING,
    min_features_to_select=MIN_FEATS,
    n_jobs=-1
)

print(f"\nAvvio RFECV (scoring={SCORING}, step=1)...\n")
selector.fit(X, y, groups=groups)

n_optimal = selector.n_features_
print(f"Numero ottimale di feature: {n_optimal}")
print(f"Balanced accuracy media al n_ottimale: "
      f"{selector.cv_results_['mean_test_score'][n_optimal-MIN_FEATS]:.4f}")

# ── Risultati per numero di feature ───────────────────────────────────────────
mean_scores = selector.cv_results_["mean_test_score"]
std_scores  = selector.cv_results_["std_test_score"]
n_range     = np.arange(MIN_FEATS, len(feats)+1)

# ── Feature selezionate ───────────────────────────────────────────────────────
selected_mask   = selector.support_
selected_feats  = [f for f, s in zip(feats, selected_mask) if s]
ranking         = selector.ranking_

report_df = pd.DataFrame({
    "Feature": feats,
    "Ranking": ranking,
    "Selected": selected_mask
}).sort_values(["Selected", "Ranking"], ascending=[False, True])

# ── Report console ─────────────────────────────────────────────────────────────
print(f"\n{'':=<55}")
print(f"  RFECV — Feature selezionate ({n_optimal})")
print(f"{'':=<55}")
for _, row in report_df[report_df["Selected"]].iterrows():
    print(f"  rank={int(row['Ranking'])}  {row['Feature']}")

print(f"\n  Feature escluse da RFECV ({(~selected_mask).sum()}):")
for _, row in report_df[~report_df["Selected"]].iterrows():
    print(f"  rank={int(row['Ranking'])}  {row['Feature']}")

# ── Plot ───────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(10, 5))

ax.plot(n_range, mean_scores, "o-", color="#4878CF",
        linewidth=2, markersize=5, label="Balanced accuracy (media LOGO)")
ax.fill_between(n_range,
                mean_scores - std_scores,
                mean_scores + std_scores,
                alpha=0.18, color="#4878CF", label="± std")
ax.axvline(n_optimal, color="#D65F5F", linestyle="--", linewidth=1.5,
           label=f"Ottimale: {n_optimal} feature")
ax.axhline(mean_scores[n_optimal - MIN_FEATS], color="#D65F5F",
           linestyle=":", linewidth=1, alpha=0.7)

ax.set_xlabel("Numero di feature", fontsize=12)
ax.set_ylabel(f"Balanced accuracy (LOGO-CV)", fontsize=12)
ax.set_title("RFECV — Selezione numero ottimale di feature\nELLONA/IREN", fontsize=13)
ax.set_xticks(n_range)
ax.legend(fontsize=10)
ax.grid(alpha=0.3)

# Annota il punto ottimale
opt_score = mean_scores[n_optimal - MIN_FEATS]
ax.annotate(f"  {n_optimal} feat\n  BA={opt_score:.3f}",
            xy=(n_optimal, opt_score),
            xytext=(n_optimal + 0.8, opt_score - 0.04),
            fontsize=9, color="#D65F5F",
            arrowprops=dict(arrowstyle="->", color="#D65F5F", lw=1.2))

plt.tight_layout()
plt.savefig(OUT_PLOT, dpi=150)
plt.close()
print(f"\n✓  {OUT_PLOT}")

# ── Salva ─────────────────────────────────────────────────────────────────────
report_df.to_csv(OUT_REPORT, sep=";", index=False)

with open(OUT_FEATS, "w") as f:
    f.write(f"# RFECV — {n_optimal} feature selezionate\n")
    f.write(f"# Scoring: {SCORING} | CV: LOGO (gruppi=Sample.ID)\n")
    f.write(f"# Balanced accuracy ottimale: "
            f"{mean_scores[n_optimal-MIN_FEATS]:.4f} ± "
            f"{std_scores[n_optimal-MIN_FEATS]:.4f}\n\n")
    for feat in selected_feats:
        f.write(feat + "\n")

print(f"✓  {OUT_REPORT}")
print(f"✓  {OUT_FEATS}")

# Salva anche la curva completa
curve_df = pd.DataFrame({
    "N_features":    n_range,
    "MeanBA":        mean_scores,
    "StdBA":         std_scores
})
curve_df.to_csv("rfecv_curve.csv", sep=";", index=False)
print(f"✓  rfecv_curve.csv")
