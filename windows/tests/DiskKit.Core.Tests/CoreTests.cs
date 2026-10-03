using System.Globalization;
using System.Runtime.InteropServices;
using Xunit;

namespace DiskKit.Tests;

public sealed class ScannerTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "diskkit-" + Guid.NewGuid().ToString("N"));

    public ScannerTests() => Directory.CreateDirectory(_root);
    public void Dispose() { try { Directory.Delete(_root, true); } catch { } }

    private void Write(string relative, int bytes)
    {
        var path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, new byte[bytes]);
    }

    [Fact]
    public void BuildsTreeSortedLargestFirst()
    {
        Write("big/movie.mov", 300_000);
        Write("big/nested/clip.mp4", 200_000);
        Write("small/note.txt", 10_000);
        Write("top.pdf", 50_000);

        var result = new DiskScanner(threads: 4).Scan(new ScanTarget(_root));

        Assert.Equal(4, result.TotalFiles);
        Assert.False(result.WasCancelled);
        Assert.Equal(new[] { "big", "small" }, result.Root.Directories.Select(d => d.Name));
        Assert.True(result.Root.Directories[0].AllocatedSize >= 500_000);
        Assert.Equal(result.Root.AllocatedSize, result.Root.Directories.Sum(d => d.AllocatedSize) + result.Root.Files.Sum(f => f.AllocatedSize));
    }

    [Fact]
    public void SymlinkedFoldersAreNotFollowed()
    {
        Write("real/data.bin", 100_000);
        try { Directory.CreateSymbolicLink(Path.Combine(_root, "alias"), Path.Combine(_root, "real")); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return; } // needs Developer Mode on Windows
        var result = new DiskScanner().Scan(new ScanTarget(_root));
        Assert.Equal(1, result.TotalFiles);
        Assert.Equal(new[] { "real" }, result.Root.Directories.Select(d => d.Name));
    }

    [Fact]
    public void ExcludedPathsAreSkipped()
    {
        Write("keep/a.bin", 1000);
        Write("skip/b.bin", 1000);
        var excluded = new HashSet<string> { Path.Combine(_root, "skip") };
        var result = new DiskScanner().Scan(new ScanTarget(_root, excluded));
        Assert.Equal(new[] { "keep" }, result.Root.Directories.Select(d => d.Name));
    }

    [Fact]
    public void CancelledScanStopsEarly()
    {
        for (var i = 0; i < 50; i++) Write($"d{i}/f.bin", 100);
        var progress = new ScanProgress();
        progress.Cancel();
        var result = new DiskScanner().Scan(new ScanTarget(_root), progress);
        Assert.True(result.WasCancelled);
        Assert.True(result.TotalFiles < 50);
    }

    [Fact]
    public void UnreadableRootIsReported()
    {
        var result = new DiskScanner().Scan(new ScanTarget(Path.Combine(_root, "missing")));
        Assert.True(result.Root.IsUnreadable);
        Assert.Equal(1, result.UnreadableDirectories);
    }

    [Fact]
    public void RemoveItemUpdatesAncestors()
    {
        Write("a/b/c.bin", 100_000);
        Write("a/d.bin", 100_000);
        var result = new DiskScanner().Scan(new ScanTarget(_root));
        var before = result.Root.AllocatedSize;
        var removed = result.Root.RemoveItem(Path.Combine(_root, "a", "b"));
        Assert.NotNull(removed);
        Assert.Equal(before - removed, result.Root.AllocatedSize);
        Assert.Equal(1, result.Root.FileCount);
        Assert.Null(result.Root.NodeAtPath(Path.Combine(_root, "a", "b")));
        Assert.Null(result.Root.RemoveItem(Path.Combine(_root, "nope")));
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLinkW(string newName, string existing, IntPtr security);

    [Fact]
    public void WindowsBulkReaderMatchesManagedReaderAndCountsHardLinksOnce()
    {
        if (!OperatingSystem.IsWindows()) return;
        Write("one.bin", 123_456);
        Write("dir/two.bin", 1);
        Write("Tiếng Việt.txt", 42);
        var bulk = new WindowsBulkDirectoryReader().Read(_root).OrderBy(e => e.Name, StringComparer.Ordinal).ToList();
        var managed = new ManagedDirectoryReader().Read(_root).OrderBy(e => e.Name, StringComparer.Ordinal).ToList();
        Assert.Equal(managed.Select(e => e.Name), bulk.Select(e => e.Name));
        Assert.Equal(managed.Select(e => e.IsDirectory), bulk.Select(e => e.IsDirectory));
        Assert.Equal(managed.Select(e => e.LogicalSize), bulk.Select(e => e.LogicalSize));
        Assert.All(bulk.Where(e => !e.IsDirectory && e.LogicalSize > 0), e => Assert.True(e.AllocatedSize >= e.LogicalSize || e.AllocatedSize == 0));
        Assert.All(bulk, e => Assert.NotEqual(0UL, e.FileId));

        Assert.True(CreateHardLinkW(Path.Combine(_root, "dir", "link.bin"), Path.Combine(_root, "one.bin"), IntPtr.Zero));
        var result = new DiskScanner(new WindowsBulkDirectoryReader()).Scan(new ScanTarget(_root));
        Assert.Equal(3, result.TotalFiles);
    }
}

