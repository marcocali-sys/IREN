function COMPUTE_BASELINE_FROM_PCA_SCORES_2()
% Baseline su PC1 e PC2 (mediana per sample_ID, poi mean/std delle mediane)
% Funziona sia con CSV con header sia senza header.
%
% OUTPUT (per GUI PC1+PC2):
%   - baseline_PC1_PC2_stats.csv  <-- contiene PC1 e PC2 mean/std
% Inoltre salva anche i file separati (compatibilità):
%   - baseline_PC1_medians.csv
%   - baseline_PC2_medians.csv
%   - baseline_PC1_stats.csv
%   - baseline_PC2_stats.csv

clear; clc;

%% ===== INPUT =====
[scoresFile, scoresPath] = uigetfile('*.csv', 'Seleziona pca_scores_train_test.csv');
if isequal(scoresFile,0), return; end
scoresCsv = fullfile(scoresPath, scoresFile);

useOnlyTraining = false;

outDir = uigetdir(scoresPath, 'Seleziona cartella OUTPUT (baseline)');
if isequal(outDir,0), outDir = scoresPath; end
if ~isfolder(outDir); mkdir(outDir); end

%% ===== LOAD ROBUST (header sì/no) =====
fid = fopen(scoresCsv, 'r');
firstLine = fgetl(fid);
fclose(fid);

hasHeader = contains(lower(string(firstLine)), "pc1") && contains(lower(string(firstLine)), "sample");

if hasHeader
    Scores = readtable(scoresCsv, 'Delimiter', ',', 'TextType', 'string');
else
    Scores = readtable(scoresCsv, 'Delimiter', ',', 'TextType', 'string', 'ReadVariableNames', false);
    if width(Scores) < 5
        error("CSV senza header ma con %d colonne: attese almeno 5 (PC1,PC2,PC3,Set,sample_ID).", width(Scores));
    end
    Scores = Scores(:,1:5);
    Scores.Properties.VariableNames = {'PC1','PC2','PC3','Set','sample_ID'};
end

%% ===== CHECK COLONNE =====
requiredCols = ["PC1","PC2","sample_ID"];
missing = setdiff(requiredCols, string(Scores.Properties.VariableNames));
if ~isempty(missing)
    error("Mancano colonne nel CSV: %s", strjoin(missing,", "));
end

%% ===== FILTRO TRAINING =====
if useOnlyTraining
    if ismember("Set", string(Scores.Properties.VariableNames))
        Scores.Set = string(Scores.Set);
        Scores = Scores(Scores.Set == "BaselineTrain", :);
    else
        warning("Colonna 'Set' non trovata: uso tutte le righe.");
    end
end

Scores.sample_ID = string(Scores.sample_ID);

PC1 = Scores.PC1; if ~isnumeric(PC1), PC1 = str2double(string(PC1)); end
PC2 = Scores.PC2; if ~isnumeric(PC2), PC2 = str2double(string(PC2)); end

%% ===== MEDIANE PER sample_ID =====
[G, sampleIDs] = findgroups(Scores.sample_ID);
PC1_median = splitapply(@(x) median(x,'omitnan'), PC1, G);
PC2_median = splitapply(@(x) median(x,'omitnan'), PC2, G);

BaselinePC1 = table(sampleIDs, PC1_median, 'VariableNames', {'sample_ID','PC1_median'});
BaselinePC2 = table(sampleIDs, PC2_median, 'VariableNames', {'sample_ID','PC2_median'});

%% ===== STATS =====
pc1_mean = mean(PC1_median,'omitnan'); pc1_std = std(PC1_median,'omitnan');
pc2_mean = mean(PC2_median,'omitnan'); pc2_std = std(PC2_median,'omitnan');

StatsPC1 = table(pc1_mean, pc1_std, 'VariableNames', {'PC1_mean_of_medians','PC1_std_of_medians'});
StatsPC2 = table(pc2_mean, pc2_std, 'VariableNames', {'PC2_mean_of_medians','PC2_std_of_medians'});

% >>> QUESTO È QUELLO CHE VUOLE LA GUI <<<
StatsBoth = table(pc1_mean, pc1_std, pc2_mean, pc2_std, ...
    'VariableNames', {'PC1_mean_of_medians','PC1_std_of_medians','PC2_mean_of_medians','PC2_std_of_medians'});

%% ===== SAVE =====
writetable(BaselinePC1, fullfile(outDir,"baseline_PC1_medians.csv"));
writetable(BaselinePC2, fullfile(outDir,"baseline_PC2_medians.csv"));

writetable(StatsPC1,    fullfile(outDir,"baseline_PC1_stats.csv"));
writetable(StatsPC2,    fullfile(outDir,"baseline_PC2_stats.csv"));

% file unico per la GUI
writetable(StatsBoth,   fullfile(outDir,"baseline_PC1_PC2_stats.csv"));

%% ===== LOG =====
fprintf("\n=== BASELINE PCA (Training only) ===\n");
fprintf("N sample_ID = %d\n", height(BaselinePC1));
fprintf("PC1 mean/std of medians = %.6f / %.6f\n", pc1_mean, pc1_std);
fprintf("PC2 mean/std of medians = %.6f / %.6f\n", pc2_mean, pc2_std);

fprintf("\nSaved:\n");
fprintf("  %s\n", fullfile(outDir,"baseline_PC1_PC2_stats.csv"));
fprintf("  %s\n", fullfile(outDir,"baseline_PC1_medians.csv"));
fprintf("  %s\n", fullfile(outDir,"baseline_PC2_medians.csv"));
fprintf("  %s\n", fullfile(outDir,"baseline_PC1_stats.csv"));
fprintf("  %s\n\n", fullfile(outDir,"baseline_PC2_stats.csv"));

end