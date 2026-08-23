using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal sealed class InstallResult
{
    public string Target { get; set; }
    public string FilterMessage { get; set; }
    public string RitualMessage { get; set; }
}

internal static class InstallerCore
{
    private const string UpdaterResource = "DivineHuntersUpdater";
    private const string UpdateTaskName = "Divine Hunters Filter Update";

    public static InstallResult Install(string targetFolder, bool enableRitual, bool recordVersion = true)
    {
        if (string.IsNullOrWhiteSpace(targetFolder))
            throw new InvalidOperationException("Choose a destination folder first.");

        if (IsPathOfExileRunning())
            throw new InvalidOperationException("Path of Exile 2 is running. Close the game completely, then try again.");

        Directory.CreateDirectory(targetFolder);
        FilterChannelResult channel = FilterChannelClient.InstallLatest(targetFolder, null);
        string filterMessage = channel.Changed
            ? "Downloaded and installed the current GitHub filter channel (" + channel.ChangedFiles + " file(s))."
            : "The installed filter and sounds already match the current GitHub filter channel.";

        string ritualMessage = enableRitual
            ? EnableRitualFilter(Path.Combine(targetFolder, "poe2_production_Config.ini"))
            : "Ritual filtering was left unchanged.";

        if (recordVersion)
            RecordInstalledVersion();

        return new InstallResult
        {
            Target = targetFolder,
            FilterMessage = filterMessage,
            RitualMessage = ritualMessage
        };
    }

    public static string ConfigureAutoUpdate(string targetFolder, bool enabled)
    {
        if (string.Equals(Environment.GetEnvironmentVariable("DIVINEHUNTERS_SKIP_AUTOUPDATE"), "1", StringComparison.Ordinal))
            return "Automatic updates were skipped for this test run.";

        if (!enabled)
        {
            DeleteScheduledTask();
            return "Automatic updates are disabled.";
        }

        string updaterFolder = GetUpdaterFolder();
        string updaterPath = Path.Combine(updaterFolder, "DivineHuntersUpdater-" + BuildInfo.Version + ".exe");
        Directory.CreateDirectory(updaterFolder);
        CopyResource(UpdaterResource, updaterPath);

        string taskCommand = QuoteCommandArgument(updaterPath) + " --target " + QuoteCommandArgument(targetFolder);
        string startTime = DateTime.Now.AddMinutes(2).ToString("HH:mm");
        string arguments = "/Create /F /SC DAILY /MO 1 /ST " + startTime
            + " /TN " + QuoteCommandArgument(UpdateTaskName)
            + " /TR " + QuoteCommandArgument(taskCommand);
        int exitCode = RunScheduledTaskCommand(arguments);
        if (exitCode != 0)
            return "Automatic updates could not be enabled; the filter itself was installed successfully.";

        PruneOldUpdaters(updaterFolder, updaterPath);
        return "Automatic updates are enabled; the updater checks the rolling GitHub filter channel daily.";
    }

    public static string RefreshAutoUpdateIfEnabled(string targetFolder)
    {
        if (string.Equals(Environment.GetEnvironmentVariable("DIVINEHUNTERS_SKIP_AUTOUPDATE"), "1", StringComparison.Ordinal))
            return "Automatic updates were skipped for this test run.";

        if (RunScheduledTaskCommand("/Query /TN " + QuoteCommandArgument(UpdateTaskName)) != 0)
            return "Automatic updates remain disabled.";

        return ConfigureAutoUpdate(targetFolder, true);
    }

    private static string GetUpdaterFolder()
    {
        string overrideFolder = Environment.GetEnvironmentVariable("DIVINEHUNTERS_UPDATER_STATE");
        if (!string.IsNullOrWhiteSpace(overrideFolder))
            return overrideFolder;

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DivineHuntersFilter");
    }

    public static void RecordInstalledVersion()
    {
        string updaterFolder = GetUpdaterFolder();
        Directory.CreateDirectory(updaterFolder);
        File.WriteAllText(Path.Combine(updaterFolder, "installed-version.txt"), BuildInfo.Version, Encoding.UTF8);
    }

