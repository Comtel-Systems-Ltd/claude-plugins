using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;

/*  DipTrace schematic plugin: DipTrace invokes this exe with the path to
    plugin_exchange.xml (full schematic in DipTrace XML format). We copy it
    next to the source .dch and generate a compact "<name>.netlist" beside it
    (net connectivity map, diff-friendly, meant to be tracked in git).

    The .dch path comes from the parent Schematic.exe command line (present
    when the file was double-clicked) or the DipTrace recent-files registry
    MRU (covers File > Open). DipTrace 5.1 leaves <ProjectDir> empty and
    titles its window just "Schematics", so neither is usable. Falls back to
    Documents\DipTrace Exports. ImpMode=None in settings.xml, so nothing is
    written back. */
class ExportForClaude
{
    static void Main(string[] args)
    {
        if (args.Length < 1 || !File.Exists(args[0]))
        {
            return;
        }
        string exchangeFile = args[0];

        string destDir = null;
        string baseName = null;

        string dchPath = GetDchFromParentCommandLine() ?? GetDchFromRegistryMru();
        if (dchPath != null && File.Exists(dchPath))
        {
            destDir = Path.GetDirectoryName(dchPath);
            baseName = Path.GetFileNameWithoutExtension(dchPath);
        }

        if (destDir == null || !Directory.Exists(destDir))
        {
            destDir = GetProjectDir(exchangeFile);
        }
        if (destDir == null || !Directory.Exists(destDir))
        {
            destDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "DipTrace Exports");
            Directory.CreateDirectory(destDir);
        }
        if (string.IsNullOrEmpty(baseName))
        {
            baseName = "schematic";
        }

        string xmlOut = Path.Combine(destDir, baseName + ".schematic.xml");
        if (!string.Equals(Path.GetFullPath(exchangeFile), Path.GetFullPath(xmlOut),
                StringComparison.OrdinalIgnoreCase))
        {
            File.Copy(exchangeFile, xmlOut, true);
        }

