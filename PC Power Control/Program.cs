using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace PCPowerControl;

internal static class Program
{
    internal static readonly Guid LidSwitchGuid = new("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
    internal static readonly Guid AcDcPowerSourceGuid = new("5D3E9A59-E9D5-4B00-A6BD-FF34FF516548");
    private static AppOptions s_options = AppOptions.Default;

    [STAThread]
    private static int Main(string[] args)
    {
        s_options = AppOptions.Parse(args);
        ApplicationConfiguration.Initialize();

        using var form = new PowerNotificationForm();
        form.PowerSettingChanged += HandlePowerSettingChanged;
        form.StartNotifications();

        PowerState.CurrentOnBattery = PowerState.ReadOnBattery();
        WriteLog($"Waiting for lid state notification ... [battery={PowerState.CurrentOnBattery}, interval={s_options.RefreshIntervalMs}ms, action={s_options.SuspendMode}]");

        using var timer = new System.Windows.Forms.Timer { Interval = s_options.RefreshIntervalMs };
        timer.Tick += (_, _) =>
        {
            PowerState.CurrentOnBattery = PowerState.ReadOnBattery();
            if (PowerState.CurrentOnBattery is not null && PowerState.CurrentLidClosed is not null)
            {
                EvaluateAndAct();
            }
        };
        timer.Start();

        Application.Run(form);
        return 0;
    }

    private static void HandlePowerSettingChanged(object? sender, PowerSettingChangedEventArgs e)
    {
        if (e.PowerSetting == LidSwitchGuid)
        {
            PowerState.CurrentLidClosed = e.Data == 0;
        }
        else if (e.PowerSetting == AcDcPowerSourceGuid)
        {
            PowerState.CurrentOnBattery = e.Data == 1;
        }

        if (PowerState.CurrentOnBattery is not null && PowerState.CurrentLidClosed is not null)
        {
            EvaluateAndAct();
        }
    }

    private static void EvaluateAndAct()
    {
        var onBattery = PowerState.CurrentOnBattery ?? false;
        var lidClosed = PowerState.CurrentLidClosed ?? false;
        var decisionKey = $"{onBattery}:{lidClosed}";

        if (decisionKey == PowerState.LastDecisionKey)
        {
            return;
        }

        PowerState.LastDecisionKey = decisionKey;

        var tempStr = TemperatureReporter.GetTemperatures();
        var ts = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);

        string msg;
        if (!onBattery && !lidClosed)
        {
            msg = $"{ts}: Abort ... - The PC is running on AC power, and the lid is open. [{tempStr}]";
        }
        else if (onBattery && !lidClosed)
        {
            msg = $"{ts}: Abort ... - The PC is running on battery power, but the lid is open. [{tempStr}]";
        }
        else if (!onBattery && lidClosed)
        {
            msg = $"{ts}: Abort ... - The PC is running on AC power, and the lid is closed. [{tempStr}]";
        }
        else
        {
            var actionLabel = s_options.SuspendMode == SuspendMode.Sleep ? "Sleeping" : "Hibernating";
            msg = $"{ts}: {actionLabel} ... - The PC is running on battery power, and the lid is closed. [{tempStr}]";
        }

        WriteLog(msg);

        if (onBattery && lidClosed)
        {
            Thread.Sleep(1000);

            if (s_options.SuspendMode == SuspendMode.Sleep)
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "rundll32.exe",
                    Arguments = "powrprof.dll,SetSuspendState 0,1,0",
                    CreateNoWindow = true,
                    UseShellExecute = false
                });
            }
            else
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "shutdown.exe",
                    Arguments = "/h",
                    CreateNoWindow = true,
                    UseShellExecute = false
                });
            }
        }
    }

    private static void WriteLog(string message)
    {
        Console.WriteLine(message);
        var logPath = Path.Combine(AppContext.BaseDirectory, "check_false_consciesnous.log");
        File.AppendAllText(logPath, message + Environment.NewLine, Encoding.UTF8);
    }
}

internal sealed record AppOptions(int RefreshIntervalMs, SuspendMode SuspendMode)
{
    public static AppOptions Default => new(20000, SuspendMode.Hibernate);

