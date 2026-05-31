<#
.SYNOPSIS
    Monitors battery/lid state and hibernates the laptop when on battery with the lid closed.
.DESCRIPTION
    Runtime-only script used by the scheduled task and for manual execution.
    It listens for Windows power-setting notifications instead of polling display state.
#>

Clear-Host

Add-Type -AssemblyName System.Windows.Forms

function Get-ScriptDirectory {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    if ($env:PC_POWER_CONTROL_ROOT) {
        return $env:PC_POWER_CONTROL_ROOT
    }

    return (Get-Location).Path
}

# ---------- P/INVOKE: GetSystemPowerStatus ----------------------------------
if (-not ('PowerApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct SystemPowerStatus {
    public byte ACLineStatus;      // 0 = battery, 1 = AC, 255 = unknown
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public uint BatteryLifeTime;
    public uint BatteryFullLifeTime;
}

public static class PowerApi {
    [DllImport("Kernel32.dll")]
    public static extern bool GetSystemPowerStatus(out SystemPowerStatus sps);
}
'@
}

# ---------- P/INVOKE: Power setting notifications --------------------------
if (-not ('PowerSettingChangedEventArgs' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class PowerSettingChangedEventArgs : EventArgs {
    public Guid PowerSetting { get; private set; }
    public int Data { get; private set; }

    public PowerSettingChangedEventArgs(Guid powerSetting, int data) {
        PowerSetting = powerSetting;
        Data = data;
    }
}

public sealed class PowerNotificationForm : Form {
    private const uint WM_POWERBROADCAST = 0x0218;
    private const uint PBT_POWERSETTINGCHANGE = 0x8013;
    private const uint DEVICE_NOTIFY_WINDOW_HANDLE = 0x00000000;

    private static Guid GUID_LIDSWITCH_STATE_CHANGE = new Guid("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
    private static Guid GUID_ACDC_POWER_SOURCE = new Guid("5D3E9A59-E9D5-4B00-A6BD-FF34FF516548");

    [StructLayout(LayoutKind.Sequential)]
    private struct POWERBROADCAST_SETTING {
        public Guid PowerSetting;
        public uint DataLength;
        public uint Data;
    }

    [DllImport("User32.dll", SetLastError = true)]
    private static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid PowerSettingGuid, uint Flags);

    [DllImport("User32.dll", SetLastError = true)]
    private static extern bool UnregisterPowerSettingNotification(IntPtr Handle);

    public event EventHandler<PowerSettingChangedEventArgs> PowerSettingChanged;

    private IntPtr _lidNotifyHandle = IntPtr.Zero;
    private IntPtr _powerNotifyHandle = IntPtr.Zero;
    private bool _notificationsRegistered;

    public PowerNotificationForm() {
        this.ShowInTaskbar = false;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.WindowState = FormWindowState.Minimized;
        this.Opacity = 0;
        var _ = this.Handle;
    }

    protected override void SetVisibleCore(bool value) {
        base.SetVisibleCore(false);
    }

    public void StartNotifications() {
        if (_notificationsRegistered) {
            return;
        }

        _lidNotifyHandle = RegisterPowerSettingNotification(this.Handle, ref GUID_LIDSWITCH_STATE_CHANGE, DEVICE_NOTIFY_WINDOW_HANDLE);
        if (_lidNotifyHandle == IntPtr.Zero) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "RegisterPowerSettingNotification for lid state failed.");
        }

        _powerNotifyHandle = RegisterPowerSettingNotification(this.Handle, ref GUID_ACDC_POWER_SOURCE, DEVICE_NOTIFY_WINDOW_HANDLE);
        if (_powerNotifyHandle == IntPtr.Zero) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "RegisterPowerSettingNotification for power source failed.");
        }

        _notificationsRegistered = true;
    }

    protected override void OnHandleDestroyed(EventArgs e) {
        if (_lidNotifyHandle != IntPtr.Zero) {
            UnregisterPowerSettingNotification(_lidNotifyHandle);
            _lidNotifyHandle = IntPtr.Zero;
        }

        if (_powerNotifyHandle != IntPtr.Zero) {
            UnregisterPowerSettingNotification(_powerNotifyHandle);
            _powerNotifyHandle = IntPtr.Zero;
        }

        _notificationsRegistered = false;
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_POWERBROADCAST && m.WParam.ToInt64() == PBT_POWERSETTINGCHANGE && m.LParam != IntPtr.Zero) {
            var setting = Marshal.PtrToStructure<POWERBROADCAST_SETTING>(m.LParam);
            if (PowerSettingChanged != null) {
                PowerSettingChanged(this, new PowerSettingChangedEventArgs(setting.PowerSetting, (int)setting.Data));
            }
        }

        base.WndProc(ref m);
    }
}
'@
}

# ---------- CONSTANTS -------------------------------------------------------
$script:LidSwitchGuid = [Guid]'BA3E0F4D-B817-4094-A2D1-D56379E6A0F3'
$script:AcDcPowerSourceGuid = [Guid]'5D3E9A59-E9D5-4B00-A6BD-FF34FF516548'

# ---------- STATE -----------------------------------------------------------
$script:CurrentOnBattery = $null
$script:CurrentLidClosed = $null
$script:LastDecisionKey = $null

# ---------- FUNCTIONS -------------------------------------------------------

