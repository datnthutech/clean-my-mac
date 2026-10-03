using System.Globalization;

namespace DiskKit;

/// <summary>Formats byte counts like Explorer's "Size on disk" but with decimal units (1 KB = 1000 B), matching the macOS app.</summary>
public static class ByteFormatter
{
    public const long Megabyte = 1_000_000;
    public const long Gigabyte = 1_000_000_000;
    private static readonly string[] Units = { "B", "KB", "MB", "GB", "TB", "PB" };

    public static string Format(long bytes, CultureInfo? culture = null)
    {
        culture ??= CultureInfo.CurrentCulture;
        if (bytes <= 0) return "0 B";
        double value = bytes;
        var index = 0;
        while (value >= 1000 && index < Units.Length - 1)
        {
            value /= 1000;
            index++;
        }
        var decimals = index >= 2 && value < 100 ? 1 : 0;
        var rounded = Math.Round(value, decimals, MidpointRounding.AwayFromZero);
        var format = decimals == 1 && rounded % 1 != 0 ? "0.0" : "0";
        return rounded.ToString(format, culture) + " " + Units[index];
    }
}

/// <summary>A regular file found during a scan, stored inline in its parent to keep memory low.</summary>
public readonly record struct FileEntry(string Name, long AllocatedSize, long LogicalSize, DateTime ModifiedUtc);

/// <summary>
/// A directory in the scanned tree. Each node is written only by the worker that lists it,
/// then read after all workers finish. After the scan, mutate from one thread only.
/// </summary>
public sealed class DirectoryNode
{
    public DirectoryNode(string name, string path, DirectoryNode? parent, bool isPackage = false)
    {
        Name = name;
        Path = path;
        Parent = parent;
        IsPackage = isPackage;
    }

    public string Name { get; }
    public string Path { get; }
    public DirectoryNode? Parent { get; }
    public bool IsPackage { get; }
    public DateTime? ModifiedUtc { get; internal set; }
    public List<FileEntry> Files { get; internal set; } = new();
    public List<DirectoryNode> Directories { get; internal set; } = new();
    /// <summary>True when the directory could not be listed (access denied, usually needs Administrator).</summary>
    public bool IsUnreadable { get; internal set; }
    public long AllocatedSize { get; internal set; }
    public int FileCount { get; internal set; }

    /// <summary>Windows-style paths keep backslashes even when the logic runs elsewhere (tests on Linux).</summary>
    private char Separator => Path.Contains('\\') || Path.EndsWith(':') ? '\\' : System.IO.Path.DirectorySeparatorChar;

    public string ChildPath(string childName) =>
        Path.EndsWith('\\') || Path.EndsWith('/') ? Path + childName : Path + Separator + childName;

    /// <summary>Computes recursive totals bottom-up and sorts children largest first (iterative, safe for deep trees).</summary>
    internal void FinalizeTree()
    {
        var postOrder = new List<DirectoryNode>();
        var stack = new Stack<DirectoryNode>();
        stack.Push(this);
        while (stack.Count > 0)
        {
            var node = stack.Pop();
            postOrder.Add(node);
            foreach (var child in node.Directories) stack.Push(child);
        }
        for (var i = postOrder.Count - 1; i >= 0; i--)
        {
            var node = postOrder[i];
            long size = 0;
            var count = node.Files.Count;
            foreach (var f in node.Files) size += f.AllocatedSize;
            foreach (var d in node.Directories)
            {
                size += d.AllocatedSize;
                count += d.FileCount;
            }
            node.AllocatedSize = size;
            node.FileCount = count;
            node.Files.Sort((a, b) => b.AllocatedSize.CompareTo(a.AllocatedSize));
            node.Directories.Sort((a, b) => b.AllocatedSize.CompareTo(a.AllocatedSize));
        }
    }

    private static readonly StringComparison PathComparison =
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    /// <summary>Finds a descendant (or self) by absolute path.</summary>
    public DirectoryNode? NodeAtPath(string target)
    {
        if (string.Equals(target.TrimEnd('\\', '/'), Path.TrimEnd('\\', '/'), PathComparison)) return this;
        var prefix = Path.EndsWith('\\') || Path.EndsWith('/') ? Path : Path + System.IO.Path.DirectorySeparatorChar;
        if (!target.StartsWith(prefix, PathComparison)) return null;
        var current = this;
        foreach (var part in target[prefix.Length..].Split('\\', '/', StringSplitOptions.RemoveEmptyEntries))
        {
            var next = current.Directories.FirstOrDefault(d => string.Equals(d.Name, part, PathComparison));
            if (next is null) return null;
            current = next;
        }
        return current;
    }

    /// <summary>Removes a file or folder (after it went to the Recycle Bin) and updates ancestor totals. Returns bytes removed, or null.</summary>
    public long? RemoveItem(string target)
    {
        var parentPath = System.IO.Path.GetDirectoryName(target.TrimEnd('\\', '/'));
        var name = System.IO.Path.GetFileName(target.TrimEnd('\\', '/'));
        if (parentPath is null) return null;
        var owner = NodeAtPath(parentPath);
        if (owner is null) return null;

        long bytes;
        int files;
        var dirIndex = owner.Directories.FindIndex(d => string.Equals(d.Name, name, PathComparison));
        if (dirIndex >= 0)
        {
            bytes = owner.Directories[dirIndex].AllocatedSize;
            files = owner.Directories[dirIndex].FileCount;
            owner.Directories.RemoveAt(dirIndex);
        }
        else
        {
            var fileIndex = owner.Files.FindIndex(f => string.Equals(f.Name, name, PathComparison));
            if (fileIndex < 0) return null;
            bytes = owner.Files[fileIndex].AllocatedSize;
            files = 1;
            owner.Files.RemoveAt(fileIndex);
        }
        for (var node = owner; node is not null; node = node.Parent)
        {
            node.AllocatedSize -= bytes;
            node.FileCount -= files;
            if (ReferenceEquals(node, this)) break;
        }
        return bytes;
    }

    /// <summary>Visits every file in the subtree; return false from <paramref name="shouldDescend"/> to skip a folder.</summary>
    public void ForEachFile(Action<DirectoryNode, FileEntry> body, Func<DirectoryNode, bool>? shouldDescend = null)
    {
        var stack = new Stack<DirectoryNode>();
        stack.Push(this);
        while (stack.Count > 0)
        {
            var node = stack.Pop();
            foreach (var file in node.Files) body(node, file);
            foreach (var dir in node.Directories)
                if (shouldDescend?.Invoke(dir) ?? true) stack.Push(dir);
        }
    }
}

public sealed record ScanResult(
    ScanTarget Target,
    DirectoryNode Root,
    DateTime StartedUtc,
    TimeSpan Duration,
    int UnreadableDirectories,
    bool WasCancelled)
{
    public long TotalAllocated => Root.AllocatedSize;
    public int TotalFiles => Root.FileCount;
}
