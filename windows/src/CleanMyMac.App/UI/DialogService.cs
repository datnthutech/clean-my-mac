using CleanMyMac.Localization;
using CleanMyMac.State;
using DiskKit;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CleanMyMac.UI;

/// <summary>All confirmation dialogs. Only one ContentDialog can be open at a time, so calls are serialized.</summary>
public sealed class DialogService
{
    private readonly Window _window;
    private readonly AppState _state;
    private readonly Localizer _l;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public DialogService(Window window, AppState state, Localizer l)
    {
        _window = window;
        _state = state;
        _l = l;
    }

    private async Task<ContentDialogResult> ShowAsync(ContentDialog dialog)
    {
        await _gate.WaitAsync();
        try
        {
            dialog.XamlRoot = _window.Content.XamlRoot;
            dialog.RequestedTheme = ((FrameworkElement)_window.Content).ActualTheme;
            return await dialog.ShowAsync();
        }
        catch
        {
            return ContentDialogResult.None;
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>"N external drives detected — scan them too?" Only shown when external drives are connected.</summary>
    public async Task ExternalDrivesAsync(IReadOnlyList<VolumeInfo> internalList, IReadOnlyList<VolumeInfo> externalList)
    {
        var boxes = externalList.Select(v => new CheckBox
        {
            IsChecked = true,
            Tag = v,
            Content = Ui.Column(2, Ui.Text(v.Name, 14, true), Ui.Caption(_l.T("external.volumeDetail", _l.Bytes(v.TotalBytes), v.Format, _l.Bytes(v.UsedBytes)))),
        }).ToList();
        var remember = new CheckBox { Content = _l.T("external.remember") };
        var body = Ui.Column(10, Ui.Text(_l.T("external.message"), 14, color: Ui.Secondary));
        boxes.ForEach(b => body.Children.Add(b));
        body.Children.Add(remember);

        var dialog = new ContentDialog
        {
            Title = _l.T("external.title", externalList.Count.ToString()),
            Content = body,
            PrimaryButtonText = _l.T("external.scanSelected", externalList.Count.ToString()),
            CloseButtonText = _l.T("external.internalOnly"),
            DefaultButton = ContentDialogButton.Primary,
        };
        foreach (var b in boxes)
        {
            void Update(object? s, RoutedEventArgs e)
            {
                var count = boxes.Count(x => x.IsChecked == true);
                dialog.PrimaryButtonText = _l.T("external.scanSelected", count.ToString());
                dialog.IsPrimaryButtonEnabled = count > 0;
            }
            b.Checked += Update;
            b.Unchecked += Update;
        }
        var result = await ShowAsync(dialog);
        var chosen = result == ContentDialogResult.Primary
            ? boxes.Where(b => b.IsChecked == true).Select(b => (VolumeInfo)b.Tag).ToList()
            : new List<VolumeInfo>();
        _state.ResolveExternalPrompt(internalList, chosen, remember.IsChecked == true);
    }

    public async Task MountedAsync(VolumeInfo volume)
    {
        var dialog = new ContentDialog
        {
            Title = _l.T("mount.title"),
            Content = Ui.Text(_l.T("mount.message", volume.Name, _l.Bytes(volume.TotalBytes))),
            PrimaryButtonText = _l.T("mount.scanNow"),
            CloseButtonText = _l.T("action.later"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await ShowAsync(dialog) == ContentDialogResult.Primary) _state.Scan(volume);
    }

    /// <summary>Confirms moving items to the Recycle Bin; protected items are listed and skipped.</summary>
    public async Task ConfirmTrashAsync(IReadOnlyList<TrashItem> items)
    {
        if (items.Count == 0) return;
        var (allowed, blocked) = _state.Classify(items);
        var total = allowed.Sum(i => i.Bytes);
        var list = Ui.Column(4);
        foreach (var item in allowed.Take(8))
            list.Children.Add(Ui.Split(Ui.Text(item.Path, 13, wrap: false), Ui.Text(_l.Bytes(item.Bytes), 13)));
        if (allowed.Count > 8) list.Children.Add(Ui.Caption(_l.T("trash.andMore", (allowed.Count - 8).ToString())));
        var body = Ui.Column(12, Ui.Text(_l.T("trash.confirmMessage"), 14, color: Ui.Secondary), list);
        if (blocked.Count > 0) body.Children.Add(Ui.Notice(_l.T("trash.blocked", blocked.Count.ToString())));
        var permanent = _state.HasItemsWithoutRecycleBin(allowed);
        if (permanent) body.Children.Add(Ui.Notice(_l.T("trash.noRecycleBin"), InfoBarSeverity.Error));

        var dialog = new ContentDialog
        {
            Title = _l.T("trash.confirmTitle", allowed.Count.ToString(), _l.Bytes(total)),
            Content = new ScrollViewer { Content = body, MaxHeight = 420 },
            PrimaryButtonText = permanent ? _l.T("trash.deletePermanently") : _l.T("action.moveToTrash"),
            CloseButtonText = _l.T("action.cancel"),
            DefaultButton = ContentDialogButton.Close,
            IsPrimaryButtonEnabled = allowed.Count > 0,
        };
        if (await ShowAsync(dialog) == ContentDialogResult.Primary) _state.MoveToRecycleBin(allowed);
    }

    public async Task ConfirmDockerRemovalAsync(IReadOnlyList<DockerImage> images)
    {
        if (images.Count == 0) return;
        var dialog = new ContentDialog
        {
            Title = _l.T("docker.confirmTitle", images.Count.ToString(), _l.Bytes(images.Sum(i => i.SizeBytes))),
            Content = Ui.Text(_l.T("docker.confirmMessage")),
            PrimaryButtonText = _l.T("docker.removeButton", images.Count.ToString()),
            CloseButtonText = _l.T("action.cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await ShowAsync(dialog) == ContentDialogResult.Primary) _state.RemoveDockerImages(images);
    }

    /// <summary>First launch: features, language and administrator rights.</summary>
    public async Task OnboardingAsync()
    {
        var language = LanguagePicker(_state, _l);
        var features = Ui.Column(10);
        foreach (var (glyph, key) in new[] { ("", "onboarding.feature1"), ("", "onboarding.feature2"), ("", "onboarding.feature3"), ("", "onboarding.feature4") })
            features.Children.Add(Ui.Row(12, Ui.Icon(glyph, 18, Theme.Accent), Ui.Text(_l.T(key), 14)));
        var admin = Ui.Card(Ui.Column(8,
            Ui.Text(_l.T("onboarding.fdaTitle"), 15, true),
            Ui.Text(_l.T("onboarding.fdaBody"), 13, color: Ui.Secondary),
            Ui.Row(8, Ui.Badge(_state.IsElevated ? _l.T("fda.granted") : _l.T("fda.missing"), Theme.For(_state.IsElevated ? Severity.Ok : Severity.Warning)))));
        var dialog = new ContentDialog
        {
            Title = _l.T("onboarding.title"),
            Content = new ScrollViewer { Content = Ui.Column(16, Ui.Text(_l.T("onboarding.subtitle"), 14, color: Ui.Secondary), features, admin, language), MaxHeight = 520 },
            PrimaryButtonText = _l.T("onboarding.continue"),
            SecondaryButtonText = _state.IsElevated ? null : _l.T("onboarding.openSettings"),
            DefaultButton = ContentDialogButton.Primary,
        };
        var result = await ShowAsync(dialog);
        _state.Settings.HasCompletedOnboarding = true;
        _state.SettingsChanged();
        if (result == ContentDialogResult.Secondary) _state.RestartAsAdministrator();
    }

    public static ComboBox LanguagePicker(AppState state, Localizer l)
    {
        var box = new ComboBox { Header = l.T("settings.language"), MinWidth = 220 };
        foreach (var lang in Enum.GetValues<AppLanguage>())
            box.Items.Add(new ComboBoxItem { Content = l.T(lang switch { AppLanguage.Vietnamese => "language.vi", AppLanguage.English => "language.en", _ => "language.system" }), Tag = lang });
        box.SelectedIndex = (int)state.Settings.Language;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedItem is ComboBoxItem { Tag: AppLanguage lang } && lang != state.Settings.Language)
            {
                state.Settings.Language = lang;
                state.Settings.Save();
                l.Apply(lang);
            }
        };
        return box;
    }
}
