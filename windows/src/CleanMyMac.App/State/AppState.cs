using System.Diagnostics;
using DiskKit;
using Microsoft.UI.Dispatching;

namespace CleanMyMac.State;

public abstract record NavItem
{
    public sealed record Summary : NavItem;
    public sealed record Volume(string Id) : NavItem;
    public sealed record Duplicates : NavItem;
    public sealed record Docker : NavItem;
    public sealed record DeletionLog : NavItem;
    public sealed record Help : NavItem;
    public sealed record Settings : NavItem;
}

public enum DriveTab { Categories, Folders, LargeFiles }

public sealed record VolumeScan(VolumeInfo Volume, ScanResult Result, CategoryReport Categories, IReadOnlyList<LargeFile> LargeFiles, DateTime ScannedUtc);

public sealed record ScanStatus(string VolumeName, long VolumeUsedBytes, int Index, int Total, DateTime StartedUtc);

public abstract record DockerState
{
    public sealed record Unknown : DockerState;
    public sealed record Checking : DockerState;
    public sealed record NotInstalled : DockerState;
    public sealed record NotRunning(string Binary) : DockerState;
    public sealed record Ready(DockerReport Report) : DockerState;
    public DockerReport? ReportOrNull => this is Ready r ? r.Report : null;
}

public sealed record TrashItem(string Path, long Bytes, bool IsDirectory);

/// <summary>
/// Single source of truth for the UI (port of the macOS AppState). Heavy work runs on background
/// threads; every change is published on the UI thread through <see cref="Changed"/>.
/// </summary>
public sealed class AppState
{
    private readonly DispatcherQueue _ui;
    private readonly VolumeService _volumeService = new();
    private readonly DiskKit.DeletionLog _log = new(DiskKit.DeletionLog.DefaultLocation());
    private ScanProgress? _currentProgress;
    private bool _cancelRequested;

    public AppState(AppSettings settings, DispatcherQueue ui)
    {
        Settings = settings;
        _ui = ui;
        IsElevated = Elevation.IsElevated();
        DeletionLog = _log.Load();
        RefreshVolumes(notify: false);
        RebuildFindings();
    }

    public event Action? Changed;
    /// <summary>Scan progress ticks (several per second) — kept separate so pages are not rebuilt while scanning.</summary>
    public event Action? ProgressChanged;
    public event Action<VolumeInfo>? VolumeMounted;
    public event Action<IReadOnlyList<VolumeInfo>, IReadOnlyList<VolumeInfo>>? ExternalPromptRequested;
    public event Action<string>? Message;

    public AppSettings Settings { get; }
    public NavItem Selection { get; private set; } = new NavItem.Summary();
    public IReadOnlyList<VolumeInfo> Volumes { get; private set; } = Array.Empty<VolumeInfo>();
    public Dictionary<string, VolumeScan> Scans { get; } = new();
    public DateTime? LastScanUtc { get; private set; }
    public ScanStatus? ScanStatus { get; private set; }
    public ScanProgress.Snapshot Progress { get; private set; }
    public IReadOnlyList<DuplicateGroup> Duplicates { get; private set; } = Array.Empty<DuplicateGroup>();
    public bool IsFindingDuplicates { get; private set; }
    public DockerState Docker { get; private set; } = new DockerState.Unknown();
    public bool IsDockerWorking { get; private set; }
    public IReadOnlyList<Finding> Findings { get; private set; } = Array.Empty<Finding>();
    public IReadOnlyList<DeletionRecord> DeletionLog { get; private set; }
    public bool IsElevated { get; }
    public Dictionary<string, DriveTab> DriveTabs { get; } = new();
    public Dictionary<string, string> FolderPaths { get; } = new();

    public bool IsScanning => ScanStatus is not null;
    public bool IsBusy => IsScanning || IsFindingDuplicates;
    public VolumeInfo? Volume(string id) => Volumes.FirstOrDefault(v => v.Id == id);
    public Severity SeverityOf(VolumeInfo v) => Settings.Policy.For(v);
    public long DuplicateReclaimable => Duplicates.Sum(g => g.ReclaimableSize);

    private void Notify() => Changed?.Invoke();

