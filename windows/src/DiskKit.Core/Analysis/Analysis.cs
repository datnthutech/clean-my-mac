using System.Text;

namespace DiskKit;

/// <summary>"What is this space used for?" — same buckets as the macOS app.</summary>
public enum StorageCategory
{
    Applications, Documents, Media, Music, Archives, Developer, Caches, IosBackups, Mail, Trash, Docker, System, Other,
}

/// <summary>Well-known Windows locations that are often large and safe(ish) to clean.</summary>
public enum HotspotKind
{
    WindowsTemp, UserTemp, WindowsUpdateCache, WindowsOld, RecycleBin, BrowserCaches, NodeModules, Downloads,
    IosBackups, NuGetCache, NpmCache, VisualStudioCache,
}

public sealed record Hotspot(HotspotKind Kind, string Path, long Bytes, int ItemCount);

public sealed record CategoryReport(IReadOnlyDictionary<StorageCategory, long> Totals, IReadOnlyList<Hotspot> Hotspots)
{
    public IReadOnlyList<(StorageCategory Category, long Bytes)> Sorted =>
        Totals.Where(t => t.Value > 0).OrderByDescending(t => t.Value).Select(t => (t.Key, t.Value)).ToList();

    public long CategorizedBytes => Totals.Values.Sum();
}

/// <summary>Known Windows folders, resolved against the drive being scanned.</summary>
public sealed record WindowsPaths(string WindowsDir, string ProgramFiles, string ProgramFilesX86, string ProgramData, string UserProfile, string LocalAppData, string RoamingAppData)
{
    public static WindowsPaths Current() => new(
        Environment.GetFolderPath(Environment.SpecialFolder.Windows),
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));

    /// <summary>Typical layout for tests: C:\Windows, C:\Users\{user}…</summary>
    public static WindowsPaths ForUser(string drive, string user) => new(
        $@"{drive}\Windows", $@"{drive}\Program Files", $@"{drive}\Program Files (x86)", $@"{drive}\ProgramData",
        $@"{drive}\Users\{user}", $@"{drive}\Users\{user}\AppData\Local", $@"{drive}\Users\{user}\AppData\Roaming");
}

/// <summary>Assigns every file to a category using folder rules first, then the file extension.</summary>
public sealed class Categorizer
{
    private readonly Dictionary<string, StorageCategory> _pathRules = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, HotspotKind> _hotspots = new(StringComparer.OrdinalIgnoreCase);