public sealed class AnalysisTests
{
    private static readonly WindowsPaths Paths = WindowsPaths.ForUser("C:", "dat");

    internal static DirectoryNode Dir(string path, DirectoryNode? parent = null, params (string Name, long Size)[] files) =>
        Dir(path, parent, DateTime.UtcNow, files);

    internal static DirectoryNode Dir(string path, DirectoryNode? parent, DateTime date, params (string Name, long Size)[] files)
    {
        var name = path.TrimEnd('\\').Split('\\', '/').Last();
        var node = new DirectoryNode(string.IsNullOrEmpty(name) ? path : name, path, parent)
        {
            Files = files.Select(f => new FileEntry(f.Name, f.Size, f.Size, date)).ToList(),
        };
        parent?.Directories.Add(node);
        return node;
    }

    [Fact]
    public void FolderRulesBeatExtensions()
    {
        var root = Dir(@"C:\", null, ("pagefile.sys", 4000), ("notes.txt", 10));
        var users = Dir(@"C:\Users", root);
        var home = Dir(@"C:\Users\dat", users);
        var appData = Dir(@"C:\Users\dat\AppData", home);
        var local = Dir(@"C:\Users\dat\AppData\Local", appData);
        Dir(@"C:\Users\dat\AppData\Local\Temp", local, ("blob.png", 500));
        var docs = Dir(@"C:\Users\dat\Documents", home, ("report.pdf", 100), ("song.mp3", 50), ("x.zip", 70));
        var project = Dir(@"C:\Users\dat\Documents\app", docs);
        Dir(@"C:\Users\dat\Documents\app\node_modules", project, ("index.js", 300));
        var pf = Dir(@"C:\Program Files", root);
        Dir(@"C:\Program Files\Foo", pf, ("foo.exe", 1000), ("readme.txt", 5));
        var win = Dir(@"C:\Windows", root);
        Dir(@"C:\Windows\System32", win, ("kernel32.dll", 2000));
        root.FinalizeTree();

        var report = new Categorizer(Paths).Report(root);
        Assert.Equal(500, report.Totals[StorageCategory.Caches]);
        Assert.Equal(110, report.Totals[StorageCategory.Documents]);
        Assert.Equal(50, report.Totals[StorageCategory.Music]);
        Assert.Equal(70, report.Totals[StorageCategory.Archives]);
        Assert.Equal(300, report.Totals[StorageCategory.Developer]);
        Assert.Equal(1005, report.Totals[StorageCategory.Applications]);
        Assert.Equal(6000, report.Totals[StorageCategory.System]);
        Assert.Equal(root.AllocatedSize, report.CategorizedBytes);
        Assert.Equal(300, report.Hotspots.Single(h => h.Kind == HotspotKind.NodeModules).Bytes);
        Assert.Equal(500, report.Hotspots.Single(h => h.Kind == HotspotKind.UserTemp).Bytes);
    }

    [Fact]
    public void LargeFilesAreSortedAndLimited()
    {
        var root = Dir(@"D:\data", null, ("a.mov", 500), ("b.txt", 5));
        Dir(@"D:\data\sub", root, ("c.zip", 800));
        root.FinalizeTree();
        var large = LargeFileFinder.Largest(root, 100, 10);
        Assert.Equal(new[] { "c.zip", "a.mov" }, large.Select(f => f.Name));
        Assert.Single(LargeFileFinder.Largest(root, 100, 1));
    }

    [Fact]
    public void DuplicatesUseNormalizedNamesAcrossDrives()
    {
        var newer = new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc);
        var older = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var a = Dir(@"C:\Users\dat\Documents", null, newer, ("Ba\u0301o ca\u0301o.pdf", 3_000_000));
        var b = Dir(@"E:\Backup", null, older, ("BÁO CÁO.pdf", 2_000_000), ("unique.mov", 9_000_000));
        a.FinalizeTree(); b.FinalizeTree();
        var groups = DuplicateFinder.Find(new[] { new DuplicateSource("C:", a), new DuplicateSource("E:", b) }, paths: Paths);
        var g = Assert.Single(groups);
        Assert.Equal(2, g.Files.Count);
        Assert.Equal("C:", g.Newest!.VolumeName);
        Assert.Equal(2_000_000, g.ReclaimableSize);
        Assert.Empty(DuplicateFinder.Removing(new HashSet<string> { g.Files[1].Path }, groups));
    }

