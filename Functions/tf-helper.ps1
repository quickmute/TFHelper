################################################
## Module primer ##
################################################
# This piece code will always run when 
# the module is installed
################################################
# This module only support single domain and org
################################################
if(!$tf_domain){
    $tf_domain = "app.terraform.io" 
}

if(!$tf_org){
  if($null -ne $env:TF_ORG){
    $tf_org = $env:TF_ORG
  }else{
    write-host "Org Name Not Found."
  }
}

if(!$tf_token){
    # Run `terraform import $domain` to populate this
    $credentialPath = "$($env:userprofile)\AppData\Roaming\terraform.d\credentials.tfrc.json"
    if(test-path($credentialPath)){
        write-host $credentialPath, "found"
        $tf_token = ((get-content -Path $credentialPath) | convertfrom-json).credentials.$($tf_domain).token 
    }else{
        if($null -ne $env:TF_TOKEN_app_terraform_io){
            write-host "env:TF_TOKEN_app_terraform_io found"
            $tf_token = $env:TF_TOKEN_app_terraform_io
        }elseif ($null -ne $env:TF_TOKEN){
            write-host "env:TF_TOKEN found"
            $tf_token = $env:TF_TOKEN
        }else{
            write-host $credentialPath, "not found."
        }
    }
}

function tf-custom-invoke{
<#
.Description
This is a wrapper for invoke-restmethod. 
Put your custom outputs and errors here. 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $endpoint,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Get","Patch","Post","Delete")]
        $method,
        $body,
        $this_domain,
        $this_token,
        $this_org
    )

    if (!$this_domain){
        $this_domain = $tf_domain
    }

    if (!$this_token){
        $this_token = $tf_token
    }

    if (!$this_org){
        $this_org = $tf_org
    }

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $this_token")
    $headers.Add("Content-Type","application/vnd.api+json")
    $domain = [System.Uri] "https://$this_domain"
    $api_version = "/api/v2"
    # Substitute :orgName with the above orgName variable
    $endpoint = $endpoint.Replace(":orgName",$this_org)
    # create the new uri using above domain and new endpoint after substitution
    $uri = "$($domain)$($api_version)$($endpoint)" 
    $response = $null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
    ## these are all the http actions we are expecting. Use the below block to define unique outputs and error catching. 
    write-host $method, $uri
    switch($method){
        "Get" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method
            }catch{
                $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - GET $uri - $($_.Exception.Message)"
                $errorMsg | Out-File -FilePath "tf-helper-errors.log" -Append
                write-host "API request failed: $($_.Exception.Message)"
            }
        }
        "Patch" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method -Body $body
                
            }catch{
                $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - PATCH $uri - $($_.Exception.Message)"
                $errorMsg | Out-File -FilePath "tf-helper-errors.log" -Append
                write-host "API request failed: $($_.Exception.Message)"
            }
        }
        "Post" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method -Body $body
            }catch{
                $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - POST $uri - $($_.Exception.Message)"
                $errorMsg | Out-File -FilePath "tf-helper-errors.log" -Append
                $errorMsg2 = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - POST $uri - $(($Error[0].ErrorDetails.Message | convertfrom-json).errors)"
                $errorMsg2 | Out-File -FilePath "tf-helper-errors.log" -Append
                write-host "API request failed: $($_.Exception.Message)"
            }
        }
        "Delete" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method -Body $body
            }catch{
                $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DELETE $uri - $($_.Exception.Message)"
                $errorMsg | Out-File -FilePath "tf-helper-errors.log" -Append
                write-host "API request failed: $($_.Exception.Message)"
            }
        }
    }
    return $response
}

function tf-special-get-workspace-children{
    <#
    .Description
    Gets list of children given an orchestrator workspace
    1. Get current run id: tf-workspace-get-current-run -workspaceId
    2. Get Sentinel Policy: tf-run-get-policy-check -run_id run-BtJXFYN6pAxmy9WK
    3. Get the output link for policy run: $output.data[0].links
    4. Search for Children workspace output
    5. Return a PSObject of children workspaces
    #>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID,
        $this_domain,
        $this_token,
        $this_org
    )
    $domain = [System.Uri] "https://$tf_domain"

    $run_id = tf-workspace-get-current-run -workspaceName $workspaceName -workspaceID $workspaceID -this_domain $this_domain -this_token $this_token -this_org $this_org
    $policy_run =  tf-run-get-policy-check -run_id $run_id -this_domain $this_domain -this_token $this_token -this_org $this_org
    $policy_link = $policy_run.data[0].links.output
    $downloadURL = "$($domain)$($policy_link)"
    $request = tf-custom-webrequest -URL $downloadURL -this_token $this_token
    $json_content = [System.Text.Encoding]::ASCII.GetString($request.Content)
    $start_string = $json_content.IndexOf("=_-^-_==_-^-_==_-^-_==_-^-_==_-^-_=") # unique string to pick up starting point
    $end_string = $json_content.IndexOf("=_-+-_==_-+-_==_-+-_==_-+-_==_-+-_=") # unique string to pick up end point
    if ($start_string -eq -1 -or $end_string -eq -1) {
        write-host "Workspace output not found. Either this is empty orc or not an orc at all"
        return @()
    }
    ## start string is ONLY valid if it's found, otherwise ignore
    $start_string = $start_string + 35
    $workspaces = $json_content.Substring($start_string, $end_string - $start_string) -split "\r?\n" | ` #split things based on carriage return, this is cross-platform compatible
                    Where-Object {$_.Trim() -and $_ -notmatch "^Total:"} | ` #make sure we don't pick up the total line, not sure if needed
                    ForEach-Object {$_.Trim() -replace " [~+-]$"} #make sure we ignore any of those funky symbols we put at end of our output
    return $workspaces
}

function tf-custom-webrequest{
<#
.Description
This is a wrapper for invoke-webrequest. 
Put your custom outputs and errors here. 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $URL,
        $this_token
    )

    if (!$this_token){
        $this_token = $tf_token
    }
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $this_token")
    $headers.Add("Content-Type","application/vnd.api+json")

    return invoke-webrequest -UseBasicParsing -uri $URL -Headers $headers -ErrorAction Stop
}
