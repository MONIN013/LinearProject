function tests = test_allocation_transfer
% Offline only: preparation, synthetic identification and the PLC log format.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,fullfile(root,'src'));
end

function testPreparationFromLiveEditorCopy(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
source = fileread(fullfile(root,'exp06_AllocationTransfer','allocation_transfer_experiment.m'));
stop = strfind(source,'%[text] ## 3. Collect');
assertEqual(testCase,numel(stop),1);
folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
scriptPath = fullfile(folder.Folder,'allocation_startup.m');
fid = fopen(scriptPath,'w'); fprintf(fid,'%s',source(1:stop-1)); fclose(fid);
% config_tunable writes these existing files even during offline preparation.
paths = {fullfile(root,'config','data','config_tunable.mat'), ...
    fullfile(root,'simulink','linear_exp_tunable_2025a.slx')};
backups = {fullfile(folder.Folder,'config.mat'),fullfile(folder.Folder,'model.slx')};
for k = 1:2, copyfile(paths{k},backups{k}); end
guard = onCleanup(@()restore_files(paths,backups));
actual = run_preparation(scriptPath);
verifyEqual(testCase,actual.root,root);
verifyEqual(testCase,actual.Ts,1/4000);
verifyLessThan(testCase,actual.sensitivityPeak,2);
verifyEqual(testCase,actual.sampleCount,48001);
verifyEqual(testCase,actual.endCount,56700000);
verifyEqual(testCase,actual.Fc,420);
verifyEqual(testCase,actual.splits,[9,3,3]);
end

function actual = run_preparation(scriptPath)
run(scriptPath);
actual = struct('root',projectRoot,'Ts',Ts,'sensitivityPeak',sensitivityPeak, ...
    'sampleCount',max(cellfun(@(p)numel(p.pos),profiles)), ...
    'endCount',endCount,'Fc',Fc, ...
    'splits',[sum(plan.split=="train"),sum(plan.split=="validation"),sum(plan.split=="test")]);
close all;
end

function restore_files(paths,backups)
for k = 1:numel(paths), copyfile(backups{k},paths{k}); end
end

function testWeightsPreserveNominalForce(testCase)
g = [1.5,1];
w = allocation_weights(.1,g(1)/g(2));
verifyEqual(testCase,g*w',sum(g),'AbsTol',1e-12);
verifyError(testCase,@()allocation_weights(.2,2),'NikonMotor:AllocationWeights');
verifyEqual(testCase,allocation_weights(0,1),[1,1]);
end

function testProfilesIdentifyAndTransferKnownCoefficients(testCase)
plan = make_allocation_plan(); Ts = 1/4000; origin = 5.61;
xGrid = origin+(.0005:.0005:.0595)';
betas = [-.1,0,.1]; maps = cell(1,3);
base = [.03,1.2,.025,.08]; slope = [.02,.3,.01,.2];
for b = 1:numel(betas)
    cases = find(plan.split=="train" & plan.beta==betas(b));
    training = cell(numel(cases),1);
    for k = 1:numel(cases)
        c = cases(k);
        traj = generate_allocation_profile(.06,plan.duration(c),plan.skew(c),Ts);
        verifyEqual(testCase,[traj.pos(1),traj.pos(end),max(traj.pos)],[0,0,.06],'AbsTol',1e-12);
        verifyLessThan(testCase,max(abs(gradient(traj.pos,Ts)-traj.vel)),1e-6);
        ff = [ones(size(traj.pos)),traj.vel,sign(traj.vel),traj.acc]*(base+betas(b)*slope)';
        training{k} = struct('passed',true,'method',"ilc_teacher",'profileIndex',k, ...
            'teacher',struct('converged',true,'currentKind',"ilc_ff_A"),'Ts',Ts, ...
            'y_absolute_ex',origin+traj.pos,'r_ex',traj.pos,'ff_ex',ff, ...
            'count_ex',(1:numel(ff))');
    end
    maps{b} = fit_acceleration_ff(training,xGrid,81,0);
    verifyTrue(testCase,all(maps{b}.valid));
    verifyLessThan(testCase,max(abs(maps{b}.coefficients-(base+betas(b)*slope)),[],'all'),1e-3);
end
for beta = [-.05,.05]
    map = interpolate_allocation_map(maps,betas,beta);
    verifyLessThan(testCase,max(abs(map.coefficients-(base+beta*slope)),[],'all'),1e-3);
    traj = generate_allocation_profile(.06,2.7,1,Ts);
    f = acceleration_feedforward(map,traj,origin,zeros(size(traj.pos)),1,.0005);
    verifyTrue(testCase,all(isfinite(f)));
    verifyEqual(testCase,f(abs(traj.vel)<=.002),zeros(nnz(abs(traj.vel)<=.002),1));
end
broken = maps; broken{2}.valid(50) = false;
verifyError(testCase,@()interpolate_allocation_map(broken,betas,.05),'NikonMotor:InvalidAllocationMap');
end
