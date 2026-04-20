function BATCH_GUI_PC1_PC2_LOD_VIEWER_SIMPLE_2()
% BATCH_GUI_PC1_PC2_LOD_VIEWER_SIMPLE
% Viewer PC1 + PC2 + LOD (compatibile UI vecchie).
%
% FIX scala PCA:
%   Z = (X - mu) ./ sigma
%   Scores = (Z - muPCA) * coeff
%
% Model .mat richiesto: mu, sigma, coeff, predictors
% Consigliato: muPCA (se manca: warning + stima dal file corrente, non perfetto)
%
% Baseline stats CSV supportato:
%   - MEDIANS: PC1_mean_of_medians, PC1_std_of_medians, PC2_mean_of_medians, PC2_std_of_medians
%   - POINTWISE: PC1_mean, PC1_std, PC2_mean, PC2_std

clearvars; clc;

app = struct();
app.modelPath = "";
app.baselinePath = "";
app.batchPaths = strings(0,1);
app.batchNames = strings(0,1);
app.idx = 0;

app.timeZone = "UTC"; % metti "Europe/Rome" se vuoi

% Model
app.mu = [];
app.sigma = [];
app.coeff = [];
app.predictors = strings(1,0);
app.muPCA = [];
app.modelLoaded = false;

% Baseline / LOD
app.baseLoaded = false;
app.baselineMode = "auto"; % "medians" | "pointwise"

app.baseline_mean_PC1 = NaN;
app.baseline_std_PC1  = NaN;
app.LOD_lower_PC1 = NaN;
app.LOD_upper_PC1 = NaN;

app.baseline_mean_PC2 = NaN;
app.baseline_std_PC2  = NaN;
app.LOD_lower_PC2 = NaN;
app.LOD_upper_PC2 = NaN;

app.lodK = 3;

% Current data
app.t_real = datetime.empty;
app.PC1 = [];
app.PC2 = [];

app.t_plot = datetime.empty;
app.PC1_plot = [];
app.PC2_plot = [];

%% ===== UI =====
fig = uifigure('Name','PC1+PC2 + LOD Viewer (2 plots)','Position',[120 120 1280 740]);

gl = uigridlayout(fig,[8 6]);
gl.RowHeight   = {28,28,28,28,'1x',28,24,24};
gl.ColumnWidth = {130,520,110,140,140,'1x'};
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

% --- Row 4: options
lblMode = uilabel(gl,'Text','Plot mode:','HorizontalAlignment','right');
lblMode.Layout.Row = 4; lblMode.Layout.Column = 1;

app.ddMode = uidropdown(gl,'Items',{'Pointwise','Window median'},'Value','Pointwise','ValueChangedFcn',@onChangeOptions);
app.ddMode.Layout.Row = 4; app.ddMode.Layout.Column = 2;

lblWin = uilabel(gl,'Text','Window (s):','HorizontalAlignment','right');
lblWin.Layout.Row = 4; lblWin.Layout.Column = 3;

app.edWin = uieditfield(gl,'numeric','Value',120,'Limits',[1 Inf],'RoundFractionalValues','on','ValueChangedFcn',@onChangeOptions);
app.edWin.Layout.Row = 4; app.edWin.Layout.Column = 4;

lblK = uilabel(gl,'Text','LOD k·std:','HorizontalAlignment','right');
lblK.Layout.Row = 4; lblK.Layout.Column = 5;

app.edK = uieditfield(gl,'numeric','Value',3,'Limits',[0.5 20],'ValueChangedFcn',@onChangeOptions);
app.edK.Layout.Row = 4; app.edK.Layout.Column = 6;

% --- Row 5: listbox + right panel (2 plots)
app.lb = uilistbox(gl,'Items',{},'ValueChangedFcn',@onSelectFile);
app.lb.Layout.Row = 5; app.lb.Layout.Column = [1 3];

rightPanel = uipanel(gl,'BorderType','none');
rightPanel.Layout.Row = 5; rightPanel.Layout.Column = [4 6];

rp = uigridlayout(rightPanel,[2 1]);
rp.RowHeight = {'1x','1x'};
rp.ColumnWidth = {'1x'};
rp.Padding = [0 0 0 0];
rp.RowSpacing = 10;

