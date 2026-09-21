function archive_experiment_intermediates(files)
%ARCHIVE_EXPERIMENT_INTERMEDIATES Retain originals locally, outside shared data.
root = fileparts(fileparts(mfilename('fullpath')));
dataRoot = [char(java.io.File(fullfile(root,'data')).getCanonicalPath()) filesep];
archiveRoot = fullfile(root,'.codex-temp','data-originals');
for k = 1:numel(files)
    source = char(java.io.File(char(files(k))).getCanonicalPath());
    if ~isfile(source), continue; end
    assert(startsWith(source,dataRoot,'IgnoreCase',ispc), ...
        'NikonMotor:ArchiveOutsideData','Only experiment data may be archived.');
    destination = fullfile(archiveRoot,source(numel(dataRoot)+1:end));
    assert(~isfile(destination),'NikonMotor:ArchiveExists', ...
        'An original already exists at %s; retain the new file for inspection.',destination);
    if ~isfolder(fileparts(destination)), mkdir(fileparts(destination)); end
    % Windows can briefly lock a MAT after the readback verification.
    for attempt = 1:5
        [ok,message] = movefile(source,destination);
        if ok, break; end
        if ~ispc || attempt==5
            error('NikonMotor:ArchiveFailed','%s',message);
        end
        pause(0.1*attempt);
    end
end
end
