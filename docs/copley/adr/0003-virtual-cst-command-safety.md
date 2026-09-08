# ADR 0003: Producer-independent virtual CST boundary

Date: 2026-07-22

## Status

Accepted.

## Context

The checked-in mapping has four physical Copley CSTCA axes moving one coupled
mechanism, while the PLC supports a compile-time two- or four-axis active
configuration. Externally the active axes must look like one CST drive with
exactly two command fields and four status fields.
Normal operation must not depend on MATLAB, Simulink, a particular TcCOM model,
or the commissioning sequencer.

## Decision

The complete public cyclic interface is:

- input `GVL_MotorRuntime.Command`: `ControlWord : WORD`,
  `TargetTorque : INT`;
- output `GVL_MotorRuntime.Status`: `StatusWord : WORD`,
  `PositionActualValue : DINT`, `VelocityActualValue : DINT`,
  `TorqueActualValue : INT`.

`MotorRuntime` directly selects this command against the private commissioning
command. The normal path has no Guard, Authorization, Clock, producer-specific
dependency, command whitelist, reset pulse shaping, calibration flag gate, or
Operation Enabled wait. It broadcasts the exact `ControlWord` to the configured
active Copley axes and converts public `TargetTorque` from rated torque / 1000
to the private Copley 0.1 A / 1000 representation. The converted torque is
written only while the shared raw Panasonic position is within that axis's
inclusive magnetic-linkage window; overlapping neighboring windows are the
measured transition margins. With the checked-in 2.0 A rated current, public
`1000` maps to physical `20000`; the separate 2.8 A model limit remains the
peak limit. Physical INT overflow is saturated. Commissioning
continues to use raw physical counts and can own the output only while the
normal command is literal `0/0`. The Copley hardware configuration still owns
the actual motion limits and DS402 enforcement.

MotorRuntime alone reads the shared Panasonic inputs and per-axis Copley Status
Words and actual currents. It writes each axis's Copley Control Word, Target
Torque, and commutation angle. The checked-in TwinCAT project maps axes 1/2 to
Drive 7 Module 1/2 and axes 3/4 to Drive 8 Module 1/2, for eighteen physical
inputs and twelve physical outputs. Each XE2 has an independent WcState and
InputToggle freshness path into the existing final zero-output gate. Public status
is a conservative StatusWord reduction of the configured active axes normalized
to canonical CiA 402 state values, shared Panasonic position and PLC-derived
velocity, and the active-axis average Copley actual-current value converted back
to rated torque / 1000. Raw
Copley auxiliary/manufacturer status bits are available in the selected-axis
commissioning feedback; they are not exposed through the virtual drive
StatusWord.
StatusWord bit 3 represents only a physical Copley fault. Arbitration and other
PLC runtime safety faults remain private with their
`fault_id`, because a CiA 402 fault reset cannot clear those conditions.

Magnetic-pole commissioning remains private. The only runtime truth for axis
`i` is its retained `RegisteredReference[i]`, containing
`reference_position_count`, `reference_commutation_angle`, and
`electrical_direction`. The record itself has no version, accepted, absence,
or fallback field, and each axis reads only its own record. The separate
retained `RegisteredReferenceValid[i]` safety gate prevents normal CST from
using an active-axis record until registration has cleared validity, written and
read back the record, then restored validity. Axes 1 and 2 are always active;
axes 3 and 4 are active together only when the compile-time
`NORMAL_FOUR_AXIS_ENABLED` constant is `TRUE` (the checked-in default is
`TRUE`). All four axes start with accepted records and valid flags. If an
active-axis flag is cleared, the existing fault 612 rejects a nonzero normal
command until its complete record is registered and read back. Inactive-axis outputs are zero and their status, drive
fault, reference validity, and current are excluded from public status. The
shared electrical period remains the runtime constant `360000` counts.

Seed and interim commissioning values use the non-retained
`CommissioningReference[i]`. They do not affect normal CST; production RETAIN
changes only when the complete final three-field record is explicitly
registered. Analysis acceptance is retained only in MATLAB artifacts.

## Transport liveness

The exact two-field command contains no PLC heartbeat. MotorRuntime passes it
transparently; communication-loss handling belongs to the selected cyclic
transport and physical drive configuration. The checked-in normal transport is
TcCOM, not one-shot ADS writes.

The checked-in project selects the two TcCOM objects as the cyclic transport:
`motor_config` exchanges `ControlWord`/`StatusWord`, while
`linear_exp_2025a` exchanges `TargetTorque` and the remaining three status
fields. This concrete mapping does not change the producer-independent PLC
contract, but it makes valid TF1400 licensing and an active EtherCAT OP state
deployment prerequisites.

## Consequences

- The public ABI remains exactly two inputs and four outputs.
- Axis selection is a compile-time PLC choice, not a cyclic or ADS input.
- The checked-in physical mapping contains four axes across two XE2 devices;
  the checked-in PLC build keeps all four enabled and commutated, while normal
  TargetTorque is position-gated per magnetic-linkage window.
- Normal virtual CST is independent of Simulink and ExperimentSequencer.
- Physical PDO expansion does not change the public virtual-CST ABI.
- Magnetic-pole estimation does not decide runtime reference validity; explicit
  registration is the only production update path.
- External transport selection and zero-on-loss behavior are mandatory before
  target activation or real-motion validation.
