param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "deploy.config.json"),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

function New-DefaultConfig {
    param([string]$path)
    $projectName = Split-Path -Leaf $repoRoot
    $defaultConfig = @{
        project_name = $projectName
        output_dir = (Join-Path $repoRoot "deploy\images")
        compose_file = "docker-compose.prod.yml"
        compose_profiles = @()
        compose_project_name = $projectName.ToLower()
        container_name_prefix = $projectName.ToLower()
        stack_name = $projectName.ToLower()
        deploy_mode = "compose"
        build_before_save = $true
        pull_missing_images = $true
        services = @(
            "api",
            "web",
            "graph",
            "etcd",
            "minio",
            "milvus",
            "postgres",
            "mineru-vllm-server",
            "mineru-api",
            "paddlex"
        )
        images = @(
            @{ image = "yuxi-api:0.5.prod"; file = "{project}-api-{date}.tar" },
            @{ image = "yuxi-web:0.5.prod"; file = "{project}-web-{date}.tar" },
            @{ image = "neo4j:5.26"; file = "neo4j-5.26.tar" },
            @{ image = "quay.io/coreos/etcd:v3.5.5"; file = "etcd-v3.5.5.tar" },
            @{ image = "minio/minio:RELEASE.2023-03-20T20-16-18Z"; file = "minio-2023-03-20.tar" },
            @{ image = "milvusdb/milvus:v2.5.6"; file = "milvus-v2.5.6.tar" },
            @{ image = "postgres:16"; file = "postgres-16.tar" },
            @{ image = "mineru-vllm:latest"; file = "{project}-mineru-vllm.tar" },
            @{ image = "paddlex:latest"; file = "{project}-paddlex.tar" }
        )
    }
    $json = $defaultConfig | ConvertTo-Json -Depth 6
    Set-Content -Path $path -Value $json -Encoding UTF8
}

if (!(Test-Path $ConfigPath)) {
    New-Item -ItemType Directory -Path $scriptDir | Out-Null
    New-DefaultConfig -path $ConfigPath
}

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$projectName = $config.project_name
$dateTag = Get-Date -Format "yyyyMMdd"

$outputDir = $config.output_dir
if (-not [System.IO.Path]::IsPathRooted($outputDir)) {
    $outputDir = Join-Path $repoRoot $outputDir
}
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

function Invoke-Docker {
    param([string[]]$dockerArgs)
    if ($DryRun) {
        Write-Host ("docker " + ($dockerArgs -join " "))
        return
    }
    & docker @dockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker command failed: docker $($dockerArgs -join ' ')"
    }
}

if ($config.build_before_save) {
    $composeFile = $config.compose_file
    if (-not [System.IO.Path]::IsPathRooted($composeFile)) {
        $composeFile = Join-Path $repoRoot $composeFile
    }
    $args = @("compose", "-f", $composeFile)
    foreach ($profile in $config.compose_profiles) {
        $args += @("--profile", $profile)
    }
    $args += "build"
    Invoke-Docker -dockerArgs $args
}

foreach ($item in $config.images) {
    $imageName = $item.image
    $fileName = $item.file
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $safeName = $imageName -replace "[^a-zA-Z0-9_.-]", "_"
        $fileName = "$projectName-$safeName-$dateTag.tar"
    }
    $fileName = $fileName.Replace("{project}", $projectName).Replace("{date}", $dateTag)
    $filePath = Join-Path $outputDir $fileName

    $imageExists = $true
    if (-not $DryRun) {
        docker image inspect $imageName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $imageExists = $false
        }
    }

    if (-not $imageExists -and $config.pull_missing_images) {
        Invoke-Docker -dockerArgs @("pull", $imageName)
    }

    Invoke-Docker -dockerArgs @("save", $imageName, "-o", $filePath)
}
