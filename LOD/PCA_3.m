%% ===== PCA BASELINE (ROBUST) =====
clear; clc;

%% ===== CONFIG =====
% --- scegli cartella input
dataDir = uigetdir(pwd, 'Seleziona cartella INPUT (CSV)');
if isequal(dataDir,0), return; end
dataDir = string(dataDir);

filePattern  = "*.csv";

predictors = ["MAG2","MAG3","MAG4","MAG5","MAG6","MAG7","Temperature","RH"];

trainFrac = 0.80;
rng(1);

% --- scegli cartella output
defaultOut = fullfile(dataDir, "pca_models_matlab");
outDir = uigetdir(defaultOut, 'Seleziona cartella OUTPUT (modelli PCA)');
if isequal(outDir,0)
    % se annulli, usa la cartella default dentro l'input
    outDir = defaultOut;
end
outDir = string(outDir);

if ~isfolder(outDir); mkdir(outDir); end
%% ===== LOAD + CONCAT (ROBUST: stesse colonne per tutti) =====
files = dir(fullfile(dataDir, filePattern));
if isempty(files)
    error("Nessun file trovato in %s con pattern %s", dataDir, filePattern);
end

needed = unique(["timestamp", predictors], "stable");  % colonne minime garantite
allT = cell(numel(files),1);

for i = 1:numel(files)
    f = fullfile(files(i).folder, files(i).name);
    fprintf("Loading %s\n", files(i).name);

    % Preserva i nomi originali + evita warning
    T = readtable(f, "VariableNamingRule","preserve");

    % Uniforma "timestamp" se ha case diverso (Timestamp / TIMESTAMP / ecc.)
    vn = string(T.Properties.VariableNames);
    idxTS = find(lower(strtrim(vn)) == "timestamp", 1);
    if ~isempty(idxTS) && vn(idxTS) ~= "timestamp"
        T.Properties.VariableNames{idxTS} = "timestamp";
    end

    % Aggiungi sample_ID
    T.sample_ID = repmat(string(erase(files(i).name,".csv")), height(T), 1);

    % Assicura che esistano tutte le colonne "needed"
    for c = needed
        if ~ismember(c, string(T.Properties.VariableNames))
            T.(c) = nan(height(T),1);
        end
    end

    % Tieni SOLO colonne utili + sample_ID (stesso ordine sempre)
    T = T(:, [cellstr(needed), "sample_ID"]);

    % Parse timestamp se presente (altrimenti resta NaT)
    if ~isdatetime(T.timestamp)
        try
            T.timestamp = datetime(string(T.timestamp), ...
                "InputFormat","dd-MMM-yyyy HH:mm:ss", ...
                "Locale","en_US");
        catch
            T.timestamp = NaT(height(T),1);
        end
    end

    allT{i} = T;
end

DATA = vertcat(allT{:});

%% ===== EXTRACT X (predictors) + CLEAN =====
X = DATA{:, predictors};

% tieni righe con tutti i predictors finiti (no NaN/Inf)
valid = all(isfinite(X), 2);
X = X(valid,:);
META = DATA(valid,:);

n = size(X,1);
fprintf("Total valid rows: %d\n", n);
if n < 5
    error("Troppi pochi dati validi dopo il filtro (n=%d).", n);
end

%% ===== TRAIN/TEST SPLIT =====
idx = randperm(n);
nTrain = max(1, round(trainFrac * n));

idxTrain = false(n,1);
idxTrain(idx(1:nTrain)) = true;
idxTest = ~idxTrain;

Xtr = X(idxTrain,:);
Xte = X(idxTest,:);

%% ===== STANDARDIZE USING TRAIN ONLY =====
mu = mean(Xtr, 1, "omitnan");
sigma = std(Xtr, 0, 1, "omitnan");
sigma(sigma==0 | isnan(sigma)) = 1;

Xtrz = (Xtr - mu) ./ sigma;
Xtez = (Xte - mu) ./ sigma;

%% ===== PCA FIT ON TRAIN =====
[coeff, score_tr, latent, tsquared, explained] = pca(Xtrz);

% Project TEST onto same PCA space
score_te = Xtez * coeff;

