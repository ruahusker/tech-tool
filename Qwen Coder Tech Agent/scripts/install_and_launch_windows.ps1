$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$RealUserProfile = $env:USERPROFILE
$InstallDir = Join-Path $env:USERPROFILE ".tech-utility\qwen-coder-tech-agent"
$LegacyInstallDir = Join-Path $env:USERPROFILE ".tech-utility\qwen-coder-codex"
$QwenCodeDir = Join-Path $InstallDir "qwen-code"
$QwenHomeDir = Join-Path $InstallDir "qwen-home"
$QwenRuntimeDir = Join-Path $InstallDir "qwen-runtime"
$LlamaDir = Join-Path $InstallDir "llama.cpp"
$ModelDir = Join-Path $InstallDir "models"
$TemplateDir = Join-Path $InstallDir "templates"
$LogDir = Join-Path $InstallDir "logs"
$RunDir = Join-Path $InstallDir "run"
$WorkRoot = Join-Path $InstallDir "workspace"
$UsbLogDir = Join-Path $RootDir "logs"
$ChatTemplateFile = "Qwen3-4B-Instruct-2507.jinja"
$ChatTemplateSource = Join-Path $RootDir "assets\templates\$ChatTemplateFile"
$ChatTemplateTarget = Join-Path $TemplateDir $ChatTemplateFile
$TechKitDir = Join-Path (Split-Path -Parent $RootDir) "TechKit"
$DraftModelFile = "qwen3-0.6b-q8_0.gguf"
$DraftModelSource = Join-Path $RootDir "models\$DraftModelFile"
$DraftModelTarget = $null
$ServerUrl = "http://127.0.0.1:1234/v1"
$LocalApiKey = "local"
$ApprovalMode = if ($env:QWEN_APPROVAL_MODE) { $env:QWEN_APPROVAL_MODE } else { "auto-edit" }
$DefaultSystemPrompt = "You are a local computer technician agent running inside Qwen Code on a customer machine. Tools: run_shell_command, read_file, edit. PRIME RULE: for diagnostics and repairs, prefer running the vetted TechKit scripts listed in QWEN.md over writing new code. Match the user's complaint to a script, run it with run_shell_command, then interpret the output: lead with any [!] findings, then a short diagnosis and the single next step. Act immediately with a tool call; never reply with a prose plan, and do not say you will run something unless you call the tool now. Keep replies under 150 words: exact counts, paths, and errors only; never restate full tool output the user already saw. Destructive TechKit scripts dry-run by default: run the dry-run first, show what would change, get explicit user confirmation, then re-run with the force flag. Never disable or delete administrator accounts; the scripts refuse this and you must not work around them. If no TechKit script fits the task, write a custom script to a file with the edit tool and reply with one sentence plus the file path; never paste a full script into chat. Use PowerShell on Windows and absolute paths. If an action needs admin and the shell is not elevated, say so and give the exact elevated command instead of pretending it ran. When a job wraps up, offer a short ticket summary (problem, findings, actions, result)."
$SystemPrompt = if ($env:QWEN_SYSTEM_PROMPT) { $env:QWEN_SYSTEM_PROMPT } else { $DefaultSystemPrompt }
$RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SafeHostName = ($env:COMPUTERNAME -replace "[^A-Za-z0-9_.-]", "_")
$RunLog = Join-Path $UsbLogDir "$SafeHostName-windows-$RunStamp.log"
$RequestedLlamaBackend = if ($env:QWEN_LLAMA_BACKEND) { $env:QWEN_LLAMA_BACKEND.ToLowerInvariant() } else { "cpu" }
$LlamaBackend = "cpu"
$CpuLlamaAsset = $null

function Log($Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $RunLog -Value $line
}