    /// <summary>Re-renders the current page after a UI-only change (tab, sort, folder).</summary>
    public void Refresh() => Notify();
    private void OnUi(Action action) => _ui.TryEnqueue(() => action());

    public void Select(NavItem item)
    {
        if (item == Selection) return;
        Selection = item;
        Notify();
    }

    // ---------------- Volumes ----------------

    public void RefreshVolumes(bool notify = true)
    {
        var before = Volumes.Select(v => v.Id).ToHashSet();
        try { Volumes = _volumeService.MountedVolumes(); }
        catch { /* keep the previous list */ }
        var ids = Volumes.Select(v => v.Id).ToHashSet();
        foreach (var gone in Scans.Keys.Where(k => !ids.Contains(k)).ToList()) Scans.Remove(gone);
        if (Selection is NavItem.Volume sel && !ids.Contains(sel.Id)) Selection = new NavItem.Summary();
        RebuildFindings();
        if (!notify) return;
        Notify();
        var added = Volumes.FirstOrDefault(v => v.IsExternal && !before.Contains(v.Id));
        if (added is not null && before.Count > 0 && !IsScanning && Settings.ExternalDrives != ExternalDriveBehavior.Never)
            VolumeMounted?.Invoke(added);
    }

    /// <summary>Polled by the window every few seconds (Windows has no simple mount notification for desktop apps).</summary>
    public void PollVolumes()
    {
        var current = _volumeService.MountedVolumes();
        if (!current.Select(v => v.Id).SequenceEqual(Volumes.Select(v => v.Id))) RefreshVolumes();
    }

    // ---------------- Scanning ----------------

    /// <summary>Internal drives always; external drives only after asking (unless Settings say otherwise).</summary>
    public void ScanAll()
    {
        if (IsScanning) return;
        RefreshVolumes();
        var internalList = Volumes.Where(v => !v.IsExternal).ToList();
        var externalList = Volumes.Where(v => v.IsExternal).ToList();
        if (externalList.Count == 0) { StartScan(internalList); return; }
        switch (Settings.ExternalDrives)
        {
            case ExternalDriveBehavior.Always: StartScan(internalList.Concat(externalList).ToList()); break;
            case ExternalDriveBehavior.Never: StartScan(internalList); break;
            default: ExternalPromptRequested?.Invoke(internalList, externalList); break;
        }
    }

    public void ResolveExternalPrompt(IReadOnlyList<VolumeInfo> internalList, IReadOnlyList<VolumeInfo> chosen, bool remember)
    {
        if (remember)
        {
            Settings.ExternalDrives = chosen.Count == 0 ? ExternalDriveBehavior.Never : ExternalDriveBehavior.Always;
            Settings.Save();
        }
        StartScan(internalList.Concat(chosen).ToList());
    }

    public void Scan(VolumeInfo volume)
    {
        if (!IsScanning) StartScan(new List<VolumeInfo> { volume });
    }

    public void CancelScan()
    {
        _cancelRequested = true;
        _currentProgress?.Cancel();
    }

    private void StartScan(List<VolumeInfo> list)
    {
        if (list.Count == 0 || IsScanning) return;
        _cancelRequested = false;
        _ = RunScansAsync(list);
    }

    private async Task RunScansAsync(List<VolumeInfo> list)
    {
        var minimumLarge = Settings.LargeFileMinimumBytes;
        var scannedAny = false;
        for (var i = 0; i < list.Count && !_cancelRequested; i++)
        {
            var volume = list[i];
            var progress = new ScanProgress();
            _currentProgress = progress;
            ScanStatus = new ScanStatus(volume.Name, volume.UsedBytes, i, list.Count, DateTime.UtcNow);
            Progress = default;
            Notify();

            using var timer = new System.Threading.Timer(_ => OnUi(() => { Progress = progress.Read(); ProgressChanged?.Invoke(); }), null, 200, 200);
            VolumeScan? scan = null;
            try
            {
                scan = await Task.Run(() =>
                {
                    var result = new DiskScanner().Scan(_volumeService.TargetFor(volume), progress);
                    var categories = new Categorizer().Report(result.Root);
                    var large = LargeFileFinder.Largest(result.Root, minimumLarge);
                    return new VolumeScan(volume, result, categories, large, DateTime.UtcNow);
                });
            }
            catch (Exception ex)
            {
                Message?.Invoke(ex.Message);
            }
            timer.Change(Timeout.Infinite, Timeout.Infinite);
            if (scan is null || scan.Result.WasCancelled) break;
            Scans[volume.Id] = scan;
            FolderPaths.Remove(volume.Id);
            scannedAny = true;
        }
        _currentProgress = null;
        ScanStatus = null;
        RefreshVolumes(notify: false);
        Notify();
        if (!scannedAny) return;
        LastScanUtc = DateTime.UtcNow;
        await FindDuplicatesAsync();
        RefreshDocker();
    }

