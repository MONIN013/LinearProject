# Copley Test Documentation

The active architecture is documented in
[`adr/0002-two-plc-consolidation-multi-axis-ready.md`](adr/0002-two-plc-consolidation-multi-axis-ready.md).
The PLC-facing data contract is in
[`plans/0002-dut-contract.md`](plans/0002-dut-contract.md).

Current boundaries:

- `ExperimentSequencer` ADS 851: command mailbox, protocol params, heartbeat,
  protocol execution, private commissioning command production, commissioning
  context, and the experiment-scoped 4/8 kHz logger ring buffer. There is no
  normal-motion ADS command gateway.
- `MotorRuntime` ADS 852: retained per-axis registered references and validity,
  commutation, I/O watchdog, and sole ownership of Copley CSTCA outputs. Its
  public cyclic boundary is one
  motor-driver shape:
  `GVL_MotorRuntime.Command` (`ControlWord`, `TargetTorque`) and
  `GVL_MotorRuntime.Status` (`StatusWord`, `PositionActualValue`,
  `VelocityActualValue`, `TorqueActualValue`). Internally axes 1 and 2 are
  always active; the compile-time `NORMAL_FOUR_AXIS_ENABLED` constant selects
  whether axes 3 and 4 are also active, with `TRUE` as the checked-in default.
  The normal virtual-CST `ControlWord` is
  broadcast unchanged to the configured active axes. Public `TargetTorque` uses
  rated torque / 1000 and is converted to each active Copley's private
  0.1 A / 1000 representation every PLC cycle, but is written only while that
  axis's measured magnetic-linkage window contains the shared raw Panasonic
  position. Adjacent windows overlap through the measured core transitions.
  All per-axis Copley outputs are forced to zero while the existing I/O
  watchdog is unsafe.
- `src/+copley`: commissioning use cases, explicit ports, fake test ports,
  ADS infrastructure, analysis, and artifact writing.

The three runtime planes must not be conflated:

| Plane | Contract | Meaning |
| --- | --- | --- |
| Public virtual CST | A cyclic transport maps two fields to `MotorRuntime.Command` and reads four fields from `MotorRuntime.Status` | One virtual motor. Torque command/feedback use rated torque / 1000. `StatusWord` is a conservative reduction of the configured active axes and position/velocity come from the Panasonic encoder. |
| Physical PDO | Shared Panasonic inputs plus four per-axis Copley Status Word/actual current inputs and Control Word/Target Torque/commutation-angle outputs. Axes 1/2 map to Drive 7 Module 1/2; axes 3/4 map to Drive 8 Module 1/2. Panasonic velocity is derived from position in the PLC. | Private to `MotorRuntime`; no upper-layer client writes these PDOs. Each XE2 has independent WcState/InputToggle inputs, and both are required healthy by the existing final zero-output gate. |
| Commissioning maintenance | `driveCommand`, `commutationOverride`, and selected-axis `motorFeedback` between `ExperimentSequencer` and `MotorRuntime` | ADS 851 commissioning only. It is heartbeat/lease gated and is not the public `MotorRuntime.Status` or a normal-CST API. |

Magnetic pole position estimation is an optional commissioning path, not the
normal motor-driver interface. The only runtime truth for each axis is its own
retained `GVL_MotorRuntimeInternal.RegisteredReference[i]`: Panasonic reference
position count, Copley `UINT` commutation angle, and electrical direction.
MotorRuntime does not estimate, accept, or repair these values, and an axis
never reads another axis's reference. Normal CST evaluates them with the shared
360000-count electrical period only when every configured active axis has a
true retained `RegisteredReferenceValid` flag. The checked-in validity state is
`[TRUE, TRUE, TRUE, TRUE]`, backed by the accepted references for all four axes.
If any active-axis validity flag is cleared, the existing fault 612 rejects a
nonzero normal command until a complete record is registered and read back.

Commissioning seeds and interim results are written only to the non-retained
`CommissioningReference[i]`. They cannot change normal CST commutation. Only an
explicit final registration writes the complete three-field record to
`RegisteredReference[i]`; an interrupted or rejected experiment leaves the
production registration unchanged. Analysis `accepted` remains artifact
quality metadata and is not part of the PLC reference payload.

