import Foundation
import Testing
@testable import HomeStereoKit

@Test func parsesServiceDescriptionActionsOnly() throws {
    let xml = Data("""
    <scpd xmlns="urn:schemas-upnp-org:service-1-0">
      <actionList>
        <action><name>SetAVTransportURI</name><argumentList><argument><name>InstanceID</name></argument></argumentList></action>
        <action><name>Play</name></action>
      </actionList>
      <serviceStateTable><stateVariable><name>TransportState</name></stateVariable></serviceStateTable>
    </scpd>
    """.utf8)
    let description = try ServiceDescriptionParser.parse(data: xml)
    #expect(description.actions == ["SetAVTransportURI", "Play"])
}

@Test func parsesSSDPResponseAndDeduplicatesUSN() throws {
    let text = "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.0.105:54380/device.xml\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:stable-id::urn:schemas-upnp-org:device:MediaRenderer:1\r\nSERVER: Linux/3.0 UPnP/1.0 Sony/1.0\r\n\r\n"
    let response = try #require(SSDPDiscovery.parseResponse(text, sourceAddress: "192.168.0.105"))
    #expect(response.location.absoluteString == "http://192.168.0.105:54380/device.xml")
    #expect(response.sourceAddress == "192.168.0.105")
    #expect(response.server?.contains("Sony") == true)
    #expect(SSDPDiscovery.deduplicated([response, response]).count == 1)
}

@Test func trackURLUsesOpaqueIDTokenAndSelectedPort() {
    let id = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    let url = TrackURLBuilder.url(host: "192.168.0.35", port: 8766, trackID: id, token: "secret")
    #expect(url.absoluteString == "http://192.168.0.35:8766/tracks/01234567-89ab-cdef-0123-456789abcdef?token=secret")
    #expect(!url.absoluteString.contains("Users"))
}

@Test func mimeTypesCoverCurrentLibraryFormats() throws {
    #expect(try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.mp3")) == "audio/mpeg")
    #expect(try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.m4a")) == "audio/mp4")
    #expect(try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.alac")) == "audio/mp4")
    #expect(try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.flac")) == "audio/flac")
    #expect(try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.wav")) == "audio/wav")
    #expect(try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.aiff")) == "audio/aiff")
    #expect(throws: HomeStereoError.unsupportedAudioFormat("ogg")) {
        try AudioMIMEType.forFileURL(URL(fileURLWithPath: "/tmp/a.ogg"))
    }
}

@Test(arguments: [
    (nil, nil),
    ("bytes=0-99", ByteRange(lowerBound: 0, upperBound: 99)),
    ("bytes=100-", ByteRange(lowerBound: 100, upperBound: 999)),
    ("bytes=-100", ByteRange(lowerBound: 900, upperBound: 999)),
    ("bytes=900-1200", ByteRange(lowerBound: 900, upperBound: 999)),
])
func parsesHTTPRanges(input: String?, expected: ByteRange?) throws {
    #expect(try ByteRange.parse(input, fileSize: 1_000) == expected)
}

@Test func rejectsInvalidHTTPRanges() {
    #expect(throws: HomeStereoError.invalidRange) { try ByteRange.parse("items=0-2", fileSize: 10) }
    #expect(throws: HomeStereoError.invalidRange) { try ByteRange.parse("bytes=10-20", fileSize: 10) }
    #expect(throws: HomeStereoError.invalidRange) { try ByteRange.parse("bytes=5-2", fileSize: 10) }
    #expect(throws: HomeStereoError.invalidRange) { try ByteRange.parse("bytes=0-1,3-4", fileSize: 10) }
}

@Test func handlesHTTPHeadGetRangesAndTraversal() {
    let id = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    let target = "/tracks/01234567-89ab-cdef-0123-456789abcdef?token=secret"
    let head = MediaHTTPRequestHandler.response(method: "HEAD", target: target, headers: [:], trackID: id, token: "secret", mimeType: "audio/mpeg", fileSize: 1_000)
    #expect(head.status == 200)
    #expect(head.headers["Content-Length"] == "1000")
    #expect(head.bodyRange == nil)
    let get = MediaHTTPRequestHandler.response(method: "GET", target: target, headers: ["range": "bytes=100-199"], trackID: id, token: "secret", mimeType: "audio/mpeg", fileSize: 1_000)
    #expect(get.status == 206)
    #expect(get.headers["Content-Range"] == "bytes 100-199/1000")
    #expect(get.bodyRange == ByteRange(lowerBound: 100, upperBound: 199))
    let invalid = MediaHTTPRequestHandler.response(method: "GET", target: target, headers: ["range": "bytes=1000-"], trackID: id, token: "secret", mimeType: "audio/mpeg", fileSize: 1_000)
    #expect(invalid.status == 416)
    let traversal = MediaHTTPRequestHandler.response(method: "GET", target: "/tracks/../private?token=secret", headers: [:], trackID: id, token: "secret", mimeType: "audio/mpeg", fileSize: 1_000)
    #expect(traversal.status == 404)
}

