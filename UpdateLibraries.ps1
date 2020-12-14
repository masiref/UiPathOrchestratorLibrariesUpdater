<#
.DESCRIPTION
    This script is intented to get newer version of libraries in orchestrator
    It should be scheduled in order to regularly check if newer version of existing libraries are available in configured NuGet feeds
.NOTES
    Script created on 2020/12 by Masire FOFANA (masire.fofana@natixis.com)
#>

$Config = Get-Content -Raw -Path config.json | ConvertFrom-Json

$ExportedCSVFilesFolder = '.\csv'
$LogsFolder = '.\logs'
$DownloadedPackagesFolder = '.\packages'

. .\Function-Write-Log.ps1

# creating logs folder if not exists
New-Item -ItemType Directory -Force -Path $LogsFolder | Out-Null

# creating csv files folder if not exists
New-Item -ItemType Directory -Force -Path $ExportedCSVFilesFolder | Out-Null

# creating downloaded packages folder if not exists
New-Item -ItemType Directory -Force -Path $DownloadedPackagesFolder | Out-Null

# generating log & csv file names
$FormattedDate = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = "$LogsFolder\$FormattedDate.log"
$CSVFile = "$ExportedCSVFilesFolder\$FormattedDate.csv"

# creating header in csv file
"Library,Version" | Add-Content -Path $CSVFile

# UiPath API request global variables definition
$UiPathAPIRequestGlobalVariables = @{
    'Headers' = @{
        'Accept' = 'application/json'
    }
    'EndPoints' = @{
        'Authentication' = 'api/Account/Authenticate'
        'GetLibraries' = 'odata/Libraries'
        'GetLibraryVersions' = "odata/Libraries/UiPath.Server.Configuration.OData.GetVersions(packageId='{0}')"
        'UploadLibrary' = 'odata/Libraries/UiPath.Server.Configuration.OData.UploadPackage'
    }
}

# UiPath authentication model
$LoginModel = @{
    'tenancyName' = $Config.ReferenceOrchestrator.Tenant
    'usernameOrEmailAddress' = $Config.ReferenceOrchestrator.Username
    'password' = $Config.ReferenceOrchestrator.Password
}

# base URI construction
$BaseURI = $Config.ReferenceOrchestrator.URL
If (-Not $BaseURI.EndsWith('/')) {
	$BaseURI = $BaseURI + '/';
}

# authenticate to reference orchestrator
Try {
    # building URI
    $URI = $BaseURI + $UiPathAPIRequestGlobalVariables.EndPoints.Authentication

    Write-Log -Message "Authenticating to reference orchestrator" -Path $LogFile -Level Info

    $Headers = $UiPathAPIRequestGlobalVariables.Headers.Clone()
	$Response = Invoke-RestMethod -Method Post -Uri $URI -Headers $Headers -Body $LoginModel

    Write-Log -Message "Successfully authenticated to $URI on tenant $($Config.ReferenceOrchestrator.Tenant) with user $($Config.ReferenceOrchestrator.Username)" -Path $LogFile -Level Info

} Catch {
    $ErrorMessage = "Unable to communicate with $URI => $_"
    Write-Log -Message $ErrorMessage -Path $LogFile -Level Error
	Throw $ErrorMessage
}

