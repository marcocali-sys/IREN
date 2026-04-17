function ELLONA_04_pca_gui()
% ELLONA_04_PCA_GUI
% =========================================================================
% PCA interattiva ELLONA/IREN — adattata da PCA_INTERATTIVA_TRAINTEST_FEATEXCLUDE
%
% Funzionalita':
%   - Lista CLASSI: seleziona quelle da escludere dalla PCA
%   - Lista FEATURE: seleziona quelle da escludere dalla PCA
%   - "Aggiorna PCA" ricalcola con classi e feature attive
%   - "Reincluidi tutte" azzera selezione
%   - PCA fit SOLO su TRAIN (mu/sigma/coeff dal train)
%   - TEST proiettato: scoreTest = Xtest_norm * coeffTrain
%   - Vista 2D/3D, metodo SVD o Cov(eig)
%   - Datacursor con info: Classe2, Sample_ID, Cod, Diluizione
%   - Viewer LOADINGS: bar loadings + heatmap + export PNG
% =========================================================================
clearvars -except varargin;
clc;

cd(fullfile(getenv('HOME'), 'Desktop', 'IREN'));

%% === 1) Seleziona CSV TRAIN e TEST ===
[fnTr, fpTr] = uigetfile({'*.csv','CSV (*.csv)'}, 'Seleziona TRAIN_FEATURES.csv');
if isequal(fnTr,0), error('Nessun TRAIN selezionato.'); end
trainCsv = fullfile(fpTr, fnTr);

[fnTe, fpTe] = uigetfile({'*.csv','CSV (*.csv)'}, 'Seleziona TEST_FEATURES.csv');
if isequal(fnTe,0), error('Nessun TEST selezionato.'); end
testCsv = fullfile(fpTe, fnTe);

% Legge con delimitatore ";" e nomi variabile MATLAB-safe
optsTr = detectImportOptions(trainCsv, 'Delimiter', ';');
optsTe = detectImportOptions(testCsv,  'Delimiter', ';');
Ttr = readtable(trainCsv, optsTr);
Tte = readtable(testCsv,  optsTe);
fprintf("TRAIN: %d righe, %d colonne\n", height(Ttr), width(Ttr));
fprintf("TEST : %d righe, %d colonne\n", height(Tte), width(Tte));

varsTr = string(Ttr.Properties.VariableNames);
varsTe = string(Tte.Properties.VariableNames);

%% === 2) Colonne meta da escludere ===
% MATLAB converte "." in "_" nei nomi variabile
metaCols = ["Data_analisi","Classe","Classe2","Diluizione","Cod", ...
            "Step1","Step2","Step3","Sample_ID","Sample_number", ...
            "Datetime_inizio","Datetime_fine"];

commonVars = intersect(varsTr, varsTe, 'stable');
cand = commonVars(~ismember(commonVars, metaCols));

allFeatCols = strings(0,1);
for i = 1:numel(cand)
    v = cand(i);
    if isnumeric(Ttr.(v)) && isnumeric(Tte.(v))
        allFeatCols(end+1,1) = v;
    end
end
if isempty(allFeatCols)
    error("Nessuna feature numerica comune trovata tra TRAIN e TEST.");
end
fprintf("Feature numeriche disponibili: %d\n", numel(allFeatCols));

%% === 3) Lista classi (da Classe2) ===
classesTr = unique(string(Ttr.Classe2));
classTe   = unique(string(Tte.Classe2));
allClassNames = unique([classesTr; classTe]);
fprintf("Classi disponibili: %s\n", strjoin(allClassNames, ', '));

%% === 4) Evidenzia feature RFECV-selected con ★ (se file disponibile) ===
logoFile = 'output/06_rfecv/rfecv_selected_features.txt';
logoFeats = strings(0,1);
if isfile(logoFile)
    fid_l = fopen(logoFile,'r');
    lns   = textscan(fid_l,'%s','Delimiter','\n'); fclose(fid_l);
    lns   = lns{1};
    for i = 1:numel(lns)
        l = strtrim(lns{i});
        if ~isempty(l) && l(1) ~= '#'
            logoFeats(end+1,1) = string(l);
        end
    end
    fprintf("Feature RFECV-selected caricate: %d\n", numel(logoFeats));
