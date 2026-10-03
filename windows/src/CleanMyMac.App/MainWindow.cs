using CleanMyMac.Localization;
using CleanMyMac.Pages;
using CleanMyMac.State;
using CleanMyMac.UI;
using DiskKit;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace CleanMyMac;

/// <summary>
/// Main window: the menu (NavigationView pane) is always expanded and never hidden — whatever a page does,
/// including throwing, only the content area is affected.
/// </summary>
public sealed class MainWindow : Window
{
    private readonly AppState _state;
    private readonly Localizer _l;
    private readonly LaunchOptions _options;
    private readonly NavigationView _nav;
    private readonly PageHost _host = new();
    private readonly Border _progressCard = new();
    private readonly InfoBar _errorBar = new() { Severity = InfoBarSeverity.Error, IsOpen = false };
    private readonly Dictionary<string, IPage> _pages = new();
    private readonly DialogService _dialogs;
    private bool _syncingMenu;

    public MainWindow(AppSettings settings, LaunchOptions options)
    {
        _options = options;
        _l = new Localizer(settings.Language);
        _state = new AppState(settings, DispatcherQueue.GetForCurrentThread());
        _dialogs = new DialogService(this, _state, _l);

        Title = _l.T("app.name");
        // Never open larger than the screen's work area (small laptops, remote sessions, CI machines).
        var area = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(AppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Primary).WorkArea;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(Math.Min(1240, Math.Max(640, area.Width - 40)), Math.Min(800, Math.Max(480, area.Height - 60))));
        try { AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico")); } catch { }
        if (MicaController.IsSupported()) SystemBackdrop = new MicaBackdrop();

        _nav = new NavigationView
        {
            PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
            IsPaneToggleButtonVisible = false,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            IsSettingsVisible = false,
            IsPaneOpen = true,
            OpenPaneLength = 270,
            IsTitleBarAutoPaddingEnabled = false,
        };
        _nav.SelectionChanged += OnMenuSelection;
        // If anything ever closes the pane, open it again: the menu must always be visible.
        _nav.PaneClosing += (_, e) => e.Cancel = true;

        var content = new Grid();
        content.Children.Add(_host);
        _errorBar.VerticalAlignment = VerticalAlignment.Top;
        _errorBar.Margin = new Thickness(16);
        content.Children.Add(_errorBar);
        _progressCard.VerticalAlignment = VerticalAlignment.Bottom;
        _progressCard.HorizontalAlignment = HorizontalAlignment.Center;
        _progressCard.Margin = new Thickness(20);
        _progressCard.Visibility = Visibility.Collapsed;
        content.Children.Add(_progressCard);
        _nav.Content = content;
        Content = _nav;

        _state.Changed += Render;
        _state.ProgressChanged += RenderProgress;
        _state.Message += key => ShowError(_l.T(key));
        _state.ExternalPromptRequested += (internalList, externalList) => _ = _dialogs.ExternalDrivesAsync(internalList, externalList);
        _state.VolumeMounted += v => _ = _dialogs.MountedAsync(v);
        _l.LanguageChanged += () => { Title = _l.T("app.name"); BuildMenu(); Render(); };

        var poll = DispatcherQueue.CreateTimer();
        poll.Interval = TimeSpan.FromSeconds(3);
        poll.Tick += (_, _) => { try { _state.PollVolumes(); } catch { } };
        poll.Start();

        BuildMenu();
        Render();
        _nav.Loaded += (_, _) => OnFirstShown();
    }

    public Localizer Localizer => _l;

    private void OnFirstShown()
    {
        switch (_options.OpenPage)
        {
            case "drive" when _state.Volumes.Count > 0: _state.Select(new NavItem.Volume(_state.Volumes[0].Id)); break;
            case "duplicates": _state.Select(new NavItem.Duplicates()); break;
            case "docker": _state.Select(new NavItem.Docker()); break;
            case "log": _state.Select(new NavItem.DeletionLog()); break;
            case "help": _state.Select(new NavItem.Help()); break;
            case "settings": _state.Select(new NavItem.Settings()); break;
        }
        if (_options.ScanOnLaunch) _state.ScanAll();
        if (!_state.Settings.HasCompletedOnboarding && !_options.SkipOnboarding && _options.OpenPage is null)
            _ = _dialogs.OnboardingAsync();
    }

