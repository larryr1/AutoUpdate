#Requires -RunAsAdministrator

$registryKeyPath = "HKLM:\SOFTWARE\larryr1\AutoUpdate\"
$legalKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

$isElevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isElevated -eq $false) {
  Write-Host -ForegroundColor Red "This script must be running with elevated privileges to continue."
  Write-Host -NoNewLine 'Press any key to continue...';
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
  exit
}



function Configure-AutoLogon {

  Param([string]$Username, [string]$Password, [string]$Domain = "", [string]$Uses = 1)

  $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $RegistryPath 'AutoAdminLogon' -Value "1" -Type String -Force
  Set-ItemProperty $RegistryPath 'AutoLogonCount' -Value $Uses -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultUsername' -Value "$Username" -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultPassword' -Value "$Password" -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultDomainName' -Value "$Domain" -type String -Force
  Set-ItemProperty $RegistryPath 'LastUsedUsername' -Value "$Username" -type String -Force
  
}

function Remove-AutoLogon {
  $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $RegistryPath 'AutoAdminLogon' -Value "0" -Type String -Force
  Set-ItemProperty $RegistryPath 'AutoLogonCount' -Value "0" -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultUsername' -Value "" -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultPassword' -Value "" -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultDomainName' -Value "" -type String -Force
  Set-ItemProperty $RegistryPath 'LastUsedUsername' -Value "" -type String -Force
}

function Continuity-Restart {
  Configure-AutoLogon -Username $config.logon.continuity.username -Password $config.logon.continuity.password -Domain $config.logon.continuity.domain -Uses 1
  Restart-System
}

function Is-RestartRequired {
  return $(Get-WURebootStatus)[0].RebootRequired
}

function RestartRequired-Checkpoint {
  if ($(Is-RestartRequired) -eq $true) {
    Write-Host -ForegroundColor Yellow "The machine needs to restart before continuing. The macine will restart in 10 seconds."
    Continuity-Restart
    Start-Sleep -Seconds 30
    exit
  }
}

function Restart-System {
  Start-Process -FilePath "shutdown.exe" -ArgumentList '/r /f /t 10 /c "The system is restarting in 10 seconds for planned updates."'
}

function Completion-Restart {
  Configure-AutoLogin -Username $config.logon.completion.username -Password $config.logon.completion.password -Domain $config.logon.completion.domain -Users 1
  Restart-System
}

function Log-Off {
  Start-Process -FilePath "shutdown.exe" -ArgumentList '/f /l'
}

function Create-RegistryKeys {
  New-Item -Path $registryKeyPath -ErrorAction Ignore
  New-ItemProperty -Path $registryKeyPath -Name PostUpdateCheck -ErrorAction Ignore
  New-ItemProperty -Path $registryKeyPath -Name StoredLegalCaption -ErrorAction Ignore
  New-ItemProperty -Path $registryKeyPath -Name StoredLegalText -ErrorAction Ignore
  New-ItemProperty -Path $registryKeyPath -Name LegalNoticeDisabled -ErrorAction Ignore
}

function Delete-RegistryKeys {
  if (Test-Path -Path $registryKeyPath) {
    Remove-Item -Path $registryKeyPath -Recurse
  }
}

function Disable-AUP {
    if ((Get-ItemProperty -Path $registryKeyPath -Name LegalNoticeDisabled -ErrorAction Stop).LegalNoticeDisabled -ne 1) {

        # Get the system legal keys
        $systemLegalCaption = (Get-ItemProperty -Path $legalKeyPath -Name legalnoticecaption -ErrorAction Stop).legalnoticecaption
        $systemLegalText = (Get-ItemProperty -Path $legalKeyPath -Name legalnoticetext -ErrorAction Stop).legalnoticetext

        # Set legal keys in program storage keys
        New-ItemProperty -Path $registryKeyPath -Name "StoredLegalCaption" -Value $systemLegalCaption -Force
        New-ItemProperty -Path $registryKeyPath -Name "StoredLegalText" -Value $systemLegalText -Force

        # Delete system legal keys
        Remove-ItemProperty -Path $legalKeyPath -Name legalnoticecaption -ErrorAction Stop -Force
        Remove-ItemProperty -Path $legalKeyPath -Name legalnoticetext -ErrorAction Stop -Force

        # Mark notice as disabled
        Set-ItemProperty -Path $registryKeyPath -Name LegalNoticeDisabled -ErrorAction Stop -Value 1
    }
}

function Enable-AUP {
    if ((Get-ItemProperty -Path $registryKeyPath -Name LegalNoticeDisabled -ErrorAction Stop).LegalNoticeDisabled -eq "1") {

        # Get the copy of system legal keys
        $storedLegalCaption = (Get-ItemProperty -Path $registryKeyPath -Name "StoredLegalCaption" -ErrorAction Stop).StoredLegalCaption
        $storedLegalText = (Get-ItemProperty -Path $registryKeyPath -Name "StoredLegalText" -ErrorAction Stop).StoredLegalText

        # Set legal keys in system registry
        New-ItemProperty -Path $legalKeyPath -Name "legalnoticecaption" -Value $storedLegalCaption -Force
        New-ItemProperty -Path $legalKeyPath -Name "legalnoticetext" -Value $storedLegalText -Force

        # Clear storage keys
        Set-ItemProperty -Path $registryKeyPath -Name "StoredLegalCaption" -Value "" -Force
        Set-ItemProperty -Path $registryKeyPath -Name "StoredLegalText" -Value "" -Force

        # Mark notice as enabled
        Set-ItemProperty -Path $registryKeyPath -Name LegalNoticeDisabled -ErrorAction Stop -Value 0
    }
}