    public Categorizer(WindowsPaths? paths = null)
    {
        var p = paths ?? WindowsPaths.Current();
        var drive = System.IO.Path.GetPathRoot(p.WindowsDir)?.TrimEnd('\\') ?? "C:";
        void Rule(string path, StorageCategory c) { if (!string.IsNullOrEmpty(path)) _pathRules[path] = c; }
        void Spot(string path, HotspotKind k) { if (!string.IsNullOrEmpty(path)) _hotspots[path] = k; }

        Rule(p.ProgramFiles, StorageCategory.Applications);
        Rule(p.ProgramFilesX86, StorageCategory.Applications);
        Rule($@"{p.LocalAppData}\Programs", StorageCategory.Applications);
        Rule($@"{p.LocalAppData}\Microsoft\WindowsApps", StorageCategory.Applications);
        Rule($@"{drive}\Program Files\WindowsApps", StorageCategory.Applications);

        Rule(p.WindowsDir, StorageCategory.System);
        Rule(p.ProgramData, StorageCategory.System);
        Rule($@"{drive}\System Volume Information", StorageCategory.System);
        Rule($@"{drive}\Recovery", StorageCategory.System);
        Rule($@"{drive}\Windows.old", StorageCategory.System);

        Rule($@"{p.LocalAppData}\Temp", StorageCategory.Caches);
        Rule($@"{p.WindowsDir}\Temp", StorageCategory.Caches);
        Rule($@"{p.WindowsDir}\SoftwareDistribution\Download", StorageCategory.Caches);
        Rule($@"{p.LocalAppData}\Google\Chrome\User Data\Default\Cache", StorageCategory.Caches);
        Rule($@"{p.LocalAppData}\Microsoft\Edge\User Data\Default\Cache", StorageCategory.Caches);
        Rule($@"{p.LocalAppData}\Mozilla\Firefox\Profiles", StorageCategory.Caches);

        Rule($@"{p.UserProfile}\.nuget", StorageCategory.Developer);
        Rule($@"{p.LocalAppData}\npm-cache", StorageCategory.Developer);
        Rule($@"{p.RoamingAppData}\npm-cache", StorageCategory.Developer);
        Rule($@"{p.UserProfile}\.gradle", StorageCategory.Developer);
        Rule($@"{p.UserProfile}\.m2", StorageCategory.Developer);
        Rule($@"{p.UserProfile}\.cargo", StorageCategory.Developer);
        Rule($@"{p.UserProfile}\.rustup", StorageCategory.Developer);
        Rule($@"{p.LocalAppData}\Android", StorageCategory.Developer);
        Rule($@"{p.LocalAppData}\Microsoft\VisualStudio", StorageCategory.Developer);
        Rule($@"{p.ProgramData}\Package Cache", StorageCategory.Developer);

        Rule($@"{p.LocalAppData}\Docker", StorageCategory.Docker);
        Rule($@"{p.ProgramData}\DockerDesktop", StorageCategory.Docker);
        Rule($@"{p.UserProfile}\.docker", StorageCategory.Docker);

        Rule($@"{p.RoamingAppData}\Apple Computer\MobileSync\Backup", StorageCategory.IosBackups);
        Rule($@"{p.UserProfile}\Apple\MobileSync\Backup", StorageCategory.IosBackups);
        Rule($@"{p.LocalAppData}\Microsoft\Outlook", StorageCategory.Mail);
        Rule($@"{p.LocalAppData}\Packages\microsoft.windowscommunicationsapps_8wekyb3d8bbwe", StorageCategory.Mail);
        Rule($@"{drive}\$Recycle.Bin", StorageCategory.Trash);

        Spot($@"{p.WindowsDir}\Temp", HotspotKind.WindowsTemp);
        Spot($@"{p.LocalAppData}\Temp", HotspotKind.UserTemp);
        Spot($@"{p.WindowsDir}\SoftwareDistribution\Download", HotspotKind.WindowsUpdateCache);
        Spot($@"{drive}\Windows.old", HotspotKind.WindowsOld);
        Spot($@"{drive}\$Recycle.Bin", HotspotKind.RecycleBin);
        Spot($@"{p.LocalAppData}\Google\Chrome\User Data\Default\Cache", HotspotKind.BrowserCaches);
        Spot($@"{p.LocalAppData}\Microsoft\Edge\User Data\Default\Cache", HotspotKind.BrowserCaches);
        Spot($@"{p.UserProfile}\Downloads", HotspotKind.Downloads);
        Spot($@"{p.RoamingAppData}\Apple Computer\MobileSync\Backup", HotspotKind.IosBackups);
        Spot($@"{p.UserProfile}\Apple\MobileSync\Backup", HotspotKind.IosBackups);
        Spot($@"{p.UserProfile}\.nuget\packages", HotspotKind.NuGetCache);
        Spot($@"{p.LocalAppData}\npm-cache", HotspotKind.NpmCache);
        Spot($@"{p.RoamingAppData}\npm-cache", HotspotKind.NpmCache);
        Spot($@"{p.ProgramData}\Package Cache", HotspotKind.VisualStudioCache);
    }

    private static readonly Dictionary<string, StorageCategory> ExtensionMap = BuildExtensionMap();

    private static Dictionary<string, StorageCategory> BuildExtensionMap()
    {
        var map = new Dictionary<string, StorageCategory>(StringComparer.OrdinalIgnoreCase);
        void Add(StorageCategory c, string list) { foreach (var e in list.Split(' ')) map[e] = c; }
        Add(StorageCategory.Documents, "pdf doc docx xls xlsx ppt pptx txt rtf md csv odt ods odp epub json xml html htm one");
        Add(StorageCategory.Media, "jpg jpeg png heic heif gif tiff tif bmp raw cr2 cr3 nef arw dng psd svg webp mov mp4 m4v avi mkv wmv flv webm mts");
        Add(StorageCategory.Music, "mp3 m4a aac wav flac aiff aif ogg wma mid midi");
        Add(StorageCategory.Archives, "zip rar 7z tar gz tgz bz2 xz iso img msi msix appx cab dmg apk");
        Add(StorageCategory.Developer, "obj pdb lib ilk pch class jar pyc nupkg");
        Add(StorageCategory.Applications, "exe dll");
        Add(StorageCategory.Mail, "pst ost");
        return map;
    }

