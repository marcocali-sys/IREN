function ELLONA_10_event_browser()
%ELLONA_10_EVENT_BROWSER  Browser interattivo event detection ELLONA.
%
%   figure + uicontrol + axes classici — MATLAB R2018b+
%
%   Controlli:
%     ▸ 📅 + HH:MM → selezione precisa periodo con calendario popup
%     ▸ Campo k  → soglia LOD digitata da tastiera (invio per applicare)
%     ▸ ◀1g  ◀1sett  1sett▶  1mese▶  → navigazione rapida
%     ▸ Clic+trascina sull'overview → selezione visiva
%     ▸ Export PNG del pannello dettaglio
%
%   Info bar mostra durata eventi: totale, media, max per blocco.
%
%   Marco Calì — PoliMi, Aprile 2026

scriptDir = fileparts(mfilename('fullpath'));
baseDir   = fullfile(scriptDir, '..', '..');
outDir    = fullfile(baseDir, 'output', 'event_detection');
procDir   = fullfile(baseDir, 'data',   'processed');

%% ── CARICA MODELLO ───────────────────────────────────────────────────────
modelFile = fullfile(outDir, 'pca_model_ELLONA.mat');
if ~isfile(modelFile)
    [f,p] = uigetfile(fullfile(outDir,'*.mat'),'Seleziona pca_model_ELLONA.mat');
    if isequal(f,0), return; end
    modelFile = fullfile(p,f);
end
M = load(modelFile);
fprintf('Modello: baseline=%s, k=%.0f, predictors=[%s]\n', ...
    M.baselineMode, M.k_lod, strjoin(cellstr(M.predictors),','));

%% ── CARICA DATI ──────────────────────────────────────────────────────────
dataFile = fullfile(procDir, 'monitoring_all.mat');
if ~isfile(dataFile)
    [f,p] = uigetfile(fullfile(procDir,'*.mat'),'Seleziona monitoring_all.mat');
    if isequal(f,0), return; end
    dataFile = fullfile(p,f);
end
fprintf('Caricamento dati... '); tic;
S = load(dataFile,'DATA'); DATA = S.DATA;
fprintf('%.1fs  (%d righe)\n', toc, height(DATA));

%% ── CALCOLO SCORE PCA ────────────────────────────────────────────────────
fprintf('Calcolo score... '); tic;
X = DATA{:, cellstr(M.predictors)};
for j = 1:size(X,2)
    nm = isnan(X(:,j));
    if any(nm), X(nm,j) = median(X(~nm,j)); end
end
SC  = ((X - M.mu) ./ M.sigma - M.muPCA) * M.coeff;
PC1 = SC(:,1);
t   = DATA.datetime;
fprintf('%.1fs\n', toc);

%% ── DOWNSAMPLE OVERVIEW ──────────────────────────────────────────────────
step  = max(1, floor(numel(t)/80000));
idx   = 1:step:numel(t);
t_ds  = t(idx);
p1_ds = PC1(idx);

% Stima dt in secondi (per calcolo durata eventi)
dt_s = seconds(median(diff(t(1:min(10000,end)))));

%% ── STATO APPLICAZIONE ───────────────────────────────────────────────────
a.t     = t;
a.PC1   = PC1;
a.M     = M;
a.t_ds  = t_ds;
a.p1_ds = p1_ds;
a.dt_s  = dt_s;
a.outDir = outDir;
a.k      = M.k_lod;
a.drag   = false;
a.dragX0 = NaT;

t0   = datetime(2025,8,1);
if t0 < t(1) || t0 > t(end), t0 = t(1); end
a.tS = t0;
a.tE = min(t0 + days(7), t(end));
a    = recalc(a);

%% ── BUILD FIGURE ─────────────────────────────────────────────────────────
BG = [0.95 0.95 0.97];
fig = figure('Name','ELLONA — Event Browser', ...
    'Units','pixels','Position',[50 30 1440 870], ...
    'Color',BG,'Toolbar','none','Menubar','none','NumberTitle','off');

