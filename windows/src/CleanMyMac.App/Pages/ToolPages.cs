using CleanMyMac.Localization;
using CleanMyMac.State;
using CleanMyMac.UI;
using DiskKit;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CleanMyMac.Pages;

public sealed class DuplicatesPage : IPage
{
    private readonly AppState _s;
    private readonly Localizer _l;
    private readonly DialogService _dialogs;
    private string? _selectedGroup;
    private readonly Dictionary<string, HashSet<string>> _marked = new();
    private static readonly long[] SizeOptions = { 0, ByteFormatter.Megabyte, 10 * ByteFormatter.Megabyte, 100 * ByteFormatter.Megabyte, 1000 * ByteFormatter.Megabyte };

    public DuplicatesPage(AppState state, Localizer l, DialogService dialogs)
    {
        _s = state;
        _l = l;
        _dialogs = dialogs;
    }

    public double MinWidth => 700;

    public UIElement Build()
    {
        var root = new Grid { Margin = new Thickness(24), RowSpacing = 14 };
        for (var i = 0; i < 3; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        root.Children.Add(Ui.Column(4, Ui.Title(_l.T("duplicates.title")),
            Ui.Caption(_l.T("duplicates.subtitle", _s.Duplicates.Count.ToString(), _l.Number(_s.Duplicates.Sum(g => g.Files.Count)), _l.Bytes(_s.DuplicateReclaimable)))));

        // Filters live on their own row and wrap, so long labels never push the page wider than the window.
        var filters = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal };
        var skipDev = new CheckBox { Content = _l.T("duplicates.skipDev"), IsChecked = _s.Settings.DuplicateSkipDeveloper, Margin = new Thickness(0, 0, 16, 0) };
        var skipSys = new CheckBox { Content = _l.T("win.duplicates.skipSystem"), IsChecked = _s.Settings.DuplicateSkipSystem, Margin = new Thickness(0, 0, 16, 0) };
        var size = new ComboBox { Header = null, MinWidth = 160 };
        foreach (var o in SizeOptions) size.Items.Add(o == 0 ? _l.T("duplicates.anySize") : $"{_l.T("duplicates.minSize")} {_l.Bytes(o)}");
        size.SelectedIndex = Math.Max(0, Array.IndexOf(SizeOptions, _s.Settings.DuplicateMinimumSize));
        void Apply()
        {
            _s.Settings.DuplicateSkipDeveloper = skipDev.IsChecked == true;
            _s.Settings.DuplicateSkipSystem = skipSys.IsChecked == true;
            _s.Settings.DuplicateMinimumSize = SizeOptions[Math.Max(0, size.SelectedIndex)];
            _s.Settings.Save();
            _marked.Clear();
            _ = _s.FindDuplicatesAsync();
        }
        skipDev.Click += (_, _) => Apply();
        skipSys.Click += (_, _) => Apply();
        size.SelectionChanged += (_, _) => { if (size.SelectedIndex >= 0 && SizeOptions[size.SelectedIndex] != _s.Settings.DuplicateMinimumSize) Apply(); };
        foreach (var c in new Control[] { skipDev, skipSys, size }) { c.IsEnabled = !_s.IsBusy; filters.Children.Add(c); }
        Grid.SetRow(filters, 1);
        root.Children.Add(filters);

        var notice = Ui.Notice(_l.T("win.duplicates.notice"));
        Grid.SetRow(notice, 2);
        root.Children.Add(notice);

        UIElement body;
        if (_s.Scans.Count == 0) body = Ui.EmptyState("", _l.T("duplicates.empty.title"), _l.T("duplicates.empty.message"), _l.T("action.scanAll"), _s.ScanAll);
        else if (_s.IsFindingDuplicates) body = Ui.Column(12, new ProgressRing { IsActive = true }, Ui.Text(_l.T("duplicates.searching")));
        else if (_s.Duplicates.Count == 0) body = Ui.EmptyState("", _l.T("duplicates.none.title"), _l.T("duplicates.none.message"));
        else body = Groups();
        Grid.SetRow((FrameworkElement)body, 3);
        root.Children.Add(body);
        return root;
    }

