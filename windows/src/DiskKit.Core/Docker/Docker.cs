using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;

namespace DiskKit;

public sealed record CommandResult(int ExitCode, string StdOut, string StdErr, bool TimedOut = false)
{
    public bool Succeeded => ExitCode == 0 && !TimedOut;
}

/// <summary>Runs external programs; abstracted so Docker logic can be tested without Docker.</summary>
public interface ICommandRunner
{
    CommandResult Run(string executable, IReadOnlyList<string> arguments, TimeSpan timeout);
}

public sealed class ProcessCommandRunner : ICommandRunner
{
    public CommandResult Run(string executable, IReadOnlyList<string> arguments, TimeSpan timeout)
    {
        var info = new ProcessStartInfo(executable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var a in arguments) info.ArgumentList.Add(a);
        using var process = Process.Start(info) ?? throw new InvalidOperationException("Cannot start " + executable);
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        var timedOut = !process.WaitForExit((int)timeout.TotalMilliseconds);
        if (timedOut)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* already gone */ }
        }
        process.WaitForExit();
        return new CommandResult(timedOut ? -1 : process.ExitCode, stdout.Result, stderr.Result, timedOut);
    }
}

public abstract record DockerStatus
{
    /// <summary>No docker.exe found — nothing to clean and no command is run.</summary>
    public sealed record NotInstalled : DockerStatus;
    /// <summary>The CLI exists but Docker Desktop / the engine is not running.</summary>
    public sealed record NotRunning(string Binary) : DockerStatus;
    public sealed record Running(string Binary, string ServerVersion) : DockerStatus;
}

public sealed record DockerImage(string Id, string Repository, string Tag, long SizeBytes, string SizeText, string CreatedSince)
{
    public bool IsDangling => Repository == "<none>" && Tag == "<none>";
}

public enum DockerUsageKind { Images, Containers, Volumes, BuildCache, Other }

public sealed record DockerDiskUsage(DockerUsageKind Kind, int TotalCount, int Active, long SizeBytes, long ReclaimableBytes);

public sealed record DockerReport(string Binary, string ServerVersion, IReadOnlyList<DockerImage> DanglingImages, IReadOnlyList<DockerDiskUsage> DiskUsage, long? VirtualDiskBytes)
{
    public long DanglingBytes => DanglingImages.Sum(i => i.SizeBytes);
    public DockerDiskUsage? Usage(DockerUsageKind kind) => DiskUsage.FirstOrDefault(u => u.Kind == kind);
}

public sealed record DockerRemovalResult(string ImageId, bool Succeeded, string Message);

/// <summary>Strict order: installed → running → scan → clean. Nothing runs when Docker is missing.</summary>
public sealed class DockerService
{
    private readonly ICommandRunner _runner;
    private readonly Func<string, bool> _fileExists;
    private readonly Func<string, string?> _env;

    public DockerService(ICommandRunner? runner = null, Func<string, bool>? fileExists = null, Func<string, string?>? environment = null)
    {
        _runner = runner ?? new ProcessCommandRunner();
        _fileExists = fileExists ?? File.Exists;
        _env = environment ?? Environment.GetEnvironmentVariable;
    }

    public IReadOnlyList<string> CandidatePaths()
    {
        var programFiles = _env("ProgramFiles") ?? @"C:\Program Files";
        var local = _env("LOCALAPPDATA") ?? "";
        var list = new List<string>
        {
            $@"{programFiles}\Docker\Docker\resources\bin\docker.exe",
            $@"{programFiles}\Rancher Desktop\resources\resources\win32\bin\docker.exe",
            $@"{local}\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe",
            $@"{programFiles}\Podman\docker.exe",
        };
        var pathVariable = _env("PATH") ?? "";
        var separator = OperatingSystem.IsWindows() || pathVariable.Contains('\\') ? ';' : ':';
        foreach (var dir in pathVariable.Split(separator, StringSplitOptions.RemoveEmptyEntries))
        {
            var d = dir.Trim().TrimEnd('\\', '/');
            list.Add(d.Contains('\\') || OperatingSystem.IsWindows() ? d + "\\docker.exe" : d + "/docker");
        }
        return list;
    }

    public string? LocateBinary() => CandidatePaths().FirstOrDefault(_fileExists);

    private CommandResult Docker(string binary, TimeSpan timeout, params string[] args) => _runner.Run(binary, args, timeout);

    public DockerStatus Status()
    {
        if (LocateBinary() is not { } binary) return new DockerStatus.NotInstalled();
        CommandResult result;
        try { result = Docker(binary, TimeSpan.FromSeconds(8), "info", "--format", "{{.ServerVersion}}"); }
        catch { return new DockerStatus.NotRunning(binary); }
        var version = result.StdOut.Trim();
        if (!result.Succeeded || version.Length == 0 || version.Contains("<no value>")) return new DockerStatus.NotRunning(binary);
        return new DockerStatus.Running(binary, version);
    }

    public IReadOnlyList<DockerImage> DanglingImages(string binary)
    {
        var r = Docker(binary, TimeSpan.FromSeconds(30), "images", "--filter", "dangling=true", "--no-trunc", "--format", "{{json .}}");
        if (!r.Succeeded) throw new InvalidOperationException(r.StdErr);
        return ParseImages(r.StdOut);
    }

