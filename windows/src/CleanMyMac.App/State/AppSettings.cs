using System.Text.Json;
using CleanMyMac.Localization;
using DiskKit;

namespace CleanMyMac.State;

public enum ExternalDriveBehavior { Ask, Always, Never }

/// <summary>User preferences, saved as JSON in %LOCALAPPDATA%\CleanMyMac\settings.json.</summary>
public sealed class AppSettings
{
    public AppLanguage Language { get; set; } = AppLanguage.System;
    public ExternalDriveBehavior ExternalDrives { get; set; } = ExternalDriveBehavior.Ask;
    public int LargeFileMinimumMB { get; set; } = 100;
    public bool HasCompletedOnboarding { get; set; }
    public long CriticalFreeBytes { get; set; } = HealthPolicy.Default.CriticalFreeBytes;
    public double CriticalFreeRatio { get; set; } = HealthPolicy.Default.CriticalFreeRatio;
    public long WarningFreeBytes { get; set; } = HealthPolicy.Default.WarningFreeBytes;
    public double WarningFreeRatio { get; set; } = HealthPolicy.Default.WarningFreeRatio;
    public long DuplicateMinimumSize { get; set; } = ByteFormatter.Megabyte;
    public bool DuplicateSkipDeveloper { get; set; } = true;
    public bool DuplicateSkipSystem { get; set; } = true;

    public HealthPolicy Policy => new(CriticalFreeBytes, CriticalFreeRatio, WarningFreeBytes, WarningFreeRatio);
    public DuplicateOptions DuplicateOptions => new(DuplicateMinimumSize, DuplicateSkipDeveloper, DuplicateSkipSystem);
    public long LargeFileMinimumBytes => LargeFileMinimumMB * ByteFormatter.Megabyte;

    private static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CleanMyMac", "settings.json");

    public static AppSettings Load()
    {
        try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings(); }
        catch { return new AppSettings(); }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* settings are a convenience; never crash on save */ }
    }

    public void ResetToDefaults()
    {
        var d = new AppSettings();
        ExternalDrives = d.ExternalDrives;
        LargeFileMinimumMB = d.LargeFileMinimumMB;
        CriticalFreeBytes = d.CriticalFreeBytes;
        CriticalFreeRatio = d.CriticalFreeRatio;
        WarningFreeBytes = d.WarningFreeBytes;
        WarningFreeRatio = d.WarningFreeRatio;
        DuplicateMinimumSize = d.DuplicateMinimumSize;
        DuplicateSkipDeveloper = d.DuplicateSkipDeveloper;
        DuplicateSkipSystem = d.DuplicateSkipSystem;
        Save();
    }
}