    [Fact]
    public void DuplicatesSkipSmallHiddenDevAndSystemFolders()
    {
        var root = Dir(@"C:\");
        var home = Dir(@"C:\Users\dat", root);
        Dir(@"C:\Users\dat\a", home, ("tiny.txt", 10), ("same.bin", 2_000_000));
        Dir(@"C:\Users\dat\b", home, ("tiny.txt", 10));
        Dir(@"C:\Users\dat\node_modules", home, ("same.bin", 2_000_000));
        Dir(@"C:\Windows", root, ("same.bin", 2_000_000));
        root.FinalizeTree();
        Assert.Empty(DuplicateFinder.Find(new[] { new DuplicateSource("C:", root) }, paths: Paths));
        var loose = new DuplicateOptions(0, false, false, false);
        var groups = DuplicateFinder.Find(new[] { new DuplicateSource("C:", root) }, loose, Paths);
        Assert.Equal(3, groups.Single(x => x.Key == "same.bin").Files.Count);
        Assert.Contains(groups, x => x.Key == "tiny.txt");
    }

    [Fact]
    public void TreemapFillsBoundsWithoutOverlap()
    {
        var items = new (string, double)[] { ("a", 6), ("b", 6), ("c", 4), ("d", 3), ("e", 2), ("f", 2), ("g", 1), ("zero", 0) };
        var bounds = new LayoutRect(0, 0, 600, 400);
        var tiles = Treemap.Squarify(items, bounds);
        Assert.Equal(7, tiles.Count);
        Assert.Equal(bounds.Area, tiles.Sum(t => t.Rect.Area), 3);
        for (var i = 0; i < tiles.Count; i++)
            for (var j = i + 1; j < tiles.Count; j++)
            {
                var a = tiles[i].Rect; var b = tiles[j].Rect;
                var w = Math.Min(a.X + a.Width, b.X + b.Width) - Math.Max(a.X, b.X);
                var h = Math.Min(a.Y + a.Height, b.Y + b.Height) - Math.Max(a.Y, b.Y);
                Assert.False(w > 0.001 && h > 0.001, $"{tiles[i].Id} overlaps {tiles[j].Id}");
            }
        Assert.Empty(Treemap.Squarify(new[] { ("a", 1.0) }, new LayoutRect(0, 0, 0, 10)));
    }
}

public sealed class ServiceTests
{
    private const long Gb = ByteFormatter.Gigabyte;

