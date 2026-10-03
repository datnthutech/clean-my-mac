using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace DiskKit;

/// <summary>
/// Fast Windows reader: one <c>GetFileInformationByHandleEx(FileIdBothDirectoryInfo)</c> call returns name,
/// attributes, size, <b>allocation size</b> and <b>file ID</b> for many entries at once — the Windows
/// equivalent of macOS <c>getattrlistbulk</c>. File IDs let the scanner count hard links (WinSxS) once.
/// </summary>
public sealed class WindowsBulkDirectoryReader : IDirectoryReader
{
    private const uint FILE_LIST_DIRECTORY = 0x0001;
    private const uint FILE_SHARE_ALL = 0x1 | 0x2 | 0x4;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const int FileIdBothDirectoryInfo = 10;
    private const int FileIdBothDirectoryRestartInfo = 11;
    private const int ERROR_NO_MORE_FILES = 18;
    private const uint ATTR_DIRECTORY = 0x10;
    private const uint ATTR_REPARSE_POINT = 0x400;
    private const int BufferSize = 64 * 1024;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, IntPtr buffer, uint size);

    public IReadOnlyList<RawEntry> Read(string path)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var longPath = path.StartsWith(@"\\?\", StringComparison.Ordinal) ? path : @"\\?\" + path;
        using var handle = CreateFileW(longPath, FILE_LIST_DIRECTORY, FILE_SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            var error = Marshal.GetLastWin32Error();
            if (error == 5) throw new UnauthorizedAccessException(path);
            throw new IOException(new Win32Exception(error).Message + ": " + path);
        }

        var entries = new List<RawEntry>();
        var buffer = Marshal.AllocHGlobal(BufferSize);
        try
        {
            var infoClass = FileIdBothDirectoryRestartInfo;
            while (GetFileInformationByHandleEx(handle, infoClass, buffer, BufferSize))
            {
                infoClass = FileIdBothDirectoryInfo;
                var offset = 0;
                while (true)
                {
                    var entry = buffer + offset;
                    var next = Marshal.ReadInt32(entry, 0);
                    var nameLength = Marshal.ReadInt32(entry, 60);
                    var name = Marshal.PtrToStringUni(entry + 104, nameLength / 2);
                    if (name != "." && name != "..")
                    {
                        var attributes = (uint)Marshal.ReadInt32(entry, 56);
                        var isDirectory = (attributes & ATTR_DIRECTORY) != 0;
                        entries.Add(new RawEntry(
                            name,
                            isDirectory,
                            (attributes & ATTR_REPARSE_POINT) != 0,
                            isDirectory ? 0 : Marshal.ReadInt64(entry, 48),
                            isDirectory ? 0 : Marshal.ReadInt64(entry, 40),
                            DateTime.FromFileTimeUtc(Math.Max(0, Marshal.ReadInt64(entry, 24))),
                            (ulong)Marshal.ReadInt64(entry, 96)));
                    }
                    if (next == 0) break;
                    offset += next;
                }
            }
            var last = Marshal.GetLastWin32Error();
            if (last != ERROR_NO_MORE_FILES && last != 0)
            {
                if (last == 5) throw new UnauthorizedAccessException(path);
                throw new IOException(new Win32Exception(last).Message + ": " + path);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
        return entries;
    }
}
