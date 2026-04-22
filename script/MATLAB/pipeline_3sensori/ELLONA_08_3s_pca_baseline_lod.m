%% ELLONA_08_3s_pca_baseline_lod.m
% Versione 3 sensori (cmos1, cmos2, cmos3) — cmos4 ESCLUSO.
%
% Motivazione esclusione cmos4 (ELLONA_13/14/15):
%   - Deriva stagionale ×59 non spiegata da T, RH, AH (R²≈0 su tutti i modelli)
%   - Loading negativo (−0.336) attenua PC1 durante gli eventi reali
%   - Genera il 67% di falsi positivi stagionali extra
%   - Comportamento incompatibile con sensore MOX per VOC riducenti
%
% Identico a ELLONA_08 salvo:
%   - moxCols = ["cmos1","cmos2","cmos3"]
%   - outDir  = output/event_detection_3s/
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ===== CONFIG =====
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..', '..');   % → IREN/
addpath(fullfile(scriptDir, '..'));                   % ellona_select_baseline.m

dataFile  = fullfile(baseDir, 'data', 'processed', 'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'event_detection_3s');
if ~isfolder(outDir), mkdir(outDir); end

% --- 3 sensori: cmos4 ESCLUSO ---
moxCols    = ["cmos1","cmos2","cmos3"];
envCols    = ["temperature","humidity"];
predictors = moxCols;
nPred      = numel(predictors);
nMox       = numel(moxCols);

% --- Parametri baseline ---
baselineMode = 'weekly';
pLow         = 25;
pHigh        = 75;
minBandPts   = 20;

% --- LOD ---
k_lod    = 3;
nPC_keep = 3;

%% ===== LOAD DATI =====
fprintf('Caricamento dati...\n');
t0 = tic;
load(dataFile, 'DATA');
nRows = height(DATA);
fprintf('  Righe: %d  |  %s --> %s  (%.1fs)\n\n', nRows, ...
    datestr(DATA.datetime(1),'dd-mmm-yyyy'), ...
    datestr(DATA.datetime(end),'dd-mmm-yyyy'), toc(t0));

X_mox = DATA{:, cellstr(moxCols)};
X_all = DATA{:, cellstr(predictors)};

for j = 1:nPred
    nanMask = isnan(X_all(:,j));
    if any(nanMask), X_all(nanMask,j) = median(X_all(~nanMask,j)); end
end

%% ===== SELEZIONE BASELINE =====
fprintf('--- Selezione baseline [P%d, P%d] | mode: %s ---\n', pLow, pHigh, baselineMode);
t1 = tic;
[isBaseline, ~, ~, ~] = ellona_select_baseline( ...
    X_mox, DATA.datetime, pLow, pHigh, minBandPts, baselineMode);
nBL   = sum(isBaseline);
pctBL = 100 * nBL / nRows;
fprintf('  Punti baseline: %d / %d (%.1f%%)  (%.1fs)\n\n', nBL, nRows, pctBL, toc(t1));

if nBL < 500
    warning('Pochi punti baseline (%d).', nBL);
end

%% ===== PCA SU BASELINE =====
fprintf('--- PCA su baseline (%d punti, %d sensori) ---\n', nBL, nPred);

X_bl   = X_all(isBaseline, :);
mu     = mean(X_bl, 1, 'omitnan');
sigma  = std( X_bl, 0, 1, 'omitnan');
sigma(sigma == 0 | isnan(sigma)) = 1;
X_bl_z = (X_bl - mu) ./ sigma;

[coeff, score_bl, latent, ~, explained, muPCA] = pca(X_bl_z);
nPC = min(nPC_keep, size(coeff, 2));

fprintf('\n  Varianza spiegata:\n');
for i = 1:nPC
    fprintf('    PC%d: %5.1f%%   (cumulativa: %5.1f%%)\n', ...
        i, explained(i), sum(explained(1:i)));
end
fprintf('\n');

%% ===== VARIABILI SUPPLEMENTARI: T e RH =====
% T e RH non entrano nella PCA per design.
% Le proiettiamo come variabili supplementari nel cerchio dei loading:
%   r_supp(k) = corr(v_z_baseline, PC_k_score_baseline)
% Questo è il loading "virtuale" — mostra dove atterrano nel biplot.
% Se r_supp(PC1) ≈ 0 → variabile ortogonale a PC1 → buona separazione.

T_bl_z  = (DATA.temperature(isBaseline)  - mean(DATA.temperature(isBaseline),'omitnan')) ...
           / std(DATA.temperature(isBaseline),'omitnan');
RH_bl_z = (DATA.humidity(isBaseline)     - mean(DATA.humidity(isBaseline),'omitnan')) ...
           / std(DATA.humidity(isBaseline),'omitnan');

supp_names = {'T','RH'};
supp_clrs  = {[0.85 0.33 0.10], [0.13 0.55 0.13]};   % arancio, verde
supp_loads = nan(2, nPC);
for s = 1:2
    v = [T_bl_z, RH_bl_z];
    for k = 1:nPC
        supp_loads(s,k) = corr(v(:,s), score_bl(:,k), 'rows','complete');
    end
end

fprintf('--- Loadings supplementari (T, RH) ---\n');
fprintf('  %-5s  %8s  %8s  %8s\n', 'Var', 'PC1', 'PC2', 'PC3');
for s = 1:2
    fprintf('  %-5s  %+8.4f  %+8.4f  %+8.4f\n', ...
        supp_names{s}, supp_loads(s,1), supp_loads(s,2), supp_loads(s,3));
end
fprintf('\n');

%% ===== LOADING PLOT (con variabili supplementari) =====
fprintf('--- Loading plot ---\n');

clr_mox = [0.15 0.35 0.75];
th = linspace(0, 2*pi, 200);

fig_load = figure('Name','PCA Loadings — 3 sensori + T/RH supplementari', ...
    'Color','w', 'Position',[80 80 1200 520]);

pairs = [1 2; 1 3];
for sp = 1:2
    if pairs(sp,2) > nPC, continue; end
    pcx = pairs(sp,1); pcy = pairs(sp,2);
    ax = subplot(1,2,sp); hold on; grid on; axis equal; box on;

    % Cerchio unitario
    plot(cos(th), sin(th), '--', 'Color',[0.78 0.78 0.78], 'LineWidth',1);

    % Frecce MOX (variabili attive)
    for k = 1:nPred
        quiver(0, 0, coeff(k,pcx), coeff(k,pcy), 0, ...
            'Color', clr_mox, 'LineWidth',2.2, 'MaxHeadSize',0.35);
        text(coeff(k,pcx)*1.14, coeff(k,pcy)*1.14, char(predictors(k)), ...
            'Color', clr_mox, 'FontSize',10, 'FontWeight','bold', ...
            'HorizontalAlignment','center');
    end

    % Frecce supplementari T e RH (tratteggiate, colore diverso)
    for s = 1:2
        lx = supp_loads(s, pcx);
        ly = supp_loads(s, pcy);
        clr_s = supp_clrs{s};
        quiver(0, 0, lx, ly, 0, ...
            'Color', clr_s, 'LineWidth',2.2, 'MaxHeadSize',0.35, ...
            'LineStyle','--');
        % offset testo per non sovrapporsi
        off = 1.16;
        text(lx*off, ly*off, supp_names{s}, ...
            'Color', clr_s, 'FontSize',10, 'FontWeight','bold', ...
            'HorizontalAlignment','center');
        % annotazione r(PC1) solo sul panel PC1 vs PC2
        if sp == 1 && pcx == 1
            text(lx*off, ly*off - 0.12, sprintf('r_{PC1}=%+.2f', lx), ...
                'Color', clr_s, 'FontSize',8, ...
                'HorizontalAlignment','center');
        end
    end

    xlabel(sprintf('PC%d (%.1f%%)', pcx, explained(pcx)), 'FontSize',11);
    ylabel(sprintf('PC%d (%.1f%%)', pcy, explained(pcy)), 'FontSize',11);
    title(sprintf('Loadings PC%d vs PC%d', pcx, pcy), 'FontSize',12);
    xlim([-1.35 1.35]); ylim([-1.35 1.35]);

    if sp == 1
        h1 = plot(nan,nan,'s','Color',clr_mox,'MarkerFaceColor',clr_mox,'MarkerSize',8);
        h2 = plot(nan,nan,'--','Color',supp_clrs{1},'LineWidth',2);
        h3 = plot(nan,nan,'--','Color',supp_clrs{2},'LineWidth',2);
        legend([h1,h2,h3], {'cmos1–3 (attivi)','T (suppl.)','RH (suppl.)'}, ...
            'Location','southwest','FontSize',9);
    end
end
sgtitle(sprintf('PCA Loadings — 3 sensori  +  T/RH supplementari (%s, N=%d)', ...
    baselineMode, nBL), 'FontSize',13, 'FontWeight','bold');
exportgraphics(fig_load, fullfile(outDir,'pca_loadings_baseline.png'), 'Resolution',300);

%% ===== SCREE PLOT =====
fig_scree = figure('Name','Scree Plot — 3 sensori', 'Color','w', 'Position',[100 100 600 380]);
yyaxis left
bar(1:nPred, explained, 'FaceColor',[0.15 0.35 0.75], 'FaceAlpha',0.8);
ylabel('Varianza spiegata singola PC (%)','FontSize',11);
yyaxis right
plot(1:nPred, cumsum(explained), '-o', 'Color',[0.80 0.15 0.10], ...
    'LineWidth',2, 'MarkerFaceColor',[0.80 0.15 0.10]);
ylabel('Varianza cumulativa (%)','FontSize',11);
xlabel('Componente Principale','FontSize',11);
title('Scree Plot — 3 sensori','FontSize',12);
grid on; xlim([0.5 nPred+0.5]);
exportgraphics(fig_scree, fullfile(outDir,'pca_scree.png'), 'Resolution',300);

%% ===== LOD =====
fprintf('--- LOD (k = %.1f) ---\n', k_lod);

pc1_bl = score_bl(:,1);
pc2_bl = score_bl(:,2);

mu_pc1    = mean(pc1_bl,'omitnan');
sigma_pc1 = std( pc1_bl,'omitnan');
mu_pc2    = mean(pc2_bl,'omitnan');
sigma_pc2 = std( pc2_bl,'omitnan');

lod_upper_pc1 = mu_pc1 + k_lod * sigma_pc1;
lod_lower_pc1 = mu_pc1 - k_lod * sigma_pc1;
lod_upper_pc2 = mu_pc2 + k_lod * sigma_pc2;
lod_lower_pc2 = mu_pc2 - k_lod * sigma_pc2;

fprintf('  PC1: μ=%+.4f  σ=%.4f  LOD=[%+.4f, %+.4f]\n', ...
    mu_pc1, sigma_pc1, lod_lower_pc1, lod_upper_pc1);
fprintf('  PC2: μ=%+.4f  σ=%.4f  LOD=[%+.4f, %+.4f]\n\n', ...
    mu_pc2, sigma_pc2, lod_lower_pc2, lod_upper_pc2);

%% ===== PROIEZIONE COMPLETA =====
fprintf('--- Proiezione dati completi (%d righe) ---\n', nRows);
t2 = tic;
X_all_z    = (X_all - mu) ./ sigma;
scores_all = (X_all_z - muPCA) * coeff;
PC1_all    = scores_all(:,1);
PC2_all    = scores_all(:,2);
fprintf('  Completata in %.1fs\n', toc(t2));

isEvent = PC1_all < lod_lower_pc1;
nEvt    = sum(isEvent);
fprintf('  Eventi (LOD−): %d / %d  (%.2f%%)\n\n', nEvt, nRows, 100*nEvt/nRows);

%% ===== VERIFICA CORRELAZIONE PC1 vs T/RH =====
fprintf('--- Verifica correlazione PC1 vs T e RH ---\n');
T_col  = DATA.temperature;
RH_col = DATA.humidity;

r_T    = corr(PC1_all, T_col,  'rows','complete');
r_RH   = corr(PC1_all, RH_col, 'rows','complete');
r_T_bl = corr(PC1_all(isBaseline), T_col(isBaseline),  'rows','complete');
r_RH_bl= corr(PC1_all(isBaseline), RH_col(isBaseline), 'rows','complete');

fprintf('  PC1 vs T:   r(tutti)=%+.3f   r(baseline)=%+.3f\n', r_T,  r_T_bl);
fprintf('  PC1 vs RH:  r(tutti)=%+.3f   r(baseline)=%+.3f\n\n', r_RH, r_RH_bl);

fig_corr = figure('Name','PC1 vs T/RH (3 sensori)', 'Color','w', 'Position',[100 100 900 400]);
subplot(1,2,1);
scatter(T_col(isBaseline), PC1_all(isBaseline), 2, [0.15 0.35 0.75], ...
    'filled', 'MarkerFaceAlpha',0.15);
grid on; xlabel('Temperature (°C)','FontSize',11); ylabel('PC₁','FontSize',11);
title(sprintf('PC₁ vs T  (r=%.3f)', r_T_bl),'FontSize',11); lsline;
subplot(1,2,2);
scatter(RH_col(isBaseline), PC1_all(isBaseline), 2, [0.05 0.55 0.20], ...
    'filled', 'MarkerFaceAlpha',0.15);
grid on; xlabel('Humidity (%RH)','FontSize',11); ylabel('PC₁','FontSize',11);
title(sprintf('PC₁ vs RH  (r=%.3f)', r_RH_bl),'FontSize',11); lsline;
sgtitle('Indipendenza PC₁ da variabili ambientali — 3 sensori','FontSize',12,'FontWeight','bold');
exportgraphics(fig_corr, fullfile(outDir,'PC1_vs_TRH_correlation.png'), 'Resolution',300);

%% ===== PLOT PC1(t) =====
fig_pc1 = figure('Name','PC1(t) — 3 sensori','Color','w','Position',[80 80 1600 680]);
sgtitle(sprintf('PC₁(t) — 3 sensori  |  k=%.0f, baseline=%s  |  eventi: %.2f%%', ...
    k_lod, baselineMode, 100*nEvt/nRows), 'FontSize',13,'FontWeight','bold');

ax1 = subplot(2,1,1); hold(ax1,'on');
plot(ax1, DATA.datetime, PC1_all, '-', 'Color',[0.65 0.75 0.9], 'LineWidth',0.3);
plot(ax1, DATA.datetime(isBaseline), PC1_all(isBaseline), '.', ...
    'Color',[0.10 0.55 0.15], 'MarkerSize',2);
plot(ax1, DATA.datetime(isEvent), PC1_all(isEvent), '.', ...
    'Color',[0.82 0.18 0.10], 'MarkerSize',3);
yline(ax1, lod_lower_pc1, '-', sprintf('LOD− = %.3f', lod_lower_pc1), ...
    'Color',[0.10 0.65 0.10], 'LineWidth',2.0, 'LabelHorizontalAlignment','left','FontSize',9);
yline(ax1, lod_upper_pc1, '-', sprintf('LOD+ = %.3f', lod_upper_pc1), ...
    'Color',[0.10 0.65 0.10], 'LineWidth',2.0, 'LabelHorizontalAlignment','left','FontSize',9);
yline(ax1, mu_pc1, '--', sprintf('μ_{BL} = %.3f', mu_pc1), ...
    'Color',[0.45 0.45 0.45], 'LineWidth',1.0);
xlabel(ax1,'Data','FontSize',10); ylabel(ax1,'PC₁(t)','FontSize',10); grid(ax1,'on');
legend(ax1,{'PC₁(t)','Baseline','Evento'},'Location','northeast','FontSize',8);
title(ax1,'Overview completo','FontSize',11);

ax2 = subplot(2,1,2); hold(ax2,'on');
zoomLim = 5 * sigma_pc1;
mask_zoom = abs(PC1_all) <= zoomLim;
plot(ax2, DATA.datetime(mask_zoom), PC1_all(mask_zoom), '-', 'Color',[0.65 0.75 0.9],'LineWidth',0.3);
plot(ax2, DATA.datetime(isBaseline), PC1_all(isBaseline), '.', 'Color',[0.10 0.55 0.15],'MarkerSize',2);
mask_near = isEvent & (PC1_all >= -10*sigma_pc1);
if any(mask_near)
    plot(ax2, DATA.datetime(mask_near), PC1_all(mask_near), 'v', ...
        'Color',[0.82 0.18 0.10], 'MarkerSize',4,'MarkerFaceColor',[0.82 0.18 0.10]);
end
mask_deep = isEvent & (PC1_all < -10*sigma_pc1);
if any(mask_deep)
    plot(ax2, DATA.datetime(mask_deep), repmat(-zoomLim*0.93, sum(mask_deep),1), 'v', ...
        'Color',[0.55 0.08 0.04],'MarkerSize',5,'MarkerFaceColor',[0.55 0.08 0.04]);
end
yline(ax2, lod_lower_pc1, '-', sprintf('LOD− = %.3f', lod_lower_pc1), ...
    'Color',[0.10 0.65 0.10],'LineWidth',2.0,'LabelHorizontalAlignment','left','FontSize',9);
yline(ax2, lod_upper_pc1, '-', 'Color',[0.10 0.65 0.10],'LineWidth',2.0);
yline(ax2, mu_pc1, '--', 'Color',[0.45 0.45 0.45],'LineWidth',1.0);
xlabel(ax2,'Data','FontSize',10); ylabel(ax2,'PC₁(t)','FontSize',10);
grid(ax2,'on'); ylim(ax2,[-zoomLim zoomLim]);
title(ax2,sprintf('Zoom banda LOD (±%.0fσ)', round(zoomLim/sigma_pc1)),'FontSize',11);
exportgraphics(fig_pc1, fullfile(outDir,'PC1_overview.png'), 'Resolution',300);

%% ===== SALVATAGGIO MODELLO =====
modelFile = fullfile(outDir, 'pca_model_ELLONA_3s.mat');
save(modelFile, ...
    'mu','sigma','muPCA','coeff','explained','latent','predictors', ...
    'moxCols','envCols','nPC', ...
    'mu_pc1','sigma_pc1','lod_lower_pc1','lod_upper_pc1', ...
    'mu_pc2','sigma_pc2','lod_lower_pc2','lod_upper_pc2', ...
    'k_lod','pLow','pHigh','baselineMode','nBL','pctBL');
fprintf('Modello salvato: %s\n', modelFile);

statsTable = table(mu_pc1, sigma_pc1, mu_pc2, sigma_pc2, ...
    'VariableNames',{'PC1_mean_of_medians','PC1_std_of_medians', ...
                     'PC2_mean_of_medians','PC2_std_of_medians'});
writetable(statsTable, fullfile(outDir,'baseline_stats_ELLONA_3s.csv'));

LoadT = table(cellstr(predictors)', coeff(:,1), coeff(:,2), coeff(:,3), ...
    'VariableNames',{'Variable','PC1','PC2','PC3'});
writetable(LoadT, fullfile(outDir,'pca_loadings_3s.csv'));

fprintf('\n===== COMPLETATO — output in: %s =====\n', outDir);
