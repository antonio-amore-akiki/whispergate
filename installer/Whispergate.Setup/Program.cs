namespace Whispergate.Setup;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        SetupOptions options = SetupOptions.Parse(args);
        SetupEngine engine = new(options);

        if (options.CheckOnly)
        {
            return engine.RunCheckOnlyAsync().GetAwaiter().GetResult();
        }

        if (options.ElevatedInstall)
        {
            return engine.RunElevatedInstallAsync().GetAwaiter().GetResult();
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(engine));
        return 0;
    }
}