end

% Costruisce etichette listbox: aggiunge "★" alle feature LOGO-selected
featLabels = allFeatCols;
for i = 1:numel(allFeatCols)
    if ismember(allFeatCols(i), logoFeats)
        featLabels(i) = "★ " + allFeatCols(i);
    end
end

%% === 5) Struttura app ===
app = struct();
app.Tall           = [];
app.rowIdxAllTrain = [];
app.rowIdxAllTest  = [];
app.lastExplained  = [];
app.coeff          = [];
app.featCols       = strings(0,1);
app.mu             = [];
app.sigmaSafe      = [];
app.allFeatCols    = allFeatCols;
app.allClassNames  = allClassNames;

viewOptions   = {'2D (PC1-PC2)','3D (PC1-PC2-PC3)'};
methodOptions = {'Standard (SVD)','Covarianza (eig)'};

%% === 6) GUI ===
f = figure('Name','PCA ELLONA/IREN — Interattiva', ...
    'NumberTitle','off','Color','w', ...
    'Units','normalized','Position',[0.03 0.03 0.93 0.90]);

ax = axes('Parent', f, 'Units','normalized','Position',[0.30 0.12 0.68 0.82]);
grid(ax,'on'); xlabel(ax,'PC1'); ylabel(ax,'PC2');
title(ax,'PCA (fit su TRAIN, TEST proiettato)');

% --- Vista ---
uicontrol('Parent',f,'Style','text','String','Vista:', ...
    'Units','normalized','Position',[0.01 0.905 0.13 0.028], ...
    'HorizontalAlignment','left','FontWeight','bold');
hPopupView = uicontrol('Parent',f,'Style','popupmenu', ...
    'Units','normalized','Position',[0.01 0.872 0.27 0.033], ...
    'String',viewOptions,'Value',1);

% --- Metodo PCA ---
uicontrol('Parent',f,'Style','text','String','Metodo PCA:', ...
    'Units','normalized','Position',[0.01 0.832 0.13 0.028], ...
    'HorizontalAlignment','left','FontWeight','bold');
hPopupMethod = uicontrol('Parent',f,'Style','popupmenu', ...
    'Units','normalized','Position',[0.01 0.799 0.27 0.033], ...
    'String',methodOptions,'Value',1);

% --- Sezione CLASSI ---
uicontrol('Parent',f,'Style','text','String','Classi da ESCLUDERE:', ...
    'Units','normalized','Position',[0.01 0.762 0.27 0.028], ...
    'HorizontalAlignment','left','FontWeight','bold','ForegroundColor',[0.1 0.3 0.7]);

hLabelClassCount = uicontrol('Parent',f,'Style','text', ...
    'String',sprintf('Classi attive: %d / %d', numel(allClassNames), numel(allClassNames)), ...
    'Units','normalized','Position',[0.01 0.737 0.27 0.023], ...
    'HorizontalAlignment','left','FontSize',8,'ForegroundColor',[0 0.5 0]);

nClasses = numel(allClassNames);
hListClasses = uicontrol('Parent',f,'Style','listbox', ...
    'Units','normalized','Position',[0.01 0.608 0.27 0.127], ...
    'String',cellstr(allClassNames), ...
    'Max',nClasses,'Value',[], ...
    'FontSize',9,'Callback',@(s,e) onClassListChange());

uicontrol('Parent',f,'Style','pushbutton','String','Includi tutte le classi', ...
    'Units','normalized','Position',[0.01 0.564 0.27 0.036], ...
    'FontWeight','bold','ForegroundColor',[0.1 0.3 0.7], ...
    'Callback',@(s,e) resetClassExclusion());

% --- Sezione FEATURE ---
uicontrol('Parent',f,'Style','text','String','Feature da ESCLUDERE  (★=LOGO selected):', ...
    'Units','normalized','Position',[0.01 0.524 0.27 0.028], ...
    'HorizontalAlignment','left','FontWeight','bold','ForegroundColor',[0.7 0 0]);

