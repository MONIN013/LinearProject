function runDir = create_run_directory(baseDir, tag)
%CREATE_RUN_DIRECTORY Create a dated run below a project-relative or absolute directory.
if nargin < 2, tag = "run"; end
baseDir = char(baseDir);
if isempty(regexp(baseDir, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
    baseDir = fullfile(fileparts(fileparts(mfilename('fullpath'))),baseDir);
end
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
baseName = [stamp '_' char(tag)];
runDir = fullfile(baseDir,baseName);
suffix = 1;
while isfolder(runDir)
    runDir = fullfile(baseDir,sprintf('%s_%d',baseName,suffix));
    suffix = suffix+1;
end
mkdir(runDir);
end
