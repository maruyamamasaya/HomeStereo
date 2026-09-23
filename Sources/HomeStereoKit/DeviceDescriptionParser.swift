import Foundation

public enum DeviceDescriptionParser {
    public static func parse(data: Data, descriptionURL: URL) throws -> MediaRenderer {
        let delegate = ParserDelegate(baseURL: descriptionURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let renderer = delegate.renderer else {
            throw HomeStereoError.invalidDeviceDescription
        }
        return renderer
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private struct ServiceFields {
        var serviceType = ""
        var serviceID = ""
        var controlURL = ""
        var eventSubURL = ""
        var scpdURL = ""
    }

    private let baseURL: URL
    private var path: [String] = []
    private var text = ""
    private var deviceType = ""
    private var friendlyName = ""
    private var manufacturer = ""
    private var modelName = ""
    private var modelNumber: String?
    private var udn = ""
    private var currentService: ServiceFields?
    private var services: [UPnPService] = []

    init(baseURL: URL) { self.baseURL = baseURL }

    var renderer: MediaRenderer? {
        guard !deviceType.isEmpty, !friendlyName.isEmpty, !udn.isEmpty else { return nil }
        return MediaRenderer(
            descriptionURL: baseURL,
            deviceType: deviceType,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            modelNumber: modelNumber,
            udn: udn,
            services: services
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        text = ""
        if elementName == "service" { currentService = ServiceFields() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentService != nil {
            switch elementName {
            case "serviceType": currentService?.serviceType = value
            case "serviceId": currentService?.serviceID = value
            case "controlURL": currentService?.controlURL = value
            case "eventSubURL": currentService?.eventSubURL = value
            case "SCPDURL": currentService?.scpdURL = value
            case "service":
                if let fields = currentService,
                   !fields.serviceType.isEmpty,
                   let controlURL = URL(string: fields.controlURL, relativeTo: baseURL)?.absoluteURL {
                    services.append(UPnPService(
                        serviceType: fields.serviceType,
                        serviceID: fields.serviceID,
                        controlURL: controlURL,
                        eventSubscriptionURL: URL(string: fields.eventSubURL, relativeTo: baseURL)?.absoluteURL,
                        descriptionURL: URL(string: fields.scpdURL, relativeTo: baseURL)?.absoluteURL
                    ))
                }
                currentService = nil
            default: break
            }
        } else if path.count >= 3, path[path.count - 2] == "device" {
            switch elementName {
            case "deviceType": deviceType = value
            case "friendlyName": friendlyName = value
            case "manufacturer": manufacturer = value
            case "modelName": modelName = value
            case "modelNumber": modelNumber = value.isEmpty ? nil : value
            case "UDN": udn = value
            default: break
            }
        }
        _ = path.popLast()
        text = ""
    }
}