# retrieve all deployed libraries & versions from reference orchestrator in a CSV file
If ($Response.Success) {
    # adding token to headers for further requests
    $Headers.Add('Authorization', "Bearer $($Response.result)")
    
    Try {
        # building URI
        $URI = $BaseURI + $UiPathAPIRequestGlobalVariables.EndPoints.GetLibraries

        # retrieve all deployed libraries
        $Response = Invoke-RestMethod -Method Get -Uri $URI -Headers $Headers
        $Libraries = $Response.value
        $LibrariesCount = $Libraries.Count

        Write-Log -Message "Successfully retrieved $LibrariesCount library(ies)" -Path $LogFile -Level Info

        # retrieve all deployed versions of libraries & write in CSV file
        $CurrentLibraryIndex = 1
        Foreach ($Library in $Libraries) {
            # building URI
            $URI = $BaseURI + ($UiPathAPIRequestGlobalVariables.EndPoints.GetLibraryVersions -f $Library.Id)

            # retrieve all deployed versions
            $Response = Invoke-RestMethod -Method Get -Uri $URI -Headers $Headers

            # write all versions in CSV file
            Foreach ($Version in $Response.value) {
                "$($Library.Id),$($Version.Version)" | Add-Content -Path $CSVFile
            }

            Write-Log -Message "$CurrentLibraryIndex / $LibrariesCount - Successfully retrieved $($Response.value.Count) version(s) for library $($Library.Id)" -Path $LogFile -Level Info
            $CurrentLibraryIndex++

        }
    } Catch {
        $ErrorMessage = "Unable to retrieve all deployed libraries & versions => $_"
        Write-Log -Message $ErrorMessage -Path $LogFile -Level Error
	    Throw $ErrorMessage
    }

    # get distinct list of libraries from CSV file
    $DistinctLibraries = Import-Csv -Path $CSVFile | Select Library -Unique
    $DistinctLibrariesCount = $DistinctLibraries.Count

    Write-Log -Message "Starting download of $DistinctLibrariesCount library(ies)" -Path $LogFile -Level Info

    # download all versions of libraries from defined nuget feeds
    $DistinctLibraryIndex = 1
    Foreach ($DistinctLibrary in $DistinctLibraries) {
        # building nuget.exe search expression
        $Search = "packageId:$($DistinctLibrary.Library)"

        Write-Log -Message "$DistinctLibraryIndex / $DistinctLibrariesCount - Downloading $($DistinctLibrary.Library) library" -Path $LogFile -Level Info

        # loop through NuGet feeds
        Foreach ($NuGetFeed in $Config.NuGetFeeds) {
            $NuGetFeedName = $NuGetFeed.Name
            $NuGetFeedLocation = $NuGetFeed.Location

            Write-Log -Message "Trying to download from [$NuGetFeedName] NuGet feed" -Path $LogFile -Level Info

            # search libraries with nuget.exe
            $LibraryVersions = .\nuget.exe list $Search -AllVersions -Source $NuGetFeedLocation
            
            # if current NuGet feed gives results, try to download newer versions
            If ($LibraryVersions -is [array] -or ($LibraryVersions -is [string] -and $LibraryVersions.StartsWith($DistinctLibrary.Library))) {
            
                $HigherAlreadyDeployedVersion = (Import-Csv -Path $CSVFile | Where-Object { $_.Library -eq $DistinctLibrary.Library } | Sort-Object -Property Version -Descending | Select -First 1).Version

                Write-Log -Message "Downloading versions higher than $HigherAlreadyDeployedVersion" -Path $LogFile -Level Info

                Foreach ($LibraryVersion in $LibraryVersions) {
                    $Library = $LibraryVersion.Split(' ').Item(0)
                    $Version = $LibraryVersion.Split(' ').Item(1)

                    # download version if greater than higher version already deployed in reference orchestrator
                    If ([System.Version]$Version -gt [System.Version]$HigherAlreadyDeployedVersion) {
                        Try {
                            .\nuget.exe install $Library -Version $Version -OutputDirectory $DownloadedPackagesFolder -Source $NuGetFeedLocation -PackageSaveMode nupkg | Out-Null

                            Write-Log -Message "Version $Version successfully downloaded" -Path $LogFile -Level Info

                        } Catch {
                            Write-Log -Message "Error while downloading version $Version => $_" -Path $LogFile -Level Error
                        }
                    }
                }

                # download next library versions => exit NuGetFeeds loop
                Break
            } Else {
                Write-Log -Message 'Library not found' -Path $LogFile -Level Warn
            }
        }

        $DistinctLibraryIndex++
    }

    # upload downloaded libraries to target orchestrators
    Foreach ($TargetOrchestrator in $Config.TargetOrchestrators) {
        # UiPath authentication model
        $LoginModel = @{
            'tenancyName' = $TargetOrchestrator.Tenant
            'usernameOrEmailAddress' = $TargetOrchestrator.Username
            'password' = $TargetOrchestrator.Password
        }

        # base URI construction
        $BaseURI = $TargetOrchestrator.URL
        If (-Not $BaseURI.EndsWith('/')) {
	        $BaseURI = $BaseURI + '/';
        }

        # authenticate to target orchestrator
        Try {
            # building URI
            $URI = $BaseURI + $UiPathAPIRequestGlobalVariables.EndPoints.Authentication

            Write-Log -Message "Authenticating to $BaseURI orchestrator" -Path $LogFile -Level Info
            
            $Headers = $UiPathAPIRequestGlobalVariables.Headers.Clone()
	        $Response = Invoke-RestMethod -Method Post -Uri $URI -Headers $Headers -Body $LoginModel

            Write-Log -Message "Successfully authenticated to $URI on tenant $($TargetOrchestrator.Tenant) with user $($TargetOrchestrator.Username)" -Path $LogFile -Level Info

        } Catch {
            $ErrorMessage = "Unable to communicate with $URI => $_"
            Write-Log -Message $ErrorMessage -Path $LogFile -Level Error
        }

        # upload downloaded libraries
        If ($Response.Success) {
            # adding token to headers for further requests
            $Headers.Add('Authorization', "Bearer $($Response.result)")

            # adding content type key with empty value
            $Headers.Add('Content-Type', '')

            Get-ChildItem -Path .\packages -Filter *.nupkg -Recurse | % {
                $Library = [System.IO.Path]::GetFileNameWithoutExtension($_)
                $LibraryLocation = $_.FullName

                $FileBytes = [System.IO.File]::ReadAllBytes($LibraryLocation);
                $FileEnc = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($FileBytes);
                $Boundary = [System.Guid]::NewGuid().ToString(); 
                $LF = "`r`n";

                $BodyLines = ( 
                    "--$Boundary",
                    "Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $LibraryLocation -Leaf)`"",
                    "Content-Type: application/octet-stream$LF",
                    $FileEnc,
                    "--$Boundary--$LF" 
                ) -join $LF
                
                $Headers['Content-Type'] = "multipart/form-data; boundary=`"$Boundary`""

                $URI = $BaseURI + $UiPathAPIRequestGlobalVariables.EndPoints.UploadLibrary

                Try {
                    $Response = Invoke-RestMethod -Method Post -Uri $URI -Headers $Headers -Body $BodyLines

                    Write-Log -Message "$Library uploaded successfully" -Path $LogFile -Level Info
                } Catch {
                    Try {
                        $RaisedError = $_
                        $ErrorDetails = $RaisedError.ErrorDetails.Message | ConvertFrom-Json
                        If ($ErrorDetails.message -ne 'Package already exists.') {
                            Write-Log -Message "Unable to upload library $Library => $RaisedError" -Path $LogFile -Level Error
                        } Else {
                            Write-Log -Message "Library $Library already exists" -Path $LogFile -Level Warn
                        }
                    } Catch {
                        Write-Log -Message "Unable to upload library $Library => $RaisedError" -Path $LogFile -Level Error
                    }
                }
            }
        }
    }

} Else {
    $ErrorMessage = "Unable to authenticate to $URI on tenant $($Config.ReferenceOrchestrator.Tenant) with user $($Config.ReferenceOrchestrator.Username) => $($Response.result)"
    Write-Log -Message $ErrorMessage -Path $LogFile -Level Error
	Throw $ErrorMessage
}
