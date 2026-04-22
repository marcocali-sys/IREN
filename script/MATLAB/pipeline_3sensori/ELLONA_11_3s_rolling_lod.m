%% ELLONA_11_3s_rolling_lod.m
% LOD rolling su PC₁ — versione 3 sensori (cmos4 escluso).
% Legge il modello da event_detection_3s (output di ELLONA_08_3s).
%
% Domanda chiave: senza cmos4, la deriva stagionale di PC1 si riduce
% al punto da rendere il Rolling LOD meno necessario?
% (Atteso: σ_roll/σ_global → 1, bias mensile < 2σ)
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ── CONFIG ───────────────────────────────────────────────────────────────
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..', '..');   % → IREN/
addpath(fullfile(scriptDir, '..', 'rolling_lod'));    % ellona_rolling_lod.m

modelFile = fullfile(baseDir, 'output', 'event_detection_3s', 'pca_model_ELLONA_3s.mat');
dataFile  = fullfile(baseDir, 'data',   'processed',          'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'rolling_lod_3s');
if ~isfolder(outDir), mkdir(outDir); end

windows   = [7, 14, 30];
step_days = 1;
pLow = 25; pHigh = 75;
k_lod = 3; minBL = 100;

%% ── CARICA ───────────────────────────────────────────────────────────────
fprintf('Caricamento modello PCA (3s)... ');
M = load(modelFile);
fprintf('OK  (baseline=%s, k=%.0f)\n', M.baselineMode, M.k_lod);

fprintf('Caricamento dati...             '); tic;
S = load(dataFile,'DATA'); DATA = S.DATA;
fprintf('%.1fs  (%d righe)\n', toc, height(DATA));

moxCols = cellstr(M.predictors);   % {'cmos1','cmos2','cmos3'}

%% ── SCORE PC₁ ────────────────────────────────────────────────────────────
fprintf('Calcolo score PCA...            '); tic;
X = DATA{:, moxCols};
for j = 1:size(X,2)
    nm = isnan(X(:,j));
    if any(nm), X(nm,j) = median(X(~nm,j)); end
end
SC  = ((X - M.mu) ./ M.sigma - M.muPCA) * M.coeff;
PC1 = SC(:,1);
t   = DATA.datetime;
dt_s = seconds(median(diff(t(1:min(5000,end)))));
fprintf('%.1fs\n', toc);

%% ── LOD FISSO ────────────────────────────────────────────────────────────
lod_lo_fix = M.lod_lower_pc1;
lod_hi_fix = M.lod_upper_pc1;
isEvt_fix  = PC1 < lod_lo_fix;

fprintf('\n--- LOD fisso ---\n');
fprintf('  LOD = [%.4f, %.4f]   (mu=%.4f, sigma=%.4f)\n', ...
    lod_lo_fix, lod_hi_fix, M.mu_pc1, M.sigma_pc1);
fprintf('  Eventi: %d / %d  (%.2f%%)\n', sum(isEvt_fix), numel(PC1), 100*mean(isEvt_fix));

%% ── LOD ROLLING ──────────────────────────────────────────────────────────
X_mox = DATA{:, moxCols};
nW    = numel(windows);
mu_roll = cell(nW,1); sigma_roll = cell(nW,1);
lod_lo_roll = cell(nW,1); lod_hi_roll = cell(nW,1);
isEvt_roll  = cell(nW,1);

for wi = 1:nW
    wd = windows(wi);
    fprintf('\n--- LOD rolling (finestra %dd) ---\n', wd);
    [lod_lo_roll{wi}, lod_hi_roll{wi}, mu_roll{wi}, sigma_roll{wi}] = ...
        ellona_rolling_lod(t, PC1, X_mox, pLow, pHigh, k_lod, wd, step_days, minBL, ...
        lod_lo_fix, lod_hi_fix);
    isEvt_roll{wi} = PC1 < lod_lo_roll{wi};
    fprintf('  LOD_lo medio = %.4f\n', mean(lod_lo_roll{wi},'omitnan'));
    fprintf('  sigma_roll   = %.4f  (%.0f%% di sigma_global)\n', ...
        mean(sigma_roll{wi},'omitnan'), 100*mean(sigma_roll{wi},'omitnan')/M.sigma_pc1);
    fprintf('  Eventi: %.2f%%\n', 100*mean(isEvt_roll{wi}));
end

%% ── PLOT ─────────────────────────────────────────────────────────────────
step_ds = max(1, floor(numel(t)/120000));
idx_ds  = 1:step_ds:numel(t);
t_ds = t(idx_ds); p1_ds = PC1(idx_ds);

colors_sg = [0.85 0.33 0.10; 0.18 0.55 0.34; 0.12 0.38 0.74];

% σ_roll(t)
fig1 = figure('Name','σ_roll — 3 sensori','Color','w','Position',[40 40 1400 480]);
hold on; grid on;
for wi = 1:nW
    plot(t_ds, sigma_roll{wi}(idx_ds), '-', 'Color',colors_sg(wi,:), 'LineWidth',1.4, ...
        'DisplayName', sprintf('σ_{roll} %dd', windows(wi)));
end
yline(M.sigma_pc1,'--k', sprintf('σ_{global} = %.4f', M.sigma_pc1), ...
    'LineWidth',2.0,'LabelHorizontalAlignment','right','FontSize',10);
xlabel('Data','FontSize',11); ylabel('σ_{roll}(t)','FontSize',11);
title('σ rolling — 3 sensori (senza cmos4)','FontSize',11);
legend('Location','northeast','FontSize',10); xlim([t(1) t(end)]);
exportgraphics(fig1, fullfile(outDir,'sigma_window_comparison.png'),'Resolution',300);

% μ_roll(t)
fig2 = figure('Name','μ_roll — 3 sensori','Color','w','Position',[40 40 1400 480]);
hold on; grid on;
for wi = 1:nW
    plot(t_ds, mu_roll{wi}(idx_ds), '-', 'Color',colors_sg(wi,:),'LineWidth',1.4, ...
        'DisplayName', sprintf('μ_{roll} %dd', windows(wi)));
end
yline(M.mu_pc1,'--k',sprintf('μ_{global} = %.4f',M.mu_pc1), ...
    'LineWidth',2.0,'LabelHorizontalAlignment','right','FontSize',10);
xlabel('Data','FontSize',11); ylabel('μ_{roll}(t)','FontSize',11);
title('μ rolling — deriva residua del baseline (3 sensori)','FontSize',11);
legend('Location','northeast','FontSize',10); xlim([t(1) t(end)]);
exportgraphics(fig2, fullfile(outDir,'mu_window_comparison.png'),'Resolution',300);

% PC1 fisso vs rolling 30d
wi_30 = find(windows == 30);
lo_r_ds = lod_lo_roll{wi_30}(idx_ds);
hi_r_ds = lod_hi_roll{wi_30}(idx_ds);

fig3 = figure('Name','PC1 Fixed vs Rolling — 3 sensori','Color','w','Position',[40 40 1500 580]);
hold on; grid on;
plot(t_ds, p1_ds, '-','Color',[0.70 0.80 0.93],'LineWidth',0.4,'DisplayName','PC₁(t)');
patch([t_ds; flipud(t_ds)],[lo_r_ds; flipud(hi_r_ds)], ...
    [0.78 0.94 0.78],'EdgeColor','none','FaceAlpha',0.45,'DisplayName','Banda rolling 30d');
plot(t_ds, lo_r_ds,'-','Color',[0.10 0.55 0.15],'LineWidth',1.5, ...
    'DisplayName',sprintf('LOD_{roll}− 30d  (%.2f%%)',100*mean(isEvt_roll{wi_30})));
plot(t_ds, hi_r_ds,'-','Color',[0.10 0.55 0.15],'LineWidth',1.5,'HandleVisibility','off');
yline(lod_lo_fix,'--','Color',[0.88 0.48 0.08],'LineWidth',2.0, ...
    'Label',sprintf('LOD_{fix}− = %.3f  (%.2f%%)',lod_lo_fix,100*mean(isEvt_fix)), ...
    'LabelHorizontalAlignment','left','FontSize',9);
xlabel('Data','FontSize',11); ylabel('PC₁','FontSize',11);
title(sprintf('PC₁ — LOD fisso vs rolling 30d  |  3 sensori  |  k=%.0f',k_lod),'FontSize',11);
legend('Location','southwest','FontSize',9); xlim([t(1) t(end)]);
exportgraphics(fig3, fullfile(outDir,'PC1_fixed_vs_rolling.png'),'Resolution',300);

% Confronto eventi settimanali
weeks_all = unique(dateshift(t,'start','week'));
nWeeks    = numel(weeks_all);
pct_mat   = zeros(nWeeks, nW+1);
for w = 1:nWeeks
    mw = t >= weeks_all(w) & t < weeks_all(w) + days(7);
    if sum(mw) < 10, continue; end
    pct_mat(w,1) = 100*mean(isEvt_fix(mw));
    for wi = 1:nW
        pct_mat(w,wi+1) = 100*mean(isEvt_roll{wi}(mw));
    end
end
fig4 = figure('Name','Confronto eventi settimanali — 3s','Color','w','Position',[40 40 1400 460]);
b = bar(weeks_all, pct_mat, 0.85,'grouped');
bar_colors = [[0.88 0.55 0.12]; colors_sg];
for bi = 1:nW+1, b(bi).FaceColor = bar_colors(bi,:); b(bi).FaceAlpha = 0.85; end
xlabel('Settimana','FontSize',11); ylabel('% eventi','FontSize',11);
title(sprintf('Confronto eventi settimanali — 3 sensori  |  k=%.0f',k_lod),'FontSize',11);
lbls = ['LOD fisso', arrayfun(@(w) sprintf('Rolling %dd',w), windows,'UniformOutput',false)];
legend(lbls,'Location','northeast','FontSize',9); grid on;
exportgraphics(fig4, fullfile(outDir,'events_weekly_comparison.png'),'Resolution',300);

%% ── STATS ────────────────────────────────────────────────────────────────
fprintf('\n======== RIEPILOGO (3 sensori) ========\n');
all_labels = [{'LOD fisso'}, arrayfun(@(w) sprintf('Roll %dd',w), windows,'UniformOutput',false)];
all_isEvt  = [{isEvt_fix}, isEvt_roll(:)'];
all_lod_lo = [lod_lo_fix, cellfun(@(x) mean(x,'omitnan'), lod_lo_roll)'];
all_sigma  = [M.sigma_pc1, cellfun(@(x) mean(x,'omitnan'), sigma_roll)'];
all_mu     = [M.mu_pc1,    cellfun(@(x) mean(x,'omitnan'), mu_roll)'];

fprintf('%-12s  %8s  %8s  %9s  %9s\n','Metodo','% eventi','LOD_lo','mu_medio','sigma_medio');
fprintf('%s\n', repmat('-',55,1));
for i = 1:numel(all_labels)
    fprintf('%-12s  %7.2f%%  %8.4f  %9.4f  %9.4f\n', ...
        all_labels{i}, 100*mean(all_isEvt{i}), all_lod_lo(i), all_mu(i), all_sigma(i));
end
fprintf('\n--- Concordanza con LOD fisso ---\n');
for wi = 1:nW
    ag  = mean(isEvt_fix == isEvt_roll{wi})*100;
    o_f = mean(isEvt_fix & ~isEvt_roll{wi})*100;
    o_r = mean(~isEvt_fix & isEvt_roll{wi})*100;
    fprintf('  Rolling %2dd: concordanza=%.1f%%  solo-fisso=%.2f%%  solo-rolling=%.2f%%\n', ...
        windows(wi), ag, o_f, o_r);
end

StatsT = table(all_labels', cellfun(@(x) 100*mean(x),all_isEvt)', ...
    all_lod_lo', all_mu', all_sigma', ...
    'VariableNames',{'Metodo','Pct_eventi','LOD_lo_medio','mu_medio','sigma_medio'});
writetable(StatsT, fullfile(outDir,'comparison_stats.csv'));
fprintf('\n===== COMPLETATO — output in: %s =====\n', outDir);