    public void ShowError(string message)
    {
        _errorBar.Title = _l.T("app.name");
        _errorBar.Message = message;
        _errorBar.IsOpen = true;
    }

    // ---------------- Menu ----------------

    private static string Key(NavItem item) => item switch
    {
        NavItem.Volume v => "volume:" + v.Id,
        _ => item.GetType().Name,
    };

    private void BuildMenu()
    {
        _syncingMenu = true;
        _nav.MenuItems.Clear();
        _nav.FooterMenuItems.Clear();

        var scan = _state.IsScanning
            ? Ui.Button(_l.T("action.cancelScan"), _state.CancelScan, glyph: "")
            : Ui.Button(_l.T("action.scanAll"), _state.ScanAll, accent: true, glyph: "");
        scan.HorizontalAlignment = HorizontalAlignment.Stretch;
        scan.Margin = new Thickness(12, 8, 12, 8);
        _nav.PaneHeader = scan;

        _nav.MenuItems.Add(new NavigationViewItemHeader { Content = _l.T("sidebar.section.overview") });
        _nav.MenuItems.Add(Item(new NavItem.Summary(), _l.T("sidebar.summary"), "", _state.Findings.Count(f => f.Severity >= Severity.Warning)));

        _nav.MenuItems.Add(new NavigationViewItemHeader { Content = _l.T("sidebar.section.drives") });
        foreach (var v in _state.Volumes)
        {
            var label = Ui.Column(0, Ui.Text(v.Name, 14, wrap: false), Ui.Caption(_l.T("volume.freeShort", _l.Bytes(v.AvailableBytes)), wrap: false));
            var row = Ui.Split(label, Ui.Dot(Theme.For(_state.SeverityOf(v))), 8);
            var item = new NavigationViewItem { Content = row, Icon = new FontIcon { Glyph = Theme.Glyph(v) }, Tag = new NavItem.Volume(v.Id) };
            ToolTipService.SetToolTip(item, v.Name);
            _nav.MenuItems.Add(item);
        }

        _nav.MenuItems.Add(new NavigationViewItemHeader { Content = _l.T("sidebar.section.tools") });
        _nav.MenuItems.Add(Item(new NavItem.Duplicates(), _l.T("sidebar.duplicates"), "", _state.Duplicates.Count));
        _nav.MenuItems.Add(Item(new NavItem.Docker(), _l.T("sidebar.docker"), "", _state.Docker.ReportOrNull?.DanglingImages.Count ?? 0));
        _nav.MenuItems.Add(Item(new NavItem.DeletionLog(), _l.T("sidebar.deletionLog"), "", 0));

        _nav.FooterMenuItems.Add(Item(new NavItem.Help(), _l.T("sidebar.help"), "", 0));
        _nav.FooterMenuItems.Add(Item(new NavItem.Settings(), _l.T("sidebar.settings"), "", 0));

        SyncMenuSelection();
        _syncingMenu = false;
    }

    private static NavigationViewItem Item(NavItem tag, string text, string glyph, int badge)
    {
        var item = new NavigationViewItem { Content = text, Icon = new FontIcon { Glyph = glyph }, Tag = tag };
        if (badge > 0) item.InfoBadge = new InfoBadge { Value = badge };
        return item;
    }

    private void SyncMenuSelection()
    {
        var key = Key(_state.Selection);
        var match = _nav.MenuItems.Concat(_nav.FooterMenuItems).OfType<NavigationViewItem>()
            .FirstOrDefault(i => i.Tag is NavItem n && Key(n) == key);
        if (match is not null && !ReferenceEquals(_nav.SelectedItem, match)) _nav.SelectedItem = match;
    }

    private void OnMenuSelection(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (_syncingMenu) return;
        if (args.SelectedItem is NavigationViewItem { Tag: NavItem item }) _state.Select(item);
    }

    // ---------------- Content ----------------

    private string _menuSignature = "";

