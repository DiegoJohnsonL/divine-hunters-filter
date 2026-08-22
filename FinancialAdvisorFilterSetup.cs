using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal sealed class InstallResult
{
    public string Target { get; set; }
    public string RitualMessage { get; set; }
}

internal static class InstallerCore
{
    private const string FilterResource = "FinancialAdvisorFilter";

    private static readonly string[] AudioResources =
    {
        "hibdivine.mp3",
        "HibOmenLight.mp3",
        "Echoes.mp3",
        "OrbOfAnnulment.mp3"
    };

    public static InstallResult Install(string targetFolder, bool enableRitual)
    {
        if (string.IsNullOrWhiteSpace(targetFolder))
            throw new InvalidOperationException("Choose a destination folder first.");

        if (IsPathOfExileRunning())
            throw new InvalidOperationException("Path of Exile 2 is running. Close the game completely, then try again.");

        Directory.CreateDirectory(targetFolder);

        string filterPath = Path.Combine(targetFolder, "FinancialAdvisor Filter.filter");
        string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
        if (File.Exists(filterPath))
            File.Copy(filterPath, filterPath + ".before-financialadvisor-" + stamp + ".bak", true);

        CopyResource(FilterResource, filterPath);
        foreach (string audioResource in AudioResources)
            CopyResource(audioResource, Path.Combine(targetFolder, audioResource));

        string ritualMessage = enableRitual
            ? EnableRitualFilter(Path.Combine(targetFolder, "poe2_production_Config.ini"))
            : "Ritual filtering was left unchanged.";

        return new InstallResult
        {
            Target = targetFolder,
            RitualMessage = ritualMessage
        };
    }

    private static bool IsPathOfExileRunning()
    {
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

        string backupPath = configPath + ".before-financialadvisor.bak";
        File.Copy(configPath, backupPath, true);
        File.WriteAllText(configPath, updated, new UTF8Encoding(true));
        return "Ritual filtering was enabled. A backup of the config was saved beside it.";
    }
}

internal sealed class InstallerForm : Form
{
    private readonly Panel[] pages;
    private readonly TextBox folderBox;
    private readonly CheckBox ritualCheck;
    private readonly Label summaryLabel;
    private readonly Button backButton;
    private readonly Button nextButton;
    private int pageIndex;

    public InstallerForm()
    {
        Text = "FinancialAdvisor Filter Setup";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(700, 430);
        BackColor = Color.White;

        Panel header = new Panel { BackColor = Color.FromArgb(42, 58, 76) };
        SetBounds(header, 0, 0, 700, 66);
        Controls.Add(header);
        Label title = MakeLabel("FinancialAdvisor Filter", 24, 12, 640, 30, 16);
        title.ForeColor = Color.White;
        header.Controls.Add(title);
        Label subtitle = MakeLabel("PoE2 installer", 26, 40, 640, 20, 9);
        subtitle.ForeColor = Color.FromArgb(215, 225, 235);
        header.Controls.Add(subtitle);

        Panel pageHost = new Panel();
        SetBounds(pageHost, 0, 66, 700, 304);
        Controls.Add(pageHost);

        Panel welcome = NewPage();
        welcome.Controls.Add(MakeLabel("Welcome", 24, 22, 640, 32, 15));
        welcome.Controls.Add(MakeLabel(
            "This wizard installs the FinancialAdvisor loot filter and its four custom sounds into your Path of Exile 2 folder.\r\n\r\nIt can also enable the filter inside Ritual rewards. Close the game before continuing.",
            24, 68, 640, 100, 11));
        pageHost.Controls.Add(welcome);

        Panel folder = NewPage();
        folder.Controls.Add(MakeLabel("Choose your Path of Exile 2 folder", 24, 22, 640, 32, 15));
        folder.Controls.Add(MakeLabel("This is normally the folder containing poe2_production_Config.ini.", 24, 60, 640, 26, 10));
        folderBox = new TextBox
        {
            Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "My Games\\Path of Exile 2")
        };
        SetBounds(folderBox, 24, 96, 540, 28);
        folder.Controls.Add(folderBox);
        Button browse = new Button { Text = "Browse..." };
        SetBounds(browse, 576, 95, 96, 30);
        folder.Controls.Add(browse);
        browse.Click += Browse_Click;
        pageHost.Controls.Add(folder);

        Panel ritual = NewPage();
        ritual.Controls.Add(MakeLabel("Ritual rewards", 24, 22, 640, 32, 15));
        ritualCheck = new CheckBox
        {
            Text = "Enable the item filter inside Ritual rewards",
            Checked = true,
            AutoSize = true,
            Font = new Font("Segoe UI", 11)
        };
        SetBounds(ritualCheck, 24, 70, 640, 30);
        ritual.Controls.Add(ritualCheck);
        ritual.Controls.Add(MakeLabel(
            "Recommended. The installer changes apply_item_filter_to_ritual to true and saves a backup of your config file. Uncheck this if you want to change it manually later.",
            48, 116, 600, 70, 10));
        pageHost.Controls.Add(ritual);

        Panel ready = NewPage();
        ready.Controls.Add(MakeLabel("Ready to install", 24, 22, 640, 32, 15));
        summaryLabel = MakeLabel("", 24, 70, 640, 150, 11);
        ready.Controls.Add(summaryLabel);
        pageHost.Controls.Add(ready);

        pages = new[] { welcome, folder, ritual, ready };

        Panel footer = new Panel { BackColor = Color.FromArgb(245, 245, 245) };
        SetBounds(footer, 0, 370, 700, 60);
        Controls.Add(footer);

        Button cancel = new Button { Text = "Cancel" };
        SetBounds(cancel, 510, 15, 78, 30);
        footer.Controls.Add(cancel);
        cancel.Click += delegate { Close(); };

        backButton = new Button { Text = "< Back" };
        SetBounds(backButton, 420, 15, 78, 30);
        footer.Controls.Add(backButton);
        backButton.Click += Back_Click;

        nextButton = new Button { Text = "Next >" };
        SetBounds(nextButton, 596, 15, 80, 30);
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

    private static Label MakeLabel(string text, int x, int y, int width, int height, int fontSize)
    {
        Label label = new Label
        {
            Text = text,
            AutoSize = false,
            Font = new Font("Segoe UI", fontSize)
        };
        SetBounds(label, x, y, width, height);
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
        foreach (Panel page in pages)
            page.Visible = false;
        pages[pageIndex].Visible = true;
        backButton.Enabled = pageIndex > 0;
        nextButton.Text = pageIndex == pages.Length - 1 ? "Install" : "Next >";

        if (pageIndex == pages.Length - 1)
        {
            string ritual = ritualCheck.Checked ? "Enable" : "Leave unchanged";
            summaryLabel.Text =
                "Install to:\r\n" + folderBox.Text.Trim() +
                "\r\n\r\nFilter: FinancialAdvisor Filter.filter\r\nCustom sounds: 4 included\r\nRitual filtering: " + ritual;
        }
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
            InstallResult result = InstallerCore.Install(folderBox.Text.Trim(), ritualCheck.Checked);
            Cursor = Cursors.Default;
            MessageBox.Show(this,
                "Installation complete.\r\n\r\n" + result.Target + "\r\n\r\n" + result.RitualMessage + "\r\n\r\nReselect the filter in-game if Path of Exile 2 is already open.",
                "FinancialAdvisor Filter Setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
        if (args.Length == 2 && string.Equals(args[0], "--test", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                InstallerCore.Install(args[1], true);
                return 0;
            }
            catch
            {
                return 1;
            }
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new InstallerForm());
        return 0;
    }
}