@Test func parsesRendererDescriptionAndResolvesRelativeServiceURLs() throws {
    let xml = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0"><device>
      <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
      <friendlyName>R soundbar</friendlyName><manufacturer>Sony Corporation</manufacturer>
      <modelName>SRS-HG1</modelName><modelNumber>MINT1.9.1</modelNumber>
      <UDN>uuid:stable-id</UDN><presentationURL>/status</presentationURL><serviceList>
        <service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><serviceId>render</serviceId><SCPDURL>/RenderingControlSCPD.xml</SCPDURL><controlURL>/upnp/control/RenderingControl</controlURL><eventSubURL>/upnp/event/RenderingControl</eventSubURL></service>
        <service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><serviceId>transport</serviceId><SCPDURL>/AVTransportSCPD.xml</SCPDURL><controlURL>/upnp/control/AVTransport</controlURL><eventSubURL>/upnp/event/AVTransport</eventSubURL></service>
        <service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><serviceId>connection</serviceId><SCPDURL>/ConnectionManagerSCPD.xml</SCPDURL><controlURL>/upnp/control/ConnectionManager</controlURL><eventSubURL>/upnp/event/ConnectionManager</eventSubURL></service>
      </serviceList>
    </device></root>
    """
    let renderer = try DeviceDescriptionParser.parse(
        data: Data(xml.utf8),
        descriptionURL: URL(string: "http://192.168.0.105:54380/device.xml")!
    )
    #expect(renderer.friendlyName == "R soundbar")
    #expect(renderer.modelName == "SRS-HG1")
    #expect(renderer.udn == "uuid:stable-id")
    #expect(renderer.avTransport?.controlURL.absoluteString == "http://192.168.0.105:54380/upnp/control/AVTransport")
    #expect(renderer.renderingControl?.controlURL.absoluteString == "http://192.168.0.105:54380/upnp/control/RenderingControl")
    #expect(renderer.connectionManager != nil)
    #expect(renderer.presentationURL?.absoluteString == "http://192.168.0.105:54380/status")
}

@Test func soapEscapesArgumentsAndUsesRequestedService() throws {
    let data = SOAPRequestBuilder.envelope(
        serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
        action: "SetAVTransportURI",
        arguments: [("InstanceID", "0"), ("CurrentURI", "http://host/a?x=1&y=<2>")]
    )
    let xml = String(decoding: data, as: UTF8.self)
    #expect(xml.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
    #expect(xml.contains("http://host/a?x=1&amp;y=&lt;2&gt;"))
    #expect(!xml.contains("x=1&y="))
}

@Test func parsesAndFormatsUPnPTime() {
    #expect(UPnPTime.parse("01:02:03") == 3_723)
    #expect(UPnPTime.parse("00:00:03.5") == 3.5)
    #expect(UPnPTime.parse("NOT_IMPLEMENTED") == nil)
    #expect(UPnPTime.format(3_723.9) == "01:02:03")
}

@Test func parsesSOAPFaultDiagnostics() {
    let data = Data("""
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><detail><UPnPError><errorCode>701</errorCode><errorDescription>Transition not available</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>
    """.utf8)
    let fault = SOAPResponseParser.fault(action: "Pause", status: 500, data: data)
    #expect(fault.action == "Pause")
    #expect(fault.httpStatus == 500)
    #expect(fault.errorCode == 701)
    #expect(fault.errorDescription == "Transition not available")
}

@Test func soapReadRetriesOneTimeoutButPlayIsNeverRetried() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TimeoutURLProtocol.self]
    let controller = UPnPController(session: URLSession(configuration: configuration))
    let service = UPnPService(
        serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
        serviceID: "av",
        controlURL: URL(string: "http://renderer.invalid/control")!,
        eventSubscriptionURL: nil,
        descriptionURL: nil
    )

    TimeoutURLProtocol.configure(succeedAfter: 1, responseBody: """
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
      <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        <CurrentTransportState>PLAYING</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>
      </u:GetTransportInfoResponse>
    </s:Body></s:Envelope>
    """)
    let info = try await controller.getTransportInfo(service: service)
    #expect(info.state == "PLAYING")
    #expect(TimeoutURLProtocol.requestCount == 2)

    TimeoutURLProtocol.configure(succeedAfter: nil, responseBody: "")
    await #expect(throws: URLError.self) {
        try await controller.play(service: service)
    }
    #expect(TimeoutURLProtocol.requestCount == 1)
}

private final class TimeoutURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var succeedAfter: Int?
    nonisolated(unsafe) private static var responseBody = ""
    nonisolated(unsafe) private static var count = 0

    static var requestCount: Int { lock.withLock { count } }

    static func configure(succeedAfter: Int?, responseBody: String) {
        lock.withLock {
            self.succeedAfter = succeedAfter
            self.responseBody = responseBody
            count = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let outcome = Self.lock.withLock { () -> (Bool, String) in
            Self.count += 1
            return (Self.succeedAfter.map { Self.count > $0 } ?? false, Self.responseBody)
        }
        guard outcome.0 else {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(outcome.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
