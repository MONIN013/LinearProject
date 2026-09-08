function projectRoot = setup_project()
%SETUP_PROJECT Add the project's shared MATLAB functions.
% Does not connect to hardware, build, activate, or enable a servo.
projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot, fullfile(projectRoot,'src'));
end
