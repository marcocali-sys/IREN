function IREN_09_monitoraggio_explorer()
% IREN_09_MONITORAGGIO_EXPLORER
% =========================================================================
% GUI interattiva per esplorare i dati di monitoraggio IREN 2025.
%
% Funzionalita':
%   - Caricamento automatico di tutti i CSV in data/raw/monitoraggio2025
%   - Normalizzazione colonne (gestisce dicembre_2025.csv con ordine diverso)
%   - Selezione variabili: MOX 1-4, ECS NH3/H2S, Temperatura, Umidita'
%   - Finestra temporale libera (data/ora inizio e fine)
%   - Shortcut: Tutto / Ultimo mese / Ultima settimana / Ultimo giorno
%   - Resampling opzionale (nessuno / 1min / 5min / 15min / 1h)
%   - Assi separati per gruppi a scale diverse (MOX / ECS / T+RH)
%
% Assunzioni:
%   - Separatore CSV: punto e virgola (;)
%   - Formato data: DD/MM/YYYY  |  Formato ora: HH:MM:SS
%   - Encoding: UTF-8
%   - Le 11 colonne sono sempre presenti ma possono essere in ordine diverso
%
% Dipendenze: MATLAB R2019b+ (uifigure, tiledlayout)
%
% Autore: [Marco Cali] - Progetto IREN
% =========================================================================

clearvars -except varargin;
clc;

%% === 0) Percorsi =========================================================
scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir, '..', '..', 'data', 'raw', 'monitoraggio2025');
dataDir   = char(java.io.File(dataDir).getCanonicalPath());   % risolve '..'

fprintf('============================================================\n');
fprintf(' IREN Monitoraggio 2025 — Explorer\n');
fprintf('============================================================\n');
fprintf('Cartella dati: %s\n\n', dataDir);

%% === 1) Caricamento dati (con cache .mat) ================================
cacheFile = fullfile(dataDir, '_cache_monitoraggio.mat');
T = carica_con_cache(dataDir, cacheFile);

%% === 2) Costruzione GUI =================================================
costruisci_gui(T);

end % function principale


% =========================================================================
%  CARICAMENTO DATI CON CACHE
% =========================================================================

function T = carica_con_cache(dataDir, cacheFile)
% Carica i CSV la prima volta e salva un .mat nella stessa cartella.
% Alle esecuzioni successive ricarica dalla cache se i file non sono cambiati.
%
% La cache viene invalidata se la data di modifica di qualsiasi CSV
% e' piu' recente della cache stessa.

    files = dir(fullfile(dataDir, '*.csv'));
    if isempty(files)
        error('Nessun file CSV trovato in:\n  %s', dataDir);
    end

    % ── Controlla se la cache e' valida ───────────────────────────────────
    if isfile(cacheFile)
        cache_info  = dir(cacheFile);
        cache_time  = cache_info.datenum;
        csv_times   = [files.datenum];
        if all(csv_times <= cache_time)
            fprintf('[CACHE] Cache valida trovata. Caricamento rapido...\n');
            tic;
            loaded = load(cacheFile, 'T');
            T = loaded.T;
            fprintf('[CACHE] Caricato in %.1f s  (%d righe)\n\n', toc, height(T));
            return
        else
            fprintf('[CACHE] File CSV modificati — rigenero la cache.\n\n');
        end
    end

    % ── Prima volta: leggi i CSV ──────────────────────────────────────────
    T = carica_tutti_i_file(dataDir, files);

    % ── Salva cache ───────────────────────────────────────────────────────
    fprintf('[CACHE] Salvataggio cache in corso...\n');
    save(cacheFile, 'T', '-v7.3');
    fprintf('[CACHE] Cache salvata: %s\n\n', cacheFile);
end


