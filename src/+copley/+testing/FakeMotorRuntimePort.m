classdef FakeMotorRuntimePort < copley.ports.MotorRuntimePort
    properties
        StagedReference = {[], [], [], []}
        RegisteredReference = {[], [], [], []}
        StageCount = 0
        RegisterCount = 0
        Status = struct('StatusWord', uint16(0), ...
            'PositionActualValue', int32(0), ...
            'VelocityActualValue', int32(0), ...
            'TorqueActualValue', int16(0), ...
            'encoder_position_raw', int32(0), ...
            'encoder_velocity_raw', int32(0), ...
            'copley_statusword', uint16(0), ...
            'copley_actual_current_count', int16(0), ...
            'fault', false, ...
            'fault_id', uint32(0))
    end

    methods
        function status = readStatus(obj)
            status = obj.Status;
        end

        function reference = stageReference(obj, reference)
            [~, reference] = ...
                copley.domain.toMotorRuntimeCalibrationPayload(reference);
            axisIndex = double(reference.axis_index);
            obj.StagedReference{axisIndex} = reference;
            obj.StageCount = obj.StageCount + 1;
        end

        function reference = registerReference(obj, reference)
            [~, reference] = ...
                copley.domain.toMotorRuntimeCalibrationPayload(reference);
            axisIndex = double(reference.axis_index);
            obj.RegisteredReference{axisIndex} = reference;
            obj.RegisterCount = obj.RegisterCount + 1;
        end
    end
end
