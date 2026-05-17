using System.Diagnostics;
using System.Text;

namespace Whispergate.Setup;

internal sealed class MainForm : Form
{
    private readonly SetupEngine engine;
    private readonly TextBox outputBox = new();
    private readonly Button checkButton = new();
    private readonly Button installButton = new();
    private readonly Button logButton = new();
    private readonly Button closeButton = new();
    private readonly Label titleLabel = new();
    private readonly Label stepLabel = new();

    public MainForm(SetupEngine engine)
    {
        this.engine = engine;
        Text = "Whispergate Setup";
        MinimumSize = new Size(760, 560);
        StartPosition = FormStartPosition.CenterScreen;
        ConfigureLayout();
    }

    protected override async void OnShown(EventArgs e)
    {
        base.OnShown(e);
        await RunCheckAsync();
    }

    private void ConfigureLayout()
    {
        titleLabel.Text = "Whispergate Windows Setup";
        titleLabel.Font = new Font(Font, FontStyle.Bold);
        titleLabel.AutoSize = true;
        titleLabel.Location = new Point(24, 20);

        stepLabel.Text = "Welcome -> Tailscale -> Install -> Verify -> Phone Setup -> Done";
        stepLabel.AutoSize = true;
        stepLabel.Location = new Point(24, 50);

        outputBox.Multiline = true;
        outputBox.ReadOnly = true;
        outputBox.ScrollBars = ScrollBars.Vertical;
        outputBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        outputBox.Location = new Point(24, 82);
        outputBox.Size = new Size(700, 360);
        outputBox.Font = new Font(FontFamily.GenericMonospace, 10);

        checkButton.Text = "Check";
        checkButton.Location = new Point(24, 462);
        checkButton.Size = new Size(120, 34);
        checkButton.Click += async (_, _) => await RunCheckAsync();

        installButton.Text = "Install / repair";
        installButton.Location = new Point(154, 462);
        installButton.Size = new Size(140, 34);
        installButton.Click += async (_, _) => await RunInstallAsync();

        logButton.Text = "Open log folder";
        logButton.Location = new Point(304, 462);
        logButton.Size = new Size(140, 34);
        logButton.Click += (_, _) => OpenLogFolder();

        closeButton.Text = "Close";
        closeButton.Location = new Point(604, 462);
        closeButton.Size = new Size(120, 34);
        closeButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
        closeButton.Click += (_, _) => Close();

        Controls.AddRange([
            titleLabel,
            stepLabel,
            outputBox,
            checkButton,
            installButton,
            logButton,
            closeButton
        ]);
    }

    private async Task RunCheckAsync()
    {
        await RunUiTaskAsync(async () =>
        {
            WriteOutput("Checking Windows, Tailscale, payload, and config...");
            SetupSnapshot snapshot = await engine.CheckAsync(CancellationToken.None);
            WriteOutput(RenderSnapshot(snapshot));
        });
    }

    private async Task RunInstallAsync()
    {
        await RunUiTaskAsync(async () =>
        {
            WriteOutput("Starting setup. Approve the Windows UAC prompt when it appears.");
            InstallResult result = await engine.StartInstallAsync(CancellationToken.None);
            StringBuilder builder = new();
            builder.AppendLine(result.Ok ? "Install and verify finished." : "Install or verify failed.");
            builder.AppendLine($"Exit code: {result.ExitCode}");
            builder.AppendLine($"Log: {result.LogPath}");
            builder.AppendLine();
            builder.AppendLine("Next phone step:");
            builder.AppendLine("1. Open ntfy on the phone while Tailscale is connected.");
            builder.AppendLine("2. Use the server URL, username, and topics shown by Check.");
            builder.AppendLine("3. Get the password from Windows Credential Manager.");
            WriteOutput(builder.ToString());
        });
    }

    private async Task RunUiTaskAsync(Func<Task> action)
    {
        SetBusy(true);
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            WriteOutput("Setup error: " + ex.Message);
            await engine.AppendLogAsync("UI error: " + ex, CancellationToken.None);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool busy)
    {
        checkButton.Enabled = !busy;
        installButton.Enabled = !busy;
        Cursor = busy ? Cursors.WaitCursor : Cursors.Default;
    }

    private void WriteOutput(string text)
    {
        outputBox.Text = text.Replace("\n", Environment.NewLine);
        outputBox.SelectionStart = outputBox.TextLength;
        outputBox.ScrollToCaret();
    }

    private static string RenderSnapshot(SetupSnapshot snapshot)
    {
        StringBuilder builder = new();
        builder.AppendLine("Welcome");
        builder.AppendLine("This wizard installs Whispergate for a private Tailscale tailnet.");
        builder.AppendLine("It is unsigned v1 software, so Windows SmartScreen may warn first.");
        builder.AppendLine();
        builder.AppendLine("Preflight");
        foreach (SetupCheck check in snapshot.Checks)
        {
            builder.AppendLine($"- {check.Name}: {(check.Ok ? "ok" : "action needed")} - {check.Action}");
        }

        builder.AppendLine();
        builder.AppendLine("Phone setup values");
        builder.AppendLine("Server URL: " + ValueOrPending(snapshot.Info.ServerUrl));
        builder.AppendLine("Username: " + ValueOrPending(snapshot.Info.UserName));
        builder.AppendLine("Topics: " + ValueOrPending(string.Join(", ", snapshot.Info.Topics)));
        builder.AppendLine("Credential Manager target: " + ValueOrPending(snapshot.Info.CredentialTarget));
        builder.AppendLine();
        builder.AppendLine("Password lookup");
        builder.AppendLine("Open Control Panel -> Credential Manager -> Windows Credentials.");
        builder.AppendLine("Find the target above after setup finishes. Do not commit or share the password.");
        builder.AppendLine();
        builder.AppendLine("Payload");
        builder.AppendLine(snapshot.PayloadPath);
        return builder.ToString();
    }

    private static string ValueOrPending(string value)
    {
        return string.IsNullOrWhiteSpace(value) ? "pending setup" : value;
    }

    private void OpenLogFolder()
    {
        string? folder = Path.GetDirectoryName(engine.LogPath);
        if (folder is null)
        {
            return;
        }

        Directory.CreateDirectory(folder);
        ProcessStartInfo startInfo = new()
        {
            FileName = folder,
            UseShellExecute = true
        };
        Process.Start(startInfo);
    }
}