function Set-WallpaperStatus {
  
  $videoSettings = (Get-WmiObject Win32_VideoController | Select CurrentHorizontalResolution, CurrentVerticalResolution)

  $filename = $env:TEMP + [guid]::NewGuid() + ".bmp"
  $bmp = new-object System.Drawing.Bitmap ([int]$videoSettings.CurrentHorizontalResolution[1]),([int]$videoSettings.CurrentVerticalResolution[1])
  
  # Text font
  $font = new-object System.Drawing.Font Consolas,24
  $font2 = new-object System.Drawing.Font Consolas,18
  $bgBrush = [System.Drawing.Brushes]::LightGreen 
  $fgBrush = [System.Drawing.Brushes]::Black
  
  # Calc text position
  $message = "Updates complete on " + (Get-Date -Format "dddd MM/dd/yyyy HH:mm K" )
  $message2 = "A machine restart is suggested."
  
  $graphics = [System.Drawing.Graphics]::FromImage($bmp)
  $graphics.FillRectangle($bgBrush, 0, 0, $bmp.Width, $bmp.Height)
  
  $textSize = $graphics.MeasureString($message, $font)
  $text2Size = $graphics.MeasureString($message2, $font2)
  
  $mWidth = [math]::Floor(([int]$videoSettings.CurrentHorizontalResolution[1] - $textSize.Width) / 2)
  $m2Width = [math]::Floor(([int]$videoSettings.CurrentHorizontalResolution[1] - $text2Size.Width) / 2)
  
  $graphics.DrawString($message, $font, $fgBrush, $mWidth, 100)
  $graphics.DrawString($message2, $font2, $fgBrush, $m2Width, 150)
  $graphics.Dispose()
  
  # Save
  $bmp.Save($filename) 
  
  # Write Registry Key, will revert to school image via GP on reboot.
  Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization\" -Name "LockScreenImage" -Value $filename
}

Write-Host Ensuring NuGet is up to date...
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

Write-Host Installing required modules...

Write-Host Trusting repository PSGallery...
Set-PSRepository PSGallery -InstallationPolicy Trusted

Write-Host Installing module PSWindowsUpdate...
Install-Module PSWindowsUpdate -Confirm:$False -Force

Write-Host Loading .NET assemblies System.Windows.Forms and System.Drawing...
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Clear-Host
Write-Host "Automatic Windows Update"
write-Host -ForegroundColor Cyan "This machine is $(((ipconfig) -match 'IPv4').split(':')[1].trim())."
Write-Host -ForegroundColor Yellow "Waiting for configuration server advertisement."

$port = 28424
$receiveEndpoint = New-Object System.Net.IPEndPoint ([IPAddress]::Any, $port)
Try {
  while($true) {
    $socket = New-Object System.Net.Sockets.UdpClient $port
    $content = $socket.Receive([ref]$receiveEndpoint)
    $socket.Close()
    [string]$data = [Text.Encoding]::ASCII.GetString($content)

    # On good packet, parse data
    if ($data.StartsWith("AUA") -eq $true) {
      [string[]]$packetArgs = $data.Split(",")

      Try {
        $receiveEndpoint.Address = [System.Net.IPAddress]::Parse($packetArgs[1])
      } Catch {
        Write-Host -BackgroundColor Red "The received IP address ($($packetArgs[1])) is not valid. Waiting for another advertisement."
        continue
      }

      Try {
        $receiveEndpoint.Port = [int]::Parse($packetArgs[2])
      } Catch {
        Write-Host -BackgroundColor Red "The received port ($($packetArgs[2])) is not valid. Waiting for another advertisement."
        continue
      }

      break
    }
  }
} Catch {
    "$($Error[0])"
}

$contactUri = "$($receiveEndpoint.ToString())/v1/update_configuration"
Write-Host -ForegroundColor Green "Got advertisement. Contacting server at $($contactUri)."

$configResponse = $null;
try {
  $configResponse = (Invoke-WebRequest -Uri $contactUri -UseBasicParsing).Content
}
catch {
  Write-Host -ForegroundColor Red "There was an error contacting the server."
  Write-Host $_.ScriptStackTrace

  Write-Host -NoNewLine 'Press any key to continue...';
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

  exit
}

Write-Host -ForegroundColor Green "Received configuration from the server."
Write-Host -ForegroundColor DarkGreen $configResponse
$config = ($configResponse | ConvertFrom-Json)

Write-Host -ForegroundColor Yellow "Starting update process. Computer may restart automatically."
Write-Host -ForegroundColor Yellow "Configured autologon for user $($config.logon.continuity.username)"
Configure-AutoLogon -Username $config.logon.continuity.username -Passsword $config.logon.continuity.password -Domain $config.logon.continuity.domain -Uses 1
Write-Host -ForegroundColor Yellow "Checking Windows Update reboot status."

# Check and reboot if a reboot is required, then install updates.
RestartRequired-Checkpoint
Install-WindowsUpdate -AcceptAll -AutoReboot -Download -Install -Silent

Write-Host -ForegroundColor Green "Finished this update installation session."

RestartRequired-Checkpoint

# Post Update Check
Create-RegistryKeys
Disable-AUP

$autoUpdateKey = Get-ItemProperty -Path $registryKeyPath

if ($autoUpdateKey.PostUpdateCheck -eq "1") {
  Enable-AUP
  Delete-RegistryKeys
    
  Write-Host -ForegroundColor Green "Updates are complete. Signing out."
  Remove-AutoLogon
  Set-WallpaperStatus
  Log-Off
  exit

} else {
  Set-ItemProperty -Path $registryKeyPath -Name "PostUpdateCheck" -Value "1" -Force
  Write-Host -ForegroundColor Green "Restarting to check for any final updates. (Using continuity account $($config.logon.continuity.username))"
  Continuity-Restart
}

Write-Host -ForegroundColor Magenta "Exit."
exit
