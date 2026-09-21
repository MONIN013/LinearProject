function capacity = tunable_trajectory_buffer_capacity
%TUNABLE_TRAJECTORY_BUFFER_CAPACITY Fixed target buffer for reference and FF.
% One buffer covers the 100 s SI excitation at either 4 or 8 kHz.
% External Mode replaces trajectories without regenerating code.
capacity = 800001;
end
