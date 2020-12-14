# What is the goal of this PowerShell script?

When using on-premise version of UiPath Orchestrator, libraries used by robots are stored on UiPath Orchestrator and need to be updated manually.
This script helps to automatically get your UiPath Orchestrator libraries up-to-date, so that when you're upgrading dependencies of projects in UiPath Studio and publishing them to UiPath Orchestrator, latest versions of activities are available for UiPath Robots.

# Configuration

The configuration is handled in `config.json` file. Make a copy of `config.example.json` file and name it `config.json`.

First, you need to specify information about "Reference UiPath Orchestrator". It will be defined as reference, meaning that downloaded libraries will have versions greater than those available in this UiPath Orchestrator.

Next, you must specify information about "Target UiPath Orchestrator(s)". They will be defined as targets, meaning that downloaded libraries will be uploaded to these UiPath Orchestrators.

Eventually, you have to define NuGet feeds. They will be searched for new versions of libraries. NuGet feeds are scanned in the order they are defined, it means that if a library is not found in a feed, next one will be searched for.

Please note that `config.json`file must be valid against `config-schema.json` schema.

# Execution

After filling `config.json` file, just start `UpdateLibraries.ps1` script from a PowerShell command prompt.

`PS C:\Path\To\Script> .\UpdateLibraries.ps1`

# Logs

At each execution, a log file is created in `logs` folder. The file should be checked to point out which libraries were not downloaded successfully.

# Compatibility

The script has been developed under PowerShell 5.1.17763.1490 in a Windows 10 environment, so it should work with above versions of PowerShell.

The tool has been test on UiPath Orchestrator 2019.10 on-premise version.

# Support

Github: [https://github.com/masiref/UiPathOrchestratorLibrariesUpdater](https://github.com/masiref/UiPathOrchestratorLibrariesUpdater)

Email: masire.fofana@natixis.com