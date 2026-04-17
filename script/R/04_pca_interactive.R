# ==============================================================================
# PCA Interattiva — ELLONA/IREN
# Output: pca_3d_interactive.html / pca_2d_interactive.html (apri nel browser)
# ==============================================================================
# Richiede: install.packages(c("plotly","htmlwidgets"))
# ==============================================================================

library(plotly)
library(htmlwidgets)

setwd(normalizePath("~/Desktop/IREN"))

CLASS_COLORS <- c(
    ARIA      = "#4878CF",
    BIOFILTRO = "#55A868",
    BIOGAS    = "#C44E52",
    FORSU     = "#8172B2",
    PERCOLATO = "#CCB974"
)
CLASS_SYMBOLS_3D <- c(
    ARIA="circle", BIOFILTRO="square", BIOGAS="diamond",
    FORSU="cross", PERCOLATO="circle-open"
)

# ── Carica feature selezionate ─────────────────────────────────────────────────
lines_raw <- readLines("logo_selected_features.txt")
selected  <- lines_raw[!grepl("^#", lines_raw) & nchar(trimws(lines_raw)) > 0]
cat(sprintf("Feature selezionate: %d\n", length(selected)))

# ── Carica dati ───────────────────────────────────────────────────────────────
df  <- read.csv("TRAIN_FEATURES.csv", sep=";", stringsAsFactors=FALSE)
y   <- df$Classe2
sid <- df$Sample.ID
X   <- df[, selected, drop=FALSE]

# Imputa NA e standardizza
for (col in names(X))
    if (any(is.na(X[[col]])))
        X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm=TRUE)

X_scaled <- scale(X)

# ── PCA ───────────────────────────────────────────────────────────────────────
pca_res <- prcomp(X_scaled, center=FALSE, scale.=FALSE)
scores  <- as.data.frame(pca_res$x)
exp_var <- (pca_res$sdev^2 / sum(pca_res$sdev^2)) * 100
loadings_mat <- pca_res$rotation

cat(sprintf("PC1: %.1f%%  |  PC2: %.1f%%  |  PC3: %.1f%%\n",
            exp_var[1], exp_var[2], exp_var[3]))

# Hover text
hover_txt <- sprintf(
    "<b>%s</b><br>Sample.ID: %d<br>PC1: %.2f<br>PC2: %.2f<br>PC3: %.2f",
    y, sid, scores$PC1, scores$PC2, scores$PC3
)

classes <- sort(unique(y))

# ══════════════════════════════════════════════════════════════════════════════
# PLOT 1: 3D interattivo
# ══════════════════════════════════════════════════════════════════════════════
fig3d <- plot_ly()

for (cls in classes) {
    mask <- y == cls
    fig3d <- fig3d %>% add_trace(
        type   = "scatter3d",
        mode   = "markers",
        name   = sprintf("%s (n=%d)", cls, sum(mask)),
        x      = scores$PC1[mask],
        y      = scores$PC2[mask],
        z      = scores$PC3[mask],
        marker = list(
            size   = 6,
            color  = CLASS_COLORS[cls],
            symbol = CLASS_SYMBOLS_3D[cls],
            opacity = 0.85,
            line   = list(color="white", width=0.5)
        ),
        text      = hover_txt[mask],
        hovertemplate = "%{text}<extra></extra>"
    )
}

fig3d <- fig3d %>% layout(
    title = list(
        text = sprintf(
            "<b>PCA 3D — ELLONA/IREN</b><br><sup>PC1=%.1f%%  PC2=%.1f%%  PC3=%.1f%%  [totale %.1f%%]</sup>",
            exp_var[1], exp_var[2], exp_var[3],
            exp_var[1]+exp_var[2]+exp_var[3]
        ),
        x = 0.5
    ),
    scene = list(
        xaxis = list(title=sprintf("PC1 (%.1f%%)", exp_var[1])),
        yaxis = list(title=sprintf("PC2 (%.1f%%)", exp_var[2])),
        zaxis = list(title=sprintf("PC3 (%.1f%%)", exp_var[3])),
        camera = list(eye=list(x=1.5, y=1.5, z=1.0))
    ),
    legend = list(title=list(text="Classe"), itemsizing="constant"),
    paper_bgcolor = "white"
)

saveWidget(fig3d, "pca_3d_interactive.html", selfcontained=FALSE,
           libdir="plotly_libs")
cat("✓  pca_3d_interactive.html\n")

# ══════════════════════════════════════════════════════════════════════════════
# PLOT 2: 2D interattivo (PC1 vs PC2)
# ══════════════════════════════════════════════════════════════════════════════
fig2d <- plot_ly()

