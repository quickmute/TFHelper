function tf-modules-get-list{
    <#
    .Description
    Return ALL modules
    #>
    param(
        $this_domain,
        $this_token,
        $this_org
    )
    ## may need to adjust this if this takes too long to return single batch
    $pageSize = "100"
    $pageNum = 1
    $modules = @()
    do{ 
        $endpoint = "/organizations/:orgName/registry-modules?page%5Bnumber%5D=$pageNum&page%5Bsize%5D=$pageSize"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
        $modules += $response.data
        $pageNum += 1
    }while ($response.data.count -eq $pageSize)

    return $modules   
}

function tf-modules-delete{
    <#
    .Description
    Delete ALL modules
    #>
    param(
        $modules,
        $this_domain,
        $this_token,
        $this_org
    )

    foreach ($item in $modules){
        $endpoint = $item.links.self -replace "/api/v2", ""
        write-host $endpoint   
        $response = tf-custom-invoke -endpoint $endpoint -Method DELETE -this_domain $this_domain -this_token $this_token -this_org $this_org
    }
}

function tf-module-import{
    <#
    .Description
    Delete ALL modules
    #>
    param(
        $module_org = "StifelFinancial",
        $module_project = "CloudServices-Modules-TFCB",
        $module_repo,
        $module_token,
        $this_domain,
        $this_token,
        $this_org
    )
    $module_identifier = "$module_org/$module_project/_git/$module_repo"
    $module_display_identifier = "$module_org/$module_project/$module_repo"

$json_body = @"
{
  "data": {
    "attributes": {
      "vcs-repo": {
        "identifier":"$module_identifier",
        "oauth-token-id":"$module_token",
        "display_identifier":"$module_display_identifier"
      }
    },
    "type":"registry-modules"
  }
}
"@
    
    $endpoint = "/organizations/:orgName/registry-modules/vcs"
    $response = tf-custom-invoke -endpoint $endpoint -Method POST -this_domain $this_domain -this_token $this_token -this_org $this_org -body $json_body
}

function tf-modules-cleanup{
    <#
    .Description
    Delete bad modules
    #>
    param(
        $modules,
        $this_domain,
        $this_token,
        $this_org
    )

    foreach ($item in $modules){
        $delete_mod = $false
        if ($item.attributes.status -notin ('setup_complete','no_version_tags')){
            write-host $item.attributes.name, ":", $item.attributes.status
            $delete_mod = $true
        }else{
            foreach($version in $item.attributes.'version-statuses'){
                if ($version.status -ne 'ok'){
                    write-host ($item.attributes.name, ":", $version.version, $version.status)
                    $delete_mod = $true
                    break
                }
            }
        }
        if ($delete_mod){
            $endpoint = $item.links.self -replace "/api/v2", ""
            $module_name = $item.attributes.name
            $response = tf-custom-invoke -endpoint $endpoint -Method DELETE -this_domain $this_domain -this_token $this_token -this_org $this_org
        }        
    }
}
