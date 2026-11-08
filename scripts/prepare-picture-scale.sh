#!/bin/sh
# Build ThirdParty/royalvnc from the pinned RoyalVNCKit commit and add the
# Screen Sharing scale message. The app sends that scale from
# VNCSession.appleServerScale. A value of 1 sends nothing.
# The committed tree is the source of truth. Re-running this over it deletes
# those edits, so the script stops when VENDORED.md is already there.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
src="$root/.derived/SourcePackages/checkouts/royalvnc"
dest="$root/ThirdParty/royalvnc"
revision=0a76294a7cdc8616b2eea5fba958415e544ed34b

if [ -f "$dest/VENDORED.md" ]; then
  printf '%s\n' "ThirdParty/royalvnc is already vendored. Edit it in place. Re-running this script would delete those edits." >&2
  exit 1
fi

if [ ! -d "$src/Sources/RoyalVNCKit" ]; then
  src=$(mktemp -d)/royalvnc
  git clone --quiet https://github.com/royalapplications/royalvnc.git "$src"
  git -C "$src" checkout --quiet "$revision"
fi

mkdir -p "$(dirname "$dest")"
rsync -a --delete --exclude .git "$src/" "$dest/"
chmod -R u+w "$dest"

python3 - "$dest" << 'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
settings = root / "Sources/RoyalVNCKit/SDK/Connection/Settings.swift"
handshake = root / "Sources/RoyalVNCKit/SDK/Connection/VNCConnection+Handshake.swift"
scale_file = root / "Sources/RoyalVNCKit/SDK/Connection/VNCConnection+AppleScale.swift"

settings_text = settings.read_text()
if "appleServerScale" not in settings_text:
    settings_text = settings_text.replace(
        "\t\tpublic let frameEncodings: [VNCFrameEncodingType]\n",
        "\t\tpublic let frameEncodings: [VNCFrameEncodingType]\n\n"
        "\t\t/// 1 keeps the server framebuffer. Below 1 asks macOS Screen Sharing\n"
        "\t\t/// to downscale the picture it sends. 1 is the default.\n"
        "\t\tpublic let appleServerScale: Double\n",
        1,
    )
    settings_text = settings_text.replace(
        "\t\t\t\t\tframeEncodings: [VNCFrameEncodingType]) {\n",
        "\t\t\t\t\tframeEncodings: [VNCFrameEncodingType],\n"
        "\t\t\t\t\tappleServerScale: Double = 1) {\n",
        1,
    )
    settings_text = settings_text.replace(
        "\t\t\tself.frameEncodings = frameEncodings\n\t\t}\n",
        "\t\t\tself.frameEncodings = frameEncodings\n"
        "\t\t\tself.appleServerScale = appleServerScale\n\t\t}\n",
        1,
    )
    settings.write_text(settings_text)

handshake_text = handshake.read_text()
needle = '\t\tlet framebufferSize = VNCSize(width: serverInit.framebufferWidth,'
insert = '''\t\tdo {
\t\t\ttry await sendAppleServerScaleIfNeeded()
\t\t} catch {
\t\t\tthrow VNCError.ConnectionError.closedDuringHandshake(handshakingPhase: "Send Apple Server Scale",
\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t underlyingError: error)
\t\t}

'''
if "sendAppleServerScaleIfNeeded" not in handshake_text:
    if needle not in handshake_text:
        raise SystemExit("handshake insertion point missing")
    handshake.write_text(handshake_text.replace(needle, insert + needle, 1))

scale_file.write_text('''#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// macOS Screen Sharing message 0x08. A scale below 1 makes screensharingd
// send a smaller picture for this viewer. The Mac's own display is unchanged.
extension VNCProtocol {
\tstruct AppleServerScale: VNCSendableMessage {
\t\tlet messageType: UInt8 = 0x08
\t\tlet scale: Double

\t\tvar data: Data {
\t\t\tlet length = 10
\t\t\tvar data = Data(capacity: length)
\t\t\tdata.append(messageType)
\t\t\tdata.appendPadding()
\t\t\tlet bits = scale.bitPattern
\t\t\tdata.append(UInt32(bits >> 32), bigEndian: true)
\t\t\tdata.append(UInt32(truncatingIfNeeded: bits), bigEndian: true)
\t\t\tguard data.count == length else {
\t\t\t\tfatalError("VNCProtocol.AppleServerScale data.count (\\(data.count)) != \\(length)")
\t\t\t}
\t\t\treturn data
\t\t}

\t\tfunc send(connection: NetworkConnectionWriting) async throws {
\t\t\ttry await connection.write(data: data)
\t\t}
\t}
}

extension VNCConnection {
\tfunc sendAppleServerScaleIfNeeded() async throws {
\t\tlet scale = settings.appleServerScale
\t\tguard scale > 0, scale < 1 else { return }
\t\tlogger.logDebug("Sending Apple server scale \\(scale)")
\t\ttry await VNCProtocol.AppleServerScale(scale: scale).send(connection: connection)
\t}
}
''')
print("patched", root)
PY