app.ax1 = uiaxes(rp); app.ax1.Layout.Row = 1; app.ax1.Layout.Column = 1;
grid(app.ax1,'on'); ylabel(app.ax1,'PC1'); xlabel(app.ax1,'Datetime (REAL)'); title(app.ax1,'PC1');

app.ax2 = uiaxes(rp); app.ax2.Layout.Row = 2; app.ax2.Layout.Column = 1;
grid(app.ax2,'on'); ylabel(app.ax2,'PC2'); xlabel(app.ax2,'Datetime (REAL)'); title(app.ax2,'PC2');

% --- Row 6: nav
app.btnPrev = uibutton(gl,'Text','◀ Prev','ButtonPushedFcn',@onPrev,'Enable','off');
app.btnPrev.Layout.Row = 6; app.btnPrev.Layout.Column = 1;

app.btnNext = uibutton(gl,'Text','Next ▶','ButtonPushedFcn',@onNext,'Enable','off');
app.btnNext.Layout.Row = 6; app.btnNext.Layout.Column = 2;

% --- Row 7: range info
app.lblRange = uilabel(gl,'Text','Data range: (load a file)');
app.lblRange.Layout.Row = 7; app.lblRange.Layout.Column = [1 6];

% --- Row 8: status
app.lblStatus = uilabel(gl,'Text','Status: load model + baseline, then batch.');
app.lblStatus.Layout.Row = 8; app.lblStatus.Layout.Column = [1 6];

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

            if isfield(S,"muPCA")
                app.muPCA = S.muPCA;
            else
                app.muPCA = [];
                warning("Model senza muPCA. Rigenera il pca_model.mat includendo muPCA per coerenza 100%%.");
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
        [f,p] = uigetfile('*.csv','Select baseline stats CSV');
        if isequal(f,0); return; end
        app.baselinePath = fullfile(p,f);
        app.txtBase.Value = app.baselinePath;

        try
            B = readtable(app.baselinePath);
            vn = string(B.Properties.VariableNames);

            hasMedians = all(ismember(["PC1_mean_of_medians","PC1_std_of_medians","PC2_mean_of_medians","PC2_std_of_medians"], vn));
            hasPoint   = all(ismember(["PC1_mean","PC1_std","PC2_mean","PC2_std"], vn));

            if ~(hasMedians || hasPoint)
                error("Baseline stats CSV deve contenere:\n- MEDIANS: PC1_mean_of_medians, PC1_std_of_medians, PC2_mean_of_medians, PC2_std_of_medians\noppure\n- POINTWISE: PC1_mean, PC1_std, PC2_mean, PC2_std");
            end

            if hasMedians && ~hasPoint
                app.baselineMode = "medians";
                app.baseline_mean_PC1 = B.PC1_mean_of_medians(1);
                app.baseline_std_PC1  = B.PC1_std_of_medians(1);
                app.baseline_mean_PC2 = B.PC2_mean_of_medians(1);
                app.baseline_std_PC2  = B.PC2_std_of_medians(1);
            elseif hasPoint && ~hasMedians
                app.baselineMode = "pointwise";
                app.baseline_mean_PC1 = B.PC1_mean(1);
                app.baseline_std_PC1  = B.PC1_std(1);
                app.baseline_mean_PC2 = B.PC2_mean(1);
                app.baseline_std_PC2  = B.PC2_std(1);
            else
                % se entrambi: usa medians di default
                app.baselineMode = "medians";
                app.baseline_mean_PC1 = B.PC1_mean_of_medians(1);
                app.baseline_std_PC1  = B.PC1_std_of_medians(1);
                app.baseline_mean_PC2 = B.PC2_mean_of_medians(1);
                app.baseline_std_PC2  = B.PC2_std_of_medians(1);
            end

            app.baseLoaded = true;
            recomputeLOD();
            updateStatus();

            % se già caricato un file, riplotta
            onChangeOptions();

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

    function onChangeOptions(~,~)
        app.lodK = app.edK.Value;
        recomputeLOD();

        if ~isempty(app.t_real) && ~isempty(app.PC1)
            makePlotSeries();
            plotCurrent(app.batchNames(app.idx));
        end
    end

    function recomputeLOD()
        if ~app.baseLoaded, return; end
        k = app.lodK;

        app.LOD_lower_PC1 = app.baseline_mean_PC1 - k*app.baseline_std_PC1;
        app.LOD_upper_PC1 = app.baseline_mean_PC1 + k*app.baseline_std_PC1;

        app.LOD_lower_PC2 = app.baseline_mean_PC2 - k*app.baseline_std_PC2;
        app.LOD_upper_PC2 = app.baseline_mean_PC2 + k*app.baseline_std_PC2;
    end

    function loadAndPlotCurrent()
        try
            fpath = app.batchPaths(app.idx);
            fname = app.batchNames(app.idx);

            app.lblStatus.Text = "Status: loading " + fname + " ...";
            drawnow;

            T = readtable(fpath, "VariableNamingRule","preserve");
            vn = string(T.Properties.VariableNames);

            missC = setdiff([app.predictors,"timestamp"], vn);
            if ~isempty(missC)
                error("Monitoring CSV missing: %s", strjoin(missC, ", "));
            end

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

            Z = (X - app.mu) ./ sigma;

            % muPCA corretto: se manca nel modello -> stima locale (non perfetto)
            if isempty(app.muPCA)
                muPCA_local = mean(Z,1,"omitnan");
            else
                muPCA_local = app.muPCA;
            end

            Scores = (Z - muPCA_local) * app.coeff;

            if size(Scores,2) < 2
                error("PCA coeff produce meno di 2 componenti. Non posso plottare PC2.");
            end

            app.PC1 = Scores(:,1);
            app.PC2 = Scores(:,2);

            makePlotSeries();
            plotCurrent(fname);

            if ~isempty(app.t_plot)
                app.lblRange.Text = sprintf("Data range: %s  →  %s   (N=%d)   | plot=%s", ...
                    datestr(min(app.t_plot),'yyyy-mm-dd HH:MM:SS'), ...
                    datestr(max(app.t_plot),'yyyy-mm-dd HH:MM:SS'), ...
                    numel(app.t_plot), ...
                    app.ddMode.Value);
            else
                app.lblRange.Text = "Data range: (empty after filtering)";
            end

            app.lblStatus.Text = "Status: loaded " + fname;

        catch ME
            uialert(fig, ME.message, 'Error');
            app.lblStatus.Text = "Status: error loading file.";
        end
    end

    function makePlotSeries()
        mode = string(app.ddMode.Value);

        if mode == "Pointwise"
            app.t_plot   = app.t_real;
            app.PC1_plot = app.PC1;
            app.PC2_plot = app.PC2;
            return;
        end

        w = seconds(app.edWin.Value);

        TT = timetable(app.t_real, app.PC1, app.PC2);

        t0 = TT.Time(1);
        t1 = TT.Time(end);
        tGrid = (t0:w:t1)';

        TTg = retime(TT, tGrid, 'median');

        app.t_plot   = TTg.Time;
        app.PC1_plot = TTg.PC1;
        app.PC2_plot = TTg.PC2;
    end

    function plotCurrent(fname)
        % ---- PC1 ----
        cla(app.ax1); hold(app.ax1,'on'); grid(app.ax1,'on');
        plot(app.ax1, app.t_plot, app.PC1_plot, '-');
        yline(app.ax1, app.baseline_mean_PC1, '--', 'Baseline');
        yline(app.ax1, app.LOD_upper_PC1, '-', 'LOD+');
        yline(app.ax1, app.LOD_lower_PC1, '-', 'LOD-');

        extra = "";
        if app.baselineMode == "medians"
            extra = " | baseline: medians";
        elseif app.baselineMode == "pointwise"
            extra = " | baseline: pointwise";
        end
        title(app.ax1, char(fname) + "  |  PC1  (" + app.ddMode.Value + ")" + extra, 'Interpreter','none');
        xlabel(app.ax1,'Datetime (REAL)');
        ylabel(app.ax1,'PC1');
        hold(app.ax1,'off');

        % ---- PC2 ----
        cla(app.ax2); hold(app.ax2,'on'); grid(app.ax2,'on');
        plot(app.ax2, app.t_plot, app.PC2_plot, '-');
        yline(app.ax2, app.baseline_mean_PC2, '--', 'Baseline');
        yline(app.ax2, app.LOD_upper_PC2, '-', 'LOD+');
        yline(app.ax2, app.LOD_lower_PC2, '-', 'LOD-');
        title(app.ax2, "PC2", 'Interpreter','none');
        xlabel(app.ax2,'Datetime (REAL)');
        ylabel(app.ax2,'PC2');
        hold(app.ax2,'off');
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