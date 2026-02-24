classdef finalLDAppCode < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        TabGroup                    matlab.ui.container.TabGroup

        % --- Tab 1: Reaction Vessel ---
        ReactionvesselTab           matlab.ui.container.Tab
        Image                       matlab.ui.control.Image
        SequenceDropDown            matlab.ui.control.DropDown
        SequenceDropDownLabel       matlab.ui.control.Label
        SolinoidValveSequenceLabel  matlab.ui.control.Label
        load_old_data               matlab.ui.control.Button
        ConnecttoArduinoButton_2    matlab.ui.control.Button
        ExportDataButton            matlab.ui.control.Button
        CloseExportButton           matlab.ui.control.Button
        ListBox                     matlab.ui.control.ListBox
        OtherTemperaturesLabel      matlab.ui.control.Label
        ReactionVesselCreationPanelLabel  matlab.ui.control.Label
        Humidity                    matlab.ui.control.UIAxes
        Leak_Rate                   matlab.ui.control.UIAxes
        CO2                         matlab.ui.control.UIAxes
        Temperature                 matlab.ui.control.UIAxes

        % --- Tab 2: Soil Analysis ---
        SoilAnalysisTab             matlab.ui.container.Tab
        SoilAnalysisPanelLabel      matlab.ui.control.Label
        CameraAxes                  matlab.ui.control.UIAxes
        ConnectCameraButton         matlab.ui.control.Button
        DisconnectCameraButton      matlab.ui.control.Button
        UIAxes                      matlab.ui.control.UIAxes   % Altitude
        UIAxes2                     matlab.ui.control.UIAxes   % CO2
        UIAxes3                     matlab.ui.control.UIAxes   % Humidity
        UIAxes4                     matlab.ui.control.UIAxes   % Rate of Change
        ConnecttoArduinoButton_4    matlab.ui.control.Button
        ExportDataButton_2          matlab.ui.control.Button
        CloseExportButton_2         matlab.ui.control.Button
        AvgCO2PPMLabel              matlab.ui.control.Label
        PeakCO2PPMLabel             matlab.ui.control.Label
    end

    properties (Access = private)
        % --- Tab 1 properties ---
        s
        timerObj
        t0
        row = 0
        maxRows = 5000
        dataSet
        tempLine
        co2Line
        humLine
        timeVec
        lastDataSet
        lastTimeVec
        selectedIdx
        Leak_RateTime
        Leak_RateData
        Leak_RateLine

        % --- Tab 2 properties ---
        soilS
        soilTimerObj
        soilT0
        soilRow = 0
        soilMaxRows = 5000
        soilDataSet          % [Humidity, CO2, Pressure]
        soilTimeVec
        soilHumLine
        soilCO2Line
        soilAltLine
        soilRocLine
        soilRocTime
        soilRocData
        soilAltitudeVec
        soilPresLine

        % Camera
        cam = []
    end

    % ======================================================================
    %  Serial read methods
    % ======================================================================
    methods (Access = public)

        % Tab 1 serial read
        function readSerial(app)
            try
                line = readline(app.s);
                data = str2double(split(line,","));
                if numel(data) ~= 3; return; end

                T = data(1);
                H = data(3);
                C = data(2);

                app.row = app.row + 1;
                app.dataSet(app.row,:) = [T C H];
                tNow = toc(app.t0);
                app.timeVec(app.row) = tNow;

                set(app.tempLine, 'XData', app.timeVec(1:app.row), ...
                                  'YData', app.dataSet(1:app.row,1));
                set(app.co2Line,  'XData', app.timeVec(1:app.row), ...
                                  'YData', app.dataSet(1:app.row,3));
                set(app.humLine,  'XData', app.timeVec(1:app.row), ...
                                  'YData', app.dataSet(1:app.row,2));

                windowSize = 10;
                if app.row >= windowSize
                    idx = app.row-windowSize+1 : app.row;
                    p = polyfit(app.timeVec(idx), app.dataSet(idx,2), 1);
                    slope = p(1);
                else
                    slope = NaN;
                end

                app.Leak_RateTime(app.row) = tNow;
                app.Leak_RateData(app.row) = slope;
                set(app.Leak_RateLine, 'XData', app.Leak_RateTime(1:app.row), ...
                                       'YData', app.Leak_RateData(1:app.row));
                drawnow limitrate
            catch
            end
        end

        % Tab 2 serial read
        function readSoilSerial(app)
            try
                line = readline(app.soilS);
                data = str2double(split(line,","));  % Expect [Humidity, CO2, Pressure]
                if numel(data) ~= 3; return; end
        
                H = data(1);
                C = data(2);
                P = data(3);
        
                % Compute altitude
                P0 = 101325; T0 = 288.15; g = 9.80665; L = 0.0065; R = 287.05;
                altitude = (T0/L) * (1 - (P/P0)^(R*L/g));
        
                % Increment row and store data
                app.soilRow = app.soilRow + 1;
                app.soilDataSet(app.soilRow,:) = [H, C, P];
                app.soilAltitudeVec(app.soilRow) = altitude;
                tNow = toc(app.soilT0);
                app.soilTimeVec(app.soilRow) = tNow;
        
                % ----- Update Pressure vs Time -----
                addpoints(app.soilPresLine, tNow, P);
        
                % ----- Update Altitude vs Time -----
                addpoints(app.soilAltLine, tNow, altitude);
        
                % ----- Update Altitude vs Pressure -----
                addpoints(app.altVsPresLine, P, altitude);
        
                % ----- Optional: CO2 rate of change -----
                windowSize = 10;
                if app.soilRow >= windowSize
                    idx = app.soilRow-windowSize+1 : app.soilRow;
                    p = polyfit(app.soilTimeVec(idx), app.soilDataSet(idx,2), 1);
                    rocSlope = p(1);
                else
                    rocSlope = NaN;
                end
                app.soilRocTime(app.soilRow) = tNow;
                app.soilRocData(app.soilRow) = rocSlope;
                if isfield(app,'soilRocLine')
                    addpoints(app.soilRocLine, tNow, rocSlope);
                end
        
                % ----- Update Avg and Peak CO2 -----
                avgCO2  = mean(app.soilDataSet(1:app.soilRow,2));
                peakCO2 = max(app.soilDataSet(1:app.soilRow,2));
                app.AvgCO2PPMLabel.Text  = sprintf('Avg CO2: %.1f PPM', avgCO2);
                app.PeakCO2PPMLabel.Text = sprintf('Peak CO2: %.1f PPM', peakCO2);
        
                drawnow limitrate
            catch
                % Ignore read errors
            end
        end

        function txt = displayCoordinates(~,info)
            x = info.Position(1);
            y = info.Position(2);
            txt = sprintf("(%s, %s)", num2str(x), num2str(y));
        end

    end

    % ======================================================================
    %  Data tip helpers
    % ======================================================================
    methods (Access = private)

        function setupDataTips(app, lineHandle)
            if isprop(lineHandle,'DataTipTemplate')
                dtRows = lineHandle.DataTipTemplate.DataTipRows;
                if numel(dtRows) >= 2
                    dtRows(1).Label = 'Time (s)';
                    dtRows(2).Label = 'Value';
                end
                lineHandle.DataTipTemplate.DataTipRows = dtRows;
            end
            if isprop(lineHandle,'DataTipCreatedFcn')
                lineHandle.DataTipCreatedFcn = @(~,event) app.datatipCreatedCallback(event);
            end
        end

        function datatipCreatedCallback(app, event)
            pos = event.DataTip.Position;
            t = pos(1);
            if app.row > 0
                [~, idx] = min(abs(app.timeVec(1:app.row) - t));
                app.selectedIdx = unique([app.selectedIdx; idx]);
            end
        end

    end

    % ======================================================================
    %  Callbacks
    % ======================================================================
    methods (Access = private)

        % ---- TAB 1 CALLBACKS ----

        function ConnecttoArduinoButton_2Pushed3(app, ~)
            port = "COM5";
            baud = 115200;

            if app.row > 0
                app.lastDataSet = app.dataSet(1:app.row,:);
                app.lastTimeVec = app.timeVec(1:app.row);
            else
                app.lastDataSet = [];
                app.lastTimeVec = [];
            end

            app.s = serialport(port, baud);
            configureTerminator(app.s,"LF");
            pause(2);
            flush(app.s);

            app.dataSet       = zeros(app.maxRows,3);
            app.timeVec       = zeros(app.maxRows,1);
            app.selectedIdx   = [];
            app.row           = 0;
            app.Leak_RateTime = zeros(app.maxRows,1);
            app.Leak_RateData = zeros(app.maxRows,1);

            cla(app.Temperature); cla(app.Humidity);
            cla(app.CO2);         cla(app.Leak_Rate);

            ORANGE = [0.9216 0.451 0.0784];

            if ~isempty(app.lastDataSet)
                hold(app.Temperature,'on');
                plot(app.Temperature, app.lastTimeVec, app.lastDataSet(:,1), ...
                     'Color',[0.4 0.4 0.4],'LineWidth',1);
                hold(app.Temperature,'off');
                hold(app.Humidity,'on');
                plot(app.Humidity, app.lastTimeVec, app.lastDataSet(:,2), ...
                     'Color',[0.4 0.4 0.4],'LineWidth',1);
                hold(app.Humidity,'off');
                hold(app.CO2,'on');
                plot(app.CO2, app.lastTimeVec, app.lastDataSet(:,3), ...
                     'Color',[0.4 0.4 0.4],'LineWidth',1);
                hold(app.CO2,'off');
            end

            hold(app.Temperature,'on');
            app.tempLine = plot(app.Temperature, NaN, NaN, '-', ...
                                'Color', ORANGE, 'LineWidth', 1.5);
            ylabel(app.Temperature,'Temperature °C');
            hold(app.Temperature,'off');

            hold(app.Humidity,'on');
            app.humLine = plot(app.Humidity, NaN, NaN, '-', ...
                               'Color', ORANGE, 'LineWidth', 1.5);
            ylabel(app.Humidity,'Humidity %');
            hold(app.Humidity,'off');

            hold(app.CO2,'on');
            app.co2Line = plot(app.CO2, NaN, NaN, '-', ...
                               'Color', ORANGE, 'LineWidth', 1.5);
            ylabel(app.CO2,'CO2 PPM');
            xlabel(app.CO2,'Time (s)');
            hold(app.CO2,'off');

            hold(app.Leak_Rate,'on');
            app.Leak_RateLine = plot(app.Leak_Rate, NaN, NaN, '-', ...
                                     'Color', ORANGE, 'LineWidth', 1.5);
            xlabel(app.Leak_Rate,'Time (s)');
            ylabel(app.Leak_Rate,'dC/dt (CO2/s)');
            hold(app.Leak_Rate,'off');

            app.Temperature.Interactions = [dataTipInteraction panInteraction zoomInteraction];
            app.Humidity.Interactions    = [dataTipInteraction panInteraction zoomInteraction];
            app.CO2.Interactions         = [dataTipInteraction panInteraction zoomInteraction];

            setupDataTips(app, app.tempLine);
            setupDataTips(app, app.humLine);
            setupDataTips(app, app.co2Line);

            app.t0 = tic;
            app.timerObj = timer('ExecutionMode','fixedSpacing','Period',0.1, ...
                                 'TimerFcn',@(~,~)readSerial(app));
            start(app.timerObj);
        end

        function ExportDataButtonPushed3(app, ~)
            resultsFolder = 'Results';
            if ~isfolder(resultsFolder); mkdir(resultsFolder); end
            baseName = 'dataSet'; ext = '.csv';
            existingFiles = dir(fullfile(resultsFolder,[baseName,'*.csv']));
            if isempty(existingFiles)
                newFileName = [baseName ext];
            else
                numbers = zeros(length(existingFiles),1);
                for k = 1:length(existingFiles)
                    tok = regexp(existingFiles(k).name,['_(\d+)' ext],'tokens');
                    if ~isempty(tok); numbers(k) = str2double(tok{1}{1}); end
                end
                newFileName = sprintf('%s_%d%s',baseName,max(numbers)+1,ext);
            end
            writetable(array2table(app.dataSet(1:app.row,:), ...
                'VariableNames',{'Temperature','CO2','Humidity'}), ...
                fullfile(resultsFolder,newFileName));
            if ~isempty(app.selectedIdx)
                idx = unique(app.selectedIdx);
                highlighted = [app.timeVec(idx), app.dataSet(idx,:)];
                writetable(array2table(highlighted, ...
                    'VariableNames',{'Time_s','Temperature','CO2','Humidity'}), ...
                    fullfile(resultsFolder,'highlighted_data.csv'));
            end
        end

        function CloseExportButtonPushed3(app, ~)
            if ~isempty(app.timerObj) && isvalid(app.timerObj)
                stop(app.timerObj); delete(app.timerObj);
            end
            if ~isempty(app.s); clear app.s; end
            delete(app.UIFigure);
        end

        function load_old_dataButtonPushed(app, ~)
        end

        % ---- TAB 2 CALLBACKS ----

        function ConnecttoArduinoButton_4Pushed(app, event)
            app.soilS = serialport("COM6", 9600);
            configureTerminator(app.soilS, "LF");
        
            app.soilMaxRows = 2000;
            app.soilDataSet = zeros(app.soilMaxRows,3);  % [Humidity, CO2, Pressure]
            app.soilAltitudeVec = zeros(app.soilMaxRows,1);
            app.soilRow = 0;
        
            % ----- Pressure vs Time -----
            hold(app.UIAxes3,'on')
            app.soilPresLine = animatedline(app.UIAxes3, 'Color',[0 0.447 0.741],'LineWidth',1.5);
            xlabel(app.UIAxes3,'Time (s)')
            ylabel(app.UIAxes3,'Pressure (Pa)')
            title(app.UIAxes3,'Pressure vs Time')
        
            % ----- Altitude vs Time -----
            hold(app.UIAxes,'on')
            app.soilAltLine = animatedline(app.UIAxes, 'Color',[0.85 0.325 0.098],'LineWidth',1.5);
            xlabel(app.UIAxes,'Time (s)')
            ylabel(app.UIAxes,'Altitude (m)')
            title(app.UIAxes,'Altitude vs Time')
        
            % ----- Altitude vs Pressure -----
            hold(app.UIAxes2,'on')
            app.altVsPresLine = animatedline(app.UIAxes, 'Color',[0.466 0.674 0.188],'LineWidth',1.5);
            xlabel(app.UIAxes2,'Pressure (Pa)')
            ylabel(app.UIAxes2,'Altitude (m)')
            title(app.UIAxes2,'Altitude vs Pressure')
        
            % Start the callback for new data
            configureCallback(app.soilS, "terminator", @(~,~)readSoilSerial(app));
        end

        function ExportDataButton_2Pushed(app, ~)

            if app.soilRow == 0; return; end
        
                resultsFolder = 'Results';
            if ~isfolder(resultsFolder); mkdir(resultsFolder); end
        
            baseName = 'soilDataSet';
            ext = '.csv';
        
            existingFiles = dir(fullfile(resultsFolder,[baseName,'*.csv']));
        
            if isempty(existingFiles)
                newFileName = [baseName ext];
            else
                numbers = zeros(length(existingFiles),1);
                for k = 1:length(existingFiles)
                    tok = regexp(existingFiles(k).name,['_(\d+)' ext],'tokens');
                    if ~isempty(tok)
                        numbers(k) = str2double(tok{1}{1});
                    end
                end
                newFileName = sprintf('%s_%d%s',baseName,max(numbers)+1,ext);
            end
        
            validRows = 1:app.soilRow;
        
            T = table( ...
                app.soilDataSet(validRows,1), ...
                app.soilDataSet(validRows,2), ...
                app.soilDataSet(validRows,3), ...
                app.soilAltitudeVec(validRows), ...
                'VariableNames',{'Humidity','CO2','Pressure_Pa','Altitude_m'});
        
            writetable(T, fullfile(resultsFolder,newFileName));
        
        end

        function CloseExportButton_2Pushed(app, ~)
            if ~isempty(app.soilTimerObj) && isvalid(app.soilTimerObj)
                stop(app.soilTimerObj); delete(app.soilTimerObj);
            end
            if ~isempty(app.soilS); clear app.soilS; end
            if ~isempty(app.cam)
                closePreview(app.cam); clear app.cam; app.cam = [];
            end
            delete(app.UIFigure);
        end

        % Camera callbacks
        function ConnectCameraButtonPushed(app, ~)
            try
                app.cam = webcam(1);
                
                % Create an image object inside the axes first
                img = snapshot(app.cam);
                hImage = image(app.CameraAxes, img);
                
                % Now pass the image handle to preview
                preview(app.cam, hImage);
            catch ME
                uialert(app.UIFigure, ME.message, 'Camera Error');
            end
        end

        function DisconnectCameraButtonPushed(app, ~)
            try
                if ~isempty(app.cam)
                    closePreview(app.cam);
                    clear app.cam;
                    app.cam = [];
                end
            catch ME
                uialert(app.UIFigure, ME.message, 'Camera Error');
            end
        end

    end

    % ======================================================================
    %  Component initialization
    % ======================================================================
    methods (Access = private)

        function createComponents(app)

            pathToMLAPP = fileparts(mfilename('fullpath'));

            % Color palette (shared across both tabs)
            BG     = [0.0784 0.0784 0.0784];
            AXBG   = [0.0784 0.0784 0.0784];   % match tab background = "clear"
            ORANGE = [0.9216 0.451  0.0784];
            FG     = [0.749  0.749  0.749 ];

            % ---- Figure ----
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.AutoResizeChildren = 'off';
            app.UIFigure.Position = [100 100 960 540];
            app.UIFigure.Name = 'MRC Life Detection';

            % ---- Tab group ----
            app.TabGroup = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [2 1 960 541];

            % ==============================================================
            %  TAB 1 – REACTION VESSEL
            % ==============================================================
            app.ReactionvesselTab = uitab(app.TabGroup);
            app.ReactionvesselTab.Title = 'Reaction vessel';
            app.ReactionvesselTab.BackgroundColor = BG;
            app.ReactionvesselTab.ForegroundColor = ORANGE;

            % Temperature axes
            app.Temperature = uiaxes(app.ReactionvesselTab);
            title(app.Temperature,'Temperature','Color',ORANGE);
            xlabel(app.Temperature,'Time','Color',FG);
            ylabel(app.Temperature,'Temperature °C','Color',FG);
            app.Temperature.Color  = AXBG;
            app.Temperature.XColor = ORANGE;
            app.Temperature.YColor = ORANGE;
            app.Temperature.XGrid  = 'on'; app.Temperature.YGrid = 'on';
            app.Temperature.Position = [20 249 456 222];

            % CO2 axes
            app.CO2 = uiaxes(app.ReactionvesselTab);
            title(app.CO2,'CO2','Color',ORANGE);
            xlabel(app.CO2,'Time','Color',FG);
            ylabel(app.CO2,'CO2 PPM','Color',FG);
            app.CO2.Color  = AXBG;
            app.CO2.XColor = ORANGE; app.CO2.YColor = ORANGE;
            app.CO2.XGrid  = 'on'; app.CO2.YGrid = 'on';
            app.CO2.Position = [486 249 455 222];

            % Leak Rate axes
            app.Leak_Rate = uiaxes(app.ReactionvesselTab);
            title(app.Leak_Rate,'Leak Rate','Color',ORANGE);
            xlabel(app.Leak_Rate,'Time','Color',FG);
            ylabel(app.Leak_Rate,'Leak Rate','Color',FG);
            app.Leak_Rate.Color  = AXBG;
            app.Leak_Rate.XColor = ORANGE; app.Leak_Rate.YColor = ORANGE;
            app.Leak_Rate.XGrid  = 'on'; app.Leak_Rate.YGrid = 'on';
            app.Leak_Rate.Position = [20 29 456 222];

            % Humidity axes
            app.Humidity = uiaxes(app.ReactionvesselTab);
            title(app.Humidity,'Humidity','Color',ORANGE);
            xlabel(app.Humidity,'Time','Color',FG);
            ylabel(app.Humidity,'Humidity %','Color',FG);
            app.Humidity.Color  = AXBG;
            app.Humidity.XColor = ORANGE; app.Humidity.YColor = ORANGE;
            app.Humidity.Position = [486 94 257 157];

            % Title label
            app.ReactionVesselCreationPanelLabel = uilabel(app.ReactionvesselTab);
            app.ReactionVesselCreationPanelLabel.FontSize  = 24;
            app.ReactionVesselCreationPanelLabel.FontColor = FG;
            app.ReactionVesselCreationPanelLabel.BackgroundColor = BG;
            app.ReactionVesselCreationPanelLabel.Position  = [20 482 344 32];
            app.ReactionVesselCreationPanelLabel.Text = 'Reaction Vessel Creation Panel';

            % Other Temperatures label
            app.OtherTemperaturesLabel = uilabel(app.ReactionvesselTab);
            app.OtherTemperaturesLabel.FontSize  = 14;
            app.OtherTemperaturesLabel.FontColor = FG;
            app.OtherTemperaturesLabel.BackgroundColor = BG;
            app.OtherTemperaturesLabel.Position  = [486 59 174 36];
            app.OtherTemperaturesLabel.Text = 'Other Temperatures';

            % ListBox
            app.ListBox = uilistbox(app.ReactionvesselTab);
            app.ListBox.Items = {'Thermoresistor','Heating element'};
            app.ListBox.Multiselect = 'on';
            app.ListBox.FontColor   = FG;
            app.ListBox.BackgroundColor = [0.12 0.12 0.12];
            app.ListBox.Position    = [486 13 174 47];
            app.ListBox.Value       = {'Thermoresistor'};

            % Buttons Tab 1
            app.CloseExportButton = uibutton(app.ReactionvesselTab,'push');
            app.CloseExportButton.ButtonPushedFcn = createCallbackFcn(app,@CloseExportButtonPushed3,true);
            app.CloseExportButton.BackgroundColor = AXBG;
            app.CloseExportButton.FontSize  = 14;
            app.CloseExportButton.FontColor = FG;
            app.CloseExportButton.Position  = [803 35 135 32];
            app.CloseExportButton.Text = 'Close & Export';

            app.ExportDataButton = uibutton(app.ReactionvesselTab,'push');
            app.ExportDataButton.ButtonPushedFcn = createCallbackFcn(app,@ExportDataButtonPushed3,true);
            app.ExportDataButton.BackgroundColor = AXBG;
            app.ExportDataButton.FontSize  = 14;
            app.ExportDataButton.FontColor = FG;
            app.ExportDataButton.Position  = [802 71 137 32];
            app.ExportDataButton.Text = 'Export Data';

            app.ConnecttoArduinoButton_2 = uibutton(app.ReactionvesselTab,'push');
            app.ConnecttoArduinoButton_2.ButtonPushedFcn = createCallbackFcn(app,@ConnecttoArduinoButton_2Pushed3,true);
            app.ConnecttoArduinoButton_2.BackgroundColor = ORANGE;
            app.ConnecttoArduinoButton_2.FontSize  = 14;
            app.ConnecttoArduinoButton_2.FontColor = [1 1 1];
            app.ConnecttoArduinoButton_2.Position  = [802 108 137 32];
            app.ConnecttoArduinoButton_2.Text = 'Connect to Arduino';

            app.load_old_data = uibutton(app.ReactionvesselTab,'push');
            app.load_old_data.ButtonPushedFcn = createCallbackFcn(app,@load_old_dataButtonPushed,true);
            app.load_old_data.BackgroundColor = AXBG;
            app.load_old_data.FontSize  = 14;
            app.load_old_data.FontColor = FG;
            app.load_old_data.Position  = [802 145 138 32];
            app.load_old_data.Text = 'Load Previous Data';

            % Solenoid controls
            app.SolinoidValveSequenceLabel = uilabel(app.ReactionvesselTab);
            app.SolinoidValveSequenceLabel.FontSize  = 14;
            app.SolinoidValveSequenceLabel.FontColor = FG;
            app.SolinoidValveSequenceLabel.BackgroundColor = BG;
            app.SolinoidValveSequenceLabel.Position  = [780 218 159 22];
            app.SolinoidValveSequenceLabel.Text = 'Solinoid Valve Sequence';

            app.SequenceDropDownLabel = uilabel(app.ReactionvesselTab);
            app.SequenceDropDownLabel.HorizontalAlignment = 'right';
            app.SequenceDropDownLabel.FontColor = FG;
            app.SequenceDropDownLabel.BackgroundColor = BG;
            app.SequenceDropDownLabel.Position  = [764 186 59 22];
            app.SequenceDropDownLabel.Text = 'Sequence';

            app.SequenceDropDown = uidropdown(app.ReactionvesselTab);
            app.SequenceDropDown.Position = [838 186 100 22];

            % MRC Logo
            app.Image = uiimage(app.ReactionvesselTab);
            app.Image.Position = [752 420 187 154];
            app.Image.ImageSource = fullfile(pathToMLAPP,'image.png');

            % ==============================================================
            %  TAB 2 – SOIL ANALYSIS
            % ==============================================================
            app.SoilAnalysisTab = uitab(app.TabGroup);
            app.SoilAnalysisTab.Title = 'Soil Analysis';
            app.SoilAnalysisTab.BackgroundColor = BG;
            app.SoilAnalysisTab.ForegroundColor = ORANGE;

            % MRC Logo (soil tab — same image as reaction vessel tab)
            SoilLogo = uiimage(app.SoilAnalysisTab);
            SoilLogo.Position    = [752 420 187 154];
            SoilLogo.ImageSource = fullfile(pathToMLAPP,'image.png');


            % Title
            app.SoilAnalysisPanelLabel = uilabel(app.SoilAnalysisTab);
            app.SoilAnalysisPanelLabel.FontSize  = 24;
            app.SoilAnalysisPanelLabel.FontColor = FG;
            app.SoilAnalysisPanelLabel.BackgroundColor = BG;
            app.SoilAnalysisPanelLabel.Position  = [19 481 280 32];
            app.SoilAnalysisPanelLabel.Text = 'Soil Analysis Panel';

            % --- Camera axes (top left) ---
            app.CameraAxes = uiaxes(app.SoilAnalysisTab);
            title(app.CameraAxes,'Camera Feed','Color',ORANGE);
            app.CameraAxes.Color  = AXBG;
            app.CameraAxes.XColor = ORANGE;
            app.CameraAxes.YColor = ORANGE;
            app.CameraAxes.XTick  = [];
            app.CameraAxes.YTick  = [];
            app.CameraAxes.Position = [19 230 400 200];

            % Connect camera button
            app.ConnectCameraButton = uibutton(app.SoilAnalysisTab,'push');
            app.ConnectCameraButton.ButtonPushedFcn = createCallbackFcn(app,@ConnectCameraButtonPushed,true);
            app.ConnectCameraButton.BackgroundColor = ORANGE;
            app.ConnectCameraButton.FontSize  = 13;
            app.ConnectCameraButton.FontColor = [1 1 1];
            app.ConnectCameraButton.Position  = [19 228 150 32];
            app.ConnectCameraButton.Text = 'Connect Camera';

            % Disconnect camera button
            app.DisconnectCameraButton = uibutton(app.SoilAnalysisTab,'push');
            app.DisconnectCameraButton.ButtonPushedFcn = createCallbackFcn(app,@DisconnectCameraButtonPushed,true);
            app.DisconnectCameraButton.BackgroundColor = AXBG;
            app.DisconnectCameraButton.FontSize  = 13;
            app.DisconnectCameraButton.FontColor = FG;
            app.DisconnectCameraButton.Position  = [210 228 150 32];
            app.DisconnectCameraButton.Text = 'Disconnect Camera';

            % --- Pressure axes ---
            app.UIAxes3 = uiaxes(app.SoilAnalysisTab);
            title(app.UIAxes3, 'Pressure','Color',ORANGE);
            xlabel(app.UIAxes3,'Time (s)','Color',FG);
            ylabel(app.UIAxes3,'Barimetric Pressure','Color',FG);
            app.UIAxes3.Color  = AXBG;
            app.UIAxes3.XColor = ORANGE; app.UIAxes3.YColor = ORANGE;
            app.UIAxes3.XGrid  = 'on'; app.UIAxes3.YGrid = 'on';
            app.UIAxes3.Position = [19 23 300 185];

            % --- CO2 axes ---
            app.UIAxes2 = uiaxes(app.SoilAnalysisTab);
            title(app.UIAxes2,'CO2','Color',ORANGE);
            xlabel(app.UIAxes2,'Time (s)','Color',FG);
            ylabel(app.UIAxes2,'CO2 PPM','Color',FG);
            app.UIAxes2.Color  = AXBG;
            app.UIAxes2.XColor = ORANGE; app.UIAxes2.YColor = ORANGE;
            app.UIAxes2.XGrid  = 'on'; app.UIAxes2.YGrid = 'on';
            app.UIAxes2.Position = [331 23 300 185];

            % --- Altitude axes ---
            app.UIAxes = uiaxes(app.SoilAnalysisTab);
            title(app.UIAxes,'Altitude Estimate','Color',ORANGE);
            xlabel(app.UIAxes,'Pressure','Color',FG);
            ylabel(app.UIAxes,'Altitude (m)','Color',FG);
            app.UIAxes.Color  = AXBG;
            app.UIAxes.XColor = ORANGE; app.UIAxes.YColor = ORANGE;
            app.UIAxes.XGrid  = 'on'; app.UIAxes.YGrid = 'on';
            app.UIAxes.Position = [644 23 300 185];

            % --- Rate of Change axes ---
            app.UIAxes4 = uiaxes(app.SoilAnalysisTab);
            title(app.UIAxes4,'CO2 Rate of Change','Color',ORANGE);
            xlabel(app.UIAxes4,'Time (s)','Color',FG);
            ylabel(app.UIAxes4,'dCO2/dt','Color',FG);
            app.UIAxes4.Color  = AXBG;
            app.UIAxes4.XColor = ORANGE; app.UIAxes4.YColor = ORANGE;
            app.UIAxes4.XGrid  = 'on'; app.UIAxes4.YGrid = 'on';
            app.UIAxes4.Position = [420 265 360 210];

            % --- Avg CO2 label ---
            app.AvgCO2PPMLabel = uilabel(app.SoilAnalysisTab);
            app.AvgCO2PPMLabel.FontSize   = 16;
            app.AvgCO2PPMLabel.FontColor  = ORANGE;
            app.AvgCO2PPMLabel.BackgroundColor = BG;
            app.AvgCO2PPMLabel.Position   = [800 430 150 31];
            app.AvgCO2PPMLabel.Text = 'Avg CO2:  -- PPM';

            % --- Peak CO2 label ---
            app.PeakCO2PPMLabel = uilabel(app.SoilAnalysisTab);
            app.PeakCO2PPMLabel.FontSize   = 16;
            app.PeakCO2PPMLabel.FontColor  = ORANGE;
            app.PeakCO2PPMLabel.BackgroundColor = BG;
            app.PeakCO2PPMLabel.Position   = [800 390 150 31];
            app.PeakCO2PPMLabel.Text = 'Peak CO2: -- PPM';

            % --- Tab 2 Buttons ---
            app.ConnecttoArduinoButton_4 = uibutton(app.SoilAnalysisTab,'push');
            app.ConnecttoArduinoButton_4.ButtonPushedFcn = createCallbackFcn(app,@ConnecttoArduinoButton_4Pushed,true);
            app.ConnecttoArduinoButton_4.BackgroundColor = ORANGE;
            app.ConnecttoArduinoButton_4.FontSize  = 14;
            app.ConnecttoArduinoButton_4.FontColor = [1 1 1];
            app.ConnecttoArduinoButton_4.Position  = [800 350 145 32];
            app.ConnecttoArduinoButton_4.Text = 'Connect to Arduino';

            app.ExportDataButton_2 = uibutton(app.SoilAnalysisTab,'push');
            app.ExportDataButton_2.ButtonPushedFcn = createCallbackFcn(app,@ExportDataButton_2Pushed,true);
            app.ExportDataButton_2.BackgroundColor = AXBG;
            app.ExportDataButton_2.FontSize  = 14;
            app.ExportDataButton_2.FontColor = FG;
            app.ExportDataButton_2.Position  = [800 310 145 32];
            app.ExportDataButton_2.Text = 'Export Data';

            app.CloseExportButton_2 = uibutton(app.SoilAnalysisTab,'push');
            app.CloseExportButton_2.ButtonPushedFcn = createCallbackFcn(app,@CloseExportButton_2Pushed,true);
            app.CloseExportButton_2.BackgroundColor = AXBG;
            app.CloseExportButton_2.FontSize  = 14;
            app.CloseExportButton_2.FontColor = FG;
            app.CloseExportButton_2.Position  = [800 270 145 32];
            app.CloseExportButton_2.Text = 'Close & Export';

            app.UIFigure.Visible = 'on';
        end
    end

    % ======================================================================
    %  App creation and deletion
    % ======================================================================
    methods (Access = public)

        function app = finalLDAppCode
            createComponents(app)
            registerApp(app, app.UIFigure)
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            if ~isempty(app.timerObj) && isvalid(app.timerObj)
                stop(app.timerObj); delete(app.timerObj);
            end
            if ~isempty(app.soilTimerObj) && isvalid(app.soilTimerObj)
                stop(app.soilTimerObj); delete(app.soilTimerObj);
            end
            if ~isempty(app.cam)
                closePreview(app.cam); clear app.cam;
            end
            delete(app.UIFigure)
        end
    end
end
