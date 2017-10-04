#Requires -Version 3.0
#Requires -Module PowerNSX

<#
    Script gets NSX Load Balancer information and exports them to an excel file
#>
param (

    [pscustomobject]$Connection=$DefaultNsxConnection
)

If ( (-not $Connection) -and ( -not $Connection.ViConnection.IsConnected ) ) 
{
    throw "No valid NSX Connection found. Connect to NSX and vCenter using 
           Connect-NsxServer first. You can specify a non default PowerNSX
           Connection using the -connection parameter."
}

##################################################
#           Start execution of report            #
##################################################

$edges_lb = @{} # Empty HT for ESG Name, and XML Element Data

$edges = get-nsxedge # Store all ESGs for looping over

foreach($item in $edges)
{
    # Pop HT with ESG's enabled for LB
    $esg = get-nsxloadbalancer $item
    if($esg.enabled -eq $true)
    {
        $edges_lb.Add($item.name, $esg)
    }
}

function get_lb()
{  
    param (
        $edge_lb
    )
    # Create custom object with only required fields
    [pscustomobject]@{
        "EdgeID" = (get-nsxloadbalancervip $edge_lb.value).edgeID
        "EdgeName" = $edge_lb.Key
        "VirtualServerName" = (get-nsxloadbalancervip $edge_lb.value).name
        "VIP" = (get-nsxloadbalancervip $edge_lb.value).ipAddress
        "Protocol" = (get-nsxloadbalancervip $edge_lb.value).protocol
        "Port" = (get-nsxloadbalancervip $edge_lb.value).port
        "L7Engine" = (get-nsxloadbalancervip $edge_lb.value).accelerationEnabled   
        "PoolID" = (get-nsxloadbalancervip $edge_lb.value).defaultPoolId
    }
}

function get_pool_stats()
{
    param (
        $edge_lb,
        $lb
    )
    # Get Pool stats and membership, append to custom object created earlier
    foreach ($item in (Get-NsxLoadBalancerStats $edge_lb.value).pool)
    {
        if ($lb.PoolID -eq $item.poolId)
        {
            $lb | Add-Member -MemberType NoteProperty -Name 'PoolStatus' -Value $item.status
            $lb | Add-Member -MemberType NoteProperty -Name 'bytesIn' -Value $item.bytesIn
            $lb | Add-Member -MemberType NoteProperty -Name 'bytesOut' -Value $item.bytesOut
            $lb | Add-Member -MemberType NoteProperty -Name 'totalSessions' -Value $item.totalSessions

            $pool_members = @() # Create empty array to store member data
            
            foreach ($member in $item.member)
            {
                $members = [pscustomobject]@{}
                $members | Add-Member -MemberType NoteProperty -Name 'Name' -Value $member.name
                $members | Add-Member -MemberType NoteProperty -Name 'Status' -Value $member.status
                $members | Add-Member -MemberType NoteProperty -Name 'FailureCause' -Value $member.FailureCause
                $members | Add-Member -MemberType NoteProperty -Name 'lastStateChange' -Value $member.lastStateChangeTime
                $members | Add-Member -MemberType NoteProperty -Name 'IPAddress' -Value $member.ipAddress
                $pool_members +=, $members
            }
            $lb | Add-Member -MemberType NoteProperty -Name 'members' -Value $pool_members            
            return $lb
            }
    }
}

function pop_esg_lb_config()
{
    $esg_lb_config = @() # Create an array to store custom objects
    foreach ($item in $edges_lb.GetEnumerator()){
        $lb = get_lb -edge_lb $item
        $lb = get_pool_stats -edge_lb $item -lb $lb
        $esg_lb_config +=, $lb 
    }
    return $esg_lb_config
}

## Display Info on the console
(pop_esg_lb_config) | ft -AutoSize *