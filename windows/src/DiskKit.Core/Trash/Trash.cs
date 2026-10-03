using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text.Json;

namespace DiskKit;

public enum ProtectionReason { SystemLocation, EssentialFolder, VolumeRoot, ApplicationItself, NotAbsolute }

/// <summary>Paths the app will never send to the Recycle Bin.</summary>
public sealed class TrashGuard
{
    private readonly WindowsPaths _paths;
    private readonly string? _appDirectory;
    private readonly HashSet<string> _essential;
    private readonly string[] _systemPrefixes;

    public TrashGuard(WindowsPaths? paths = null, string? appDirectory = null)
    {
        _paths = paths ?? WindowsPaths.Current();
        _appDirectory = appDirectory ?? AppContext.BaseDirectory.TrimEnd('\\', '/');
        var p = _paths;
        var drive = Path.GetPathRoot(p.WindowsDir)?.TrimEnd('\\') ?? "C:";
        _systemPrefixes = new[]
        {
            p.WindowsDir, p.ProgramData, $@"{drive}\System Volume Information", $@"{drive}\Recovery", $@"{drive}\Boot",
            $@"{drive}\$Recycle.Bin", $@"{drive}\Program Files\WindowsApps",
        };
        _essential = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            p.ProgramFiles, p.ProgramFilesX86, $@"{drive}\Users", p.UserProfile,
            $@"{p.UserProfile}\Desktop", $@"{p.UserProfile}\Documents", $@"{p.UserProfile}\Downloads", $@"{p.UserProfile}\Pictures",
            $@"{p.UserProfile}\Videos", $@"{p.UserProfile}\Music", $@"{p.UserProfile}\AppData", p.LocalAppData, p.RoamingAppData,
            $@"{p.UserProfile}\OneDrive", $@"{drive}\pagefile.sys", $@"{drive}\hiberfil.sys", $@"{drive}\swapfile.sys",
        };
    }

    public ProtectionReason? Check(string rawPath)
    {
        if (!Path.IsPathFullyQualified(rawPath)) return ProtectionReason.NotAbsolute;
        var path = Path.GetFullPath(rawPath).TrimEnd('\\', '/');
        if (path.Length <= 3 || Path.GetPathRoot(path)?.TrimEnd('\\', '/').Equals(path, StringComparison.OrdinalIgnoreCase) == true)
            return ProtectionReason.VolumeRoot;
        if (_appDirectory is { Length: > 3 } app && (path.Equals(app, StringComparison.OrdinalIgnoreCase) || path.StartsWith(app + "\\", StringComparison.OrdinalIgnoreCase)))
            return ProtectionReason.ApplicationItself;
        foreach (var prefix in _systemPrefixes)
            if (path.Equals(prefix, StringComparison.OrdinalIgnoreCase) || path.StartsWith(prefix + "\\", StringComparison.OrdinalIgnoreCase))
                return ProtectionReason.SystemLocation;
        if (_essential.Contains(path)) return ProtectionReason.EssentialFolder;
        return null;
    }

    public bool IsAllowed(string path) => Check(path) is null;
}

public sealed record TrashOutcome(string Path, bool Succeeded, string? Error);

/// <summary>Sends items to the Recycle Bin via the Windows shell (never deletes permanently from here).</summary>
public sealed class RecycleBinService
{
    private readonly TrashGuard _guard;

    public RecycleBinService(TrashGuard? guard = null) => _guard = guard ?? new TrashGuard();

    public IReadOnlyList<TrashOutcome> MoveToRecycleBin(IEnumerable<string> paths) =>
        paths.Select(path =>
        {
            if (!_guard.IsAllowed(path)) return new TrashOutcome(path, false, "protected");
            if (!OperatingSystem.IsWindows()) return new TrashOutcome(path, false, "unsupported platform");
            if (!File.Exists(path) && !Directory.Exists(path)) return new TrashOutcome(path, false, "not found");
            var op = new SHFILEOPSTRUCT
            {
                wFunc = FO_DELETE,
                pFrom = path + "\0\0",
                fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI | FOF_WANTNUKEWARNING,
            };
            var code = SHFileOperationW(ref op);
            var ok = code == 0 && !op.fAnyOperationsAborted && !File.Exists(path) && !Directory.Exists(path);
            return new TrashOutcome(path, ok, ok ? null : $"error 0x{code:X}");
        }).ToList();

    private const uint FO_DELETE = 3;
    private const ushort FOF_SILENT = 0x0004;
    private const ushort FOF_NOCONFIRMATION = 0x0010;
    private const ushort FOF_ALLOWUNDO = 0x0040;
    private const ushort FOF_NOERRORUI = 0x0400;
    /// <summary>Makes the shell abort instead of deleting permanently when the item cannot go to the Recycle Bin.</summary>
    private const ushort FOF_WANTNUKEWARNING = 0x4000;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperationW(ref SHFILEOPSTRUCT op);
}

public enum DeletionKind { File, Folder, DockerImage }

public sealed record DeletionRecord(Guid Id, DateTime DateUtc, DeletionKind Kind, string Path, long Bytes);

/// <summary>History of what the app removed (JSON in %LOCALAPPDATA%\CleanMyMac).</summary>
public sealed class DeletionLog
{
    public const int MaximumRecords = 2000;
    private readonly string _file;
    private readonly object _lock = new();
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public DeletionLog(string file) => _file = file;

    public static string DefaultLocation() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CleanMyMac", "deletion-log.json");

    public IReadOnlyList<DeletionRecord> Load()
    {
        lock (_lock)
        {
            try { return JsonSerializer.Deserialize<List<DeletionRecord>>(File.ReadAllText(_file)) ?? new(); }
            catch { return new List<DeletionRecord>(); }
        }
    }

    public IReadOnlyList<DeletionRecord> Append(IEnumerable<DeletionRecord> records)
    {
        var all = Load().ToList();
        lock (_lock)
        {
            all.InsertRange(0, records.Reverse());
            if (all.Count > MaximumRecords) all.RemoveRange(MaximumRecords, all.Count - MaximumRecords);
            Save(all);
            return all;
        }
    }

    public void Clear()
    {
        lock (_lock) Save(new List<DeletionRecord>());
    }

    private void Save(List<DeletionRecord> records)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_file)!);
        var temp = _file + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(records, Json));
        File.Move(temp, _file, overwrite: true);
    }
}

/// <summary>Windows replaces macOS "Full Disk Access" with running as Administrator.</summary>
public static class Elevation
{
    public static bool IsElevated()
    {
        if (!OperatingSystem.IsWindows()) return true;
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
}