    private void Render()
    {
        // Rebuild the menu only when what it shows changed (volumes, badges, scan state, language).
        var signature = string.Join("|", _state.Volumes.Select(v => v.Id + v.AvailableBytes / 1_000_000_000 + _state.SeverityOf(v)))
            + $"|{_state.IsScanning}|{_state.Duplicates.Count}|{_state.Findings.Count}|{_state.Docker.ReportOrNull?.DanglingImages.Count}|{_l.Code}";
        if (signature != _menuSignature)
        {
            _menuSignature = signature;
            BuildMenu();
        }
        else
        {
            _syncingMenu = true;
            SyncMenuSelection();
            _syncingMenu = false;
        }

        var key = Key(_state.Selection);
        if (!_pages.TryGetValue(key, out var page))
        {
            page = _state.Selection switch
            {
                NavItem.Volume v => new DrivePage(_state, _l, _dialogs, v.Id),
                NavItem.Duplicates => new DuplicatesPage(_state, _l, _dialogs),
                NavItem.Docker => new DockerPage(_state, _l, _dialogs),
                NavItem.DeletionLog => new LogPage(_state, _l),
                NavItem.Help => new HelpPage(_state, _l),
                NavItem.Settings => new SettingsPage(_state, _l),
                _ => new SummaryPage(_state, _l),
            };
            _pages[key] = page;
        }
        _host.Show(page, _l);
        RenderProgress();
    }

    private void RenderProgress()
    {
        if (_state.ScanStatus is not { } status)
        {
            _progressCard.Visibility = Visibility.Collapsed;
            return;
        }
        var p = _state.Progress;
        var fraction = status.VolumeUsedBytes > 0 ? Math.Min(0.99, (double)p.BytesScanned / status.VolumeUsedBytes) : 0;
        var card = Ui.Column(8,
            Ui.Split(Ui.Text(_l.T("scan.scanning", status.VolumeName), 15, true, wrap: false),
                     Ui.Caption(_l.T("scan.volumeIndex", (status.Index + 1).ToString(), status.Total.ToString()))),
            new ProgressBar { Value = fraction * 100, Maximum = 100 },
            Ui.Split(Ui.Row(16, Ui.Text(_l.T("scan.files", _l.Number(p.FilesScanned)), 13), Ui.Text(_l.Bytes(p.BytesScanned), 13),
                                Ui.Text(_l.Duration(DateTime.UtcNow - status.StartedUtc), 13)),
                     Ui.Button(_l.T("action.cancelScan"), _state.CancelScan)),
            Ui.Caption(p.CurrentPath, wrap: false));
        _progressCard.Child = card;
        _progressCard.Width = 560;
        _progressCard.Padding = new Thickness(16);
        _progressCard.CornerRadius = new CornerRadius(12);
        _progressCard.Background = Ui.ThemeBrush("AcrylicInAppFillColorDefaultBrush");
        _progressCard.BorderBrush = Ui.CardStroke;
        _progressCard.BorderThickness = new Thickness(1);
        _progressCard.Visibility = Visibility.Visible;
    }
}

/// <summary>A page builds its content from <see cref="AppState"/>; it may keep UI state (selection) in fields.</summary>
public interface IPage
{
    /// <summary>Smallest width at which the page lays out cleanly; below it the page scrolls sideways.</summary>
    double MinWidth { get; }
    double MinHeight => 460;
    UIElement Build();
}

/// <summary>
/// The page area with CSS-like <c>overflow: auto</c>: the page fills the viewport but never shrinks below its
/// minimum size (scroll bars appear instead), and an exception while building shows an error panel
/// in the content area only — the menu stays.
/// </summary>
public sealed class PageHost : Grid
{
    private readonly ScrollViewer _scroller = new()
    {
        HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        HorizontalScrollMode = ScrollMode.Auto,
        VerticalScrollMode = ScrollMode.Auto,
    };
    private readonly Grid _frame = new();
    private IPage? _page;

    public PageHost()
    {
        _scroller.Content = _frame;
        Children.Add(_scroller);
        SizeChanged += (_, _) => Fit();
    }

    public void Show(IPage page, Localizer l)
    {
        _page = page;
        UIElement content;
        try
        {
            content = page.Build();
        }
        catch (Exception ex)
        {
            content = Ui.EmptyState("\uE783", l.T("page.error.title"), l.T("page.error.message") + "\n\n" + ex.Message);
        }
        _frame.Children.Clear();
        _frame.Children.Add(content);
        Fit();
    }

    private void Fit()
    {
        if (_page is null) return;
        _frame.Width = Math.Max(ActualWidth, _page.MinWidth);
        _frame.Height = Math.Max(ActualHeight, _page.MinHeight);
    }
}
