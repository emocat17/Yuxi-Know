param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "deploy.config.json"),
    [string[]]$ComposeArgs = @(),
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

$outputDir = $config.output_dir
if (-not [System.IO.Path]::IsPathRooted($outputDir)) {
    $outputDir = Join-Path $repoRoot $outputDir
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

$imageFiles = @()
foreach ($item in $config.images) {
    if (-not [string]::IsNullOrWhiteSpace($item.file)) {
        $resolved = $item.file.Replace("{project}", $projectName).Replace("{date}", (Get-Date -Format "yyyyMMdd"))
        $imageFiles += (Join-Path $outputDir $resolved)
    }
}

foreach ($tarPath in $imageFiles) {
    if ($DryRun) {
        Invoke-Docker -dockerArgs @("load", "-i", $tarPath)
        continue
    }
    if (!(Test-Path $tarPath)) {
        throw "image tar not found: $tarPath"
    }
    Invoke-Docker -dockerArgs @("load", "-i", $tarPath)
}

$composeFile = $config.compose_file
if (-not [System.IO.Path]::IsPathRooted($composeFile)) {
    $composeFile = Join-Path $repoRoot $composeFile
}

$overridePath = Join-Path $scriptDir "compose.override.generated.yml"
$containerPrefix = $config.container_name_prefix
$services = $config.services

$lines = @("services:")
foreach ($svc in $services) {
    $lines += ("  {0}:" -f $svc)
    $lines += ("    container_name: {0}-{1}" -f $containerPrefix, $svc)
}
Set-Content -Path $overridePath -Value $lines -Encoding UTF8

if ($config.deploy_mode -eq "stack") {
    $stackName = $config.stack_name
    $args = @("stack", "deploy", "-c", $composeFile, "-c", $overridePath, $stackName)
    Invoke-Docker -dockerArgs $args
} else {
    $args = @("compose", "-f", $composeFile, "-f", $overridePath)
    foreach ($profile in $config.compose_profiles) {
        $args += @("--profile", $profile)
    }
    if (-not [string]::IsNullOrWhiteSpace($config.compose_project_name)) {
        $args += @("-p", $config.compose_project_name)
    }
    if ($ComposeArgs.Count -eq 0) {
        $args += @("up", "-d")
    } else {
        $args += $ComposeArgs
    }
    Invoke-Docker -dockerArgs $args
}
