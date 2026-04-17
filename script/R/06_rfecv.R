# ==============================================================================
# Step C — RFECV con LOGO-CV
# - Feature post correlation-pruning
# - Recursive Feature Elimination manuale con ranger + LOGO-CV
# - Trova numero ottimale di feature per balanced accuracy
# ==============================================================================
# Richiede: install.packages(c("ranger","ggplot2"))
# ==============================================================================

library(ranger)
library(ggplot2)

setwd(normalizePath("~/Desktop/IREN"))

RANDOM_SEED <- 42
N_TREES     <- 300
MIN_FEATS   <- 3

set.seed(RANDOM_SEED)

# ── Carica feature post-pruning ───────────────────────────────────────────────
lines_raw <- readLines("corr_pruned_features.txt")
feats     <- lines_raw[!grepl("^#", lines_raw) & nchar(trimws(lines_raw)) > 0]
cat(sprintf("Feature in input (post correlation pruning): %d\n", length(feats)))

# ── Carica training set ───────────────────────────────────────────────────────
df     <- read.csv("TRAIN_FEATURES.csv", sep=";", stringsAsFactors=FALSE)
groups <- df$Sample.ID
y      <- as.factor(df$Classe2)
X      <- df[, feats, drop=FALSE]
for (col in names(X))
    if (any(is.na(X[[col]]))) X[[col]][is.na(X[[col]])] <- median(X[[col]], na.rm=TRUE)

cat(sprintf("Training set: %d campioni, %d feature\n", nrow(df), length(feats)))

unique_groups <- unique(groups)
n_folds       <- length(unique_groups)
cat(sprintf("Gruppi LOGO: %d fold\n\n", n_folds))

# ── Helper: LOGO-CV con ranger su un sottoinsieme di feature ─────────────────
logo_balanced_accuracy <- function(feat_subset) {
    correct_per_class <- list()
    total_per_class   <- list()

    for (g in unique_groups) {
        test_mask  <- groups == g
        train_mask <- !test_mask

        X_tr <- X[train_mask, feat_subset, drop=FALSE]
        X_te <- X[test_mask,  feat_subset, drop=FALSE]
        y_tr <- y[train_mask]
        y_te <- y[test_mask]

        train_df_fold <- cbind(X_tr, Classe2=y_tr)
        rf <- ranger(Classe2 ~ ., data=train_df_fold,
                     num.trees=N_TREES, seed=RANDOM_SEED,
                     num.threads=parallel::detectCores())
        preds <- predict(rf, data=X_te)$predictions

        for (cls in levels(y)) {
            mask_true <- y_te == cls
            if (!sum(mask_true)) next
            correct_per_class[[cls]] <- (correct_per_class[[cls]] %||% 0) +
                sum(preds[mask_true] == cls)
            total_per_class[[cls]]   <- (total_per_class[[cls]] %||% 0) +
                sum(mask_true)
        }
    }
    per_class_acc <- sapply(levels(y), function(cls) {
        if (is.null(total_per_class[[cls]]) || total_per_class[[cls]] == 0) return(NA)
        correct_per_class[[cls]] / total_per_class[[cls]]
    })
    mean(per_class_acc, na.rm=TRUE)
}
`%||%` <- function(a, b) if (!is.null(a)) a else b

# ── RFE manuale ───────────────────────────────────────────────────────────────
# 1. Fit RF su tutte le feature → importanza
# 2. Evalua LOGO-CV per ogni sottoinsieme (da n_max a MIN_FEATS)
# 3. Trova n ottimale

cat("Avvio RFECV manuale...\n")
cat(sprintf("  Valuto %d configurazioni (da %d a %d feature)\n",
            length(feats) - MIN_FEATS + 1, length(feats), MIN_FEATS))

# Ranking iniziale tramite RF su tutti i dati di training
full_train <- cbind(X, Classe2=y)
rf_full <- ranger(Classe2 ~ ., data=full_train,
                  num.trees=N_TREES, importance="impurity",
                  seed=RANDOM_SEED, num.threads=parallel::detectCores())
imp_order <- order(rf_full$variable.importance, decreasing=TRUE)
feats_ranked <- feats[imp_order]   # feature ordinate per importanza

n_sizes  <- seq(length(feats), MIN_FEATS)
ba_scores <- numeric(length(n_sizes))

for (i in seq_along(n_sizes)) {
    n   <- n_sizes[i]
    top <- feats_ranked[1:n]
    ba  <- logo_balanced_accuracy(top)
    ba_scores[i] <- ba
    cat(sprintf("  n=%2d feature → balanced_accuracy=%.4f\n", n, ba))
}

best_idx   <- which.max(ba_scores)
n_optimal  <- n_sizes[best_idx]
ba_optimal <- ba_scores[best_idx]
selected_feats <- feats_ranked[1:n_optimal]

cat(sprintf("\nNumero ottimale di feature: %d\n", n_optimal))
cat(sprintf("Balanced accuracy ottimale: %.4f\n", ba_optimal))

# ── Report ────────────────────────────────────────────────────────────────────
cat(sprintf("\n%s\n  RFECV — Feature selezionate (%d)\n%s\n",
            strrep("=",50), n_optimal, strrep("=",50)))
for (i in seq_along(selected_feats))
    cat(sprintf("  %2d. %s\n", i, selected_feats[i]))

excluded <- setdiff(feats_ranked, selected_feats)
if (length(excluded))
    cat(sprintf("\n  Feature escluse (%d): %s\n", length(excluded), paste(excluded, collapse=", ")))

# ── Plot curva RFECV ──────────────────────────────────────────────────────────
curve_df <- data.frame(N=n_sizes, BA=ba_scores)
p <- ggplot(curve_df, aes(x=N, y=BA)) +
    geom_line(color="#4878CF", linewidth=1.2) +
    geom_point(color="#4878CF", size=3) +
    geom_vline(xintercept=n_optimal, linetype="dashed",
               color="#D65F5F", linewidth=1) +
    geom_hline(yintercept=ba_optimal, linetype="dotted",
               color="#D65F5F", linewidth=0.8, alpha=0.7) +
    annotate("label", x=n_optimal, y=ba_optimal - 0.04,
             label=sprintf("%d feat\nBA=%.3f", n_optimal, ba_optimal),
             color="#D65F5F", size=3.5, fill="white") +
    scale_x_continuous(breaks=n_sizes) +
    labs(title="RFECV — Selezione numero ottimale di feature\nELLONA/IREN",
         x="Numero di feature", y="Balanced accuracy (LOGO-CV)") +
    theme_minimal(base_size=11) +
    theme(panel.grid.minor=element_blank())

ggsave("rfecv_results.png", p, width=10, height=5, dpi=150)
cat("\n✓  rfecv_results.png\n")

# ── Salva ─────────────────────────────────────────────────────────────────────
write.table(curve_df, "rfecv_curve.csv", sep=";", row.names=FALSE, quote=FALSE)

con <- file("rfecv_selected_features.txt","w")
writeLines(sprintf("# RFECV — %d feature selezionate", n_optimal), con)
writeLines(sprintf("# Scoring: balanced_accuracy | CV: LOGO (gruppi=Sample.ID)"), con)
writeLines(sprintf("# Balanced accuracy ottimale: %.4f", ba_optimal), con)
writeLines("", con)
writeLines(selected_feats, con)
close(con)

cat("✓  rfecv_curve.csv\n")
cat("✓  rfecv_selected_features.txt\n")