% ──────────────── AXES ────────────────────────────────────────────────────
%  Layout verticale (normalizzato, dal basso):
%  0.000–0.038  status bar
%  0.042–0.510  detail axes
%  0.515–0.548  info durata
%  0.552–0.582  info range/eventi
%  0.588–0.848  overview axes
%  0.855–0.905  control row 2  (date/time)
%  0.912–0.962  control row 1  (nav + k + export)

axOv = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.070 0.632 0.918 0.220], ...
    'Box','on','XGrid','on','YGrid','on','FontSize',9);
title(axOv,'PC₁(t) — Overview  ·  clic + trascina per selezionare il periodo','FontSize',10);
ylabel(axOv,'PC₁'); xlabel(axOv,'');

axDet = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.070 0.092 0.918 0.445], ...
    'Box','on','XGrid','on','YGrid','on','FontSize',9);
xlabel(axDet,''); ylabel(axDet,'PC₁');

% ──────────────── CONTROL ROW 1 — nav + k + export ───────────────────────
R1y = 0.918; Rh = 0.044;
bw  = 0.068; bs = 0.004;

uicontrol(fig,'Style','pushbutton','String','◀ 1 g', ...
    'Units','normalized','Position',[0.008          R1y bw Rh], ...
    'Callback',@(~,~) nav(fig,-1,'day'));
uicontrol(fig,'Style','pushbutton','String','◀ 1 sett', ...
    'Units','normalized','Position',[0.008+bw+bs    R1y bw Rh], ...
    'Callback',@(~,~) nav(fig,-7,'day'));
uicontrol(fig,'Style','pushbutton','String','1 sett ▶', ...
    'Units','normalized','Position',[0.008+2*(bw+bs) R1y bw Rh], ...
    'Callback',@(~,~) nav(fig,+7,'day'));
uicontrol(fig,'Style','pushbutton','String','1 mese ▶', ...
    'Units','normalized','Position',[0.008+3*(bw+bs) R1y bw Rh], ...
    'Callback',@(~,~) nav(fig,+1,'month'));

uicontrol(fig,'Style','text','String','k LOD:', ...
    'Units','normalized','Position',[0.345 R1y 0.042 Rh], ...
    'BackgroundColor',BG,'FontWeight','bold','FontSize',10, ...
    'HorizontalAlignment','right');
edtK = uicontrol(fig,'Style','edit', ...
    'String',sprintf('%.1f',a.k), ...
    'Units','normalized','Position',[0.391 R1y 0.058 Rh], ...
    'TooltipString','Soglia LOD: digita k e premi Invio', ...
    'Callback',@(src,~) set_k_str(fig, src.String));

uicontrol(fig,'Style','pushbutton','String','💾 Export PNG', ...
    'Units','normalized','Position',[0.878 R1y 0.115 Rh], ...
    'Callback',@(~,~) export_png(fig));

% ──────────────── CONTROL ROW 2 — date / time ────────────────────────────
R2y = 0.860;
% Da:
uicontrol(fig,'Style','text','String','Da:', ...
    'Units','normalized','Position',[0.008 R2y+0.007 0.024 0.030], ...
    'BackgroundColor',BG,'FontWeight','bold');
uicontrol(fig,'Style','pushbutton','String','📅', ...
    'Units','normalized','Position',[0.034 R2y 0.030 Rh], ...
    'TooltipString','Apri calendario', ...
    'Callback',@(~,~) open_cal(fig,'start'));
edtSD = uicontrol(fig,'Style','edit', ...
    'String',char(a.tS,'dd-MMM-yyyy'), ...
    'Units','normalized','Position',[0.068 R2y 0.105 Rh], ...
    'TooltipString','Formato: dd-MMM-yyyy', ...
    'Callback',@(src,~) set_date_str(fig,'start',src.String));
uicontrol(fig,'Style','text','String','HH:', ...
    'Units','normalized','Position',[0.177 R2y+0.007 0.025 0.030], ...
    'BackgroundColor',BG);
edtSH = uicontrol(fig,'Style','edit', ...
    'String',sprintf('%02d',hour(a.tS)), ...
    'Units','normalized','Position',[0.205 R2y 0.036 Rh], ...
    'Callback',@(src,~) set_time(fig,'start_h',src.String));
