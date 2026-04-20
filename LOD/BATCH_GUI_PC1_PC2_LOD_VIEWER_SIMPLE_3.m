function BATCH_GUI_PC1_PC2_LOD_VIEWER_SIMPLE_3()
% BATCH_GUI_PC1_PC2_LOD_VIEWER_SIMPLE
% Viewer PC1 + PC2 + LOD (super semplice, compatibile UI "vecchie")
%
% Layout:
% - Sinistra: listbox file
% - Destra: 2 plot impilati (PC1 sopra, PC2 sotto)
%
% Requisiti:
%   Model .mat: mu, sigma, coeff, predictors, (opzionale ma consigliato: muPCA)
%   Baseline stats CSV: colonne che INIZIANO con:
%       PC1_mean_of*, PC1_std_of*, PC2_mean_of*, PC2_std_of*
%   Monitoring CSV: timestamp + predictors (nomi esatti)

clearvars; clc;

app = struct();
app.modelPath = "";
app.baselinePath = "";
app.batchPaths = strings(0,1);
app.batchNames = strings(0,1);
app.idx = 0;

app.timeZone = "UTC"; % cambia in "Europe/Rome" se vuoi

app.mu = [];
app.sigma = [];
app.coeff = [];
app.muPCA = [];               % <-- IMPORTANTISSIMO per proiezione corretta
app.predictors = strings(1,0);

% Baseline/LOD PC1
app.baseline_mean_PC1 = NaN;
app.LOD_lower_PC1 = NaN;
app.LOD_upper_PC1 = NaN;

% Baseline/LOD PC2
app.baseline_mean_PC2 = NaN;
app.LOD_lower_PC2 = NaN;
app.LOD_upper_PC2 = NaN;

app.kSigma = 3; % LOD = mean ± kSigma*std

% data corrente
app.t_real = datetime.empty;
app.PC1 = [];
app.PC2 = [];

app.modelLoaded = false;
app.baseLoaded  = false;

%% ===== UI =====
fig = uifigure('Name','PC1+PC2 + LOD Viewer (2 plots)','Position',[120 120 1250 720]);

gl = uigridlayout(fig,[7 6]);
gl.RowHeight   = {28,28,28,'1x',28,24,24};
gl.ColumnWidth = {120,420,110,160,160,'1x'};
gl.Padding     = [10 10 10 10];
gl.RowSpacing  = 8;
gl.ColumnSpacing = 10;

% --- Row 1: model
lblModel = uilabel(gl,'Text','PCA model (.mat):','HorizontalAlignment','right');
lblModel.Layout.Row = 1; lblModel.Layout.Column = 1;

app.txtModel = uieditfield(gl,'text','Editable','off');
app.txtModel.Layout.Row = 1; app.txtModel.Layout.Column = 2;

btnModel = uibutton(gl,'Text','Browse','ButtonPushedFcn',@onBrowseModel);
btnModel.Layout.Row = 1; btnModel.Layout.Column = 3;

% --- Row 2: baseline
lblBase = uilabel(gl,'Text','Baseline stats CSV:','HorizontalAlignment','right');
lblBase.Layout.Row = 2; lblBase.Layout.Column = 1;

app.txtBase = uieditfield(gl,'text','Editable','off');
app.txtBase.Layout.Row = 2; app.txtBase.Layout.Column = 2;

btnBase = uibutton(gl,'Text','Browse','ButtonPushedFcn',@onBrowseBaseline);
btnBase.Layout.Row = 2; btnBase.Layout.Column = 3;

% --- Row 3: batch
lblBatch = uilabel(gl,'Text','Batch CSV:','HorizontalAlignment','right');
lblBatch.Layout.Row = 3; lblBatch.Layout.Column = 1;

app.txtBatch = uieditfield(gl,'text','Editable','off','Placeholder','Select multiple *.csv');
app.txtBatch.Layout.Row = 3; app.txtBatch.Layout.Column = 2;

btnBatch = uibutton(gl,'Text','Browse batch','ButtonPushedFcn',@onBrowseBatch);
btnBatch.Layout.Row = 3; btnBatch.Layout.Column = 3;

% --- Row 4: listbox + right panel (2 plots)
app.lb = uilistbox(gl,'Items',{},'ValueChangedFcn',@onSelectFile);
app.lb.Layout.Row = 4; app.lb.Layout.Column = [1 3];