    [Fact]
    public void ByteFormatterUsesCultureSeparators()
    {
        Assert.Equal("0 B", ByteFormatter.Format(0));
        Assert.Equal("8.2 GB", ByteFormatter.Format(8_200_000_000, CultureInfo.GetCultureInfo("en-US")));
        Assert.Equal("8,2 GB", ByteFormatter.Format(8_200_000_000, CultureInfo.GetCultureInfo("vi-VN")));
        Assert.Equal("256 GB", ByteFormatter.Format(256_000_000_000, CultureInfo.GetCultureInfo("en-US")));
        Assert.Equal("2 KB", ByteFormatter.Format(1_500, CultureInfo.GetCultureInfo("en-US")));
    }

    [Fact]
    public void DriveClassification()
    {
        DriveFacts F(DriveType t, bool system = false, bool usb = false, bool ready = true) => new("X:\\", "", t, ready, system, usb, "NTFS", 100, 50);
        Assert.Equal(VolumeKind.System, VolumeClassifier.Classify(F(DriveType.Fixed, system: true)));
        Assert.Equal(VolumeKind.Internal, VolumeClassifier.Classify(F(DriveType.Fixed)));
        Assert.Equal(VolumeKind.External, VolumeClassifier.Classify(F(DriveType.Fixed, usb: true)));
        Assert.Equal(VolumeKind.External, VolumeClassifier.Classify(F(DriveType.Removable)));
        Assert.Null(VolumeClassifier.Classify(F(DriveType.Network)));
        Assert.Null(VolumeClassifier.Classify(F(DriveType.CDRom)));
        Assert.Null(VolumeClassifier.Classify(F(DriveType.Removable, ready: false)));
    }

    [Fact]
    public void HealthPolicyForSystemAndOtherDrives()
    {
        var p = HealthPolicy.Default;
        Assert.Equal(Severity.Critical, p.For(8 * Gb, 1000 * Gb, true));
        Assert.Equal(Severity.Warning, p.For(15 * Gb, 100 * Gb, true));
        Assert.Equal(Severity.Ok, p.For(60 * Gb, 500 * Gb, true));
        Assert.Equal(Severity.Ok, p.For(9 * Gb, 64 * Gb, false));
        Assert.Equal(Severity.Warning, p.For(5 * Gb, 64 * Gb, false));
        Assert.Equal(Severity.Critical, p.For(2 * Gb, 64 * Gb, false));
    }

