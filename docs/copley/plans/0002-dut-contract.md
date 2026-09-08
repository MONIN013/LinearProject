# DUT Contract

Date: 2026-07-07

This note records the active PLC-facing DUT shape.

## Command Boundary

`DUT_CommandMailbox`:

1. `command_id : UINT`
2. `request_id : UDINT`
3. `lease_id : UDINT`
4. `protocol_id : UINT`
5. `last_accepted_request_id : UDINT`
6. `last_rejected_request_id : UDINT`
7. `rejection_reason : STRING(80)`

`DUT_Heartbeat`: `lease_id : UDINT`, `counter : UDINT`.

`DUT_ProtocolParams` is the 192-byte prepare payload:

1. `axis_index : UINT`
2. `position_raw_zero : DINT`
3. `position_zero_m : LREAL`
4. `position_m_per_count : LREAL`
5. `velocity_mps_per_count : LREAL`
6. `x_soft_min_m : LREAL`
7. `x_soft_max_m : LREAL`
8. `max_velocity_mps : LREAL`
9. `max_target_count : INT`
10. `current_ramp_count_per_s : LREAL`
11. `task_period_s : LREAL`
12. `settle_time_s : LREAL`
13. `pulse_time_s : LREAL`
14. `post_time_s : LREAL`
15. `timeout_s : LREAL`
16. `angle_start_rad : LREAL`
17. `angle_step_rad : LREAL`
18. `angle_count : UINT`
19. `protocol2_repeat_count : UINT`
20. `protocol2_vmax_mps : LREAL`
21. `protocol2_accel_time_s : LREAL`
22. `protocol2_const_time_s : LREAL`
23. `protocol2_pause_time_s : LREAL`
24. `speed_kp_count_per_mps : LREAL`
25. `speed_ki_count_per_m : LREAL`
26. `speed_integral_limit_count : INT`

The protocol identity is carried only by `DUT_CommandMailbox.protocol_id`; it
is not duplicated in this payload.
`axis_index` is a maintenance selector with the valid range 1 through 4.

## Motor-Driver Boundary

- `DUT_MotorDriverCommand`: `ControlWord : WORD`, `TargetTorque : INT`.
- `DUT_MotorDriverStatus`: `StatusWord : WORD`,
  `PositionActualValue : DINT`, `VelocityActualValue : DINT`,
  `TorqueActualValue : INT`.

The public virtual-CST ABI is intentionally exactly two inputs and four
outputs. A selected cyclic transport maps the two-field source directly to
`GVL_MotorRuntime.Command` and reads `GVL_MotorRuntime.Status`. Normal command
acceptance is entirely inside MotorRuntime and has no Simulink,
ExperimentSequencer, Guard, Authorization, or producer Clock dependency.

MotorRuntime broadcasts the normal ControlWord to every configured active
Copley axis without filtering, zero-cycle insertion, reset pulse shaping, or an
additional software-ready gate. Axes 1 and 2 are always active; the compile-time
`NORMAL_FOUR_AXIS_ENABLED` constant selects whether axes 3 and 4 are also
active, with `TRUE` as the checked-in default. Public TargetTorque uses rated
torque / 1000 and is converted to the private Copley 0.1 A / 1000
representation (factor 20 for the checked-in 2.0 A rated current; the model's
separate 2.8 A value remains its peak limit). Normal TargetTorque is written
only to active axes whose inclusive magnetic-linkage window contains the raw
Panasonic position; adjacent windows overlap through the measured core
transitions. Conversion overflow is saturated to the physical signed-16-bit
range and recorded privately. Commissioning retains
raw physical counts. The physical Copley configuration owns operating limits.
There is no ADS normal-motion request/auth/status gateway.

Because the two command fields contain no liveness information, the configured
cyclic transport must force them to `0/0` on connection or producer loss, or
provide a private transport-quality interlock.

`commissioningCommand` and `commutationOverride` are distinct private inputs,
selected only during the heartbeat-gated maintenance workflow.

### Public status semantics

- `StatusWord`: conservative reduction of configured active-axis status words;
  bit 3 is reserved for a physical drive fault, while PLC runtime safety faults
  remain private with their `fault_id`.
- `PositionActualValue`: shared Panasonic position count.
- `VelocityActualValue`: velocity derived from the shared Panasonic position
  count using the assigned 4 or 8 kHz PLC task period.
- `TorqueActualValue`: average of the configured active-axis actual-current
  values, converted to rated torque / 1000.

### Physical PDO semantics

MotorRuntime alone owns the process-image slots for each Copley Status Word and
actual-current input and each Control Word, Target Torque, and commutation-angle
output, plus the shared Panasonic communication inputs and independent
WcState/InputToggle inputs for both XE2 devices. Panasonic velocity is derived
from position in the PLC. Axes 1/2 map to Drive 7 Module 1/2 and axes 3/4 map to
Drive 8 Module 1/2. Both drive communication paths feed the existing final
zero-output gate in two- and four-axis builds. These values are not additional
public virtual-CST fields.