rightPanel = uipanel(gl,'BorderType','none');
rightPanel.Layout.Row = 4;
rightPanel.Layout.Column = [4 6];

rp = uigridlayout(rightPanel,[2 1]);
rp.RowHeight = {'1x','1x'};
rp.ColumnWidth = {'1x'};
rp.Padding = [0 0 0 0];
rp.RowSpacing = 10;

app.ax1 = uiaxes(rp);
app.ax1.Layout.Row = 1; app.ax1.Layout.Column = 1;
grid(app.ax1,'on');
ylabel(app.ax1,'PC1');
xlabel(app.ax1,'Datetime (REAL)');
title(app.ax1,'PC1');

app.ax2 = uiaxes(rp);
app.ax2.Layout.Row = 2; app.ax2.Layout.Column = 1;
grid(app.ax2,'on');
ylabel(app.ax2,'PC2');
xlabel(app.ax2,'Datetime (REAL)');
title(app.ax2,'PC2');

% --- Row 5: nav
app.btnPrev = uibutton(gl,'Text','◀ Prev','ButtonPushedFcn',@onPrev,'Enable','off');
app.btnPrev.Layout.Row = 5; app.btnPrev.Layout.Column = 1;

app.btnNext = uibutton(gl,'Text','Next ▶','ButtonPushedFcn',@onNext,'Enable','off');
app.btnNext.Layout.Row = 5; app.btnNext.Layout.Column = 2;

% --- Row 6: range info
app.lblRange = uilabel(gl,'Text','Data range: (load a file)');
app.lblRange.Layout.Row = 6; app.lblRange.Layout.Column = [1 6];

% --- Row 7: status
app.lblStatus = uilabel(gl,'Text','Status: load model + baseline, then batch.');
app.lblStatus.Layout.Row = 7; app.lblStatus.Layout.Column = [1 6];

