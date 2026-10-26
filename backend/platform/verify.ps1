# Isolated PostgreSQL policies test. Hosted Auth/Storage APIs are not simulated end to end.
$ErrorActionPreference = 'Stop'
$testContainer = 'neuralnotes-policies-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
try {
    docker run --rm -d --name $testContainer -e POSTGRES_PASSWORD=fixture-only postgres:16-alpine | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Postgres test container did not start' }
    $ready = $false
    # The entrypoint briefly starts a Unix-socket-only server during initdb,
    # then stops it. Only the final server accepts TCP connections.
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        docker exec $testContainer pg_isready -h 127.0.0.1 -p 5432 -U postgres -d postgres *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { docker logs --tail 30 $testContainer; throw 'Final Postgres TCP server not ready' }
    foreach ($script in @('test-bootstrap.sql', 'schema.sql', 'migrations/001_account_lifecycle.sql', 'migrations/002_revision_conflict.sql', 'migrations/003_readiness.sql', 'security.test.sql', 'account-lifecycle.test.sql')) {
        Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot $script) | docker exec -i -e PGPASSWORD=fixture-only $testContainer psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) { throw "SQL verification failed: $script" }
    }
} finally {
    docker stop $testContainer | Out-Null
}
