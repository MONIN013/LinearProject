function f = my_save_mat(matFile, varargin)
% MY_SAVE_MAT saves workspace variables with specified file name, date, and incremental numbering.
%
% Usage:
% my_save_mat('feedback_result', 'var1','var2',...) saves specified variables.
% my_save_mat('feedback_result') saves all workspace variables.

% Get current date
currentDate = datestr(now,'yyyy-mm-dd');

% Create folder
folderName = fullfile('data_4k');
if ~exist(folderName, 'dir')
    mkdir(folderName);
end

% Ensure matFile is a character array
matFile = char(matFile);

% Initial filename
baseFilename = fullfile(folderName, [matFile, '_', currentDate, '.mat']);
filename = baseFilename;

% Increment filename if exists
fileCounter = 1;
while exist(filename, 'file')
    filename = fullfile(folderName, [matFile, '_', currentDate, '_', num2str(fileCounter), '.mat']);
    fileCounter = fileCounter + 1;
end

% Convert varargin to character vectors if needed
for i = 1:length(varargin)
    varargin{i} = char(varargin{i});
end

% Save variables using caller workspace
if isempty(varargin)
    evalin('caller', ['save(''', filename, ''')']);
else
    vars = strjoin(strcat('''', varargin, ''''), ',');
    evalin('caller', ['save(''', filename, ''',', vars,')']);
end

fprintf('Saved data to %s\n', filename);
f=filename;
end