uicontrol('Parent',f,'Style','text', ...
    'String','Ctrl+click = selezione multipla | selezionate = ESCLUSE', ...
    'Units','normalized','Position',[0.01 0.498 0.27 0.023], ...
    'HorizontalAlignment','left','FontSize',7,'ForegroundColor',[0.4 0.4 0.4]);

hLabelCount = uicontrol('Parent',f,'Style','text', ...
    'String',sprintf('Feature attive: %d / %d', numel(allFeatCols), numel(allFeatCols)), ...
    'Units','normalized','Position',[0.01 0.474 0.27 0.023], ...
    'HorizontalAlignment','left','FontSize',8,'ForegroundColor',[0 0.5 0]);

hListFeats = uicontrol('Parent',f,'Style','listbox', ...
    'Units','normalized','Position',[0.01 0.145 0.27 0.327], ...
    'String',cellstr(featLabels), ...
    'Max',numel(allFeatCols),'Value',[], ...
    'FontSize',8,'Callback',@(s,e) onListChange());

uicontrol('Parent',f,'Style','pushbutton','String','Reincluidi tutte', ...
    'Units','normalized','Position',[0.01 0.100 0.13 0.038], ...
    'FontWeight','bold','ForegroundColor',[0 0.5 0], ...
    'Callback',@(s,e) resetExclusion());

uicontrol('Parent',f,'Style','pushbutton','String','Inverti selezione', ...
    'Units','normalized','Position',[0.15 0.100 0.13 0.038], ...
    'Callback',@(s,e) invertSelection());

% --- Bottoni PCA ---
uicontrol('Parent',f,'Style','pushbutton','String','Aggiorna PCA', ...
    'Units','normalized','Position',[0.30 0.04 0.14 0.055], ...
    'FontWeight','bold','BackgroundColor',[0.2 0.5 0.8],'ForegroundColor','w', ...
    'Callback',@(s,e) updatePCA());

uicontrol('Parent',f,'Style','pushbutton','String','Scree Plot', ...
    'Units','normalized','Position',[0.45 0.04 0.10 0.055], ...
    'FontWeight','bold','Callback',@(s,e) showScree());

uicontrol('Parent',f,'Style','pushbutton','String','Loadings', ...
    'Units','normalized','Position',[0.56 0.04 0.10 0.055], ...
    'FontWeight','bold','Callback',@(s,e) showLoadings());

hTextVar = uicontrol('Parent',f,'Style','text', ...
    'String','PC1=--.-%  PC2=--.-%  PC3=--.-% ', ...
    'Units','normalized','Position',[0.67 0.04 0.31 0.055], ...
    'HorizontalAlignment','left','FontSize',8);

% Datacursor
dcm = datacursormode(f);
set(dcm,'Enable','on','UpdateFcn',@cursorUpdate);

% Prima PCA con tutte le feature e classi
updatePCA();

