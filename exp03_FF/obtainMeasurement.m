%% Run one trajectory through the shared tunable capture
runDir = create_run_directory('data/ff', 'feedforward');
measurement = capture_tunable_trajectory(ModelName, r, f, Ts, runDir);