uicontrol(fig,'Style','text','String',':', ...
    'Units','normalized','Position',[0.243 R2y+0.007 0.010 0.030], ...
    'BackgroundColor',BG,'FontSize',12,'FontWeight','bold');
edtSM = uicontrol(fig,'Style','edit', ...
    'String',sprintf('%02d',minute(a.tS)), ...
    'Units','normalized','Position',[0.255 R2y 0.036 Rh], ...
    'Callback',@(src,~) set_time(fig,'start_m',src.String));

uicontrol(fig,'Style','text','String','→', ...
    'Units','normalized','Position',[0.300 R2y+0.006 0.028 0.032], ...
    'BackgroundColor',BG,'FontSize',13,'FontWeight','bold');

% A:
uicontrol(fig,'Style','text','String','A:', ...
    'Units','normalized','Position',[0.338 R2y+0.007 0.020 0.030], ...
    'BackgroundColor',BG,'FontWeight','bold');
uicontrol(fig,'Style','pushbutton','String','📅', ...
    'Units','normalized','Position',[0.362 R2y 0.030 Rh], ...
    'TooltipString','Apri calendario', ...
    'Callback',@(~,~) open_cal(fig,'end'));
edtED = uicontrol(fig,'Style','edit', ...
    'String',char(a.tE,'dd-MMM-yyyy'), ...
    'Units','normalized','Position',[0.396 R2y 0.105 Rh], ...
    'TooltipString','Formato: dd-MMM-yyyy', ...
    'Callback',@(src,~) set_date_str(fig,'end',src.String));
uicontrol(fig,'Style','text','String','HH:', ...
    'Units','normalized','Position',[0.505 R2y+0.007 0.025 0.030], ...
    'BackgroundColor',BG);
edtEH = uicontrol(fig,'Style','edit', ...
    'String',sprintf('%02d',hour(a.tE)), ...
    'Units','normalized','Position',[0.533 R2y 0.036 Rh], ...
    'Callback',@(src,~) set_time(fig,'end_h',src.String));
uicontrol(fig,'Style','text','String',':', ...
    'Units','normalized','Position',[0.571 R2y+0.007 0.010 0.030], ...
    'BackgroundColor',BG,'FontSize',12,'FontWeight','bold');
edtEM = uicontrol(fig,'Style','edit', ...
    'String',sprintf('%02d',minute(a.tE)), ...
    'Units','normalized','Position',[0.583 R2y 0.036 Rh], ...
    'Callback',@(src,~) set_time(fig,'end_m',src.String));

% ──────────────── INFO BAR ────────────────────────────────────────────────
lblRng = uicontrol(fig,'Style','text','String','—', ...
    'Units','normalized','Position',[0.005 0.578 0.550 0.028], ...
    'BackgroundColor',BG,'HorizontalAlignment','left','FontSize',9);
lblEvt = uicontrol(fig,'Style','text','String','—', ...
    'Units','normalized','Position',[0.560 0.578 0.280 0.028], ...
    'BackgroundColor',BG,'FontWeight','bold','FontSize',10, ...
    'ForegroundColor',[0.80 0.08 0.05],'HorizontalAlignment','center');
lblLOD = uicontrol(fig,'Style','text','String','—', ...
    'Units','normalized','Position',[0.844 0.578 0.150 0.028], ...
    'BackgroundColor',BG,'FontSize',9,'HorizontalAlignment','right');

lblDur = uicontrol(fig,'Style','text','String','—', ...
    'Units','normalized','Position',[0.005 0.545 0.988 0.028], ...
    'BackgroundColor',[0.91 0.91 0.94],'HorizontalAlignment','left', ...
    'FontSize',9,'ForegroundColor',[0.20 0.20 0.40]);

% ──────────────── STATUS BAR ─────────────────────────────────────────────
uicontrol(fig,'Style','text', ...
    'String', sprintf('  %d righe · baseline=%s · predictors: [%s] · dt≈%.0fs', ...
        numel(t), M.baselineMode, strjoin(cellstr(M.predictors),','), dt_s), ...
    'Units','normalized','Position',[0 0 1 0.038], ...
    'BackgroundColor',[0.85 0.85 0.88],'FontSize',8, ...
    'HorizontalAlignment','left');

