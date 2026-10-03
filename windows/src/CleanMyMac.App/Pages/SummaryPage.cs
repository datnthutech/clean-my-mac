using CleanMyMac.Localization;
using CleanMyMac.State;
using CleanMyMac.UI;
using DiskKit;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CleanMyMac.Pages;

public sealed class SummaryPage : IPage
{
    private readonly AppState _s;
    private readonly Localizer _l;

    public SummaryPage(AppState state, Localizer l)
    {
        _s = state;
        _l = l;
    }

    public double MinWidth => 560;

    public UIElement Build()
    {
        var subtitle = _s.LastScanUtc is { } date
            ? _l.T("summary.subtitle", _l.Date(date), _s.Scans.Count.ToString(), _l.Number(_s.Scans.Values.Sum(x => x.Result.TotalFiles)))
            : _l.T("summary.subtitle.never", _s.Volumes.Count.ToString());
        var scan = Ui.Button(_l.T("action.scanAll"), _s.ScanAll, accent: true, glyph: "");
        scan.IsEnabled = !_s.IsScanning;

        var page = Ui.Column(20, Ui.Split(Ui.Column(4, Ui.Title(_l.T("summary.title")), Ui.Caption(subtitle)), scan));
        if (_s.Scans.Count == 0 && !_s.IsScanning) page.Children.Add(Ui.Notice(_l.T("summary.notScannedYet"), InfoBarSeverity.Informational));
        page.Children.Add(Findings());
        page.Children.Add(Ui.Heading(_l.T("summary.drives")));

        var drives = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 300, ItemHeight = 130 };
        foreach (var v in _s.Volumes) drives.Children.Add(VolumeCard(v));
        page.Children.Add(drives);

        var startup = _s.Volumes.FirstOrDefault(v => v.Kind == VolumeKind.System);
        if (startup is not null && _s.Scans.TryGetValue(startup.Id, out var scanResult))
            page.Children.Add(CategoryCard(scanResult));

