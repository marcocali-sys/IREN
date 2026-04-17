"""
PCA — ELLONA/IREN
Input:  data/processed/TRAIN_FEATURES.csv + output/06_rfecv/rfecv_selected_features.txt
Output: output/04_pca/pca_scores.png      (PC1 vs PC2, ellissi per classe)
        output/04_pca/pca_scree.png       (varianza spiegata)
        output/04_pca/pca_loadings.png    (contributo feature a PC1/PC2)
        output/04_pca/pca_3d.png          (PC1 vs PC2 vs PC3)
        output/04_pca/pca_results.csv     (scores + classe)
"""

import pandas as pd
import numpy as np
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import Ellipse
import matplotlib.transforms as transforms

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE    = "data/processed/TRAIN_FEATURES.csv"
FEAT_FILE     = "output/06_rfecv/rfecv_selected_features.txt"
OUT_DIR       = "output/04_pca"
RANDOM_SEED   = 42

CLASS_COLORS = {
    "ARIA":      "#4878CF",
    "BIOFILTRO": "#6ACC65",
    "BIOGAS":    "#D65F5F",
    "FORSU":     "#B47CC7",
    "PERCOLATO": "#C4AD66",
}
CLASS_MARKERS = {
    "ARIA": "o", "BIOFILTRO": "s", "BIOGAS": "^", "FORSU": "D", "PERCOLATO": "P"
}
# ──────────────────────────────────────────────────────────────────────────────

os.makedirs(OUT_DIR, exist_ok=True)

# ── Carica feature selezionate ─────────────────────────────────────────────────
with open(FEAT_FILE) as f:
    selected = [l.strip() for l in f if l.strip() and not l.startswith("#")]
print(f"Feature selezionate: {len(selected)}")

# ── Carica dati ───────────────────────────────────────────────────────────────
df     = pd.read_csv(TRAIN_FILE, sep=";")
y      = df["Classe2"].values
X_raw  = df[selected].values

# Imputa NA e standardizza
X = SimpleImputer(strategy="median").fit_transform(X_raw)
X = StandardScaler().fit_transform(X)

# ── PCA ───────────────────────────────────────────────────────────────────────
pca        = PCA(random_state=RANDOM_SEED)
scores     = pca.fit_transform(X)
exp_var    = pca.explained_variance_ratio_ * 100
cum_var    = np.cumsum(exp_var)
loadings   = pca.components_          # shape: (n_components, n_features)
n_comp_90  = np.argmax(cum_var >= 90) + 1

print(f"\nPC1: {exp_var[0]:.1f}%  |  PC2: {exp_var[1]:.1f}%  |  PC3: {exp_var[2]:.1f}%")
print(f"Componenti per 90% varianza: {n_comp_90}")

# ─────────────────────────────────────────────────────────────────────────────
# Helper: ellisse di confidenza (95%) per una classe
# ─────────────────────────────────────────────────────────────────────────────
def confidence_ellipse(x, y, ax, n_std=2.0, **kwargs):
    if len(x) < 3:
        return
    cov  = np.cov(x, y)
    pearson = cov[0, 1] / np.sqrt(cov[0, 0] * cov[1, 1])
    rx   = np.sqrt(1 + pearson)
    ry   = np.sqrt(1 - pearson)
    ell  = Ellipse((0, 0), width=rx * 2, height=ry * 2, **kwargs)
    sx   = np.sqrt(cov[0, 0]) * n_std
    sy   = np.sqrt(cov[1, 1]) * n_std
    t    = transforms.Affine2D().rotate_deg(45).scale(sx, sy).translate(np.mean(x), np.mean(y))
    ell.set_transform(t + ax.transData)
    ax.add_patch(ell)

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 1: Scree plot
# ─────────────────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(12, 4))

axes[0].bar(range(1, 11), exp_var[:10], color="#4878CF", alpha=0.8, edgecolor="white")
axes[0].set_xlabel("Componente principale")
axes[0].set_ylabel("Varianza spiegata (%)")
axes[0].set_title("Scree Plot")
axes[0].set_xticks(range(1, 11))
for i, v in enumerate(exp_var[:10]):
    axes[0].text(i+1, v+0.3, f"{v:.1f}%", ha="center", fontsize=8)

axes[1].plot(range(1, len(exp_var)+1), cum_var, "o-", color="#D65F5F", linewidth=1.5, markersize=4)
axes[1].axhline(90, color="gray", linestyle="--", linewidth=1, label="90%")
axes[1].axvline(n_comp_90, color="gray", linestyle="--", linewidth=1)
axes[1].set_xlabel("Numero di componenti")
axes[1].set_ylabel("Varianza cumulativa (%)")
axes[1].set_title("Varianza Cumulativa")
axes[1].legend()
axes[1].set_xlim(1, min(20, len(exp_var)))
axes[1].grid(alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_scree.png"), dpi=150)
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 2: PC1 vs PC2 con ellissi
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 7))

