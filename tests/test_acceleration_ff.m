function tests=test_acceleration_ff
%TEST_ACCELERATION_FF Offline MATLAB tests; no Simulink/ADS/hardware calls.
tests=functiontests(localfunctions);
end
function setupOnce(t)
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src'));
t.TestData.options=accelff.options();
end
function testProfileEndpoints(t)
p=accelff.profile(.84,6,.65,.001,[.1,.2,.1]);
verifyEqual(t,p.x([1,end]),[0;0],'AbsTol',1e-12);
verifyEqual(t,max(p.x),.84,'AbsTol',1e-12);
verifyEqual(t,diff(p.t),repmat(.001,numel(p.t)-1,1),'AbsTol',1e-12);
end
function testReturnAccelerationSign(t)
p=accelff.profile(.84,6,.65,.001,[0,0,0]); n=(numel(p.t)+1)/2;
verifyEqual(t,p.x(1:n),flipud(p.x(n:end)),'AbsTol',1e-12);
verifyEqual(t,p.v(1:n),-flipud(p.v(n:end)),'AbsTol',1e-12);
verifyEqual(t,p.a(1:n),flipud(p.a(n:end)),'AbsTol',1e-12);
end
function testProfileAnalyticDerivative(t)
p=accelff.profile(.84,6,-.65,.001,[0,0,0]);
ix=10:5990;
v=(p.x(ix+1)-p.x(ix-1))/.002;
a=(p.v(ix+1)-p.v(ix-1))/.002;
verifyLessThan(t,max(abs(v-p.v(ix))),1e-6);
verifyLessThan(t,max(abs(a-p.a(ix))),1e-6);
end
function testDecodeIdentity(t)
[job,m]=fixture(); tr=accelff.decode(m,job,1,1e-10);
verifyEqual(t,tr.current,m(3,:)'); verifyFalse(t,tr.quality_passed);
verifyEqual(t,tr.x,m(8,:)');
end
function testDecodeMissingCounter(t)
[job,m]=fixture(); m(1,5:end)=m(1,5:end)+1;
verifyError(t,@()accelff.decode(m,job,1,1e-10),'accelff:Counter');
end
function testDecodeWrongDelay(t)
[job,m]=fixture(); verifyError(t,@()accelff.decode(m,job,0,1e-10),'accelff:Reference');
end
function testDecodeWrongFF(t)
[job,m]=fixture(); m(7,4)=m(7,4)+.1;
verifyError(t,@()accelff.decode(m,job,1,1e-10),'accelff:Feedforward');
end
function testFitCoefficients(t)
[obs,grid,b]=sampleObservations(); model=accelff.fit_map(obs,grid,t.TestData.options);
verifyTrue(t,all(model.valid)); verifyEqual(t,model.coefficients,repmat(b,2,1),'AbsTol',1e-10);
verifyFalse(t,model.hardware_approved);
end
function testHoldoutRejected(t)
[obs,grid]=sampleObservations(); obs.split(1)="test";
verifyError(t,@()accelff.fit_map(obs,grid,t.TestData.options),'accelff:Holdout');
end
function testConfoundedAcceleration(t)
[obs,grid]=sampleObservations(); obs.a=2*obs.v;
model=accelff.fit_map(obs,grid,t.TestData.options);
verifyFalse(t,any(model.valid)); verifyTrue(t,all(isnan(model.coefficients),'all'));
end
function testRepeatsDoNotCreateExcitation(t)
[obs,grid]=sampleObservations(); obs.profile_id(:)="same";
model=accelff.fit_map([obs;obs;obs],grid,t.TestData.options);
verifyFalse(t,any(model.valid));
end
function testMapPredictionAndAdvance(t)
[m,l]=mapFixture(); x=[0;.25;.5;.75;1]; v=.1*ones(5,1); a=zeros(5,1);
f=accelff.feedforward(m,x,v,a,zeros(5,1),1,.01,1,l);
verifyEqual(t,f,.12*ones(5,1),'AbsTol',1e-12);
end
function testMapNoExtrapolation(t)
[m,l]=mapFixture();
verifyError(t,@()accelff.feedforward(m,[-.1;.5],[.1;.1],[0;0],[0;0],1,.01,0,l),'accelff:Coverage');
end
function testMapHole(t)
[m,l]=mapFixture(); m.valid(2)=false;
verifyError(t,@()accelff.feedforward(m,[.25;.5],[.1;.1],[0;0],[0;0],1,.01,0,l),'accelff:Coverage');
end
function testMapEnvelope(t)
[m,l]=mapFixture();
verifyError(t,@()accelff.feedforward(m,[.25;.5],[2;2],[0;0],[0;0],1,.01,0,l),'accelff:Envelope');
end
function testNoClipping(t)
[m,l]=mapFixture(); l.ff_A=.01;
verifyError(t,@()accelff.feedforward(m,[.25;.5],[.1;.1],[0;0],[0;0],1,.01,0,l),'accelff:FFLimit');
end
function testStoppedUsesBaseline(t)
[m,l]=mapFixture();
f=accelff.feedforward(m,[-1;-1],[0;0],[0;0],[.01;.02],1,.01,0,l);
verifyEqual(t,f,[.01;.02]);
end
function testObservationsRequireValidatedCapture(t)
[job,m]=fixture(); tr=accelff.decode(m,job,1,1e-10);
verifyError(t,@()accelff.observations(tr,[5.41;5.5],t.TestData.options),'accelff:Quality');
end
function testAlignmentMustBeReviewed(t)
[job,m]=fixture(); tr=accelff.decode(m,job,1,1e-10); tr.quality_passed=true;
verifyError(t,@()accelff.observations(tr,[5.41;5.5],t.TestData.options),'accelff:AlignmentUnverified');
end
function [job,m]=fixture()
p=accelff.profile(.1,1,.2,.001,[.1,.1,.1]);
job=struct('id',"fixture",'profile_id',"fixture",'split',"train", ...
    'method',"fb",'v',p.v,'a',p.a,'r',p.x,'f',zeros(size(p.x)),'Ts',p.Ts);
n=numel(p.x); r=[0;p.x(1:end-1)]; v=[0;p.v(1:end-1)];
m=zeros(10,n); m(1,:)=100+(0:n-1); m(3,:)=.3;
m(4,:)=v'; m(5,:)=r'; m(8,:)=5.41+r'; m(9,:)=r';
end
function [obs,grid,b]=sampleObservations()
grid=[0;1]; b=[.05,.2,.05,.3];
v0=[.1;-.1;.2;-.2;.3;-.3]; a0=[.1;.1;-.2;-.2;.3;.3];
v=[v0;v0]; a=[a0;a0]; y=[ones(size(v)),v,sign(v),a]*b';
profiles=repmat(["one";"one";"two";"two";"three";"three"],2,1);
obs=table([ones(6,1);2*ones(6,1)],v,a,y,profiles,repmat("train",12,1), ...
    'VariableNames',{'bin','v','a','current','profile_id','split'});
end
function [m,l]=mapFixture()
m=struct('schema_version',1,'grid',[0;1],'coefficients',repmat([.05,.2,.05,.3],2,1), ...
    'coefficient_order',["g","b","c","alpha"],'valid',true(2,1), ...
    'bounds',repmat([-1,1,-1,1],2,1));
l=struct('velocity_floor',.002,'ff_A',1,'ff_slew_A_s',100);
end
