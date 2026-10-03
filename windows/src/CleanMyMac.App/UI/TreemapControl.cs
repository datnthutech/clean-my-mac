using CleanMyMac.Localization;
using DiskKit;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CleanMyMac.UI;

/// <summary>Squarified treemap of one folder. Double-click a folder tile to open it.</summary>
public sealed class TreemapControl : Grid
{
    public sealed record Item(string Id, string Name, long Bytes, bool IsDirectory, StorageCategory? Category);

    private const int MaximumTiles = 40;
    private readonly IReadOnlyList<Item> _items;
    private readonly Localizer _l;
    private readonly Canvas _canvas = new();

    public event Action<string>? Opened;

    public TreemapControl(IReadOnlyList<Item> items, Localizer l)
    {
        _items = items;
        _l = l;
        Background = Ui.Subtle;
        CornerRadius = new CornerRadius(8);
        MinHeight = 320;
        Children.Add(_canvas);
        SizeChanged += (_, e) => Layout(e.NewSize.Width, e.NewSize.Height);
    }

    private static readonly StorageCategory[] FolderPalette =
    {
        StorageCategory.Developer, StorageCategory.Applications, StorageCategory.Media, StorageCategory.Documents,
        StorageCategory.Music, StorageCategory.Docker, StorageCategory.Archives, StorageCategory.Caches,
    };

    private void Layout(double width, double height)
    {
        _canvas.Children.Clear();
        if (width <= 0 || height <= 0) return;
        var shown = _items.Take(MaximumTiles).ToList();
        var rest = _items.Skip(MaximumTiles).Sum(i => i.Bytes);
        var entries = shown.Select(i => (i.Id, (double)i.Bytes)).ToList();
        if (rest > 0) entries.Add(("__other__", rest));
        var lookup = shown.GroupBy(i => i.Id).ToDictionary(g => g.Key, g => g.First());

        foreach (var tile in Treemap.Squarify(entries, new LayoutRect(0, 0, width, height)))
        {
            lookup.TryGetValue(tile.Id, out var item);
            var index = shown.FindIndex(i => i.Id == tile.Id);
            var color = item is null ? Theme.For(StorageCategory.Other)
                : item.IsDirectory ? Theme.For(FolderPalette[Math.Max(0, index) % FolderPalette.Length])
                : Theme.For(item.Category ?? StorageCategory.Other);
            var name = item?.Name ?? _l.T("treemap.other");
            var bytes = item?.Bytes ?? rest;
            var border = new Border
            {
                Width = Math.Max(0, tile.Rect.Width),
                Height = Math.Max(0, tile.Rect.Height),
                Background = Ui.Brush(color),
                BorderBrush = Ui.Brush(Colors.White),
                BorderThickness = new Thickness(1),
            };
            if (tile.Rect.Width > 56 && tile.Rect.Height > 34)
            {
                border.Child = new StackPanel
                {
                    Margin = new Thickness(6),
                    Children =
                    {
                        new TextBlock { Text = name, FontSize = 11, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = Ui.Brush(Colors.White), TextTrimming = TextTrimming.CharacterEllipsis },
                        new TextBlock { Text = _l.Bytes(bytes), FontSize = 11, Foreground = Ui.Brush(Colors.White) },
                    },
                };
            }
            ToolTipService.SetToolTip(border, $"{name} — {_l.Bytes(bytes)}");
            if (item is not null) border.DoubleTapped += (_, _) => Opened?.Invoke(item.Id);
            Canvas.SetLeft(border, tile.Rect.X);
            Canvas.SetTop(border, tile.Rect.Y);
            _canvas.Children.Add(border);
        }
    }
}
