Configuration SharePoint2019
{
    #region Credentials
    $AdminCreds = Get-AutomationPSCredential -Name "AdminCreds"
    $SPSetup    = Get-AutomationPSCredential -Name "SPSetup"
    $SPFarm     = Get-AutomationPSCredential -Name "SPFarm"
    #endregion

    #region DSC Resources
    Import-DscResource -ModuleName "xComputerManagement" -ModuleVersion "4.1.0.0"
    Import-DscResource -ModuleName "xDisk"               -ModuleVersion "1.0"
    Import-DscResource -ModuleName "cDisk"               -ModuleVersion "1.0"
    Import-DscResource -ModuleName "xNetworking"         -ModuleVersion "5.7.0.0"
    Import-DscResource -ModuleName "SharePointDSC"       -ModuleVersion "3.4.0.0"
    Import-DscResource -ModuleName "xDownloadISO"        -ModuleVersion "1.0"
    #endregion

    Node $AllNodes.NodeName
    {
        $DomainCreds = New-Object System.Management.Automation.PSCredential ("$($ConfigurationData.Settings.DomainName.Split('.')[0])\$($Admincreds.UserName)", $Admincreds.Password)
        xDownloadISO DownloadTAPBits
        {
            SourcePath               = "https://download.microsoft.com/download/C/B/A/CBA01793-1C8A-4671-BE0D-38C9E5BBD0E9/officeserver.img"
            DestinationDirectoryPath = "c:\SP2019"
            PsDscRunAsCredential     = $Admincreds
        }

        xWaitforDisk Disk2
        {
            DiskNumber           = 2
            RetryIntervalSec     = 60
            RetryCount           = 30
            PsDscRunAsCredential = $Admincreds
        }

        cDiskNoRestart SPDataDisk
        {
            DiskNumber           = 2
            DriveLetter          = "F"
            DependsOn            = "[xWaitforDisk]Disk2"
            PsDscRunAsCredential = $Admincreds
        }

        WindowsFeature DotNet
        {
            Name                 = "Net-Framework-Core"
            Ensure               = 'Present'
            PsDscRunAsCredential = $Admincreds
        }

        xComputer DomainJoin
        {
            Name                 = $Node.NodeName
            DomainName           = $ConfigurationData.Settings.DomainName
            Credential           = $AdminCreds
            PsDscRunAsCredential = $Admincreds
        }

        Script DisableFirewall
        {
            GetScript = {
                @{
                    GetScript = $GetScript
                    SetScript = $SetScript
                    TestScript = $TestScript
                    Result = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                }
            }
            SetScript = {
                Set-NetFirewallProfile -All -Enabled False -Verbose
            }    
            TestScript = {
                $Status = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                $Status -eq $True
            }
        }

        Group AddUserAccountToLocalAdminsGroup
        {
            GroupName            = "Administrators"
            Credential           = $DomainCreds
            MembersToInclude     = @($SPSetup.UserName, $SPFarm.UserName)
            Ensure               = "Present"
            PsDscRunAsCredential = $DomainCreds
        }

        SPInstallPrereqs Prereqs
        {
            IsSIngleInstance     = "Yes"
            InstallerPath        = "C:\SP2019\PrerequisiteInstaller.exe"
            OnlineMode           = $true
            PsDscRunAsCredential = $DomainCreds
        }

        SPInstall Install
        {
            IsSingleInstance     = "Yes"
            BinaryDir            = "C:\SP2019"
            ProductKey           = "M692G-8N2JP-GG8B2-2W2P7-YY7J6"
            PsDscRunAsCredential = $DomainCreds
        }

        $runCA = $false
        if ($Node.MinRole -eq "WebFrontEnd")
        {
            $runCA = $true
        }
        SPFarm Farm
        {
            IsSingleInstance         = "Yes"
            FarmConfigDatabaseName   = "SPConfig"
            DatabaseServer           = $ConfigurationData.Settings.DatabaseServer
            FarmAccount              = $SPFarm
            Passphrase               = $SPFarm
            AdminContentDatabaseName = "SPAdmin"
            RunCentralAdmin          = $runCA
            ServerRole               = $Node.MinRole
            Ensure                   = "Present"
            PsDscRunAsCredential     = $SPFarm
        }
    }
}
