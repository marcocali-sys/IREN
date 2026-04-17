"""
PCA Interattiva — ELLONA/IREN
Input:  data/processed/TRAIN_FEATURES.csv + output/06_rfecv/rfecv_selected_features.txt
Output: output/04_pca/pca_3d_interactive.html
        output/04_pca/pca_2d_interactive.html
        output/04_pca/pca_loadings_interactive.html
"""

import os
import pandas as pd
import numpy as np
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots

# ── Parametri ──────────────────────────────────────────────────────────────────
TRAIN_FILE = "data/processed/TRAIN_FEATURES.csv"
FEAT_FILE  = "output/06_rfecv/rfecv_selected_features.txt"
OUT_DIR    = "output/04_pca"

os.makedirs(OUT_DIR, exist_ok=True)

CLASS_COLORS = {
    "ARIA":      "#4878CF",
    "BIOFILTRO": "#55A868",
    "BIOGAS":    "#C44E52",
    "FORSU":     "#8172B2",
    "PERCOLATO": "#CCB974",
}
CLASS_SYMBOLS_3D = {
    "ARIA": "circle", "BIOFILTRO": "square", "BIOGAS": "diamond",
    "FORSU": "cross", "PERCOLATO": "circle-open"
}
# ──────────────────────────────────────────────────────────────────────────────

# ── Carica feature selezionate ─────────────────────────────────────────────────
with open(FEAT_FILE) as f:
    selected = [l.strip() for l in f if l.strip() and not l.startswith("#")]
print(f"Feature selezionate: {len(selected)}")

# ── Carica e prepara dati ─────────────────────────────────────────────────────
df    = pd.read_csv(TRAIN_FILE, sep=";")
y     = df["Classe2"].values
sids  = df["Sample.ID"].values
X_raw = df[selected].values

X = SimpleImputer(strategy="median").fit_transform(X_raw)
X = StandardScaler().fit_transform(X)

# ── PCA ───────────────────────────────────────────────────────────────────────
pca      = PCA(random_state=42)
scores   = pca.fit_transform(X)
exp_var  = pca.explained_variance_ratio_ * 100
loadings = pca.components_

print(f"PC1: {exp_var[0]:.1f}%  |  PC2: {exp_var[1]:.1f}%  |  PC3: {exp_var[2]:.1f}%")

# ── Hover text ────────────────────────────────────────────────────────────────
hover = [
    f"<b>{cls}</b><br>Sample.ID: {sid}<br>"
    f"PC1: {s1:.2f}<br>PC2: {s2:.2f}<br>PC3: {s3:.2f}"
    for cls, sid, s1, s2, s3 in zip(y, sids, scores[:,0], scores[:,1], scores[:,2])
]

# ══════════════════════════════════════════════════════════════════════════════
# PLOT 1: 3D interattivo (PC1, PC2, PC3)
# ══════════════════════════════════════════════════════════════════════════════
fig3d = go.Figure()

for cls in sorted(CLASS_COLORS.keys()):
    mask = y == cls
    fig3d.add_trace(go.Scatter3d(
        x=scores[mask, 0],
        y=scores[mask, 1],
        z=scores[mask, 2],
        mode="markers",
        name=f"{cls} (n={mask.sum()})",
        marker=dict(
            size=6,
            color=CLASS_COLORS[cls],
            symbol=CLASS_SYMBOLS_3D[cls],
            opacity=0.85,
            line=dict(color="white", width=0.5)
        ),
        text=[hover[i] for i in np.where(mask)[0]],
        hovertemplate="%{text}<extra></extra>"
    ))

fig3d.update_layout(
    title=dict(
        text="<b>PCA 3D — ELLONA/IREN</b><br>"
             f"<sup>PC1={exp_var[0]:.1f}%  PC2={exp_var[1]:.1f}%  PC3={exp_var[2]:.1f}%  "
             f"[totale {exp_var[0]+exp_var[1]+exp_var[2]:.1f}%]</sup>",
        x=0.5
    ),
    scene=dict(
        xaxis_title=f"PC1 ({exp_var[0]:.1f}%)",
        yaxis_title=f"PC2 ({exp_var[1]:.1f}%)",
        zaxis_title=f"PC3 ({exp_var[2]:.1f}%)",
        xaxis=dict(backgroundcolor="#f8f8f8", gridcolor="white"),
        yaxis=dict(backgroundcolor="#f0f0f0", gridcolor="white"),
        zaxis=dict(backgroundcolor="#e8e8e8", gridcolor="white"),
        camera=dict(eye=dict(x=1.5, y=1.5, z=1.0))
    ),
    legend=dict(title="Classe", itemsizing="constant", font=dict(size=12)),
    margin=dict(l=0, r=0, t=80, b=0),
    width=1000, height=750,
    paper_bgcolor="white"
)

fig3d.write_html(os.path.join(OUT_DIR, "pca_3d_interactive.html"),
                 include_plotlyjs="cdn",
                 full_html=True)
print("✓  pca_3d_interactive.html")