function T = carica_tutti_i_file(dataDir, files)
% Legge tutti i CSV, normalizza le colonne e li unisce in un'unica timetable.
% Usa opzioni di importazione esplicite (piu' veloce di detectImportOptions).

    % Nomi colonna canonici nei due ordini possibili
    % (standard: 11 file su 10; alternativo: dicembre_2025.csv)
    COLS_STANDARD    = {'date','time','cmos1','cmos2','cmos3','cmos4', ...
                        'temperature','humidity','nh3','h2s','pid'};
    COLS_ALTERNATIVO = {'date','time','temperature','humidity','cmos1','cmos2', ...
                        'cmos3','cmos4','pid','h2s','nh3'};

    % Tipi colonna: le prime 2 stringhe, le altre double
    N = numel(COLS_STANDARD);
    tipi_std = [{'char','char'}, repmat({'double'}, 1, N-2)];
    tipi_alt = tipi_std;   % stessa struttura, diverso ordine

    colonne_attese = {'cmos1','cmos2','cmos3','cmos4','temperature','humidity','nh3','h2s'};

    frames     = cell(numel(files), 1);
    n_caricati = 0;

    for k = 1:numel(files)
        fpath = fullfile(files(k).folder, files(k).name);
        fname = files(k).name;
        try
            % Leggi prima riga per capire l'ordine delle colonne
            fid   = fopen(fpath, 'r');
            hdr   = fgetl(fid);
            fclose(fid);
            hdr_cols = strsplit(lower(strtrim(hdr)), ';');

            % Scegli schema in base all'ordine rilevato
            if isequal(hdr_cols, COLS_ALTERNATIVO)
                col_names = COLS_ALTERNATIVO;
                col_types = tipi_alt;
            else
                col_names = COLS_STANDARD;
                col_types = tipi_std;
            end

            % Verifica colonne minime
            mancanti = setdiff(colonne_attese, hdr_cols);
            if ~isempty(mancanti)
                fprintf('[WARN] %s: colonne mancanti {%s} — saltato\n', ...
                    fname, strjoin(mancanti, ', '));
                continue
            end

            % Opzioni di importazione esplicite (evita detectImportOptions)
            opts = delimitedTextImportOptions( ...
                'NumVariables',       numel(col_names), ...
                'Delimiter',          ';',              ...
                'VariableNames',      col_names,        ...
                'VariableTypes',      col_types,        ...
                'DataLines',          [2 Inf],          ...
                'MissingRule',        'fill',           ...
                'ImportErrorRule',    'fill'            ...
            );

            raw = readtable(fpath, opts);

            n_caricati = n_caricati + 1;
            frames{n_caricati} = raw;
            fprintf('[OK]  Caricato %s  (%d righe)\n', fname, height(raw));

        catch ME
            fprintf('[ERR] Impossibile leggere %s: %s\n', fname, ME.message);
        end
    end

    if n_caricati == 0
        error('Nessun file caricato correttamente.');
    end
    frames = frames(1:n_caricati);

    % ── Concatenazione ────────────────────────────────────────────────────
    combined = vertcat(frames{:});

    % ── Parsing timestamp ─────────────────────────────────────────────────
    dt_str = strcat(strtrim(combined.date), {' '}, strtrim(combined.time));
    dt = datetime(dt_str, 'InputFormat', 'dd/MM/yyyy HH:mm:ss', ...
                  'Format', 'dd/MM/yyyy HH:mm:ss');

    bad = isnat(dt);
    if any(bad)
        fprintf('[WARN] %d righe con timestamp non valido rimosse.\n', sum(bad));
        combined(bad, :) = [];
        dt(bad) = [];
    end

    % ── Costruzione timetable ─────────────────────────────────────────────
    cols_num  = {'cmos1','cmos2','cmos3','cmos4','temperature','humidity','nh3','h2s'};
    cols_keep = intersect(combined.Properties.VariableNames, [cols_num, {'pid'}], 'stable');
    T_num = combined(:, cols_keep);
    T_num.datetime = dt;

    T_num = sortrows(T_num, 'datetime');

    [~, ia] = unique(T_num.datetime, 'first');
    n_dup = height(T_num) - numel(ia);
    if n_dup > 0
        fprintf('[INFO] %d timestamp duplicati rimossi.\n', n_dup);
        T_num = T_num(ia, :);
    end

    T = table2timetable(T_num, 'RowTimes', 'datetime');

    fprintf('\n[INFO] Dataset totale: %d righe | da %s a %s\n', ...
        height(T), ...
        datestr(T.datetime(1),   'dd/mm/yyyy HH:MM:SS'), ...
        datestr(T.datetime(end), 'dd/mm/yyyy HH:MM:SS'));
end


% =========================================================================
%  COSTRUZIONE GUI
% =========================================================================

function costruisci_gui(T)
% Crea la finestra principale e tutti i controlli.
% Richiede MATLAB R2020b+ (uidatepicker).
%
% Convenzione coordinate:
%   - yt = posizione dall'alto (pixels dal bordo superiore del pannello)
%   - P(yt, h, SH) converte in coordinate MATLAB (y dal basso):
%       y_matlab = SH - yt - h

    % ── Dimensioni ───────────────────────────────────────────────────────
    HDR = 46;    % altezza header
    SH  = 634;   % altezza pannello sidebar (contenuto)
    SW  = 270;   % larghezza sidebar
    FH  = SH + HDR;
    FW  = 1440;
    PAD = 12;    % margine orizzontale

    % Helper: converte yt (px dal bordo top del pannello di altezza sh) in y MATLAB
    % Uso: pos(yt, h) → [x yt_matlab w h]  chiamata con x e w a parte
    yb = @(yt, h) SH - yt - h;

    % ── Palette colori ───────────────────────────────────────────────────
    BG     = [0.96 0.96 0.96];   % sfondo sidebar
    BG2    = [1.00 1.00 1.00];   % sfondo controlli
    SEP    = [0.80 0.80 0.80];   % separatori
    TITL   = [0.15 0.15 0.15];   % titoli sezione
    FG     = [0.20 0.20 0.20];   % testo normale
    FG2    = [0.55 0.55 0.55];   % testo secondario
    ACCENT = [0.17 0.45 0.70];   % blu accento

    % ── Definizioni variabili ─────────────────────────────────────────────
    VAR_LABELS = { ...
        'MOX 1 (cmos1)',   'cmos1'; ...
        'MOX 2 (cmos2)',   'cmos2'; ...
        'MOX 3 (cmos3)',   'cmos3'; ...
        'MOX 4 (cmos4)',   'cmos4'; ...
        'ECS NH3 (nh3)',   'nh3';   ...
        'ECS H2S (h2s)',   'h2s';   ...
        'Temperatura (T)', 'temperature'; ...
        'Umidita'' (RH)',  'humidity'; ...
    };

    YLABELS = containers.Map( ...
        {'cmos1','cmos2','cmos3','cmos4','nh3','h2s','temperature','humidity'}, ...
        {'MOX 1 (a.u.)','MOX 2 (a.u.)','MOX 3 (a.u.)','MOX 4 (a.u.)', ...
         'NH3 (ppm)','H2S (ppm)','T (°C)','RH (%)'});

    VAR_COLORS = { ...
        'cmos1',       [0.122, 0.467, 0.706]; ...
        'cmos2',       [0.850, 0.325, 0.098]; ...
        'cmos3',       [0.173, 0.627, 0.173]; ...
        'cmos4',       [0.839, 0.153, 0.157]; ...
        'nh3',         [0.494, 0.184, 0.557]; ...
        'h2s',         [0.467, 0.275, 0.208]; ...
        'temperature', [0.800, 0.200, 0.600]; ...
        'humidity',    [0.000, 0.620, 0.714]; ...
    };
    color_map = containers.Map(VAR_COLORS(:,1), VAR_COLORS(:,2));

    % ── Figura principale ─────────────────────────────────────────────────
    fig = uifigure( ...
        'Name',     'IREN — Monitoraggio 2025 Explorer', ...
        'Position', [60 60 FW FH], ...
        'Color',    [1 1 1]);

    % ── Header ───────────────────────────────────────────────────────────
    uipanel(fig, 'Position', [0 FH-HDR SW HDR], ...
        'BackgroundColor', ACCENT, 'BorderType', 'none');
    uilabel(fig, 'Text', 'IREN Explorer', ...
        'Position', [0 FH-HDR SW HDR], ...
        'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
        'HorizontalAlignment', 'center', 'BackgroundColor', ACCENT);

    % ── Sidebar panel ─────────────────────────────────────────────────────
    sidebar = uipanel(fig, 'Position', [0 0 SW SH], ...
        'BackgroundColor', BG, 'BorderType', 'none');
    % Linea destra
    uipanel(fig, 'Position', [SW 0 1 FH], ...
        'BackgroundColor', SEP, 'BorderType', 'none');

    % ── Layout top-down: yt = pixel dal bordo superiore del sidebar ───────
    % Ogni elemento: pos = [PAD, yb(yt,h), w, h]
    yt = 10;   % margine superiore
    IW = SW - 2*PAD;   % larghezza interna utile

    % ── VARIABILI ─────────────────────────────────────────────────────────
    h = 16;
    uilabel(sidebar, 'Text', 'VARIABILI', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'FontWeight', 'bold', 'FontSize', 9, 'FontColor', TITL, ...
        'BackgroundColor', BG);
    yt = yt + h + 5;

    % MOX
    h = 13;
    uilabel(sidebar, 'Text', 'MOX', ...
        'Position', [PAD+2 yb(yt,h) IW h], ...
        'FontSize', 8, 'FontAngle', 'italic', 'FontColor', FG2, ...
        'BackgroundColor', BG);
    yt = yt + h + 2;

    cb = gobjects(8,1);
    h = 20;
    for i = 1:4
        cb(i) = uicheckbox(sidebar, 'Text', VAR_LABELS{i,1}, 'Value', false, ...
            'Position', [PAD+2 yb(yt,h) IW-4 h], ...
            'FontSize', 9, 'FontColor', FG);
        yt = yt + h + 2;
    end

    % ECS
    yt = yt + 4;
    h = 13;
    uilabel(sidebar, 'Text', 'ECS', ...
        'Position', [PAD+2 yb(yt,h) IW h], ...
        'FontSize', 8, 'FontAngle', 'italic', 'FontColor', FG2, ...
        'BackgroundColor', BG);
    yt = yt + h + 2;

    h = 20;
    for i = 5:6
        cb(i) = uicheckbox(sidebar, 'Text', VAR_LABELS{i,1}, 'Value', false, ...
            'Position', [PAD+2 yb(yt,h) IW-4 h], ...
            'FontSize', 9, 'FontColor', FG);
        yt = yt + h + 2;
    end

    % Ambiente
    yt = yt + 4;
    h = 13;
    uilabel(sidebar, 'Text', 'Ambiente', ...
        'Position', [PAD+2 yb(yt,h) IW h], ...
        'FontSize', 8, 'FontAngle', 'italic', 'FontColor', FG2, ...
        'BackgroundColor', BG);
    yt = yt + h + 2;

    h = 20;
    for i = 7:8
        cb(i) = uicheckbox(sidebar, 'Text', VAR_LABELS{i,1}, 'Value', false, ...
            'Position', [PAD+2 yb(yt,h) IW-4 h], ...
            'FontSize', 9, 'FontColor', FG);
        yt = yt + h + 2;
    end

    % Bottoni Tutti / Nessuno
    yt = yt + 6;
    h = 22;
    bw = floor(IW/2) - 2;
    uibutton(sidebar, 'Text', 'Tutti', ...
        'Position', [PAD yb(yt,h) bw h], ...
        'BackgroundColor', BG2, 'FontColor', FG, 'FontSize', 9, ...
        'ButtonPushedFcn', @(~,~) seleziona_tutto(cb, true));
    uibutton(sidebar, 'Text', 'Nessuno', ...
        'Position', [PAD+bw+4 yb(yt,h) bw h], ...
        'BackgroundColor', BG2, 'FontColor', FG, 'FontSize', 9, ...
        'ButtonPushedFcn', @(~,~) seleziona_tutto(cb, false));
    yt = yt + h + 10;

    % ── Separatore ───────────────────────────────────────────────────────
    uipanel(sidebar, 'Position', [PAD yb(yt,1) IW 1], ...
        'BackgroundColor', SEP, 'BorderType', 'none');
    yt = yt + 1 + 8;

    % ── PERIODO ───────────────────────────────────────────────────────────
    h = 16;
    uilabel(sidebar, 'Text', 'PERIODO', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'FontWeight', 'bold', 'FontSize', 9, 'FontColor', TITL, ...
        'BackgroundColor', BG);
    yt = yt + h + 6;

    % Inizio
    h = 12;
    uilabel(sidebar, 'Text', 'Inizio', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'FontSize', 8, 'FontAngle', 'italic', 'FontColor', FG2, ...
        'BackgroundColor', BG);
    yt = yt + h + 2;

    h = 24;
    dw = 152;  tw = IW - dw - 4;
    dp_start = uidatepicker(sidebar, ...
        'Value', dateshift(T.datetime(1),'start','day'), ...
        'Position', [PAD yb(yt,h) dw h], ...
        'DisplayFormat', 'dd/MM/yyyy', ...
        'FontColor', FG, 'BackgroundColor', BG2);
    ef_start_time = uieditfield(sidebar, 'text', ...
        'Value', char(datestr(T.datetime(1),'HH:MM:SS')), ...
        'Position', [PAD+dw+4 yb(yt,h) tw h], ...
        'FontColor', FG, 'BackgroundColor', BG2, ...
        'HorizontalAlignment', 'center');
    yt = yt + h + 8;

    % Fine
    h = 12;
    uilabel(sidebar, 'Text', 'Fine', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'FontSize', 8, 'FontAngle', 'italic', 'FontColor', FG2, ...
        'BackgroundColor', BG);
    yt = yt + h + 2;

    h = 24;
    dp_end = uidatepicker(sidebar, ...
        'Value', dateshift(T.datetime(end),'start','day'), ...
        'Position', [PAD yb(yt,h) dw h], ...
        'DisplayFormat', 'dd/MM/yyyy', ...
        'FontColor', FG, 'BackgroundColor', BG2);
    ef_end_time = uieditfield(sidebar, 'text', ...
        'Value', char(datestr(T.datetime(end),'HH:MM:SS')), ...
        'Position', [PAD+dw+4 yb(yt,h) tw h], ...
        'FontColor', FG, 'BackgroundColor', BG2, ...
        'HorizontalAlignment', 'center');
    yt = yt + h + 6;

    % Shortcut: 4 bottoni su riga unica
    h = 22;
    sw4 = floor(IW/4) - 2;
    shortcuts = {'Tutto','1 mese','1 sett.','1 g'};
    tfn = { ...
        @() set_range(T.datetime(1), T.datetime(end)); ...
        @() set_range(max(T.datetime(1), T.datetime(end)-calmonths(1)), T.datetime(end)); ...
        @() set_range(max(T.datetime(1), T.datetime(end)-days(7)),      T.datetime(end)); ...
        @() set_range(max(T.datetime(1), T.datetime(end)-days(1)),      T.datetime(end)); ...
    };
    for k = 1:4
        fn = tfn{k};
        uibutton(sidebar, 'Text', shortcuts{k}, ...
            'Position', [PAD+(k-1)*(sw4+2) yb(yt,h) sw4 h], ...
            'BackgroundColor', BG2, 'FontColor', FG, 'FontSize', 8, ...
            'ButtonPushedFcn', @(~,~) fn());
    end
    yt = yt + h + 10;

    % ── Separatore ───────────────────────────────────────────────────────
    uipanel(sidebar, 'Position', [PAD yb(yt,1) IW 1], ...
        'BackgroundColor', SEP, 'BorderType', 'none');
    yt = yt + 1 + 8;

    % ── OPZIONI ───────────────────────────────────────────────────────────
    h = 16;
    uilabel(sidebar, 'Text', 'OPZIONI', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'FontWeight', 'bold', 'FontSize', 9, 'FontColor', TITL, ...
        'BackgroundColor', BG);
    yt = yt + h + 6;

    h = 22;
    lw = 80;
    uilabel(sidebar, 'Text', 'Resampling:', ...
        'Position', [PAD yb(yt,h) lw h], ...
        'FontSize', 9, 'FontColor', FG2, 'BackgroundColor', BG);
    dd_resample = uidropdown(sidebar, ...
        'Items',    {'nessuno','1 min','5 min','15 min','1 h'}, ...
        'Value',    'nessuno', ...
        'Position', [PAD+lw+2 yb(yt,h) IW-lw-2 h], ...
        'BackgroundColor', BG2, 'FontColor', FG, 'FontSize', 9);
    yt = yt + h + 10;

    % ── Separatore ───────────────────────────────────────────────────────
    uipanel(sidebar, 'Position', [PAD yb(yt,1) IW 1], ...
        'BackgroundColor', SEP, 'BorderType', 'none');
    yt = yt + 1 + 8;

    % ── PLOTTA ───────────────────────────────────────────────────────────
    h = 34;
    uibutton(sidebar, 'Text', 'PLOTTA', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'BackgroundColor', ACCENT, 'FontColor', [1 1 1], ...
        'FontWeight', 'bold', 'FontSize', 13, ...
        'ButtonPushedFcn', @(~,~) do_plot());
    yt = yt + h + 8;

    h = 20;
    lbl_status = uilabel(sidebar, 'Text', 'Pronto.', ...
        'Position', [PAD yb(yt,h) IW h], ...
        'FontColor', FG2, 'FontSize', 8, ...
        'BackgroundColor', BG, 'WordWrap', 'on');

    % ── Pannello grafici ──────────────────────────────────────────────────
    plot_panel = uipanel(fig, 'Position', [SW+1 0 FW-SW-1 FH], ...
        'BackgroundColor', [1 1 1], 'BorderType', 'none');

    lbl_placeholder = uilabel(plot_panel, ...
        'Text', sprintf('Seleziona variabili e periodo,\npoi premi PLOTTA'), ...
        'Position', [100 FH/2-30 FW-SW-200 60], ...
        'FontSize', 14, 'FontColor', [0.72 0.72 0.72], ...
        'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1]);

    axes_handles = [];

    % =====================================================================
    %  CALLBACKS
    % =====================================================================

    function set_range(t_start, t_end)
        dp_start.Value      = dateshift(t_start, 'start', 'day');
        ef_start_time.Value = char(datestr(t_start, 'HH:MM:SS'));
        dp_end.Value        = dateshift(t_end, 'start', 'day');
        ef_end_time.Value   = char(datestr(t_end, 'HH:MM:SS'));
    end

    function seleziona_tutto(cb_array, val)
        for ii = 1:numel(cb_array)
            cb_array(ii).Value = val;
        end
    end

    function do_plot()
        % ── Variabili selezionate ─────────────────────────────────────────
        sel_cols = {};
        for ii = 1:size(VAR_LABELS,1)
            if cb(ii).Value
                sel_cols{end+1} = VAR_LABELS{ii,2}; %#ok<AGROW>
            end
        end
        if isempty(sel_cols)
            uialert(fig, 'Seleziona almeno una variabile.', 'Attenzione');
            return
        end

        % ── Datetime da picker + ora ──────────────────────────────────────
        try
            t_start = combina_data_ora(dp_start.Value, ef_start_time.Value);
            t_end   = combina_data_ora(dp_end.Value,   ef_end_time.Value);
        catch ME
            uialert(fig, ME.message, 'Errore ora');
            return
        end
        if t_start >= t_end
            uialert(fig, 'Inizio deve essere precedente alla fine.', 'Errore');
            return
        end

        % ── Filtro ───────────────────────────────────────────────────────
        mask   = T.datetime >= t_start & T.datetime <= t_end;
        subset = T(mask, :);
        if height(subset) == 0
            uialert(fig, 'Nessun dato nel periodo selezionato.', 'Nessun dato');
            return
        end

        % ── Resampling ───────────────────────────────────────────────────
        rs_map = containers.Map( ...
            {'1 min','5 min','15 min','1 h'}, ...
            {minutes(1), minutes(5), minutes(15), hours(1)});
        rs_val = dd_resample.Value;
        if rs_map.isKey(rs_val)
            subset = retime(subset, 'regular', 'mean', 'TimeStep', rs_map(rs_val));
        end

        n_pts = height(subset);
        lbl_status.Text = sprintf('%d punti  |  %s  →  %s', n_pts, ...
            datestr(t_start,'dd/mm/yyyy HH:MM'), ...
            datestr(t_end,  'dd/mm/yyyy HH:MM'));

        % ── Disegna: un asse per variabile ────────────────────────────────
        n_ax = numel(sel_cols);

        if isvalid(lbl_placeholder), lbl_placeholder.Visible = 'off'; end
        for ii = 1:numel(axes_handles)
            if isvalid(axes_handles(ii)), delete(axes_handles(ii)); end
        end
        axes_handles = gobjects(n_ax, 1);

        pw = plot_panel.Position(3);
        ph = plot_panel.Position(4);
        ml = 72; mr = 20; mb = 52; mt = 40;
        gap = 6;
        ax_h = floor((ph - mb - mt - gap*(n_ax-1)) / n_ax);
        ax_w = pw - ml - mr;

        title_str = sprintf('Monitoraggio IREN 2025   |   %s  –  %s', ...
            datestr(t_start,'dd/mm/yyyy HH:MM'), ...
            datestr(t_end,  'dd/mm/yyyy HH:MM'));

        for g = 1:n_ax
            g_inv = n_ax - g + 1;
            ax_y  = mb + (g_inv-1)*(ax_h + gap);
            ax = uiaxes(plot_panel, ...
                'Position', [ml ax_y ax_w ax_h], ...
                'Color', [1 1 1], 'FontSize', 9);
            ax.XGrid = 'on';  ax.YGrid = 'on';
            ax.GridLineStyle = ':';  ax.GridAlpha = 0.5;
            ax.GridColor = [0.7 0.7 0.7];
            ax.Box = 'off';
            ax.XColor = [0.4 0.4 0.4];
            ax.YColor = [0.4 0.4 0.4];
            axes_handles(g) = ax;

            col = sel_cols{g};
            clr = color_map(col);
            plot(ax, subset.datetime, subset.(col), ...
                'Color', clr, 'LineWidth', 1.0);

            ylabel(ax, YLABELS(col), 'FontSize', 8, 'Color', [0.3 0.3 0.3]);

            if g == n_ax
                formatta_xaxis(ax, t_start, t_end);
            else
                ax.XTickLabel = {};
            end

            if g == 1
                title(ax, title_str, 'FontSize', 10, 'FontWeight', 'bold', ...
                    'Color', [0.15 0.15 0.15]);
            end
        end

        if n_ax > 1
            linkaxes(axes_handles, 'x');
        end
    end  % do_plot

end  % costruisci_gui


% =========================================================================
%  FUNZIONI DI SUPPORTO
% =========================================================================

function dt = combina_data_ora(dateval, time_str)
% Combina un datetime (da uidatepicker, solo data) con una stringa ora HH:MM:SS.
    time_str = strtrim(time_str);
    % Accetta HH:MM:SS o HH:MM
    parts = str2double(strsplit(time_str, ':'));
    if numel(parts) < 2 || any(isnan(parts))
        error('Formato ora non valido: "%s"\nUsare HH:MM o HH:MM:SS', time_str);
    end
    h = parts(1);
    m = parts(2);
    s = 0;
    if numel(parts) >= 3, s = parts(3); end
    dt = datetime(dateval.Year, dateval.Month, dateval.Day, h, m, s);
end


function formatta_xaxis(ax, t_start, t_end)
% Imposta formato e tick dell'asse X in base alla durata del range.
    delta_h = hours(t_end - t_start);

    if delta_h <= 6
        ax.XAxis.TickLabelFormat = 'HH:mm';
        ax.XAxis.TickValues = t_start : minutes(30) : t_end;
    elseif delta_h <= 24
        ax.XAxis.TickLabelFormat = 'HH:mm';
        ax.XAxis.TickValues = t_start : hours(2) : t_end;
    elseif delta_h <= 14*24
        ax.XAxis.TickLabelFormat = 'dd/MM HH:mm';
        ax.XAxis.TickValues = t_start : hours(12) : t_end;
    elseif delta_h <= 60*24
        ax.XAxis.TickLabelFormat = 'dd/MM';
        ax.XAxis.TickValues = t_start : days(3) : t_end;
    else
        ax.XAxis.TickLabelFormat = 'dd/MM/yy';
        ax.XAxis.TickValues = t_start : calmonths(1) : t_end;
    end
    ax.XTickLabelRotation = 30;
end


% =========================================================================
%  HELPER WIDGET (creazione controlli sidebar)
% =========================================================================

