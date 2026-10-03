using System.IO.Enumeration;

namespace DiskKit;

/// <summary>What to scan and where to stop.</summary>
public sealed record ScanTarget(string RootPath, IReadOnlySet<string>? ExcludedPaths = null);

/// <summary>Live counters shared between scanner threads and the UI.</summary>
public sealed class ScanProgress
{
    public readonly record struct Snapshot(int FilesScanned, int DirectoriesScanned, long BytesScanned, string CurrentPath, int UnreadableDirectories);

    private readonly object _lock = new();
    private int _files, _dirs, _unreadable;
    private long _bytes;
    private string _current = "";
    private volatile bool _cancelled;

    public bool IsCancelled => _cancelled;
    public void Cancel() => _cancelled = true;

    public Snapshot Read()
    {
        lock (_lock) return new Snapshot(_files, _dirs, _bytes, _current, _unreadable);
    }

    internal void Record(int files, long bytes, string path)
    {
        lock (_lock)
        {
            _files += files;
            _bytes += bytes;
            _dirs++;
            _current = path;
        }
    }

    internal void RecordUnreadable()
    {
        lock (_lock) _unreadable++;
    }
}

/// <summary>One entry returned when listing a directory.</summary>
public readonly record struct RawEntry(
    string Name,
    bool IsDirectory,
    bool IsReparsePoint,
    long AllocatedSize,
    long LogicalSize,
    DateTime ModifiedUtc,
    ulong FileId);

public interface IDirectoryReader
{
    /// <summary>Lists one directory. Throws <see cref="UnauthorizedAccessException"/> or <see cref="IOException"/> when unreadable.</summary>
    IReadOnlyList<RawEntry> Read(string path);
}

public static class DirectoryReaders
{
    /// <summary>The fastest reader for the current OS: FILE_ID_BOTH_DIR_INFO bulk listing on Windows, .NET enumeration elsewhere.</summary>
    public static IDirectoryReader Best => OperatingSystem.IsWindows() ? new WindowsBulkDirectoryReader() : new ManagedDirectoryReader();
}

/// <summary>Portable reader on top of <see cref="FileSystemEnumerable{T}"/>. Allocated size is the length rounded up to the cluster size.</summary>
public sealed class ManagedDirectoryReader : IDirectoryReader
{
    private readonly long _clusterSize;

    public ManagedDirectoryReader(long clusterSize = 4096) => _clusterSize = clusterSize;

    public IReadOnlyList<RawEntry> Read(string path)
    {
        if (!Directory.Exists(path)) throw new DirectoryNotFoundException(path);
        var options = new EnumerationOptions
        {
            IgnoreInaccessible = false,
            RecurseSubdirectories = false,
            AttributesToSkip = 0,
            ReturnSpecialDirectories = false,
        };
        var cluster = _clusterSize;
        var enumerable = new FileSystemEnumerable<RawEntry>(path, (ref FileSystemEntry e) =>
        {
            var isLink = (e.Attributes & FileAttributes.ReparsePoint) != 0;
            var length = e.IsDirectory ? 0 : e.Length;
            var allocated = length == 0 ? 0 : (length + cluster - 1) / cluster * cluster;
            return new RawEntry(e.FileName.ToString(), e.IsDirectory, isLink, allocated, length, e.LastWriteTimeUtc.UtcDateTime, 0);
        }, options);
        return enumerable.ToList();
    }
}

/// <summary>
/// Walks a directory tree in parallel and builds a <see cref="DirectoryNode"/> tree.
/// Accuracy: allocated sizes, hard links counted once (by file ID), reparse points
/// (junctions, symlinks, mounted volumes) are never followed.
/// </summary>
public sealed class DiskScanner
{
    private readonly IDirectoryReader _reader;
    private readonly int _threads;

    public DiskScanner(IDirectoryReader? reader = null, int? threads = null)
    {
        _reader = reader ?? DirectoryReaders.Best;
        _threads = Math.Max(1, threads ?? Math.Min(Environment.ProcessorCount * 2, 16));
    }

