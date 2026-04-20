function ELLONA_09_gui_viewer()
% ELLONA_09_GUI_VIEWER
%   Viewer interattivo PC1 + PC2 + LOD per dati di monitoraggio ELLONA.
%
%   Workflow:
%     1. Carica pca_model_ELLONA.mat   (output di ELLONA_08)
%     2. Carica baseline_stats_ELLONA.csv (output di ELLONA_08)
%     3. Seleziona uno o più file CSV mensili da monitoraggio2025/
%     4. Naviga e visualizza PC1(t) + PC2(t) con bande LOD
%
%   Adattato da BATCH_GUI_PC1_PC2_LOD_VIEWER_SIMPLE per ELLONA:
%     - Colonne: cmos1,cmos2,cmos3,cmos4,temperature,humidity
%     - Datetime: colonne separate "date" + "time"  →  dd/MM/yyyy HH:mm:ss
%     - LOD k configurabile da slider nella GUI
%
%   Richiede: MATLAB R2020b+ (uifigure, uigridlayout)
%
% Marco Calì — PoliMi, Aprile 2026

clearvars; clc;

%% ===== STATO APPLICAZIONE =====
app = struct();
app.modelPath    = "";
app.baselinePath = "";
app.batchPaths   = strings(0,1);
app.batchNames   = strings(0,1);
app.idx          = 0;

% Modello PCA
app.mu         = [];
app.sigma      = [];
app.muPCA      = [];
app.coeff      = [];
app.predictors = strings(1,0);
app.modelLoaded   = false;
app.baseLoaded    = false;

% LOD (da CSV, ma modificabile con slider)
app.k_lod          = 6.0;
app.mu_pc1         = NaN;
app.sigma_pc1      = NaN;
app.lod_lower_pc1  = NaN;
app.lod_upper_pc1  = NaN;
app.mu_pc2         = NaN;
app.sigma_pc2      = NaN;
app.lod_lower_pc2  = NaN;
app.lod_upper_pc2  = NaN;

% Dati correnti
app.t_real = datetime.empty;
app.PC1    = [];
app.PC2    = [];

%% ===== COSTRUZIONE UI =====
fig = uifigure('Name','ELLONA — PC1 + PC2 + LOD Viewer', ...
    'Position',[100 80 1350 750]);

gl = uigridlayout(fig, [8 6]);
gl.RowHeight   = {26,26,26,26,'1x',28,24,22};
gl.ColumnWidth = {130,400,100,160,160,'1x'};
gl.Padding     = [10 8 10 8];
gl.RowSpacing  = 6;
gl.ColumnSpacing = 8;

% ---- Row 1: Modello ----
uilabel(gl,'Text','PCA model (.mat):', ...
    'HorizontalAlignment','right').Layout.Row=1; ...
    uilabel(gl).Layout.Column=1; % placeholder, fix below
lbl1 = uilabel(gl,'Text','PCA model (.mat):', ...
    'HorizontalAlignment','right');
lbl1.Layout.Row=1; lbl1.Layout.Column=1;

app.txtModel = uieditfield(gl,'text','Editable','off', ...
    'Placeholder','(non caricato)');
app.txtModel.Layout.Row=1; app.txtModel.Layout.Column=2;
delete(lbl1);   % workaround doppio label

% ---- Ricostruisci layout pulito ----
delete(fig); clearvars;

%% ===== RICOSTRUZIONE UI PULITA =====
app = struct();
app.modelPath=''; app.baselinePath='';
app.batchPaths=strings(0,1); app.batchNames=strings(0,1); app.idx=0;
app.mu=[]; app.sigma=[]; app.muPCA=[]; app.coeff=[]; app.predictors=strings(1,0);
app.modelLoaded=false; app.baseLoaded=false;
app.k_lod=6.0;
app.mu_pc1=NaN; app.sigma_pc1=NaN;
app.lod_lower_pc1=NaN; app.lod_upper_pc1=NaN;
app.mu_pc2=NaN; app.sigma_pc2=NaN;
app.lod_lower_pc2=NaN; app.lod_upper_pc2=NaN;
app.t_real=datetime.empty; app.PC1=[]; app.PC2=[];

