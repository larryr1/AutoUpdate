﻿#Requires -RunAsAdministrator

$isElevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isElevated -eq $false) {
  Write-Host -ForegroundColor Red "This script must be running with elevated privileges to continue."
  Write-Host -NoNewLine 'Press any key to continue...';
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
  exit
}



function Configure-AutoLogon {

  Param([string]$Username, [string]$Password, [string]$Uses = 1)

  $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $RegistryPath 'AutoAdminLogon' -Value "1" -Type String -Force
  Set-ItemProperty $RegistryPath 'AutoLogonCount' -Value $Uses -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultUsername' -Value "$Username" -type String -Force
  Set-ItemProperty $RegistryPath 'DefaultPassword' -Value "$Password" -type String -Force
  Set-ItemProperty $RegistryPath 'LastUsedUsername' -Value "$Username" -type String -Force
  
}

function Continuity-Restart {
  Configure-AutoLogon -Username config.logon.continuity.username -Passsword config.logon.continuity.password -Uses 1
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
  Start-Process -FilePath "shutdown.exe" -ArgumentList '/r /f /t 10 /c "The system is restarting in 10 seconds for planned updates.'
}

function Completion-Restart {
  Configure-AutoLogin -Username $config.logon.completion.username -Password $config.logon.completion.password -Users 1
  Restart-System
}

function Create-RegistryKeys {
  $KeyPath = "HKLM:\SOFTWARE\larryr1\AutoUpdate"  
  $ValueName = "PostUpdateCheck"  
  $ValueData = "0
  "  
  try {  
      Get-ItemProperty -Path $KeyPath -Name $valueName -ErrorAction Stop | Out-Null
  }  
  catch [System.Management.Automation.ItemNotFoundException] {  
      New-Item -Path $KeyPath -Force  
      New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Force  
  }  
  catch {  
      New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type String -Force  
  }  
}

function Delete-RegistryKeys {
  $KeyPath = "HKLM:\SOFTWARE\larryr1\"
  if (Test-Path -Path $KeyPath) {
    Remove-Item -Path $KeyPath -Recurse
  }
}

Write-Host Installing required modules...
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module SQLServer -Confirm:$False -Force

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

Write-Host -ForegroundColor Green "Received config from the server."
Write-Host -ForegroundColor DarkGreen $configResponse
$config = ($configResponse | ConvertFrom-Json)

Write-Host -ForegroundColor Yellow "Getting available updates. Computer may restart automatically."
Write-Host -ForegroundColor Yellow "Configured autologon for user $($config.logon.continuity.username)"
Configure-AutoLogon -Username config.logon.continuity.username -Passsword config.logon.continuity.password -Uses 1
RestartRequired-Checkpoint
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot

<# foreach ($update in $availableUpdates) {

  # Make sure no restarts are pending
  RestartRequired-Checkpoint

  # Start processing update
  Write-Host -ForegroundColor Cyan "Installing $(If ($update.KB -eq '') {"(NO KB)"} Else { $update.KB }) ($($update.Size)) $($update.Title)"

  # Download
  if ($update.IsDownloaded() -eq $true) {
    Write-Host -ForegroundColor Yellow "   - Update has been previously downloaded. Continuing to installation."
  } else {
    Write-Host -ForegroundColor Yellow "   - Downloading update."
    Get-WindowsUpdate -Download -MicrosoftUpdate -AcceptAll -UpdateID $update.Identity().UpdateID()
    Write-Host -ForegroundColor DarkGreen "   - Downloading complete."
  }

  # Install
  Write-Host -ForegroundColor Yellow "   - Installing update."
  Get-WindowsUpdate -Install -MicrosoftUpdate -AcceptAll -UpdateID $update.Identity().UpdateID()
  Write-Host -ForegroundColor DarkGreen "   - Installation complete."
} #>

Write-Host -ForegroundColor Green "Finished update installation."

RestartRequired-Checkpoint

# Post Update Check
Create-RegistryKeys

$postUpdateCheck = Get-ItemProperty -Path "HKLM:\SOFTWARE\larryr1\AutoUpdate\" -Name "PostUpdateCheck"
if ($postUpdateCheck -eq "1") {
  Delete-RegistryKeys
  Write-Host -ForegroundColor Green "Updates are complete. Restarting to log in to pre-configured completion account ($($config.logon.completion.username))."
  Completion-Restart
} else {
  Set-ItemProperty -Path "HKLM:\SOFTWARE\larryr1\AutoUpdate\" -Name "PostUpdateCheck" -Value "1" -Force
  Write-Host -ForegroundColor Green "Updates are almost complete. Restarting to check for any final updates. (Using account $($config.logon.continuity.username).)"
  Continuity-Restart
}

Write-Host -ForegroundColor Magenta "Exit."
exit