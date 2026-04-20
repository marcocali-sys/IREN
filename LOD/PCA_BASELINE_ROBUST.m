function PCA_BASELINE_ROBUST()
% PCA_BASELINE_ROBUST
% Costruisce un modello PCA "di riferimento" (aria inodore) da una cartella di CSV:
% - carica e concatena (robusto a colonne mancanti)
% - standardizza (mu/sigma) e fa PCA
% - salva modello riapplicabile a dati nuovi: mu, sigma, muPCA, coeff, predictors, explained
% - esporta scores/loadings + plot
%
% Nota: anche se i dati sono già "normalizzati" (es. R/R0), qui facciamo comunque
%       una standardizzazione z-score (mu/sigma) per PCA (è la prassi).
%
% Marco-style: baseline per LOD su PC1 -> applicabile a monitoraggio/training.

clear; clc;

%% ===== CONFIG =====
dataDir = uigetdir(pwd, 'Seleziona cartella INPUT (CSV)');
if isequal(dataDir,0), return; end
dataDir = string(dataDir);

filePattern  = "*.csv";

predictors = ["MAG2","MAG3","MAG4","MAG5","MAG6","MAG7","Temperature","RH"];

% --- Modalità: per baseline di aria inodore, di default NON fare split ---
doSplitCheck = true;   % <- metti true se vuoi anche train/test (solo controllo)
trainFrac    = 0.80;
rng(1);

% --- Output ---
defaultOut = fullfile(dataDir, "pca_models_matlab");
outDir = uigetdir(defaultOut, 'Seleziona cartella OUTPUT (modelli PCA)');
if isequal(outDir,0), outDir = defaultOut; end
outDir = string(outDir);
if ~isfolder(outDir); mkdir(outDir); end

%% ===== LOAD + CONCAT (ROBUST) =====
files = dir(fullfile(dataDir, filePattern));
if isempty(files)
    error("Nessun file trovato in %s con pattern %s", dataDir, filePattern);
end

needed = unique(["timestamp", predictors], "stable");
allT = cell(numel(files),1);

for i = 1:numel(files)
    f = fullfile(files(i).folder, files(i).name);
    fprintf("Loading %s\n", files(i).name);

    T = readtable(f, "VariableNamingRule","preserve");

    % uniforma timestamp (case-insensitive)
    vn = string(T.Properties.VariableNames);
    idxTS = find(lower(strtrim(vn)) == "timestamp", 1);
    if ~isempty(idxTS) && vn(idxTS) ~= "timestamp"
        T.Properties.VariableNames{idxTS} = "timestamp";
    end

    % sample_ID = nome file
    T.sample_ID = repmat(string(erase(files(i).name,".csv")), height(T), 1);

    % assicura colonne needed
    for c = needed
        if ~ismember(c, string(T.Properties.VariableNames))
            T.(c) = nan(height(T),1);
        end
    end

    % tieni solo needed + sample_ID nello stesso ordine
    T = T(:, [cellstr(needed), "sample_ID"]);

    % parse timestamp se possibile (non critico per PCA)
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

%% ===== EXTRACT X + CLEAN =====
X = DATA{:, predictors};

% tieni solo righe finite
valid = all(isfinite(X), 2);
X = X(valid,:);
META = DATA(valid,:);

n = size(X,1);
fprintf("Total valid rows: %d\n", n);
if n < 5
    error("Troppi pochi dati validi dopo il filtro (n=%d).", n);
end

%% ===== (OPZIONALE) TRAIN/TEST SPLIT SOLO COME CHECK =====
if doSplitCheck
    idx = randperm(n);
    nTrain = max(2, round(trainFrac * n)); % almeno 2
    idxTrain = false(n,1);
    idxTrain(idx(1:nTrain)) = true;
    idxTest = ~idxTrain;

    Xtr = X(idxTrain,:);
    Xte = X(idxTest,:);
