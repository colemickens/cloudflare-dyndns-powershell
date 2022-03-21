param(
    [string[]] $records = @("<Your FQDN with Cloudflare>"),
    [string] $email = "<Your Cloudflare logon>",
    [string] $key = "<Your Cloudflare API key>",
    [int] $newTtl = "120"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$authHeaders = @{ "X-Auth-Email" = $email; "X-Auth-Key" = $key }

$newIp = (ConvertFrom-Json (Invoke-WebRequest -UseBasicParsing -Method Get -Uri "https://api.ipify.org?format=json").Content).ip

$zoneResponseRaw = Invoke-WebRequest -UseBasicParsing -Method Get -Uri "https://api.cloudflare.com/client/v4/zones" -Headers $authHeaders
$zoneResponse = ConvertFrom-Json ($zoneResponseRaw).Content

$zoneResponse.result | % {
    $zoneId = $_.id

    $recordResponse = ConvertFrom-Json (Invoke-WebRequest -UseBasicParsing `
        -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records" `
        -Method Get -Headers  $authHeaders)

    $recordResponse.result | % {
        $recordId = $_.id
        if ($records -NotContains $_.name)
        {
            New-Object psobject -Property @{ "name" = $_.name; "response" = $_.content; "action" = "skipped" }
            $action = "skipped"
        }
        elseif ( ($records -Contains $_.name) -and ($_.Type -eq "A") )
        {
            $updateHeaders = $authHeaders.Clone()
            $updateHeaders += @{"Content-Type" = "application/json"}
            try {
                $updateResponseRaw = Invoke-WebRequest -UseBasicParsing `
                    -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId" `
                    -Method Put -Headers  $updateHeaders `
                    -Body (ConvertTo-Json `
                        @{
                            "id" = "$recordId";
                            "type" = $_.type;
                            "name" = $_.name;
                            "content" = $newIp;
                            "ttl" = $newTtl;
                        })
            } catch {
                $exceptionStream = $_.Exception.Response.GetResponseStream()
                $exceptionText = (New-Object System.IO.StreamReader($exceptionStream)).ReadToEnd();
                throw $exceptionText
            }

            $updateResponse = (ConvertFrom-Json $updateResponseRaw).result

            New-Object psobject -Property @{ "name" = $_.name; "response" = $updateResponse.content; "action" = "updated" }
        }
    }
} | Format-Table name,response,action