## Registered Reference And Override

`DUT_AxisCalibration`:

1. `reference_position_count : DINT`
2. `reference_commutation_angle : UINT`
3. `electrical_direction : INT`

This fixed eight-byte record is the complete calibration record. Runtime truth
is `GVL_MotorRuntimeInternal.RegisteredReference[i]`, a retained array with one
independent record per axis. The record embeds no version, accepted, or fallback
field. The separate retained `RegisteredReferenceValid[i]` is mandatory:
normal CST remains unready and reports fault ID 612 for a nonzero command until
every configured active axis is valid. `AdsMotorRuntimePort` clears validity,
writes and reads back the complete record, then sets validity and verifies it.
Axis `i` still never
reads another axis's record. Analysis acceptance remains commissioning artifact
metadata and is not part of the calibration record.
MATLAB registration manifests must contain the complete axis set `[1,2]` or
`[1,2,3,4]`; duplicates, gaps, and all other sets are invalid.

`GVL_MotorRuntimeInternal.CommissioningReference[i]` uses the same record type
but is non-retained. Commissioning may stage seed and interim values there;
only an explicit final registration may replace a complete
`RegisteredReference[i]` record. The runtime-wide
`COUNTS_PER_ELECTRICAL_PERIOD=360000` constant is not repeated in the payload.
For current Panasonic count `p`, normal CST evaluates only axis `i` as:

`wrap(2*pi*reference_commutation_angle/65536 + electrical_direction*2*pi*(p-reference_position_count)/360000)`

The wrapped angle is converted back to the Copley `UINT` output.

`DUT_CommutationOverride`:

1. `enable : BOOL`
2. `angle_offset_rad : LREAL`
3. `axis_index : UINT`

`DUT_MotorFeedbackSnapshot`:

1. `encoder_position_raw : DINT`
2. `encoder_velocity_raw : DINT`
3. `copley_statusword : WORD`
4. `copley_actual_current_count : INT`
5. `output_torque_count : INT`
6. `fault_id : UDINT`

## Sequencer Status And Context

`DUT_SequencerStatus`:

1. `done : BOOL`
2. `fault : BOOL`
3. `fault_id : UDINT`

`DUT_SequencerContext`:

1. `protocol_id : UINT`
2. `phase_id : UINT`
3. `angle_index : UINT`
4. `protocol2_local_sample_index : UINT`
5. `experiment_angle_rad : LREAL`
6. `x_ref_traj_m : LREAL`
7. `t_cycle_s : LREAL`
8. `fault_id : UDINT`
9. `iq_cmd_count_req_lreal : LREAL`
10. `target_current_count_lreal : LREAL`

## Logger Sample Layout

`DUT_LoggerSample` is 72 bytes and is decoded by `AdsLoggerPort` with this byte
layout:

| Byte offset | Field | Type |
| ---: | --- | --- |
| 0 | `sample_index` | `UDINT` |
| 4 | `protocol_id` | `UINT` |
| 6 | `phase_id` | `UINT` |
| 8 | `angle_index` | `UINT` |
| 10 | `protocol2_local_sample_index` | `UINT` |
| 12-15 | alignment padding | 4 bytes |
| 16 | `t_cycle_s` | `LREAL` |
| 24 | `experiment_angle_rad` | `LREAL` |
| 32 | `x_ref_traj_m` | `LREAL` |
| 40 | `encoder_position_raw` | `DINT` |
| 44 | `encoder_velocity_raw` | `DINT` |
| 48 | `copley_actual_current_count` | `INT` |
| 50 | `output_torque_count` | `INT` |
| 52 | `fault_id` | `UDINT` |
| 56 | `iq_cmd_count_req_lreal` | `LREAL` |
| 64 | `target_current_count_lreal` | `LREAL` |

## Axis Count

- `GVL_MotorRuntimeInternal.AXIS_COUNT : UINT := 4`.
- `GVL_MotorRuntimeInternal.NORMAL_FOUR_AXIS_ENABLED : BOOL := TRUE`; setting
  it `FALSE` deactivates axes 3/4 together and requires rebuild/download.
- `GVL_MotorRuntimeInternal.RegisteredReference :
  ARRAY [1..AXIS_COUNT] OF DUT_AxisCalibration`.
- `GVL_MotorRuntimeInternal.RegisteredReferenceValid :
  ARRAY [1..AXIS_COUNT] OF BOOL`.
- `GVL_MotorRuntimeInternal.CommissioningReference :
  ARRAY [1..AXIS_COUNT] OF DUT_AxisCalibration`.

The checked-in registered-reference validity is `[TRUE, TRUE, TRUE, TRUE]`,
with accepted initial records for all four axes. Either build reports fault 612
for a nonzero normal command if any configured active-axis validity flag is
cleared.

The commissioning `motorFeedback` snapshot is selected-axis maintenance data
used by the sequencer and logger. It is deliberately separate from public
`GVL_MotorRuntime.Status`.
