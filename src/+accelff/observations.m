function obs = observations(trials, grid, o)
%OBSERVATIONS Position-aligned measured kinematics and identification current.
% TRAIN data must come from accelff.accept_ilc_teacher: the target is the
% converged learned ILC FF [A], matching the thesis decomposition. It is NOT
% raw feedback-only current and NOT row-3 total command. Validation/test may
% retain command_A for diagnostic prediction but fit_map accepts train only.
% Each element is one validated round trip. Assign profile_id before data
% collection; repeats keep that ID. Identical references cannot cross splits.
% Local cubic differentiation is OFFLINE and noncausal. Edges are discarded.
% Pair mechanical sample k with current(k+offset); negative offset means an
% earlier current. The row-9 logging delay does not belong in this parameter.
validateattributes(grid,{'double'},{'column','finite','increasing'});
validateattributes(o.derivative_window,{'double'}, ...
    {'scalar','integer','>=',5});
assert(mod(o.derivative_window,2)==1,'accelff:Window','Window must be odd.');
validateattributes(o.velocity_floor,{'double'},{'scalar','finite','positive'});
validateattributes(o.current_offset_samples,{'double'},{'scalar','integer','finite'});
assert(~isempty(trials),'accelff:NoTrials','No validated trials were supplied.');
ids = strings(numel(trials),1);
for q=1:numel(trials)
    tr=trials(q); ids(q)=tr.id;
    assert(isequal(tr.quality_passed,true), ...
        'accelff:Quality','Only validated captures are accepted.');
    assert(ismember(string(tr.split),["train","validation","test"]), ...
        'accelff:Split','Unknown split.');
    if string(tr.split)=="train"
        assert(string(tr.current_kind)=="ilc_ff_A" && ...
            string(tr.method)=="ilc_teacher" && ...
            isfield(tr,'ilc_teacher_converged') && isequal(tr.ilc_teacher_converged,true), ...
            'accelff:TeacherRequired', ...
            'Training observations require a converged ILC learned-FF teacher.');
    else
        assert(ismember(string(tr.current_kind),["command_A","ilc_ff_A"]), ...
            'accelff:CurrentKind','Unknown current signal kind.');
    end
    for h=1:q-1
        sameReference = isequal(tr.Ts,trials(h).Ts) && isequal(tr.r,trials(h).r);
        sameProfile = string(tr.profile_id)==string(trials(h).profile_id);
        assert(~sameReference || sameProfile,'accelff:RenamedProfile', ...
            'An identical reference was renamed as a new independent profile.');
        assert(~sameProfile || string(tr.split)==string(trials(h).split), ...
            'accelff:Leakage','A trajectory profile occurs in multiple splits.');
    end
end
assert(numel(unique(ids))==numel(ids),'accelff:Duplicate','Repeated trial ID.');
assert(isequal(o.alignment_reviewed,true),'accelff:AlignmentUnverified', ...
    'Verify learned-FF-to-motion alignment before producing identification observations.');
% Explicitly typed empty table remains usable when no positions overlap.
obs=table('Size',[0,7],'VariableTypes', ...
    {'double','double','double','double','string','string','string'}, ...
    'VariableNames',{'bin','v','a','current','profile_id','trial_id','split'});
for q=1:numel(trials)
    tr=trials(q); n=numel(tr.x); Ts=tr.Ts;
    validateattributes(Ts,{'double'},{'scalar','finite','positive'});
    validateattributes(tr.x,{'double'},{'column','finite','real'});
    validateattributes(tr.current,{'double'},{'column','finite','numel',n});
    assert(numel(tr.counter)==n && all(diff(tr.counter)==1), ...
        'accelff:Counter','Cannot differentiate across lost samples.');
    h=(o.derivative_window-1)/2;
    assert(n>2*h+4,'accelff:TooShort','Capture is shorter than the derivative window.');
    tau=(-h:h)'*Ts;
    % Scale time for conditioning; derivative units are restored explicitly.
    s=tau/(h*Ts); W=pinv([ones(size(s)),s,s.^2,s.^3]);
    xf=conv(tr.x,flipud(W(1,:)'),'valid');
    vf=conv(tr.x,flipud(W(2,:)'),'valid')/(h*Ts);
    af=2*conv(tr.x,flipud(W(3,:)'),'valid')/(h*Ts)^2;
    k=(h+1:n-h)'; kc=k+o.current_offset_samples;
    keep=kc>=1 & kc<=n; xf=xf(keep); vf=vf(keep); af=af(keep);
    current=tr.current(kc(keep));
    direction=sign(vf); direction(abs(vf)<o.velocity_floor)=0;
    cuts=[1;find(diff(direction)~=0)+1;numel(direction)+1];
    seen=false(numel(grid),2);
    for b=1:numel(cuts)-1
        ix=(cuts(b):cuts(b+1)-1)'; d=direction(ix(1));
        if d==0 || numel(ix)<3, continue; end
        if d<0, ix=flipud(ix); end
        assert(all(diff(xf(ix))>0),'accelff:Nonmonotone', ...
            'Measured motion is nonmonotone; do not sort noise or a reversal.');
        g=find(grid>=xf(ix(1)) & grid<=xf(ix(end)));
        di=1+(d>0);
        assert(~any(seen(g,di)),'accelff:MultipleVisits', ...
            'More than one visit to a position/direction in the same trial.');
        seen(g,di)=true;
        z=interp1(xf(ix),[vf(ix),af(ix),current(ix)],grid(g),'linear',NaN);
        obs=[obs;table(g,z(:,1),z(:,2),z(:,3), ...
            repmat(string(tr.profile_id),numel(g),1), ...
            repmat(string(tr.id),numel(g),1),repmat(string(tr.split),numel(g),1), ...
            'VariableNames',obs.Properties.VariableNames)]; %#ok<AGROW>
    end
end
end
