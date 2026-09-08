function [plantPath, currentPath] = save_experiment_plant(runDir, plant, plantsDir)
%SAVE_EXPERIMENT_PLANT Keep identification history before replacing the current plant.
% plantsDir can point to an isolated directory for offline verification.
if nargin < 3
    plantsDir = fullfile(fileparts(fileparts(mfilename('fullpath'))),'data','plants');
end
plantPath = save_experiment_result(runDir,'plant',plant);
rate = round(1/plant.Ts);
assert(ismember(rate,[4000 8000]),'NikonMotor:UnsupportedPlantRate', ...
    'Expected a 4 or 8 kHz experiment plant.');
load_experiment_plant('',plantPath,1/rate);
folder = fullfile(plantsDir,sprintf('%dkhz',rate/1000));
if ~isfolder(folder), mkdir(folder); end
currentPath = fullfile(folder,'current.mat');
temporaryPath = [tempname(folder) '.mat'];
guard = onCleanup(@()remove_temporary(temporaryPath));
copyfile(plantPath,temporaryPath);
movefile(temporaryPath,currentPath,'f');
end

function remove_temporary(path)
if isfile(path), delete(path); end
end
