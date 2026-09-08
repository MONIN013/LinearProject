function data = readJsonFile(path)
fid = fopen(path, 'r');
if fid < 0
    error('copley:readJsonFile:OpenFailed', 'Could not open %s.', path);
end
cleanup = onCleanup(@()fclose(fid));
txt = fread(fid, '*char')';
delete(cleanup);
data = jsondecode(txt);
end
