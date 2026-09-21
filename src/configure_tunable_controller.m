function configure_tunable_controller(model,Kd,Ts)
%CONFIGURE_TUNABLE_CONTROLLER Keep controller order fixed across exp01-06.
path = string(model)+"/LTI System";
values = fixed_feedback_coefficients(Kd,Ts);
workspace = get_param(model,'ModelWorkspace');
for name = string(fieldnames(values))'
    assignin(workspace,name,Simulink.Parameter(values.(name)));
end
if string(get_param(path,'BlockType'))~="DiscreteTransferFcn"
    load_system('simulink');
    replace_block(model,'SearchDepth',1,'Name','LTI System', ...
        'simulink/Discrete/Discrete Transfer Fcn','noprompt');
end
set_param(path,'Numerator','p_fb_num''','Denominator','p_fb_den''', ...
    'SampleTime','Ts','InitialStates','0');
end
