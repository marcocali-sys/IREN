%% ELLONA_15_pca_3vs4_sensors.m
%
% Confronto PCA a 3 sensori (cmos1-2-3) vs 4 sensori (cmos1-2-3-4).
%
% Domanda: rimuovere cmos4 risolve il bias stagionale di PC1
%           e rende il Rolling LOD superfluo?
%
% Metriche di confronto:
%   1. Loading plot e varianza spiegata
%   2. Bias stagionale di PC1 (media mensile)
%   3. r(PC1, T) e r(PC1, RH) a scala rapida e mensile
%   4. σ_global vs σ_roll — il gap si riduce senza cmos4?
%   5. Tasso eventi con LOD fisso (k=3)
%   6. Concordanza eventi tra le due versioni
%
% Output → IREN/output/pca_3vs4/
%
% Marco Calì — PoliMi, Aprile 2026

clear; clc; close all;

%% ══════════════════════════════════════════════════════════════════════════
%% CONFIG
%% ══════════════════════════════════════════════════════════════════════════
scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');

dataFile  = fullfile(baseDir, 'data', 'processed', 'monitoring_all.mat');
outDir    = fullfile(baseDir, 'output', 'pca_3vs4');
if ~isfolder(outDir), mkdir(outDir); end

k_lod    = 3;       % moltiplicatore LOD
roll_win = 7*24;    % finestra rolling (7 giorni @1h)

% PoliMi palette
C_blu    = [0   56  102]/255;
C_azz    = [20  100 160]/255;
C_azzlt  = [107 163 214]/255;
C_grig   = [88  89  91 ]/255;
C_rosso  = [181 57  78 ]/255;
C_arancio= [232 163 61 ]/255;
C_verde  = [74  155 110]/255;

COL_4 = C_blu;    % colore per versione 4 sensori
COL_3 = C_rosso;  % colore per versione 3 sensori

month_labels = {'Mar','Apr','Mag','Giu','Lug','Ago','Set','Ott','Nov','Dic'};

fprintf('=== ELLONA_15 — PCA 3 vs 4 sensori ===\n\n');

%% ══════════════════════════════════════════════════════════════════════════
%% 1. CARICAMENTO + RESAMPLE @1h
%% ══════════════════════════════════════════════════════════════════════════
fprintf('1. Caricamento dati...\n');
load(dataFile, 'DATA');
fprintf('   Righe: %d  |  %s → %s\n\n', height(DATA), ...
    datestr(DATA.datetime(1),'dd-mmm-yyyy'), ...
    datestr(DATA.datetime(end),'dd-mmm-yyyy'));

TT_raw = timetable(DATA.datetime, ...
    DATA.cmos1, DATA.cmos2, DATA.cmos3, DATA.cmos4, ...
    DATA.temperature, DATA.humidity, ...
    'VariableNames', {'cmos1','cmos2','cmos3','cmos4','T_C','RH'});
TT_1h = retime(TT_raw, 'hourly', 'mean');
TT_1h = rmmissing(TT_1h);

t_h    = TT_1h.Properties.RowTimes;
T_C    = TT_1h.T_C;
RH_h   = TT_1h.RH;
X4     = TT_1h{:, {'cmos1','cmos2','cmos3','cmos4'}};
X3     = TT_1h{:, {'cmos1','cmos2','cmos3'}};
months = month(t_h);
nH     = height(TT_1h);

months_avail = unique(months)';
nMon         = numel(months_avail);
xl_mon       = month_labels(months_avail - 2);

fprintf('   Punti @1h: %d\n\n', nH);

%% ══════════════════════════════════════════════════════════════════════════
%% 2. BASELINE IQR WEEKLY (comune a entrambe le versioni)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('2. Selezione baseline IQR weekly (su cmos1-2-3)...\n');
% Usiamo solo cmos1-3 per la baseline mask di entrambe le versioni,
% così il confronto è equo (stessa finestra di calibrazione)
week_id  = floor(datenum(t_h) / 7);
wks_uniq = unique(week_id);
bl_mask  = true(nH, 1);
for wk = wks_uniq'
    idx = week_id == wk;
    for j = 1:3   % solo cmos1-3
        y_wk = X3(idx, j);
        p25  = prctile(y_wk, 25);
        p75  = prctile(y_wk, 75);
        bl_mask(idx) = bl_mask(idx) & (y_wk >= p25) & (y_wk <= p75);
    end
