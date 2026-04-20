%% ELLONA_08_pca_baseline_lod.m
% Pipeline PCA + LOD per event detection su dati di monitoraggio ELLONA.
%
% Pipeline:
%   1. Carica monitoring_all.mat (output di ELLONA_07)
%   2. Selezione baseline via intersezione [P95, P99] per ciascun MOX
%      su base giornaliera (configurabile: 'daily'|'weekly'|'monthly'|'global')
%   3. PCA su baseline — predictors: cmos1-4 + temperature + humidity
%   4. Loading plot + verifica quantitativa ortogonalità T/RH vs PC1
%   5. Definizione LOD: μ ± k·σ su PC1 della baseline
%   6. Proiezione di tutti i dati → PC1(t), PC2(t)
%   7. Plot overview + salvataggio modello e stats
%   8. Confronto baseline: daily | weekly | monthly | global
%
% Output: IREN/output/event_detection/
%   - pca_model_ELLONA.mat
%   - baseline_stats_ELLONA.csv       (compatibile con GUI viewer)
%   - pca_loadings.csv
%   - pca_loadings_baseline.png
%   - pca_scree.png
%   - PC1_overview.png
%   - PC2_overview.png
%   - baseline_comparison.png
%
% Marco Calì — PoliMi, Aprile 2026
% Richiede: ellona_select_baseline.m (nella stessa cartella)

clear; clc; close all;

%% ===== CONFIG =====
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');

