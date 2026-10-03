using DiskKit;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace CleanMyMac.UI;

/// <summary>Colors shared by every page — the same palette as the macOS app.</summary>
public static class Theme
{
    public static Color Accent => Color.FromArgb(255, 10, 92, 212);

    public static Color For(Severity s) => s switch
    {
        Severity.Critical => Color.FromArgb(255, 196, 38, 28),
        Severity.Warning => Color.FromArgb(255, 194, 84, 0),
        Severity.Info => Accent,
        _ => Color.FromArgb(255, 31, 122, 59),
    };

    public static Color For(StorageCategory c) => c switch
    {
        StorageCategory.Applications => Color.FromArgb(255, 47, 95, 196),
        StorageCategory.Developer => Color.FromArgb(255, 107, 69, 194),
        StorageCategory.Media => Color.FromArgb(255, 184, 98, 15),
        StorageCategory.Music => Color.FromArgb(255, 204, 64, 115),
        StorageCategory.Documents => Color.FromArgb(255, 31, 127, 112),
        StorageCategory.Archives => Color.FromArgb(255, 140, 115, 26),
        StorageCategory.Caches => Color.FromArgb(255, 108, 113, 122),
        StorageCategory.IosBackups => Color.FromArgb(255, 51, 140, 191),
        StorageCategory.Mail => Color.FromArgb(255, 77, 153, 77),
        StorageCategory.Trash => Color.FromArgb(255, 140, 89, 77),
        StorageCategory.Docker => Color.FromArgb(255, 13, 140, 217),
        StorageCategory.System => Color.FromArgb(255, 92, 100, 115),
        _ => Color.FromArgb(255, 158, 163, 173),
    };

    public static Color Unscanned => Color.FromArgb(90, 128, 128, 128);

    public static string Glyph(StorageCategory c) => c switch
    {
        StorageCategory.Applications => "",
        StorageCategory.Documents => "",
        StorageCategory.Media => "",
        StorageCategory.Music => "",
        StorageCategory.Archives => "",
        StorageCategory.Developer => "",
        StorageCategory.Caches => "",
        StorageCategory.IosBackups => "",
        StorageCategory.Mail => "",
        StorageCategory.Trash => "",
        StorageCategory.Docker => "",
        StorageCategory.System => "",
        _ => "",
    };

    public static string Glyph(VolumeInfo v) => v.Kind switch
    {
        VolumeKind.External => v.IsRemovable ? "" : "",
        _ => "",
    };
}

/// <summary>Small factory helpers so pages read like the SwiftUI version.</summary>
public static class Ui
{
    public static SolidColorBrush Brush(Color c) => new(c);
    public static Brush ThemeBrush(string key) => (Brush)Application.Current.Resources[key];
    public static Brush Secondary => ThemeBrush("TextFillColorSecondaryBrush");
    public static Brush CardBackground => ThemeBrush("CardBackgroundFillColorDefaultBrush");
    public static Brush CardStroke => ThemeBrush("CardStrokeColorDefaultBrush");
    public static Brush Subtle => ThemeBrush("SubtleFillColorSecondaryBrush");