end
nBL = sum(bl_mask);
fprintf('   Baseline: %d punti (%.1f%%)\n\n', nBL, 100*nBL/nH);

%% ══════════════════════════════════════════════════════════════════════════
%% 3. PCA — entrambe le versioni su baseline
%% ══════════════════════════════════════════════════════════════════════════
fprintf('3. PCA su baseline...\n');

configs = struct();
configs(1).name    = '4 sensori';
configs(1).label   = '4s';
configs(1).X       = X4;
configs(1).nSens   = 4;
configs(1).snames  = {'cmos1','cmos2','cmos3','cmos4'};
configs(1).color   = COL_4;

configs(2).name    = '3 sensori (senza cmos4)';
configs(2).label   = '3s';
configs(2).X       = X3;
configs(2).nSens   = 3;
configs(2).snames  = {'cmos1','cmos2','cmos3'};
configs(2).color   = COL_3;

for ci = 1:2
    cfg = configs(ci);
    X_bl = cfg.X(bl_mask, :);

    % z-score su baseline
    mu_bl    = mean(X_bl, 1);
    sigma_bl = std(X_bl, 0, 1);
    X_bl_z   = (X_bl - mu_bl) ./ sigma_bl;

    % PCA
    [coeff, ~, latent, ~, explained] = pca(X_bl_z);

    % Proietta TUTTO il dataset
    X_all_z = (cfg.X - mu_bl) ./ sigma_bl;
    scores_all = X_all_z * coeff;
    PC1_all    = scores_all(:, 1);

    % Parametri LOD su baseline PC1
    scores_bl = X_bl_z * coeff;
    PC1_bl    = scores_bl(:, 1);
    mu_pc1   = mean(PC1_bl);
    sig_pc1  = std(PC1_bl);
    lod_lo   = mu_pc1 - k_lod * sig_pc1;

    % Rolling LOD (mu rolling, sigma globale)
    mu_roll  = movmean(PC1_all, roll_win, 'omitnan');
    lod_roll = mu_roll - k_lod * sig_pc1;

    % Sigma rolling (per valutare gap)
    sig_roll = movstd(PC1_all, roll_win, 'omitnan');

    % Eventi
    evt_fixed  = PC1_all < lod_lo;
    evt_roll   = PC1_all < lod_roll;
    pct_fixed  = 100 * mean(evt_fixed);
    pct_roll   = 100 * mean(evt_roll);
    concordance= 100 * mean(evt_fixed == evt_roll);

    % Media mensile PC1
    PC1_monthly = nan(nMon, 1);
    for mi = 1:nMon
        idx_m = months == months_avail(mi);
        PC1_monthly(mi) = mean(PC1_all(idx_m), 'omitnan');
    end

    % r(PC1, T) e r(PC1, RH) a più scale
    scales = {'@1h', '@1D', '@1M'};
    r_T = nan(1,3); r_RH = nan(1,3);
    % @1h
    r_T(1)  = corr(PC1_all, T_C,  'rows','complete');
    r_RH(1) = corr(PC1_all, RH_h, 'rows','complete');
    % @1D
    PC1_1d = nan(nH,1);
    T_1d   = nan(nH,1); RH_1d = nan(nH,1);
    days_id = floor(datenum(t_h));
    for d = unique(days_id)'
        idx_d = days_id == d;
        PC1_1d(idx_d) = mean(PC1_all(idx_d), 'omitnan');
        T_1d(idx_d)   = mean(T_C(idx_d),     'omitnan');
        RH_1d(idx_d)  = mean(RH_h(idx_d),    'omitnan');
    end
    r_T(2)  = corr(PC1_1d, T_1d,  'rows','complete');
    r_RH(2) = corr(PC1_1d, RH_1d, 'rows','complete');
    % @1M (mensile)
    PC1_mon_v = nan(nMon,1); T_mon_v = nan(nMon,1); RH_mon_v = nan(nMon,1);
    for mi=1:nMon
        idx_m = months == months_avail(mi);
        PC1_mon_v(mi) = mean(PC1_all(idx_m),'omitnan');
        T_mon_v(mi)   = mean(T_C(idx_m),    'omitnan');
        RH_mon_v(mi)  = mean(RH_h(idx_m),   'omitnan');
    end
    r_T(3)  = corr(PC1_mon_v, T_mon_v,  'rows','complete');
    r_RH(3) = corr(PC1_mon_v, RH_mon_v, 'rows','complete');

    % Bias stagionale: range mensile di PC1
    bias_range = max(PC1_monthly) - min(PC1_monthly);
    sig_roll_mean = mean(sig_roll, 'omitnan');
    var_expl_roll = 100 * (1 - (sig_roll_mean/sig_pc1)^2);

    % Salva tutto nella struct
    configs(ci).coeff        = coeff;
    configs(ci).explained    = explained;
    configs(ci).mu_bl        = mu_bl;
    configs(ci).sigma_bl     = sigma_bl;
    configs(ci).mu_pc1       = mu_pc1;
    configs(ci).sig_pc1      = sig_pc1;
    configs(ci).lod_lo       = lod_lo;
    configs(ci).PC1_all      = PC1_all;
    configs(ci).PC1_monthly  = PC1_monthly;
    configs(ci).evt_fixed    = evt_fixed;
    configs(ci).evt_roll     = evt_roll;
    configs(ci).pct_fixed    = pct_fixed;
    configs(ci).pct_roll     = pct_roll;
    configs(ci).concordance  = concordance;
    configs(ci).r_T          = r_T;
    configs(ci).r_RH         = r_RH;
    configs(ci).sig_roll_mean= sig_roll_mean;
    configs(ci).bias_range   = bias_range;
    configs(ci).var_expl_roll= var_expl_roll;

    fprintf('   [%s]\n', cfg.name);
    fprintf('     Varianza spiegata PC1:   %.1f%%\n', explained(1));
    fprintf('     σ_PC1 (baseline):        %.4f\n',  sig_pc1);
    fprintf('     LOD⁻ (k=3):             %.4f\n',  lod_lo);
    fprintf('     Tasso eventi (fisso):    %.2f%%\n', pct_fixed);
    fprintf('     Tasso eventi (rolling):  %.2f%%\n', pct_roll);
    fprintf('     Concordanza fix/roll:    %.2f%%\n', concordance);
    fprintf('     Bias stagionale (range): %.3f σ\n', bias_range/sig_pc1);
    fprintf('     σ_roll medio:            %.4f  (%.0f%% di σ_global)\n', ...
        sig_roll_mean, 100*sig_roll_mean/sig_pc1);
    fprintf('     r(PC1,T)  @1h/1d/1m:    %+.3f / %+.3f / %+.3f\n', r_T(1), r_T(2), r_T(3));
    fprintf('     r(PC1,RH) @1h/1d/1m:    %+.3f / %+.3f / %+.3f\n\n', r_RH(1), r_RH(2), r_RH(3));
