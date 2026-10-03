using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using DiskKit;

namespace CleanMyMac.Localization;

public enum AppLanguage { System, Vietnamese, English }

/// <summary>
/// Strings come from the macOS app's Localizable.strings (shared) with Windows overrides on top,
/// so both apps say the same thing. Switching language takes effect immediately.
/// </summary>
public sealed partial class Localizer
{
    private Dictionary<string, string> _current = new();
    private readonly Dictionary<string, string> _english;

    public Localizer(AppLanguage language)
    {
        _english = LoadTable("en");
        Apply(language);
    }

    public event Action? LanguageChanged;
    public string Code { get; private set; } = "en";
    public CultureInfo Culture { get; private set; } = CultureInfo.GetCultureInfo("en-US");

    public static string Resolve(AppLanguage language) => language switch
    {
        AppLanguage.Vietnamese => "vi",
        AppLanguage.English => "en",
        _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "vi" ? "vi" : "en",
    };

    public void Apply(AppLanguage language)
    {
        Code = Resolve(language);
        _current = Code == "en" ? _english : LoadTable(Code);
        Culture = CultureInfo.GetCultureInfo(Code == "vi" ? "vi-VN" : "en-US");
        LanguageChanged?.Invoke();
    }

    public string T(string key) =>
        _current.TryGetValue(key, out var v) ? v : _english.TryGetValue(key, out var e) ? e : key;

    /// <summary>Formats %@ placeholders in order (same syntax as the macOS strings files).</summary>
    public string T(string key, params string[] args)
    {
        var template = T(key);
        var index = 0;
        return PlaceholderRegex().Replace(template, _ => index < args.Length ? args[index++] : "");
    }

    public string Bytes(long value) => ByteFormatter.Format(value, Culture);
    public string Number(long value) => value.ToString("N0", Culture);
    public string Percent(double ratio) => ratio.ToString(ratio is > 0 and < 0.1 ? "P1" : "P0", Culture);
    public string Date(DateTime utc, bool time = true) => utc.ToLocalTime().ToString(time ? "g" : "d", Culture);
    public string Duration(TimeSpan span) => $"{(int)span.TotalMinutes:00}:{span.Seconds:00}";

    [GeneratedRegex("%@")]
    private static partial Regex PlaceholderRegex();

    private static Dictionary<string, string> LoadTable(string code)
    {
        var table = Parse(ReadResource($"Strings.{code}.base"));
        foreach (var (k, v) in Parse(ReadResource($"Strings.{code}.windows"))) table[k] = v;
        return table;
    }

    private static string ReadResource(string name)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        if (stream is null) return "";
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    [GeneratedRegex("^\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*;\\s*$", RegexOptions.Multiline)]
    private static partial Regex EntryRegex();

    internal static Dictionary<string, string> Parse(string text)
    {
        var table = new Dictionary<string, string>();
        foreach (Match m in EntryRegex().Matches(text))
            table[Unescape(m.Groups[1].Value)] = Unescape(m.Groups[2].Value);
        return table;
    }

    private static string Unescape(string s) =>
        s.Replace("\\n", "\n").Replace("\\\"", "\"").Replace("\\\\", "\\");
}