classes = sorted(CLASS_COLORS.keys())
for cls in classes:
    mask = y == cls
    if mask.sum() == 0:
        continue
    ax.scatter(scores[mask, 0], scores[mask, 1],
               c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
               s=70, alpha=0.85, edgecolors="white", linewidths=0.5,
               label=f"{cls} (n={mask.sum()})")
    confidence_ellipse(scores[mask, 0], scores[mask, 1], ax,
                       n_std=2.0,
                       edgecolor=CLASS_COLORS[cls],
                       facecolor=CLASS_COLORS[cls],
                       alpha=0.12, linewidth=1.5)

ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
ax.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=12)
ax.set_ylabel(f"PC2 ({exp_var[1]:.1f}%)", fontsize=12)
ax.set_title("PCA — ELLONA/IREN  (ellissi 95%)", fontsize=13)
ax.legend(loc="best", framealpha=0.9, fontsize=9)
ax.grid(alpha=0.2)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_scores.png"), dpi=150)
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 3: Loadings PC1 vs PC2 (biplot delle variabili)
# ─────────────────────────────────────────────────────────────────────────────
load1 = loadings[0]
load2 = loadings[1]

# Tutte le 11 feature selezionate
contrib = np.sqrt(load1**2 + load2**2)
top_idx = np.argsort(contrib)[::-1]

fig, ax = plt.subplots(figsize=(9, 7))
for i in top_idx:
    ax.annotate("", xy=(load1[i], load2[i]), xytext=(0, 0),
                arrowprops=dict(arrowstyle="->", color="#4878CF", lw=1.5))
    ax.text(load1[i] * 1.08, load2[i] * 1.08, selected[i],
            fontsize=8, ha="center", color="#222222")

circle = plt.Circle((0, 0), 1, fill=False, color="gray", linestyle="--", linewidth=0.8)
ax.add_patch(circle)
ax.set_xlim(-1.2, 1.2)
ax.set_ylim(-1.2, 1.2)
ax.axhline(0, color="gray", linewidth=0.5)
ax.axvline(0, color="gray", linewidth=0.5)
ax.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=12)
ax.set_ylabel(f"PC2 ({exp_var[1]:.1f}%)", fontsize=12)
ax.set_title(f"Loadings PCA — {len(selected)} feature selezionate (RFECV)", fontsize=13)
ax.set_aspect("equal")
ax.grid(alpha=0.2)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_loadings.png"), dpi=150)
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 4: PC1 vs PC2 vs PC3 (3D)
# ─────────────────────────────────────────────────────────────────────────────
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

fig = plt.figure(figsize=(10, 7))
ax3 = fig.add_subplot(111, projection="3d")

for cls in classes:
    mask = y == cls
    if mask.sum() == 0:
        continue
    ax3.scatter(scores[mask, 0], scores[mask, 1], scores[mask, 2],
                c=CLASS_COLORS[cls], marker=CLASS_MARKERS[cls],
                s=50, alpha=0.85, edgecolors="white", linewidths=0.3,
                label=f"{cls}")

ax3.set_xlabel(f"PC1 ({exp_var[0]:.1f}%)", fontsize=9)
ax3.set_ylabel(f"PC2 ({exp_var[1]:.1f}%)", fontsize=9)
ax3.set_zlabel(f"PC3 ({exp_var[2]:.1f}%)", fontsize=9)
ax3.set_title("PCA 3D — ELLONA/IREN", fontsize=12)
ax3.legend(loc="upper left", fontsize=8, framealpha=0.8)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, "pca_3d.png"), dpi=150)
plt.close()

# ─────────────────────────────────────────────────────────────────────────────
# Salva scores
# ─────────────────────────────────────────────────────────────────────────────
scores_df = pd.DataFrame(scores[:, :5],
                         columns=[f"PC{i+1}" for i in range(5)])
scores_df.insert(0, "Classe2",    y)
scores_df.insert(1, "Sample.ID",  df["Sample.ID"].values)
scores_df.to_csv(os.path.join(OUT_DIR, "pca_results.csv"), sep=";", index=False)

print(f"\n✓  {OUT_DIR}/pca_scree.png")
print(f"✓  {OUT_DIR}/pca_scores.png")
print(f"✓  {OUT_DIR}/pca_loadings.png")
print(f"✓  {OUT_DIR}/pca_3d.png")
print(f"✓  {OUT_DIR}/pca_results.csv")
