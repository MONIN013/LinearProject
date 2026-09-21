function tests = test_common_tunable_controller
tests = functiontests(localfunctions);
end

function testCurrentControllersHaveTheSameFrequencyResponse(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src'));
for Ts = [1/4000,1/8000]
    [plant,~] = load_experiment_plant(root,sprintf('data/plants/%dkhz/current.mat',1/Ts/1000),Ts);
    fb = fbDesign(plant.Pd,Ts);
    bandwidth = 110;
    if Ts==1/8000, bandwidth = 80; end
    pid = pidtune(plant.Pd,'PIDF',bandwidth,pidtuneOptions('PhaseMargin',60));
    controllers = {tf(.06,1),pid,fb.K};
    for k = 1:numel(controllers)
        values = fixed_feedback_coefficients(controllers{k},Ts);
        actual = tf(values.p_fb_num',values.p_fb_den',Ts);
        w = logspace(0,log10(.8*pi/Ts),100);
        expected = squeeze(freqresp(controllers{k},w));
        observed = squeeze(freqresp(actual,w));
        verifyLessThan(testCase,max(abs(observed-expected)./max(abs(expected),1)),1e-6);
        verifySize(testCase,values.p_fb_num,[3,1]);
        verifySize(testCase,values.p_fb_den,[3,1]);
    end
end
end
