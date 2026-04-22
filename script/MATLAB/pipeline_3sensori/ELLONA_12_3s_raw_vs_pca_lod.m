%% ELLONA_12_3s_raw_vs_pca_lod.m
% Confronto LOD su segnali grezzi (cmos1–3) vs LOD su PC₁ — 3 sensori.
% cmos4 ESCLUSO dal confronto (escluso anche dalla PCA).
%
% Domanda: anche con 3 sensori, il LOD diretto sul grezzo genera
% falsi positivi stagionali? (Atteso: sì, perché cmos1-3 hanno ancora
% correlazione con T/RH, solo meno estrema di cmos4)
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ── CONFIG ───────────────────────────────────────────────────────────────
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..', '..');

modelFile = fullfile(baseDir, 'output', 'event_detection_3s', 'pca_model_ELLONA_3s.mat');
dataFile  = fullfile(baseDir, 'data',   'processed',          'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'raw_vs_pca_3s');
if ~isfolder(outDir), mkdir(outDir); end

pLow = 25; pHigh = 75;
k_lod = 3;

%% ── CARICA ───────────────────────────────────────────────────────────────
fprintf('Caricamento modello PCA (3s)... ');
M = load(modelFile);
fprintf('OK\n');

fprintf('Caricamento dati...             '); tic;
S = load(dataFile,'DATA'); DATA = S.DATA;
fprintf('%.1fs  (%d righe)\n\n', toc, height(DATA));

% 3 sensori grezzi + avg_z + PC1
moxCols = {'cmos1','cmos2','cmos3'};
nMox    = numel(moxCols);

%% ── BASELINE MASK (IQR su cmos1-3) ──────────────────────────────────────
fprintf('Baseline IQR [P%d,P%d] su cmos1-3...\n', pLow, pHigh);
X_mox   = DATA{:, moxCols};
t       = DATA.datetime;
nRows   = height(DATA);

% Periodo giornaliero
days_id   = floor(datenum(t));
days_uniq = unique(days_id);
isBL      = false(nRows,1);
for d = days_uniq'
    idx = days_id == d;
    ok  = true(sum(idx),1);
    for j = 1:nMox
        y = X_mox(idx,j);
        ok = ok & y >= prctile(y,pLow) & y <= prctile(y,pHigh);
    end
    tmp = isBL(idx); tmp(ok) = true; isBL(idx) = tmp;
end
nBL = sum(isBL);
fprintf('  Baseline: %d / %d (%.1f%%)\n\n', nBL, nRows, 100*nBL/nRows);

%% ── SCORE PC₁ ────────────────────────────────────────────────────────────
X_pca = DATA{:, cellstr(M.predictors)};
for j = 1:size(X_pca,2)
    nm = isnan(X_pca(:,j));
    if any(nm), X_pca(nm,j) = median(X_pca(~nm,j)); end
end
SC   = ((X_pca - M.mu) ./ M.sigma - M.muPCA) * M.coeff;
PC1  = SC(:,1);

%% ── LOD PER OGNI METODO ──────────────────────────────────────────────────
fprintf('Calcolo LOD per ogni metodo...\n');

% z-score di ciascun sensore (su baseline propria)
X_mox_z = nan(nRows, nMox);
for j = 1:nMox
    mu_j  = mean(X_mox(isBL,j),'omitnan');
    sg_j  = std( X_mox(isBL,j),'omitnan');
    X_mox_z(:,j) = (X_mox(:,j) - mu_j) / sg_j;
end
avg_z = mean(X_mox_z, 2, 'omitnan');

% Tutti i segnali da testare
signals = [X_mox, avg_z, PC1];
names   = [moxCols, {'avg_z','PC1'}];
nSig    = numel(names);

mu_sig  = nan(nSig,1);
sg_sig  = nan(nSig,1);
lod_lo  = nan(nSig,1);
isEvt   = false(nRows, nSig);
pct_evt = nan(nSig,1);

for s = 1:nSig
    y       = signals(:,s);
    mu_sig(s) = mean(y(isBL),'omitnan');
    sg_sig(s) = std( y(isBL),'omitnan');
    lod_lo(s) = mu_sig(s) - k_lod * sg_sig(s);
    isEvt(:,s) = y < lod_lo(s);
    pct_evt(s) = 100 * mean(isEvt(:,s));
    fprintf('  %-8s  LOD⁻=%.4f  eventi=%.2f%%\n', names{s}, lod_lo(s), pct_evt(s));
end
fprintf('\n');

%% ── CORRELAZIONE EVENTI vs TEMPERATURA (settimanale) ──────────────────
fprintf('Correlazione settimanale eventi vs T...\n');
T_col    = DATA.temperature;
weeks_all = unique(dateshift(t,'start','week'));
nWeeks    = numel(weeks_all);
pct_wk   = nan(nWeeks, nSig);
T_wk     = nan(nWeeks,1);

for w = 1:nWeeks
    mw = t >= weeks_all(w) & t < weeks_all(w)+days(7);
    if sum(mw) < 10, continue; end
    T_wk(w) = mean(T_col(mw),'omitnan');
    for s = 1:nSig
        pct_wk(w,s) = 100*mean(isEvt(mw,s));
    end
end

r_T = nan(nSig,1);
for s = 1:nSig
    valid = ~isnan(pct_wk(:,s)) & ~isnan(T_wk);
    r_T(s) = corr(pct_wk(valid,s), T_wk(valid));
end
fprintf('  %-8s  %8s\n','Metodo','r(evt,T)');
for s=1:nSig, fprintf('  %-8s  %+8.4f\n', names{s}, r_T(s)); end
fprintf('\n');

%% ── OVERLAP CON PC₁ ──────────────────────────────────────────────────────
fprintf('Overlap eventi vs PC₁...\n');
pc1_idx   = find(strcmp(names,'PC1'));
pct_overlap = nan(nSig,1);
pct_fp      = nan(nSig,1);
for s = 1:nSig
    if s == pc1_idx, continue; end
    both = isEvt(:,s) & isEvt(:,pc1_idx);
    excl = isEvt(:,s) & ~isEvt(:,pc1_idx);
    if sum(isEvt(:,s)) > 0
        pct_overlap(s) = 100*mean(both);
        pct_fp(s)      = 100*sum(excl)/sum(isEvt(:,s));
    end
    fprintf('  %-8s  overlap=%.2f%%  solo-questo(FP)=%.1f%%\n', ...
        names{s}, pct_overlap(s), pct_fp(s));
end
fprintf('\n');

%% ── FIGURE ───────────────────────────────────────────────────────────────
C_blu = [0 56 102]/255; C_azz = [20 100 160]/255; C_azzlt = [107 163 214]/255;
C_grig = [88 89 91]/255; C_rosso = [181 57 78]/255; C_arancio = [232 163 61]/255;
sig_colors = [C_blu; C_azz; C_azzlt; C_arancio; C_rosso];

% Tasso eventi
fig1 = figure('Name','Tasso eventi — 3 sensori','Color','w','Position',[50 50 900 420]);
b = bar(1:nSig, pct_evt, 0.6,'FaceColor','flat','EdgeColor','white','LineWidth',1.5);
for k=1:nSig, b.CData(k,:) = sig_colors(k,:); end
hold on;
pc1_val = pct_evt(pc1_idx);
text(pc1_idx, pc1_val+0.2,'RIFERIMENTO','HorizontalAlignment','center', ...
    'FontSize',10,'FontWeight','bold','Color',C_rosso);
for k=1:nSig
    text(k, pct_evt(k)+0.1, sprintf('%.2f%%',pct_evt(k)), ...
        'HorizontalAlignment','center','FontSize',11,'FontWeight','bold','Color',sig_colors(k,:));
end
set(gca,'XTick',1:nSig,'XTickLabel',names,'FontSize',12);
ylabel('% eventi'); title('Tasso eventi — segnali grezzi vs PC₁ (3 sensori)','FontWeight','bold');
grid on; box off;
exportgraphics(fig1, fullfile(outDir,'event_rates.png'),'Resolution',300);

% r(eventi, T)
fig2 = figure('Name','Correlazione T — 3 sensori','Color','w','Position',[50 50 900 420]);
b2 = bar(1:nSig, abs(r_T), 0.6,'FaceColor','flat','EdgeColor','white','LineWidth',1.5);
for k=1:nSig
    clr = C_rosso*(abs(r_T(k))>0.3) + C_azz*(abs(r_T(k))<=0.3);
    b2.CData(k,:) = clr;
    text(k, abs(r_T(k))+0.01, sprintf('r=%+.3f',r_T(k)), ...
        'HorizontalAlignment','center','FontSize',11,'FontWeight','bold','Color',clr);
end
yline(0.3,':','Color',C_grig,'LineWidth',1.2,'Label','|r|=0.3');
set(gca,'XTick',1:nSig,'XTickLabel',names,'FontSize',12);
ylabel('|r(eventi, T)|');
title('Correlazione settimanale eventi vs T — 3 sensori','FontWeight','bold');
grid on; box off;
exportgraphics(fig2, fullfile(outDir,'temperature_correlation.png'),'Resolution',300);

% FP (overlap con PC1)
fig3 = figure('Name','Falsi positivi — 3 sensori','Color','w','Position',[50 50 900 420]);
hold on;
pct_ov_plot = pct_overlap; pct_ov_plot(pc1_idx) = 0;
pct_fp_plot = zeros(nSig,1);
for s=1:nSig
    if s~=pc1_idx && ~isnan(pct_fp(s))
        pct_fp_plot(s) = pct_evt(s) * pct_fp(s)/100;
    end
end
bar(1:nSig, pct_ov_plot, 0.6,'FaceColor',[74 155 110]/255,'EdgeColor','white', ...
    'LineWidth',1.5,'DisplayName','Confermato da PC₁ (TP)');
bar(1:nSig, pct_fp_plot, 0.6,'FaceColor',C_rosso,'EdgeColor','white', ...
    'LineWidth',1.5,'DisplayName','Solo questo metodo (FP)','BarLayout','stacked');
for s=1:nSig
    if s~=pc1_idx && ~isnan(pct_fp(s))
        text(s, pct_evt(s)+0.1, sprintf('%.0f%% FP',pct_fp(s)), ...
            'HorizontalAlignment','center','FontSize',10,'FontWeight','bold', ...
            'Color', C_rosso*(pct_fp(s)>50)+C_grig*(pct_fp(s)<=50));
    end
end
set(gca,'XTick',1:nSig,'XTickLabel',names,'FontSize',12);
ylabel('% eventi'); legend('Location','northeast','FontSize',10);
title('Scomposizione eventi: TP vs FP (3 sensori)','FontWeight','bold');
grid on; box off;
exportgraphics(fig3, fullfile(outDir,'event_overlap.png'),'Resolution',300);

%% ── SALVATAGGIO CSV ──────────────────────────────────────────────────────
StatsT = table(names', pct_evt, r_T, pct_overlap, pct_fp, ...
    'VariableNames',{'Metodo','Pct_eventi','r_temperatura','Pct_overlap_PC1','Pct_esclusivi_FP'});
writetable(StatsT, fullfile(outDir,'raw_vs_pca_stats.csv'));

fprintf('======== RIEPILOGO (3 sensori) ========\n');
fprintf('%-8s  %8s  %8s  %10s  %8s\n','Metodo','% eventi','r(evt,T)','Overlap PC₁','%FP');
for s=1:nSig
    fprintf('%-8s  %8.2f%%  %+8.4f  %10.2f%%  %7.1f%%\n', ...
        names{s}, pct_evt(s), r_T(s), ...
        coalesce(pct_overlap(s),0), coalesce(pct_fp(s),0));
end
fprintf('\nOutput: %s\n===== DONE =====\n', outDir);

function v = coalesce(x, default)
    if isnan(x), v = default; else, v = x; end
end