fig = uifigure('Name','ELLONA — PC1 + PC2 + LOD Viewer', ...
    'Position',[100 80 1350 750]);

gl = uigridlayout(fig, [8 6]);
gl.RowHeight   = {26,26,26,26,'1x',30,22,22};
gl.ColumnWidth = {130,400,100,170,170,'1x'};
gl.Padding     = [10 8 10 8];
gl.RowSpacing  = 5;
gl.ColumnSpacing = 8;

% --- Row 1: PCA model ---
r=1;
l=uilabel(gl,'Text','PCA model (.mat):','HorizontalAlignment','right');
l.Layout.Row=r; l.Layout.Column=1;
app.txtModel=uieditfield(gl,'text','Editable','off','Placeholder','non caricato');
app.txtModel.Layout.Row=r; app.txtModel.Layout.Column=2;
b=uibutton(gl,'Text','Browse','ButtonPushedFcn',@onBrowseModel);
b.Layout.Row=r; b.Layout.Column=3;

% --- Row 2: Baseline stats ---
r=2;
l=uilabel(gl,'Text','Baseline stats CSV:','HorizontalAlignment','right');
l.Layout.Row=r; l.Layout.Column=1;
app.txtBase=uieditfield(gl,'text','Editable','off','Placeholder','non caricato');
app.txtBase.Layout.Row=r; app.txtBase.Layout.Column=2;
b=uibutton(gl,'Text','Browse','ButtonPushedFcn',@onBrowseBaseline);
b.Layout.Row=r; b.Layout.Column=3;

% --- Row 3: Batch CSV ---
r=3;
l=uilabel(gl,'Text','CSV mensili:','HorizontalAlignment','right');
l.Layout.Row=r; l.Layout.Column=1;
app.txtBatch=uieditfield(gl,'text','Editable','off','Placeholder','seleziona file CSV');
app.txtBatch.Layout.Row=r; app.txtBatch.Layout.Column=2;
b=uibutton(gl,'Text','Browse batch','ButtonPushedFcn',@onBrowseBatch);
b.Layout.Row=r; b.Layout.Column=3;

% --- Row 4: LOD k slider ---
r=4;
l=uilabel(gl,'Text','LOD  k:','HorizontalAlignment','right');
l.Layout.Row=r; l.Layout.Column=1;
app.sliderK = uislider(gl,'Value',6,'Limits',[1 12], ...
    'MajorTicks',1:12,'ValueChangedFcn',@onKChanged);
app.sliderK.Layout.Row=r; app.sliderK.Layout.Column=2;
app.lblK = uilabel(gl,'Text','k = 6.0');
app.lblK.Layout.Row=r; app.lblK.Layout.Column=3;

% --- Row 5: listbox + pannello plot ---
r=5;
app.lb = uilistbox(gl,'Items',{},'ValueChangedFcn',@onSelectFile);
app.lb.Layout.Row=r; app.lb.Layout.Column=[1 3];

rightPanel = uipanel(gl,'BorderType','none');
rightPanel.Layout.Row=r; rightPanel.Layout.Column=[4 6];

rp = uigridlayout(rightPanel,[2 1]);
rp.RowHeight={'1x','1x'}; rp.ColumnWidth={'1x'};
rp.Padding=[0 0 0 0]; rp.RowSpacing=8;

app.ax1=uiaxes(rp); app.ax1.Layout.Row=1; app.ax1.Layout.Column=1;
grid(app.ax1,'on'); ylabel(app.ax1,'PC_1'); title(app.ax1,'PC_1(t)');

