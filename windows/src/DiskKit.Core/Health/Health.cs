namespace DiskKit;

public enum Severity { Ok = 0, Info = 1, Warning = 2, Critical = 3 }

/// <summary>
/// Free-space thresholds (rules of thumb, editable in Settings). GB limits apply to the system drive only:
/// Windows needs room there for the page file, updates (~20 GB) and temp files. Other drives use percentages.
/// </summary>
public sealed record HealthPolicy(
    long CriticalFreeBytes = 10 * ByteFormatter.Gigabyte,
    double CriticalFreeRatio = 0.05,
    long WarningFreeBytes = 20 * ByteFormatter.Gigabyte,
    double WarningFreeRatio = 0.10)
{
    public static readonly HealthPolicy Default = new();

    public Severity For(VolumeInfo v) => For(v.AvailableBytes, v.TotalBytes, v.Kind == VolumeKind.System);

    public Severity For(long free, long total, bool isSystemDrive)
    {
        if (total <= 0) return Severity.Ok;
        var ratio = (double)free / total;
        if (ratio < CriticalFreeRatio || (isSystemDrive && free < CriticalFreeBytes)) return Severity.Critical;
        if (ratio < WarningFreeRatio || (isSystemDrive && free < WarningFreeBytes)) return Severity.Warning;
        return Severity.Ok;
    }
}

public abstract record FindingTarget
{
    public sealed record Volume(string Id) : FindingTarget;
    public sealed record Folder(string VolumeId, string Path) : FindingTarget;
    public sealed record Duplicates : FindingTarget;
    public sealed record Docker : FindingTarget;
    public sealed record Elevation : FindingTarget;
}

public abstract record FindingKind
{
    public sealed record LowDiskSpace(string VolumeName, long FreeBytes, double FreeRatio, bool IsSystemDrive) : FindingKind;
    public sealed record DockerDangling(int Count, long Bytes) : FindingKind;
    public sealed record DockerBuildCache(long Bytes) : FindingKind;
    public sealed record HotspotFound(HotspotKind Kind, long Bytes) : FindingKind;
    public sealed record Duplicates(int Groups, long Reclaimable) : FindingKind;
    public sealed record UnreadableFolders(string VolumeName, int Count) : FindingKind;
}

public sealed record Finding(string Id, Severity Severity, FindingKind Kind, FindingTarget Target, long Bytes = 0);

public sealed record SummaryInput(
    IReadOnlyList<VolumeInfo> Volumes,
    IReadOnlyDictionary<string, IReadOnlyList<Hotspot>> HotspotsByVolume,
    IReadOnlyDictionary<string, int> UnreadableByVolume,
    int DuplicateGroups,
    long DuplicateReclaimable,
    DockerReport? Docker,
    bool IsElevated,
    HealthPolicy Policy);

/// <summary>Turns analysis into a short list sorted by severity — the Summary screen.</summary>
public static class SummaryBuilder
{
    public static IReadOnlyList<Finding> Findings(SummaryInput input)
    {
        var result = new List<Finding>();
        const long gb = ByteFormatter.Gigabyte;

        foreach (var v in input.Volumes)
        {
            var s = input.Policy.For(v);
            if (s >= Severity.Warning)
                result.Add(new Finding($"space-{v.Id}", s, new FindingKind.LowDiskSpace(v.Name, v.AvailableBytes, v.FreeRatio, v.Kind == VolumeKind.System), new FindingTarget.Volume(v.Id), v.UsedBytes));
        }

        if (input.Docker is { } d)
        {
            if (d.DanglingImages.Count > 0)
                result.Add(new Finding("docker-dangling", d.DanglingBytes >= 5 * gb ? Severity.Warning : Severity.Info,
                    new FindingKind.DockerDangling(d.DanglingImages.Count, d.DanglingBytes), new FindingTarget.Docker(), d.DanglingBytes));
            if (d.Usage(DockerUsageKind.BuildCache) is { ReclaimableBytes: >= gb } cache)
                result.Add(new Finding("docker-cache", cache.ReclaimableBytes >= 10 * gb ? Severity.Warning : Severity.Info,
                    new FindingKind.DockerBuildCache(cache.ReclaimableBytes), new FindingTarget.Docker(), cache.ReclaimableBytes));
        }

        foreach (var (volumeId, spots) in input.HotspotsByVolume)
            foreach (var h in spots)
                if (HotspotSeverity(h) is { } s)
                    result.Add(new Finding($"hotspot-{volumeId}-{h.Kind}", s, new FindingKind.HotspotFound(h.Kind, h.Bytes), new FindingTarget.Folder(volumeId, h.Path), h.Bytes));

        if (input.DuplicateGroups > 0)
            result.Add(new Finding("duplicates", Severity.Info, new FindingKind.Duplicates(input.DuplicateGroups, input.DuplicateReclaimable), new FindingTarget.Duplicates(), input.DuplicateReclaimable));

        // Without Administrator rights many system folders are skipped — suggest elevating once.
        if (!input.IsElevated)
        {
            var unreadable = input.UnreadableByVolume.Values.Sum();
            if (unreadable > 0)
            {
                var first = input.UnreadableByVolume.First(kv => kv.Value > 0);
                var name = input.Volumes.FirstOrDefault(v => v.Id == first.Key)?.Name ?? first.Key;
                result.Add(new Finding("unreadable", Severity.Info, new FindingKind.UnreadableFolders(name, unreadable), new FindingTarget.Elevation()));
            }
        }

        return result.OrderByDescending(f => f.Severity).ThenByDescending(f => f.Bytes).ThenBy(f => f.Id, StringComparer.Ordinal).ToList();
    }

    internal static Severity? HotspotSeverity(Hotspot h)
    {
        const long gb = ByteFormatter.Gigabyte;
        if (h.Kind == HotspotKind.Downloads) return h.Bytes >= 20 * gb ? Severity.Info : null;
        if (h.Bytes >= 10 * gb) return Severity.Warning;
        if (h.Bytes >= gb) return Severity.Info;
        return null;
    }

    public static IReadOnlyDictionary<Severity, int> Counts(IEnumerable<Finding> findings) =>
        findings.GroupBy(f => f.Severity).ToDictionary(g => g.Key, g => g.Count());
}