end

%% ══════════════════════════════════════════════════════════════════════════
%% FIGURE
%% ══════════════════════════════════════════════════════════════════════════

%% ─── FIG 1: Loading plot confronto ───────────────────────────────────────
fprintf('Plot Fig 1: loading plot...\n');
fig1 = figure('Position',[50 50 1300 480]);

for ci = 1:2
    cfg  = configs(ci);
    ax   = subplot(1,2,ci);
    ns   = cfg.nSens;
    ldgs = cfg.coeff(:,1);
    cols = arrayfun(@(v) ternary(v>=0, C_blu, C_rosso), ldgs, 'UniformOutput',false);
    cols = vertcat(cols{:});
    b    = bar(1:ns, ldgs, 0.6, 'FaceColor','flat', 'EdgeColor','white','LineWidth',1.5);
    for k=1:ns, b.CData(k,:) = cols(k,:); end
    hold on; yline(0,'Color',C_grig,'LineWidth',0.8);
    for k=1:ns
        ypos = ldgs(k) + sign(ldgs(k))*0.04;
        text(k, ypos, sprintf('%+.3f', ldgs(k)), ...
            'HorizontalAlignment','center','FontSize',12,'FontWeight','bold', ...
            'Color', cols(k,:));
    end
    set(ax,'XTick',1:ns,'XTickLabel',cfg.snames,'FontSize',12);
    ylabel('Loading su PC₁');
    title(sprintf('%s  —  PC₁ = %.1f%% varianza', cfg.name, cfg.explained(1)), ...
        'FontWeight','bold','FontSize',13);
    ylim([-0.8 0.8]); grid on; box off;