app.ax2=uiaxes(rp); app.ax2.Layout.Row=2; app.ax2.Layout.Column=1;
grid(app.ax2,'on'); ylabel(app.ax2,'PC_2'); title(app.ax2,'PC_2(t)');

% --- Row 6: navigazione ---
r=6;
app.btnPrev=uibutton(gl,'Text','◀ Prev','ButtonPushedFcn',@onPrev,'Enable','off');
app.btnPrev.Layout.Row=r; app.btnPrev.Layout.Column=1;
app.btnNext=uibutton(gl,'Text','Next ▶','ButtonPushedFcn',@onNext,'Enable','off');
app.btnNext.Layout.Row=r; app.btnNext.Layout.Column=2;
app.btnExport=uibutton(gl,'Text','Export PNG','ButtonPushedFcn',@onExport,'Enable','off');
app.btnExport.Layout.Row=r; app.btnExport.Layout.Column=3;

% --- Row 7: info range ---
r=7;
app.lblRange=uilabel(gl,'Text','Range: (caricare file)');
app.lblRange.Layout.Row=r; app.lblRange.Layout.Column=[1 6];

% --- Row 8: status ---
r=8;
app.lblStatus=uilabel(gl,'Text','Status: caricare modello + baseline, poi selezionare CSV.');
app.lblStatus.Layout.Row=r; app.lblStatus.Layout.Column=[1 6];

