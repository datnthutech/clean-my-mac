using CleanMyMac.Localization;
using CleanMyMac.State;
using CleanMyMac.UI;
using DiskKit;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CleanMyMac.Pages;

/// <summary>In-app user guide. Shares topics with the macOS guide; Windows-specific topics use "win.help.*" keys.</summary>
public sealed class HelpPage : IPage
{
    private static readonly (string Key, string Glyph)[] Topics =
    {
        ("quickStart", ""), ("win.admin", ""), ("win.scanning", ""), ("severity", ""), ("folders", ""),
        ("duplicates", ""), ("win.docker", ""), ("win.deleting", ""), ("win.faq", ""),
    };

    private readonly AppState _s;
    private readonly Localizer _l;
    private string _topic = "quickStart";

    public HelpPage(AppState state, Localizer l)
    {
        _s = state;
        _l = l;
    }

    public double MinWidth => 640;

    public UIElement Build()
    {
        var toc = new ListView { SelectionMode = ListViewSelectionMode.Single, Header = Ui.Caption(_l.T("help.toc")) };
        foreach (var (key, glyph) in Topics)
        {
            var row = Ui.Row(10, Ui.Icon(glyph, 14), Ui.Text(_l.T(TitleKey(key)), 14, wrap: false));
            row.Tag = key;
            toc.Items.Add(row);
            if (key == _topic) toc.SelectedItem = row;
        }
        toc.SelectionChanged += (_, _) => { if (toc.SelectedItem is FrameworkElement { Tag: string k } && k != _topic) { _topic = k; _s.Refresh(); } };

        var content = Ui.Column(18, Ui.Split(Ui.Title(_l.T(TitleKey(_topic))), DialogService.LanguagePicker(_s, _l)));
        if (_topic == "quickStart")
        {
            for (var step = 1; step <= 4; step++)
            {
                var number = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(14), Background = Ui.Brush(Theme.Accent), VerticalAlignment = VerticalAlignment.Top,
                    Child = new TextBlock { Text = step.ToString(), Foreground = Ui.Brush(Microsoft.UI.Colors.White), FontWeight = Microsoft.UI.Text.FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
                var text = Ui.Column(4, Ui.Text(_l.T($"win.help.quickStart.step{step}.title"), 15, true), Ui.Text(_l.T($"win.help.quickStart.step{step}.body"), 14));
                if (step == 1 && !_s.IsElevated) text.Children.Add(Ui.Button(_l.T("win.admin.restart"), _s.RestartAsAdministrator));
                var row = new Grid { ColumnSpacing = 14 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.Children.Add(number);
                Grid.SetColumn(text, 1);
                row.Children.Add(text);
                content.Children.Add(row);
            }
            content.Children.Add(SeverityTable());
        }
        else
        {
            foreach (var paragraph in _l.T(BodyKey(_topic)).Split("\n\n"))
                content.Children.Add(new TextBlock { Text = paragraph, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, FontSize = 14, LineHeight = 22 });
            if (_topic == "severity") content.Children.Add(SeverityTable());
            if (_topic == "win.admin")
                content.Children.Add(Ui.Row(10, Ui.Badge(_s.IsElevated ? _l.T("fda.granted") : _l.T("fda.missing"), Theme.For(_s.IsElevated ? Severity.Ok : Severity.Warning)),
                    _s.IsElevated ? new TextBlock() : Ui.Button(_l.T("win.admin.restart"), _s.RestartAsAdministrator, accent: true)));
        }
        content.MaxWidth = 760;
        content.HorizontalAlignment = HorizontalAlignment.Left;
        content.Margin = new Thickness(28);

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var tocBorder = new Border { Child = toc, Padding = new Thickness(8, 24, 8, 8), BorderBrush = Ui.CardStroke, BorderThickness = new Thickness(0, 0, 1, 0) };
        grid.Children.Add(tocBorder);
        var scroller = new ScrollViewer { Content = content };
        Grid.SetColumn(scroller, 1);
        grid.Children.Add(scroller);
        return grid;
    }

    private static string TitleKey(string key) => key.StartsWith("win.") ? $"win.help.{key[4..]}.title" : $"help.{key}.title";
    private static string BodyKey(string key) => key.StartsWith("win.") ? $"win.help.{key[4..]}.body" : key == "folders" ? "win.help.folders.body" : $"help.{key}.body";

    private UIElement SeverityTable()
    {
        var p = _s.Settings.Policy;
        var rows = new[]
        {
            (Severity.Critical, _l.T("win.help.severity.critical", _l.Bytes(p.CriticalFreeBytes), _l.Percent(p.CriticalFreeRatio))),
            (Severity.Warning, _l.T("win.help.severity.warning", _l.Bytes(p.WarningFreeBytes), _l.Percent(p.WarningFreeRatio))),
            (Severity.Ok, _l.T("help.severity.ok")),
        };
        var col = Ui.Column(8, Ui.Text(_l.T("help.severity.tableTitle"), 15, true));
        foreach (var (sev, text) in rows)
        {
            var name = Ui.Text(_l.T("severity." + SummaryPage.Key(sev)), 14, true);
            name.Width = 120;
            col.Children.Add(Ui.Row(10, Ui.Dot(Theme.For(sev), 10), name, Ui.Text(text, 14)));
        }
        return Ui.Card(col);
    }
}

public sealed class SettingsPage : IPage
{
    private readonly AppState _s;
    private readonly Localizer _l;

    public SettingsPage(AppState state, Localizer l)
    {
        _s = state;
        _l = l;
    }

    public double MinWidth => 560;

    public UIElement Build()
    {
        var st = _s.Settings;
        var external = new ComboBox { Header = _l.T("settings.externalDrives"), MinWidth = 260 };
        foreach (var key in new[] { "settings.external.ask", "settings.external.always", "settings.external.never" }) external.Items.Add(_l.T(key));
        external.SelectedIndex = (int)st.ExternalDrives;
        external.SelectionChanged += (_, _) => { st.ExternalDrives = (ExternalDriveBehavior)Math.Max(0, external.SelectedIndex); _s.SettingsChanged(); };

        var largeFiles = Number(_l.T("settings.largeFileMin") + " (MB)", st.LargeFileMinimumMB, 10, 10000, 50, v => st.LargeFileMinimumMB = (int)v);
        var critical = Number(_l.T("settings.criticalBytes") + " (GB)", st.CriticalFreeBytes / ByteFormatter.Gigabyte, 1, 200, 1, v => st.CriticalFreeBytes = (long)v * ByteFormatter.Gigabyte);
        var criticalRatio = Number(_l.T("settings.criticalRatio") + " (%)", Math.Round(st.CriticalFreeRatio * 100), 1, 50, 1, v => st.CriticalFreeRatio = v / 100);
        var warning = Number(_l.T("settings.warningBytes") + " (GB)", st.WarningFreeBytes / ByteFormatter.Gigabyte, 1, 500, 1, v => st.WarningFreeBytes = (long)v * ByteFormatter.Gigabyte);
        var warningRatio = Number(_l.T("settings.warningRatio") + " (%)", Math.Round(st.WarningFreeRatio * 100), 1, 60, 1, v => st.WarningFreeRatio = v / 100);

        var admin = Ui.Row(10, Ui.Text(_l.T("win.settings.admin"), 14), Ui.Badge(_s.IsElevated ? _l.T("fda.granted") : _l.T("fda.missing"), Theme.For(_s.IsElevated ? Severity.Ok : Severity.Warning)));
        if (!_s.IsElevated) admin.Children.Add(Ui.Button(_l.T("win.admin.restart"), _s.RestartAsAdministrator));

        var version = typeof(SettingsPage).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
        var page = Ui.Column(16,
            Ui.Title(_l.T("sidebar.settings")),
            Ui.Card(Ui.Column(12, Ui.Heading(_l.T("settings.general")), DialogService.LanguagePicker(_s, _l), external, largeFiles)),
            Ui.Card(Ui.Column(12, Ui.Heading(_l.T("settings.thresholds")), critical, criticalRatio, warning, warningRatio, Ui.Caption(_l.T("win.settings.thresholds.footer")))),
            Ui.Card(Ui.Column(12, Ui.Heading(_l.T("settings.permissions")), admin)),
            Ui.Card(Ui.Column(12, Ui.Heading(_l.T("settings.about")), Ui.Text($"{_l.T("settings.version")}: {version}", 14),
                Ui.Button(_l.T("settings.reset"), () => { st.ResetToDefaults(); _s.SettingsChanged(); }))));
        page.Margin = new Thickness(24);
        page.MaxWidth = 720;
        page.HorizontalAlignment = HorizontalAlignment.Left;
        return new ScrollViewer { Content = page };
    }

    private NumberBox Number(string header, double value, double min, double max, double step, Action<double> set)
    {
        var box = new NumberBox { Header = header, Value = value, Minimum = min, Maximum = max, SmallChange = step, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline, MinWidth = 260, HorizontalAlignment = HorizontalAlignment.Left };
        box.ValueChanged += (_, e) =>
        {
            if (double.IsNaN(e.NewValue)) return;
            set(Math.Clamp(e.NewValue, min, max));
            _s.Settings.Save();
            _s.RebuildFindings();
        };
        return box;
    }
}