    public ScanResult Scan(ScanTarget target, ScanProgress? progress = null)
    {
        progress ??= new ScanProgress();
        var started = DateTime.UtcNow;
        var rootPath = Normalize(target.RootPath);
        var rootName = Path.GetFileName(rootPath.TrimEnd('\\', '/'));
        var root = new DirectoryNode(string.IsNullOrEmpty(rootName) ? rootPath : rootName, rootPath, null);

        new Engine(_reader, target, progress).Run(root, _threads);
        root.FinalizeTree();
        return new ScanResult(target, root, started, DateTime.UtcNow - started, progress.Read().UnreadableDirectories, progress.IsCancelled);
    }

    internal static string Normalize(string path)
    {
        var root = Path.GetPathRoot(path);
        if (!string.IsNullOrEmpty(root) && path.Length <= root.Length) return root;
        return path.TrimEnd('\\', '/');
    }

    private sealed class Engine
    {
        private readonly IDirectoryReader _reader;
        private readonly ScanTarget _target;
        private readonly ScanProgress _progress;
        private readonly object _gate = new();
        private readonly Stack<DirectoryNode> _pending = new();
        private int _active;
        private readonly HashSet<ulong> _seenFileIds = new();

        public Engine(IDirectoryReader reader, ScanTarget target, ScanProgress progress)
        {
            _reader = reader;
            _target = target;
            _progress = progress;
        }

        public void Run(DirectoryNode root, int threads)
        {
            _pending.Push(root);
            var workers = Enumerable.Range(0, threads).Select(i => new Thread(Work) { IsBackground = true, Name = $"DiskScanner-{i}" }).ToList();
            workers.ForEach(t => t.Start());
            workers.ForEach(t => t.Join());
        }

        private void Work()
        {
            while (true)
            {
                DirectoryNode node;
                lock (_gate)
                {
                    while (_pending.Count == 0 && _active > 0 && !_progress.IsCancelled) Monitor.Wait(_gate);
                    if (_pending.Count == 0 || _progress.IsCancelled)
                    {
                        Monitor.PulseAll(_gate);
                        return;
                    }
                    node = _pending.Pop();
                    _active++;
                }

                var children = Process(node);

                lock (_gate)
                {
                    foreach (var child in children) _pending.Push(child);
                    _active--;
                    Monitor.PulseAll(_gate);
                }
            }
        }

        private List<DirectoryNode> Process(DirectoryNode node)
        {
            IReadOnlyList<RawEntry> entries;
            try
            {
                entries = _reader.Read(node.Path);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or System.Security.SecurityException)
            {
                node.IsUnreadable = true;
                _progress.RecordUnreadable();
                return new List<DirectoryNode>();
            }

            var dirs = new List<DirectoryNode>();
            var files = new List<FileEntry>(entries.Count);
            long bytes = 0;
            var candidates = new List<RawEntry>(entries.Count);
            foreach (var e in entries)
            {
                if (e.IsReparsePoint) continue; // junctions, symlinks, mount points
                if (e.IsDirectory)
                {
                    var path = node.ChildPath(e.Name);
                    if (_target.ExcludedPaths?.Contains(path) == true) continue;
                    dirs.Add(new DirectoryNode(e.Name, path, node) { ModifiedUtc = e.ModifiedUtc });
                    continue;
                }
                candidates.Add(e);
            }
            // One lock per directory: drop the second (third…) name of a hard-linked file.
            lock (_seenFileIds)
            {
                foreach (var e in candidates)
                {
                    if (e.FileId != 0 && !_seenFileIds.Add(e.FileId)) continue;
                    files.Add(new FileEntry(e.Name, e.AllocatedSize, e.LogicalSize, e.ModifiedUtc));
                    bytes += e.AllocatedSize;
                }
            }
            node.Files = files;
            node.Directories = dirs;
            _progress.Record(files.Count, bytes, node.Path);
            return dirs;
        }
    }
}
