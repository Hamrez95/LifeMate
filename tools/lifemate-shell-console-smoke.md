# LifeMate Shell local console smoke

The LifeMate parent shell is registered in `tools/lifemate.apps.json` under the `lifemate` app key.

Useful commands:

```powershell
pwsh .\tools\lifemate.ps1 -List
pwsh .\tools\lifemate.ps1 -App lifemate -Run -Target Android
pwsh .\tools\lifemate.ps1 -App lifemate -Run -Target Chrome
pwsh .\tools\lifemate.ps1 -App lifemate -Build Debug -Format APK
```

The Android path uses `tools/release/prepare-lifemate-android.sh` before Flutter run/build so the generated Android host keeps the isolated `com.mylifemate.lifemate` package identity.

Local runs require the normal public runtime configuration selected by the console (`tools/lifemate.local.json` or process environment variables). No private/service-role values belong in this file.