%% ===== CALLBACKS =====

    % ---- Carica modello PCA ----
    function onBrowseModel(~,~)
        scriptPath = fileparts(mfilename('fullpath'));
        defPath    = fullfile(scriptPath,'..','..','output','event_detection');
        if ~isfolder(defPath), defPath=pwd; end
        [f,p] = uigetfile(fullfile(defPath,'*.mat'),'Seleziona pca_model_ELLONA.mat');
        if isequal(f,0), return; end
        app.modelPath = fullfile(p,f);
        app.txtModel.Value = app.modelPath;
        try
            S = load(app.modelPath);
            required = {'mu','sigma','coeff','predictors'};
            miss = setdiff(required, fieldnames(S));
            if ~isempty(miss)
                error('Variabili mancanti nel .mat: %s', strjoin(miss,', '));
            end
            app.mu         = S.mu;
            app.sigma      = S.sigma;
            app.coeff      = S.coeff;
            app.predictors = string(S.predictors(:))';
            app.muPCA = zeros(1, numel(app.predictors));
            if isfield(S,'muPCA'), app.muPCA = S.muPCA; end
            % Pre-carica LOD dal modello se disponibili
            if isfield(S,'mu_pc1')
                app.mu_pc1 = S.mu_pc1; app.sigma_pc1 = S.sigma_pc1;
                app.mu_pc2 = S.mu_pc2; app.sigma_pc2 = S.sigma_pc2;
                app.k_lod  = S.k_lod;
                app.sliderK.Value = app.k_lod;
                app.lblK.Text = sprintf('k = %.1f', app.k_lod);
                recomputeLOD();
            end
            app.modelLoaded = true;
            updateStatus();
        catch ME
            app.modelLoaded = false;
            uialert(fig, ME.message, 'Errore modello');
            updateStatus();
        end
    end

    % ---- Carica baseline stats ----
    function onBrowseBaseline(~,~)
        scriptPath = fileparts(mfilename('fullpath'));
        defPath    = fullfile(scriptPath,'..','..','output','event_detection');
        if ~isfolder(defPath), defPath=pwd; end
        [f,p] = uigetfile(fullfile(defPath,'*.csv'),'Seleziona baseline_stats_ELLONA.csv');
        if isequal(f,0), return; end
        app.baselinePath = fullfile(p,f);
        app.txtBase.Value = app.baselinePath;
        try
            B = readtable(app.baselinePath);
            vn = lower(string(B.Properties.VariableNames));

            % Cerca colonne con prefisso PC1_mean / PC1_std / PC2_mean / PC2_std
            iP1m = find(startsWith(vn,'pc1_mean'),1);
            iP1s = find(startsWith(vn,'pc1_std'), 1);
            iP2m = find(startsWith(vn,'pc2_mean'),1);
            iP2s = find(startsWith(vn,'pc2_std'), 1);

            if any(cellfun(@isempty,{iP1m,iP1s,iP2m,iP2s}))
                error('CSV deve avere colonne: PC1_mean*, PC1_std*, PC2_mean*, PC2_std*');
            end
            app.mu_pc1    = double(B{1,iP1m});
            app.sigma_pc1 = double(B{1,iP1s});
            app.mu_pc2    = double(B{1,iP2m});
            app.sigma_pc2 = double(B{1,iP2s});

            if any(~isfinite([app.mu_pc1 app.sigma_pc1 app.mu_pc2 app.sigma_pc2]))
                error('Valori non finiti nel CSV baseline stats.');
            end
            recomputeLOD();
            app.baseLoaded = true;
            updateStatus();
        catch ME
            app.baseLoaded = false;
            uialert(fig, ME.message, 'Errore baseline');
            updateStatus();
        end
    end

    % ---- Carica batch CSV mensili ----
    function onBrowseBatch(~,~)
        if ~(app.modelLoaded && app.baseLoaded)
            uialert(fig,'Caricare prima modello + baseline.','Manca modello/baseline');
            return;
        end
        scriptPath = fileparts(mfilename('fullpath'));
        defPath    = fullfile(scriptPath,'..','..','data','raw','monitoraggio2025');
        if ~isfolder(defPath), defPath=pwd; end
        [f,p] = uigetfile(fullfile(defPath,'*.csv'), ...
            'Seleziona CSV mensili (multi-selezione ok)','MultiSelect','on');
        if isequal(f,0), return; end
        if ischar(f), f={f}; end

        % Ordina alfabeticamente (→ ordine cronologico per nomi mensili)
        fSorted = sort(string(f(:)));
        app.batchNames = fSorted;
        app.batchPaths = string(fullfile(p, fSorted));

        app.txtBatch.Value = sprintf('%d file selezionati (%s)', numel(fSorted), p);
        app.lb.Items = cellstr(app.batchNames);

        app.idx=1; app.lb.Value=app.lb.Items{1};
        app.btnPrev.Enable='on'; app.btnNext.Enable='on'; app.btnExport.Enable='on';
        loadAndPlot();
    end

    % ---- Navigazione ----
    function onSelectFile(~,~)
        if isempty(app.lb.Items), return; end
        sel = string(app.lb.Value);
        k   = find(app.batchNames==sel,1,'first');
        if ~isempty(k), app.idx=k; loadAndPlot(); end
    end
    function onPrev(~,~)
        if isempty(app.batchPaths), return; end
        app.idx = max(1, app.idx-1);
        app.lb.Value = app.lb.Items{app.idx};
        loadAndPlot();
    end
    function onNext(~,~)
        if isempty(app.batchPaths), return; end
        app.idx = min(numel(app.batchPaths), app.idx+1);
        app.lb.Value = app.lb.Items{app.idx};
        loadAndPlot();
    end

    % ---- Slider k LOD ----
    function onKChanged(src,~)
        app.k_lod = src.Value;
        app.lblK.Text = sprintf('k = %.1f', app.k_lod);
        recomputeLOD();
        if ~isempty(app.PC1), redrawPlots(); end
    end

    % ---- Export PNG ----
    function onExport(~,~)
        if isempty(app.PC1), return; end
        [f,p] = uiputfile('*.png','Salva figura come...');
        if isequal(f,0), return; end
        exportgraphics(fig, fullfile(p,f), 'Resolution',300);
        app.lblStatus.Text = sprintf('Salvato: %s', fullfile(p,f));
    end