end
sgtitle('Loading plot PC₁  —  4 sensori vs 3 sensori', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig1, fullfile(outDir,'fig01_loadings_3vs4.png'));

%% ─── FIG 2: Bias stagionale — PC1 mensile ────────────────────────────────
fprintf('Plot Fig 2: bias stagionale PC1...\n');
fig2 = figure('Position',[50 50 1100 480]);

ax = gca; hold on;
xs = 1:nMon;
w  = 0.35;

b4 = bar(xs - w/2, configs(1).PC1_monthly, w, ...
    'FaceColor', COL_4, 'EdgeColor','white','LineWidth',1.5,'DisplayName','4 sensori');
b3 = bar(xs + w/2, configs(2).PC1_monthly, w, ...
    'FaceColor', COL_3, 'EdgeColor','white','LineWidth',1.5,'DisplayName','3 sensori');

% LOD lines
yline(configs(1).lod_lo, '--', 'Color', COL_4, 'LineWidth',1.5, ...
    'Label', sprintf('LOD⁻ (4s) = %.2f', configs(1).lod_lo), 'FontSize',10);
yline(configs(2).lod_lo, '--', 'Color', COL_3, 'LineWidth',1.5, ...
    'Label', sprintf('LOD⁻ (3s) = %.2f', configs(2).lod_lo), 'FontSize',10);
yline(0, '-', 'Color', C_grig, 'LineWidth',0.8);

set(gca,'XTick',xs,'XTickLabel',xl_mon,'FontSize',12);
ylabel('PC₁ medio mensile (σ normalizzate)');
title('Bias stagionale di PC₁  —  il range mensile si riduce senza cmos4?', ...
    'FontWeight','bold');
legend('Location','best','FontSize',11);
grid on; box off;

% Annotazioni range
r4 = configs(1).bias_range / configs(1).sig_pc1;
r3 = configs(2).bias_range / configs(2).sig_pc1;
text(0.02, 0.97, sprintf('Range mensile 4s: %.2f σ', r4), ...
    'Units','normalized','VerticalAlignment','top','FontSize',11, ...
    'Color',COL_4,'FontWeight','bold','BackgroundColor','white','EdgeColor',COL_4);
text(0.02, 0.87, sprintf('Range mensile 3s: %.2f σ', r3), ...
    'Units','normalized','VerticalAlignment','top','FontSize',11, ...
    'Color',COL_3,'FontWeight','bold','BackgroundColor','white','EdgeColor',COL_3);

saveas(fig2, fullfile(outDir,'fig02_seasonal_bias_PC1.png'));

%% ─── FIG 3: Correlazione r(PC1, T/RH) a più scale ───────────────────────
fprintf('Plot Fig 3: correlazione PC1 vs T e RH...\n');
fig3 = figure('Position',[50 50 1000 480]);

scale_labels = {'@1h','@1 giorno','@1 mese'};
xs = 1:3;
w  = 0.2;