Normal virtual-CST commands enter only through the two-field process-image
`Command`. For normal operation, `MotorRuntime` broadcasts the complete 16-bit
`ControlWord` unchanged to every configured active axis and converts signed
16-bit `TargetTorque` from rated torque / 1000 to the Copley internal
0.1 A / 1000 representation. The checked-in 2.0 A rated-current setting
therefore uses a factor of 20: public `1000` becomes physical `20000` on each
magnetically linked axis and zero on every unlinked axis. The inclusive windows
are Axis 1 `[54054804,57600015]`, Axis 2 `[55809159,61230980]`, Axis 3
`[59369714,64809681]`, and Axis 4 `[63068811,66655810]`. Their overlaps are
the measured transitions in which both neighboring axes receive the command.
An additional `TORQUE_LINKAGE_MARGIN_COUNT=186127` extends both ends of every
window for pre-excitation and delayed cutoff in either travel direction.
This is 10% of the largest measured segment width, rounded up; it covers
boundary errors bounded by that many counts, not 10% of absolute encoder
coordinates or accumulated scale error. The effective inclusive windows are
Axis 1 `[53868677,57786142]`, Axis 2 `[55623032,61417107]`, Axis 3
`[59183587,64995808]`, and Axis 4 `[62882684,66841937]`.
The separate 2.8 A model limit remains the peak limit. Values
outside the physical signed-16-bit range are saturated. The inverse conversion
averages only the active axes for public `TorqueActualValue`. Private
commissioning remains raw, so its
`TargetTorque 1000` still means 0.1 A. The runtime does not filter CiA 402
commands, limit reset duration, or wait for every active axis to report
Operation Enabled. It does require every active retained registration-valid
flag before normal commutation. `ExperimentSequencer`
can take commissioning ownership only while the normal command is literal
`0/0`.

The public `StatusWord` reports a conservative, canonical CiA 402 reduction of
the configured active axes (`0x0000`, `0x0040`, `0x0021`, `0x0023`, `0x0027`,
`0x0007`, `0x000F`, or `0x0008`). Inactive-axis state and drive faults are
excluded. Copley auxiliary/manufacturer bits such as `0x1600` are stripped from
this public value. During commissioning, selected-axis
`motorFeedback.copley_statusword` carries the raw word. In particular, public
bit 3 is set only for a physical drive fault that `0x0080` can clear. PLC
runtime safety faults remain in the private commissioning `fault_id` feedback
and do not masquerade as a drive fault.

The two-field public ABI intentionally contains no PLC heartbeat or additional
authorization. The selected cyclic transport and physical drive configuration
own loss-of-communication handling. One-shot ADS writes are not the configured
normal transport; the checked-in project uses the two TcCOM objects.

## Virtual-CST activation prerequisites

The PLC boundary is transport-neutral. Before activation, map exactly these
external cyclic fields:

- transport output `ControlWord` -> `GVL_MotorRuntime.Command.ControlWord`;
- transport output `TargetTorque` -> `GVL_MotorRuntime.Command.TargetTorque`;
- the four `GVL_MotorRuntime.Status` fields -> transport inputs.

These are the complete six virtual-CST links. There is no separate TcCOM
diagnostics process-image plane.

Keep the thirty physical Panasonic/Copley PDO links and the three private
PLC-to-PLC commissioning links unchanged. The checked-in project uses
the TcCOM objects as its cyclic virtual-CST transport: `motor_config` supplies
`ControlWord`, `linear_exp_2025a` supplies `TargetTorque`, and the four public
status fields are returned to those objects. This transport requires a valid
TF1400 runtime license. If that license expires, or the EtherCAT configuration
is not active and OP, the physical CSTCA input image can remain all zero even
though the Simulink algorithm itself is valid.

## Virtual-CST real-machine procedure

1. Open `twincat/NikonMotorProject2025.sln` in Visual Studio 2019 and select target NetId
   `192.168.10.3.1.1`.
2. Confirm EtherCAT is OP, all four mapped Copley modules report a nonzero
   Status Word, and both XE2 communication inputs are healthy.