# ══════════════════════════════════════════════════════════════════════════════
# PLOT 2: 2D interattivo con scree — dashboard in un unico HTML
# ══════════════════════════════════════════════════════════════════════════════
fig2d = make_subplots(
    rows=1, cols=2,
    column_widths=[0.72, 0.28],
    subplot_titles=[
        f"PC1 ({exp_var[0]:.1f}%) vs PC2 ({exp_var[1]:.1f}%)",
        "Varianza spiegata"
    ]
)

# Scatter PC1 vs PC2
for cls in sorted(CLASS_COLORS.keys()):
    mask = y == cls
    fig2d.add_trace(go.Scatter(
        x=scores[mask, 0],
        y=scores[mask, 1],
        mode="markers",
        name=f"{cls} (n={mask.sum()})",
        marker=dict(
            size=9,
            color=CLASS_COLORS[cls],
            opacity=0.85,
            line=dict(color="white", width=0.8)
        ),
        text=[hover[i] for i in np.where(mask)[0]],
        hovertemplate="%{text}<extra></extra>"
    ), row=1, col=1)

# Linee di riferimento
fig2d.add_hline(y=0, line=dict(color="gray", dash="dash", width=0.8), row=1, col=1)
fig2d.add_vline(x=0, line=dict(color="gray", dash="dash", width=0.8), row=1, col=1)

# Scree bar
n_show = min(10, len(exp_var))
fig2d.add_trace(go.Bar(
    x=[f"PC{i+1}" for i in range(n_show)],
    y=exp_var[:n_show],
    marker_color=[CLASS_COLORS["ARIA"]] + ["#BDBDBD"] * (n_show - 1),
    name="Var. spiegata",
    showlegend=False,
    text=[f"{v:.1f}%" for v in exp_var[:n_show]],
    textposition="outside",
    textfont=dict(size=9)
), row=1, col=2)

fig2d.update_layout(
    title=dict(
        text="<b>PCA 2D — ELLONA/IREN</b>",
        x=0.5, font=dict(size=16)
    ),
    legend=dict(title="Classe", itemsizing="constant"),
    width=1200, height=600,
    paper_bgcolor="white",
    plot_bgcolor="#fafafa"
)
fig2d.update_xaxes(title_text=f"PC1 ({exp_var[0]:.1f}%)", row=1, col=1, zeroline=False)
fig2d.update_yaxes(title_text=f"PC2 ({exp_var[1]:.1f}%)", row=1, col=1, zeroline=False)
fig2d.update_xaxes(title_text="Componente", row=1, col=2)
fig2d.update_yaxes(title_text="Varianza (%)", row=1, col=2)

fig2d.write_html(os.path.join(OUT_DIR, "pca_2d_interactive.html"),
                 include_plotlyjs="cdn",
                 full_html=True)
print("✓  pca_2d_interactive.html")

# ══════════════════════════════════════════════════════════════════════════════
# PLOT 3: Loadings interattivo (biplot feature)
# ══════════════════════════════════════════════════════════════════════════════
load1   = loadings[0]
load2   = loadings[1]
contrib = np.sqrt(load1**2 + load2**2)
top_idx = np.argsort(contrib)[::-1]

fig_load = go.Figure()

# Cerchio unitario
theta = np.linspace(0, 2*np.pi, 300)
fig_load.add_trace(go.Scatter(
    x=np.cos(theta), y=np.sin(theta),
    mode="lines",
    line=dict(color="gray", dash="dash", width=1),
    showlegend=False, hoverinfo="skip"
))

# Frecce + label per top 15
for i in top_idx:
    fig_load.add_annotation(
        x=load1[i], y=load2[i],
        ax=0, ay=0,
        xref="x", yref="y",
        axref="x", ayref="y",
        showarrow=True,
        arrowhead=2, arrowsize=1.2,
        arrowcolor=CLASS_COLORS["ARIA"],
        arrowwidth=1.8
    )
    fig_load.add_trace(go.Scatter(
        x=[load1[i] * 1.12],
        y=[load2[i] * 1.12],
        mode="text",
        text=[selected[i]],
        textfont=dict(size=10, color="#222222"),
        showlegend=False,
        hoverinfo="skip"
    ))

fig_load.update_layout(
    title=dict(text=f"<b>Cerchio delle correlazioni — {len(selected)} feature RFECV</b>", x=0.5),
    xaxis=dict(title=f"PC1 ({exp_var[0]:.1f}%)", range=[-1.3, 1.3],
               zeroline=True, zerolinecolor="gray", zerolinewidth=0.8,
               scaleanchor="y"),
    yaxis=dict(title=f"PC2 ({exp_var[1]:.1f}%)", range=[-1.3, 1.3],
               zeroline=True, zerolinecolor="gray", zerolinewidth=0.8),
    width=750, height=750,
    paper_bgcolor="white", plot_bgcolor="#fafafa"
)

fig_load.write_html(os.path.join(OUT_DIR, "pca_loadings_interactive.html"),
                    include_plotlyjs="cdn",
                    full_html=True)
print("✓  pca_loadings_interactive.html")