    public IReadOnlyList<DockerDiskUsage> DiskUsage(string binary)
    {
        var r = Docker(binary, TimeSpan.FromSeconds(60), "system", "df", "--format", "{{json .}}");
        if (!r.Succeeded) throw new InvalidOperationException(r.StdErr);
        return ParseDiskUsage(r.StdOut);
    }

    /// <summary>Docker Desktop (WSL 2) keeps everything in a virtual disk that does not shrink by itself.</summary>
    public long? VirtualDiskBytes()
    {
        var local = _env("LOCALAPPDATA") ?? "";
        foreach (var path in new[] { $@"{local}\Docker\wsl\disk\docker_data.vhdx", $@"{local}\Docker\wsl\data\ext4.vhdx", $@"{local}\Docker\wsl\main\ext4.vhdx" })
        {
            try
            {
                var info = new FileInfo(path);
                if (info.Exists) return info.Length;
            }
            catch { /* ignore */ }
        }
        return null;
    }

    public (DockerStatus Status, DockerReport? Report) Report()
    {
        var status = Status();
        if (status is not DockerStatus.Running running) return (status, null);
        IReadOnlyList<DockerImage> images;
        IReadOnlyList<DockerDiskUsage> usage;
        try { images = DanglingImages(running.Binary); } catch { images = Array.Empty<DockerImage>(); }
        try { usage = DiskUsage(running.Binary); } catch { usage = Array.Empty<DockerDiskUsage>(); }
        return (status, new DockerReport(running.Binary, running.ServerVersion, images, usage, VirtualDiskBytes()));
    }

    /// <summary>Removes images one by one without --force: Docker refuses any image a container still uses.</summary>
    public IReadOnlyList<DockerRemovalResult> RemoveImages(IEnumerable<string> ids, string binary) =>
        ids.Select(id =>
        {
            try
            {
                var r = Docker(binary, TimeSpan.FromSeconds(60), "image", "rm", id);
                return new DockerRemovalResult(id, r.Succeeded, (r.Succeeded ? r.StdOut : r.StdErr).Trim());
            }
            catch (Exception ex)
            {
                return new DockerRemovalResult(id, false, ex.Message);
            }
        }).ToList();

    internal static IReadOnlyList<DockerImage> ParseImages(string output)
    {
        var images = new List<DockerImage>();
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            try
            {
                using var doc = JsonDocument.Parse(line);
                var o = doc.RootElement;
                string Get(string key, string fallback) => o.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? fallback : fallback;
                var id = Get("ID", "");
                if (id.StartsWith("sha256:", StringComparison.Ordinal)) id = id[7..];
                if (id.Length == 0) continue;
                var size = Get("Size", Get("VirtualSize", "0B"));
                images.Add(new DockerImage(id, Get("Repository", "<none>"), Get("Tag", "<none>"), DockerSize.Parse(size), size, Get("CreatedSince", "")));
            }
            catch (JsonException) { /* skip non-JSON lines */ }
        }
        return images.OrderByDescending(i => i.SizeBytes).ToList();
    }

    internal static IReadOnlyList<DockerDiskUsage> ParseDiskUsage(string output)
    {
        var list = new List<DockerDiskUsage>();
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            try
            {
                using var doc = JsonDocument.Parse(line);
                var o = doc.RootElement;
                string Get(string key) => o.TryGetProperty(key, out var v) ? (v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : v.ToString()) : "";
                var kind = Get("Type").ToLowerInvariant() switch
                {
                    "images" => DockerUsageKind.Images,
                    "containers" => DockerUsageKind.Containers,
                    "local volumes" or "volumes" => DockerUsageKind.Volumes,
                    "build cache" => DockerUsageKind.BuildCache,
                    _ => DockerUsageKind.Other,
                };
                int.TryParse(Get("TotalCount"), out var total);
                int.TryParse(Get("Active"), out var active);
                var reclaimable = Get("Reclaimable").Split(' ')[0];
                list.Add(new DockerDiskUsage(kind, total, active, DockerSize.Parse(Get("Size")), DockerSize.Parse(reclaimable)));
            }
            catch (JsonException) { }
        }
        return list;
    }
}

/// <summary>Parses Docker's human sizes ("1.2GB", "980MB", "12.3kB"). Docker uses decimal units; *iB are binary.</summary>
public static class DockerSize
{
    public static long Parse(string text)
    {
        var t = text.Trim();
        var number = new StringBuilder();
        var unit = new StringBuilder();
        foreach (var ch in t)
        {
            if ((char.IsDigit(ch) || ch == '.') && unit.Length == 0) number.Append(ch);
            else if (!char.IsWhiteSpace(ch)) unit.Append(ch);
        }
        if (!double.TryParse(number.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value)) return 0;
        var multiplier = unit.ToString().ToLowerInvariant() switch
        {
            "b" or "" => 1d,
            "kb" or "k" => 1e3,
            "mb" or "m" => 1e6,
            "gb" or "g" => 1e9,
            "tb" or "t" => 1e12,
            "kib" => 1024d,
            "mib" => 1048576d,
            "gib" => 1073741824d,
            "tib" => 1099511627776d,
            _ => 1d,
        };
        return (long)Math.Round(value * multiplier);
    }
}
