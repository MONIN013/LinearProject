function matPath = save_experiment_result(runDir, name, values)
%SAVE_EXPERIMENT_RESULT Save explicit variables, preserving their MAT-file names.
if ~isfolder(runDir), mkdir(runDir); end
matPath = fullfile(runDir,[char(name) '.mat']);
temporary = [tempname(runDir) '.mat'];
guard = onCleanup(@()remove_temporary(temporary));
save(temporary,'-struct','values');
% Windows may briefly lock a newly saved MAT. Retry only the replacement,
% retaining both the completed temporary file and the previous result.
for attempt = 1:5
    [ok,message,messageId] = movefile(temporary,matPath,'f');
    if ok, break; end
    if ~ispc || attempt==5, error(messageId,'%s',message); end
    pause(0.1*attempt);
end
fprintf('Saved data to %s\n',matPath);
end

function remove_temporary(path)
if isfile(path), delete(path); end
end