    // ---------------- Duplicates ----------------

    public async Task FindDuplicatesAsync()
    {
        if (Scans.Count == 0) return;
        var sources = Scans.Values.OrderBy(s => s.Volume.Name).Select(s => new DuplicateSource(s.Volume.Name, s.Result.Root)).ToList();
        var options = Settings.DuplicateOptions;
        IsFindingDuplicates = true;
        Notify();
        try { Duplicates = await Task.Run(() => DuplicateFinder.Find(sources, options)); }
        catch (Exception ex) { Message?.Invoke(ex.Message); }
        IsFindingDuplicates = false;
        RebuildFindings();
        Notify();
    }

    // ---------------- Docker ----------------

    public void RefreshDocker()
    {
        if (IsDockerWorking) return;
        Docker = new DockerState.Checking();
        IsDockerWorking = true;
        Notify();
        Task.Run(() => new DockerService().Report()).ContinueWith(t => OnUi(() =>
        {
            Docker = t.IsCompletedSuccessfully
                ? t.Result.Status switch
                {
                    DockerStatus.NotRunning nr => new DockerState.NotRunning(nr.Binary),
                    DockerStatus.Running when t.Result.Report is { } r => new DockerState.Ready(r),
                    _ => new DockerState.NotInstalled(),
                }
                : new DockerState.NotInstalled();
            IsDockerWorking = false;
            RebuildFindings();
            Notify();
        }));
    }

    public void OpenDockerDesktop()
    {
        var exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Docker", "Docker", "Docker Desktop.exe");
        if (File.Exists(exe)) Shell.Open(exe);
    }

    public void RemoveDockerImages(IReadOnlyList<DockerImage> images)
    {
        if (Docker is not DockerState.Ready ready || IsDockerWorking || images.Count == 0) return;
        IsDockerWorking = true;
        Notify();
        var binary = ready.Report.Binary;
        Task.Run(() => new DockerService().RemoveImages(images.Select(i => i.Id), binary)).ContinueWith(t => OnUi(() =>
        {
            var ok = t.IsCompletedSuccessfully ? t.Result.Where(r => r.Succeeded).Select(r => r.ImageId).ToHashSet() : new HashSet<string>();
            AppendLog(images.Where(i => ok.Contains(i.Id)).Select(i => new DeletionRecord(Guid.NewGuid(), DateTime.UtcNow, DeletionKind.DockerImage, "docker:" + i.Id[..Math.Min(12, i.Id.Length)], i.SizeBytes)));
            IsDockerWorking = false;
            if (ok.Count < images.Count) Message?.Invoke("docker.removeFailed");
            RefreshDocker();
        }));
    }

    // ---------------- Recycle Bin ----------------

    public (List<TrashItem> Allowed, List<TrashItem> Blocked) Classify(IEnumerable<TrashItem> items)
    {
        var guard = new TrashGuard();
        var list = items.ToList();
        return (list.Where(i => guard.IsAllowed(i.Path)).ToList(), list.Where(i => !guard.IsAllowed(i.Path)).ToList());
    }

    /// <summary>True when any item lives on a drive without a Recycle Bin (USB stick, SD card).</summary>
    public bool HasItemsWithoutRecycleBin(IEnumerable<TrashItem> items) =>
        items.Any(i => Volumes.FirstOrDefault(v => i.Path.StartsWith(v.Path, StringComparison.OrdinalIgnoreCase)) is { HasRecycleBin: false });