%% ============================================================
%                     Nested functions
%% ============================================================

    function onClassListChange()
        nTotal = numel(allClassNames);
        nExcl  = numel(get(hListClasses,'Value'));
        nAct   = nTotal - nExcl;
        if nExcl > 0
            set(hLabelClassCount,'String', ...
                sprintf('Classi attive: %d / %d  (%d escluse)', nAct, nTotal, nExcl), ...
                'ForegroundColor',[0.7 0 0]);
        else
            set(hLabelClassCount,'String', ...
                sprintf('Classi attive: %d / %d', nAct, nTotal), ...
                'ForegroundColor',[0 0.5 0]);
        end
    end

    function resetClassExclusion()
        set(hListClasses,'Value',[]);
        onClassListChange();
    end

    function onListChange()
        nTotal  = numel(allFeatCols);
        nExcl   = numel(get(hListFeats,'Value'));
        nActive = nTotal - nExcl;
        if nExcl > 0
            set(hLabelCount,'String', ...
                sprintf('Feature attive: %d / %d  (%d escluse)', nActive, nTotal, nExcl), ...
                'ForegroundColor',[0.7 0 0]);
        else
            set(hLabelCount,'String', ...
                sprintf('Feature attive: %d / %d', nActive, nTotal), ...
                'ForegroundColor',[0 0.5 0]);
        end
    end

    function resetExclusion()
        set(hListFeats,'Value',[]);
        onListChange();
    end

    function invertSelection()
        nTotal  = numel(allFeatCols);
        currSel = get(hListFeats,'Value');
        set(hListFeats,'Value',setdiff(1:nTotal, currSel));
        onListChange();
    end

    function updatePCA()
        delete(findall(f,'Type','colorbar'));
        set(dcm,'Enable','off');

        %% Filtra CLASSI
        exclClassIdx = get(hListClasses,'Value');
        if ~isempty(exclClassIdx)
            exclClasses = allClassNames(exclClassIdx);
        else
            exclClasses = strings(0,1);
        end

        maskTr = ~ismember(string(Ttr.Classe2), exclClasses);
        maskTe = ~ismember(string(Tte.Classe2), exclClasses);
        TtrF   = Ttr(maskTr,:);
        TteF   = Tte(maskTe,:);

        if height(TtrF) < 3
            warndlg('Troppo pochi campioni TRAIN (min 3).','Classi insufficienti');
            set(dcm,'Enable','on'); return;
        end

        nExclClass = numel(exclClassIdx);
        if nExclClass > 0
            fprintf('Classi escluse: %s\n', strjoin(exclClasses,', '));
        end

        %% Filtra FEATURE
        exclFeatIdx = get(hListFeats,'Value');
        keepIdx  = setdiff(1:numel(allFeatCols), exclFeatIdx);
        featCols = allFeatCols(keepIdx);

        if isempty(featCols)
            warndlg('Nessuna feature attiva!','Errore');
            set(dcm,'Enable','on'); return;
        end

        nExclFeat = numel(exclFeatIdx);
        fprintf('PCA: %d feature attive (%d escluse) | %d classi attive (%d escluse)\n', ...
            numel(featCols), nExclFeat, numel(allClassNames)-nExclClass, nExclClass);

        %% Costruisce Xtrain / Xtest
        Xtrain = TtrF{:, cellstr(featCols)};
        Xtest  = TteF{:, cellstr(featCols)};

        % Imputa NA con mediana colonna (calcolata su train)
        colMed = median(Xtrain,'omitnan');
        for j = 1:size(Xtrain,2)
            Xtrain(isnan(Xtrain(:,j)),j) = colMed(j);
            Xtest(isnan(Xtest(:,j)),j)   = colMed(j);
        end

        %% Normalizzazione su TRAIN
        mu        = mean(Xtrain);
        sigma     = std(Xtrain);
        sigmaSafe = sigma; sigmaSafe(sigmaSafe==0) = 1;
        Xtrain_norm = (Xtrain - mu) ./ sigmaSafe;
        Xtest_norm  = (Xtest  - mu) ./ sigmaSafe;

        %% PCA su TRAIN
        methodIdx  = get(hPopupMethod,'Value');
        methodName = methodOptions{methodIdx};

        switch methodName
            case 'Standard (SVD)'
                [coeff, scoreTrain, ~, ~, explained] = pca(Xtrain_norm);
            case 'Covarianza (eig)'
                C = cov(Xtrain_norm);
                [V,D] = eig(C,'vector');
                [Dsorted, idxEig] = sort(D,'descend');
                explained  = 100 * Dsorted ./ sum(Dsorted);
                coeff      = V(:,idxEig);
                scoreTrain = Xtrain_norm * coeff;
        end

        scoreTest = Xtest_norm * coeff;

        if size(scoreTrain,2) < 3
            scoreTrain(:,end+1:3) = 0;
            scoreTest(:,end+1:3)  = 0;
            explained(end+1:3)    = 0;
        end

        % Cache
        app.lastExplained = explained(:);
        app.coeff         = coeff;
        app.featCols      = featCols;
        app.mu            = mu;
        app.sigmaSafe     = sigmaSafe;

        e1 = explained(1); e2 = explained(2); e3 = explained(3);

        classInfo = '';
        if nExclClass > 0
            classInfo = sprintf(' | -cl:%s', strjoin(exclClasses,','));
        end
        set(hTextVar,'String', sprintf('%s | PC1=%.1f%% PC2=%.1f%% PC3=%.1f%% | feat:%d/%d%s', ...
            methodName, e1, e2, e3, numel(featCols), numel(allFeatCols), classInfo));

        %% Tabella combinata per datacursor
        Tall = [TtrF; TteF];
        Tall.Set = [repmat("TRAIN", height(TtrF), 1); repmat("TEST", height(TteF), 1)];
        app.Tall           = Tall;
        app.rowIdxAllTrain = (1:height(TtrF))';
        app.rowIdxAllTest  = (height(TtrF)+1 : height(TtrF)+height(TteF))';

        %% Plot
        viewIdx = get(hPopupView,'Value');
        rotate3d(ax,'off');
        delete(allchild(ax));
        legend(ax,'off');
        cla(ax,'reset');
        set(ax,'Parent',f,'Units','normalized','Position',[0.30 0.12 0.68 0.82]);
        hold(ax,'on'); grid(ax,'on');

        cAll   = categorical(string(Tall.Classe2));
        cTrain = cAll(app.rowIdxAllTrain);
        cTest  = cAll(app.rowIdxAllTest);
        cats   = union(categories(cTrain), categories(cTest));
        if isempty(cats), cats = {'All'}; end
        Cmap   = lines(numel(cats));

        if viewIdx == 1   % 2D
            for ii = 1:numel(cats)
                mCTrain = (cTrain == cats{ii});
                mCTest  = (cTest  == cats{ii});
                if any(mCTrain)
                    sc = scatter(ax, scoreTrain(mCTrain,1), scoreTrain(mCTrain,2), ...
                        65, Cmap(ii,:), 'filled', 'o', 'DisplayName', char(cats{ii}));
                    sc.UserData = app.rowIdxAllTrain(mCTrain);
                else
                    scatter(ax,NaN,NaN,65,Cmap(ii,:),'filled','o','DisplayName',char(cats{ii}));
                end
                if any(mCTest)
                    sc = scatter(ax, scoreTest(mCTest,1), scoreTest(mCTest,2), ...
                        85, Cmap(ii,:), '^', 'LineWidth', 1.4, 'HandleVisibility','off');
                    sc.UserData = app.rowIdxAllTest(mCTest);
                end
            end
            xlabel(ax, sprintf('PC1 (%.1f%%)',e1));
            ylabel(ax, sprintf('PC2 (%.1f%%)',e2));
            title(ax, sprintf('PCA 2D  ●=TRAIN  △=TEST  |  feat:%d/%d  classi:%d/%d', ...
                numel(featCols), numel(allFeatCols), numel(allClassNames)-nExclClass, numel(allClassNames)));
            view(ax,2); rotate3d(ax,'off');
        else              % 3D
            for ii = 1:numel(cats)
                mCTrain = (cTrain == cats{ii});
                mCTest  = (cTest  == cats{ii});
                if any(mCTrain)
                    sc = scatter3(ax, scoreTrain(mCTrain,1), scoreTrain(mCTrain,2), scoreTrain(mCTrain,3), ...
                        65, Cmap(ii,:), 'filled', 'o', 'DisplayName', char(cats{ii}));
                    sc.UserData = app.rowIdxAllTrain(mCTrain);
                else
                    scatter3(ax,NaN,NaN,NaN,65,Cmap(ii,:),'filled','o','DisplayName',char(cats{ii}));
                end
                if any(mCTest)
                    sc = scatter3(ax, scoreTest(mCTest,1), scoreTest(mCTest,2), scoreTest(mCTest,3), ...
                        85, Cmap(ii,:), '^', 'LineWidth', 1.4, 'HandleVisibility','off');
                    sc.UserData = app.rowIdxAllTest(mCTest);
                end
            end
            xlabel(ax, sprintf('PC1 (%.1f%%)',e1));
            ylabel(ax, sprintf('PC2 (%.1f%%)',e2));
            zlabel(ax, sprintf('PC3 (%.1f%%)',e3));
            title(ax, sprintf('PCA 3D  ●=TRAIN  △=TEST  |  feat:%d/%d  classi:%d/%d', ...
                numel(featCols), numel(allFeatCols), numel(allClassNames)-nExclClass, numel(allClassNames)));
            view(ax,3); rotate3d(ax,'on');
        end

        legend(ax,'show','Location','bestoutside','FontSize',8);
        hold(ax,'off');
        drawnow;
        set(dcm,'Enable','on');
    end

