function matPath = finalize_experiment_result(runDir, name, values, rawSubdir, checkpoints)
%FINALIZE_EXPERIMENT_RESULT Keep one result MAT, with captures and axis records.
% Intermediate files remain recoverable in the ignored .codex-temp directory.
if nargin < 4, rawSubdir = 'raw'; end
if nargin < 5, checkpoints = strings(0,1); end
rawDir = fullfile(runDir,rawSubdir);
parts = dir(fullfile(rawDir,'**','measurement_*.mat'));
captures = cell(numel(parts),1);
for k = 1:numel(parts)
    source = fullfile(parts(k).folder,parts(k).name);
    raw = load(source,'tc_yout');
    capture = struct('source',string(source),'time',horzcat(raw.tc_yout.time), ...
        'data',horzcat(raw.tc_yout.data),'rows',[],'trial',[], ...
        'fields',{cell(10,1)},'axisSource','');
    capture.rows = 1:size(capture.data,1);
    trial = regexp(parts(k).folder,'[\\/]trial_(\d+)$','tokens','once');
    % ILC already owns these seven measured channels. Store only the other
    % channels here, retaining original row numbers for offline reconstruction.
    if isfield(values,'history') && ~isempty(trial)
        n = str2double(trial{1});
        rows = [1 2 3 5 7 8 9];
        fields = {'count','e','u','y','ff','y_absolute','r'};
        matches = size(capture.data,1)>=10;
        for j = 1:numel(fields)
            matches = matches && isfield(values.history,fields{j}) && ...
                size(values.history.(fields{j}),2)>=n && ...
                isequaln(capture.data(rows(j),:)',values.history.(fields{j})(:,n));
        end
        if matches
            capture.trial = n;
            capture.fields(rows) = strcat('history.',fields);
            capture.rows(rows) = [];
            capture.data(rows,:) = [];
        end
    end
    names = fieldnames(values);
    if ~isempty(capture.trial), names = {}; end
    for row = intersect(capture.rows,1:10)
        rowIndex = find(capture.rows==row);
        for j = 1:numel(names)
            v = values.(names{j});
            if isnumeric(v) && isvector(v) && isequaln(v(:)',capture.data(rowIndex,:))
                capture.fields{row} = names{j};
                break
            elseif strcmp(names{j},'measurement') && isnumeric(v) && ...
                    size(v,1)>=row && isequaln(v(row,:),capture.data(rowIndex,:))
                capture.fields{row} = 'measurement';
                break
            end
        end
        if ~isempty(capture.fields{row})
            capture.data(rowIndex,:) = [];
            capture.rows(rowIndex) = [];
        end
    end
    captures{k} = capture;
end
if isfield(values,'history') && isfield(values.history,'captures')
    captures = [values.history.captures(:); captures];
    values.history = rmfield(values.history,'captures');
end
if ~isempty(captures), values.captures = captures; end
% Keep the validated allocation record inside the result, including resumed
% trials whose original captures belong to an earlier run.
if isfield(values,'history') && isfield(values.history,'allocationLogFiles')
    paths = values.history.allocationLogFiles;
    records = cell(size(paths));
    if isfield(values.history,'allocationLog'), records = values.history.allocationLog; end
    for k = 1:numel(paths)
        if ~isempty(paths{k}), records{k} = load(paths{k}); end
    end
    values.history.allocationLog = records;
    values.history = rmfield(values.history,'allocationLogFiles');
elseif isfield(values,'allocationLogFile')
    values.allocationLog = load(values.allocationLogFile);
    values = rmfield(values,'allocationLogFile');
end
% The axis record is authoritative when available. Do not store the same
% twenty channels a second time in the packed capture.
if isfield(values,'captures')
    for k = 1:numel(values.captures)
        capture = values.captures{k};
        previousAxisSource = capture.axisSource;
        axis = [];
        logPath = fullfile(fileparts(capture.source),'allocation_log.mat');
        if isfile(logPath)
            record = load(logPath);
            recorded = (~isempty(capture.trial) && isfield(values.history,'allocationLog') && ...
                numel(values.history.allocationLog)>=capture.trial && ...
                isequaln(record,values.history.allocationLog{capture.trial})) || ...
                (isfield(values,'allocationLog') && isequaln(record,values.allocationLog));
            if ~recorded, capture.allocationLog = record; end
        end
        if ~isempty(capture.trial) && isfield(values.history,'allocationLog')
            record = values.history.allocationLog{capture.trial};
            if isfield(record,'axisLog'), axis = record.axisLog; capture.axisSource = 'history.allocationLog'; end
        elseif isfield(values,'allocationLog') && isfield(values.allocationLog,'axisLog')
            axis = values.allocationLog.axisLog;
            capture.axisSource = 'allocationLog';
        elseif isfield(values,'measurement_metadata') && isfield(values.measurement_metadata,'axisLog')
            axis = values.measurement_metadata.axisLog;
            capture.axisSource = 'measurement_metadata';
        end
        if isfield(capture,'allocationLog') && isfield(capture.allocationLog,'axisLog')
            axis = capture.allocationLog.axisLog;
            capture.axisSource = 'capture.allocationLog';
        end
        axisRows = capture.rows>=11 & capture.rows<=30;
        if sum(axisRows)==20 && ~isempty(axis)
            decoded = decode_axis_snapshot(capture.data(axisRows,:),values.Ts);
            fields = setdiff(fieldnames(decoded),{'time'});
            same = all(cellfun(@(f)isequaln(decoded.(f),axis.(f)),fields));
            if same
                capture.data(axisRows,:) = [];
                capture.rows(axisRows) = [];
            else
                capture.axisSource = '';
            end
        else
            capture.axisSource = previousAxisSource;
        end
        values.captures{k} = capture;
    end
end
logs = dir(fullfile(rawDir,'**','allocation_log.mat'));
for k = 1:numel(logs)
    if any(strcmp({parts.folder},logs(k).folder)), continue; end
    if ~isfield(values,'allocationNotes'), values.allocationNotes = {}; end
    values.allocationNotes{end+1} = load(fullfile(logs(k).folder,logs(k).name));
end
matPath = save_experiment_result(runDir,name,values);
assert(isequaln(load(matPath),values),'NikonMotor:ResultRoundTrip', ...
    'Result MAT could not be verified; intermediate files have been retained.');
files = string(fullfile({parts.folder},{parts.name}));
files = [files(:); string(fullfile({logs.folder},{logs.name}))'; ...
    fullfile(string(runDir),checkpoints(:))];
if isfield(values,'allocationLog'), files(end+1) = fullfile(runDir,'allocation_log.mat'); end
archive_experiment_intermediates(files);
end
