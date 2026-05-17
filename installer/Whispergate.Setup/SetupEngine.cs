using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace Whispergate.Setup;

internal sealed class SetupEngine
{
    private const string ResourceName = "Whispergate.Setup.Payload.payload.zip";
    private const string LocalAppFolderName = "Whispergate";
    private const string EmbeddedPayloadFolderName = "embedded-current";
    private const string BeginnerSetupPath = "scripts\\setup-windows-beginner.ps1";
    private const string DoctorPath = "scripts\\doctor.ps1";
    private const string VerifyPath = "scripts\\verify.ps1";
    private const string ConfigPath = "config.json";
    private const int ProcessTimeoutMilliseconds = 60000;
    private readonly SetupOptions options;

    public SetupEngine(SetupOptions options)
    {
        this.options = options;
        string logPath = options.LogPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            LocalAppFolderName,
            "setup",
            "setup.log");
        LogPath = Path.GetFullPath(logPath);
    }

    public string LogPath { get; }

    public async Task<int> RunCheckOnlyAsync()
    {
        SetupSnapshot snapshot = await CheckAsync(CancellationToken.None);
        await AppendLogAsync(snapshot.ToLogText(), CancellationToken.None);
        return 0;
    }

    public async Task<SetupSnapshot> CheckAsync(CancellationToken cancellationToken)
    {
        string payloadPath = await EnsurePayloadAsync(cancellationToken);
        List<SetupCheck> checks = [];
        checks.Add(Check("windows", OperatingSystem.IsWindows(), "Windows is required."));
        checks.Add(Check("admin", IsAdministrator(), "Admin rights are needed for install only."));

        string? tailscaleExe = FindTailscaleExe();
        checks.Add(Check("tailscale", tailscaleExe is not null, "Install Tailscale and sign in."));
        string hostName = string.Empty;
        if (tailscaleExe is not null)
        {
            ProcessResult status = await RunProcessAsync(
                tailscaleExe,
                "status --self --json",
                payloadPath,
                cancellationToken);
            bool signedIn = status.ExitCode == 0 && TryGetTailscaleHost(status.Output, out hostName);
            checks.Add(Check("tailscale_sign_in", signedIn, "Sign in to Tailscale on this PC."));
        }

        SetupInfo info = ReadSetupInfo(payloadPath, hostName);
        return new SetupSnapshot(payloadPath, checks, info);
    }

    public async Task<int> RunElevatedInstallAsync()
    {
        try
        {
            string payloadPath = await EnsurePayloadAsync(CancellationToken.None);
            await AppendLogAsync($"Payload: {payloadPath}", CancellationToken.None);
            await RunPowerShellStepAsync(payloadPath, BeginnerSetupPath, string.Empty, CancellationToken.None);
            await RunPowerShellStepAsync(payloadPath, DoctorPath, string.Empty, CancellationToken.None);
            await RunPowerShellStepAsync(payloadPath, VerifyPath, string.Empty, CancellationToken.None);
            await AppendLogAsync("Install flow finished.", CancellationToken.None);
            return 0;
        }
        catch (Exception ex)
        {
            await AppendLogAsync("Install flow failed: " + ex.Message, CancellationToken.None);
            return 1;
        }
    }

    public async Task<InstallResult> StartInstallAsync(CancellationToken cancellationToken)
    {
        string payloadPath = await EnsurePayloadAsync(cancellationToken);
        if (!IsAdministrator())
        {
            return await StartElevatedSelfAsync(payloadPath, cancellationToken);
        }

        int exitCode = await RunElevatedInstallAsync();
        return new InstallResult(exitCode == 0, exitCode, LogPath);
    }

    public async Task<string> EnsurePayloadAsync(CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(options.PayloadDir))
        {
            string overridePath = Path.GetFullPath(options.PayloadDir);
            ValidatePayload(overridePath);
            return overridePath;
        }

        string basePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            LocalAppFolderName,
            "app");
        string destination = Path.Combine(basePath, EmbeddedPayloadFolderName);
        ResetEmbeddedPayload(destination, basePath);

        Assembly assembly = typeof(SetupEngine).Assembly;
        await using Stream? stream = assembly.GetManifestResourceStream(ResourceName);
        if (stream is null)
        {
            throw new InvalidOperationException("Embedded Whispergate payload is missing.");
        }

        Directory.CreateDirectory(destination);
        ZipFile.ExtractToDirectory(stream, destination, overwriteFiles: true);
        ValidatePayload(destination);
        return destination;
    }

    public SetupInfo ReadSetupInfo(string payloadPath, string detectedHost)
    {
        string configPath = Path.Combine(payloadPath, ConfigPath);
        if (!File.Exists(configPath))
        {
            configPath = Path.Combine(payloadPath, "config.example.json");
        }

        if (!File.Exists(configPath))
        {
            return new SetupInfo(detectedHost, string.Empty, [], string.Empty);
        }

        using FileStream stream = File.OpenRead(configPath);
        using JsonDocument document = JsonDocument.Parse(stream);
        JsonElement root = document.RootElement;
        string host = GetString(root, "host");
        string userName = GetString(root, "defaultUser");
        string deploymentName = GetString(root, "deploymentName");
        List<string> topics = [];
        if (root.TryGetProperty("instances", out JsonElement instances))
        {
            foreach (JsonElement instance in instances.EnumerateArray())
            {
                string topic = GetString(instance, "topic");
                if (!string.IsNullOrWhiteSpace(topic))
                {
                    topics.Add(topic);
                }
            }
        }

        bool exampleHost = host.Contains(
            "your-device",
            StringComparison.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(detectedHost) && exampleHost)
        {
            host = detectedHost;
        }

        string credentialTarget = string.Empty;
        if (!string.IsNullOrWhiteSpace(deploymentName) && !string.IsNullOrWhiteSpace(userName))
        {
            credentialTarget = $"Whispergate/ntfy/{deploymentName}/{userName}";
        }

        return new SetupInfo(host, userName, topics, credentialTarget);
    }

    public async Task AppendLogAsync(string text, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
        await File.AppendAllTextAsync(LogPath, text + Environment.NewLine, Encoding.UTF8, cancellationToken);
    }

    private static SetupCheck Check(string name, bool ok, string action)
    {
        return new SetupCheck(name, ok, action);
    }

    private static void ResetEmbeddedPayload(string destination, string basePath)
    {
        string fullDestination = Path.GetFullPath(destination);
        string fullBase = Path.GetFullPath(basePath) + Path.DirectorySeparatorChar;
        if (!fullDestination.StartsWith(fullBase, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Refusing to clear a path outside the Whispergate app folder.");
        }

        if (Directory.Exists(fullDestination))
        {
            Directory.Delete(fullDestination, recursive: true);
        }
    }

    private static void ValidatePayload(string path)
    {
        string setupPath = Path.Combine(path, BeginnerSetupPath);
        if (!File.Exists(setupPath))
        {
            throw new InvalidOperationException("Payload is missing scripts/setup-windows-beginner.ps1.");
        }
    }

    private static bool IsAdministrator()
    {
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static string? FindTailscaleExe()
    {
        List<string> candidates = [];
        string? pathValue = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(pathValue))
        {
            IEnumerable<string> pathCandidates = pathValue
                .Split(Path.PathSeparator)
                .Select(path => Path.Combine(path, "tailscale.exe"));
            candidates.AddRange(pathCandidates);
        }

        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        candidates.Add(Path.Combine(programFiles, "Tailscale", "tailscale.exe"));
        return candidates.FirstOrDefault(File.Exists);
    }

    private static bool TryGetTailscaleHost(string json, out string hostName)
    {
        hostName = string.Empty;
        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            string backendState = GetString(root, "BackendState");
            bool online = root.TryGetProperty("Self", out JsonElement self) && GetBool(self, "Online");
            string dnsName = root.TryGetProperty("Self", out self) ? GetString(self, "DNSName") : string.Empty;
            hostName = dnsName.TrimEnd('.');
            return backendState.Equals("Running", StringComparison.OrdinalIgnoreCase)
                && online
                && hostName.EndsWith(".ts.net", StringComparison.OrdinalIgnoreCase);
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private async Task RunPowerShellStepAsync(
        string payloadPath,
        string relativeScriptPath,
        string arguments,
        CancellationToken cancellationToken)
    {
        string scriptPath = Path.Combine(payloadPath, relativeScriptPath);
        string commandArguments = $"-NoProfile -ExecutionPolicy Bypass -File {Quote(scriptPath)} {arguments}".TrimEnd();
        ProcessResult result = await RunProcessAsync(
            "powershell.exe",
            commandArguments,
            payloadPath,
            cancellationToken);
        await AppendLogAsync(result.ToLogText(relativeScriptPath), cancellationToken);
        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException($"PowerShell step failed: {relativeScriptPath}");
        }
    }

    private async Task<InstallResult> StartElevatedSelfAsync(string payloadPath, CancellationToken cancellationToken)
    {
        string exePath = Environment.ProcessPath ?? Application.ExecutablePath;
        string arguments = string.Join(" ", new[]
        {
            "--elevated-install",
            "--payload-dir", Quote(payloadPath),
            "--log-path", Quote(LogPath)
        });
        ProcessStartInfo startInfo = new()
        {
            FileName = exePath,
            Arguments = arguments,
            UseShellExecute = true,
            Verb = "runas"
        };
        using Process process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to start elevated setup.");
        await process.WaitForExitAsync(cancellationToken);
        return new InstallResult(process.ExitCode == 0, process.ExitCode, LogPath);
    }

    private static async Task<ProcessResult> RunProcessAsync(
        string fileName,
        string arguments,
        string workingDirectory,
        CancellationToken cancellationToken)
    {
        ProcessStartInfo startInfo = new()
        {
            FileName = fileName,
            Arguments = arguments,
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        using Process process = new() { StartInfo = startInfo };
        process.Start();
        Task<string> stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        Task waitTask = process.WaitForExitAsync(cancellationToken);
        Task completedTask = await Task.WhenAny(waitTask, Task.Delay(ProcessTimeoutMilliseconds, cancellationToken));
        if (completedTask != waitTask)
        {
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            throw new TimeoutException($"Process timed out: {fileName}");
        }

        return new ProcessResult(process.ExitCode, await stdoutTask, await stderrTask);
    }

    private static string Quote(string value)
    {
        return '"' + value.Replace("\"", "\\\"") + '"';
    }

    private static string GetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out JsonElement value)
            && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? string.Empty
            : string.Empty;
    }

    private static bool GetBool(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out JsonElement value)
            && value.ValueKind == JsonValueKind.True;
    }
}