% ──────────────── SALVA HANDLES ──────────────────────────────────────────
a.axOv  = axOv;   a.axDet = axDet;
a.edtK  = edtK;
a.edtSD = edtSD;  a.edtSH = edtSH;  a.edtSM = edtSM;
a.edtED = edtED;  a.edtEH = edtEH;  a.edtEM = edtEM;
a.lblRng = lblRng; a.lblEvt = lblEvt;
a.lblLOD = lblLOD; a.lblDur = lblDur;
guidata(fig, a);

% ──────────────── MOUSE CALLBACKS ────────────────────────────────────────
set(axOv,'ButtonDownFcn',       @(src,~) ov_down(fig,src));
set(fig, 'WindowButtonMotionFcn',@(f,~)  ov_move(f));
set(fig, 'WindowButtonUpFcn',    @(f,~)  ov_up(f));

%% ── PRIMO DISEGNO ────────────────────────────────────────────────────────
draw_ov(fig);
draw_det(fig);

end   % ── fine ELLONA_10_event_browser ──


%% ══════════════════════════ FUNZIONI LOCALI ══════════════════════════════

% ── Ricalcola LOD e isEvent ───────────────────────────────────────────────
function a = recalc(a)
    a.lod_lo  = a.M.mu_pc1 - a.k * a.M.sigma_pc1;
    a.lod_hi  = a.M.mu_pc1 + a.k * a.M.sigma_pc1;
    a.isEvent = a.PC1 < a.lod_lo;
end

% ── Overview plot ─────────────────────────────────────────────────────────
function draw_ov(fig)
    a  = guidata(fig);
    ax = a.axOv;
    cla(ax); hold(ax,'on');

    plot(ax, a.t_ds, a.p1_ds, '-', 'Color',[0.68 0.78 0.93], 'LineWidth',0.5);

    rng_y = max(a.p1_ds) - min(a.p1_ds);
    ylo   = min(a.p1_ds) - 0.04*rng_y;
    yhi   = max(a.p1_ds) + 0.04*rng_y;
    patch(ax,[a.tS a.tE a.tE a.tS],[ylo ylo yhi yhi], ...
        [0.99 0.88 0.10],'FaceAlpha',0.30, ...
        'EdgeColor',[0.75 0.55 0.00],'LineWidth',1.2);

    yline(ax, a.lod_lo, '-', 'Color',[0.12 0.62 0.12],'LineWidth',1.5);
    yline(ax, a.lod_hi, '-', 'Color',[0.12 0.62 0.12],'LineWidth',1.5);
    yline(ax, a.M.mu_pc1,'--','Color',[0.55 0.55 0.55],'LineWidth',0.8);

    hold(ax,'off');
    xlim(ax,[a.t(1) a.t(end)]);
    ylim(ax,[ylo yhi]);
    % Formato etichette asse x — overview sempre full-year
    ax.XAxis.TickLabelFormat = 'MMM-yy';
    ax.XTickLabelRotation    = 0;
    ax.FontSize = 9;
end

