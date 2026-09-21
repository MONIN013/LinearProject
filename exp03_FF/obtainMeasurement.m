%% Run one trajectory through the shared tunable capture
runDir = create_run_directory('data/ff', 'feedforward');
pre = read_tunable_idle_state(Ts);
[measurement,~,measurement_metadata] = capture_tunable_trajectory(ModelName,r,f,Ts,runDir);
post = read_tunable_idle_state(Ts);