subplot(1,2,1); hold on;
title('r(PC₁, T)','FontWeight','bold','FontSize',13);
b4 = bar(xs - w, configs(1).r_T, w*1.8, 'FaceColor',COL_4,'EdgeColor','white','LineWidth',1.5);
b3 = bar(xs + w, configs(2).r_T, w*1.8, 'FaceColor',COL_3,'EdgeColor','white','LineWidth',1.5);
yline(0,'-','Color',C_grig,'LineWidth',0.8);
yline( 0.3,':','Color',C_grig,'LineWidth',1,'Alpha',0.5);
yline(-0.3,':','Color',C_grig,'LineWidth',1,'Alpha',0.5);
set(gca,'XTick',xs,'XTickLabel',scale_labels,'FontSize',12);
ylabel('Pearson r'); ylim([-1 1]); grid on; box off;
legend({'4 sensori','3 sensori'},'Location','best','FontSize',11);
for k=1:3
    text(k-w, configs(1).r_T(k) + sign(configs(1).r_T(k))*0.05, ...
        sprintf('%.3f',configs(1).r_T(k)),'HorizontalAlignment','center', ...
        'FontSize',10,'Color',COL_4,'FontWeight','bold');
    text(k+w, configs(2).r_T(k) + sign(configs(2).r_T(k))*0.05, ...
        sprintf('%.3f',configs(2).r_T(k)),'HorizontalAlignment','center', ...
        'FontSize',10,'Color',COL_3,'FontWeight','bold');
end

subplot(1,2,2); hold on;
title('r(PC₁, RH)','FontWeight','bold','FontSize',13);
bar(xs - w, configs(1).r_RH, w*1.8,'FaceColor',COL_4,'EdgeColor','white','LineWidth',1.5);
bar(xs + w, configs(2).r_RH, w*1.8,'FaceColor',COL_3,'EdgeColor','white','LineWidth',1.5);
yline(0,'-','Color',C_grig,'LineWidth',0.8);
yline( 0.3,':','Color',C_grig,'LineWidth',1,'Alpha',0.5);
yline(-0.3,':','Color',C_grig,'LineWidth',1,'Alpha',0.5);
set(gca,'XTick',xs,'XTickLabel',scale_labels,'FontSize',12);
ylabel('Pearson r'); ylim([-1 1]); grid on; box off;
legend({'4 sensori','3 sensori'},'Location','best','FontSize',11);
for k=1:3
    text(k-w, configs(1).r_RH(k) + sign(configs(1).r_RH(k))*0.05, ...
        sprintf('%.3f',configs(1).r_RH(k)),'HorizontalAlignment','center', ...
        'FontSize',10,'Color',COL_4,'FontWeight','bold');
    text(k+w, configs(2).r_RH(k) + sign(configs(2).r_RH(k))*0.05, ...
        sprintf('%.3f',configs(2).r_RH(k)),'HorizontalAlignment','center', ...
        'FontSize',10,'Color',COL_3,'FontWeight','bold');
end

sgtitle('Correlazione PC₁ con variabili ambientali — 4s vs 3s', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig3, fullfile(outDir,'fig03_PC1_env_correlation.png'));

%% ─── FIG 4: σ_roll vs σ_global — gap ridotto senza cmos4? ───────────────
fprintf('Plot Fig 4: sigma roll vs global...\n');
fig4 = figure('Position',[50 50 800 450]);
hold on;

names_bars = {'σ_{global} 4s','σ_{roll} 4s','σ_{global} 3s','σ_{roll} 3s'};
vals_bars  = [configs(1).sig_pc1, configs(1).sig_roll_mean, ...
              configs(2).sig_pc1, configs(2).sig_roll_mean];
bar_colors = [COL_4; COL_4*0.5+0.5; COL_3; COL_3*0.5+0.5];

b = bar(1:4, vals_bars, 0.6, 'FaceColor','flat','EdgeColor','white','LineWidth',1.5);
for k=1:4, b.CData(k,:) = bar_colors(k,:); end

for k=1:4
    text(k, vals_bars(k)+0.01, sprintf('%.3f', vals_bars(k)), ...
        'HorizontalAlignment','center','FontSize',12,'FontWeight','bold', ...
        'Color', bar_colors(k,:));
end

% Rapporto σ_roll/σ_global
gap4 = 100*(1 - configs(1).sig_roll_mean/configs(1).sig_pc1);
gap3 = 100*(1 - configs(2).sig_roll_mean/configs(2).sig_pc1);
text(0.5, 0.93, sprintf('Gap 4s: %.0f%% varianza stagionale in σ_{global}', gap4), ...
    'Units','normalized','FontSize',11,'Color',COL_4,'FontWeight','bold', ...
    'BackgroundColor','white','EdgeColor',COL_4);