else
    % baseline: usa tutto
    idxTrain = true(n,1);
    idxTest  = false(n,1);
    Xtr = X;
    Xte = [];
end

%% ===== STANDARDIZE (mu/sigma) CALCOLATI SUL "TRAIN" (che per baseline = tutto) =====
mu    = mean(Xtr, 1, "omitnan");
sigma = std(Xtr, 0, 1, "omitnan");
sigma(sigma==0 | isnan(sigma)) = 1;

Xtrz = (Xtr - mu) ./ sigma;

%% ===== PCA FIT (COERENTE) =====
% IMPORTANTISSIMO: salva il centro usato dalla PCA (muPCA) e usalo nelle proiezioni
[coeff, score_tr, latent, tsquared, explained, muPCA] = pca(Xtrz);

% Proiezione TEST (solo se doSplitCheck)
if doSplitCheck && ~isempty(Xte)
    Xtez = (Xte - mu) ./ sigma;
    score_te = (Xtez - muPCA) * coeff;
else
    score_te = [];
end

% keep first 3 PCs
nPC = min(3, size(score_tr,2));
pcNames = "PC" + string(1:nPC);
expl3 = explained(1:nPC);

score_tr3 = score_tr(:,1:nPC);
if ~isempty(score_te)
    score_te3 = score_te(:,1:nPC);
else
    score_te3 = [];
end

%% ===== SCORES TABLE =====
ScoresTrain = array2table(score_tr3, "VariableNames", cellstr(pcNames));
ScoresTrain.Set = repmat("BaselineTrain", height(ScoresTrain), 1);
ScoresTrain.sample_ID = META.sample_ID(idxTrain);

if doSplitCheck && ~isempty(score_te3)
    ScoresTest = array2table(score_te3, "VariableNames", cellstr(pcNames));
    ScoresTest.Set = repmat("TestProjection", height(ScoresTest), 1);
    ScoresTest.sample_ID = META.sample_ID(idxTest);
    Scores = [ScoresTrain; ScoresTest];
else
    Scores = ScoresTrain;
end

%% ===== LOADINGS TABLE =====
Loadings = table(predictors', coeff(:,1), 'VariableNames', {'Variable','PC1'});
if nPC >= 2, Loadings.PC2 = coeff(:,2); end
if nPC >= 3, Loadings.PC3 = coeff(:,3); end

%% ===== PLOTS =====
% Scores PC1-PC2
if nPC >= 2
    figure; gscatter(Scores.PC1, Scores.PC2, Scores.Set);
    grid on;
    xlabel(sprintf("PC1 (%.1f%%)", expl3(1)));
    ylabel(sprintf("PC2 (%.1f%%)", expl3(2)));
    title("PCA Scores (baseline + eventuale test projection)");
    exportgraphics(gcf, fullfile(outDir, "scores_pc12.png"), "Resolution", 300);
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

% Scree
figure;
bar(explained);
grid on;
xlabel("Principal Component");
ylabel("Explained variance (%)");
title("Scree plot");
exportgraphics(gcf, fullfile(outDir, "scree.png"), "Resolution", 300);

%% ===== SAVE CSV =====
writetable(Scores,   fullfile(outDir, "pca_scores_all.csv"));
writetable(Loadings, fullfile(outDir, "pca_loadings.csv"));

%% ===== SAVE MODEL (MONITORING-READY) =====
save(fullfile(outDir, "pca_model.mat"), ...
    "mu","sigma","muPCA","coeff","explained","latent","predictors");

fprintf("Saved outputs in: %s\n", outDir);

%% ===== INFO: formula da usare in monitoraggio =====
fprintf("\nPer applicare il modello a dati nuovi:\n");
fprintf("  Xz = (X - mu) ./ sigma;\n");
fprintf("  Scores = (Xz - muPCA) * coeff;\n");
fprintf("  PC1 = Scores(:,1);\n\n");

end