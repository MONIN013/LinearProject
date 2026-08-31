function capacity = tunable_trajectory_buffer_capacity
%TUNABLE_TRAJECTORY_BUFFER_CAPACITY Fixed target buffer for reference and FF.
% The fixed dimension lets External Mode replace trajectories without
% regenerating code. At the current 125 us sample time this stores 16.384 s.
capacity = 131072;
end