text(0.5, 0.83, sprintf('Gap 3s: %.0f%% varianza stagionale in σ_{global}', gap3), ...
    'Units','normalized','FontSize',11,'Color',COL_3,'FontWeight','bold', ...
    'BackgroundColor','white','EdgeColor',COL_3);

set(gca,'XTick',1:4,'XTickLabel',names_bars,'FontSize',12);
ylabel('σ di PC₁');
title('Varianza stagionale in σ_{global}  —  si riduce senza cmos4?', ...
    'FontWeight','bold');
grid on; box off;
saveas(fig4, fullfile(outDir,'fig04_sigma_roll_vs_global.png'));

%% ─── FIG 5: PC1 nel tempo — 4s vs 3s (con LOD) ──────────────────────────
fprintf('Plot Fig 5: PC1 timeline...\n');
fig5 = figure('Position',[50 50 1400 600]);

for ci = 1:2
    cfg = configs(ci);
    subplot(2,1,ci); hold on;

    % Media giornaliera per leggibilità
    PC1_day = nan(nH,1);
    days_id = floor(datenum(t_h));
    for d = unique(days_id)'
        idx_d = days_id == d;
        PC1_day(idx_d) = mean(cfg.PC1_all(idx_d),'omitnan');
    end

    plot(t_h, PC1_day, '-', 'Color', [cfg.color 0.6], 'LineWidth', 1.2);
    yline(cfg.lod_lo,'--','Color',cfg.color,'LineWidth',2, ...
        'Label',sprintf('LOD⁻ = %.2f', cfg.lod_lo),'FontSize',10);
    yline(0, '-', 'Color', C_grig, 'LineWidth', 0.8);

    % Evidenzia eventi
    evt_days = PC1_day < cfg.lod_lo;
    scatter(t_h(evt_days), PC1_day(evt_days), 8, cfg.color, 'filled', ...
        'MarkerFaceAlpha', 0.4);

    ylabel('PC₁'); grid on; box off; set(gca,'FontSize',11);
    title(sprintf('%s  |  eventi: %.2f%%  |  bias stagionale: %.2f σ', ...
        cfg.name, cfg.pct_fixed, cfg.bias_range/cfg.sig_pc1), ...
        'FontWeight','bold');
end
sgtitle('PC₁ nel tempo  —  4 sensori vs 3 sensori', ...
    'FontWeight','bold','FontSize',14,'Color',C_blu);
saveas(fig5, fullfile(outDir,'fig05_PC1_timeline_3vs4.png'));

%% ─── FIG 6: Concordanza eventi 3s vs 4s ─────────────────────────────────
fprintf('Plot Fig 6: concordanza eventi...\n');
fig6 = figure('Position',[50 50 800 480]);

evt4 = configs(1).evt_fixed;
evt3 = configs(2).evt_fixed;

both    = evt4 & evt3;
only4   = evt4 & ~evt3;
only3   = ~evt4 & evt3;
neither = ~evt4 & ~evt3;

vals_venn = [mean(both), mean(only4), mean(only3)]*100;
labels_venn = {sprintf('Entrambi\n%.2f%%', vals_venn(1)), ...
               sprintf('Solo 4s\n%.2f%%',  vals_venn(2)), ...
               sprintf('Solo 3s\n%.2f%%',  vals_venn(3))};
bar_c = [C_azzlt; COL_4; COL_3];
b = bar(1:3, vals_venn, 0.6, 'FaceColor','flat','EdgeColor','white','LineWidth',1.5);
for k=1:3, b.CData(k,:) = bar_c(k,:); end
hold on;
for k=1:3
    text(k, vals_venn(k)+0.05, sprintf('%.2f%%', vals_venn(k)), ...
        'HorizontalAlignment','center','FontSize',13,'FontWeight','bold', ...
        'Color', bar_c(k,:));
end
set(gca,'XTick',1:3,'XTickLabel',labels_venn,'FontSize',12);
ylabel('% campioni totali');
title('Sovrapposizione eventi: 3s vs 4s (LOD fisso, k=3)','FontWeight','bold');
grid on; box off;