dataFile  = fullfile(baseDir, 'data', 'processed', 'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'event_detection');
if ~isfolder(outDir), mkdir(outDir); end

% --- Predictors ---
moxCols    = ["cmos1","cmos2","cmos3","cmos4"];   % usati per selezione baseline E PCA
envCols    = ["temperature","humidity"];           % tenuti per verifica a posteriori
predictors = moxCols;                             % SOLO MOX nella PCA
% Motivazione: T e RH includono variabilità stagionale co-variata con i MOX
% → caricano su PC1 distorcendo l'interpretazione. Si verifica a posteriori
% che corr(PC1, T) e corr(PC1, RH) siano bassi (buona separazione).
nPred      = numel(predictors);
nMox       = numel(moxCols);

% --- Parametri baseline ---
baselineMode = 'weekly';    % 'daily' | 'weekly' | 'monthly' | 'global'
pLow         = 25;         % percentile inferiore della banda (IQR lower)
pHigh        = 75;         % percentile superiore (IQR upper)
% Giustificazione: assumento odori < 10% del tempo, anche il P25 cade in
% aria pulita. L'IQR [P25,P75] cattura il comportamento tipico del sistema
% in condizioni normali, robusto a drift e outlier estremi (es. cmos4).
minBandPts   = 20;         % min punti nella banda per validare il periodo

% --- LOD ---
k_lod  = 3;              % LOD = μ ± k·σ  (tipicamente 3–6)

% --- Output ---
nPC_keep = 3;              % componenti da salvare nel modello

%% ===== LOAD DATI =====
fprintf('Caricamento dati...\n');
t0 = tic;
load(dataFile, 'DATA');
nRows = height(DATA);
fprintf('  Righe: %d  |  %s --> %s  (%.1fs)\n\n', nRows, ...
    datestr(DATA.datetime(1),'dd-mmm-yyyy'), ...
    datestr(DATA.datetime(end),'dd-mmm-yyyy'), toc(t0));

% Estrai matrici sensori
X_mox = DATA{:, cellstr(moxCols)};    % N x 4  (solo MOX per baseline)
X_all = DATA{:, cellstr(predictors)}; % N x 6  (per PCA)

% Imputazione NaN residui (mediana colonna) — per robustezza proiezione
for j = 1:nPred
    nanMask = isnan(X_all(:,j));
    if any(nanMask)
        X_all(nanMask,j) = median(X_all(~nanMask,j));
    end
end

%% ===== SELEZIONE BASELINE =====
fprintf('--- Selezione baseline [P%d, P%d] | mode: %s ---\n', pLow, pHigh, baselineMode);
t1 = tic;
[isBaseline, R0_rows, P95_rows, P99_rows] = ellona_select_baseline( ...
    X_mox, DATA.datetime, pLow, pHigh, minBandPts, baselineMode);
nBL   = sum(isBaseline);
pctBL = 100 * nBL / nRows;
fprintf('  Punti baseline: %d / %d (%.1f%%)  (%.1fs)\n\n', nBL, nRows, pctBL, toc(t1));

if nBL < 500
    warning(['Pochi punti baseline (%d). ' ...
        'Prova baselineMode=''global'' o aumenta pHigh.'], nBL);
end

%% ===== MODELLO PCA SU BASELINE =====
fprintf('--- PCA su baseline (%d punti, %d predictors) ---\n', nBL, nPred);

X_bl = X_all(isBaseline, :);   % N_bl x 6

% Standardizzazione z-score calcolata SOLO sulla baseline
mu    = mean(X_bl, 1, 'omitnan');
sigma = std( X_bl, 0, 1, 'omitnan');
sigma(sigma == 0 | isnan(sigma)) = 1;

X_bl_z = (X_bl - mu) ./ sigma;

% PCA (MATLAB centra internamente; muPCA ≈ 0 perché X_bl_z già centrata,
%      ma va salvata per coerenza nelle proiezioni)
[coeff, score_bl, latent, ~, explained, muPCA] = pca(X_bl_z);

nPC = min(nPC_keep, size(coeff, 2));

fprintf('\n  Varianza spiegata:\n');
for i = 1:nPC
    fprintf('    PC%d: %5.1f%%   (cumulativa: %5.1f%%)\n', ...
        i, explained(i), sum(explained(1:i)));
end
fprintf('\n');

%% ===== LOADING PLOT =====
fprintf('--- Generazione loading plot ---\n');

% Palette colori: MOX=blu (ora solo 4 vettori)
cmap = containers.Map( ...
    {'cmos1','cmos2','cmos3','cmos4'}, ...
    {[0.15 0.35 0.75],[0.15 0.35 0.75],[0.15 0.35 0.75],[0.15 0.35 0.75]});

th = linspace(0, 2*pi, 200);   % cerchio unitario

fig_load = figure('Name','PCA Loadings — Baseline ELLONA', ...
    'Color','w', 'Position',[80 80 1200 520]);

pairs = [1 2; 1 3];   % coppie PC da plottare
for sp = 1:2
    if pairs(sp,2) > nPC, continue; end
    pcx = pairs(sp,1);  pcy = pairs(sp,2);

    subplot(1,2,sp); hold on; grid on; axis equal; box on;

    % Cerchio di riferimento
    plot(cos(th), sin(th), '--', 'Color',[0.78 0.78 0.78], 'LineWidth',1);

    % Vettori loading
    for k = 1:nPred
        pname = char(predictors(k));
        clr   = cmap(pname);
        quiver(0, 0, coeff(k,pcx), coeff(k,pcy), 0, ...
            'Color',clr, 'LineWidth',2.0, 'MaxHeadSize',0.35);
        text(coeff(k,pcx)*1.14, coeff(k,pcy)*1.14, pname, ...
            'Color',clr, 'FontSize',10, 'FontWeight','bold', ...
            'HorizontalAlignment','center');
    end

    xlabel(sprintf('PC%d (%.1f%%)', pcx, explained(pcx)), 'FontSize',11);
    ylabel(sprintf('PC%d (%.1f%%)', pcy, explained(pcy)), 'FontSize',11);
    title(sprintf('Loadings PC%d vs PC%d', pcx, pcy), 'FontSize',12);
    xlim([-1.35 1.35]); ylim([-1.35 1.35]);

    if sp == 1
        h1 = plot(nan,nan,'s','Color',[0.15 0.35 0.75],'MarkerFaceColor',[0.15 0.35 0.75]);
        legend(h1, {'cmos1–4 (MOX)'}, 'Location','southwest','FontSize',9);
    end
end
sgtitle(sprintf('PCA Loadings — Baseline ELLONA (%s, N=%d)', baselineMode, nBL), ...
    'FontSize',13,'FontWeight','bold');

exportgraphics(fig_load, fullfile(outDir,'pca_loadings_baseline.png'), 'Resolution',300);
fprintf('  Salvato: pca_loadings_baseline.png\n');

%% ===== ANALISI QUANTITATIVA ORTOGONALITÀ T/RH vs PC1 =====
fprintf('\n--- Ortogonalità T/RH rispetto a PC1 ---\n');

% T/RH sono esclusi dai predictors per design (no co-varianza stagionale in PCA).
% L'ortogonalità è verificata a posteriori tramite correlazione PC1(t) vs T/RH
% nella sezione successiva. Angoli sui loadings non applicabili (variabili assenti).
hasEnvInPCA = any(ismember(predictors, envCols));
if hasEnvInPCA
    fprintf('  %-14s  %+9s  %+9s  %+10s  %9s\n', ...
        'Variabile','load_PC1','load_PC2','load_PC3','ang_vs_PC1');
    fprintf('  %s\n', repmat('-',58,1));
    for vname = envCols
        idx_v = find(predictors == vname);
        if isempty(idx_v), continue; end
        lvec   = coeff(idx_v, 1:nPC);
        pc1_ax = [1 zeros(1, nPC-1)];
        ang    = acosd(abs(dot(lvec, pc1_ax)) / (norm(lvec) * norm(pc1_ax)));
        fprintf('  %-14s  %+9.4f  %+9.4f  %+10.4f  %8.1f°\n', ...
            vname, coeff(idx_v,1), coeff(idx_v,2), coeff(idx_v,min(3,nPC)), ang);
    end
    fprintf('  [Comportamento atteso: angolo ~90° → T/RH ortogonali a PC1]\n');
else
    fprintf('  T/RH esclusi dai predictors per design → nessun loading da verificare.\n');
    fprintf('  Verifica a posteriori via correlazione PC1(t) vs T/RH (sezione sotto).\n');
end
fprintf('\n');

%% ===== SCREE PLOT =====
fig_scree = figure('Name','Scree Plot — Baseline ELLONA', ...
    'Color','w', 'Position',[100 100 600 380]);
yyaxis left
bar(1:nPred, explained, 'FaceColor',[0.15 0.35 0.75], 'FaceAlpha',0.8);
ylabel('Varianza spiegata singola PC (%)', 'FontSize',11);
yyaxis right
plot(1:nPred, cumsum(explained), '-o', 'Color',[0.80 0.15 0.10], ...
    'LineWidth',2, 'MarkerFaceColor',[0.80 0.15 0.10]);
ylabel('Varianza cumulativa (%)', 'FontSize',11);
xlabel('Componente Principale', 'FontSize',11);
title('Scree Plot — Baseline ELLONA', 'FontSize',12);
grid on; xlim([0.5 nPred+0.5]);
exportgraphics(fig_scree, fullfile(outDir,'pca_scree.png'), 'Resolution',300);

%% ===== LOD DA BASELINE SCORES =====
fprintf('--- Definizione LOD (k = %.1f) ---\n', k_lod);

pc1_bl = score_bl(:, 1);
pc2_bl = score_bl(:, 2);

mu_pc1    = mean(pc1_bl, 'omitnan');
sigma_pc1 = std( pc1_bl, 'omitnan');
mu_pc2    = mean(pc2_bl, 'omitnan');
sigma_pc2 = std( pc2_bl, 'omitnan');

lod_upper_pc1 = mu_pc1 + k_lod * sigma_pc1;
lod_lower_pc1 = mu_pc1 - k_lod * sigma_pc1;
lod_upper_pc2 = mu_pc2 + k_lod * sigma_pc2;
lod_lower_pc2 = mu_pc2 - k_lod * sigma_pc2;

fprintf('  PC1: μ=%+.4f  σ=%.4f  LOD=[%+.4f, %+.4f]\n', ...
    mu_pc1, sigma_pc1, lod_lower_pc1, lod_upper_pc1);
fprintf('  PC2: μ=%+.4f  σ=%.4f  LOD=[%+.4f, %+.4f]\n\n', ...
    mu_pc2, sigma_pc2, lod_lower_pc2, lod_upper_pc2);

%% ===== PROIEZIONE DI TUTTI I DATI =====
fprintf('--- Proiezione dati completi (%d righe) ---\n', nRows);
t2 = tic;

X_all_z    = (X_all - mu) ./ sigma;
scores_all = (X_all_z - muPCA) * coeff;   % N x nPred
PC1_all    = scores_all(:, 1);
PC2_all    = scores_all(:, 2);

fprintf('  Completata in %.1f s\n', toc(t2));

% Flag eventi su PC1
isEvent = PC1_all < lod_lower_pc1;   % risposta MOX NEGATIVA → scende sotto LOD_lower
nEvt    = sum(isEvent);
fprintf('  Superamenti LOD- su PC1: %d punti (%.2f%%)\n\n', ...
    nEvt, 100*nEvt/nRows);

%% ===== VERIFICA A POSTERIORI: correlazione PC1 vs T e RH =====
fprintf('--- Verifica correlazione PC1(t) vs variabili ambientali ---\n');
T_col  = DATA.temperature;
RH_col = DATA.humidity;

% Correlazione di Pearson su tutti i dati
r_T  = corr(PC1_all, T_col,  'rows','complete');
r_RH = corr(PC1_all, RH_col, 'rows','complete');

% Correlazione solo sulla baseline (più indicativa del modello)
r_T_bl  = corr(PC1_all(isBaseline), T_col(isBaseline),  'rows','complete');
r_RH_bl = corr(PC1_all(isBaseline), RH_col(isBaseline), 'rows','complete');

fprintf('  %-12s  r(tutti)=%+.3f   r(baseline)=%+.3f\n', 'PC1 vs T',  r_T,  r_T_bl);
fprintf('  %-12s  r(tutti)=%+.3f   r(baseline)=%+.3f\n', 'PC1 vs RH', r_RH, r_RH_bl);

if abs(r_T_bl) < 0.3 && abs(r_RH_bl) < 0.3
    fprintf('  → Buona separazione: PC1 è quasi indipendente da T e RH.\n\n');
elseif abs(r_T_bl) < 0.5 && abs(r_RH_bl) < 0.5
    fprintf('  → Correlazione moderata: PC1 ha ancora influenza ambientale residua.\n\n');
else
    fprintf('  → ATTENZIONE: PC1 è significativamente correlato con T o RH.\n');
    fprintf('    Considerare compensazione termica o uso di PC2+ per la detection.\n\n');
end

% Scatter plot PC1 vs T e RH (sulla baseline)
fig_corr = figure('Name','PC1 vs T/RH (baseline)', 'Color','w', 'Position',[100 100 900 400]);
subplot(1,2,1);
scatter(T_col(isBaseline), PC1_all(isBaseline), 2, [0.15 0.35 0.75], 'filled', 'MarkerFaceAlpha',0.15);
grid on; xlabel('Temperature (°C)','FontSize',11); ylabel('PC_1','FontSize',11);
title(sprintf('PC_1 vs T  (r=%.3f, baseline)', r_T_bl),'FontSize',11);
lsline;

subplot(1,2,2);
scatter(RH_col(isBaseline), PC1_all(isBaseline), 2, [0.05 0.55 0.20], 'filled', 'MarkerFaceAlpha',0.15);
grid on; xlabel('Humidity (%RH)','FontSize',11); ylabel('PC_1','FontSize',11);
title(sprintf('PC_1 vs RH  (r=%.3f, baseline)', r_RH_bl),'FontSize',11);
lsline;

sgtitle('Verifica indipendenza PC_1 da variabili ambientali','FontSize',12,'FontWeight','bold');
exportgraphics(fig_corr, fullfile(outDir,'PC1_vs_TRH_correlation.png'), 'Resolution',300);
fprintf('  Salvato: PC1_vs_TRH_correlation.png\n\n');

%% ===== PLOT PC1(t) OVERVIEW (pannello doppio: full + zoom LOD) =====
fig_pc1 = figure('Name','PC1(t) — ELLONA', 'Color','w', 'Position',[80 80 1600 680]);
sgtitle(sprintf('PC_1(t) — ELLONA  |  k=%.0f, baseline=%s  |  eventi LOD-: %.2f%%', ...
    k_lod, baselineMode, 100*nEvt/nRows), 'FontSize',13, 'FontWeight','bold');

% ----- Pannello superiore: overview completo -----
ax1 = subplot(2,1,1);
hold(ax1,'on');
plot(ax1, DATA.datetime, PC1_all, '-', 'Color',[0.65 0.75 0.9], 'LineWidth',0.3);
plot(ax1, DATA.datetime(isBaseline), PC1_all(isBaseline), '.', ...
    'Color',[0.10 0.55 0.15], 'MarkerSize',2);
plot(ax1, DATA.datetime(isEvent), PC1_all(isEvent), '.', ...
    'Color',[0.82 0.18 0.10], 'MarkerSize',3);
yline(ax1, lod_upper_pc1, '-', sprintf('LOD+ = %.3f', lod_upper_pc1), ...
    'Color',[0.10 0.65 0.10], 'LineWidth',2.0, 'LabelHorizontalAlignment','left','FontSize',9);
yline(ax1, lod_lower_pc1, '-', sprintf('LOD− = %.3f', lod_lower_pc1), ...
    'Color',[0.10 0.65 0.10], 'LineWidth',2.0, 'LabelHorizontalAlignment','left','FontSize',9);
yline(ax1, mu_pc1, '--', sprintf('μ_{BL} = %.3f', mu_pc1), ...
    'Color',[0.45 0.45 0.45], 'LineWidth',1.0);
xlabel(ax1, 'Data', 'FontSize',10);
ylabel(ax1, 'PC_1(t)', 'FontSize',10);
grid(ax1, 'on');
legend(ax1, {'PC_1(t)','Baseline','Evento'}, 'Location','northeast','FontSize',8);
title(ax1, 'Overview completo (scala reale)', 'FontSize',11);

% ----- Pannello inferiore: zoom sulla banda LOD -----
ax2 = subplot(2,1,2);
hold(ax2,'on');

zoomLim  = 5 * sigma_pc1;   % ±5σ_pc1 ≈ ±6.6 in units di score

% Punti entro la finestra di zoom (baseline + segnale regolare)
mask_zoom = abs(PC1_all) <= zoomLim;
plot(ax2, DATA.datetime(mask_zoom), PC1_all(mask_zoom), '-', ...
    'Color',[0.65 0.75 0.9], 'LineWidth',0.3);
plot(ax2, DATA.datetime(isBaseline), PC1_all(isBaseline), '.', ...
    'Color',[0.10 0.55 0.15], 'MarkerSize',2);

% Eventi "vicini" (tra LOD- e -10σ): triangolo pieno rosso
mask_evt_near = isEvent & (PC1_all >= -10*sigma_pc1);
if any(mask_evt_near)
    plot(ax2, DATA.datetime(mask_evt_near), PC1_all(mask_evt_near), 'v', ...
        'Color',[0.82 0.18 0.10], 'MarkerSize',4, 'MarkerFaceColor',[0.82 0.18 0.10]);
end
% Eventi profondi (< -10σ): clampa al bordo con triangolo scuro
mask_evt_deep = isEvent & (PC1_all < -10*sigma_pc1);
if any(mask_evt_deep)
    plot(ax2, DATA.datetime(mask_evt_deep), repmat(-zoomLim*0.93, sum(mask_evt_deep), 1), 'v', ...
        'Color',[0.55 0.08 0.04], 'MarkerSize',5, 'MarkerFaceColor',[0.55 0.08 0.04]);
end

yline(ax2, lod_upper_pc1, '-', sprintf('LOD+ = %.3f', lod_upper_pc1), ...
    'Color',[0.10 0.65 0.10], 'LineWidth',2.0, 'LabelHorizontalAlignment','left','FontSize',9);
yline(ax2, lod_lower_pc1, '-', sprintf('LOD− = %.3f', lod_lower_pc1), ...
    'Color',[0.10 0.65 0.10], 'LineWidth',2.0, 'LabelHorizontalAlignment','left','FontSize',9);
yline(ax2, mu_pc1, '--', sprintf('μ_{BL} = %.3f', mu_pc1), ...
    'Color',[0.45 0.45 0.45], 'LineWidth',1.0);
xlabel(ax2, 'Data', 'FontSize',10);
ylabel(ax2, 'PC_1(t)', 'FontSize',10);
grid(ax2, 'on');
ylim(ax2, [-zoomLim zoomLim]);
title(ax2, sprintf('Zoom banda LOD (±%.0fσ_{PC1} = ±%.2f)  — ▼ = evento (scuro = molto profondo)', ...
    round(zoomLim/sigma_pc1), zoomLim), 'FontSize',11);

exportgraphics(fig_pc1, fullfile(outDir,'PC1_overview.png'), 'Resolution',300);
fprintf('Salvato: PC1_overview.png\n');

%% ===== PLOT PC2(t) OVERVIEW =====
isEvent_pc2 = PC2_all < lod_lower_pc2 | PC2_all > lod_upper_pc2;
fig_pc2 = figure('Name','PC2(t) — ELLONA', 'Color','w', 'Position',[80 80 1400 400]);
hold on; grid on;
plot(DATA.datetime, PC2_all, '-', 'Color',[0.75 0.70 0.90], 'LineWidth',0.35);
plot(DATA.datetime(isEvent_pc2), PC2_all(isEvent_pc2), '.', ...
    'Color',[0.60 0.10 0.65], 'MarkerSize',3);
yline(lod_upper_pc2, '-', sprintf('LOD+ = %.3f',lod_upper_pc2), ...
    'Color',[0.50 0.10 0.55],'LineWidth',2);
yline(lod_lower_pc2, '-', sprintf('LOD- = %.3f',lod_lower_pc2), ...
    'Color',[0.50 0.10 0.55],'LineWidth',2);
yline(mu_pc2, '--', sprintf('μ_{BL} = %.3f',mu_pc2), ...
    'Color',[0.45 0.45 0.45],'LineWidth',1.2);
xlabel('Data','FontSize',11); ylabel('PC_2(t)','FontSize',11);
title(sprintf('PC_2(t) — ELLONA  |  k=%.0f, baseline=%s', k_lod, baselineMode),'FontSize',12);
exportgraphics(fig_pc2, fullfile(outDir,'PC2_overview.png'), 'Resolution',300);

%% ===== SALVATAGGIO MODELLO =====
modelFile = fullfile(outDir, 'pca_model_ELLONA.mat');
save(modelFile, ...
    'mu','sigma','muPCA','coeff','explained','latent','predictors', ...
    'moxCols','envCols','nPC', ...
    'mu_pc1','sigma_pc1','lod_lower_pc1','lod_upper_pc1', ...
    'mu_pc2','sigma_pc2','lod_lower_pc2','lod_upper_pc2', ...
    'k_lod','pLow','pHigh','baselineMode','nBL','pctBL');
fprintf('\nModello PCA salvato: %s\n', modelFile);

% Baseline stats CSV — formato compatibile con GUI (BATCH_GUI_PC1_PC2_LOD_VIEWER)
statsTable = table( ...
    mu_pc1, sigma_pc1, mu_pc2, sigma_pc2, ...
    'VariableNames', { ...
    'PC1_mean_of_medians','PC1_std_of_medians', ...
    'PC2_mean_of_medians','PC2_std_of_medians'});
statsFile = fullfile(outDir, 'baseline_stats_ELLONA.csv');
writetable(statsTable, statsFile);
fprintf('Baseline stats (GUI-compatibile): %s\n', statsFile);

% Loadings CSV
LoadT = table(cellstr(predictors)', coeff(:,1), coeff(:,2), coeff(:,3), ...
    'VariableNames', {'Variable','PC1','PC2','PC3'});
writetable(LoadT, fullfile(outDir,'pca_loadings.csv'));

%% ===== CONFRONTO BASELINE MODES =====
fprintf('\n======== CONFRONTO BASELINE MODES ========\n');
fprintf('%-8s  %8s  %6s  %9s  %10s  %9s\n', ...
    'Mode','N_bl','%_bl','PC1_expl%','LOD_range','Event%');
fprintf('%s\n', repmat('-',58,1));

modes_cmp = {'daily','weekly','monthly','global'};
T_cmp = table('Size',[numel(modes_cmp),6], ...
    'VariableTypes',{'string','double','double','double','double','double'}, ...
    'VariableNames',{'Mode','N_baseline','Pct_baseline','PC1_explained','LOD_range','Event_pct'});

for m = 1:numel(modes_cmp)
    bm = modes_cmp{m};
    [isBL_m, ~, ~, ~] = ellona_select_baseline( ...
        X_mox, DATA.datetime, pLow, pHigh, minBandPts, bm);
    nBL_m = sum(isBL_m);
    if nBL_m < 100
        fprintf('  %-8s  [SKIP: %d punti insufficienti]\n', bm, nBL_m);
        continue;
    end
    X_m  = X_all(isBL_m,:);
    mu_m = mean(X_m,1,'omitnan');
    sg_m = std(X_m,0,1,'omitnan');
    sg_m(sg_m==0|isnan(sg_m)) = 1;
    [coeff_m, scr_m, ~, ~, expl_m, muPCA_m] = pca((X_m-mu_m)./sg_m);

    mu_p1_m  = mean(scr_m(:,1),'omitnan');
    sg_p1_m  = std(scr_m(:,1),'omitnan');
    lod_lo_m = mu_p1_m - k_lod*sg_p1_m;
    lod_hi_m = mu_p1_m + k_lod*sg_p1_m;

    Xaz_m    = (X_all - mu_m) ./ sg_m;
    sc_all_m = (Xaz_m - muPCA_m) * coeff_m;
    evt_m    = mean(sc_all_m(:,1) < lod_lo_m) * 100;   % solo LOD- (risposta MOX negativa)

    T_cmp.Mode(m)          = string(bm);
    T_cmp.N_baseline(m)    = nBL_m;
    T_cmp.Pct_baseline(m)  = 100*nBL_m/nRows;
    T_cmp.PC1_explained(m) = expl_m(1);
    T_cmp.LOD_range(m)     = 2*k_lod*sg_p1_m;
    T_cmp.Event_pct(m)     = evt_m;
    fprintf('  %-8s  %8d  %5.1f%%  %9.1f%%  %10.4f  %8.2f%%\n', ...
        bm, nBL_m, 100*nBL_m/nRows, expl_m(1), 2*k_lod*sg_p1_m, evt_m);
end

% Plot confronto eventi %
fig_cmp = figure('Name','Confronto Baseline Modes','Color','w','Position',[100 100 700 380]);
valid_rows = T_cmp.N_baseline > 0;
bar(categorical(T_cmp.Mode(valid_rows)), T_cmp.Event_pct(valid_rows), ...
    'FaceColor',[0.15 0.35 0.75],'FaceAlpha',0.85);
grid on; ylabel('% punti fuori LOD','FontSize',11);
xlabel('Baseline mode','FontSize',11);
title(sprintf('Confronto % eventi per baseline mode (k=%.0f)', k_lod),'FontSize',12);
exportgraphics(fig_cmp, fullfile(outDir,'baseline_comparison.png'), 'Resolution',300);
writetable(T_cmp(valid_rows,:), fullfile(outDir,'baseline_comparison.csv'));

fprintf('\n===== COMPLETATO =====\n');
fprintf('Output in: %s\n', outDir);