% ---- Scree ----
    function showScree()
        if isempty(app.lastExplained)
            warndlg('Esegui prima la PCA.','Nessun dato'); return;
        end
        figure('Name','Scree Plot','Color','w','Units','normalized','Position',[0.18 0.18 0.64 0.55]);
        expl  = app.lastExplained(:);
        nComp = numel(expl);
        subplot(1,2,1);
        bar(expl,'FaceColor',[0.282 0.471 0.812],'EdgeColor','none');
        xlabel('Componente'); ylabel('Varianza spiegata (%)');
        title(sprintf('Scree Plot — %d feature', numel(app.featCols))); grid on;
        subplot(1,2,2);
        plot(1:nComp, cumsum(expl),'-o','LineWidth',1.3, ...
             'Color',[0.839 0.373 0.373],'MarkerFaceColor',[0.839 0.373 0.373],'MarkerSize',5);
        yline(90,'--','90%','Color',[0.5 0.5 0.5],'LineWidth',0.9);
        xlabel('Componente'); ylabel('Varianza cumulata (%)');
        title('Varianza cumulata'); grid on; ylim([0 105]);
    end

% ---- Loadings ----
    function showLoadings()
        if isempty(app.coeff)
            warndlg('Esegui prima la PCA.','Nessun dato'); return;
        end
        coeff = app.coeff;
        feat  = app.featCols(:);
        expl  = app.lastExplained(:);
        if size(coeff,2) < 3, coeff(:,end+1:3) = 0; expl(end+1:3) = 0; end

        fL = figure('Name','PCA Loadings','Color','w','Units','normalized','Position',[0.10 0.08 0.82 0.82]);
        axBar = axes('Parent',fL,'Units','normalized','Position',[0.06 0.12 0.54 0.78]);
        axHm  = axes('Parent',fL,'Units','normalized','Position',[0.65 0.12 0.32 0.78]);

        maxPcShown  = min(10, numel(expl));
        compOptions = arrayfun(@(k) sprintf('PC%d (%.1f%%)',k,expl(k)), 1:maxPcShown, 'UniformOutput',false);

        uicontrol('Parent',fL,'Style','text','String','Componente:', ...
            'Units','normalized','Position',[0.06 0.93 0.12 0.04], ...
            'HorizontalAlignment','left','FontWeight','bold');
        hComp = uicontrol('Parent',fL,'Style','popupmenu', ...
            'Units','normalized','Position',[0.18 0.935 0.18 0.04], ...
            'String',compOptions,'Value',1, ...
            'Callback',@(s,e) redrawBar());
        uicontrol('Parent',fL,'Style','pushbutton','String','Export PNG', ...
            'Units','normalized','Position',[0.38 0.935 0.12 0.04], ...
            'FontWeight','bold','Callback',@(s,e) exportPng());
        uicontrol('Parent',fL,'Style','pushbutton','String','Top loadings', ...
            'Units','normalized','Position',[0.51 0.935 0.12 0.04], ...
            'FontWeight','bold','Callback',@(s,e) showTopTable());

        nPcHm = min(5, size(coeff,2));
        imagesc(axHm, coeff(:,1:nPcHm));
        colormap(axHm, parula); colorbar(axHm);
        axHm.XTick = 1:nPcHm;
        axHm.XTickLabel = arrayfun(@(k) sprintf('PC%d',k), 1:nPcHm, 'UniformOutput',false);
        axHm.YTick = 1:numel(feat);
        if numel(feat) <= 60, axHm.YTickLabel = cellstr(feat); else, axHm.YTickLabel = {}; end
        title(axHm, sprintf('Heatmap loadings (PC1–PC%d)', nPcHm));
        xlabel(axHm,'Componenti'); ylabel(axHm,'Feature');
        grid(axHm,'on');

        redrawBar();

        function redrawBar()
            pc = max(1, min(get(hComp,'Value'), size(coeff,2)));
            L  = coeff(:,pc);
            [~, ord] = sort(abs(L),'descend');
            Ls = L(ord); feats = feat(ord);
            Nshow = 40;
            if numel(Ls) > Nshow
                Ls = Ls(1:Nshow); feats = feats(1:Nshow);
                note = sprintf('Top %d su %d', Nshow, numel(L));
            else
                note = '';
            end
            cla(axBar);
            bar(axBar, Ls, 'FaceColor',[0.282 0.471 0.812],'EdgeColor','none');
            grid(axBar,'on');
            title(axBar, sprintf('Loadings %s', compOptions{pc}));
            xlabel(axBar,'Feature (per |loading|)'); ylabel(axBar,'Loading');
            axBar.XTick = 1:numel(feats);
            if numel(feats) <= 40
                axBar.XTickLabel = cellstr(feats);
                axBar.XTickLabelRotation = 60;
                axBar.TickLabelInterpreter = 'none';
            else
                axBar.XTickLabel = {};
            end
            if ~isempty(note)
                text(axBar,0.01,0.98,note,'Units','normalized','VerticalAlignment','top','FontSize',9);
            end
        end

        function showTopTable()
            pc = max(1, min(get(hComp,'Value'), size(coeff,2)));
            L  = coeff(:,pc);
            [~, ord] = sort(abs(L),'descend');
            topN   = min(30, numel(L));
            feats2 = feat(ord(1:topN)); vals = L(ord(1:topN));
            Tout = table(feats2, vals, abs(vals), 'VariableNames',{'Feature','Loading','AbsLoading'});
            fT = figure('Name',sprintf('Top loadings %s', compOptions{pc}),'Color','w', ...
                'Units','normalized','Position',[0.25 0.20 0.50 0.60]);
            uitable('Parent',fT,'Data',Tout{:,:}, ...
                'ColumnName',Tout.Properties.VariableNames, ...
                'Units','normalized','Position',[0.05 0.05 0.90 0.90]);
        end

        function exportPng()
            [file, path] = uiputfile('Loadings.png','Salva PNG loadings');
            if isequal(file,0), return; end
            try
                exportgraphics(fL, fullfile(path,file), 'Resolution', 220);
            catch
                print(fL, fullfile(path,file), '-dpng', '-r220');
            end
            msgbox(sprintf('Salvato: %s', file),'OK');
        end
    end