        //  Netlist generation must never break the XML export.
        try
        {
            string netlist = BuildNetlist(xmlOut);
            File.WriteAllText(Path.Combine(destDir, baseName + ".netlist"), netlist);
        }
        catch
        {
        }
    }

    class PinInfo
    {
        public string Name = "";
        public string Num = "";
    }

    class PartInfo
    {
        public string RefDes = "?";
        public string Value = "";
        public string Name = "";
        public string Style = "";
        public int PinCount;
    }

    /*  Build the net connectivity map:
        === PARTS (n) ===
        RefDes: LibName = Value [pin count]
        === NETS (n) ===
        NET[id] NetName: RefDes.PinNumber[PinName](Value) ...

        Pin names/numbers are resolved through the <Library> section embedded
        in the exchange file (Component Editor XML format), keyed by the
        ComponentStyle attribute. Anything missing falls back to pin index+1. */
    static string BuildNetlist(string xmlPath)
    {
        var doc = new XmlDocument();
        doc.Load(xmlPath);

        var stylePins = new Dictionary<string, List<PinInfo>>();
        foreach (XmlElement comp in doc.SelectNodes("//*[local-name()='Library']//*[@ComponentStyle]"))
        {
            string style = comp.GetAttribute("ComponentStyle");
            if (string.IsNullOrEmpty(style) || stylePins.ContainsKey(style))
            {
                continue;
            }
            var list = new List<PinInfo>();
            foreach (XmlElement pn in comp.SelectNodes(".//*[local-name()='Pins']/*[local-name()='Pin']"))
            {
                var nameNode = pn.SelectSingleNode("*[local-name()='Name']");
                var numNode = pn.SelectSingleNode("*[local-name()='PadNumber']");
                list.Add(new PinInfo
                {
                    Name = nameNode != null ? nameNode.InnerText : "",
                    Num = numNode != null ? numNode.InnerText : ""
                });
            }
            stylePins[style] = list;
        }

        var partById = new Dictionary<int, PartInfo>();
        var parts = new List<PartInfo>();
        foreach (XmlElement p in doc.SelectNodes("//*[local-name()='Components']/*[local-name()='Part']"))
        {
            var refDes = p.SelectSingleNode("*[local-name()='RefDes']");
            var value = p.SelectSingleNode("*[local-name()='Value']");
            var name = p.SelectSingleNode("*[local-name()='Name']");
            var part = new PartInfo
            {
                RefDes = refDes != null ? refDes.InnerText : "?",
                Value = value != null ? value.InnerText : "",
                Name = name != null ? name.InnerText : "",
                Style = p.GetAttribute("ComponentStyle"),
                PinCount = p.SelectNodes("*[local-name()='Pins']/*[local-name()='Pin']").Count
            };
            parts.Add(part);
            int id;
            if (int.TryParse(p.GetAttribute("Id"), out id))
            {
                partById[id] = part;
            }
        }

        var sb = new StringBuilder();
        sb.AppendLine("=== PARTS (" + parts.Count + ") ===");
        foreach (var p in parts)
        {
            sb.AppendLine(p.RefDes + ": " + p.Name + " = " + p.Value + " [" + p.PinCount + " pins]");
        }
        sb.AppendLine();

        var netNodes = doc.SelectNodes("//*[local-name()='Nets']/*[local-name()='Net']");
        sb.AppendLine("=== NETS (" + netNodes.Count + ") ===");
        foreach (XmlElement n in netNodes)
        {
            var nameNode = n.SelectSingleNode("*[local-name()='Name']");
            string netId = n.GetAttribute("Id");
            string netName = nameNode != null ? nameNode.InnerText : "Net" + netId;

            var conn = new List<string>();
            foreach (XmlElement item in n.SelectNodes("*[local-name()='Pins']/*[local-name()='Item']"))
            {
                int partId, pinIdx;
                int.TryParse(item.GetAttribute("Part"), out partId);
                int.TryParse(item.GetAttribute("Pin"), out pinIdx);

                PartInfo part;
                if (!partById.TryGetValue(partId, out part))
                {
                    conn.Add("part" + partId + "." + pinIdx);
                    continue;
                }

                string pinNum = (pinIdx + 1).ToString();
                string pinName = "";
                List<PinInfo> lp;
                if (!string.IsNullOrEmpty(part.Style) && stylePins.TryGetValue(part.Style, out lp) && pinIdx < lp.Count)
                {
                    if (!string.IsNullOrEmpty(lp[pinIdx].Num))
                    {
                        pinNum = lp[pinIdx].Num;
                    }
                    pinName = lp[pinIdx].Name;
                }

                string label = part.RefDes + "." + pinNum;
                if (!string.IsNullOrEmpty(pinName) && pinName != pinNum)
                {
                    label += "[" + pinName + "]";
                }
                if (!string.IsNullOrEmpty(part.Value) && part.Value != part.Name)
                {
                    label += "(" + part.Value + ")";
                }
                conn.Add(label);
            }

            sb.AppendLine("NET[" + netId + "] " + netName + ": " +
                (conn.Count > 0 ? string.Join(" ", conn.ToArray()) : "(no pins)"));
        }
        return sb.ToString();
    }

    /*  Pull <ProjectDir>...</ProjectDir> out of the exchange XML with a cheap
        line scan; the file can be several MB and we only need the header. */
    static string GetProjectDir(string exchangeFile)
    {
        try
        {
            using (var reader = new StreamReader(exchangeFile))
            {
                string line;
                int linesScanned = 0;
                var re = new Regex(@"<ProjectDir>(.*?)</ProjectDir>");
                while ((line = reader.ReadLine()) != null && linesScanned++ < 500)
                {
                    Match m = re.Match(line);
                    if (m.Success)
                    {
                        string dir = m.Groups[1].Value.Trim();
                        return dir.Length > 0 ? dir : null;
                    }
                }
            }
        }
        catch
        {
        }
        return null;
    }

    /*  When the schematic was opened by double-click, Schematic.exe's command
        line is:  "...\Schematic.exe" "D:\path\file.dch"  */
    static string GetDchFromParentCommandLine()
    {
        try
        {
            int myPid = Process.GetCurrentProcess().Id;
            int parentPid = 0;
            using (var searcher = new ManagementObjectSearcher(
                "SELECT ParentProcessId FROM Win32_Process WHERE ProcessId = " + myPid))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    parentPid = Convert.ToInt32(obj["ParentProcessId"]);
                }
            }
            if (parentPid <= 0)
            {
                return null;
            }

            string cmdLine = null;
            using (var searcher = new ManagementObjectSearcher(
                "SELECT CommandLine FROM Win32_Process WHERE ProcessId = " + parentPid))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    cmdLine = obj["CommandLine"] as string;
                }
            }
            if (string.IsNullOrEmpty(cmdLine))
            {
                return null;
            }

            Match m = Regex.Match(cmdLine, @"[A-Za-z]:\\[^""]*?\.dch", RegexOptions.IgnoreCase);
            if (m.Success)
            {
                return m.Value;
            }
        }
        catch
        {
        }
        return null;
    }

    /*  DipTrace keeps a recent-files MRU in the registry; file0 is the
        most recently opened schematic — the current document, unless the
        user has several open and exported an older one. */
    static string GetDchFromRegistryMru()
    {
        try
        {
            using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Novarm\DipTrace\Schematic\Files"))
            {
                if (key != null)
                {
                    return key.GetValue("file0") as string;
                }
            }
        }
        catch
        {
        }
        return null;
    }
}
