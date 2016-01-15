 # Install mandatory features on all machines
 Add-WindowsFeature Telnet-Client
 New-Item -ItemType Directory -Path C:\Temp -Force
 
 switch ($env:COMPUTERNAME) {
    #Domain Controller
    'DC01' {
        #Create OU Structure
        Add-WindowsFeature RSAT-ADDS
        $OU = Get-ADOrganizationalUnit -Identity "OU=Users,OU=TP2B Corp,DC=corp,DC=tp2b,DC=com" -ErrorAction Ignore -WarningAction Ignore
        if (-not($OU)) {
            New-ADOrganizationalUnit -Name "TP2B Corp" -ProtectedFromAccidentalDeletion $false
            New-ADOrganizationalUnit -Path "OU=TP2B Corp,DC=corp,DC=tp2b,DC=com" -Name "Users" -ProtectedFromAccidentalDeletion $false
            New-ADOrganizationalUnit -Path "OU=TP2B Corp,DC=corp,DC=tp2b,DC=com" -Name "Groups" -ProtectedFromAccidentalDeletion $false
        }
        #region create test users
       
        Invoke-WebRequest -Uri https://raw.githubusercontent.com/daltondhcp/PowerShell/master/Azure/Atea/EMS/FirstLastEurope.csv -OutFile C:\temp\FirstLastEurope.csv -UseBasicParsing
        $Names = Import-CSV C:\Temp\FirstLastEurope.csv | Select-Object -First 50
        $Password = 'Pa$$w0rd'
        $UPNSuffix = (Get-ADDomain).DnsRoot
        $OU = "OU=Users,OU=TP2B Corp,DC=corp,DC=tp2b,DC=com"
        foreach ($name in $names) {
            
            #Generate username and check for duplicates
            $firstname = $name.firstname
            $lastname = $name.lastname 

            $username = $name.firstname.Substring(0,3).tolower() + $name.lastname.Substring(0,3).tolower()
            $exit = 0
            $count = 1
            do
            { 
                try { 
                    $userexists = Get-AdUser -Identity $username
                    $username = $firstname.Substring(0,3).tolower() + $lastname.Substring(0,3).tolower() + $count++
                }
                catch {
                    $exit = 1
                }
            }
            while ($exit -eq 0)

            #Set Displayname and UserPrincipalNBame
            $displayname = "$firstname $lastname ($username)"
            if ($username -eq "alpast") {
                $upn = "{0}.{1}@{2}" -f $firstname,$lastname,(Get-ADForest).upnsuffixes[0]
            } else {
                $upn = "$username@$upnsuffix"
            }
            #Create the user
            Write-Host "Creating user $username in $ou"
            New-ADUser –Name $displayname –DisplayName $displayname `
                 –SamAccountName $username -UserPrincipalName $upn `
                 -GivenName $firstname -Surname $lastname -description "Test User" `
                 -Path $ou –Enabled $true –ChangePasswordAtLogon $false -Department $Department `
                 -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -force) 

        }
        #endregion create test users

    }
    'APP01'{
        Add-WindowsFeature Net-Framework-Core
    }
    'CM01' {
        Enable-PSRemoting -Force
        #Open Firewall ports for SQL
        New-NetFirewallRule -DisplayName "Allow inbound TCP Port 1433" –Direction inbound –LocalPort 1433 -Protocol TCP -Action Allow
        New-NetFirewallRule -DisplayName "Allow outbound TCP Port 1433" –Direction outbound –LocalPort 1433 -Protocol TCP -Action Allow
        New-NetFirewallRule -DisplayName "Allow inbound TCP Port 1434" -Direction inbound –LocalPort 1434 -Protocol TCP -Action Allow
        New-NetFirewallRule -DisplayName "Allow outbound TCP Port 1434" -Direction outbound –LocalPort 1434 -Protocol TCP -Action Allow
        #Download ConfigMgr Media
        Start-BitsTransfer  -Source "http://care.dlservice.microsoft.com/dl/download/E/F/3/EF388C92-F307-42B7-989F-FF4DA328B328/SC_Configmgr_1511.exe" -Destination c:\temp\
        #Add CORP\sysadmin as administrator to the sql server.
        $AdminUsername = 'cm01\sysadmin'
        $AdminPassword = (ConvertTo-SecureString -AsPlainText 'Pa$$w0rd' -Force)
        $SQLCredentials = (New-Object System.Management.Automation.PSCredential -ArgumentList $AdminUsername, $AdminPassword)

        Invoke-Command -ComputerName CM01 -Credential $SQLCredentials -ScriptBlock {
            Invoke-Sqlcmd -Database master -HostName CM01 -Query "CREATE LOGIN [CORP\sysadmin] FROM WINDOWS WITH DEFAULT_DATABASE=[master]"
            Invoke-Sqlcmd -Database master -HostName CM01 -Query "EXEC master..sp_addsrvrolemember @loginame = N'corp\sysadmin', @rolename = N'sysadmin'"
        }
    }
    'CL01' {
        #Add Domain users to the machines remote desktop users group

        $localGroupName = "Remote Desktop Users"
        $domainGroupName = "Domain Users"
        $DomainName = "corp.tp2b.com"
        $vname = $env:COMPUTERNAME
        try { 
            $adsi = [ADSI]"WinNT://$vname/$localGroupName,group" 
            $adsi.add("WinNT://$DomainName/$domainGroupName,group")  
        } catch {
        }
    }
    }
 