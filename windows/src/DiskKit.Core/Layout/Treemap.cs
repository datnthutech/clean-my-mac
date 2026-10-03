namespace DiskKit;

public readonly record struct LayoutRect(double X, double Y, double Width, double Height)
{
    public double Area => Width * Height;
}

public readonly record struct TreemapTile<TId>(TId Id, LayoutRect Rect);

/// <summary>Squarified treemap (Bruls, Huizing, van Wijk): tiles stay close to square so labels fit.</summary>
public static class Treemap
{
    public static IReadOnlyList<TreemapTile<TId>> Squarify<TId>(IEnumerable<(TId Id, double Value)> items, LayoutRect bounds)
    {
        var positive = items.Where(i => i.Value > 0).OrderByDescending(i => i.Value).ToList();
        var total = positive.Sum(i => i.Value);
        var tiles = new List<TreemapTile<TId>>(positive.Count);
        if (total <= 0 || bounds.Width <= 0 || bounds.Height <= 0) return tiles;

        var scale = bounds.Area / total;
        var areas = positive.Select(i => i.Value * scale).ToArray();
        var remaining = bounds;
        var index = 0;
        while (index < areas.Length)
        {
            var side = Math.Min(remaining.Width, remaining.Height);
            var end = index + 1;
            double sum = areas[index], min = areas[index], max = areas[index];
            var current = Worst(sum, min, max, side);
            while (end < areas.Length)
            {
                var a = areas[end];
                var next = Worst(sum + a, Math.Min(min, a), Math.Max(max, a), side);
                if (next > current) break;
                sum += a; min = Math.Min(min, a); max = Math.Max(max, a); current = next;
                end++;
            }
            if (remaining.Width >= remaining.Height)
            {
                var w = remaining.Height > 0 ? sum / remaining.Height : 0;
                var y = remaining.Y;
                for (var i = index; i < end; i++)
                {
                    var h = w > 0 ? areas[i] / w : 0;
                    tiles.Add(new TreemapTile<TId>(positive[i].Id, new LayoutRect(remaining.X, y, w, h)));
                    y += h;
                }
                remaining = remaining with { X = remaining.X + w, Width = Math.Max(0, remaining.Width - w) };
            }
            else
            {
                var h = remaining.Width > 0 ? sum / remaining.Width : 0;
                var x = remaining.X;
                for (var i = index; i < end; i++)
                {
                    var w = h > 0 ? areas[i] / h : 0;
                    tiles.Add(new TreemapTile<TId>(positive[i].Id, new LayoutRect(x, remaining.Y, w, h)));
                    x += w;
                }
                remaining = remaining with { Y = remaining.Y + h, Height = Math.Max(0, remaining.Height - h) };
            }
            index = end;
        }
        return tiles;
    }

    private static double Worst(double sum, double min, double max, double side)
    {
        if (sum <= 0 || min <= 0 || side <= 0) return double.PositiveInfinity;
        var s2 = side * side;
        var sum2 = sum * sum;
        return Math.Max(s2 * max / sum2, sum2 / (s2 * min));
    }
}