    public void MoveToRecycleBin(IReadOnlyList<TrashItem> items)
    {
        if (items.Count == 0) return;
        Task.Run(() => new RecycleBinService().MoveToRecycleBin(items.Select(i => i.Path))).ContinueWith(t => OnUi(() =>
        {
            var outcomes = t.IsCompletedSuccessfully ? t.Result : Array.Empty<TrashOutcome>();
            var removed = outcomes.Where(o => o.Succeeded).Select(o => o.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
            ApplyRemoval(removed);
            AppendLog(items.Where(i => removed.Contains(i.Path)).Select(i => new DeletionRecord(Guid.NewGuid(), DateTime.UtcNow, i.IsDirectory ? DeletionKind.Folder : DeletionKind.File, i.Path, i.Bytes)));
            if (removed.Count < items.Count) Message?.Invoke("trash.someFailed");
            Notify();
        }));
    }

    private void ApplyRemoval(HashSet<string> paths)
    {
        if (paths.Count == 0) return;
        var touched = new HashSet<string>();
        foreach (var path in paths)
        {
            var owner = Scans.Where(kv => path.StartsWith(kv.Value.Result.Root.Path, StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(kv => kv.Value.Result.Root.Path.Length).FirstOrDefault();
            if (owner.Value is null) continue;
            if (owner.Value.Result.Root.RemoveItem(path) is not null) touched.Add(owner.Key);
        }
        foreach (var id in touched)
        {
            var scan = Scans[id];
            Scans[id] = scan with
            {
                LargeFiles = scan.LargeFiles.Where(f => !paths.Any(p => f.Path.StartsWith(p, StringComparison.OrdinalIgnoreCase))).ToList(),
                Categories = new Categorizer().Report(scan.Result.Root),
            };
        }
        Duplicates = DuplicateFinder.Removing(paths, Duplicates);
        RefreshVolumes(notify: false);
    }

    private void AppendLog(IEnumerable<DeletionRecord> records)
    {
        var list = records.ToList();
        if (list.Count == 0) return;
        try { DeletionLog = _log.Append(list); }
        catch { DeletionLog = list.Concat(DeletionLog).ToList(); }
    }

    public void ClearDeletionLog()
    {
        try { _log.Clear(); } catch { }
        DeletionLog = Array.Empty<DeletionRecord>();
        Notify();
    }

    // ---------------- Navigation & shell ----------------

    public void Navigate(FindingTarget target)
    {
        switch (target)
        {
            case FindingTarget.Volume v: Select(new NavItem.Volume(v.Id)); break;
            case FindingTarget.Folder f:
                DriveTabs[f.VolumeId] = DriveTab.Folders;
                FolderPaths[f.VolumeId] = f.Path;
                Selection = new NavItem.Volume(f.VolumeId);
                Notify();
                break;
            case FindingTarget.Duplicates: Select(new NavItem.Duplicates()); break;
            case FindingTarget.Docker: Select(new NavItem.Docker()); break;
            case FindingTarget.Elevation: Select(new NavItem.Help()); break;
        }
    }

    public void RestartAsAdministrator()
    {
        try
        {
            var exe = Environment.ProcessPath;
            if (exe is null) return;
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, Verb = "runas" });
            Environment.Exit(0);
        }
        catch { /* user cancelled the UAC prompt */ }
    }

    public void RebuildFindings()
    {
        Findings = SummaryBuilder.Findings(new SummaryInput(
            Volumes,
            Scans.ToDictionary(kv => kv.Key, kv => kv.Value.Categories.Hotspots),
            Scans.ToDictionary(kv => kv.Key, kv => kv.Value.Result.UnreadableDirectories),
            Duplicates.Count,
            DuplicateReclaimable,
            Docker.ReportOrNull,
            IsElevated,
            Settings.Policy));
    }

    public void SettingsChanged()
    {
        Settings.Save();
        RebuildFindings();
        Notify();
    }
}

public static class Shell
{
    public static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
    }

    public static void RevealInExplorer(string path)
    {
        try { Process.Start("explorer.exe", $"/select,\"{path}\""); } catch { }
    }

    public static void OpenRecycleBin()
    {
        try { Process.Start("explorer.exe", "shell:RecycleBinFolder"); } catch { }
    }
}
