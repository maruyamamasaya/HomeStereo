import Foundation
import Testing
@testable import HomeStereoKit

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

@Test func parsesRendererDescriptionAndResolvesRelativeServiceURLs() throws {
    let xml = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0"><device>
      <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
      <friendlyName>R soundbar</friendlyName><manufacturer>Sony Corporation</manufacturer>
      <modelName>SRS-HG1</modelName><modelNumber>MINT1.9.1</modelNumber>
      <UDN>uuid:stable-id</UDN><serviceList>
        <service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><serviceId>render</serviceId><SCPDURL>/RenderingControlSCPD.xml</SCPDURL><controlURL>/upnp/control/RenderingControl</controlURL><eventSubURL>/upnp/event/RenderingControl</eventSubURL></service>
        <service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><serviceId>transport</serviceId><SCPDURL>/AVTransportSCPD.xml</SCPDURL><controlURL>/upnp/control/AVTransport</controlURL><eventSubURL>/upnp/event/AVTransport</eventSubURL></service>
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