% ── Detail plot + stats durata ────────────────────────────────────────────
function draw_det(fig)
    a  = guidata(fig);
    ax = a.axDet;

    mask = a.t >= a.tS & a.t <= a.tE;
    tw   = a.t(mask);
    p1w  = a.PC1(mask);
    ew   = a.isEvent(mask);
    nW   = numel(tw);
    nE   = sum(ew);

    cla(ax); hold(ax,'on');

    if nW == 0
        text(ax,0.5,0.5,'Nessun dato nel periodo selezionato', ...
            'Units','normalized','HorizontalAlignment','center','FontSize',12);
        hold(ax,'off'); return;
    end

    plot(ax, tw, p1w, '-', 'Color',[0.68 0.78 0.93],'LineWidth',0.7);
    if any(ew)
        plot(ax, tw(ew), p1w(ew), '.','Color',[0.87 0.12 0.06],'MarkerSize',5);
    end

    yline(ax, a.lod_lo,'-', sprintf('LOD- = %.3f',a.lod_lo), ...
        'Color',[0.12 0.62 0.12],'LineWidth',2.2, ...
        'LabelHorizontalAlignment','left','FontSize',9);
    yline(ax, a.lod_hi,'-', sprintf('LOD+ = %.3f',a.lod_hi), ...
        'Color',[0.12 0.62 0.12],'LineWidth',2.2, ...
        'LabelHorizontalAlignment','left','FontSize',9);
    yline(ax, a.M.mu_pc1,'--',sprintf('mu_BL = %.4f',a.M.mu_pc1), ...
        'Color',[0.55 0.55 0.55],'LineWidth',1.0);

    hold(ax,'off');
    xlim(ax,[a.tS a.tE]);
    % Formato etichette asse x — adattivo alla durata della finestra
    dur = a.tE - a.tS;
    if     dur < hours(2),   tFmt = 'HH:mm:ss';
    elseif dur < hours(12),  tFmt = 'HH:mm  dd-MMM';
    elseif dur < days(2),    tFmt = 'dd-MMM  HH:mm';
    elseif dur < days(14),   tFmt = 'dd-MMM';
    else,                    tFmt = 'dd-MMM-yy';
    end
    ax.XAxis.TickLabelFormat = tFmt;
    ax.XTickLabelRotation    = 20;
    ax.FontSize = 9;
    title(ax, sprintf('Dettaglio  |  %d campioni (dt=%.0fs)  |  eventi: %d / %d  (%.1f%%)', ...
        nW, a.dt_s, nE, nW, 100*nE/max(nW,1)),'FontSize',10);

    % ── Calcola durata eventi ─────────────────────────────────────────────
    st = event_stats(ew, a.dt_s);

    % Info bar - riga 1
    set(a.lblRng,'String', sprintf('%s  →  %s   (%.2f giorni)', ...
        char(a.tS,'dd-MMM-yyyy HH:mm'), char(a.tE,'dd-MMM-yyyy HH:mm'), ...
        days(a.tE - a.tS)));
    set(a.lblEvt,'String', sprintf('%d eventi in %d blocchi  (%.1f%%)', ...
        nE, st.n_blocks, 100*nE/max(nW,1)));
    set(a.lblLOD,'String', sprintf('LOD = mu+/-%.1f*s = [%.3f, %.3f]', ...
        a.k, a.lod_lo, a.lod_hi));

    % Info bar - riga 2 (durata)
    if st.n_blocks > 0
        durStr = sprintf( ...
            'Durata tot: %s  |  Media/blocco: %s  |  Max blocco: %s  |  Min blocco: %s', ...
            fmt_dur(st.total_s), fmt_dur(st.mean_s), fmt_dur(st.max_s), fmt_dur(st.min_s));
    else
        durStr = 'Nessun evento nel periodo selezionato';
    end
    set(a.lblDur,'String', ['  ' durStr]);
end

% ── Navigazione ───────────────────────────────────────────────────────────
function nav(fig, delta, unit)
    a = guidata(fig);
    w = a.tE - a.tS;
    switch lower(unit)
        case 'day',   sh = days(delta);
        case 'month', sh = calmonths(delta);
    end
    a.tS = a.tS + sh;  a.tE = a.tE + sh;
    if a.tS < a.t(1),   a.tS = a.t(1);     a.tE = a.t(1)+w;    end
    if a.tE > a.t(end), a.tE = a.t(end);   a.tS = a.t(end)-w;  end
    guidata(fig,a);
    sync_date_fields(fig);
    draw_ov(fig); draw_det(fig);
end

% ── Imposta k da tastiera ─────────────────────────────────────────────────
function set_k_str(fig, str)
    a    = guidata(fig);
    kval = str2double(str);
    if isnan(kval) || kval <= 0 || kval > 20
        set(a.edtK,'String',sprintf('%.1f',a.k));   % ripristina
        return;
    end
    a.k = kval;
    a   = recalc(a);
    guidata(fig,a);
    draw_ov(fig); draw_det(fig);
end

