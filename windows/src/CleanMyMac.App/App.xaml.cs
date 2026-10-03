using CleanMyMac.State;
using Microsoft.UI.Xaml;

namespace CleanMyMac;

public partial class App : Application
{
    private MainWindow? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            // Never let one failing page take the whole app down; the menu stays usable.
            e.Handled = true;
            _window?.ShowError(e.Exception?.Message ?? e.Message);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var options = LaunchOptions.Parse(Environment.GetCommandLineArgs());
        var settings = AppSettings.Load();
        _window = new MainWindow(settings, options);
        _window.Activate();
    }
}

/// <summary>Command-line switches used by the CI smoke test: --open-page &lt;name&gt; and --scan-on-launch.</summary>
public sealed record LaunchOptions(string? OpenPage, bool ScanOnLaunch, bool SkipOnboarding)
{
    public static LaunchOptions Parse(string[] args)
    {
        string? page = null;
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == "--open-page") page = args[i + 1];
        return new LaunchOptions(page, args.Contains("--scan-on-launch"), args.Contains("--skip-onboarding"));
    }
}