    private static void PruneOldUpdaters(string updaterFolder, string currentUpdater)
    {
        try
        {
            foreach (string path in Directory.GetFiles(updaterFolder, "DivineHuntersUpdater*.exe"))
            {
                if (string.Equals(path, currentUpdater, StringComparison.OrdinalIgnoreCase))
                    continue;
                try { File.Delete(path); }
                catch { }
            }
        }
        catch
        {
            // A running migration updater can stay behind harmlessly.
        }
    }

    private static void DeleteScheduledTask()
    {
        RunScheduledTaskCommand("/Delete /F /TN " + QuoteCommandArgument(UpdateTaskName));
    }

    private static int RunScheduledTaskCommand(string arguments)
    {
        ProcessStartInfo startInfo = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, "schtasks.exe"),
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using (Process process = Process.Start(startInfo))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string QuoteCommandArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static bool IsPathOfExileRunning()
    {
        if (string.Equals(Environment.GetEnvironmentVariable("DIVINEHUNTERS_SKIP_GAME_CHECK"), "1", StringComparison.Ordinal))
            return false;

        foreach (Process process in Process.GetProcesses())
        {
            try
            {
                if (process.ProcessName.StartsWith("PathOfExile", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch
            {
                // A process can disappear between enumeration and inspection.
            }
            finally
            {
                process.Dispose();
            }
        }
        return false;
    }

    private static void CopyResource(string resourceName, string destination)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream source = assembly.GetManifestResourceStream(resourceName))
        {
            if (source == null)
                throw new FileNotFoundException("The installer is missing embedded resource: " + resourceName);

            using (FileStream output = File.Create(destination))
                source.CopyTo(output);
        }
    }

    private static string EnableRitualFilter(string configPath)
    {
        if (!File.Exists(configPath))
            return "poe2_production_Config.ini was not found; Ritual filtering was not changed.";

        string text = File.ReadAllText(configPath);
        const string pattern = @"(?m)^([ \t]*apply_item_filter_to_ritual[ \t]*=[ \t]*)(?:false|true)([ \t]*)(\r?)$";
        if (!Regex.IsMatch(text, pattern))
            return "The Ritual setting was not found; Ritual filtering was not changed.";

        string updated = Regex.Replace(text, pattern, "$1true$2$3");
        if (updated == text)
            return "Ritual filtering was already enabled.";

        string backupPath = configPath + ".before-divinehunters.bak";
        File.Copy(configPath, backupPath, true);
        File.WriteAllText(configPath, updated, new UTF8Encoding(true));
        return "Ritual filtering was enabled. A backup of the config was saved beside it.";
    }
}

internal static class PoETheme
{
    public static readonly Color Window = Color.FromArgb(9, 10, 12);
    public static readonly Color HeaderTop = Color.FromArgb(45, 44, 42);
    public static readonly Color HeaderBottom = Color.FromArgb(19, 19, 20);
    public static readonly Color Surface = Color.FromArgb(32, 33, 36);
    public static readonly Color Inset = Color.FromArgb(14, 15, 18);
    public static readonly Color Footer = Color.FromArgb(19, 20, 22);
    public static readonly Color Gold = Color.FromArgb(184, 134, 58);
    public static readonly Color GoldBright = Color.FromArgb(240, 195, 107);
    public static readonly Color Text = Color.FromArgb(246, 237, 219);
    public static readonly Color Muted = Color.FromArgb(200, 188, 168);
    public static readonly Color Danger = Color.FromArgb(187, 92, 69);
}

internal sealed class PoEButton : Button
{
    private bool hovering;
    private bool pressed;

    public bool Primary { get; set; }

