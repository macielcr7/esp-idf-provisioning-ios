// Copyright 2020 Espressif Systems
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//  ESPProvision.swift
//  ESPProvision
//

import Foundation
import UIKit
import CoreBluetooth

/// Supported mode of communication with device.
public enum ESPTransport: String {
    /// Communicate using bluetooth.
    case ble
    /// Communicate using Soft Access Point.
    case softap
    
    public init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "ble": self = .ble
        case "softap": self = .softap
        default: return nil
        }
    }
}

/// Security options on data transmission.
public enum ESPSecurity: Int {
    /// Unsecure data transmission.
    case unsecure = 0
    /// Data is encrypted before transmission.
    case secure = 1
    /// Data is encrypted using SRP algorithm before transmission
    case secure2 = 2
    
    public init(rawValue: Int) {
        switch rawValue {
        case 0:
            self = .unsecure
        case 1:
            self = .secure
        case 2:
            self = .secure2
        default:
            self = .secure2
        }
    }
}

/// The `ESPProvisionManager` class is a singleton class. It provides methods for getting `ESPDevice` object.
/// Provide option to
public class ESPProvisionManager: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    
    private var espDevices:[ESPDevice] = []
    private var espBleTransport:ESPBleTransport!
    private var devicePrefix:String?
    private var serviceUuids:[CBUUID]?
    private var transport:ESPTransport = .ble
    private var security: ESPSecurity = .secure2
    private var searchCompletionHandler: (([ESPDevice]?,ESPDeviceCSSError?) -> Void)?
    private var scanCompletionHandler: ((ESPDevice?,ESPDeviceCSSError?) -> Void)?
    // Stores block that will be invoked during QR code processing.
    private var scanStatusBlock: ((ESPScanStatus) -> Void)?
    
    /// Member to access singleton object of class.
    public static let shared = ESPProvisionManager()
    
    private override init() {
        
    }
    
    /// Search for `ESPDevice` using bluetooth scan.
    /// SoftAp search is not yet supported in iOS
    ///
    /// - Parameters:
    ///   - devicePrefix: Prefix of found device should match with devicePrefix.
    ///   - transport: Mode of transport.
    ///   - security: Security mode for communication.
    ///   - completionHandler: The completion handler is called when search for devices is complete. Result
    ///                        of search is returned as parameter of this function. When search is successful
    ///                        array of found devices are returned. When search fails then reaon for failure is
    ///                        returned as `ESPDeviceCSSError`.
    public func searchESPDevices(devicePrefix: String? = nil, serviceUuids:[CBUUID]? = nil, transport: ESPTransport, security:ESPSecurity = .secure, completionHandler: @escaping ([ESPDevice]?,ESPDeviceCSSError?) -> Void) {
        
        ESPLog.log("Search ESPDevices called.")
        
        // Store handler to call when search is complete
        self.scanCompletionHandler = nil
        self.searchCompletionHandler = completionHandler
        
        // Store configuration related properties
        self.transport = transport
        self.devicePrefix = devicePrefix
        self.serviceUuids = serviceUuids
        self.security = security
        
        switch transport {
            case .ble:
                espBleTransport = ESPBleTransport(scanTimeout: 5.0, deviceNamePrefix: devicePrefix, serviceUuids: serviceUuids)
                espBleTransport.scan(delegate: self)
            case .softap:
                ESPLog.log("ESP SoftAp Devices search is not yet supported in iOS.")
                completionHandler(nil,.softApSearchNotSupported)
        }
        
    }
    
    /// Stops searching for Bluetooth devices. Not applicable for SoftAP device type.
    /// Any intermediate search result will be ignored. Delegate for peripheralsNotFound is called.
    public func stopESPDevicesSearch() {
        ESPLog.log("Stop ESPDevices search called.")
        espBleTransport.stopSearch()
    }
    
    /// Stop camera session that is capturing QR code. Call this method when your `Scan View` goes out of scope.
    ///
    public func stopScan() {
        ESPLog.log("Stopping Camera Session..")
    }
    
    /// Refresh device list with current transport and security settings.
    ///
    /// - Parameter completionHandler: The completion handler is called when refresh is completed. Result
    ///                                of refresh is returned as parameter of this function.
    public func refreshDeviceList(completionHandler: @escaping ([ESPDevice]?,ESPDeviceCSSError?) -> Void) {
        searchESPDevices(devicePrefix: self.devicePrefix, serviceUuids: self.serviceUuids, transport: self.transport, security: self.security, completionHandler: completionHandler)
    }
        
    /// Manually create `ESPDevice` object.
    ///
    /// - Parameters:
    ///   - deviceName: Name of `ESPDevice`.
    ///   - transport: Mode of transport.
    ///   - security: Security mode for communication.
    ///   - completionHandler: The completion handler is invoked with parameters containing newly created device object.
    ///                        Error in case where method fails to return a device object.
    public func createESPDevice(deviceName: String, transport: ESPTransport, security: ESPSecurity = .secure2, proofOfPossession:String? = nil, softAPPassword:String? = nil, username:String? = nil, completionHandler: @escaping (ESPDevice?,ESPDeviceCSSError?) -> Void) {
        
        ESPLog.log("Creating ESPDevice...")
        
        switch transport {
        case .ble:
            self.searchCompletionHandler = nil
            self.scanCompletionHandler = completionHandler
            self.security = security
            self.scanStatusBlock?(.searchingBLE(deviceName))
            espBleTransport = ESPBleTransport(scanTimeout: 5.0, deviceNamePrefix: deviceName, proofOfPossession: proofOfPossession, username: username)
            espBleTransport.scan(delegate: self)
        default:
            self.scanStatusBlock?(.joiningSoftAP(deviceName))
            let newDevice = ESPDevice(name: deviceName, security: security, transport: transport, proofOfPossession: proofOfPossession, username:username, softAPPassword: softAPPassword)
            ESPLog.log("SoftAp device created successfully.")
            completionHandler(newDevice, nil)
        }
        self.scanStatusBlock = nil
    }
    
    /// Method to enable/disable library logs.
    ///
    /// - Parameter enable: Bool to enable/disable console logs`.
    public func enableLogs(_ enable: Bool) {
        ESPLog.isLogEnabled = enable
    }
}

extension ESPProvisionManager: ESPBLETransportDelegate {
    
    func peripheralsFound(peripherals: [String:ESPDevice]) {
        
        ESPLog.log("Ble devices found :\(peripherals)")
        
        espDevices.removeAll()
        for device in peripherals.values {
            device.security = self.security
            device.proofOfPossession  = espBleTransport.proofOfPossession
            device.username = espBleTransport.username
            device.espBleTransport = espBleTransport
            espDevices.append(device)
        }
        self.searchCompletionHandler?(espDevices,nil)
        self.scanCompletionHandler?(espDevices.first,nil)
    }

    func peripheralsNotFound(serviceUUID _: UUID?) {
        
        ESPLog.log("No ble devices found.")
        
        self.searchCompletionHandler?(nil,.espDeviceNotFound)
        self.scanCompletionHandler?(nil,.espDeviceNotFound)
    }
}
