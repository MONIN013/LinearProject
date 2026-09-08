function summary = compare_cases(results)
%COMPARE_CASES Pair accepted methods on identical held-out references.
% Input: cell array of explicit saved result structs, never a 'latest' search.
% No failed/saturated cases are silently dropped. Missing methods are errors.
% Ratios <1 indicate lower RMS than frozen thesis FF; not a significance test.
assert(iscell(results) && ~isempty(results),'accelff:Results','Pass explicit result structs.');
ids=strings(numel(results),1); profiles=ids; methods=ids;
repeat=zeros(numel(results),1); moving=repeat; accelerated=repeat; peak=repeat;
for k=1:numel(results)
    r=results{k};
    assert(string(r.status)=="accepted" && r.metrics.saturated_samples==0 && ...
        string(r.job.split)~="train",'accelff:InvalidComparison', ...
        'Every case must be accepted, unsaturated, and outside training.');
    ids(k)=r.job.id; profiles(k)=r.job.profile_id; methods(k)=r.job.method;
    repeat(k)=r.job.repeat; moving(k)=r.metrics.rms_moving_m;
    accelerated(k)=r.metrics.rms_accelerating_m; peak(k)=r.metrics.peak_m;
end
assert(numel(unique(ids))==numel(ids),'accelff:Duplicate','Repeated case ID.');
summary=table(ids,profiles,repeat,methods,moving,accelerated,peak, ...
    nan(size(moving)),nan(size(moving)), 'VariableNames', ...
    {'id','profile_id','repeat','method','rms_moving_m','rms_accelerating_m','peak_m', ...
     'moving_ratio_to_thesis','acceleration_ratio_to_thesis'});
groups=findgroups(profiles,repeat);
for g=unique(groups)'
    ix=find(groups==g);
    assert(numel(ix)==3 && isequal(sort(methods(ix)),sort(["fb";"thesis";"acceleration"])), ...
        'accelff:MissingMethod','Each profile/repeat requires exactly three methods.');
    base=results{ix(1)};
    for k=ix'
        r=results{k};
        assert(isequal(r.job.r,base.job.r) && r.job.Ts==base.job.Ts && ...
            r.job.origin_m==base.job.origin_m && string(r.job.split)==string(base.job.split) && ...
            isequaln(r.config.approved_Kd,base.config.approved_Kd) && ...
            r.config.current_limit_A==base.config.current_limit_A && ...
            r.config.evaluation_velocity_floor==base.config.evaluation_velocity_floor && ...
            r.config.evaluation_acceleration_threshold==base.config.evaluation_acceleration_threshold, ...
            'accelff:ComparisonMismatch','Reference, origin, controller, limit, split, or masks differ.');
    end
    thesis=ix(methods(ix)=="thesis");
    if moving(thesis)>0
        summary.moving_ratio_to_thesis(ix)=moving(ix)/moving(thesis);
    end
    if accelerated(thesis)>0
        summary.acceleration_ratio_to_thesis(ix)=accelerated(ix)/accelerated(thesis);
    end
end
end