%% ===== CALLBACKS =====
    function onBrowseModel(~,~)
        [f,p] = uigetfile('*.mat','Select pca_model.mat');
        if isequal(f,0); return; end
        app.modelPath = fullfile(p,f);
        app.txtModel.Value = app.modelPath;

        try
            S = load(app.modelPath);

            need = ["mu","sigma","coeff","predictors"];
            miss = setdiff(need, string(fieldnames(S)));
            if ~isempty(miss)
                error("Model missing variables: %s", strjoin(miss, ", "));
            end

            app.mu = S.mu;
            app.sigma = S.sigma;
            app.coeff = S.coeff;
            app.predictors = string(S.predictors(:))';

            % muPCA è importantissimo; se manca, assumo zeri ma avviso (meno corretto)
            if isfield(S,"muPCA")
                app.muPCA = S.muPCA;
            else
                app.muPCA = zeros(1, size(app.coeff,1));
                warning("muPCA not found in model. Projections may be shifted. Consider saving muPCA in pca_model.mat.");
            end

            app.modelLoaded = true;
            updateStatus();
        catch ME
            app.modelLoaded = false;
            uialert(fig, ME.message, 'Error loading model');
            updateStatus();
        end
    end

    function onBrowseBaseline(~,~)
        [f,p] = uigetfile('*.csv','Select baseline_PC1_PC2_stats.csv');
        if isequal(f,0); return; end
        app.baselinePath = fullfile(p,f);
        app.txtBase.Value = app.baselinePath;

        try
            B  = readtable(app.baselinePath);
            vn = string(B.Properties.VariableNames);
            vnl = lower(strtrim(vn));

            % helper: trova 1a colonna che inizia con prefisso (case-insensitive)
            findCol = @(prefix) find(startsWith(vnl, lower(prefix)), 1, 'first');

            i_pc1_mean = findCol("PC1_mean_of");
            i_pc1_std  = findCol("PC1_std_of");
            i_pc2_mean = findCol("PC2_mean_of");
            i_pc2_std  = findCol("PC2_std_of");

            if any(isempty([i_pc1_mean, i_pc1_std, i_pc2_mean, i_pc2_std]))
                error("Baseline stats CSV must contain columns starting with: PC1_mean_of*, PC1_std_of*, PC2_mean_of*, PC2_std_of*");
            end

            pc1_mean = double(B{1, i_pc1_mean});
            pc1_std  = double(B{1, i_pc1_std});
            pc2_mean = double(B{1, i_pc2_mean});
            pc2_std  = double(B{1, i_pc2_std});

            if any(~isfinite([pc1_mean, pc1_std, pc2_mean, pc2_std])) || any([pc1_std, pc2_std] <= 0)
                error("Baseline stats contain invalid values (NaN/Inf or non-positive std).");
            end

            % Salva in app + calcola LOD (mean ± k*std)
            app.baseline_mean_PC1 = pc1_mean;
            app.baseline_mean_PC2 = pc2_mean;

            app.LOD_lower_PC1 = pc1_mean - app.kSigma*pc1_std;
            app.LOD_upper_PC1 = pc1_mean + app.kSigma*pc1_std;

            app.LOD_lower_PC2 = pc2_mean - app.kSigma*pc2_std;
            app.LOD_upper_PC2 = pc2_mean + app.kSigma*pc2_std;

            app.baseLoaded = true;
            updateStatus();
        catch ME
            app.baseLoaded = false;
            uialert(fig, ME.message, 'Error loading baseline');
            updateStatus();
        end
    end

    function onBrowseBatch(~,~)
        if ~(app.modelLoaded && app.baseLoaded)
            uialert(fig,'Load PCA model and baseline first.','Missing model/baseline');
            return;
        end

        [f,p] = uigetfile('*.csv','Select monitoring CSV files','MultiSelect','on');
        if isequal(f,0); return; end
        if ischar(f); f = {f}; end

        app.batchNames = string(f(:));
        app.batchPaths = string(fullfile(p, f(:)));

        app.txtBatch.Value = sprintf("%d files selected (folder: %s)", numel(app.batchPaths), p);
        app.lb.Items = cellstr(app.batchNames);

        app.idx = 1;
        app.lb.Value = app.lb.Items{1};

        app.btnPrev.Enable = 'on';
        app.btnNext.Enable = 'on';

        loadAndPlotCurrent();
    end

    function onSelectFile(~,~)
        if isempty(app.lb.Items); return; end
        sel = string(app.lb.Value);
        k = find(app.batchNames == sel, 1, 'first');
        if ~isempty(k)
            app.idx = k;
            loadAndPlotCurrent();
        end
    end

    function onPrev(~,~)
        if isempty(app.batchPaths); return; end
        app.idx = max(1, app.idx - 1);
        app.lb.Value = app.lb.Items{app.idx};
        loadAndPlotCurrent();
    end

    function onNext(~,~)
        if isempty(app.batchPaths); return; end
        app.idx = min(numel(app.batchPaths), app.idx + 1);
        app.lb.Value = app.lb.Items{app.idx};
        loadAndPlotCurrent();
    end

    function loadAndPlotCurrent()
        try
            fpath = app.batchPaths(app.idx);
            fname = app.batchNames(app.idx);

            app.lblStatus.Text = "Status: loading " + fname + " ...";
            drawnow;

            T = readtable(fpath, "VariableNamingRule","preserve");
            vn = string(T.Properties.VariableNames);

            % timestamp robust: match case-insensitive e rinomina a 'timestamp'
            vnLow = lower(strtrim(vn));
            idxTS = find(vnLow == "timestamp", 1);
            if isempty(idxTS)
                error("Monitoring CSV missing column: timestamp");
            end
            if vn(idxTS) ~= "timestamp"
                T.Properties.VariableNames{idxTS} = "timestamp";
                vn = string(T.Properties.VariableNames);
            end

            % predictors: richiedi esatti (case sensitive) MA proviamo mapping case-insensitive
            T = ensurePredictorsColumns(T, app.predictors);

            t = parseTimestamp(T.timestamp, app.timeZone);
            X = T{:, app.predictors};

            valid = ~isnat(t) & all(isfinite(X),2);
            t = t(valid);
            X = X(valid,:);

            [t, ord] = sort(t,'ascend');
            X = X(ord,:);

            [t, ia] = unique(t,'stable');
            X = X(ia,:);

            app.t_real = t;

            sigma = app.sigma;
            sigma(sigma==0 | isnan(sigma)) = 1;

            % standardizzazione + proiezione CORRETTA (usa muPCA)
            Xz = (X - app.mu) ./ sigma;
            scores = (Xz - app.muPCA) * app.coeff;

            if size(scores,2) < 2
                error("PCA coeff produce meno di 2 componenti. Non posso plottare PC2.");
            end

            app.PC1 = scores(:,1);
            app.PC2 = scores(:,2);

            % ---- PLOT PC1 (TOP) ----
            cla(app.ax1); hold(app.ax1,'on'); grid(app.ax1,'on');
            plot(app.ax1, app.t_real, app.PC1, '-');
            yline(app.ax1, app.baseline_mean_PC1, '--', 'Baseline');
            yline(app.ax1, app.LOD_upper_PC1, '-', 'LOD+');
            yline(app.ax1, app.LOD_lower_PC1, '-', 'LOD-');
            title(app.ax1, char(fname) + "  |  PC1", 'Interpreter','none');
            xlabel(app.ax1,'Datetime (REAL)');
            ylabel(app.ax1,'PC1');
            hold(app.ax1,'off');

            % ---- PLOT PC2 (BOTTOM) ----
            cla(app.ax2); hold(app.ax2,'on'); grid(app.ax2,'on');
            plot(app.ax2, app.t_real, app.PC2, '-');
            yline(app.ax2, app.baseline_mean_PC2, '--', 'Baseline');
            yline(app.ax2, app.LOD_upper_PC2, '-', 'LOD+');
            yline(app.ax2, app.LOD_lower_PC2, '-', 'LOD-');
            title(app.ax2, char(fname) + "  |  PC2", 'Interpreter','none');
            xlabel(app.ax2,'Datetime (REAL)');
            ylabel(app.ax2,'PC2');
            hold(app.ax2,'off');

            if ~isempty(app.t_real)
                app.lblRange.Text = sprintf("Data range: %s  →  %s   (N=%d)", ...
                    datestr(min(app.t_real),'yyyy-mm-dd HH:MM:SS'), ...
                    datestr(max(app.t_real),'yyyy-mm-dd HH:MM:SS'), ...
                    numel(app.t_real));
            else
                app.lblRange.Text = "Data range: (empty after filtering)";
            end

            app.lblStatus.Text = "Status: loaded " + fname;

        catch ME
            uialert(fig, ME.message, 'Error');
            app.lblStatus.Text = "Status: error loading file.";
        end
    end

    function updateStatus()
        if app.modelLoaded && app.baseLoaded
            app.lblStatus.Text = "Status: model+baseline OK. Now select batch.";
        elseif app.modelLoaded && ~app.baseLoaded
            app.lblStatus.Text = "Status: model OK. Load baseline.";
        elseif ~app.modelLoaded && app.baseLoaded
            app.lblStatus.Text = "Status: baseline OK. Load model.";
        else
            app.lblStatus.Text = "Status: load model + baseline, then batch.";
        end
    end

