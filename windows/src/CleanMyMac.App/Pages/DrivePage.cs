using CleanMyMac.Localization;
using CleanMyMac.State;
using CleanMyMac.UI;
using DiskKit;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace CleanMyMac.Pages;

public sealed class DrivePage : IPage
{
    private readonly AppState _s;
    private readonly Localizer _l;
    private readonly DialogService _dialogs;
    private readonly string _volumeId;
    private readonly HashSet<string> _selection = new(StringComparer.OrdinalIgnoreCase);
    private int _sort; // 0 size, 1 name, 2 date

    public DrivePage(AppState state, Localizer l, DialogService dialogs, string volumeId)
    {
        _s = state;
        _l = l;
        _dialogs = dialogs;
        _volumeId = volumeId;
    }

    public double MinWidth => 720;
    public double MinHeight => 560;

    private DriveTab Tab
    {
        get => _s.DriveTabs.TryGetValue(_volumeId, out var t) ? t : DriveTab.Categories;
        set => _s.DriveTabs[_volumeId] = value;
    }

    public UIElement Build()
    {
        if (_s.Volume(_volumeId) is not { } volume)
            return Ui.EmptyState("", _l.T("drive.missing"), "");

        var root = new Grid { Margin = new Thickness(24), RowSpacing = 14 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _s.Scans.TryGetValue(_volumeId, out var scan);
        root.Children.Add(Header(volume, scan));

        if (scan is null)
        {
            var empty = Ui.EmptyState(Theme.Glyph(volume), _l.T("drive.notScanned.title"),
                volume.IsExternal ? _l.T("drive.notScanned.external") : _l.T("drive.notScanned.message"),
                _l.T("drive.scanThis"), () => _s.Scan(volume));
            Grid.SetRow((FrameworkElement)empty, 2);
            root.Children.Add(empty);
            return root;
        }

        var bar = new SelectorBar();
        foreach (var tab in Enum.GetValues<DriveTab>())
            bar.Items.Add(new SelectorBarItem { Text = _l.T("drive.tab." + (tab switch { DriveTab.Categories => "categories", DriveTab.Folders => "folders", _ => "largeFiles" })), Tag = tab, IsSelected = tab == Tab });
        bar.SelectionChanged += (_, _) =>
        {
            if (bar.SelectedItem?.Tag is DriveTab t && t != Tab) { Tab = t; _selection.Clear(); _s.Refresh(); }
        };
        Grid.SetRow(bar, 1);
        root.Children.Add(bar);

        UIElement body = Tab switch
        {
            DriveTab.Folders => Folders(scan),
            DriveTab.LargeFiles => LargeFiles(scan),
            _ => Categories(scan),
        };
        Grid.SetRow((FrameworkElement)body, 2);
        root.Children.Add(body);
        return root;
    }

    private UIElement Header(VolumeInfo v, VolumeScan? scan)
    {
        var severity = _s.SeverityOf(v);
        var segments = new List<(double, Windows.UI.Color)>();
        if (scan is not null && v.TotalBytes > 0)
        {
            segments.AddRange(scan.Categories.Sorted.Select(t => ((double)t.Bytes / v.TotalBytes, Theme.For(t.Category))));
            var unscanned = v.UsedBytes - scan.Categories.CategorizedBytes;
            if (unscanned > 0) segments.Add(((double)unscanned / v.TotalBytes, Theme.Unscanned));
        }
        else segments.Add((v.UsedRatio, Theme.For(severity)));

        var parts = new List<string> { _l.T("volume.usedOf", _l.Bytes(v.UsedBytes), _l.Bytes(v.TotalBytes)), v.Format, _l.T("volume.kind." + SummaryPage.KindKey(v.Kind)) };
        if (scan is not null) parts.Add(_l.T("drive.scannedAt", _l.Date(scan.ScannedUtc), _l.Number(scan.Result.TotalFiles), _l.Duration(scan.Result.Duration)));

        var rescan = Ui.Button(scan is null ? _l.T("drive.scanThis") : _l.T("drive.rescan"), () => _s.Scan(v), glyph: "");
        rescan.IsEnabled = !_s.IsScanning;
        rescan.VerticalAlignment = VerticalAlignment.Top;
        return Ui.Split(Ui.Column(8,
            Ui.Row(10, Ui.Text(v.Name, 24, true, wrap: false), Ui.Badge($"{_l.T("severity." + SummaryPage.Key(severity))} · {_l.T("volume.freeShort", _l.Bytes(v.AvailableBytes))}", Theme.For(severity))),
            Ui.CapacityBar(segments, 10),
            Ui.Caption(string.Join(" · ", parts.Where(p => p.Length > 0)))), rescan);
    }

    // ---------------- Categories ----------------

    private UIElement Categories(VolumeScan scan)
    {
        var totals = scan.Categories.Sorted;
        var unscanned = Math.Max(0, scan.Volume.UsedBytes - scan.Categories.CategorizedBytes);
        var baseBytes = (double)Math.Max(1, scan.Categories.CategorizedBytes + unscanned);
        var list = Ui.Column(10, Ui.Heading(_l.T("drive.categories.title")));
        foreach (var (c, b) in totals)
            list.Children.Add(CategoryRow(Theme.Glyph(c), Theme.For(c), _l.T("category." + SummaryPage.CategoryKey(c)), _l.T("category." + SummaryPage.CategoryKey(c) + ".detail"), b, b / baseBytes));
        if (unscanned > 0)
            list.Children.Add(CategoryRow("", Theme.Unscanned, _l.T("category.unscanned"), _l.T("win.category.unscanned.detail"), unscanned, unscanned / baseBytes));

        var content = Ui.Column(16, Ui.Card(list));
        if (scan.Categories.Hotspots.Count > 0)
        {
            var spots = Ui.Column(0, Ui.Heading(_l.T("drive.hotspots.title")), Ui.Caption(_l.T("drive.hotspots.subtitle")));
            foreach (var h in scan.Categories.Hotspots)
            {
                var key = "hotspot." + SummaryPage.HotspotKey(h.Kind);
                var buttons = Ui.Row(8, Ui.Text(_l.Bytes(h.Bytes), 14, true),
                    Ui.Button(_l.T("action.show"), () => _s.Navigate(new FindingTarget.Folder(scan.Volume.Id, h.Path))),
                    Ui.Button(_l.T("action.revealInFinder"), () => Shell.RevealInExplorer(h.Path)));
                var row = Ui.Split(Ui.Column(2, Ui.Text(_l.T(key), 14, true), Ui.Caption(h.Path, wrap: false)), buttons);
                row.Padding = new Thickness(0, 10, 0, 10);
                row.BorderBrush = Ui.CardStroke;
                row.BorderThickness = new Thickness(0, 1, 0, 0);
                spots.Children.Add(row);
            }
            content.Children.Add(Ui.Card(spots));
        }
        return new ScrollViewer { Content = content };
    }

    private UIElement CategoryRow(string glyph, Windows.UI.Color color, string title, string subtitle, long bytes, double fraction)
    {
        var top = Ui.Split(Ui.Row(8, Ui.Text(title, 14, true, wrap: false), Ui.Caption(subtitle, wrap: false)),
                           Ui.Row(12, Ui.Text(_l.Bytes(bytes), 14, true), Ui.Caption(_l.Percent(fraction))));
        var row = new Grid { ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(Ui.Icon(glyph, 16, color));
        var right = Ui.Column(4, top, Ui.CapacityBar(new[] { (fraction, color) }, 6));
        Grid.SetColumn(right, 1);
        row.Children.Add(right);
        return row;
    }

    // ---------------- Folders ----------------

    private DirectoryNode Current(VolumeScan scan) =>
        _s.FolderPaths.TryGetValue(_volumeId, out var p) && scan.Result.Root.NodeAtPath(p) is { } n ? n : scan.Result.Root;

    private sealed record Entry(string Path, string Name, bool IsDirectory, long Bytes, int FileCount, DateTime? Modified, bool Unreadable, StorageCategory? Category);

    private List<Entry> Entries(DirectoryNode node)
    {
        var items = node.Directories.Select(d => new Entry(d.Path, d.Name, true, d.AllocatedSize, d.FileCount, d.ModifiedUtc, d.IsUnreadable, null))
            .Concat(node.Files.Select(f => new Entry(node.ChildPath(f.Name), f.Name, false, f.AllocatedSize, 1, f.ModifiedUtc, false, Categorizer.CategoryForFile(f.Name))));
        return (_sort switch
        {
            1 => items.OrderBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase),
            2 => items.OrderByDescending(i => i.Modified ?? DateTime.MinValue),
            _ => items.OrderByDescending(i => i.Bytes),
        }).Take(500).ToList();
    }

    private void Open(string path)
    {
        _s.FolderPaths[_volumeId] = path;
        _selection.Clear();
        _s.Refresh();
    }

    private UIElement Folders(VolumeScan scan)
    {
        var node = Current(scan);
        var entries = Entries(node);

        var crumbs = new List<DirectoryNode>();
        for (var n = node; n is not null; n = n.Parent) crumbs.Insert(0, n);
        var breadcrumb = new BreadcrumbBar { ItemsSource = crumbs.Select(c => c.Parent is null ? c.Path : c.Name).ToList() };
        breadcrumb.ItemClicked += (_, e) => Open(crumbs[e.Index].Path);

        var sort = new ComboBox { MinWidth = 180 };
        foreach (var key in new[] { "folders.sort.size", "folders.sort.name", "folders.sort.date" }) sort.Items.Add(_l.T(key));
        sort.SelectedIndex = _sort;
        sort.SelectionChanged += (_, _) => { _sort = sort.SelectedIndex; _s.Refresh(); };

        var list = new ListView { SelectionMode = ListViewSelectionMode.Extended };
        foreach (var e in entries) list.Items.Add(FolderRow(e, node.AllocatedSize));
        foreach (var item in list.Items.OfType<FrameworkElement>()) if (_selection.Contains((string)item.Tag)) list.SelectedItems.Add(item);
        list.SelectionChanged += (_, _) =>
        {
            _selection.Clear();
            foreach (var item in list.SelectedItems.OfType<FrameworkElement>()) _selection.Add((string)item.Tag);
        };
        list.DoubleTapped += (_, e) =>
        {
            if (list.SelectedItems.Count == 1 && list.SelectedItem is FrameworkElement { Tag: string path })
            {
                var entry = entries.FirstOrDefault(x => x.Path == path);
                if (entry is { IsDirectory: true }) Open(path); else if (entry is not null) Shell.Open(path);
            }
        };

        var treemap = new TreemapControl(entries.Where(e => e.Bytes > 0).Select(e => new TreemapControl.Item(e.Path, e.Name, e.Bytes, e.IsDirectory, e.Category)).ToList(), _l)
        {
            MinWidth = 300,
        };
        treemap.Opened += path => { if (entries.Any(e => e.Path == path && e.IsDirectory)) Open(path); };

        var actions = Ui.ActionBar(
            _l.T("folders.itemsSummary", _l.Number(entries.Count), _l.Bytes(node.AllocatedSize)),
            Ui.Button(_l.T("action.revealInFinder"), () => { foreach (var p in _selection) Shell.RevealInExplorer(p); }),
            Ui.Button(_l.T("action.quickLook"), () => { foreach (var p in _selection.Take(1)) Shell.Open(p); }),
            Ui.Button(_l.T("action.moveToTrash"), () => _ = _dialogs.ConfirmTrashAsync(entries.Where(e => _selection.Contains(e.Path)).Select(e => new TrashItem(e.Path, e.Bytes, e.IsDirectory)).ToList()), glyph: ""));

        var listPanel = new Grid { BorderBrush = Ui.CardStroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8) };
        listPanel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        listPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        listPanel.Children.Add(list);
        Grid.SetRow((FrameworkElement)actions, 1);
        listPanel.Children.Add(actions);

        var body = new Grid { ColumnSpacing = 16 };
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star), MinWidth = 300, MaxWidth = 520 });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star), MinWidth = 340 });
        body.Children.Add(treemap);
        Grid.SetColumn(listPanel, 1);
        body.Children.Add(listPanel);

        var root = new Grid { RowSpacing = 10 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(Ui.Split(breadcrumb, sort));
        Grid.SetRow(body, 1);
        root.Children.Add(body);
        if (scan.Result.UnreadableDirectories > 0)
        {
            var note = Ui.Caption(_l.T("win.folders.unreadableNote", _l.Number(scan.Result.UnreadableDirectories)));
            Grid.SetRow(note, 2);
            root.Children.Add(note);
        }
        return root;
    }

    private FrameworkElement FolderRow(Entry e, long parentBytes)
    {
        var glyph = e.Unreadable ? "" : e.IsDirectory ? "" : "";
        var color = e.IsDirectory ? Theme.Accent : Theme.For(e.Category ?? StorageCategory.Other);
        var name = Ui.Column(0, Ui.Text(e.Name, 14, wrap: false));
        if (e.IsDirectory) name.Children.Add(Ui.Caption(e.Unreadable ? _l.T("folders.unreadable") : _l.T("folders.fileCount", _l.Number(e.FileCount)), wrap: false));
        var grid = new Grid { ColumnSpacing = 10, Padding = new Thickness(0, 4, 0, 4), Tag = e.Path };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(84) });
        grid.Children.Add(Ui.Icon(glyph, 16, color));
        Grid.SetColumn(name, 1);
        grid.Children.Add(name);
        var bar = Ui.CapacityBar(new[] { (parentBytes > 0 ? (double)e.Bytes / parentBytes : 0, Theme.Accent) }, 6);
        bar.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(bar, 2);
        grid.Children.Add(bar);
        var size = Ui.Text(_l.Bytes(e.Bytes), 14, true, wrap: false);
        size.HorizontalAlignment = HorizontalAlignment.Right;
        size.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(size, 3);
        grid.Children.Add(size);
        ToolTipService.SetToolTip(grid, e.Path);
        return grid;
    }

    // ---------------- Large files ----------------

    private UIElement LargeFiles(VolumeScan scan)
    {
        var files = scan.LargeFiles;
        if (files.Count == 0) return Ui.EmptyState("", _l.T("largeFiles.none"), "");
        var list = new ListView { SelectionMode = ListViewSelectionMode.Extended };
        foreach (var f in files)
        {
            var grid = new Grid { ColumnSpacing = 10, Padding = new Thickness(0, 4, 0, 4), Tag = f.Path };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(84) });
            grid.Children.Add(Ui.Icon(Theme.Glyph(f.Category), 16, Theme.For(f.Category)));
            var name = Ui.Column(0, Ui.Text(f.Name, 14, wrap: false), Ui.Caption(f.Path, wrap: false));
            Grid.SetColumn(name, 1);
            grid.Children.Add(name);
            var date = Ui.Caption(_l.Date(f.ModifiedUtc, false), wrap: false);
            date.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(date, 2);
            grid.Children.Add(date);
            var size = Ui.Text(_l.Bytes(f.AllocatedSize), 14, true, wrap: false);
            size.HorizontalAlignment = HorizontalAlignment.Right;
            size.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(size, 3);
            grid.Children.Add(size);
            list.Items.Add(grid);
        }
        list.SelectionChanged += (_, _) =>
        {
            _selection.Clear();
            foreach (var item in list.SelectedItems.OfType<FrameworkElement>()) _selection.Add((string)item.Tag);
        };
        list.DoubleTapped += (_, _) => { if (list.SelectedItem is FrameworkElement { Tag: string p }) Shell.Open(p); };

        var actions = Ui.ActionBar(
            _l.T("largeFiles.total", _l.Bytes(files.Sum(f => f.AllocatedSize))),
            Ui.Button(_l.T("action.revealInFinder"), () => { foreach (var p in _selection) Shell.RevealInExplorer(p); }),
            Ui.Button(_l.T("action.quickLook"), () => { foreach (var p in _selection.Take(1)) Shell.Open(p); }),
            Ui.Button(_l.T("action.moveToTrash"), () => _ = _dialogs.ConfirmTrashAsync(files.Where(f => _selection.Contains(f.Path)).Select(f => new TrashItem(f.Path, f.AllocatedSize, false)).ToList()), glyph: ""));

        var root = new Grid { RowSpacing = 8 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(Ui.Caption(_l.T("largeFiles.subtitle", _l.Bytes(_s.Settings.LargeFileMinimumBytes), files.Count.ToString())));
        Grid.SetRow(list, 1);
        root.Children.Add(list);
        Grid.SetRow((FrameworkElement)actions, 2);
        root.Children.Add(actions);
        return root;
    }
}