% ── Calendario popup ──────────────────────────────────────────────────────
function open_cal(fig, which_end)
    a = guidata(fig);
    t_init = a.tS;
    if strcmp(which_end,'end'), t_init = a.tE; end

    t_sel = calendar_picker(t_init, a.t(1), a.t(end));
    if isnat(t_sel), return; end   % annullato

    % Preserva l'ora corrente, aggiorna solo il giorno
    if strcmp(which_end,'start')
        a.tS = datetime(year(t_sel),month(t_sel),day(t_sel), ...
                        hour(a.tS),minute(a.tS),0);
        a.tS = max(a.tS, a.t(1));
    else
        a.tE = datetime(year(t_sel),month(t_sel),day(t_sel), ...
                        hour(a.tE),minute(a.tE),0);
        a.tE = min(a.tE, a.t(end));
    end
    if a.tS >= a.tE, a.tE = a.tS + hours(1); end
    guidata(fig,a);
    sync_date_fields(fig);
    draw_ov(fig); draw_det(fig);
end

% ── Imposta data da campo testo ───────────────────────────────────────────
function set_date_str(fig, which_end, str)
    a = guidata(fig);
    try
        tNew = datetime(str,'InputFormat','dd-MMM-yyyy');
    catch
        sync_date_fields(fig); return;
    end
    if strcmp(which_end,'start')
        a.tS = datetime(year(tNew),month(tNew),day(tNew), ...
                        hour(a.tS),minute(a.tS),0);
        a.tS = max(a.tS, a.t(1));
    else
        a.tE = datetime(year(tNew),month(tNew),day(tNew), ...
                        hour(a.tE),minute(a.tE),0);
        a.tE = min(a.tE, a.t(end));
    end
    if a.tS >= a.tE, a.tE = a.tS + hours(1); end
    guidata(fig,a);
    sync_date_fields(fig);
    draw_ov(fig); draw_det(fig);
end

% ── Imposta ora / minuti ──────────────────────────────────────────────────
function set_time(fig, which, str)
    a   = guidata(fig);
    val = max(0, min(str2double(str), ...
        iif(contains(which,'_h'), 23, 59)));
    if isnan(val), sync_date_fields(fig); return; end
    val = round(val);
    switch which
        case 'start_h'
            a.tS = datetime(year(a.tS),month(a.tS),day(a.tS),val,minute(a.tS),0);
        case 'start_m'
            a.tS = datetime(year(a.tS),month(a.tS),day(a.tS),hour(a.tS),val,0);
        case 'end_h'
            a.tE = datetime(year(a.tE),month(a.tE),day(a.tE),val,minute(a.tE),0);
        case 'end_m'
            a.tE = datetime(year(a.tE),month(a.tE),day(a.tE),hour(a.tE),val,0);
    end
    a.tS = max(a.tS, a.t(1));
    a.tE = min(a.tE, a.t(end));
    if a.tS >= a.tE, a.tE = a.tS + hours(1); end
    guidata(fig,a);
    sync_date_fields(fig);
    draw_ov(fig); draw_det(fig);
end

% ── Sincronizza campi testo con stato interno ─────────────────────────────
function sync_date_fields(fig)
    a = guidata(fig);
    set(a.edtSD,'String', char(a.tS,'dd-MMM-yyyy'));
    set(a.edtSH,'String', sprintf('%02d',hour(a.tS)));
    set(a.edtSM,'String', sprintf('%02d',minute(a.tS)));
    set(a.edtED,'String', char(a.tE,'dd-MMM-yyyy'));
    set(a.edtEH,'String', sprintf('%02d',hour(a.tE)));
    set(a.edtEM,'String', sprintf('%02d',minute(a.tE)));
    set(a.edtK, 'String', sprintf('%.1f',a.k));
end

% ── Mouse callbacks ───────────────────────────────────────────────────────
function ov_down(fig, ax)
    a  = guidata(fig);
    cp = get(ax,'CurrentPoint');
    xv = cp(1,1);
    if ~isa(xv,'datetime')
        xv = datetime(xv,'ConvertFrom','datenum');
    end
    xv = max(xv,a.t(1)); xv = min(xv,a.t(end));
    a.drag = true; a.dragX0 = xv;
    a.tS   = xv;   a.tE = min(xv+hours(24), a.t(end));
    guidata(fig,a);
    sync_date_fields(fig);
    draw_ov(fig);