% ---- Datacursor ----
    function txt = cursorUpdate(~, event_obj)
        hTarget      = get(event_obj,'Target');
        idxInScatter = get(event_obj,'DataIndex');
        rowIdxAll    = get(hTarget,'UserData');
        if isempty(rowIdxAll) || idxInScatter > numel(rowIdxAll)
            txt = {'N/A'}; return;
        end
        rowIdx = rowIdxAll(idxInScatter);
        Tall   = app.Tall;
        v      = string(Tall.Properties.VariableNames);
        pos    = get(event_obj,'Position');

        setStr  = "N/A"; if ismember("Set",v),       setStr  = string(Tall.Set(rowIdx));      end
        classe  = "N/A"; if ismember("Classe2",v),   classe  = string(Tall.Classe2(rowIdx));  end
        sid     = "N/A"; if ismember("Sample_ID",v), sid     = string(Tall.Sample_ID(rowIdx));end
        cod     = "N/A"; if ismember("Cod",v),       cod     = string(Tall.Cod(rowIdx));      end
        dil     = "N/A"; if ismember("Diluizione",v),dil     = string(Tall.Diluizione(rowIdx));end
        data    = "N/A"; if ismember("Data_analisi",v),data  = string(Tall.Data_analisi(rowIdx));end

        txt = {};
        if numel(pos)>=1, txt{end+1} = sprintf('PC1 = %.3f', pos(1)); end
        if numel(pos)>=2, txt{end+1} = sprintf('PC2 = %.3f', pos(2)); end
        if numel(pos)>=3, txt{end+1} = sprintf('PC3 = %.3f', pos(3)); end
        txt{end+1} = sprintf('Set:       %s', setStr);
        txt{end+1} = sprintf('Classe2:   %s', classe);
        txt{end+1} = sprintf('Sample.ID: %s', sid);
        txt{end+1} = sprintf('Cod:       %s', cod);
        txt{end+1} = sprintf('Diluizione:%s', dil);
        txt{end+1} = sprintf('Data:      %s', data);
        txt{end+1} = sprintf('Row:       %d', rowIdx);
    end

end
