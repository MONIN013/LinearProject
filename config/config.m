clear; close all;
configDir = fileparts(mfilename("fullpath"));
projectRoot = fileparts(configDir);
%% default control config
run(fullfile(configDir, "sample_rate.m"));
Tend = 1;
N=round(Tend/Ts);
t=Ts*(0:N-1);
Kd=tf(0);
feedbackFlag = 0; % 0: openLoop 1: closedLoop

%% plot options
bop = bodeoptions("cstprefs");
bop.FreqUnits = 'Hz';
bop.PhaseWrapping = 'on';
bop.XLimMode = 'manual';
bop.XLim = {[1,1/8/Ts]};
nop = nyquistoptions("cstprefs");
nop.ShowFullContour = 'off';
nop.Xlim = [-1.5 1];
nop.Ylim = [-1.5 1];
%% simulink info config
ModelName = "simulink/linear_exp_2025a.slx";
load_system(fullfile(projectRoot, ModelName))
[~, model] = fileparts(ModelName);
model = string(model);
BlockPaths = find_system(model);
Index_active = find(contains(BlockPaths,'active'));
if length(Index_active) > 1
    warning("There appear to be duplicate 'active' blocks in your model. Please remove all duplicate blocks.");
    Index_active = Index_active(1);
end
Index_servo = find(contains(BlockPaths,'servo switch'));
if length(Index_servo) > 1
    warning("There appear to be duplicate 'servo switch' blocks in your model. Please remove all duplicate blocks.");
    Index_servo = Index_servo(1);
end
close_system(model);

set_ff = zeros(N,1);
set_ref = zeros(N,1);
%% matlab color
matlab_blue = [0.00000,0.44700,0.74100];
matlab_red = [0.85000,0.32500,0.09800];
matlab_orange = [0.92900,0.69400,0.12500];
matlab_purple = [0.49400,0.18400,0.55600];
matlab_green = [0.46600,0.67400,0.18800];
matlab_cyan = [0.3010 0.7450 0.9330];
matlab_brown = [0.6350 0.0780 0.1840];
%% cud color
cud_red = [1 0.294 0];
cud_yellow = [1 0.945 0];
cud_green = [0.012 0.686 0.478];
cud_blue = [0 0.353 1];
cud_sky = [0.302 0.769 1];
cud_pink = [1 0.502 0.510];
cud_orange = [0.965 0.667 0];
cud_purple = [0.6 0 0.6];
cud_brown = [0.502 0.251 0];
cud_color_order = [cud_blue; cud_red; cud_orange;...
    cud_purple; cud_green; cud_brown;...
    cud_sky; cud_pink; cud_yellow];
%% save config
save(fullfile(configDir, "data", "config.mat"));
