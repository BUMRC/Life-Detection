port = "/dev/cu.usbmodem101"; % change every time
baud = 115200; %also adjust
s = serialport(port, baud);
configureTerminator(s,"LF");
pause(2);
flush(s);

%Dataset preallocation
maxRows = 5000;            % pick an upper bound
initialDataSet = zeros(maxRows, 3);
row = 0;

disp('Starting continuous read... Press q in the figure to stop.');
%%Plot setup
stopScript = false;
f = figure("Name", "Live Data");
t = tiledlayout(3,1);
title(t, 'Live Data from Arduino')
ax1 = nexttile; a1 = animatedline(ax1,'Color','b'); ylabel(ax1,'Temperature °C'); ylim(ax1,[20 30]);
ax2 = nexttile; a2 = animatedline(ax2,'Color','r'); ylabel(ax2,'CO2 PPM'); ylim(ax2,[300 6000]);
ax3 = nexttile; a3 = animatedline(ax3,'Color','g'); ylabel(ax3,'Humidity %'); ylim(ax3,[0 100]); xlabel(ax3,'Time (s)');

t0 = tic;
%Auto adjust
ax1.YLimMode = 'auto';  % automatically adjust Y-axis as new points come in
ax2.YLimMode = 'auto';
ax3.YLimMode = 'auto';

ax1.XLimMode = 'auto';  
ax2.XLimMode = 'auto';
ax3.XLimMode = 'auto';

set(f,'KeyPressFcn', @(~,event) assignin('base','stopScript',true));

while ~evalin('base','stopScript')
    try
        % Read a line from Arduino
        line = readline(s);
        data = str2double(split(line, ","));
        val1 = data(1);
        val2 = data(2);
        val3 = data(3);
        fprintf('%g ', data);
        fprintf('\n');
        
        %data storage
        row = row + 1;
        initialDataSet(row, :) = [val1, val2, val3];
        %plotting
        tNow = toc(t0);
        addpoints(a1, tNow, data(1));
        addpoints(a2, tNow, data(3));
        addpoints(a3, tNow, data(2));
        drawnow limitrate;

    catch ME
        % Catch errors so loop doesn't crash
        warning('Error reading data: %s', ME.message);
    end
end

dataSet = initialDataSet(1:row,:);


%% Cleanup
clear s   % free serial port
disp('Script stopped sucessfully.');

%% Define folder path

% Folder where files will be saved
resultsFolder = '../Results';

% Make sure folder exists
if ~isfolder(resultsFolder)
    mkdir(resultsFolder);
end

% Base file name
baseName = 'dataSet';
ext = '.csv';

% Find existing files
existingFiles = dir(fullfile(resultsFolder, [baseName, '*.csv']));

% Determine next number
if isempty(existingFiles)
    newFileName = [baseName, ext];   % first file: dataSet.csv
else
    % Extract numbers from existing files
    numbers = zeros(length(existingFiles),1);
    for k = 1:length(existingFiles)
        fname = existingFiles(k).name;
        % Match _number pattern
        tok = regexp(fname, ['_', '(\d+)', ext], 'tokens');
        if ~isempty(tok)
            numbers(k) = str2double(tok{1}{1});
        else
            numbers(k) = 0;  % plain dataSet.csv counts as 0
        end
    end
    nextNum = max(numbers)+1;
    newFileName = sprintf('%s_%d%s', baseName, nextNum, ext);
end

% Full path
fullFilePath = fullfile(resultsFolder, newFileName);

% Save the table
writetable(array2table(dataSet(1:row,:), ...
    'VariableNames', {'Temperature','Humidity','CO2'}), fullFilePath);

disp(['Data saved to: ', fullFilePath]);


