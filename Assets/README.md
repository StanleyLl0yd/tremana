# TreMana application icon

`TreMana-AppIcon.webp` is the approved TreMana artwork, based on the familiar
Transmission icon silhouette, with a cloud and two red arrows to communicate
remote administration. The image has transparent outer margins.

`scripts/package-app.sh` generates a macOS `TreMana.icns` from this source
at standard 16–1024-pixel sizes. The generated icon is included in the app
bundle before code signing. Do not edit released GitHub assets in place.

TreMana is an independent Transmission RPC client, not an official Transmission
application. Transmission is acknowledged as the original visual reference.
