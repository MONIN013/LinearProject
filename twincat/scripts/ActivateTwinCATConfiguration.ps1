param(
    [string]$SolutionPath = (Join-Path $PSScriptRoot '..\NikonMotorProject2025.sln'),
    [string]$ExpectedTargetNetId = '',
    [string]$TrialLicensePath = '',
    [switch]$SkipTrialLicenseCheck,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'

function Invoke-ComRetry {
    param(
        [scriptblock]$Block,
        [int]$Attempts = 100,
        [int]$DelayMilliseconds = 500
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            return & $Block
        } catch {
            if ($i -eq $Attempts) {
                throw
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

function Assert-TrialLicenseValid {
    param(
        [string]$Path,
        [bool]$RequireTf1400
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "TwinCAT trial license file not found: '$Path'."
    }

    [xml]$licenseDocument = Get-Content -LiteralPath $Path -Raw
    $licenseInfo = $licenseDocument.TcLicenseInfo.LicenseInfo
    if ($null -eq $licenseInfo -or [string]::IsNullOrWhiteSpace($licenseInfo.ExpireTime)) {
        throw "TwinCAT trial license has no ExpireTime: '$Path'."
    }

    $expireTime = [DateTime]::Parse(
        [string]$licenseInfo.ExpireTime,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeLocal)
    if ($expireTime -le (Get-Date)) {
        throw "TwinCAT trial license expired at $($expireTime.ToString('s')): '$Path'."
    }

    $orderNumbers = @($licenseInfo.License | ForEach-Object { [string]$_.OrderNo })
    if ($RequireTf1400 -and $orderNumbers -notcontains 'TF1400') {
        throw "TwinCAT trial license does not contain TF1400 Runtime for MATLAB/Simulink: '$Path'."
    }

    Write-Host "Repository TwinCAT trial license valid until $($expireTime.ToString('s'))."
}

function Assert-RequiredCstcaMappings {
    param([string]$ProjectPath)

    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
        throw "TwinCAT project file not found: '$ProjectPath'."
    }

    [xml]$projectDocument = Get-Content -LiteralPath $ProjectPath -Raw
    $motorRuntimeOwner = 'TIPC^MotorRuntime^MotorRuntime Instance'
    $encoderOwner = 'TIID^Device 3 (EtherCAT)^Term 1 (EK1100)^Term 2 (EL5042)'
    $drive1Owner = 'TIID^Device 3 (EtherCAT)^Drive 7 (XE2)'
    $drive2Owner = 'TIID^Device 3 (EtherCAT)^Drive 8 (XE2)'
    $motorConfigOwner = 'TIRC^TcCOM Objects^Object1 (motor_config)'
    $linearOwner = 'TIRC^TcCOM Objects^Object3 (linear_exp_2025a)'
    $requiredLinks = @(
        @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderPositionRaw', 'FB Inputs Channel 1^Position'),
        @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderReady', 'FB Inputs Channel 1^Status^Ready'),
        @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderError', 'FB Inputs Channel 1^Status^Error'),
        @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderTxPdoState', 'FB Inputs Channel 1^Status^TxPDO State'),
        @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderWcState', 'WcState^WcState'),
        @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderInputToggle', 'WcState^InputToggle'),
        @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyActualCurrentCountModule1', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Torque actual value'),
        @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyStatusWordModule1', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Status word'),
        @($drive1Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyCommutationAngleModule1', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Commutation angle'),
        @($drive1Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyControlWordModule1', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Control word'),
        @($drive1Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyTargetTorqueModule1', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Target Torque'),
        @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyActualCurrentCountModule2', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Torque actual value'),
        @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyStatusWordModule2', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Status word'),
        @($drive1Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyCommutationAngleModule2', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Commutation angle'),
        @($drive1Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyControlWordModule2', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Control word'),
        @($drive1Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyTargetTorqueModule2', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Target Torque'),
        @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyWcState', 'WcState^WcState'),
        @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyInputToggle', 'WcState^InputToggle'),
        @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyActualCurrentCountModule3', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Torque actual value'),
        @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyStatusWordModule3', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Status word'),
        @($drive2Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyCommutationAngleModule3', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Commutation angle'),
        @($drive2Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyControlWordModule3', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Control word'),
        @($drive2Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyTargetTorqueModule3', 'Module 1 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Target Torque'),
        @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyActualCurrentCountModule4', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Torque actual value'),
        @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyStatusWordModule4', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Inputs^Status word'),
        @($drive2Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyCommutationAngleModule4', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Commutation angle'),
        @($drive2Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyControlWordModule4', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Control word'),
        @($drive2Owner, 'PlcTask Outputs^PRG_MotorRuntime.copleyTargetTorqueModule4', 'Module 2 (Cyclic torque with commutation angle Mode)^Cyclic torque with commutation angle Outputs^Target Torque'),
        @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyWcStateDrive2', 'WcState^WcState'),
        @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyInputToggleDrive2', 'WcState^InputToggle'),
        @($motorConfigOwner, 'PlcTask Inputs^GVL_MotorRuntime.Command^ControlWord', 'motor_config_Y^controlWord'),
        @($linearOwner, 'PlcTask Inputs^GVL_MotorRuntime.Command^TargetTorque', 'TcModuleOutput^LinearSystem^TargetTorque'),
        @($motorConfigOwner, 'PlcTask Outputs^GVL_MotorRuntime.Status^StatusWord', 'motor_config_U^statusWord'),
        @($linearOwner, 'PlcTask Outputs^GVL_MotorRuntime.Status^PositionActualValue', 'TcModuleInput^LinearSystem^Positionactualvalue'),
        @($linearOwner, 'PlcTask Outputs^GVL_MotorRuntime.Status^VelocityActualValue', 'TcModuleInput^LinearSystem^Velocityactualvalue'),
        @($linearOwner, 'PlcTask Outputs^GVL_MotorRuntime.Status^TorqueActualValue', 'TcModuleInput^LinearSystem^Torqueactualvalue1')
    )

    foreach ($requiredLink in $requiredLinks) {
        $ownerName = $requiredLink[0]
        $varA = $requiredLink[1]
        $varB = $requiredLink[2]
        $owners = @($projectDocument.SelectNodes(
            "/TcSmProject/Mappings/OwnerA[@Name='$motorRuntimeOwner']/OwnerB") |
            Where-Object { $_.GetAttribute('Name') -eq $ownerName })
        if ($owners.Count -ne 1) {
            throw "Required TwinCAT mapping owner is missing or duplicated: '$ownerName'."
        }
        $found = @($owners[0].SelectNodes('Link') | Where-Object {
            ($_.VarA -eq $varA -and $_.VarB -eq $varB) -or
            ($_.VarA -eq $varB -and $_.VarB -eq $varA)
        }).Count -eq 1
        if (-not $found) {
            throw "Required TwinCAT link is missing under '$ownerName': '$varA' <-> '$varB'."
        }
    }

    $physicalOwners = @($encoderOwner, $drive1Owner, $drive2Owner)
    $motorOwnerNodes = @($projectDocument.SelectNodes(
        "/TcSmProject/Mappings/OwnerA[@Name='$motorRuntimeOwner']/OwnerB"))
    foreach ($physicalVarA in @($requiredLinks | Where-Object {
        $physicalOwners -contains $_[0]
    } | ForEach-Object { $_[1] })) {
        $physicalLinkCount = @($motorOwnerNodes | ForEach-Object {
            $_.SelectNodes("Link[@VarA='$physicalVarA' or @VarB='$physicalVarA']")
        }).Count
        if ($physicalLinkCount -ne 1) {
            throw "Physical PLC symbol must have exactly one TwinCAT link: '$physicalVarA'."
        }
    }

    $projectText = Get-Content -LiteralPath $ProjectPath -Raw
    if ($projectText -match 'PRG_MotorRuntime\.copley(?:StatusWord|ActualCurrentCount|ControlWord|TargetTorque|CommutationAngle)\[[12]\]') {
        throw 'TwinCAT project still contains obsolete Copley array-element links that cannot be restored.'
    }

    Write-Host 'Required physical CSTCA and virtual-CST mappings are present.'
}

