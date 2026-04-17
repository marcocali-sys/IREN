% =========================================================================
% Train/Test split per dataset ELLONA/IREN
% - Rispetta i gruppi Sample.ID (stesso campione madre sempre nello stesso set)
% - Stratificato per Classe2 (ogni classe rappresentata nel test)
% - Ordina per Classe2 per ispezione visiva
% - Salva TRAIN_FEATURES.csv e TEST_FEATURES.csv
% =========================================================================

INPUT_FILE  = 'Features_Sall.csv';
TRAIN_FILE  = 'TRAIN_FEATURES.csv';
TEST_FILE   = 'TEST_FEATURES.csv';
TEST_SIZE   = 0.20;   % 80/20 → cambia a 0.30 per 70/30
RANDOM_SEED = 42;

rng(RANDOM_SEED);

% ── Carica dataset ────────────────────────────────────────────────────────
opts = detectImportOptions(INPUT_FILE, 'Delimiter', ';');
df   = readtable(INPUT_FILE, opts);

fprintf('Dataset caricato: %d campioni, %d colonne\n', height(df), width(df));

% ── Analisi gruppi ────────────────────────────────────────────────────────
sample_ids  = df.Sample_ID;   % MATLAB rinomina Sample.ID → Sample_ID
classes     = df.Classe2;

unique_ids  = unique(sample_ids);
n_groups    = numel(unique_ids);
fprintf('\nSample.ID unici: %d\n', n_groups);

fprintf('\nDistribuzione campioni per Classe2:\n');
unique_cls = unique(classes);
unique_cls = sort(unique_cls);
for i = 1:numel(unique_cls)
    cls = unique_cls{i};
    n   = sum(strcmp(classes, cls));
    fprintf('  %-15s %3d campioni\n', cls, n);
end

% Mappa Sample.ID → Classe2 (ogni Sample.ID appartiene a una sola classe)
id_to_class = cell(n_groups, 2);
for i = 1:n_groups
    sid  = unique_ids(i);
    mask = sample_ids == sid;
    cls_vals = classes(mask);
    id_to_class{i, 1} = sid;
    id_to_class{i, 2} = cls_vals{1};
end

% Dimensione gruppi (numero diluizioni per Sample.ID)
fprintf('\nSample.ID con più diluizioni:\n');
fprintf('  %-12s %-6s %-15s\n', 'Sample.ID', 'N_dil', 'Classe2');
fprintf('  %s\n', repmat('-', 1, 36));
group_sizes = zeros(n_groups, 1);
for i = 1:n_groups
    group_sizes(i) = sum(sample_ids == unique_ids(i));
end
[~, sort_idx] = sort(group_sizes, 'descend');
for i = 1:n_groups
    idx = sort_idx(i);
    if group_sizes(idx) > 1
        fprintf('  %-12d %-6d %-15s\n', unique_ids(idx), group_sizes(idx), id_to_class{idx, 2});
    end
end

% ── Split stratificato per classe a livello di Sample.ID ─────────────────
test_ids  = [];
train_ids = [];

for i = 1:numel(unique_cls)
    cls = unique_cls{i};

    % Sample.ID appartenenti a questa classe
    cls_mask = strcmp([id_to_class{:,2}]', cls);
    cls_ids  = cell2mat(id_to_class(cls_mask, 1));

    % Shuffle
    cls_ids = cls_ids(randperm(numel(cls_ids)));

    n_test  = max(1, round(numel(cls_ids) * TEST_SIZE));
    test_ids  = [test_ids;  cls_ids(1:n_test)];
    train_ids = [train_ids; cls_ids(n_test+1:end)];
end

train_mask = ismember(sample_ids, train_ids);
test_mask  = ismember(sample_ids, test_ids);

train_df = df(train_mask, :);
test_df  = df(test_mask,  :);

% Ordina per Classe2
train_df = sortrows(train_df, 'Classe2');
test_df  = sortrows(test_df,  'Classe2');

% ── Verifica: nessun Sample.ID condiviso ─────────────────────────────────
overlap = intersect(train_ids, test_ids);
if ~isempty(overlap)
    fprintf('\nATTENZIONE: Sample.ID in comune: ');
    fprintf('%d ', overlap);
    fprintf('\n');
else
    fprintf('\n✓  Nessun Sample.ID condiviso tra train e test\n');
end

% ── Report finale ─────────────────────────────────────────────────────────
sep = repmat('=', 1, 55);
dash = repmat('-', 1, 40);
fprintf('\n%s\n', sep);
fprintf('  SPLIT %d/%d  (stratificato per Classe2)\n', ...
        round((1-TEST_SIZE)*100), round(TEST_SIZE*100));
fprintf('%s\n', sep);
fprintf('  %-15s %6s %6s %8s\n', 'Classe2', 'Train', 'Test', 'Totale');
fprintf('  %s\n', dash);

for i = 1:numel(unique_cls)
    cls  = unique_cls{i};
    n_tr = sum(strcmp(train_df.Classe2, cls));
    n_te = sum(strcmp(test_df.Classe2,  cls));
    fprintf('  %-15s %6d %6d %8d\n', cls, n_tr, n_te, n_tr+n_te);
end

fprintf('  %s\n', dash);
fprintf('  %-15s %6d %6d %8d\n', 'TOTALE', height(train_df), height(test_df), height(df));
fprintf('  Sample.ID unici train: %d\n', numel(unique(train_df.Sample_ID)));
fprintf('  Sample.ID unici test:  %d\n', numel(unique(test_df.Sample_ID)));

% ── Salva ─────────────────────────────────────────────────────────────────
writetable(train_df, TRAIN_FILE, 'Delimiter', ';');
writetable(test_df,  TEST_FILE,  'Delimiter', ';');
fprintf('\n✓  Salvato: %s  (%d righe)\n', TRAIN_FILE, height(train_df));
fprintf('✓  Salvato: %s   (%d righe)\n', TEST_FILE,  height(test_df));