    private UIElement Groups()
    {
        var groups = _s.Duplicates;
        var selected = groups.FirstOrDefault(g => g.Key == _selectedGroup) ?? groups[0];
        _selectedGroup = selected.Key;

        var list = new ListView { SelectionMode = ListViewSelectionMode.Single };
        foreach (var g in groups.Take(1000))
        {
            var row = Ui.Split(Ui.Text(g.DisplayName, 14, wrap: false), Ui.Row(10, Ui.Caption(g.Files.Count.ToString()), Ui.Text(_l.Bytes(g.ReclaimableSize), 14, true)));
            row.Tag = g.Key;
            ToolTipService.SetToolTip(row, g.DisplayName);
            list.Items.Add(row);
            if (g.Key == selected.Key) list.SelectedItem = row;
        }
        list.SelectionChanged += (_, _) => { if (list.SelectedItem is FrameworkElement { Tag: string k } && k != _selectedGroup) { _selectedGroup = k; _s.Refresh(); } };

        var ticked = _marked.TryGetValue(selected.Key, out var m) ? m : selected.Files.Skip(1).Select(f => f.Path).ToHashSet();
        _marked[selected.Key] = ticked;
        var files = Ui.Column(0);
        foreach (var f in selected.Files)
        {
            var box = new CheckBox { IsChecked = ticked.Contains(f.Path), MinWidth = 0 };
            box.Click += (_, _) => { if (box.IsChecked == true) ticked.Add(f.Path); else ticked.Remove(f.Path); _s.Refresh(); };
            var folder = Path.GetDirectoryName(f.Path) ?? f.Path;
            var title = Ui.Row(6, Ui.Text(folder, 14, wrap: false));
            if (f == selected.Newest) title.Children.Add(Ui.Badge(_l.T("duplicates.newest"), Theme.For(Severity.Ok)));
            ToolTipService.SetToolTip(title, f.Path);
            var info = Ui.Column(2, title, Ui.Caption($"{f.VolumeName} · {_l.Date(f.ModifiedUtc)}", wrap: false));
            var actions = Ui.Row(6, Ui.Text(_l.Bytes(f.AllocatedSize), 14),
                Ui.Button(_l.T("action.quickLook"), () => Shell.Open(f.Path)),
                Ui.Button(_l.T("action.revealInFinder"), () => Shell.RevealInExplorer(f.Path)));
            var row = new Grid { ColumnSpacing = 8, Padding = new Thickness(12, 8, 12, 8), BorderBrush = Ui.CardStroke, BorderThickness = new Thickness(0, 0, 0, 1) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(box);
            Grid.SetColumn(info, 1);
            row.Children.Add(info);
            Grid.SetColumn(actions, 2);
            row.Children.Add(actions);
            files.Children.Add(row);
        }
        var chosen = selected.Files.Where(f => ticked.Contains(f.Path)).ToList();
        var trash = Ui.Button(_l.T("duplicates.trashSelected", chosen.Count.ToString()),
            () => _ = _dialogs.ConfirmTrashAsync(chosen.Select(f => new TrashItem(f.Path, f.AllocatedSize, false)).ToList()), glyph: "");
        trash.IsEnabled = chosen.Count > 0 && chosen.Count < selected.Files.Count;
        var bar = Ui.ActionBar(_l.T("selection.summary", chosen.Count.ToString(), _l.Bytes(chosen.Sum(f => f.AllocatedSize))),
            Ui.Button(_l.T("duplicates.keepNewest"), () => { _marked[selected.Key] = selected.Files.Skip(1).Select(f => f.Path).ToHashSet(); _s.Refresh(); }),
            trash);

        var detail = new Grid { BorderBrush = Ui.CardStroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8) };
        detail.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        detail.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        detail.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = Ui.Column(2, Ui.Text(selected.DisplayName, 15, true), Ui.Caption(_l.T("duplicates.groupSummary", selected.Files.Count.ToString(), _l.Bytes(selected.TotalSize), _l.Bytes(selected.ReclaimableSize))));
        header.Padding = new Thickness(12);
        detail.Children.Add(header);
        var scroller = new ScrollViewer { Content = files };
        Grid.SetRow(scroller, 1);
        detail.Children.Add(scroller);
        Grid.SetRow((FrameworkElement)bar, 2);
        detail.Children.Add(bar);

        var listBorder = new Border { Child = list, BorderBrush = Ui.CardStroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8) };
        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star), MinWidth = 220, MaxWidth = 340 });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star), MinWidth = 380 });
        grid.Children.Add(listBorder);
        Grid.SetColumn(detail, 1);
        grid.Children.Add(detail);
        return grid;
    }
}

public sealed class DockerPage : IPage
{
    private readonly AppState _s;
    private readonly Localizer _l;
    private readonly DialogService _dialogs;
    private readonly HashSet<string> _unselected = new();

    public DockerPage(AppState state, Localizer l, DialogService dialogs)
    {
        _s = state;
        _l = l;
        _dialogs = dialogs;
    }

    public double MinWidth => 600;