end

function ov_move(fig)
    a = guidata(fig);
    if ~a.drag, return; end
    ax = a.axOv;
    cp = get(ax,'CurrentPoint');
    xv = cp(1,1);
    if ~isa(xv,'datetime'), xv = datetime(xv,'ConvertFrom','datenum'); end
    xv = max(xv,a.t(1)); xv = min(xv,a.t(end));
    if xv > a.dragX0, a.tS = a.dragX0; a.tE = xv;
    else,             a.tS = xv;        a.tE = a.dragX0; end
    if a.tE-a.tS < hours(1), a.tE = a.tS+hours(1); end
    guidata(fig,a);
    sync_date_fields(fig);
    draw_ov(fig);
end

function ov_up(fig)
    a = guidata(fig);
    if ~a.drag, return; end
    a.drag = false;
    guidata(fig,a);
    draw_det(fig);
end

% ── Export PNG ────────────────────────────────────────────────────────────
function export_png(fig)
    a = guidata(fig);
    fname = sprintf('detail_%s_to_%s_k%.0f.png', ...
        char(a.tS,'yyyyMMdd-HHmm'), char(a.tE,'yyyyMMdd-HHmm'), a.k);
    fout  = fullfile(a.outDir, fname);
    try
        exportgraphics(a.axDet, fout,'Resolution',300);
        msgbox(sprintf('Salvato:\n%s',fout),'Export OK','help');
        fprintf('Export: %s\n',fout);
    catch ME
        errordlg(ME.message,'Export fallito');
    end
end

% ── Statistiche durata eventi ─────────────────────────────────────────────
function st = event_stats(isEvt, dt_s)
    st.n_blocks = 0; st.total_s = 0;
    st.mean_s   = 0; st.max_s   = 0; st.min_s = 0;
    if ~any(isEvt), return; end
    chg    = diff([false; isEvt(:); false]);
    starts = find(chg ==  1);
    ends   = find(chg == -1) - 1;
    dur    = (ends - starts + 1) * dt_s;
    st.n_blocks = numel(dur);
    st.total_s  = sum(dur);
    st.mean_s   = mean(dur);
    st.max_s    = max(dur);
    st.min_s    = min(dur);
end

% ── Formatta durata in h/m/s ──────────────────────────────────────────────
function str = fmt_dur(s)
    s = round(s);
    if s <= 0, str = '0s'; return; end
    h = floor(s/3600); s = mod(s,3600);
    m = floor(s/60);   s = mod(s,60);
    if h > 0,     str = sprintf('%dh %02dm %02ds', h, m, s);
    elseif m > 0, str = sprintf('%dm %02ds', m, s);
    else,         str = sprintf('%ds', s);
    end
end

% ── Ternario inline ───────────────────────────────────────────────────────
function v = iif(cond, a, b)
    if cond, v = a; else, v = b; end
end

% ── CALENDARIO POPUP ─────────────────────────────────────────────────────
function t_out = calendar_picker(t_init, t_min, t_max)
%CALENDAR_PICKER  Finestra modale per selezione data.
    if nargin < 2, t_min = datetime(2000,1,1); end
    if nargin < 3, t_max = datetime(2100,1,1); end

    cal.yr    = year(t_init);
    cal.mo    = month(t_init);
    cal.sel   = day(t_init);
    cal.tmin  = t_min;
    cal.tmax  = t_max;
    cal.result = NaT;

    hf = figure('Name','Seleziona giorno', ...
        'Units','pixels','Position',[500 340 268 258], ...
        'Resize','off','Toolbar','none','Menubar','none', ...
        'NumberTitle','off','WindowStyle','modal', ...
        'Color',[0.97 0.97 0.99]);

    guidata(hf, cal);
    cal_draw(hf);
    uiwait(hf);

    if ishandle(hf)
        cal   = guidata(hf);
        t_out = cal.result;
        delete(hf);
    else
        t_out = NaT;
    end
end