    public static AppOptions Parse(string[] args)
    {
        var intervalMs = Default.RefreshIntervalMs;
        var suspendMode = Default.SuspendMode;

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];

            if (arg.Equals("--interval-ms", StringComparison.OrdinalIgnoreCase) || arg.Equals("-i", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 < args.Length && int.TryParse(args[i + 1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
                {
                    intervalMs = parsed;
                    i++;
                }

                continue;
            }

            if (arg.Equals("--action", StringComparison.OrdinalIgnoreCase) || arg.Equals("-a", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 < args.Length)
                {
                    suspendMode = ParseSuspendMode(args[i + 1], suspendMode);
                    i++;
                }

                continue;
            }

            if (int.TryParse(arg, NumberStyles.Integer, CultureInfo.InvariantCulture, out var positionalInterval))
            {
                intervalMs = positionalInterval;
            }
        }

        intervalMs = Math.Clamp(intervalMs, 250, 60000);
        return new AppOptions(intervalMs, suspendMode);
    }

    private static SuspendMode ParseSuspendMode(string value, SuspendMode fallback)
    {
        if (value.Equals("sleep", StringComparison.OrdinalIgnoreCase))
        {
            return SuspendMode.Sleep;
        }

        if (value.Equals("hibernate", StringComparison.OrdinalIgnoreCase) || value.Equals("shutdown", StringComparison.OrdinalIgnoreCase) || value.Equals("shutdownh", StringComparison.OrdinalIgnoreCase))
        {
            return SuspendMode.Hibernate;
        }

        return fallback;
    }
}

internal enum SuspendMode
{
    Sleep,
    Hibernate
}

internal static class PowerState
{
    public static bool? CurrentOnBattery { get; set; }
    public static bool? CurrentLidClosed { get; set; }
    public static string? LastDecisionKey { get; set; }

    public static bool ReadOnBattery()
    {
        var status = new NativePower.SystemPowerStatus();
        if (!NativePower.GetSystemPowerStatus(out status))
        {
            return true;
        }

        return status.ACLineStatus == 0;
    }
}

internal static class TemperatureReporter
{
    public static string GetTemperatures()
    {
        var cpu = ReadTemperatureByKeywords(new[] { "CPU", "PROC", "CORE" }, fallbackIndex: 0);
        var gpu = ReadGpuTemperature();
        var mb = ReadTemperatureByKeywords(new[] { "MB", "SYS", "BOARD" }, fallbackIndex: 1);

        return $"CPU: {cpu} | GPU: {gpu} | MB: {mb}";
    }

    private static string ReadTemperatureByKeywords(string[] keywords, int fallbackIndex)
    {
        try
        {
            var zones = ReadThermalZones();
            if (zones.Count == 0)
            {
                return "N/A";
            }

            var matched = zones.FirstOrDefault(zone =>
            {
                var name = zone.InstanceName.ToUpperInvariant();
                return keywords.Any(keyword => name.Contains(keyword, StringComparison.OrdinalIgnoreCase));
            });

            if (matched is not null)
            {
                return $"{RoundCelsius(matched.CurrentTemperature)}°C";
            }

            var sorted = zones
                .Select(zone => RoundCelsius(zone.CurrentTemperature))
                .OrderByDescending(v => v)
                .ToArray();

            if (sorted.Length > fallbackIndex)
            {
                return $"{sorted[fallbackIndex]}°C";
            }
        }
        catch
        {
        }

        return "N/A";
    }

    private static string ReadGpuTemperature()
    {
        try
        {
            var output = RunPowerShell(
                "-NoProfile",
                "-Command",
                "try { $v = (nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null); if ($LASTEXITCODE -eq 0 -and $v) { [Console]::Write($v.Trim()) } } catch {}"
            );

            if (!string.IsNullOrWhiteSpace(output))
            {
                return $"{output.Trim()}°C";
            }
        }
        catch
        {
        }

        return "N/A";
    }

    private static List<ThermalZone> ReadThermalZones()
    {
        var output = RunPowerShell(
            "-NoProfile",
            "-Command",
            "try { Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | ForEach-Object { Write-Output (($_.CurrentTemperature.ToString()) + '|' + ($_.InstanceName.ToString())) } } catch {}"
        );

        var zones = new List<ThermalZone>();
        var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var line in lines)
        {
            var parts = line.Split('|', 2);
            if (parts.Length != 2)
            {
                continue;
            }

            if (int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var currentTemperature))
            {
                zones.Add(new ThermalZone(currentTemperature, parts[1]));
            }
        }

