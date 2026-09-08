function projectRoot = copley_project_root()
%COPLEY_PROJECT_ROOT Bootstrap a direct src entry through setup_project.
srcDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(srcDir);
if exist('setup_project', 'file') ~= 2
    addpath(projectRoot);
end
projectRoot = setup_project();
end