%% ===== HELPER FUNCTIONS =====

    function recomputeLOD()
        if ~isfinite(app.sigma_pc1) || ~isfinite(app.sigma_pc2), return; end
        app.lod_lower_pc1 = app.mu_pc1 - app.k_lod * app.sigma_pc1;
        app.lod_upper_pc1 = app.mu_pc1 + app.k_lod * app.sigma_pc1;
        app.lod_lower_pc2 = app.mu_pc2 - app.k_lod * app.sigma_pc2;
        app.lod_upper_pc2 = app.mu_pc2 + app.k_lod * app.sigma_pc2;
    end

    function loadAndPlot()
        try
            fpath = app.batchPaths(app.idx);
            fname = app.batchNames(app.idx);
            app.lblStatus.Text = sprintf('Status: caricamento %s ...', fname);
            drawnow;

            % Leggi CSV con delimitatore ;
            T = readtable(fpath, 'Delimiter',';', 'VariableNamingRule','preserve');

            % Costruisci datetime da "date" + "time"
            if ismember('date',T.Properties.VariableNames) && ...
               ismember('time',T.Properties.VariableNames)
                t = datetime(string(T.date) + " " + string(T.time), ...
                    'InputFormat','dd/MM/yyyy HH:mm:ss');
            elseif ismember('timestamp',T.Properties.VariableNames)
                t = parseTsRobust(T.timestamp);
            else
                error('Nessuna colonna datetime trovata (serve "date"+"time" o "timestamp").');
            end

            % Estrai predictors
            missCols = setdiff(cellstr(app.predictors), T.Properties.VariableNames);
            if ~isempty(missCols)
                error('Colonne mancanti: %s', strjoin(missCols,', '));
            end
            X = T{:, cellstr(app.predictors)};

            % Filtra righe valide
            valid = ~isnat(t) & all(isfinite(X),2);
            t = t(valid); X = X(valid,:);

            % Sort temporale + dedup
            [t, ord] = sort(t,'ascend');
            X = X(ord,:);
            [t, ia] = unique(t,'stable');
            X = X(ia,:);

            app.t_real = t;

            % Proiezione PCA
            sg = app.sigma; sg(sg==0|isnan(sg))=1;
            Xz = (X - app.mu) ./ sg;
            sc = (Xz - app.muPCA) * app.coeff;
            if size(sc,2) < 2
                error('PCA produce < 2 componenti. Controllare il modello.');
            end
            app.PC1 = sc(:,1);
            app.PC2 = sc(:,2);

            redrawPlots();

            rng_str = sprintf('%s  →  %s   (N=%d)', ...
                datestr(min(t),'dd-mmm-yyyy HH:MM'), ...
                datestr(max(t),'dd-mmm-yyyy HH:MM'), numel(t));
            app.lblRange.Text = rng_str;
            app.lblStatus.Text = sprintf('Status: %s  |  k=%.1f', fname, app.k_lod);

        catch ME
            uialert(fig, ME.message, 'Errore caricamento');
            app.lblStatus.Text = 'Status: errore nel caricamento.';
        end
    end

    function redrawPlots()
        if isempty(app.PC1) || isempty(app.t_real), return; end
        fname = app.batchNames(app.idx);

        isEv1 = app.PC1 < app.lod_lower_pc1;  % risposta MOX negativa → scende
        evPct = 100*mean(isEv1);

        % --- PC1 ---
        cla(app.ax1); hold(app.ax1,'on'); grid(app.ax1,'on');
        plot(app.ax1, app.t_real, app.PC1, '-', 'Color',[0.60 0.72 0.90],'LineWidth',0.5);
        ev_idx1 = find(isEv1);
        if ~isempty(ev_idx1)
            plot(app.ax1, app.t_real(ev_idx1), app.PC1(ev_idx1), '.', ...
                'Color',[0.82 0.18 0.10],'MarkerSize',4);
        end
        yline(app.ax1, app.lod_upper_pc1, '-', sprintf('LOD+ %.3f',app.lod_upper_pc1), ...
            'Color',[0.10 0.65 0.10],'LineWidth',2.2,'LabelHorizontalAlignment','left');
        yline(app.ax1, app.lod_lower_pc1, '-', sprintf('LOD- %.3f',app.lod_lower_pc1), ...
            'Color',[0.10 0.65 0.10],'LineWidth',2.2,'LabelHorizontalAlignment','left');
        yline(app.ax1, app.mu_pc1, '--', sprintf('μ %.3f',app.mu_pc1), ...
            'Color',[0.50 0.50 0.50],'LineWidth',1.0);
        title(app.ax1, sprintf('%s  |  PC_1  (eventi: %.1f%%)', fname, evPct), ...
            'Interpreter','none','FontSize',10);
        ylabel(app.ax1,'PC_1'); xlabel(app.ax1,'Datetime');
        hold(app.ax1,'off');

        % --- PC2 ---
        isEv2 = app.PC2 < app.lod_lower_pc2 | app.PC2 > app.lod_upper_pc2;
        cla(app.ax2); hold(app.ax2,'on'); grid(app.ax2,'on');
        plot(app.ax2, app.t_real, app.PC2, '-', 'Color',[0.75 0.68 0.90],'LineWidth',0.5);
        ev_idx2 = find(isEv2);
        if ~isempty(ev_idx2)
            plot(app.ax2, app.t_real(ev_idx2), app.PC2(ev_idx2), '.', ...
                'Color',[0.60 0.10 0.65],'MarkerSize',4);
        end
        yline(app.ax2, app.lod_upper_pc2, '-', sprintf('LOD+ %.3f',app.lod_upper_pc2), ...
            'Color',[0.50 0.10 0.55],'LineWidth',2.0,'LabelHorizontalAlignment','left');
        yline(app.ax2, app.lod_lower_pc2, '-', sprintf('LOD- %.3f',app.lod_lower_pc2), ...
            'Color',[0.50 0.10 0.55],'LineWidth',2.0,'LabelHorizontalAlignment','left');
        yline(app.ax2, app.mu_pc2, '--', sprintf('μ %.3f',app.mu_pc2), ...
            'Color',[0.50 0.50 0.50],'LineWidth',1.0);
        title(app.ax2,'PC_2(t)','FontSize',10);
        ylabel(app.ax2,'PC_2'); xlabel(app.ax2,'Datetime');
        hold(app.ax2,'off');
    end

    function updateStatus()
        if app.modelLoaded && app.baseLoaded
            app.lblStatus.Text = 'Status: modello + baseline OK. Selezionare CSV mensili.';
        elseif app.modelLoaded
            app.lblStatus.Text = 'Status: modello OK. Caricare baseline_stats_ELLONA.csv.';
        elseif app.baseLoaded
            app.lblStatus.Text = 'Status: baseline OK. Caricare pca_model_ELLONA.mat.';
        else
            app.lblStatus.Text = 'Status: caricare modello + baseline, poi CSV.';
        end
    end

end % fine funzione principale

%% ===== HELPER LOCALE: parsing timestamp robusto =====
function t = parseTsRobust(ts)
if isdatetime(ts), t=ts; return; end
if isnumeric(ts)
    t = datetime(double(ts),'ConvertFrom','posixtime'); return;
end
s = strtrim(string(ts));
t = NaT(size(s));
fmts = ["dd/MM/yyyy HH:mm:ss","dd-MMM-yyyy HH:mm:ss","yyyy-MM-dd HH:mm:ss","yyyy/MM/dd HH:mm:ss"];
for k=1:numel(fmts)
    try
        tk = datetime(s,'InputFormat',fmts(k),'Locale','en_US');
        ok = ~isnat(tk); t(ok)=tk(ok);
    catch, end
    if all(~isnat(t)), return; end
end
end