    public UIElement Build()
    {
        // First visit: check Docker after this render (never re-enter rendering from Build).
        if (_s.Docker is DockerState.Unknown)
            Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread()?.TryEnqueue(_s.RefreshDocker);
        var subtitle = _s.Docker switch
        {
            DockerState.Ready r => $"{_l.T("docker.engine")} {r.Report.ServerVersion} · {r.Report.Binary}",
            DockerState.NotRunning n => n.Binary,
            _ => "",
        };
        var recheck = Ui.Button(_l.T("docker.recheck"), _s.RefreshDocker, glyph: "");
        recheck.IsEnabled = !_s.IsDockerWorking;
        var page = Ui.Column(16, Ui.Split(Ui.Column(4, Ui.Title(_l.T("docker.title")), Ui.Caption(subtitle, wrap: false)), recheck), Steps());

        switch (_s.Docker)
        {
            case DockerState.Unknown or DockerState.Checking:
                page.Children.Add(Ui.Row(10, new ProgressRing { IsActive = true, Width = 20, Height = 20 }, Ui.Text(_l.T("docker.checking"))));
                break;
            case DockerState.NotInstalled:
                page.Children.Add(Ui.Card(Ui.Column(6, Ui.Heading(_l.T("docker.notInstalled.title")), Ui.Text(_l.T("docker.notInstalled.message"), 14, color: Ui.Secondary))));
                break;
            case DockerState.NotRunning:
                page.Children.Add(Ui.Card(Ui.Column(10, Ui.Heading(_l.T("docker.notRunning.title")), Ui.Text(_l.T("win.docker.notRunning.message"), 14, color: Ui.Secondary),
                    Ui.Row(8, Ui.Button(_l.T("docker.openApp"), _s.OpenDockerDesktop, accent: true), Ui.Button(_l.T("docker.recheck"), _s.RefreshDocker)))));
                break;
            case DockerState.Ready r:
                Ready(page, r.Report);
                break;
        }
        page.Margin = new Thickness(24);
        return new ScrollViewer { Content = page };
    }

    private UIElement Steps()
    {
        var (reached, failed) = _s.Docker switch
        {
            DockerState.NotInstalled => (0, 1),
            DockerState.NotRunning => (1, 2),
            DockerState.Ready => (3, 0),
            _ => (0, 0),
        };
        var row = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal };
        for (var step = 1; step <= 4; step++)
        {
            var color = step <= reached ? Theme.For(Severity.Ok) : step == failed ? Theme.For(Severity.Warning) : Windows.UI.Color.FromArgb(255, 140, 140, 140);
            var isIcon = step <= reached || step == failed;
            var label = new TextBlock
            {
                Text = isIcon ? (step <= reached ? "\uE73E" : "\uE711") : step.ToString(),
                FontSize = 11,
                Foreground = Ui.Brush(Microsoft.UI.Colors.White),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            if (isIcon) label.FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Segoe Fluent Icons,Segoe MDL2 Assets");
            var marker = new Border { Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = Ui.Brush(color), Child = label };
            var item = Ui.Row(8, marker, Ui.Text(_l.T($"docker.step{step}"), 13));
            item.Margin = new Thickness(0, 0, 22, 0);
            row.Children.Add(item);
        }
        return Ui.Card(row, 12);
    }

    private void Ready(StackPanel page, DockerReport report)
    {
        var stats = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 200 };
        void Stat(string title, string value, string caption, Windows.UI.Color? tint = null)
        {
            var card = Ui.Card(Ui.Column(4, Ui.Caption(title), Ui.Text(value, 22, true, tint is { } t ? Ui.Brush(t) : null), Ui.Caption(caption)), 14);
            card.Margin = new Thickness(0, 0, 12, 12);
            stats.Children.Add(card);
        }
        Stat(_l.T("docker.stat.dangling"), _l.Bytes(report.DanglingBytes), _l.T("docker.stat.images", report.DanglingImages.Count.ToString()), report.DanglingImages.Count > 0 ? Theme.For(Severity.Warning) : null);
        if (report.Usage(DockerUsageKind.Images) is { } images) Stat(_l.T("docker.stat.allImages"), _l.Bytes(images.SizeBytes), _l.T("docker.stat.reclaimable", _l.Bytes(images.ReclaimableBytes)));
        if (report.Usage(DockerUsageKind.BuildCache) is { } cache) Stat(_l.T("docker.stat.buildCache"), _l.Bytes(cache.SizeBytes), _l.T("docker.stat.reclaimable", _l.Bytes(cache.ReclaimableBytes)));
        if (report.VirtualDiskBytes is { } disk) Stat(_l.T("win.docker.stat.virtualDisk"), _l.Bytes(disk), _l.T("docker.stat.virtualDiskCaption"));
        page.Children.Add(stats);