for (cls in classes) {
    mask <- y == cls
    fig2d <- fig2d %>% add_trace(
        type = "scatter",
        mode = "markers",
        name = sprintf("%s (n=%d)", cls, sum(mask)),
        x    = scores$PC1[mask],
        y    = scores$PC2[mask],
        marker = list(
            size    = 9,
            color   = CLASS_COLORS[cls],
            opacity = 0.85,
            line    = list(color="white", width=0.8)
        ),
        text          = hover_txt[mask],
        hovertemplate = "%{text}<extra></extra>"
    )
}

fig2d <- fig2d %>%
    add_segments(x=min(scores$PC1)*1.2, xend=max(scores$PC1)*1.2,
                 y=0, yend=0,
                 line=list(color="gray", dash="dash", width=0.8),
                 showlegend=FALSE, hoverinfo="skip") %>%
    add_segments(x=0, xend=0,
                 y=min(scores$PC2)*1.2, yend=max(scores$PC2)*1.2,
                 line=list(color="gray", dash="dash", width=0.8),
                 showlegend=FALSE, hoverinfo="skip") %>%
    layout(
        title  = list(text="<b>PCA 2D — ELLONA/IREN</b>", x=0.5),
        xaxis  = list(title=sprintf("PC1 (%.1f%%)", exp_var[1]), zeroline=FALSE),
        yaxis  = list(title=sprintf("PC2 (%.1f%%)", exp_var[2]), zeroline=FALSE),
        legend = list(title=list(text="Classe"), itemsizing="constant"),
        paper_bgcolor="white", plot_bgcolor="#fafafa"
    )

saveWidget(fig2d, "pca_2d_interactive.html", selfcontained=FALSE,
           libdir="plotly_libs")
cat("✓  pca_2d_interactive.html\n")

# ══════════════════════════════════════════════════════════════════════════════
# PLOT 3: Loadings interattivo
# ══════════════════════════════════════════════════════════════════════════════
load1   <- loadings_mat[, 1]
load2   <- loadings_mat[, 2]
contrib <- sqrt(load1^2 + load2^2)
top_idx <- order(contrib, decreasing=TRUE)[1:15]

theta_circ <- seq(0, 2*pi, length.out=300)

fig_load <- plot_ly() %>%
    add_trace(
        type="scatter", mode="lines",
        x=cos(theta_circ), y=sin(theta_circ),
        line=list(color="gray", dash="dash", width=1),
        showlegend=FALSE, hoverinfo="skip"
    )

# Frecce come segmenti (origine → punta) + punti a punta per effetto freccia
seg_x <- as.vector(rbind(rep(0, length(top_idx)), load1[top_idx], NA))
seg_y <- as.vector(rbind(rep(0, length(top_idx)), load2[top_idx], NA))

labels_df <- data.frame(
    x    = load1[top_idx] * 1.15,
    y    = load2[top_idx] * 1.15,
    feat = selected[top_idx]
)

fig_load <- fig_load %>%
    add_trace(
        type="scatter", mode="lines",
        x=seg_x, y=seg_y,
        line=list(color=CLASS_COLORS["ARIA"], width=2),
        showlegend=FALSE, hoverinfo="skip"
    ) %>%
    add_trace(
        type="scatter", mode="markers",
        x=load1[top_idx], y=load2[top_idx],
        marker=list(symbol="arrow", size=10,
                    color=CLASS_COLORS["ARIA"],
                    angleref="previous"),
        showlegend=FALSE, hoverinfo="skip"
    ) %>%
    add_trace(
        type="scatter", mode="text",
        x=labels_df$x, y=labels_df$y,
        text=labels_df$feat,
        textfont=list(size=10, color="#222222"),
        showlegend=FALSE, hoverinfo="skip"
    )

fig_load <- fig_load %>% layout(
    title = list(text="<b>Cerchio delle correlazioni — Top 15 feature</b>", x=0.5),
    xaxis = list(title=sprintf("PC1 (%.1f%%)", exp_var[1]),
                 range=c(-1.3, 1.3), scaleanchor="y",
                 zeroline=TRUE, zerolinecolor="gray"),
    yaxis = list(title=sprintf("PC2 (%.1f%%)", exp_var[2]),
                 range=c(-1.3, 1.3),
                 zeroline=TRUE, zerolinecolor="gray"),
    paper_bgcolor="white", plot_bgcolor="#fafafa",
    width=700, height=700
)

saveWidget(fig_load, "pca_loadings_interactive.html", selfcontained=FALSE,
           libdir="plotly_libs")
cat("✓  pca_loadings_interactive.html\n")
