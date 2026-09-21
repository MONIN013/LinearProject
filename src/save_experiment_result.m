function matPath = save_experiment_result(runDir, name, values)
%SAVE_EXPERIMENT_RESULT Save explicit variables, preserving their MAT-file names.
if ~isfolder(runDir), mkdir(runDir); end
matPath = fullfile(runDir,[char(name) '.mat']);
temporary = [tempname(runDir) '.mat'];
guard = onCleanup(@()remove_temporary(temporary));
save(temporary,'-struct','values');
movefile(temporary,matPath,'f');
fprintf('Saved data to %s\n',matPath);
end

function remove_temporary(path)
if isfile(path), delete(path); end
end
