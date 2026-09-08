# ADR 0002: Two-PLC Configured-Axis Runtime

Date: 2026-07-07

## Status

Accepted.

## Context

The project runs a linear motor from TwinCAT. The checked-in hardware mapping
exposes one Panasonic MCDLT35BM as the mover position feedback source and two
Copley XE2 drives with four CSTCA axes, all coupled to the mover. The PLC can be
compiled with axes 1/2 active or with all four axes active; physical mappings for
all four axes remain present in either build.

From the outside, the runtime presents one CST-style motor-driver boundary:
input `ControlWord` and `TargetTorque`; output `StatusWord`,
`PositionActualValue`, `VelocityActualValue`, and `TorqueActualValue`.

Magnetic pole position estimation is a commissioning workflow. It targets one
axis at a time and can explicitly register a per-axis reference for normal
operation.

Both PLC projects share one selectable 125 us (8 kHz) or 250 us (4 kHz) task.
Their timing calculations use the assigned runtime task period.

## Decision

### PLC Projects

- `ExperimentSequencer` ADS 851: MATLAB command boundary, heartbeat
  supervision, protocol execution, driver-command production, commissioning
  commutation override, sequencer context, and logger ring buffer.
- `MotorRuntime` ADS 852: sole owner of Copley CSTCA outputs, public
  motor-driver boundary, retained per-axis registered references, commutation,
  and diagnostic feedback.

Only `MotorRuntime` writes physical Copley output symbols.

### Runtime Shape

`MotorRuntime` uses `AXIS_COUNT : UINT := 4` and stores production references
as the retained
`RegisteredReference : ARRAY [1..AXIS_COUNT] OF DUT_AxisCalibration`.

Each axis has its own magnetic pole reference:
`reference_position_count : DINT` and
`reference_commutation_angle : UINT`, plus
`electrical_direction : INT`. These are the Panasonic count captured at the
reference, the Copley angle to apply at that count, and that axis's electrical
direction. The PLC treats every registered value as authoritative: it has no
embedded version, validity, acceptance, or cross-axis fallback field. The
separate retained `RegisteredReferenceValid[i]` flag is mandatory, and normal
CST requires every configured active axis to be valid. Each axis uses only its
own record. Counts per electrical period remain the shared runtime constant
`360000`.

Commissioning uses a separate, non-retained
`CommissioningReference : ARRAY [1..AXIS_COUNT] OF DUT_AxisCalibration` for
seed and interim values. A commissioning run does not mutate production
registration unless its final result is explicitly registered as a complete
record. Experiment acceptance remains MATLAB artifact metadata, not a PLC
runtime decision.

Normal operation always commands axes 1 and 2. The compile-time constant
`NORMAL_FOUR_AXIS_ENABLED : BOOL := TRUE` selects whether axes 3 and 4 are
also active; changing modes requires rebuilding and downloading the PLC. There
is no runtime axis-membership mode switch. `MotorRuntime` broadcasts the same
unchanged `ControlWord` to each active axis and converts public `TargetTorque`
from rated torque / 1000 to the private 0.1 A / 1000 representation. It writes
that torque only while the shared raw Panasonic position is inside the axis's
inclusive magnetic-linkage window; adjacent windows overlap through the
measured transition regions. Every active retained registration-valid flag must be true
before normal output and commutation; a nonzero normal command while an active
record is invalid reports fault 612. The checked-in validity state is
`[TRUE, TRUE, TRUE, TRUE]`, with accepted records for all four axes. Inactive-axis
ControlWord, TargetTorque, and commutation angle remain zero. Operating limits
remain configured in the physical Copley hardware. Mover position remains a
single shared Panasonic encoder value; each active electrical angle is derived
from that shared position plus that axis's registered reference.

### Commissioning Override

`DUT_ProtocolParams.axis_index` selects the target axis for commissioning.
`DUT_CommutationOverride.axis_index` carries the active target axis to
`MotorRuntime`.

When override is enabled, `MotorRuntime` accepts motion only for the selected
axis. The sequencer heartbeat lease controls override enablement and clears the
commissioning command when the lease expires.

### Command And Safety Identifiers

- `command_id`: mailbox command code.
- `request_id`: MATLAB command acknowledgement correlation.
- `lease_id`: heartbeat lease checked by the PLC during protocol execution.
- `protocol_id`: selected protocol and analysis key.
- `phase_id`, `angle_index`, `protocol2_local_sample_index`: protocol-local
  logger and analysis coordinates.
- `fault_id`, `rejection_reason`: fault and command-rejection diagnostics.

Experiment identity is not part of the PLC boundary, commissioning plan,
logger sample, or analysis result. RunStore owns output directory creation.

### Logger

The logger captures only while a protocol is actively running. Its 72-byte
sample contains protocol coordinates and timing, encoder position and velocity,
actual current, output torque, `fault_id`, the controller current request, and
the applied current command needed by MATLAB analysis.

### MATLAB

MATLAB owns commissioning orchestration: command sequencing, heartbeat
production, monitoring, log download, analysis, artifact writing, and optional
calibration apply. Normal motor operation does not depend on MATLAB.
Maintenance `axis_index` values range from 1 through 4. Magnetic-pole manifests
must contain exactly axes `[1,2]` or `[1,2,3,4]`.

### Normal Control Producer

The normal producer and commissioning producer are now separate. The
selected cyclic transport maps its complete two-field command directly to
`GVL_MotorRuntime.Command`; normal command acceptance does not depend on the
sequencer.

Commissioning retains its own command, commutation override, and selected-axis
feedback maintenance plane. MotorRuntime arbitrates both sources and fails to
zero on source conflict or an invalid transition. Commissioning retains its own
heartbeat/counter checks. There is no ADS request/auth/status surface for normal
CST.
See ADR 0003 for the safety contract.

The public four-field status is produced by MotorRuntime: Panasonic position
and velocity, a conservative StatusWord reduction of the configured active
axes, and the average of their Copley actual-current values converted back to
rated torque / 1000. Inactive-axis state, drive fault, reference validity, and
actual current do not enter the public virtual-drive result. Per-axis PDOs and
commissioning feedback remain private and are not alternate public status
endpoints.

## Acceptance Checks

- No source outside `MotorRuntime` writes Copley output symbols.
- Heartbeat expiry clears the private commissioning driver command.
- Normal virtual-CST ControlWord reaches every configured active Copley module
  unchanged. Converted TargetTorque reaches only position-linked axes, both
  neighbors receive it in overlap regions, and every other torque output is
  zero.
- The checked-in four-axis build includes all four axes in status and current
  aggregation. A deliberate two-axis build excludes axes 3/4, and either mode
  reports fault 612 until every active reference is valid.
- Both physical XE2 devices have independent communication freshness inputs and
  are always included in the existing final zero-output watchdog gate.
- Each active normal commutation output uses only its own registered three-field
  reference and the shared 360000-count electrical period.
- MATLAB `runtests('tests/test_copley.m')` passes on R2025a.
- `devenv.com twincat/NikonMotorProject2025.sln /Rebuild "Debug|TwinCAT RT (x64)"` succeeds.
