function COMPUTE_BASELINE_FROM_PCA_SCORES_POINTWISE_MEANSTD()
% Baseline su PC1 e PC2 POINTWISE (tutte le righe) usando SOLO mean/std.
%
% INPUT:
%   - CSV scores (deve contenere almeno PC1, PC2; sample_ID/Set sono opzionali)
%
% OUTPUT (per GUI PC1+PC2):
%   - baseline_PC1_PC2_stats.csv  <-- mean/std su tutti i punti
% Inoltre (debug/compatibilità):
%   - baseline_PC1_values.csv
%   - baseline_PC2_values.csv

clear; clc;

%% ===== INPUT =====
[scoresFile, scoresPath] = uigetfile('*.csv', 'Seleziona pca_scores_all.csv (o simile)');
if isequal(scoresFile,0), return; end
scoresCsv = fullfile(scoresPath, scoresFile);

outDir = uigetdir(scoresPath, 'Seleziona cartella OUTPUT (baseline)');
if isequal(outDir,0), outDir = scoresPath; end
if ~isfolder(outDir); mkdir(outDir); end

%% ===== LOAD ROBUST (header sì/no) =====
fid = fopen(scoresCsv, 'r');
firstLine = fgetl(fid);
fclose(fid);

hasHeader = contains(lower(string(firstLine)), "pc1");

if hasHeader
    Scores = readtable(scoresCsv, 'Delimiter', ',', 'TextType', 'string');
else
    Scores = readtable(scoresCsv, 'Delimiter', ',', 'TextType', 'string', 'ReadVariableNames', false);
    if width(Scores) < 2
        error("CSV senza header con %d colonne: attese almeno 2 (PC1, PC2).", width(Scores));
    end
    Scores = Scores(:,1:2);
    Scores.Properties.VariableNames = {'PC1','PC2'};
end

%% ===== CHECK COLONNE =====
requiredCols = ["PC1","PC2"];
missing = setdiff(requiredCols, string(Scores.Properties.VariableNames));
if ~isempty(missing)
    error("Mancano colonne nel CSV: %s", strjoin(missing,", "));
end

%% ===== ESTRAI PC1/PC2 =====
PC1 = Scores.PC1; if ~isnumeric(PC1), PC1 = str2double(string(PC1)); end
PC2 = Scores.PC2; if ~isnumeric(PC2), PC2 = str2double(string(PC2)); end

% tieni solo punti finiti
valid = isfinite(PC1) & isfinite(PC2);
PC1 = PC1(valid);
PC2 = PC2(valid);

n = numel(PC1);
if n < 10
    error("Troppi pochi punti validi (%d).", n);
end

%% ===== STATS (SOLO MEAN/STD) =====
pc1_mean = mean(PC1,'omitnan');
pc1_std  = std(PC1,'omitnan');

pc2_mean = mean(PC2,'omitnan');
pc2_std  = std(PC2,'omitnan');

%% ===== OUTPUT TABLE (FORMATO GUI) =====
StatsBoth = table(pc1_mean, pc1_std, pc2_mean, pc2_std, ...
    'VariableNames', {'PC1_mean_of_points','PC1_std_of_points','PC2_mean_of_points','PC2_std_of_points'});

writetable(StatsBoth, fullfile(outDir,"baseline_PC1_PC2_stats.csv"));

%% ===== DEBUG (opzionali) =====
writetable(table(PC1), fullfile(outDir,"baseline_PC1_values.csv"));
writetable(table(PC2), fullfile(outDir,"baseline_PC2_values.csv"));

%% ===== LOG =====
fprintf("\n=== BASELINE PCA (POINTWISE, mean/std) ===\n");
fprintf("N punti validi = %d\n", n);
fprintf("PC1 mean/std = %.6f / %.6f\n", pc1_mean, pc1_std);
fprintf("PC2 mean/std = %.6f / %.6f\n", pc2_mean, pc2_std);
fprintf("\nSaved:\n  %s\n\n", fullfile(outDir,"baseline_PC1_PC2_stats.csv"));

end