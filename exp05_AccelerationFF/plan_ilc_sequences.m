function plan = plan_ilc_sequences()
%PLAN_ILC_SEQUENCES Sequence-level plan; each row requires repeated real trials.
% This function is offline only. It does not call Simulink, ADS, Homing, or servo.
% Training profiles produce ILC teachers. Held-out profiles compare the SAME
% frozen ILC law from zero / thesis / proposed initial FF.

trainProfiles=["train01";"train02";"train03";"train04";"train05";"train06"];
validationProfiles=["validation01";"validation02"];
testProfiles=["test01";"test02"];
plan=table('Size',[0,6],'VariableTypes', ...
    {'string','string','string','string','double','double'}, ...
    'VariableNames',{'sequence_id','profile_id','split','role','max_iterations','initialization'});
for p=1:numel(trainProfiles)
    id="teacher_"+trainProfiles(p);
    plan=[plan;{id,trainProfiles(p),"train","teacher",15,"zero"}]; %#ok<AGROW>
end
for splitName=["validation","test"]
    profiles=validationProfiles;
    if splitName=="test", profiles=testProfiles; end
    for p=1:numel(profiles)
        for init=["zero","thesis","acceleration"]
            id="convergence_"+profiles(p)+"_from_"+init;
            plan=[plan;{id,profiles(p),splitName,"convergence",8,init}]; %#ok<AGROW>
        end
    end
end
end
