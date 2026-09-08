function [paths, runDir] = archive_measurement_parts(dataDir, runDir, rawSubdir)
%ARCHIVE_MEASUREMENT_PARTS Preserve completed File Writer parts after drive cleanup.
% Omitted runDir retains unassigned parts in data/archive. Never overwrites raw data.
if nargin < 2, runDir = ''; end
if nargin < 3, rawSubdir = 'raw'; end
parts = dir(fullfile(dataDir,'measurement_*.mat'));
paths = strings(numel(parts),1);
if isempty(parts), return; end
if isempty(runDir)
    runDir = create_run_directory('data/archive','unassigned_measurement');
end
rawDir = fullfile(runDir,rawSubdir);
if ~isfolder(rawDir), mkdir(rawDir); end
for k = 1:numel(parts)
    paths(k) = string(fullfile(rawDir,parts(k).name));
    assert(~isfile(paths(k)),'NikonMotor:RawFileExists', ...
        'A raw capture already exists: %s',paths(k));
end
for k = 1:numel(parts)
    [ok,message] = movefile(fullfile(parts(k).folder,parts(k).name),paths(k));
    assert(ok,'NikonMotor:RawArchiveFailed','Could not archive measurement: %s',message);
end
end
