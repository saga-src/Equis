function Assert-ProductionWindowsUpdateBuild {
  param([Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Executable)
  # Flutter records the definitions passed to its Windows AOT build here.
  # Inspect only update flag names; never print other definitions or values.
  $configuration = Join-Path $ProjectRoot 'windows/flutter/ephemeral/generated_config.cmake'
  if (!(Test-Path -LiteralPath $configuration -PathType Leaf)) {
    throw 'Rebuild Windows before preparing production update artifacts.'
  }
  if ((Get-Item -LiteralPath $configuration).LastWriteTimeUtc -gt
      (Get-Item -LiteralPath $Executable).LastWriteTimeUtc) {
    throw 'The Windows executable predates its generated build configuration. Rebuild Windows.'
  }
  $text = Get-Content -LiteralPath $configuration -Raw
  $definitions = [regex]::Matches($text, '(?m)^\s*"DART_DEFINES=([^"\r\n]*)"\s*$')
  if ($definitions.Count -gt 1) { throw 'Ambiguous Windows build definitions.' }
  if ($definitions.Count -eq 1 -and $definitions[0].Groups[1].Value) {
    foreach ($encoded in $definitions[0].Groups[1].Value.Split(',')) {
      try { $definition = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) }
      catch { throw 'Invalid Windows build definitions.' }
      $name = $definition.Split('=', 2)[0]
      if ($name.StartsWith('EQUIS_UPDATE_TEST_', [StringComparison]::Ordinal) -or
          $name -eq 'EQUIS_WINDOWS_INSTALLED_UPDATE_ENABLED') {
        throw 'Test update definitions cannot be packaged for production.'
      }
    }
  }
}
