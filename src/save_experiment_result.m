function matPath = save_experiment_result(runDir, name, values)
%SAVE_EXPERIMENT_RESULT Save explicit variables, preserving their MAT-file names.
if ~isfolder(runDir), mkdir(runDir); end
matPath = fullfile(runDir,[char(name) '.mat']);
save(matPath,'-struct','values');
fprintf('Saved data to %s\n',matPath);
end
