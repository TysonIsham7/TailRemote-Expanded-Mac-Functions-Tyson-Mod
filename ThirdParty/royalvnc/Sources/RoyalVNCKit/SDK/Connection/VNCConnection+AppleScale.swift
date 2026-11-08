#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// macOS Screen Sharing message 0x08. A scale below 1 makes screensharingd
// send a smaller picture for this viewer. The Mac's own display is unchanged.
extension VNCProtocol {
	struct AppleServerScale: VNCSendableMessage {
		let messageType: UInt8 = 0x08
		let scale: Double

		var data: Data {
			let length = 10
			var data = Data(capacity: length)
			data.append(messageType)
			data.appendPadding()
			let bits = scale.bitPattern
			data.append(UInt32(bits >> 32), bigEndian: true)
			data.append(UInt32(truncatingIfNeeded: bits), bigEndian: true)
			guard data.count == length else {
				fatalError("VNCProtocol.AppleServerScale data.count (\(data.count)) != \(length)")
			}
			return data
		}

		func send(connection: NetworkConnectionWriting) async throws {
			try await connection.write(data: data)
		}
	}
}

extension VNCConnection {
	func sendAppleServerScaleIfNeeded() async throws {
		let scale = settings.appleServerScale
		guard scale > 0, scale < 1 else { return }
		logger.logDebug("Sending Apple server scale \(scale)")
		try await VNCProtocol.AppleServerScale(scale: scale).send(connection: connection)
	}
}
