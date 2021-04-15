###################
#Notification
# Create, list, show, delete, and update
###################
##https://www.terraform.io/docs/cloud/api/notification-configurations.html


function tf-notification-delete{
<#
.Description
Delete a single notigication configuration. Needs notification config id 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $notificationId
    )
    $endpoint = "/notification-configurations/$notificationId"
    $response = tf-custom-invoke -endpoint $endpoint -Method Delete
    return  $response
}

function tf-notification-update{
<#
.Description
Update a single notigication configuration. 
Needs notification config id 
Will only update list of users, tough cookies
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $notificationId,
        [array]
        $users = @()
    )
    $body = @{
        "data" = @{
            "id" = $notificationId
            "type" = "notification-configurations"
            "attributes" = @{
                "users" = $users
            }
        }
    }

    $json_body = $body | convertto-json
    $endpoint = "/notification-configurations/$notificationId"
    $response = tf-custom-invoke -endpoint $endpoint -body $json_body -Method Patch
    return  $response
}



function tf-notification-show{
<#
.Description
Displays a single notigication configuration. 
Needs notification config id 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $notificationId
    )
    
    $endpoint = "/notification-configurations/$notificationId"
    $response = tf-custom-invoke -endpoint $endpoint -Method Get
    return  $response
}



function tf-notification-list{
<#
.Description
Displays all notification configuration in a workspace. 
Need workspace objects 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces
    )
    foreach ($workspace in $workspaces){
        $workspaceId = $workspace.id
        $endpoint = "/workspaces/$workspaceId/notification-configurations"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
        $result += $response
    }
    return $result
}

function tf-notification-email-add{
<#
.Description
Adds a new workspace email notification 
Need workspace objects
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $true)]
        [string]
        $name,
        [Parameter(Mandatory = $false)]
        [PSObject]
        $users,
        [Parameter(Mandatory = $false)]
        [switch]
        $applying,
        [Parameter(Mandatory = $false)]
        [switch]
        $completed,
        [Parameter(Mandatory = $false)]
        [switch]
        $created,
        [Parameter(Mandatory = $false)]
        [switch]
        $errored,
        [Parameter(Mandatory = $false)]
        [switch]
        $needs_attention,
        [Parameter(Mandatory = $false)]
        [switch]
        $planning,
        [Parameter(Mandatory = $false)]
        [switch]
        $alltriggers

    )
        
    $triggers = @()
    if($applying){
        $triggers += "run:applying"
    }
    if($completed){
        $triggers += "run:completed"
    }
    if($created){
        $triggers += "run:created"
    }
    if($errored){
        $triggers += "run:errored"
    }
    if($needs_attention){
        $triggers += "run:needs_attention"
    }
    if($planning){
        $triggers += "run:planning"
    }
    if($alltriggers){
        $triggers = "run:applying","run:completed","run:created","run:errored","run:needs_attention","run:planning"
    }

    #create user data
    $userList = @()
    foreach ($user in $users){
        write-host $user    
        $hash = @{
            id       = $user.id
            type     = "users"
        }
        $Object = New-Object PSObject -Property $hash  
        $userList += $Object
    }
    $body = @{
        "data" = @{
            "type" = "notification-configurations"
            "attributes" = @{
                "name" = $name
                "destination-type" = "email"
                "enabled" = $true
                "triggers" = $triggers
            }
            "relationships" = @{
                "users" = @{
                    "data" = $userList
                    }
            }
        }
    }
    #set the depth lower if necessary
    $json_body = convertto-json $body -Depth 5
    foreach ($workspace in $workspaces){
        $workspaceId = $workspace.id
        $endpoint = "/workspaces/$workspaceId/notification-configurations"
        $response = tf-custom-invoke -endpoint $endpoint -body $json_body  -Method Post
        write-host $json_body
        write-host $response.data.id
    }
}
