param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path

[xml]$project = Get-Content -LiteralPath (Join-Path $root 'NikonMotorProject2025.tsproj') -Raw
[xml]$motorTmc = Get-Content -LiteralPath `
    (Join-Path $root 'MotorRuntime\MotorRuntime.tmc') -Raw
[xml]$sequencerTmc = Get-Content -LiteralPath `
    (Join-Path $root 'ExperimentSequencer\ExperimentSequencer.tmc') -Raw

function Get-DataTypeBitSize {
    param(
        [xml]$Document,
        [string]$Name
    )

    $node = $Document.SelectSingleNode(
        "/TcModuleClass/DataTypes/DataType[Name='$Name']")
    if ($null -eq $node) {
        throw "Generated TMC data type '$Name' was not found."
    }
    return [int]$node.BitSize
}

$motorFeedbackBits = Get-DataTypeBitSize `
    -Document $motorTmc -Name 'DUT_MotorFeedbackSnapshot'
$sequencerFeedbackBits = Get-DataTypeBitSize `
    -Document $sequencerTmc -Name 'DUT_MotorFeedbackSnapshot'
$loggerSampleBits = Get-DataTypeBitSize `
    -Document $sequencerTmc -Name 'DUT_LoggerSample'
if ($motorFeedbackBits -ne 160 -or $sequencerFeedbackBits -ne 160) {
    throw "Commissioning motor feedback ABI must be 160 bits in both PLC projects."
}
if ($loggerSampleBits -ne 576) {
    throw "Commissioning logger sample ABI must be 576 bits (72 bytes)."
}
$motorRuntimeOwner = 'TIPC^MotorRuntime^MotorRuntime Instance'
$encoderOwner = 'TIID^Device 3 (EtherCAT)^Term 1 (EK1100)^Term 2 (EL5042)'
$drive1Owner = 'TIID^Device 3 (EtherCAT)^Drive 7 (XE2)'
$drive2Owner = 'TIID^Device 3 (EtherCAT)^Drive 8 (XE2)'
$requiredPhysicalLinks = @(
    @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderPositionRaw', 'FB Inputs Channel 1^Position'),
    @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderReady', 'FB Inputs Channel 1^Status^Ready'),
    @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderError', 'FB Inputs Channel 1^Status^Error'),
    @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderTxPdoState', 'FB Inputs Channel 1^Status^TxPDO State'),
    @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderWcState', 'WcState^WcState'),
    @($encoderOwner, 'PlcTask Inputs^PRG_MotorRuntime.encoderInputToggle', 'WcState^InputToggle'),
    @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyWcState', 'WcState^WcState'),
    @($drive1Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyInputToggle', 'WcState^InputToggle'),
    @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyWcStateDrive2', 'WcState^WcState'),
    @($drive2Owner, 'PlcTask Inputs^PRG_MotorRuntime.copleyInputToggleDrive2', 'WcState^InputToggle')
)

foreach ($required in $requiredPhysicalLinks) {
    $ownerName = $required[0]
    $varA = $required[1]
    $varB = $required[2]
    $owners = @($project.SelectNodes(
        "/TcSmProject/Mappings/OwnerA[@Name='$motorRuntimeOwner']/OwnerB") |
        Where-Object { $_.GetAttribute('Name') -eq $ownerName })
    if ($owners.Count -ne 1) {
        throw "Required feedback diagnostic owner is missing or duplicated: '$ownerName'."
    }
    $found = @($owners[0].SelectNodes('Link') | Where-Object {
        ($_.VarA -eq $varA -and $_.VarB -eq $varB) -or
        ($_.VarA -eq $varB -and $_.VarB -eq $varA)
    }).Count -eq 1
    if (-not $found) {
        throw "Required feedback diagnostic link is missing under '$ownerName': '$varA' <-> '$varB'."
    }
}

$obsoleteInputs = @('PlcTask Inputs^PRG_MotorRuntime.copleyInfoState')
$links = @($project.SelectNodes('/TcSmProject/Mappings//Link'))
foreach ($obsolete in $obsoleteInputs) {
    if (@($links | Where-Object {
        $_.VarA -eq $obsolete -or $_.VarB -eq $obsolete
    }).Count -ne 0) {
        throw "Obsolete physical diagnostic link remains: '$obsolete'."
    }
}

Write-Host (
    'Feedback diagnostics verified: Feedback={0} bytes, LoggerSample={1} bytes, physical links={2}.' `
        -f ($motorFeedbackBits / 8), ($loggerSampleBits / 8),
        $requiredPhysicalLinks.Count)