        if (report.DanglingImages.Count == 0)
        {
            page.Children.Add(Ui.Card(Ui.Row(10, Ui.Icon("", 16, Theme.For(Severity.Ok)), Ui.Text(_l.T("docker.noDangling")))));
        }
        else
        {
            var list = Ui.Column(0);
            var toggle = Ui.Button(_unselected.Count == 0 ? _l.T("docker.selectNone") : _l.T("docker.selectAll"), () =>
            {
                if (_unselected.Count == 0) foreach (var i in report.DanglingImages) _unselected.Add(i.Id); else _unselected.Clear();
                _s.Refresh();
            });
            var head = Ui.Split(Ui.Heading(_l.T("docker.danglingList")), toggle);
            head.Padding = new Thickness(12);
            list.Children.Add(head);
            foreach (var image in report.DanglingImages)
            {
                var box = new CheckBox { IsChecked = !_unselected.Contains(image.Id), MinWidth = 0 };
                box.Click += (_, _) => { if (box.IsChecked == true) _unselected.Remove(image.Id); else _unselected.Add(image.Id); _s.Refresh(); };
                var left = Ui.Row(12, box, new TextBlock { Text = image.Id[..Math.Min(12, image.Id.Length)], FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), VerticalAlignment = VerticalAlignment.Center },
                    Ui.Caption($"{image.Repository}:{image.Tag}", wrap: false));
                var row = Ui.Split(left, Ui.Row(12, Ui.Caption(image.CreatedSince), Ui.Text(_l.Bytes(image.SizeBytes), 14, true)));
                row.Padding = new Thickness(12, 6, 12, 6);
                row.BorderBrush = Ui.CardStroke;
                row.BorderThickness = new Thickness(0, 1, 0, 0);
                list.Children.Add(row);
            }
            var chosen = report.DanglingImages.Where(i => !_unselected.Contains(i.Id)).ToList();
            var remove = Ui.Button(_l.T("docker.removeButton", chosen.Count.ToString()), () => _ = _dialogs.ConfirmDockerRemovalAsync(chosen), glyph: "");
            remove.IsEnabled = chosen.Count > 0 && !_s.IsDockerWorking;
            list.Children.Add(Ui.ActionBar(_l.T("docker.selected", chosen.Count.ToString(), _l.Bytes(chosen.Sum(i => i.SizeBytes))), remove));
            page.Children.Add(Ui.Card(list, 0));
        }
        page.Children.Add(Ui.Notice(_l.T("win.docker.note"), InfoBarSeverity.Informational));
    }
}

public sealed class LogPage : IPage
{
    private readonly AppState _s;
    private readonly Localizer _l;

    public LogPage(AppState state, Localizer l)
    {
        _s = state;
        _l = l;
    }

    public double MinWidth => 560;

    public UIElement Build()
    {
        var clear = Ui.Button(_l.T("log.clear"), _s.ClearDeletionLog);
        clear.IsEnabled = _s.DeletionLog.Count > 0;
        var header = Ui.Split(Ui.Column(4, Ui.Title(_l.T("log.title")), Ui.Caption(_l.T("log.subtitle", _l.Bytes(_s.DeletionLog.Sum(r => r.Bytes))))),
            Ui.Row(8, Ui.Button(_l.T("win.log.openRecycleBin"), Shell.OpenRecycleBin, glyph: ""), clear));

        var root = new Grid { Margin = new Thickness(24), RowSpacing = 14 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(header);
        var hint = Ui.Notice(_l.T("win.log.restoreHint"), InfoBarSeverity.Informational);
        Grid.SetRow(hint, 1);
        root.Children.Add(hint);

        UIElement body;
        if (_s.DeletionLog.Count == 0) body = Ui.EmptyState("", _l.T("log.empty"), "");
        else
        {
            var list = new ListView { SelectionMode = ListViewSelectionMode.None };
            foreach (var r in _s.DeletionLog)
            {
                var glyph = r.Kind switch { DeletionKind.Folder => "", DeletionKind.DockerImage => "", _ => "" };
                list.Items.Add(Ui.Split(Ui.Row(10, Ui.Icon(glyph), Ui.Column(0, Ui.Text(r.Path, 14, wrap: false), Ui.Caption(_l.Date(r.DateUtc)))), Ui.Text(_l.Bytes(r.Bytes), 14)));
            }
            body = list;
        }
        Grid.SetRow((FrameworkElement)body, 2);
        root.Children.Add(body);
        return root;
    }
}