% Keep first 3 PCs (se ci sono)
nPC = min(3, size(score_tr,2));
score_tr3 = score_tr(:,1:nPC);
score_te3 = score_te(:,1:nPC);
expl3 = explained(1:nPC);

%% ===== BUILD SCORES TABLE (train + test) =====
pcNames = "PC" + string(1:nPC);

ScoresTrain = array2table(score_tr3, "VariableNames", cellstr(pcNames));
ScoresTrain.Set = repmat("Training", height(ScoresTrain), 1);
ScoresTrain.sample_ID = META.sample_ID(idxTrain);

ScoresTest  = array2table(score_te3, "VariableNames", cellstr(pcNames));
ScoresTest.Set = repmat("Test", height(ScoresTest), 1);
ScoresTest.sample_ID = META.sample_ID(idxTest);

Scores = [ScoresTrain; ScoresTest];

%% ===== LOADINGS TABLE =====
Loadings = table(predictors', coeff(:,1), 'VariableNames', {'Variable','PC1'});
if nPC >= 2, Loadings.PC2 = coeff(:,2); end
if nPC >= 3, Loadings.PC3 = coeff(:,3); end

%% ===== PLOTS =====
% Scores PC1-PC2 (se PC2 esiste)
if nPC >= 2
    figure; gscatter(Scores.PC1, Scores.PC2, Scores.Set);
    grid on;
    xlabel(sprintf("PC1 (%.1f%%)", expl3(1)));
    ylabel(sprintf("PC2 (%.1f%%)", expl3(2)));
    title("PCA Scores (Train + Test projection)");
    exportgraphics(gcf, fullfile(outDir, "scores_pc12.png"), "Resolution", 300);
end

% Scores PC1-PC3 (se PC3 esiste)
if nPC >= 3
    figure; gscatter(Scores.PC1, Scores.PC3, Scores.Set);
    grid on;
    xlabel(sprintf("PC1 (%.1f%%)", expl3(1)));
    ylabel(sprintf("PC3 (%.1f%%)", expl3(3)));
    title("PCA Scores (PC1 vs PC3)");
    exportgraphics(gcf, fullfile(outDir, "scores_pc13.png"), "Resolution", 300);
end

% Loadings PC1-PC2
if nPC >= 2
    figure; hold on; grid on; axis equal;
    quiver(zeros(numel(predictors),1), zeros(numel(predictors),1), ...
        coeff(:,1), coeff(:,2), 0, "LineWidth",1.5);
    for k = 1:numel(predictors)
        text(coeff(k,1)*1.1, coeff(k,2)*1.1, predictors(k));
    end
    xlabel(sprintf("PC1 (%.1f%%)", expl3(1)));
    ylabel(sprintf("PC2 (%.1f%%)", expl3(2)));
    title("PCA Loadings (PC1 vs PC2)");
    exportgraphics(gcf, fullfile(outDir, "loadings_pc12.png"), "Resolution", 300);
end

% Loadings PC1-PC3
if nPC >= 3
    figure; hold on; grid on; axis equal;
    quiver(zeros(numel(predictors),1), zeros(numel(predictors),1), ...
        coeff(:,1), coeff(:,3), 0, "LineWidth",1.5);
    for k = 1:numel(predictors)
        text(coeff(k,1)*1.1, coeff(k,3)*1.1, predictors(k));
    end
    xlabel(sprintf("PC1 (%.1f%%)", expl3(1)));
    ylabel(sprintf("PC3 (%.1f%%)", expl3(3)));
    title("PCA Loadings (PC1 vs PC3)");
    exportgraphics(gcf, fullfile(outDir, "loadings_pc13.png"), "Resolution", 300);
end

% Scree
figure;
bar(explained);
grid on;
xlabel("Principal Component");
ylabel("Explained variance (%)");
title("Scree plot");
exportgraphics(gcf, fullfile(outDir, "scree.png"), "Resolution", 300);

%% ===== SAVE CSV =====
writetable(Scores,   fullfile(outDir, "pca_scores_train_test.csv"));
writetable(Loadings, fullfile(outDir, "pca_loadings.csv"));

%% ===== SAVE MODEL =====
save(fullfile(outDir, "pca_model.mat"), "mu", "sigma", "coeff", "explained", "predictors");
fprintf("Saved outputs in: %s\n", outDir);