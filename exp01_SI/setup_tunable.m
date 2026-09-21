%% Build the shared tunable target after preparing the SI settings
% Same fixed trajectory buffer and runtime controller as exp02 through exp06.
projectRoot = setup_project();
assert(string(ModelName)=="simulink/linear_exp_tunable_2025a.slx", ...
    'NikonMotor:UnexpectedModel', 'Load config_tunable before building the SI target.');
run(fullfile(projectRoot, "exp03_FF", "setup_tunable.m"));
