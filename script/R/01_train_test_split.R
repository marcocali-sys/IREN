# ==============================================================================
# Train/Test split per dataset ELLONA/IREN
# - Rispetta i gruppi Sample.ID (stesso campione madre sempre nello stesso set)
# - Stratificato per Classe2 (ogni classe rappresentata nel test)
# - Ordina per Classe2 per ispezione visiva
# - Salva TRAIN_FEATURES.csv e TEST_FEATURES.csv
# ==============================================================================

INPUT_FILE  <- "Features_Sall.csv"
TRAIN_FILE  <- "TRAIN_FEATURES.csv"
TEST_FILE   <- "TEST_FEATURES.csv"
TEST_SIZE   <- 0.20   # 80/20 → cambia a 0.30 per 70/30
RANDOM_SEED <- 42

set.seed(RANDOM_SEED)

# ── Carica dataset ─────────────────────────────────────────────────────────────
df <- read.csv(INPUT_FILE, sep = ";", stringsAsFactors = FALSE)
cat(sprintf("Dataset caricato: %d campioni, %d colonne\n", nrow(df), ncol(df)))

stopifnot("Sample.ID" %in% names(df))
stopifnot("Classe2"   %in% names(df))

# ── Analisi gruppi ─────────────────────────────────────────────────────────────
cat(sprintf("\nSample.ID unici: %d\n", length(unique(df$Sample.ID))))

cat("\nDistribuzione campioni per Classe2:\n")
class_counts <- sort(table(df$Classe2))
for (cls in names(class_counts)) {
  cat(sprintf("  %-15s %3d campioni\n", cls, class_counts[cls]))
}

# Mappa Sample.ID → Classe2 (ogni Sample.ID appartiene a una sola classe)
id_class_map <- aggregate(Classe2 ~ Sample.ID, data = df, FUN = function(x) x[1])

group_sizes <- aggregate(Sample.ID ~ Sample.ID, data = df, FUN = length)
names(group_sizes)[2] <- "n_diluizioni"
group_sizes <- merge(group_sizes, id_class_map, by = "Sample.ID")
group_sizes <- group_sizes[order(-group_sizes$n_diluizioni), ]

cat("\nSample.ID con più diluizioni:\n")
multi <- group_sizes[group_sizes$n_diluizioni > 1, ]
print(multi, row.names = FALSE)

# ── Split stratificato per classe a livello di Sample.ID ──────────────────────
test_ids  <- c()
train_ids <- c()

for (cls in sort(unique(df$Classe2))) {
  cls_ids <- id_class_map$Sample.ID[id_class_map$Classe2 == cls]
  cls_ids <- sample(cls_ids)  # shuffle

  n_test <- max(1L, round(length(cls_ids) * TEST_SIZE))
  test_ids  <- c(test_ids,  cls_ids[seq_len(n_test)])
  train_ids <- c(train_ids, cls_ids[seq(n_test + 1, length(cls_ids))])
}

train_df <- df[df$Sample.ID %in% train_ids, ]
test_df  <- df[df$Sample.ID %in% test_ids,  ]

# Ordina per Classe2
train_df <- train_df[order(train_df$Classe2), ]
test_df  <- test_df[ order(test_df$Classe2),  ]
rownames(train_df) <- NULL
rownames(test_df)  <- NULL

# ── Verifica: nessun Sample.ID condiviso ──────────────────────────────────────
overlap <- intersect(train_ids, test_ids)
if (length(overlap) > 0) {
  cat(sprintf("\n⚠️  ATTENZIONE: Sample.ID in comune: %s\n", paste(overlap, collapse = ", ")))
} else {
  cat("\n✓  Nessun Sample.ID condiviso tra train e test\n")
}

# ── Report finale ──────────────────────────────────────────────────────────────
cat(sprintf("\n%s\n", strrep("=", 55)))
cat(sprintf("  SPLIT %d/%d  (stratificato per Classe2)\n",
            as.integer((1 - TEST_SIZE) * 100), as.integer(TEST_SIZE * 100)))
cat(sprintf("%s\n", strrep("=", 55)))
cat(sprintf("  %-15s %6s %6s %8s\n", "Classe2", "Train", "Test", "Totale"))
cat(sprintf("  %s\n", strrep("-", 40)))

for (cls in sort(unique(df$Classe2))) {
  n_tr <- sum(train_df$Classe2 == cls)
  n_te <- sum(test_df$Classe2  == cls)
  cat(sprintf("  %-15s %6d %6d %8d\n", cls, n_tr, n_te, n_tr + n_te))
}

cat(sprintf("  %s\n", strrep("-", 40)))
cat(sprintf("  %-15s %6d %6d %8d\n", "TOTALE", nrow(train_df), nrow(test_df), nrow(df)))
cat(sprintf("  Sample.ID unici train: %d\n", length(unique(train_df$Sample.ID))))
cat(sprintf("  Sample.ID unici test:  %d\n", length(unique(test_df$Sample.ID))))

# ── Salva ──────────────────────────────────────────────────────────────────────
write.table(train_df, TRAIN_FILE, sep = ";", row.names = FALSE, quote = FALSE)
write.table(test_df,  TEST_FILE,  sep = ";", row.names = FALSE, quote = FALSE)
cat(sprintf("\n✓  Salvato: %s  (%d righe)\n", TRAIN_FILE, nrow(train_df)))
cat(sprintf("✓  Salvato: %s   (%d righe)\n", TEST_FILE,  nrow(test_df)))