    public static StorageCategory CategoryForFile(string name) =>
        ExtensionMap.TryGetValue(System.IO.Path.GetExtension(name).TrimStart('.'), out var c) ? c : StorageCategory.Other;

    internal static StorageCategory? CategoryForDirectoryName(string name) => name.ToLowerInvariant() switch
    {
        "node_modules" or ".git" or ".vs" or "__pycache__" or ".venv" or "venv" => StorageCategory.Developer,
        "$recycle.bin" => StorageCategory.Trash,
        _ => null,
    };

    /// <summary>Huge Windows system files at the drive root, reported as System even though they sit outside \Windows.</summary>
    private static readonly HashSet<string> RootSystemFiles = new(StringComparer.OrdinalIgnoreCase) { "pagefile.sys", "hiberfil.sys", "swapfile.sys", "DumpStack.log.tmp" };

    public CategoryReport Report(DirectoryNode root)
    {
        var totals = new Dictionary<StorageCategory, long>();
        var spots = new Dictionary<HotspotKind, (string Path, long Bytes, int Count, long Largest)>();
        void Add(StorageCategory c, long b) => totals[c] = totals.GetValueOrDefault(c) + b;

        var stack = new Stack<(DirectoryNode Node, StorageCategory? Inherited)>();
        stack.Push((root, _pathRules.TryGetValue(root.Path.TrimEnd('\\'), out var rc) ? rc : null));
        while (stack.Count > 0)
        {
            var (node, inherited) = stack.Pop();
            if (_hotspots.TryGetValue(node.Path, out var hk) && node.AllocatedSize > 0)
            {
                var prev = spots.GetValueOrDefault(hk);
                spots[hk] = (prev.Bytes >= node.AllocatedSize ? prev.Path : node.Path, prev.Bytes + node.AllocatedSize, prev.Count + node.FileCount, 0);
            }
            if (string.Equals(node.Name, "node_modules", StringComparison.OrdinalIgnoreCase))
            {
                var prev = spots.GetValueOrDefault(HotspotKind.NodeModules);
                var largestPath = node.AllocatedSize > prev.Largest ? node.Path : prev.Path;
                spots[HotspotKind.NodeModules] = (largestPath, prev.Bytes + node.AllocatedSize, prev.Count + 1, Math.Max(prev.Largest, node.AllocatedSize));
                Add(inherited ?? StorageCategory.Developer, node.AllocatedSize);
                continue;
            }
            var isRoot = node.Parent is null;
            foreach (var f in node.Files)
            {
                var category = inherited ?? (isRoot && RootSystemFiles.Contains(f.Name) ? StorageCategory.System : CategoryForFile(f.Name));
                Add(category, f.AllocatedSize);
            }
            foreach (var child in node.Directories)
            {
                StorageCategory? forced = _pathRules.TryGetValue(child.Path, out var c) ? c : null;
                forced ??= inherited is null ? CategoryForDirectoryName(child.Name) : null;
                stack.Push((child, forced ?? inherited));
            }
        }
        var hotspots = spots.Select(s => new Hotspot(s.Key, s.Value.Path, s.Value.Bytes, s.Value.Count)).OrderByDescending(h => h.Bytes).ToList();
        return new CategoryReport(totals, hotspots);
    }
}

public sealed record LargeFile(string Path, string Name, long AllocatedSize, DateTime ModifiedUtc, StorageCategory Category);