3. Confirm `motor_config` and `linear_exp_2025a` are running. Do not start a
   commissioning protocol; it is not part of normal virtual CST.
4. Activate the checked-in configuration, or run
   `powershell.exe -ExecutionPolicy Bypass -File scripts\ActivateTwinCATConfiguration.ps1 -ExpectedTargetNetId 192.168.10.3.1.1`.
5. Before enabling torque, verify online that every configured active axis has
   the unchanged `GVL_MotorRuntime.Command.ControlWord`, a commutation angle
   matching its own registered reference calculation within one count. Verify
   that only axes whose linkage windows contain the encoder position receive
   TargetTorque equal to the virtual input multiplied by 20; in each overlap
   region the two neighboring axes receive it. Every other TargetTorque must be
   zero. In a deliberately rebuilt two-axis mode, Module 3/4 remain zero.
6. Start the existing Simulink experiment. The CiA 402 progression produced by
   `motor_config` is passed unchanged to every configured active module.
7. To stop, stop/disable the Simulink experiment so it outputs
   `TargetTorque=0`, then `ControlWord=0`. Confirm all four mapped Module outputs
   follow.

## Registered magnetic-pole references

The checked-in production references are recorded in
[`config/copley/magnetic_pole_references.json`](../../config/copley/magnetic_pole_references.json):

| Axis | Reference position | Reference angle | Direction | Source |
| --- | ---: | ---: | ---: | --- |
| 1 | 54984708 | 49480 | 1 | `data/raw/replay_20260617_164644/commissioning_20260807_142216_759` |
| 2 | 58408617 | 17933 | 1 | `data/raw/replay_20260617_164644/commissioning_20260807_141224_687` |
| 3 | 61902867 | 63448 | 1 | `data/raw/replay_20260617_164644/commissioning_20260831_144234_825` |
| 4 | 65824016 | 57717 | 1 | `data/raw/replay_20260617_164644/commissioning_20260831_150055_861` |

The same four records are the checked-in RETAIN initial values, with
`RegisteredReferenceValid=[TRUE, TRUE, TRUE, TRUE]`. A PLC download or cold
start therefore falls back to this authoritative four-axis manifest rather
than superseded references. Explicit registration can still replace the live
RETAIN records without motion.

Use `src/register_magnetic_pole_references.m` to re-register this manifest.
MATLAB maintenance accepts `axis_index` 1 through 4 and requires a manifest to
contain exactly axes `[1,2]` or `[1,2,3,4]`; duplicates, gaps, and other axis
sets are rejected.
Before any RETAIN write, the normal ControlWord lower nibble must not be
`0xF` (Operation Enabled), normal TargetTorque must be zero, the commissioning
command must be literal `0/0`, and `CommutationOverride.enable` must be false.
Registration is one complete eight-byte record per axis, followed immediately
by readback of all three fields. Do not request Operation Enabled unless every
configured active-axis record exactly matches the manifest. This registration
path does not request motion.

Commissioning entry point:

```powershell
& 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -batch "setup_project; main"
```

`main.m` is a script entry point for real ADS commissioning. By default it uses
`config/copley/exp_20260617_164644_sequence.real.local.json` with
`AllowRealMotion=true`. Set `COPLEY_MAIN_CONFIG` and
`COPLEY_MAIN_APPLY_INTERIM_CALIBRATION` to override the script without editing
it. Commissioning stages seed/interim references in the non-retained array.
Production RETAIN changes only through the explicit final registration path;
leaving final registration disabled preserves the existing retained records.

For programmable or dry-run use, call `run_commissioning_main(...)` directly.
Non-dry-run ADS execution requires a real-local config and
`AllowRealMotion=true`. PLC-side motion is gated by the heartbeat lease.

RunStore creates a timestamped commissioning output directory under the
configured `baseDir`. A complete output includes `commissioning_result.mat`,
`commissioning_result.json`, `theta_result.json`, `report.md`, and SVG figures
under `figures/`.

The logger sample is the 72-byte post-Wave-1 layout documented in
`plans/0002-dut-contract.md`; its Panasonic-derived channels are named
`encoder_position_raw` and `encoder_velocity_raw` throughout PLC, ADS decoding,
and analysis.

The analyzer uses:

- Protocol 1 differential alpha/alpha+pi pulse response and sine fit.
- Protocol 2 shifted-axis q/d current equality compares the configured current
  source, converted to ampere (`TargetTorque 1000 count = 0.1 A` by default).
  The default source is `iq_cmd_count_req_lreal`, the controller current
  request immediately before `LREAL_TO_INT`; set
  `analysis.protocol2_current_source = "actual_current_count"` when measured
  drive current is the intended acceptance signal.
- Protocol 2 can run without a zero-current pause between positive/negative and
  axis-shifted runs. The PLC current request uses velocity error
  (`speed_kp * (quantized_v_ref - v_actual)` plus optional integral) and does
  not add position-error current in Protocol 2. The ExperimentSequencer applies
  `current_ramp_count_per_s * TaskPeriod_s` as a software slew limit before
  writing `TargetTorque`; the raw controller request remains logged separately
  as `iq_cmd_count_req_lreal`. Analysis rejects Protocol 2 when paired q/d
  input-current mismatch exceeds the configured threshold, and also rejects
  fully degenerate current pairs.
- Protocol 3 positive/negative q-axis pulse response as the final acceptance
  gate. It remains a distinct `protocol_id = 3` analysis result; its estimated
  position and angle supply the registered reference in `buildThetaResult`.

Re-analyze a saved commissioning folder:

```powershell
& 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -batch "setup_project; theta = analyze_commissioning_folder('<runDir>');"
```

Dry-run smoke check:

```powershell
& 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -batch "setup_project; result = run_commissioning_main('ConfigFile','config/copley/exp_20260617_164644_sequence.real.local.json','DryRun',true,'Verbose',false); assert(result.accepted);"
```

Protocol 2-only real commissioning:

```powershell
$env:COPLEY_MAIN_CONFIG='config\copley\exp_ipp_current_ratio.real.local.json'
$env:COPLEY_MAIN_APPLY_INTERIM_CALIBRATION='false'
& 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -batch "setup_project; main"
```

## Switching between 4 and 8 kHz

Stop all motion and commissioning protocols, then change only the TwinCAT
`PlcTask1` cycle time under `System > Tasks`:

- 4 kHz: `250 us` (`2500` ticks at the checked-in 100 ns base time)
- 8 kHz: `125 us` (`1250` ticks at the checked-in 100 ns base time)

Both PLC projects read the assigned task period at runtime. Real ADS runs
through `run_commissioning_main` read the same value from
`GVL_ExperimentSequencer.taskPeriod_s`, so JSON `task_period_s` values cannot
silently put PLC timing and MATLAB analysis out of sync. The active TE1400
modules use `UseTaskCycleTime` and calculate with the selected task period.
Verify the generated-model control behavior at both rates before real motion.
After changing the task, rebuild, review the TwinCAT diff, then activate and
restart the configuration using the command below. Dry runs still use the
period in their plan/config, with 4 kHz as the default.

Verification:

```powershell
& 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -batch "setup_project; results = runtests('tests/test_copley.m'); assert(all([results.Passed]));"
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\IDE\devenv.com' twincat/NikonMotorProject2025.sln /Rebuild "Debug|TwinCAT RT (x64)" /Out build_devenv.log
```

After a TwinCAT PLC change, rebuild output that says `ready for download` is
not enough to prove the target runtime was updated. Activate and restart the
configured TwinCAT target explicitly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File scripts\ActivateTwinCATConfiguration.ps1 -ExpectedTargetNetId 192.168.10.3.1.1
```

The activation script creates `VisualStudio.DTE.16.0`, matching the repository's
Visual Studio 2019 requirement. Before changing the target it verifies the
repository TF1400 trial expiration and the required physical-CSTCA and
virtual-CST links. The preflight checks eighteen physical inputs, twelve physical
outputs, and six virtual-CST links; the project also retains the three private
PLC-to-PLC commissioning links described above.
Run the same checks without activation or restart by adding `-PreflightOnly`.
Activation still changes the configured target; run it only after completing
the signal-direction and safety checks above. On a target covered exclusively
by a permanent or dongle license, use `-SkipTrialLicenseCheck` only after
confirming that target license is valid.
