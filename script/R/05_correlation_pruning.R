# ==============================================================================
# Step A — Correlation-based pruning
# - Carica le feature LOGO-selected
# - Pruning greedy per importanza: rimuove feature con |ρ| > soglia
# ==============================================================================
# Richiede: install.packages(c("ggplot2","reshape2"))
# ==============================================================================

library(ggplot2)
library(reshape2)

setwd(normalizePath("~/Desktop/IREN"))

CORR_THRESH <- 0.90

# ── Carica feature e importanze ───────────────────────────────────────────────
lines_raw   <- readLines("logo_selected_features.txt")
logo_feats  <- lines_raw[!grepl("^#", lines_raw) & nchar(trimws(lines_raw)) > 0]

imp_df <- read.csv("logo_feature_importance.csv", sep=";", stringsAsFactors=FALSE)
imp_df <- imp_df[imp_df$Feature %in% logo_feats, ]
imp_df <- imp_df[order(-imp_df$MeanImportance), ]
features_ranked <- imp_df$Feature
cat(sprintf("Feature LOGO-selected in input: %d\n", length(features_ranked)))

# ── Carica training set ───────────────────────────────────────────────────────
df <- read.csv("TRAIN_FEATURES.csv", sep=";", stringsAsFactors=FALSE)
X  <- df[, features_ranked, drop=FALSE]
for (col in names(X))
    if (any(is.na(X[[col]]))) X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm=TRUE)

corr_matrix <- cor(X)

# ── Pruning greedy ────────────────────────────────────────────────────────────
kept    <- character(0)
removed <- character(0)
reason  <- list()

for (feat in features_ranked) {
    if (length(kept) == 0) { kept <- c(kept, feat); next }
    corrs    <- abs(corr_matrix[feat, kept])
    max_corr <- max(corrs)
    if (max_corr <= CORR_THRESH) {
        kept <- c(kept, feat)
    } else {
        partner <- kept[which.max(corrs)]
        removed <- c(removed, feat)
        reason[[feat]] <- c(partner, round(corr_matrix[feat, partner], 4))
    }
}

cat(sprintf("\nSoglia correlazione: |ρ| > %.2f\n", CORR_THRESH))
cat(sprintf("Feature mantenute: %d\n", length(kept)))
cat(sprintf("Feature rimosse:   %d\n", length(removed)))

# ── Report ────────────────────────────────────────────────────────────────────
cat(sprintf("\n%s\n  FEATURE MANTENUTE (%d)\n%s\n", strrep("=",55), length(kept), strrep("=",55)))
for (i in seq_along(kept)) {
    imp <- imp_df$MeanImportance[imp_df$Feature == kept[i]]
    cat(sprintf("  %2d. %-15s  imp=%.5f\n", i, kept[i], imp))
}

cat(sprintf("\n  FEATURE RIMOSSE (%d) — troppo correlate:\n", length(removed)))
for (feat in removed) {
    imp     <- imp_df$MeanImportance[imp_df$Feature == feat]
    partner <- reason[[feat]][1]
    rho     <- as.numeric(reason[[feat]][2])
    cat(sprintf("  %-15s  imp=%.5f  |ρ|=%.3f  con %s\n", feat, imp, abs(rho), partner))
}

# ── Plot heatmap feature mantenute ───────────────────────────────────────────
corr_kept <- corr_matrix[kept, kept]
corr_melt <- melt(corr_kept)
names(corr_melt) <- c("Var1","Var2","value")
# Triangolo inferiore
corr_melt$value[as.integer(corr_melt$Var1) < as.integer(corr_melt$Var2)] <- NA

p <- ggplot(corr_melt, aes(x=Var1, y=Var2, fill=value)) +
    geom_tile(color="white") +
    scale_fill_gradient2(low="#B2182B", mid="white", high="#2166AC",
                         midpoint=0, limits=c(-1,1), na.value="gray95",
                         name="ρ") +
    geom_text(aes(label=ifelse(!is.na(value), sprintf("%.2f",value), "")),
              size=3) +
    labs(title=sprintf("Correlazione — %d feature post-pruning (|ρ|≤%.2f)",
                       length(kept), CORR_THRESH),
         x=NULL, y=NULL) +
    theme_minimal(base_size=10) +
    theme(axis.text.x=element_text(angle=45, hjust=1))

ggsave("corr_matrix_kept.png", p,
       width=max(6, length(kept)*0.5), height=max(5, length(kept)*0.45), dpi=150)
cat("\n✓  corr_matrix_kept.png\n")

# ── Salva ─────────────────────────────────────────────────────────────────────
rows <- lapply(features_ranked, function(feat) {
    imp <- imp_df$MeanImportance[imp_df$Feature == feat]
    if (feat %in% kept) {
        data.frame(Feature=feat, Status="Kept", MeanImportance=imp,
                   RemovedDueTo="", MaxCorr=NA_real_, stringsAsFactors=FALSE)
    } else {
        data.frame(Feature=feat, Status="Removed", MeanImportance=imp,
                   RemovedDueTo=reason[[feat]][1],
                   MaxCorr=as.numeric(reason[[feat]][2]), stringsAsFactors=FALSE)
    }
})
report_df <- do.call(rbind, rows)
write.table(report_df, "corr_pruning_report.csv", sep=";", row.names=FALSE, quote=FALSE)

con <- file("corr_pruned_features.txt","w")
writeLines(sprintf("# Correlation pruning — soglia |ρ|=%.2f", CORR_THRESH), con)
writeLines(sprintf("# Input: %d  →  Output: %d feature", length(features_ranked), length(kept)), con)
writeLines("", con)
writeLines(kept, con)
close(con)

cat("✓  corr_pruning_report.csv\n")
cat("✓  corr_pruned_features.txt\n")