function cal_draw(hf)
    cal = guidata(hf);
    BG  = [0.97 0.97 0.99];
    clf(hf); set(hf,'Color',BG);

    mesi = {'Gennaio','Febbraio','Marzo','Aprile','Maggio','Giugno', ...
            'Luglio','Agosto','Settembre','Ottobre','Novembre','Dicembre'};

    % Header navigazione mese
    uicontrol(hf,'Style','pushbutton','String','◀', ...
        'Units','normalized','Position',[0.02 0.890 0.10 0.095], ...
        'Callback',@(~,~) cal_prev(hf));
    uicontrol(hf,'Style','text', ...
        'String',sprintf('%s  %d', mesi{cal.mo}, cal.yr), ...
        'Units','normalized','Position',[0.13 0.890 0.74 0.095], ...
        'FontWeight','bold','FontSize',10,'BackgroundColor',BG);
    uicontrol(hf,'Style','pushbutton','String','▶', ...
        'Units','normalized','Position',[0.88 0.890 0.10 0.095], ...
        'Callback',@(~,~) cal_next(hf));

    % Intestazioni giorni
    gg = {'L','M','M','G','V','S','D'};
    CW = 0.96/7;
    for d = 1:7
        uicontrol(hf,'Style','text','String',gg{d}, ...
            'Units','normalized', ...
            'Position',[(d-1)*CW+0.02, 0.795, CW-0.01, 0.085], ...
            'FontWeight','bold','FontSize',9, ...
            'BackgroundColor',[0.88 0.88 0.94],'ForegroundColor',[0.2 0.2 0.5]);
    end

    % Griglia giorni
    nDays    = day(dateshift(datetime(cal.yr,cal.mo,1),'end','month'));
    firstCol = mod(weekday(datetime(cal.yr,cal.mo,1)) - 2, 7);
    today    = datetime('today');

    CH = 0.76/6;
    col = firstCol;  row = 5;

    for d = 1:nDays
        xp = col*CW + 0.02;
        yp = row*CH + 0.015;

        isSel   = (d == cal.sel);
        isToday = (cal.yr == year(today) && cal.mo == month(today) && d == day(today));
        % Check se fuori range dati
        tThis   = datetime(cal.yr, cal.mo, d);
        outRange = tThis < dateshift(cal.tmin,'start','day') || ...
                   tThis > dateshift(cal.tmax,'start','day');

        if isSel
            bg = [0.18 0.44 0.82]; fg = [1 1 1];
        elseif isToday
            bg = [0.78 0.90 1.00]; fg = [0 0 0];
        elseif outRange
            bg = BG; fg = [0.75 0.75 0.75];
        else
            bg = BG; fg = [0.10 0.10 0.10];
        end

        uicontrol(hf,'Style','pushbutton', ...
            'String',num2str(d), ...
            'Units','normalized', ...
            'Position',[xp, yp, CW-0.012, CH-0.012], ...
            'BackgroundColor',bg,'ForegroundColor',fg,'FontSize',9, ...
            'Callback',@(~,~) cal_select(hf, d));

        col = col+1;
        if col >= 7, col = 0; row = row-1; end
    end

    % Pulsante Annulla
    uicontrol(hf,'Style','pushbutton','String','Annulla', ...
        'Units','normalized','Position',[0.02 0.01 0.45 0.085], ...
        'Callback',@(~,~) uiresume(hf));
end

function cal_prev(hf)
    cal = guidata(hf);
    cal.mo = cal.mo - 1;
    if cal.mo < 1, cal.mo = 12; cal.yr = cal.yr-1; end
    cal.sel = min(cal.sel, day(dateshift(datetime(cal.yr,cal.mo,1),'end','month')));
    guidata(hf, cal); cal_draw(hf);
end

function cal_next(hf)
    cal = guidata(hf);
    cal.mo = cal.mo + 1;
    if cal.mo > 12, cal.mo = 1; cal.yr = cal.yr+1; end
    cal.sel = min(cal.sel, day(dateshift(datetime(cal.yr,cal.mo,1),'end','month')));
    guidata(hf, cal); cal_draw(hf);
end

function cal_select(hf, d)
    cal        = guidata(hf);
    cal.sel    = d;
    cal.result = datetime(cal.yr, cal.mo, d);
    guidata(hf, cal);
    uiresume(hf);
end