        return zones;
    }

    private static double RoundCelsius(int currentTemperature)
    {
        return Math.Round((currentTemperature - 2732) / 10.0, 1);
    }

    private static string RunPowerShell(params string[] args)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = string.Join(" ", args.Select(QuoteArgument)),
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        process.Start();
        var output = process.StandardOutput.ReadToEnd();
        _ = process.StandardError.ReadToEnd();
        process.WaitForExit();
        return output;
    }

    private static string QuoteArgument(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "\"\"";
        }

        if (value.Contains(' ') || value.Contains('"'))
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        return value;
    }

    private sealed record ThermalZone(int CurrentTemperature, string InstanceName);
}

internal sealed class PowerSettingChangedEventArgs : EventArgs
{
    public PowerSettingChangedEventArgs(Guid powerSetting, uint data)
    {
        PowerSetting = powerSetting;
        Data = data;
    }

    public Guid PowerSetting { get; }
    public uint Data { get; }
}

internal sealed class PowerNotificationForm : Form
{
    private const uint WM_POWERBROADCAST = 0x0218;
    private const uint PBT_POWERSETTINGCHANGE = 0x8013;
    private const uint DEVICE_NOTIFY_WINDOW_HANDLE = 0x00000000;

    private IntPtr _lidNotifyHandle = IntPtr.Zero;
    private IntPtr _powerNotifyHandle = IntPtr.Zero;
    private bool _notificationsRegistered;

    public event EventHandler<PowerSettingChangedEventArgs>? PowerSettingChanged;

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct POWERBROADCAST_SETTING
    {
        public Guid PowerSetting;
        public uint DataLength;
        public uint Data;
    }

    [DllImport("User32.dll", SetLastError = true)]
    private static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid PowerSettingGuid, uint Flags);

    [DllImport("User32.dll", SetLastError = true)]
    private static extern bool UnregisterPowerSettingNotification(IntPtr Handle);

    public PowerNotificationForm()
    {
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        WindowState = FormWindowState.Minimized;
        Opacity = 0;
    }

    public void StartNotifications()
    {
        if (_notificationsRegistered)
        {
            return;
        }

        var lidGuid = Program.LidSwitchGuid;
        var powerGuid = Program.AcDcPowerSourceGuid;

        _lidNotifyHandle = RegisterPowerSettingNotification(Handle, ref lidGuid, DEVICE_NOTIFY_WINDOW_HANDLE);
        if (_lidNotifyHandle == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "RegisterPowerSettingNotification for lid state failed.");
        }

        _powerNotifyHandle = RegisterPowerSettingNotification(Handle, ref powerGuid, DEVICE_NOTIFY_WINDOW_HANDLE);
        if (_powerNotifyHandle == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "RegisterPowerSettingNotification for power source failed.");
        }

        _notificationsRegistered = true;
    }

    protected override void SetVisibleCore(bool value)
    {
        base.SetVisibleCore(false);
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        if (_lidNotifyHandle != IntPtr.Zero)
        {
            UnregisterPowerSettingNotification(_lidNotifyHandle);
            _lidNotifyHandle = IntPtr.Zero;
        }

        if (_powerNotifyHandle != IntPtr.Zero)
        {
            UnregisterPowerSettingNotification(_powerNotifyHandle);
            _powerNotifyHandle = IntPtr.Zero;
        }

        _notificationsRegistered = false;
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_POWERBROADCAST && m.WParam.ToInt64() == PBT_POWERSETTINGCHANGE && m.LParam != IntPtr.Zero)
        {
            var setting = Marshal.PtrToStructure<POWERBROADCAST_SETTING>(m.LParam);
            PowerSettingChanged?.Invoke(this, new PowerSettingChangedEventArgs(setting.PowerSetting, setting.Data));
        }

        base.WndProc(ref m);
    }
}

internal static class NativePower
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct SystemPowerStatus
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    [DllImport("Kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetSystemPowerStatus(out SystemPowerStatus sps);
}