end

%% ===== helper: ensure predictor columns exist (case-insensitive mapping) =====
function T = ensurePredictorsColumns(T, predictors)
vn = string(T.Properties.VariableNames);
vnLow = lower(strtrim(vn));

for k = 1:numel(predictors)
    want = string(predictors(k));
    wantLow = lower(strtrim(want));

    if ismember(want, vn)
        continue;
    end

    idx = find(vnLow == wantLow, 1);
    if ~isempty(idx)
        % rinomina colonna trovata nel nome "want"
        T.Properties.VariableNames{idx} = char(want);
        vn = string(T.Properties.VariableNames);
        vnLow = lower(strtrim(vn));
    else
        error("Monitoring CSV missing predictor column: %s", want);
    end
end
end

%% ===== helper: robust timestamp parsing =====
function t = parseTimestamp(ts, tz)
if isdatetime(ts)
    t = ts;
    try, t.TimeZone = tz; end %#ok<TRYNC>
    return;
end

if isnumeric(ts)
    t = datetime(ts,'ConvertFrom','posixtime','TimeZone',tz);
    return;
end

s = string(ts);
s = strtrim(s);
t = NaT(size(s));

fmts = [ ...
    "dd-MMM-yyyy HH:mm:ss"
    "dd-MMM-yyyy HH:mm"
    "yyyy-MM-dd HH:mm:ss"
    "yyyy-MM-dd HH:mm"
    "dd/MM/yyyy HH:mm:ss"
    "dd/MM/yyyy HH:mm"
    ];

for k = 1:numel(fmts)
    try
        tk = datetime(s,'InputFormat',fmts(k),'Locale','en_US','TimeZone',tz);
        ok = ~isnat(tk);
        t(ok) = tk(ok);
    catch
    end
    if all(~isnat(t)), break; end
end

if any(isnat(t))
    try
        tk = datetime(s,'TimeZone',tz);
        ok = ~isnat(tk);
        t(ok) = tk(ok);
    catch
    end
end
end