concordance_12 = 100*mean(evt4 == evt3);
text(0.98, 0.95, sprintf('Concordanza totale: %.2f%%', concordance_12), ...
    'Units','normalized','HorizontalAlignment','right','FontSize',12, ...
    'FontWeight','bold','Color',C_blu, ...
    'BackgroundColor','white','EdgeColor',C_blu);

saveas(fig6, fullfile(outDir,'fig06_event_concordance.png'));

%% ══════════════════════════════════════════════════════════════════════════
%% SALVATAGGIO
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\nSalvataggio output...\n');

save(fullfile(outDir,'pca_3vs4_results.mat'), 'configs', 'months_avail');

% Tabella riepilogativa
T_out = table( ...
    {'4 sensori (cmos1-4)'; '3 sensori (cmos1-3)'}, ...
    [configs(1).explained(1); configs(2).explained(1)], ...
    [configs(1).sig_pc1;      configs(2).sig_pc1], ...
    [configs(1).lod_lo;       configs(2).lod_lo], ...
    [configs(1).pct_fixed;    configs(2).pct_fixed], ...
    [configs(1).pct_roll;     configs(2).pct_roll], ...
    [configs(1).concordance;  configs(2).concordance], ...
    [configs(1).bias_range/configs(1).sig_pc1; configs(2).bias_range/configs(2).sig_pc1], ...
    [configs(1).sig_roll_mean/configs(1).sig_pc1; configs(2).sig_roll_mean/configs(2).sig_pc1], ...
    'VariableNames', {'Config','PC1_var_pct','sigma_pc1','LOD_lo', ...
                      'pct_eventi_fisso','pct_eventi_rolling', ...
                      'concordanza_fix_roll','bias_stagionale_sigma', ...
                      'sigma_roll_ratio'});
writetable(T_out, fullfile(outDir,'summary_3vs4.csv'));
fprintf('   ✓ summary_3vs4.csv\n');
fprintf('   ✓ pca_3vs4_results.mat\n\n');

%% ══════════════════════════════════════════════════════════════════════════
%% RIEPILOGO A SCHERMO
%% ══════════════════════════════════════════════════════════════════════════
fprintf('══════════════════════════════════════════════════════════════════\n');
fprintf('%-35s  %12s  %12s\n', 'Metrica', '4 sensori', '3 sensori');
fprintf('%-35s  %12s  %12s\n', repmat('-',1,35), repmat('-',1,12), repmat('-',1,12));
metrics = { ...
    'PC₁ varianza spiegata (%)',          configs(1).explained(1),          configs(2).explained(1); ...
    'σ_global PC₁',                       configs(1).sig_pc1,               configs(2).sig_pc1; ...
    'LOD⁻ (k=3)',                         configs(1).lod_lo,                configs(2).lod_lo; ...
    'Tasso eventi fisso (%)',             configs(1).pct_fixed,             configs(2).pct_fixed; ...
    'Tasso eventi rolling (%)',           configs(1).pct_roll,              configs(2).pct_roll; ...
    'Concordanza fisso/rolling (%)',      configs(1).concordance,           configs(2).concordance; ...
    'Bias stagionale (range in σ)',       configs(1).bias_range/configs(1).sig_pc1, configs(2).bias_range/configs(2).sig_pc1; ...
    'σ_roll / σ_global',                  configs(1).sig_roll_mean/configs(1).sig_pc1, configs(2).sig_roll_mean/configs(2).sig_pc1; ...
    'r(PC1,T) mensile',                   configs(1).r_T(3),               configs(2).r_T(3); ...
    'r(PC1,RH) mensile',                  configs(1).r_RH(3),              configs(2).r_RH(3); ...
};
for k = 1:size(metrics,1)
    fprintf('%-35s  %12.4f  %12.4f\n', metrics{k,1}, metrics{k,2}, metrics{k,3});
end
fprintf('\nOutput: %s\n=== DONE ===\n', outDir);

%% ══════════════════════════════════════════════════════════════════════════
%% HELPER
%% ══════════════════════════════════════════════════════════════════════════
function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