    public static TextBlock Text(string text, double size = 14, bool bold = false, Brush? color = null, bool wrap = true) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        Foreground = color ?? ThemeBrush("TextFillColorPrimaryBrush"),
        TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap,
        TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
        IsTextSelectionEnabled = false,
    };

    public static TextBlock Caption(string text, bool wrap = true) => Text(text, 12, color: Secondary, wrap: wrap);
    public static TextBlock Title(string text) => Text(text, 26, bold: true);
    public static TextBlock Heading(string text) => Text(text, 16, bold: true);

    public static FontIcon Icon(string glyph, double size = 16, Color? color = null)
    {
        var icon = new FontIcon { Glyph = glyph, FontSize = size };
        if (color is { } c) icon.Foreground = Brush(c);
        return icon;
    }

    public static StackPanel Row(double spacing = 8, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var c in children) panel.Children.Add(c);
        return panel;
    }

    public static StackPanel Column(double spacing = 8, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Vertical, Spacing = spacing };
        foreach (var c in children) panel.Children.Add(c);
        return panel;
    }

    /// <summary>A grid row: [left content (stretches)] [right content (auto)].</summary>
    public static Grid Split(UIElement left, UIElement right, double spacing = 12)
    {
        var g = new Grid { ColumnSpacing = spacing };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(left);
        Grid.SetColumn((FrameworkElement)right, 1);
        g.Children.Add(right);
        return g;
    }

    public static Border Card(UIElement content, double padding = 16) => new()
    {
        Child = content,
        Padding = new Thickness(padding),
        CornerRadius = new CornerRadius(8),
        Background = CardBackground,
        BorderBrush = CardStroke,
        BorderThickness = new Thickness(1),
    };

    public static Border Badge(string text, Color color) => new()
    {
        Child = new TextBlock { Text = text, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brush(color) },
        Background = Brush(Color.FromArgb(36, color.R, color.G, color.B)),
        CornerRadius = new CornerRadius(10),
        Padding = new Thickness(8, 2, 8, 3),
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static Microsoft.UI.Xaml.Shapes.Ellipse Dot(Color color, double size = 8) => new()
    {
        Width = size, Height = size, Fill = Brush(color), VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Horizontal usage bar made of colored segments (fractions of the full width).</summary>
    public static Grid CapacityBar(IEnumerable<(double Fraction, Color Color)> segments, double height = 10)
    {
        var grid = new Grid { Height = height, CornerRadius = new CornerRadius(height / 2), Background = Subtle };
        var used = 0.0;
        var col = 0;
        foreach (var (fraction, color) in segments)
        {
            var f = Math.Clamp(fraction, 0, 1 - used);
            if (f <= 0 || double.IsNaN(f)) continue;
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(f, GridUnitType.Star) });
            var rect = new Border { Background = Brush(color) };
            Grid.SetColumn(rect, col++);
            grid.Children.Add(rect);
            used += f;
        }
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.0001, 1 - used), GridUnitType.Star) });
        return grid;
    }

    public static Button Button(string text, Action onClick, bool accent = false, string? glyph = null)
    {
        object content = glyph is null ? text : Row(8, Icon(glyph, 14), new TextBlock { Text = text });
        var b = new Button { Content = content };
        if (accent) b.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        b.Click += (_, _) => onClick();
        return b;
    }

    public static UIElement EmptyState(string glyph, string title, string message, string? actionTitle = null, Action? action = null)
    {
        var col = Column(12, Icon(glyph, 44), Text(title, 20, true), Text(message, 14, color: Secondary));
        foreach (var child in col.Children.OfType<FrameworkElement>()) child.HorizontalAlignment = HorizontalAlignment.Center;
        foreach (var t in col.Children.OfType<TextBlock>()) { t.TextAlignment = TextAlignment.Center; t.MaxWidth = 460; }
        if (actionTitle is not null && action is not null)
        {
            var b = Button(actionTitle, action, accent: true);
            b.HorizontalAlignment = HorizontalAlignment.Center;
            col.Children.Add(b);
        }
        col.HorizontalAlignment = HorizontalAlignment.Center;
        col.VerticalAlignment = VerticalAlignment.Center;
        col.Margin = new Thickness(40);
        return col;
    }

    /// <summary>InfoBar-style notice for important caveats ("same name ≠ same content").</summary>
    public static InfoBar Notice(string text, InfoBarSeverity severity = InfoBarSeverity.Warning) => new()
    {
        Message = text,
        Severity = severity,
        IsOpen = true,
        IsClosable = false,
    };

    /// <summary>Summary text + buttons that never get clipped: the buttons wrap to a new line when the pane is narrow.</summary>
    public static UIElement ActionBar(string summary, params Button[] buttons)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        foreach (var b in buttons) panel.Children.Add(b);
        var grid = new Grid { Padding = new Thickness(10), Background = Subtle, ColumnSpacing = 8, RowSpacing = 6 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = Caption(summary, wrap: false);
        label.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(label);
        Grid.SetColumn(panel, 1);
        grid.Children.Add(panel);
        // Narrow pane: move the buttons under the summary instead of squeezing them.
        grid.SizeChanged += (_, e) =>
        {
            panel.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
            var narrow = e.NewSize.Width < panel.DesiredSize.Width + 160;
            Grid.SetRow(panel, narrow ? 1 : 0);
            Grid.SetColumn(panel, narrow ? 0 : 1);
            Grid.SetColumnSpan(panel, narrow ? 2 : 1);
            if (narrow && grid.RowDefinitions.Count < 2)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            }
        };
        return grid;
    }
}