$dte = $null
try {
    $resolvedSolution = (Resolve-Path $SolutionPath).Path
    $solutionDirectory = Split-Path -Parent $resolvedSolution
    $projectPath = Join-Path $solutionDirectory 'NikonMotorProject2025.tsproj'
    Assert-RequiredCstcaMappings -ProjectPath $projectPath

    if (-not $SkipTrialLicenseCheck) {
        if ([string]::IsNullOrWhiteSpace($TrialLicensePath)) {
            $TrialLicensePath = Join-Path $solutionDirectory 'TrialLicense.tclrs'
        } elseif (-not [IO.Path]::IsPathRooted($TrialLicensePath)) {
            $TrialLicensePath = Join-Path $solutionDirectory $TrialLicensePath
        }
        [xml]$projectDocument = Get-Content -LiteralPath $projectPath -Raw
        $enabledTe140x = @($projectDocument.SelectNodes(
            "/TcSmProject/Project/System/Modules/Module[" +
            "not(@Disabled='true') and " +
            "starts-with(@ClassFactoryId, 'TE140x Module Vendor|')]"))
        Assert-TrialLicenseValid -Path $TrialLicensePath `
            -RequireTf1400 ($enabledTe140x.Count -gt 0)
    }

    if ($PreflightOnly) {
        Write-Host 'TwinCAT activation preflight passed. No configuration was activated.'
        return
    }

    $dte = New-Object -ComObject 'VisualStudio.DTE.16.0'
    Invoke-ComRetry { $dte.SuppressUI = $true } | Out-Null
    Invoke-ComRetry { $dte.MainWindow.Visible = $false } | Out-Null
    Invoke-ComRetry { $dte.Solution.Open($resolvedSolution) } | Out-Null
    Start-Sleep -Seconds 8

    $sysManager = Invoke-ComRetry { $dte.GetObject('TcSysManager') }
    $targetNetId = $sysManager.GetTargetNetId()
    Write-Host "TwinCAT target NetId: $targetNetId"

    if ($ExpectedTargetNetId -and ($targetNetId -ne $ExpectedTargetNetId)) {
        throw "Expected target NetId '$ExpectedTargetNetId' but project targets '$targetNetId'."
    }

    Write-Host 'Activating TwinCAT configuration...'
    Invoke-ComRetry { $sysManager.ActivateConfiguration() } | Out-Null
    Write-Host 'Restarting TwinCAT...'
    Invoke-ComRetry { $sysManager.StartRestartTwinCAT() } | Out-Null
    Write-Host 'TwinCAT activation/restart requested.'
} finally {
    if ($null -ne $dte) {
        try { $dte.Solution.Close($false) } catch { }
        try { $dte.Quit() } catch { }
    }
}
