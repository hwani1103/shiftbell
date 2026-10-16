$ErrorActionPreference = 'Stop'
$gameDesign = Join-Path $PSScriptRoot '../../../docs/next_version_27이후/game_design_v1'
$gameLevels = Get-Content -LiteralPath (Join-Path $gameDesign '08_pilot_levels.json') -Raw -Encoding UTF8
$gameCollisions = Get-Content -LiteralPath (Join-Path $gameDesign '10_collision_fixtures.json') -Raw -Encoding UTF8
$gameCertificates = Get-Content -LiteralPath (Join-Path $gameDesign '09_pilot_certificates.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$gameWitnesses = @($gameCertificates.levels | ForEach-Object { [pscustomobject]@{ id=$_.id; witness=$_.witness } }) | ConvertTo-Json -Depth 20 -Compress
$gameFixtureSource = "// Generated development fixtures; never a runtime asset.`nconst pilotLevels = r'''$gameLevels''';`nconst pilotWitnesses = r'''$gameWitnesses''';`nconst collisionFixtures = r'''$gameCollisions''';`n"
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'web_fixtures.g.dart') -Value $gameFixtureSource -Encoding UTF8