function Copy-ServerLogsToUsb {
    param([string]$Label = "")

    $outLog = Join-Path $LogDir "llama-server.out.log"
    $errLog = Join-Path $LogDir "llama-server.err.log"
    $openAiDir = Join-Path $LogDir "openai"
    $labelPart = if ($Label) { "-$Label" } else { "" }
    $outCopy = Join-Path $UsbLogDir "$SafeHostName-windows-llama-server$labelPart-out-$RunStamp.log"
    $errCopy = Join-Path $UsbLogDir "$SafeHostName-windows-llama-server$labelPart-err-$RunStamp.log"
    $openAiCopy = Join-Path $UsbLogDir "$SafeHostName-windows-openai$labelPart-$RunStamp"
    if (Test-Path -LiteralPath $outLog) {
        Copy-Item -LiteralPath $outLog -Destination $outCopy -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $errLog) {
        Copy-Item -LiteralPath $errLog -Destination $errCopy -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $openAiDir) {
        Remove-Item -LiteralPath $openAiCopy -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $openAiCopy -ErrorAction SilentlyContinue | Out-Null
        Copy-Item -Path (Join-Path $openAiDir "*") -Destination $openAiCopy -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Fail($Message) {
    Copy-ServerLogsToUsb
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Write-Host "Log: $RunLog"
    Write-Host "Press Enter to close this window."
    [void][Console]::ReadLine()
    exit 1
}

function Copy-IfNeeded($Source, $Target) {
    if (!(Test-Path -LiteralPath $Source)) {
        Fail "Missing required file: $Source"
    }

    $copy = $true
    if (Test-Path -LiteralPath $Target) {
        $sourceSize = (Get-Item -LiteralPath $Source).Length
        $targetSize = (Get-Item -LiteralPath $Target).Length
        $copy = $sourceSize -ne $targetSize
    }

    if ($copy) {
        Log "Copying $(Split-Path -Leaf $Source) to $Target"
        Copy-Item -LiteralPath $Source -Destination $Target -Force
    } else {
        Log "Using existing $(Split-Path -Leaf $Target)"
    }
}

function Find-Archive($Pattern, $Family) {
    $assetDir = Join-Path $RootDir "assets\$Family"
    $archive = Get-ChildItem -LiteralPath $assetDir -File -Filter $Pattern | Select-Object -First 1
    if (!$archive) {
        Fail "Missing $Family archive matching $Pattern in $assetDir"
    }
    return $archive.FullName
}

function Find-OptionalArchive($Pattern, $Family) {
    $assetDir = Join-Path $RootDir "assets\$Family"
    $archive = Get-ChildItem -LiteralPath $assetDir -File -Filter $Pattern | Select-Object -First 1
    if (!$archive) {
        return $null
    }
    return $archive.FullName
}

function Validate-ApprovalMode {
    if ($ApprovalMode -notin @("plan", "default", "auto-edit", "auto", "yolo")) {
        Fail "Unsupported QWEN_APPROVAL_MODE value: $ApprovalMode. Use plan, default, auto-edit, auto, or yolo."
    }
}

function Select-Model {
    $requested = if ($env:QWEN_MODEL_SIZE) { $env:QWEN_MODEL_SIZE.ToLowerInvariant() } else { "auto" }
    if ($requested -in @("3b", "7b")) {
        Log "QWEN_MODEL_SIZE=$requested is from the legacy build; selecting Qwen3 4B instead."
    } elseif ($requested -notin @("auto", "4b", "qwen3", "qwen3-4b", "qwen3-4b-instruct-2507")) {
        Fail "Unsupported QWEN_MODEL_SIZE value: $requested. Use auto or 4b."
    }

    $script:ModelFile = "qwen3-4b-instruct-2507-q4_k_m.gguf"
    $script:ModelId = "local/qwen3-4b-instruct-2507-q4_k_m"
    $script:ModelDisplayName = "Qwen3-4B Instruct 2507 Q4_K_M"
    $defaultContext = 32768
    $defaultOutput = 4096

    $script:ContextSize = if ($env:QWEN_CONTEXT_SIZE) { [int]$env:QWEN_CONTEXT_SIZE } else { $defaultContext }
    $script:OutputTokens = if ($env:QWEN_MAX_OUTPUT_TOKENS) { [int]$env:QWEN_MAX_OUTPUT_TOKENS } else { $defaultOutput }
    $script:ModelSource = Join-Path $RootDir ("models\" + $script:ModelFile)
    $script:ModelTarget = Join-Path $ModelDir $script:ModelFile

    Log "Selected model: $($script:ModelDisplayName)"
    Log "Model file: $($script:ModelFile)"
    Log "Context size: $($script:ContextSize) tokens"
    Log "Max output tokens: $($script:OutputTokens)"
}

function Test-WindowsVulkanRuntime {
    $runtimePaths = @()
    if ($env:WINDIR) {
        $runtimePaths += (Join-Path $env:WINDIR "System32\vulkan-1.dll")
        $runtimePaths += (Join-Path $env:WINDIR "SysWOW64\vulkan-1.dll")
    }

    foreach ($runtimePath in $runtimePaths) {
        if (Test-Path -LiteralPath $runtimePath) {
            Log "Detected Vulkan runtime loader: $runtimePath"
            return $true
        }
    }

    $vulkanInfo = Get-Command "vulkaninfo.exe" -ErrorAction SilentlyContinue
    if ($vulkanInfo) {
        Log "Detected vulkaninfo.exe: $($vulkanInfo.Source)"
        return $true
    }

    return $false
}

function Expand-QwenCode($Archive) {
    if (Test-Path -LiteralPath (Join-Path $QwenCodeDir "bin\qwen.cmd")) {
        Log "Using existing Qwen Code install: $QwenCodeDir"
        return
    }

    $tempDir = Join-Path $InstallDir "tmp\qwen-code"
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $QwenCodeDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempDir, $QwenCodeDir | Out-Null

    Log "Extracting Qwen Code from $(Split-Path -Leaf $Archive)"
    Expand-Archive -LiteralPath $Archive -DestinationPath $tempDir -Force
    $qwenCmd = Get-ChildItem -LiteralPath $tempDir -Recurse -File -Filter "qwen.cmd" | Select-Object -First 1
    if (!$qwenCmd) {
        Fail "Could not find qwen.cmd inside $Archive"
    }

    $packageDir = Split-Path -Parent (Split-Path -Parent $qwenCmd.FullName)
    Copy-Item -Path (Join-Path $packageDir "*") -Destination $QwenCodeDir -Recurse -Force
}

function Expand-Llama($Archive) {
    $tempDir = Join-Path $InstallDir "tmp\llama"
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $LlamaDir) {
        Get-ChildItem -LiteralPath $LlamaDir -Force | Remove-Item -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $tempDir, $LlamaDir | Out-Null

    Log "Extracting llama.cpp from $(Split-Path -Leaf $Archive)"
    Expand-Archive -LiteralPath $Archive -DestinationPath $tempDir -Force
    $binary = Get-ChildItem -LiteralPath $tempDir -Recurse -File -Filter "llama-server.exe" | Select-Object -First 1
    if (!$binary) {
        Fail "Could not find llama-server.exe inside $Archive"
    }

    Copy-Item -Path (Join-Path (Split-Path -Parent $binary.FullName) "*") -Destination $LlamaDir -Recurse -Force
}

function Server-IsReady {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/models" -UseBasicParsing -TimeoutSec 2
        return $response.Content -like "*$($script:ModelId)*"
    } catch {
        return $false
    }
}

function Port-Responds {
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/models" -UseBasicParsing -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Cleanup-LegacyInstall {
    if (!(Test-Path -LiteralPath $LegacyInstallDir)) {
        return
    }

    Log "Removing previous Codex-based Qwen Coder install: $LegacyInstallDir"
    $legacyPidFile = Join-Path $LegacyInstallDir "run\llama-server.pid"
    if (Test-Path -LiteralPath $legacyPidFile) {
        $oldPid = Get-Content -LiteralPath $legacyPidFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($oldPid) {
            Stop-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }

    Get-CimInstance Win32_Process -Filter "name = 'llama-server.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -like "$LegacyInstallDir*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }

    Remove-Item -LiteralPath $LegacyInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Start-LocalServer {
    param([switch]$AllowStartupFailure)

    $pidFile = Join-Path $RunDir "llama-server.pid"
    if (Test-Path -LiteralPath $pidFile) {
        $oldPid = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($oldPid) {
            Log "Stopping previous toolkit llama-server process $oldPid"
            Stop-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }

    if (Port-Responds) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/models" -UseBasicParsing -TimeoutSec 2
            Add-Content -LiteralPath $RunLog -Value $response.Content
        } catch {}
        Fail "Port 1234 is already serving a model from another process. Stop that server and run this launcher again."
    }

    $server = Join-Path $LlamaDir "llama-server.exe"
    $outLog = Join-Path $LogDir "llama-server.out.log"
    $errLog = Join-Path $LogDir "llama-server.err.log"
    $quotedModel = '"' + $script:ModelTarget + '"'
    $quotedModelId = '"' + $script:ModelId + '"'
    $quotedTemplate = '"' + $ChatTemplateTarget + '"'
    $args = "-m $quotedModel --host 127.0.0.1 --port 1234 --alias $quotedModelId -c $($script:ContextSize) --parallel 1 --jinja --chat-template-file $quotedTemplate --reasoning off --cache-reuse 256"
    if ($LlamaBackend -eq "vulkan") {
        $args = "$args -ngl 999 -fa off"
    } else {
        # CPU: flash attention + q8_0 KV cache roughly halves KV memory at 32K context
        # (the difference between fitting in RAM and swapping on 8 GB machines), and
        # physical-core thread count beats logical (hyperthreads hurt GEMM throughput).
        $physicalCores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
        if ($physicalCores -ge 2) {
            $args = "$args -t $physicalCores"
            Log "llama-server threads: $physicalCores physical cores"
        }
        $args = "$args -fa on --cache-type-k q8_0 --cache-type-v q8_0"
    }
    # Speculative decoding: benchmarked SLOWER than plain decoding for this model pairing
    # (draft-simple 0.76x, ngram-simple 0.44x on repetition) - off by default.
    # QWEN_SPEC=draft|ngram-simple|... re-enables it for experiments.
    $specMode = if ($env:QWEN_SPEC) { $env:QWEN_SPEC.ToLowerInvariant() } else { "off" }
    if ($specMode -in @("off", "none", "0")) {
        Log "Speculative decoding: off"
    } elseif ($specMode -eq "draft") {
        if ($script:DraftModelTarget -and (Test-Path -LiteralPath $script:DraftModelTarget)) {
            $quotedDraft = '"' + $script:DraftModelTarget + '"'
            $args = "$args --spec-type draft-simple --model-draft $quotedDraft --spec-draft-n-max 8 --spec-draft-n-min 2 --spec-draft-p-min 0.75 -ctkd q8_0 -ctvd q8_0"
            if ($LlamaBackend -eq "vulkan") { $args = "$args -ngld 999" }
            Log "Speculative decoding: draft-simple with $DraftModelFile (experimental)"
        } else {
            Log "QWEN_SPEC=draft but $DraftModelFile missing; speculative decoding off"
        }
    } else {
        $args = "$args --spec-type $specMode"
        Log "Speculative decoding: $specMode (experimental)"
    }

    Log "Starting llama-server on 127.0.0.1:1234"
    Log "llama-server backend: $LlamaBackend"
    Log "Chat template: $ChatTemplateTarget"
    Log "Server stdout log: $outLog"
    Log "Server stderr log: $errLog"
    try {
        $proc = Start-Process -FilePath $server -ArgumentList $args -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru -WindowStyle Minimized
    } catch {
        if ($AllowStartupFailure) {
            Log "llama-server failed to start with backend $LlamaBackend`: $($_.Exception.Message)"
            Copy-ServerLogsToUsb -Label "$LlamaBackend-failed"
            return $false
        }
        Fail "llama-server failed to start: $($_.Exception.Message)"
    }
    Set-Content -LiteralPath $pidFile -Value $proc.Id

    for ($i = 0; $i -lt 60; $i++) {
        if (Server-IsReady) {
            Log "llama-server is ready"
            try {
                $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/models" -UseBasicParsing -TimeoutSec 2
                Add-Content -LiteralPath $RunLog -Value $response.Content
            } catch {}
            return $true
        }

        $proc.Refresh()
        if ($proc.HasExited) {
            Log "llama-server process exited before readiness with status $($proc.ExitCode)"
            break
        }
        Start-Sleep -Seconds 1
    }

    if ($AllowStartupFailure) {
        if ($proc -and !$proc.HasExited) {
            Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        Copy-ServerLogsToUsb -Label "$LlamaBackend-failed"
        Log "llama-server did not become ready with backend $LlamaBackend"
        return $false
    }

    Fail "llama-server did not become ready. See $outLog and $errLog"
}

function Write-QwenWorkspaceConfig {
    New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot ".qwen"), $QwenHomeDir, $QwenRuntimeDir, (Join-Path $LogDir "openai") | Out-Null

    $includeDirs = @($RealUserProfile)
    if (Test-Path -LiteralPath "C:\") { $includeDirs += "C:\" }
    $usbRoot = (Split-Path -Path $RootDir -Qualifier) + "\"
    if ($usbRoot -ne "C:\") { $includeDirs += $usbRoot }

    $settings = [ordered]@{
        modelProviders = [ordered]@{
            openai = @(
                [ordered]@{
                    id = $script:ModelId
                    name = $script:ModelDisplayName
                    description = "Local llama.cpp server started by Qwen Coder Tech Agent"
                    envKey = "OPENAI_API_KEY"
                    baseUrl = $ServerUrl
                    generationConfig = [ordered]@{
                        timeout = 600000
                        maxRetries = 0
                        contextWindowSize = $script:ContextSize
                        splitToolMedia = $true
                        samplingParams = [ordered]@{
                            temperature = 0.2
                            top_p = 0.9
                            max_tokens = $script:OutputTokens
                        }
                    }
                }
            )
        }
        env = [ordered]@{
            OPENAI_API_KEY = $LocalApiKey
            OPENAI_BASE_URL = $ServerUrl
            OPENAI_MODEL = $script:ModelId
        }
        security = [ordered]@{
            auth = [ordered]@{
                selectedType = "openai"
            }
        }
        model = [ordered]@{
            name = $script:ModelId
            skipStartupContext = $true
            enableOpenAILogging = $true
            openAILoggingDir = (Join-Path $LogDir "openai")
        }
        tools = [ordered]@{
            approvalMode = $ApprovalMode
            sandbox = $false
            useRipgrep = $true
            truncateToolOutputThreshold = 50000
            truncateToolOutputLines = 2000
        }
        permissions = [ordered]@{
            allow = @("Read", "Edit", "Write", "Grep", "Glob", "ListFiles")
        }
        context = [ordered]@{
            includeDirectories = $includeDirs
            loadFromIncludeDirectories = $false
            fileFiltering = [ordered]@{
                respectGitIgnore = $true
                respectQwenIgnore = $true
                enableFuzzySearch = $false
            }
        }
        general = [ordered]@{
            checkpointing = [ordered]@{
                enabled = $true
            }
        }
        memory = [ordered]@{
            enableManagedAutoMemory = $false
            enableManagedAutoDream = $false
            enableAutoSkill = $false
        }
        privacy = [ordered]@{
            usageStatisticsEnabled = $false
        }
        telemetry = [ordered]@{
            enabled = $false
        }
    }

    $settingsPath = Join-Path $WorkRoot ".qwen\settings.json"
    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    $catalogMd = Join-Path $TechKitDir "catalog-windows.md"
    $header = @"
# Qwen Coder Tech Agent - technician workspace

Follow the technician system prompt. Prefer TechKit scripts below over writing new code.
TechKit library (USB): $TechKitDir
Evidence bundles land in: $TechKitDir\collections

"@
    if (Test-Path -LiteralPath $catalogMd) {
        $catalog = (Get-Content -LiteralPath $catalogMd -Raw).
            Replace("__TECHKIT__", $TechKitDir).
            Replace("__CATALOG__", (Join-Path $TechKitDir "catalog.json"))
        $instructions = $header + $catalog
    } else {
        $instructions = $header + "(TechKit catalog not found on USB - fall back to plain PowerShell commands.)"
    }
    Set-Content -LiteralPath (Join-Path $WorkRoot "QWEN.md") -Value $instructions -Encoding UTF8
    Log "Wrote Qwen Code project settings: $settingsPath"
    Log "Wrote Qwen instructions with TechKit catalog: $(Join-Path $WorkRoot "QWEN.md")"
}

New-Item -ItemType Directory -Force -Path $UsbLogDir | Out-Null
Log "Starting Qwen Coder Tech Agent launcher"
Log "USB root: $RootDir"
Log "Install dir: $InstallDir"
Log "Qwen Code home: $QwenHomeDir"
Log "Qwen workspace: $WorkRoot"
Log "Approval mode: $ApprovalMode"
Log "Requested llama.cpp backend: $RequestedLlamaBackend"

Validate-ApprovalMode
Select-Model

$arch = $env:PROCESSOR_ARCHITECTURE
Log "Detected Windows architecture: $arch"
if ($arch -eq "AMD64") {
    $QwenCodeAsset = Find-Archive "qwen-code-win-x64.zip" "qwen-code"
    $CpuLlamaAsset = Find-Archive "llama-*-bin-win-cpu-x64.zip" "llama.cpp"
    if ($RequestedLlamaBackend -eq "vulkan") {
        $LlamaAsset = Find-Archive "llama-*-bin-win-vulkan-x64.zip" "llama.cpp"
        $LlamaBackend = "vulkan"
    } elseif ($RequestedLlamaBackend -eq "cpu") {
        $LlamaAsset = $CpuLlamaAsset
        $LlamaBackend = "cpu"
    } elseif ($RequestedLlamaBackend -eq "auto") {
        $VulkanLlamaAsset = Find-OptionalArchive "llama-*-bin-win-vulkan-x64.zip" "llama.cpp"
        if ($VulkanLlamaAsset -and (Test-WindowsVulkanRuntime)) {
            $LlamaAsset = $VulkanLlamaAsset
            $LlamaBackend = "vulkan"
            Log "Auto-selected Vulkan llama.cpp build"
        } else {
            if ($VulkanLlamaAsset) {
                Log "No Windows Vulkan runtime detected; using CPU llama.cpp build"
            } else {
                Log "No Vulkan llama.cpp archive found on the USB; using CPU llama.cpp build"
            }
            $LlamaAsset = $CpuLlamaAsset
            $LlamaBackend = "cpu"
        }
    } else {
        Fail "Unsupported QWEN_LLAMA_BACKEND value: $RequestedLlamaBackend. Use cpu, vulkan, or auto."
    }
} else {
    Fail "Unsupported Windows architecture: $arch. This Qwen Code bundle includes Windows x64 only."
}

New-Item -ItemType Directory -Force -Path $QwenCodeDir, $QwenHomeDir, $QwenRuntimeDir, $LlamaDir, $ModelDir, $TemplateDir, $LogDir, $RunDir, $WorkRoot, (Join-Path $InstallDir "tmp") | Out-Null
Cleanup-LegacyInstall
Copy-IfNeeded $script:ModelSource $script:ModelTarget
if ($env:QWEN_SPEC -eq "draft" -and (Test-Path -LiteralPath $DraftModelSource)) {
    $script:DraftModelTarget = Join-Path $ModelDir $DraftModelFile
    Copy-IfNeeded $DraftModelSource $script:DraftModelTarget
}
Copy-IfNeeded $ChatTemplateSource $ChatTemplateTarget
Expand-QwenCode $QwenCodeAsset
Expand-Llama $LlamaAsset
if ($LlamaBackend -eq "vulkan" -and !(Test-Path -LiteralPath (Join-Path $LlamaDir "ggml-vulkan.dll"))) {
    Fail "Selected Vulkan llama.cpp archive did not install ggml-vulkan.dll"
}
Write-QwenWorkspaceConfig

$AllowVulkanFallback = $RequestedLlamaBackend -eq "auto" -and $LlamaBackend -eq "vulkan" -and $CpuLlamaAsset
$ServerStarted = Start-LocalServer -AllowStartupFailure:$AllowVulkanFallback
if (!$ServerStarted -and $AllowVulkanFallback) {
    Log "Auto-selected Vulkan backend failed; falling back to CPU llama.cpp build"
    $LlamaAsset = $CpuLlamaAsset
    $LlamaBackend = "cpu"
    Expand-Llama $LlamaAsset
    [void](Start-LocalServer)
}
# Copy server logs to USB now, not only on exit, so evidence survives a yanked drive
Copy-ServerLogsToUsb

$env:QWEN_HOME = $QwenHomeDir
$env:QWEN_RUNTIME_DIR = $QwenRuntimeDir
$env:QWEN_SANDBOX = "false"
$env:QWEN_TELEMETRY_ENABLED = "false"
$env:QWEN_CODE_TOOL_CALL_STYLE = "qwen-coder"
$env:QWEN_CODE_MAX_OUTPUT_TOKENS = [string]$script:OutputTokens
$env:QWEN_CODE_SUPPRESS_YOLO_WARNING = "1"
$env:LOCAL_QWEN_API_KEY = $LocalApiKey
$env:OPENAI_API_KEY = $LocalApiKey
$env:OPENAI_BASE_URL = $ServerUrl
$env:OPENAI_MODEL = $script:ModelId

Set-Location -LiteralPath $WorkRoot
Log "Changed shell working directory to Qwen workspace: $WorkRoot"
$QwenCmd = Join-Path $QwenCodeDir "bin\qwen.cmd"
& $QwenCmd --version >> $RunLog 2>&1

$usbDriveRoot = (Split-Path -Path $RootDir -Qualifier) + "\"
$includeArg = @($RealUserProfile, "C:\", $usbDriveRoot) -join ","
$openAiLogDir = Join-Path $LogDir "openai"
Write-Host ""
Write-Host "Qwen Coder local server is ready at $ServerUrl"
Write-Host "Launching Qwen Code with $($script:ModelDisplayName)..."
Write-Host ""
Log "Launching Qwen Code: $QwenCmd --bare -e none --auth-type openai --model $($script:ModelId) --openai-base-url $ServerUrl --approval-mode $ApprovalMode --system-prompt <technician>"
Log "Included directories: $includeArg"
Log "OpenAI API logs will be copied to USB on exit"

& $QwenCmd `
    --bare `
    -e none `
    --auth-type openai `
    --model $script:ModelId `
    --openai-api-key $LocalApiKey `
    --openai-base-url $ServerUrl `
    --openai-logging `
    --openai-logging-dir $openAiLogDir `
    --approval-mode $ApprovalMode `
    --core-tools run_shell_command `
    --core-tools read_file `
    --core-tools edit `
    --exclude-tools notebook_edit `
    --system-prompt $SystemPrompt `
    --include-directories $includeArg
$QwenStatus = $LASTEXITCODE
Copy-ServerLogsToUsb
Log "Qwen Code exited with status $QwenStatus"
if ($QwenStatus -ne 0) {
    Write-Host ""
    Write-Host "Qwen Code exited with status $QwenStatus." -ForegroundColor Red
    Write-Host "Launcher log: $RunLog"
    Write-Host ""
    Write-Host "Press Enter to close this window."
    [void][Console]::ReadLine()
    exit $QwenStatus
}
