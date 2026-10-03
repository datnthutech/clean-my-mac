using System.Runtime.InteropServices;

namespace DiskKit;

public enum VolumeKind
{
    /// <summary>The drive Windows runs from (usually C:).</summary>
    System,
    /// <summary>Another internal drive/partition.</summary>
    Internal,
    /// <summary>USB stick, SD card, external SSD/HDD.</summary>
    External,
}

public sealed record VolumeInfo(
    string Name,
    string Path,
    VolumeKind Kind,
    string Format,
    long TotalBytes,
    long AvailableBytes,
    bool IsRemovable)
{
    public string Id => Path;
    public long UsedBytes => Math.Max(0, TotalBytes - AvailableBytes);
    public double FreeRatio => TotalBytes > 0 ? (double)AvailableBytes / TotalBytes : 0;
    public double UsedRatio => 1 - FreeRatio;
    public bool IsExternal => Kind == VolumeKind.External;
    /// <summary>Removable media (USB sticks, SD cards) have no Recycle Bin: deleting is permanent.</summary>
    public bool HasRecycleBin => !IsRemovable;
}

/// <summary>Raw facts about a drive, separated from <see cref="DriveInfo"/> so the rules are testable.</summary>
public sealed record DriveFacts(string Path, string Label, DriveType Type, bool IsReady, bool IsSystemDrive, bool IsUsbBus, string Format, long Total, long Free);

public static class VolumeClassifier
{
    /// <summary>Returns null for drives the app does not show: network, optical, RAM disks, not-ready drives.</summary>
    public static VolumeKind? Classify(DriveFacts d)
    {
        if (!d.IsReady || d.Total <= 0) return null;
        if (d.IsSystemDrive) return VolumeKind.System;
        return d.Type switch
        {
            DriveType.Removable => VolumeKind.External,
            DriveType.Fixed => d.IsUsbBus ? VolumeKind.External : VolumeKind.Internal,
            _ => null,
        };
    }
}

public sealed class VolumeService
{
    public IReadOnlyList<VolumeInfo> MountedVolumes()
    {
        var systemRoot = System.IO.Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\";
        var result = new List<VolumeInfo>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            DriveFacts facts;
            try
            {
                var ready = drive.IsReady;
                facts = new DriveFacts(
                    drive.Name,
                    ready ? drive.VolumeLabel : "",
                    drive.DriveType,
                    ready,
                    string.Equals(drive.Name, systemRoot, StringComparison.OrdinalIgnoreCase) || (!OperatingSystem.IsWindows() && drive.Name == "/"),
                    OperatingSystem.IsWindows() && drive.DriveType == DriveType.Fixed && UsbBus.IsUsb(drive.Name),
                    ready ? drive.DriveFormat : "",
                    ready ? drive.TotalSize : 0,
                    ready ? drive.AvailableFreeSpace : 0);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (VolumeClassifier.Classify(facts) is not { } kind) continue;
            var letter = facts.Path.TrimEnd('\\');
            var name = string.IsNullOrWhiteSpace(facts.Label) ? letter : $"{facts.Label} ({letter})";
            result.Add(new VolumeInfo(name, facts.Path, kind, facts.Format, facts.Total, facts.Free, facts.Type == DriveType.Removable));
        }
        return result.OrderBy(v => v.Kind).ThenBy(v => v.Path, StringComparer.OrdinalIgnoreCase).ToList();
    }

    public ScanTarget TargetFor(VolumeInfo volume)
    {
        // System files that are huge but not files you can clean show up as their own items;
        // nothing is excluded so totals match what the drive really holds.
        return new ScanTarget(volume.Path);
    }
}

/// <summary>Asks the storage driver which bus a drive sits on, so external USB SSDs (reported as "Fixed") count as external.</summary>
internal static class UsbBus
{
    private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
    private const int BusTypeUsb = 7;

    [StructLayout(LayoutKind.Sequential)]
    private struct StoragePropertyQuery
    {
        public int PropertyId;
        public int QueryType;
        public byte AdditionalParameters;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(Microsoft.Win32.SafeHandles.SafeFileHandle device, uint code, ref StoragePropertyQuery input, int inputSize, byte[] output, int outputSize, out int returned, IntPtr overlapped);

    public static bool IsUsb(string root)
    {
        try
        {
            var device = @"\\.\" + root.TrimEnd('\\');
            using var handle = CreateFileW(device, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (handle.IsInvalid) return false;
            var query = new StoragePropertyQuery { PropertyId = 0, QueryType = 0 };
            var buffer = new byte[1024];
            if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, ref query, Marshal.SizeOf<StoragePropertyQuery>(), buffer, buffer.Length, out var returned, IntPtr.Zero) || returned < 32)
                return false;
            // STORAGE_DEVICE_DESCRIPTOR.BusType is the 32-bit value at offset 28.
            return BitConverter.ToInt32(buffer, 28) == BusTypeUsb;
        }
        catch
        {
            return false;
        }
    }
}