public static class LargeFileFinder
{
    public static IReadOnlyList<LargeFile> Largest(DirectoryNode root, long minimumSize = 100 * ByteFormatter.Megabyte, int limit = 200)
    {
        var found = new List<LargeFile>();
        root.ForEachFile((dir, f) =>
        {
            if (f.AllocatedSize >= minimumSize)
                found.Add(new LargeFile(dir.ChildPath(f.Name), f.Name, f.AllocatedSize, f.ModifiedUtc, Categorizer.CategoryForFile(f.Name)));
        });
        return found.OrderByDescending(f => f.AllocatedSize).Take(limit).ToList();
    }
}

public sealed record DuplicateOptions(
    long MinimumSize = ByteFormatter.Megabyte,
    bool SkipDeveloperFolders = true,
    bool SkipSystemFolders = true,
    bool SkipHiddenFiles = true)
{
    public static readonly HashSet<string> DeveloperFolderNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "node_modules", ".git", ".svn", ".hg", "bin", "obj", ".vs", "packages", "build", "target", "__pycache__", ".venv", "venv",
        "vendor", "$Recycle.Bin", "System Volume Information",
    };
}

public sealed record DuplicateFile(string Path, string VolumeName, long AllocatedSize, DateTime ModifiedUtc);

/// <summary>Files sharing the same name (case-insensitive, Unicode-normalized). Newest first.</summary>
public sealed record DuplicateGroup(string Key, string DisplayName, IReadOnlyList<DuplicateFile> Files)
{
    public long TotalSize => Files.Sum(f => f.AllocatedSize);
    /// <summary>Space freed by keeping only the newest copy.</summary>
    public long ReclaimableSize => TotalSize - (Files.Count > 0 ? Files[0].AllocatedSize : 0);
    public DuplicateFile? Newest => Files.Count > 0 ? Files[0] : null;
}

public sealed record DuplicateSource(string VolumeName, DirectoryNode Root);

public static class DuplicateFinder
{
    public static string NormalizedKey(string name) => name.Normalize(NormalizationForm.FormC).ToLowerInvariant();

    public static IReadOnlyList<DuplicateGroup> Find(IEnumerable<DuplicateSource> sources, DuplicateOptions? options = null, WindowsPaths? paths = null)
    {
        options ??= new DuplicateOptions();
        var p = paths ?? WindowsPaths.Current();
        var blocked = options.SkipSystemFolders
            ? new HashSet<string>(StringComparer.OrdinalIgnoreCase)
              { p.WindowsDir, p.ProgramFiles, p.ProgramFilesX86, p.ProgramData, $@"{p.UserProfile}\AppData" }
            : new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        var buckets = new Dictionary<string, List<DuplicateFile>>();
        foreach (var source in sources)
        {
            source.Root.ForEachFile((dir, f) =>
            {
                if (f.AllocatedSize < options.MinimumSize) return;
                if (options.SkipHiddenFiles && f.Name.StartsWith('.')) return;
                var key = NormalizedKey(f.Name);
                if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = new List<DuplicateFile>();
                list.Add(new DuplicateFile(dir.ChildPath(f.Name), source.VolumeName, f.AllocatedSize, f.ModifiedUtc));
            }, dir =>
                !dir.IsPackage
                && !(options.SkipDeveloperFolders && DuplicateOptions.DeveloperFolderNames.Contains(dir.Name))
                && !(options.SkipHiddenFiles && dir.Name.StartsWith('.'))
                && !blocked.Contains(dir.Path));
        }

        return buckets.Where(b => b.Value.Count >= 2)
            .Select(b =>
            {
                var files = b.Value.OrderByDescending(f => f.ModifiedUtc).ThenBy(f => f.Path, StringComparer.Ordinal).ToList();
                return new DuplicateGroup(b.Key, System.IO.Path.GetFileName(files[0].Path).Normalize(NormalizationForm.FormC), files);
            })
            .OrderByDescending(g => g.ReclaimableSize).ThenBy(g => g.Key, StringComparer.Ordinal)
            .ToList();
    }

    public static IReadOnlyList<DuplicateGroup> Removing(ISet<string> paths, IEnumerable<DuplicateGroup> groups) =>
        groups.Select(g => g with { Files = g.Files.Where(f => !paths.Contains(f.Path)).ToList() })
            .Where(g => g.Files.Count >= 2)
            .OrderByDescending(g => g.ReclaimableSize)
            .ToList();
}