    public PoEButton()
    {
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        UseVisualStyleBackColor = false;
        Font = new Font("Segoe UI", 10, FontStyle.Bold);
        Cursor = Cursors.Hand;
        TabStop = true;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        hovering = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        hovering = false;
        pressed = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        pressed = true;
        Invalidate();
        base.OnMouseDown(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        pressed = false;
        Invalidate();
        base.OnMouseUp(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Color fill = Primary ? PoETheme.Gold : PoETheme.Surface;
        if (!Enabled)
            fill = Color.FromArgb(25, 26, 29);
        if (Enabled && hovering)
            fill = Primary ? PoETheme.GoldBright : Color.FromArgb(48, 45, 38);
        if (Enabled && pressed)
            fill = Primary ? Color.FromArgb(125, 94, 45) : PoETheme.Inset;

        using (SolidBrush brush = new SolidBrush(fill))
            e.Graphics.FillRectangle(brush, ClientRectangle);

        using (Pen border = new Pen(Primary ? PoETheme.GoldBright : PoETheme.Gold))
            e.Graphics.DrawRectangle(border, 0, 0, Width - 1, Height - 1);

        Color textColor = !Enabled
            ? Color.FromArgb(100, 98, 91)
            : Primary ? Color.FromArgb(24, 21, 17) : PoETheme.Text;
        TextRenderer.DrawText(
            e.Graphics,
            Text,
            Font,
            ClientRectangle,
            textColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
}

internal sealed class InstallerForm : Form
{
    private readonly Panel[] pages;
    private readonly TextBox folderBox;
    private readonly CheckBox ritualCheck;
    private readonly CheckBox autoUpdateCheck;
    private readonly Label summaryLabel;
    private readonly Label stepLabel;
    private readonly Button backButton;
    private readonly Button nextButton;
    private int pageIndex;

    public InstallerForm()
    {
        Text = "Divine Hunters Filter Setup";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(720, 440);
        BackColor = PoETheme.Window;
        Font = new Font("Segoe UI", 10);

        Panel header = new Panel { BackColor = PoETheme.HeaderTop };
        SetBounds(header, 0, 0, 720, 76);
        header.Paint += Header_Paint;
        Controls.Add(header);
        Label title = MakeLabel("Divine Hunters Filter", 72, 10, 600, 30, 18, true);
        title.ForeColor = PoETheme.GoldBright;
        header.Controls.Add(title);
        Label subtitle = MakeLabel("PATH OF EXILE 2  //  FILTER INSTALLATION", 74, 43, 500, 18, 9, false);
        subtitle.ForeColor = PoETheme.Muted;
        header.Controls.Add(subtitle);
        stepLabel = MakeLabel("STEP 1 OF 4", 590, 43, 105, 18, 9, false);
        stepLabel.TextAlign = ContentAlignment.MiddleRight;
        stepLabel.ForeColor = PoETheme.Gold;
        header.Controls.Add(stepLabel);

        Panel pageHost = new Panel { BackColor = PoETheme.Surface };
        SetBounds(pageHost, 18, 92, 684, 258);
        pageHost.Paint += PageHost_Paint;
        Controls.Add(pageHost);

        Panel welcome = NewPage();
        welcome.Controls.Add(MakeLabel("WELCOME, EXILE", 26, 16, 630, 32, 18, true));
        welcome.Controls.Add(MakeLabel(
            "This wizard securely downloads the current Divine Hunters filter and five custom drop sounds from GitHub.\r\n\r\nIt can also enable the filter inside Ritual rewards. Close the game before continuing.",
            28, 62, 630, 90, 12, false));
        welcome.Controls.Add(MakeInsetLabel("Always-current filter + 5 sounds + optional Ritual setting", 28, 168, 630, 34));
        autoUpdateCheck = new CheckBox
        {
            Text = "Check for filter updates daily",
            Checked = true,
            AutoSize = true,
            Font = new Font("Segoe UI", 11),
            ForeColor = PoETheme.Text,
            BackColor = PoETheme.Surface,
            Cursor = Cursors.Hand
        };
        SetBounds(autoUpdateCheck, 28, 214, 630, 30);
        welcome.Controls.Add(autoUpdateCheck);
        pageHost.Controls.Add(welcome);

        Panel folder = NewPage();
        folder.Controls.Add(MakeLabel("CHOOSE DESTINATION", 26, 16, 630, 32, 18, true));
        folder.Controls.Add(MakeLabel("Choose the folder containing poe2_production_Config.ini.", 28, 56, 630, 26, 12, false));
        folderBox = new TextBox
        {
            Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "My Games\\Path of Exile 2")
        };
        folderBox.BackColor = PoETheme.Inset;
        folderBox.ForeColor = PoETheme.Text;
        folderBox.BorderStyle = BorderStyle.FixedSingle;
        folderBox.Font = new Font("Segoe UI", 12);
        SetBounds(folderBox, 28, 88, 520, 34);
        folder.Controls.Add(folderBox);
        PoEButton browse = new PoEButton { Text = "BROWSE..." };
        SetBounds(browse, 558, 89, 100, 34);
        folder.Controls.Add(browse);
        browse.Click += Browse_Click;
        folder.Controls.Add(MakeInsetLabel("Usually: Documents\\My Games\\Path of Exile 2", 28, 144, 630, 34));
        pageHost.Controls.Add(folder);

        Panel ritual = NewPage();
        ritual.Controls.Add(MakeLabel("RITUAL REWARDS", 26, 16, 630, 32, 18, true));
        ritualCheck = new CheckBox
        {
            Text = "Enable the item filter inside Ritual rewards",
            Checked = true,
            AutoSize = true,
            Font = new Font("Segoe UI", 12),
            ForeColor = PoETheme.Text,
            BackColor = PoETheme.Surface,
            Cursor = Cursors.Hand
        };
        SetBounds(ritualCheck, 28, 64, 640, 32);
        ritual.Controls.Add(ritualCheck);
        ritual.Controls.Add(MakeLabel(
            "Recommended. The installer changes apply_item_filter_to_ritual to true and saves a backup of your config file. Uncheck this if you want to change it manually later.",
            52, 106, 610, 66, 12, false));
        ritual.Controls.Add(MakeInsetLabel("The game must be closed while this setting is changed.", 28, 186, 630, 34));
        pageHost.Controls.Add(ritual);

        Panel ready = NewPage();
        ready.Controls.Add(MakeLabel("READY TO DEPLOY", 26, 16, 630, 32, 18, true));
        summaryLabel = MakeInsetLabel("", 28, 60, 630, 150);
        summaryLabel.Font = new Font("Consolas", 11);
        ready.Controls.Add(summaryLabel);
        pageHost.Controls.Add(ready);

        pages = new[] { welcome, folder, ritual, ready };

        Panel footer = new Panel { BackColor = PoETheme.Footer };
        SetBounds(footer, 0, 368, 720, 72);
        footer.Paint += Footer_Paint;
        Controls.Add(footer);

        PoEButton cancel = new PoEButton { Text = "CANCEL" };
        SetBounds(cancel, 458, 19, 86, 34);
        footer.Controls.Add(cancel);
        cancel.Click += delegate { Close(); };

        backButton = new PoEButton { Text = "< BACK" };
        SetBounds(backButton, 366, 19, 86, 34);
        footer.Controls.Add(backButton);
        backButton.Click += Back_Click;

        nextButton = new PoEButton { Text = "NEXT >", Primary = true };
        SetBounds(nextButton, 554, 19, 112, 34);
        footer.Controls.Add(nextButton);
        nextButton.Click += Next_Click;

        AcceptButton = nextButton;
        CancelButton = cancel;
        ShowPage();
    }

    private static Panel NewPage()
    {
        return new Panel { Dock = DockStyle.Fill, Visible = false };
    }

    private static Label MakeLabel(string text, int x, int y, int width, int height, int fontSize, bool display)
    {
        Label label = new Label
        {
            Text = text,
            AutoSize = false,
            Font = display ? new Font("Georgia", fontSize, FontStyle.Bold) : new Font("Segoe UI", fontSize),
            ForeColor = PoETheme.Text,
            BackColor = Color.Transparent
        };
        SetBounds(label, x, y, width, height);
        return label;
    }

    private static Label MakeInsetLabel(string text, int x, int y, int width, int height)
    {
        Label label = MakeLabel(text, x, y, width, height, 10, false);
        label.BackColor = PoETheme.Inset;
        label.ForeColor = PoETheme.Muted;
        label.Padding = new Padding(8, 6, 8, 5);
        return label;
    }

    private static void SetBounds(Control control, int x, int y, int width, int height)
    {
        control.Location = new Point(x, y);
        control.Size = new Size(width, height);
    }

    private void Browse_Click(object sender, EventArgs e)
    {
        using (FolderBrowserDialog dialog = new FolderBrowserDialog())
        {
            dialog.Description = "Choose the Path of Exile 2 folder";
            dialog.ShowNewFolderButton = true;
            if (Directory.Exists(folderBox.Text))
                dialog.SelectedPath = folderBox.Text;
            if (dialog.ShowDialog(this) == DialogResult.OK)
                folderBox.Text = dialog.SelectedPath;
        }
    }

    private void ShowPage()
    {
        bool updateMode = IsUpdateMode();
        foreach (Panel page in pages)
            page.Visible = false;
        pages[pageIndex].Visible = true;
        backButton.Enabled = pageIndex > 0;
        nextButton.Text = pageIndex == pages.Length - 1
            ? (updateMode ? "UPDATE" : "INSTALL")
            : "NEXT >";
        stepLabel.Text = "STEP " + (pageIndex + 1) + " OF " + pages.Length;
        ritualCheck.Enabled = !updateMode;
        ritualCheck.Text = updateMode
            ? "Ritual setting will be preserved during this update"
            : "Enable the item filter inside Ritual rewards";
        autoUpdateCheck.Enabled = !updateMode;
        autoUpdateCheck.Text = updateMode
            ? "Automatic update schedule will be left unchanged"
            : "Check for filter updates daily";

        if (pageIndex == pages.Length - 1)
        {
            string action = updateMode ? "Update" : "Install";
            string ritual = updateMode
                ? "Preserve current setting"
                : ritualCheck.Checked ? "Enable" : "Leave unchanged";
            string updates = updateMode
                ? "Leave unchanged"
                : autoUpdateCheck.Checked ? "Daily check" : "Disabled";
            summaryLabel.Text =
                action + " to:\r\n" + folderBox.Text.Trim() +
                "\r\n\r\nFilter: download current GitHub channel\r\nCustom sounds: verify/download 5\r\nRitual filtering: " + ritual +
                "\r\nAutomatic updates: " + updates;
        }
    }

    private bool IsUpdateMode()
    {
        string path = folderBox.Text.Trim();
        return !string.IsNullOrWhiteSpace(path)
            && (File.Exists(Path.Combine(path, "Divine Hunters.filter"))
                || File.Exists(Path.Combine(path, "FinancialAdvisor Filter.filter")));
    }

    private static void Header_Paint(object sender, PaintEventArgs e)
    {
        Panel header = (Panel)sender;
        using (LinearGradientBrush brush = new LinearGradientBrush(header.ClientRectangle, PoETheme.HeaderTop, PoETheme.HeaderBottom, 90f))
            e.Graphics.FillRectangle(brush, header.ClientRectangle);

        using (Pen line = new Pen(PoETheme.Gold, 1))
            e.Graphics.DrawLine(line, 0, header.Height - 2, header.Width, header.Height - 2);

        using (Pen sigil = new Pen(PoETheme.GoldBright, 1.4f))
        {
            e.Graphics.DrawEllipse(sigil, 18, 16, 38, 38);
            e.Graphics.DrawEllipse(sigil, 25, 23, 24, 24);
            Point[] diamond = { new Point(37, 13), new Point(47, 35), new Point(37, 57), new Point(27, 35) };
            e.Graphics.DrawPolygon(sigil, diamond);
        }
    }

    private static void PageHost_Paint(object sender, PaintEventArgs e)
    {
        Panel panel = (Panel)sender;
        using (Pen border = new Pen(PoETheme.Gold, 1))
            e.Graphics.DrawRectangle(border, 0, 0, panel.Width - 1, panel.Height - 1);
        using (Pen inner = new Pen(Color.FromArgb(59, 53, 43), 1))
            e.Graphics.DrawRectangle(inner, 4, 4, panel.Width - 9, panel.Height - 9);
    }

    private static void Footer_Paint(object sender, PaintEventArgs e)
    {
        Panel footer = (Panel)sender;
        using (Pen line = new Pen(Color.FromArgb(67, 55, 39), 1))
            e.Graphics.DrawLine(line, 0, 0, footer.Width, 0);
    }

    private bool ConfirmTargetFolder()
    {
        string path = folderBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(path))
        {
            MessageBox.Show(this, "Choose a destination folder first.", "Destination required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }

        try
        {
            if (!Directory.Exists(path))
            {
                DialogResult choice = MessageBox.Show(this, "This folder does not exist:\r\n" + path + "\r\n\r\nCreate it?", "Create folder", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (choice != DialogResult.Yes)
                    return false;
                Directory.CreateDirectory(path);
            }
            folderBox.Text = Path.GetFullPath(path);
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "The folder could not be used:\r\n" + ex.Message, "Invalid destination", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return false;
        }
    }

    private void Back_Click(object sender, EventArgs e)
    {
        if (pageIndex > 0)
        {
            pageIndex--;
            ShowPage();
        }
    }

    private void Next_Click(object sender, EventArgs e)
    {
        if (pageIndex == 1 && !ConfirmTargetFolder())
            return;

        if (pageIndex < pages.Length - 1)
        {
            pageIndex++;
            ShowPage();
            return;
        }

        try
        {
            Cursor = Cursors.WaitCursor;
            bool updateMode = IsUpdateMode();
            InstallResult result = InstallerCore.Install(folderBox.Text.Trim(), updateMode ? false : ritualCheck.Checked);
            string updateMessage = updateMode
                ? InstallerCore.RefreshAutoUpdateIfEnabled(folderBox.Text.Trim())
                : InstallerCore.ConfigureAutoUpdate(folderBox.Text.Trim(), autoUpdateCheck.Checked);
            Cursor = Cursors.Default;
            MessageBox.Show(this,
                "Installation complete.\r\n\r\n" + result.Target + "\r\n\r\n" + result.FilterMessage + "\r\n\r\n" + result.RitualMessage + "\r\n\r\n" + updateMessage + "\r\n\r\nReselect the filter in-game if Path of Exile 2 is already open.",
                "Divine Hunters Filter Setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
            Close();
        }
        catch (Exception ex)
        {
            Cursor = Cursors.Default;
            MessageBox.Show(this, ex.Message, "Installation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 2 && string.Equals(args[0], "--update", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                // The legacy updater only marks v1.4.0 installed when both the
                // rolling-channel download and task migration succeed. Otherwise it
                // retains v1.3.0 state and retries this migration on its next run.
                InstallerCore.Install(args[1], false, false);
                string schedule = InstallerCore.ConfigureAutoUpdate(args[1], true);
                if (schedule.StartsWith("Automatic updates could not", StringComparison.Ordinal))
                    return 1;
                InstallerCore.RecordInstalledVersion();
                return 0;
            }
            catch
            {
                return 1;
            }
        }

        if (args.Length == 2 && string.Equals(args[0], "--test", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                InstallerCore.Install(args[1], true, false);
                return 0;
            }
            catch (Exception ex)
            {
                string errorPath = Environment.GetEnvironmentVariable("DIVINEHUNTERS_TEST_ERROR_LOG");
                if (!string.IsNullOrWhiteSpace(errorPath))
                {
                    try { File.WriteAllText(errorPath, ex.ToString()); }
                    catch { }
                }
                return 1;
            }
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new InstallerForm());
        return 0;
    }
}