    [Fact]
    public void SummaryOrdersBySeverityThenSize()
    {
        var c = new VolumeInfo("Local Disk (C:)", @"C:\", VolumeKind.System, "NTFS", 256 * Gb, 8 * Gb, false);
        var docker = new DockerReport("docker.exe", "27",
            new[] { new DockerImage("a", "<none>", "<none>", 6 * Gb, "6GB", "") },
            new[] { new DockerDiskUsage(DockerUsageKind.BuildCache, 1, 0, 3 * Gb, 3 * Gb) }, null);
        var input = new SummaryInput(new[] { c },
            new Dictionary<string, IReadOnlyList<Hotspot>> { [@"C:\"] = new[] { new Hotspot(HotspotKind.WindowsUpdateCache, "x", 15 * Gb, 1), new Hotspot(HotspotKind.UserTemp, "y", 100, 1) } },
            new Dictionary<string, int> { [@"C:\"] = 12 }, 37, Gb / 2, docker, false, HealthPolicy.Default);
        var findings = SummaryBuilder.Findings(input);
        Assert.Equal(Severity.Critical, findings[0].Severity);
        Assert.Equal(findings.Select(f => f.Severity).OrderByDescending(s => s), findings.Select(f => f.Severity));
        Assert.Contains(findings, f => f.Id == "docker-dangling" && f.Severity == Severity.Warning);
        Assert.Contains(findings, f => f.Id == "docker-cache" && f.Severity == Severity.Info);
        Assert.Contains(findings, f => f.Id == "unreadable");
        Assert.DoesNotContain(findings, f => f.Id.EndsWith("UserTemp"));
        Assert.Equal(1, SummaryBuilder.Counts(findings)[Severity.Critical]);
    }

    [Fact]
    public void TrashGuardProtectsSystemAndEssentialFolders()
    {
        if (!OperatingSystem.IsWindows()) return; // Windows path semantics
        var g = new TrashGuard(WindowsPaths.ForUser("C:", "dat"), @"C:\Program Files\CleanMyMac");
        Assert.Equal(ProtectionReason.SystemLocation, g.Check(@"C:\Windows\System32"));
        Assert.Equal(ProtectionReason.SystemLocation, g.Check(@"C:\ProgramData\Microsoft"));
        Assert.Equal(ProtectionReason.VolumeRoot, g.Check(@"D:\"));
        Assert.Equal(ProtectionReason.EssentialFolder, g.Check(@"C:\Users\dat\Documents"));
        Assert.Equal(ProtectionReason.EssentialFolder, g.Check(@"C:\Users\dat\AppData\Local"));
        Assert.Equal(ProtectionReason.ApplicationItself, g.Check(@"C:\Program Files\CleanMyMac\app.exe"));
        Assert.Equal(ProtectionReason.NotAbsolute, g.Check(@"relative\path"));
        Assert.True(g.IsAllowed(@"C:\Users\dat\Downloads\big.iso"));
        Assert.True(g.IsAllowed(@"C:\Users\dat\AppData\Local\Temp\x"));
        Assert.True(g.IsAllowed(@"E:\Archive\old.mov"));
    }

    [Fact]
    public void DeletionLogRoundTrip()
    {
        var file = Path.Combine(Path.GetTempPath(), "log-" + Guid.NewGuid().ToString("N"), "log.json");
        var log = new DeletionLog(file);
        Assert.Empty(log.Load());
        log.Append(new[] { new DeletionRecord(Guid.NewGuid(), DateTime.UtcNow, DeletionKind.File, "/a", 1), new DeletionRecord(Guid.NewGuid(), DateTime.UtcNow, DeletionKind.DockerImage, "sha", 2) });
        log.Append(new[] { new DeletionRecord(Guid.NewGuid(), DateTime.UtcNow, DeletionKind.Folder, "/b", 3) });
        Assert.Equal(new[] { "/b", "sha", "/a" }, log.Load().Select(r => r.Path));
        log.Clear();
        Assert.Empty(log.Load());
    }
}

public sealed class FakeRunner : ICommandRunner
{
    public Dictionary<string, CommandResult> Responses { get; } = new();
    public List<IReadOnlyList<string>> Calls { get; } = new();

    public CommandResult Run(string executable, IReadOnlyList<string> arguments, TimeSpan timeout)
    {
        Calls.Add(arguments);
        return Responses.TryGetValue(string.Join(' ', arguments), out var r) ? r : new CommandResult(1, "", "unknown");
    }
}

public sealed class DockerTests
{
    private static Func<string, string?> Env(string path = "") => key => key switch
    {
        "ProgramFiles" => @"C:\Program Files",
        "LOCALAPPDATA" => @"C:\nonexistent",
        "PATH" => path,
        _ => null,
    };

    [Fact]
    public void NotInstalledRunsNothing()
    {
        var runner = new FakeRunner();
        var service = new DockerService(runner, _ => false, Env());
        Assert.IsType<DockerStatus.NotInstalled>(service.Status());
        var (status, report) = service.Report();
        Assert.IsType<DockerStatus.NotInstalled>(status);
        Assert.Null(report);
        Assert.Empty(runner.Calls);
    }

    [Fact]
    public void InstalledButNotRunning()
    {
        var runner = new FakeRunner();
        runner.Responses["info --format {{.ServerVersion}}"] = new CommandResult(1, "", "error during connect");
        var exe = @"C:\Program Files\Docker\Docker\resources\bin\docker.exe";
        var service = new DockerService(runner, p => p == exe, Env());
        Assert.Equal(new DockerStatus.NotRunning(exe), service.Status());
        Assert.Single(runner.Calls);
    }

    [Fact]
    public void RunningReportParsesImagesAndUsage()
    {
        var runner = new FakeRunner();
        runner.Responses["info --format {{.ServerVersion}}"] = new CommandResult(0, "27.3.1\n", "");
        runner.Responses["images --filter dangling=true --no-trunc --format {{json .}}"] = new CommandResult(0,
            "{\"CreatedSince\":\"3 weeks ago\",\"ID\":\"sha256:aaa\",\"Repository\":\"\\u003cnone\\u003e\",\"Size\":\"1.2GB\",\"Tag\":\"\\u003cnone\\u003e\"}\n" +
            "{\"CreatedSince\":\"1 month ago\",\"ID\":\"sha256:bbb\",\"Repository\":\"<none>\",\"Size\":\"980MB\",\"Tag\":\"<none>\"}\nnot json\n", "");
        runner.Responses["system df --format {{json .}}"] = new CommandResult(0,
            "{\"Active\":\"2\",\"Reclaimable\":\"6.4GB (52%)\",\"Size\":\"12.3GB\",\"TotalCount\":\"14\",\"Type\":\"Images\"}\n" +
            "{\"Active\":\"0\",\"Reclaimable\":\"4.8GB\",\"Size\":\"4.8GB\",\"TotalCount\":\"31\",\"Type\":\"Build Cache\"}\n", "");
        var exe = @"C:\tools\docker.exe";
        var service = new DockerService(runner, p => p == exe, Env(@"C:\tools"));
        var (status, report) = service.Report();
        Assert.Equal(new DockerStatus.Running(exe, "27.3.1"), status);
        Assert.NotNull(report);
        Assert.Equal(new[] { "aaa", "bbb" }, report!.DanglingImages.Select(i => i.Id));
        Assert.All(report.DanglingImages, i => Assert.True(i.IsDangling));
        Assert.Equal(2_180_000_000, report.DanglingBytes);
        Assert.Equal(6_400_000_000, report.Usage(DockerUsageKind.Images)!.ReclaimableBytes);
        Assert.Equal(31, report.Usage(DockerUsageKind.BuildCache)!.TotalCount);
    }

    [Fact]
    public void RemoveNeverForces()
    {
        var runner = new FakeRunner();
        runner.Responses["image rm abc"] = new CommandResult(0, "Deleted: sha256:abc", "");
        runner.Responses["image rm used"] = new CommandResult(1, "", "conflict: image is being used");
        var results = new DockerService(runner, _ => true, Env()).RemoveImages(new[] { "abc", "used" }, "docker.exe");
        Assert.Equal(new[] { true, false }, results.Select(r => r.Succeeded));
        Assert.DoesNotContain(runner.Calls.SelectMany(c => c), a => a is "-f" or "--force");
    }

    [Theory]
    [InlineData("1.2GB", 1_200_000_000)]
    [InlineData("980MB", 980_000_000)]
    [InlineData("12.3kB", 12_300)]
    [InlineData("512B", 512)]
    [InlineData("1GiB", 1_073_741_824)]
    [InlineData("", 0)]
    [InlineData("N/A", 0)]
    public void ParsesDockerSizes(string text, long expected) => Assert.Equal(expected, DockerSize.Parse(text));
}