        page.Margin = new Thickness(28);
        return page;
    }

    private UIElement Findings()
    {
        var counts = SummaryBuilder.Counts(_s.Findings);
        var badges = Ui.Row(6);
        foreach (var sev in new[] { Severity.Critical, Severity.Warning, Severity.Info })
            if (counts.TryGetValue(sev, out var c) && c > 0)
                badges.Children.Add(Ui.Badge($"{c} {_l.T("severity." + Key(sev))}", Theme.For(sev)));

        var body = Ui.Column(0, Ui.Split(Ui.Heading(_l.T("summary.attention")), badges));
        if (_s.Findings.Count == 0)
        {
            var text = _s.Scans.Count == 0 ? _l.T("summary.noFindings.unscanned") : _l.T("summary.noFindings");
            var row = Ui.Row(10, Ui.Icon("", 16, Theme.For(Severity.Ok)), Ui.Text(text, 14, color: Ui.Secondary));
            row.Margin = new Thickness(0, 12, 0, 0);
            body.Children.Add(row);
        }
        foreach (var f in _s.Findings)
        {
            var (title, detail) = FindingText.For(f, _l);
            var show = Ui.Button(_l.T("action.show"), () => _s.Navigate(f.Target));
            show.VerticalAlignment = VerticalAlignment.Center;
            var left = Ui.Row(14, Ui.Dot(Theme.For(f.Severity), 10), Ui.Column(2, Ui.Text(title, 14, true), Ui.Caption(detail)));
            var row = Ui.Split(left, show);
            row.Padding = new Thickness(0, 10, 0, 10);
            row.BorderBrush = Ui.CardStroke;
            row.BorderThickness = new Thickness(0, 1, 0, 0);
            body.Children.Add(row);
        }
        return Ui.Card(body);
    }

    private UIElement VolumeCard(VolumeInfo v)
    {
        var severity = _s.SeverityOf(v);
        var badge = _s.Scans.ContainsKey(v.Id) || severity != Severity.Ok
            ? Ui.Badge(_l.T("severity." + Key(severity)), Theme.For(severity))
            : Ui.Badge(_l.T("volume.notScanned"), Theme.For(Severity.Ok));
        var card = Ui.Card(Ui.Column(10,
            Ui.Split(Ui.Row(8, Ui.Icon(Theme.Glyph(v)), Ui.Text(v.Name, 15, true, wrap: false)), badge),
            Ui.CapacityBar(new[] { (v.UsedRatio, Theme.For(severity)) }, 8),
            Ui.Caption(_l.T("volume.detailLine", _l.Bytes(v.UsedBytes), _l.Bytes(v.TotalBytes), _l.Bytes(v.AvailableBytes), v.Format, _l.T("volume.kind." + KindKey(v.Kind))))));
        card.Margin = new Thickness(0, 0, 12, 12);
        var button = new Button { Content = card, Padding = new Thickness(0), Background = null, BorderThickness = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch };
        button.Click += (_, _) => _s.Select(new NavItem.Volume(v.Id));
        return button;
    }

    private UIElement CategoryCard(VolumeScan scan)
    {
        var totals = scan.Categories.Sorted;
        var used = Math.Max(scan.Volume.UsedBytes, scan.Categories.CategorizedBytes);
        var legend = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 200 };
        foreach (var (c, b) in totals.Take(8))
            legend.Children.Add(Ui.Row(6, new Border { Width = 10, Height = 10, CornerRadius = new CornerRadius(2), Background = Ui.Brush(Theme.For(c)), VerticalAlignment = VerticalAlignment.Center },
                                        Ui.Caption($"{_l.T("category." + CategoryKey(c))} {_l.Bytes(b)}", wrap: false)));
        return Ui.Card(Ui.Column(12,
            Ui.Heading(_l.T("summary.usedFor", scan.Volume.Name)),
            Ui.CapacityBar(totals.Select(t => (used > 0 ? (double)t.Bytes / used : 0, Theme.For(t.Category))), 20),
            legend));
    }

    internal static string Key(Severity s) => s switch
    {
        Severity.Critical => "critical",
        Severity.Warning => "warning",
        Severity.Info => "info",
        _ => "ok",
    };

    internal static string KindKey(VolumeKind k) => k switch
    {
        VolumeKind.System => "system",
        VolumeKind.Internal => "internalDrive",
        _ => "external",
    };

    internal static string CategoryKey(StorageCategory c) => c switch
    {
        StorageCategory.IosBackups => "iosBackups",
        _ => char.ToLowerInvariant(c.ToString()[0]) + c.ToString()[1..],
    };

    internal static string HotspotKey(HotspotKind k) => "win." + char.ToLowerInvariant(k.ToString()[0]) + k.ToString()[1..];
}

/// <summary>Turns a finding into localized title + explanation (same wording as the macOS app where possible).</summary>
public static class FindingText
{
    public static (string Title, string Detail) For(Finding f, Localizer l) => f.Kind switch
    {
        FindingKind.LowDiskSpace s => (l.T("finding.lowSpace.title", s.VolumeName, l.Bytes(s.FreeBytes), l.Percent(s.FreeRatio)),
            l.T(s.IsSystemDrive ? (f.Severity == Severity.Critical ? "win.finding.lowSpace.critical" : "win.finding.lowSpace.warning") : "finding.lowSpace.external")),
        FindingKind.DockerDangling d => (l.T("finding.docker.title", d.Count.ToString(), l.Bytes(d.Bytes)), l.T("finding.docker.detail")),
        FindingKind.DockerBuildCache c => (l.T("finding.dockerCache.title", l.Bytes(c.Bytes)), l.T("finding.dockerCache.detail")),
        FindingKind.HotspotFound h => (l.T("finding.hotspot.title", l.T("hotspot." + SummaryPage.HotspotKey(h.Kind)), l.Bytes(h.Bytes)), l.T("hotspot." + SummaryPage.HotspotKey(h.Kind) + ".detail")),
        FindingKind.Duplicates d => (l.T("finding.duplicates.title", d.Groups.ToString(), l.Bytes(d.Reclaimable)), l.T("finding.duplicates.detail")),
        FindingKind.UnreadableFolders u => (l.T("win.finding.unreadable.title", u.VolumeName, l.Number(u.Count)), l.T("win.finding.unreadable.detail")),
        _ => ("", ""),
    };
}
