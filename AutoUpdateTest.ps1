cls
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

  [System.Net.IPAddress]
  Write-Host -ForegroundColor Green "Got advertisement. Contacting server at $($receiveEndpoint.ToString())."
  Invoke-WebRequest -Uri "$($receiveEndpoint.ToString()))/v1/update_configuration"