function Get-IsOnBattery {
    $s = New-Object SystemPowerStatus
    [PowerApi]::GetSystemPowerStatus([ref]$s) | Out-Null
    return ($s.ACLineStatus -eq 0)
}

function Get-Temperatures {
    $deg = [char]176
    $cpu = 'N/A'
    $gpu = 'N/A'
    $mb = 'N/A'

    try {
        $zones = @(Get-WmiObject -Namespace 'root\wmi' -Class 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)
        $named = @{}

        foreach ($zone in $zones) {
            $c = [math]::Round(($zone.CurrentTemperature - 2732) / 10, 1)
            $name = $zone.InstanceName.ToUpper()
            if ($name -match 'CPU|PROC|CORE') { $named['cpu'] = $c }
            elseif ($name -match 'GPU|VGA|DGPU') { $named['gpu'] = $c }
            elseif ($name -match 'MB|SYS|BOARD') { $named['mb'] = $c }
            else { $named["zone_$($zone.InstanceName)"] = $c }
        }

        if ($named.ContainsKey('cpu')) { $cpu = "$($named['cpu'])${deg}C" }
        if ($named.ContainsKey('gpu')) { $gpu = "$($named['gpu'])${deg}C" }
        if ($named.ContainsKey('mb')) { $mb = "$($named['mb'])${deg}C" }

        if ($cpu -eq 'N/A' -and $zones.Count -ge 1) {
            $sorted = $zones | ForEach-Object { [math]::Round(($_.CurrentTemperature - 2732) / 10, 1) } | Sort-Object -Descending
            $cpu = "$($sorted[0])${deg}C"
            if ($sorted.Count -ge 2) { $mb = "$($sorted[1])${deg}C" }
        }
    } catch {}

    if ($gpu -eq 'N/A') {
        try {
            $nv = & nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $nv) { $gpu = "$($nv.Trim())${deg}C" }
        } catch {}
    }

    if ($gpu -eq 'N/A') {
        foreach ($ns in @('root\LibreHardwareMonitor', 'root\OpenHardwareMonitor')) {
            try {
                $s = Get-WmiObject -Namespace $ns -Class Sensor -Filter "SensorType='Temperature' AND Name='GPU Core'" -ErrorAction Stop
                if ($s) { $gpu = "$([math]::Round($s.Value, 1))${deg}C"; break }
            } catch {}
        }
    }

    return "CPU: $cpu | GPU: $gpu | MB: $mb"
}

function Write-PowerLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Output $Message
    $logFile = Join-Path (Get-ScriptDirectory) 'check_false_consciesnous.log'
    Add-Content -Path $logFile -Value $Message -Encoding UTF8
}

function Invoke-PowerControlCheck {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$OnBattery,

        [Parameter(Mandatory = $true)]
        [bool]$LidClosed
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $tempStr = Get-Temperatures
    $decisionKey = "{0}:{1}" -f $OnBattery, $LidClosed

    if ($decisionKey -eq $script:LastDecisionKey) {
        return
    }

    $script:LastDecisionKey = $decisionKey

    $msg = if (-not $OnBattery -and -not $LidClosed) {
        "${ts}: Abort ... - The PC is running on AC power, and the lid is open. [$tempStr]"
    } elseif ($OnBattery -and -not $LidClosed) {
        "${ts}: Abort ... - The PC is running on battery power, but the lid is open. [$tempStr]"
    } elseif (-not $OnBattery -and $LidClosed) {
        "${ts}: Abort ... - The PC is running on AC power, and the lid is closed. [$tempStr]"
    } else {
        "${ts}: Hibernating ... - The PC is running on battery power, and the lid is closed. [$tempStr]"
    }

    Write-PowerLog -Message $msg

    if ($OnBattery -and $LidClosed) {
        Start-Sleep -Seconds 1
        & shutdown.exe /h
    }
}

function Update-PowerState {
    param(
        [Parameter(Mandatory = $true)]
        [Guid]$PowerSetting,

        [Parameter(Mandatory = $true)]
        [int]$Data
    )

    if ($PowerSetting -eq $script:LidSwitchGuid) {
        $script:CurrentLidClosed = ($Data -eq 0)
        return
    }

    if ($PowerSetting -eq $script:AcDcPowerSourceGuid) {
        $script:CurrentOnBattery = ($Data -eq 1)
        return
    }
}

function Invoke-IfReady {
    if ($null -eq $script:CurrentOnBattery -or $null -eq $script:CurrentLidClosed) {
        return
    }

    Invoke-PowerControlCheck -OnBattery $script:CurrentOnBattery -LidClosed $script:CurrentLidClosed
}

# ---------- INITIAL STATE ---------------------------------------------------
$script:CurrentOnBattery = Get-IsOnBattery
Write-PowerLog -Message ("{0}: Waiting for lid state notification ... [battery={1}]" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $script:CurrentOnBattery)

# ---------- MESSAGE LOOP ----------------------------------------------------
$form = New-Object PowerNotificationForm
$form.add_PowerSettingChanged([System.EventHandler[PowerSettingChangedEventArgs]]{
    param($sender, $eventArgs)
    Update-PowerState -PowerSetting $eventArgs.PowerSetting -Data $eventArgs.Data
    Invoke-IfReady
})
$form.StartNotifications()

try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    if ($form) {
        $form.Dispose()
    }
}
