using System.Text;

namespace Whispergate.Setup;

internal sealed record SetupOptions(
    bool CheckOnly,
    bool ElevatedInstall,
    string? LogPath,
    string? PayloadDir)
{
    public static SetupOptions Parse(string[] args)
    {
        bool checkOnly = false;
        bool elevatedInstall = false;
        string? logPath = null;
        string? payloadDir = null;

        for (int index = 0; index < args.Length; index++)
        {
            string arg = args[index];
            if (arg.Equals("--check-only", StringComparison.OrdinalIgnoreCase))
            {
                checkOnly = true;
            }
            else if (arg.Equals("--elevated-install", StringComparison.OrdinalIgnoreCase))
            {
                elevatedInstall = true;
            }
            else if (arg.Equals("--log-path", StringComparison.OrdinalIgnoreCase))
            {
                logPath = RequireValue(args, ref index, arg);
            }
            else if (arg.Equals("--payload-dir", StringComparison.OrdinalIgnoreCase))
            {
                payloadDir = RequireValue(args, ref index, arg);
            }
            else
            {
                throw new ArgumentException($"Unknown setup argument: {arg}");
            }
        }

        return new SetupOptions(checkOnly, elevatedInstall, logPath, payloadDir);
    }

    private static string RequireValue(string[] args, ref int index, string name)
    {
        if (index + 1 >= args.Length)
        {
            throw new ArgumentException($"Missing value for {name}");
        }

        index++;
        return args[index];
    }
}

internal sealed record SetupCheck(string Name, bool Ok, string Action);

internal sealed record SetupInfo(
    string Host,
    string UserName,
    IReadOnlyList<string> Topics,
    string CredentialTarget)
{
    public string ServerUrl => string.IsNullOrWhiteSpace(Host) ? string.Empty : $"https://{Host}";
}

internal sealed record SetupSnapshot(
    string PayloadPath,
    IReadOnlyList<SetupCheck> Checks,
    SetupInfo Info)
{
    public string ToLogText()
    {
        StringBuilder builder = new();
        builder.AppendLine("Whispergate setup check");
        builder.AppendLine($"Payload: {PayloadPath}");
        foreach (SetupCheck check in Checks)
        {
            builder.AppendLine($"{check.Name}: {(check.Ok ? "ok" : "action")} - {check.Action}");
        }

        if (!string.IsNullOrWhiteSpace(Info.ServerUrl))
        {
            builder.AppendLine($"Server URL: {Info.ServerUrl}");
        }

        return builder.ToString().TrimEnd();
    }
}

internal sealed record InstallResult(bool Ok, int ExitCode, string LogPath);

internal sealed record ProcessResult(int ExitCode, string Output, string Error)
{
    public string ToLogText(string label)
    {
        StringBuilder builder = new();
        builder.AppendLine($"[{label}] exit={ExitCode}");
        if (!string.IsNullOrWhiteSpace(Output))
        {
            builder.AppendLine(Output.TrimEnd());
        }

        if (!string.IsNullOrWhiteSpace(Error))
        {
            builder.AppendLine(Error.TrimEnd());
        }

        return builder.ToString().TrimEnd();
    }
}
