
import Foundation
import CoreBluetooth
import RxSwift

open class BleRscNotification {
    public let speed: Double
    public let candence: UInt8
    public let strideLength: Int
    public let distance: Double
    public let running: Bool
    public let flags: UInt8
    
    init(speed: Double, candence: UInt8, strideLength: Int, distance: Double, running: Bool, flags: UInt8){
        self.speed = speed
        self.candence = candence
        self.strideLength = strideLength
        self.distance = distance
        self.running = running
        self.flags = flags
    }
}

public class BleRscClient: BleGattClientBase {
    
    public static let RSC_SERVICE = CBUUID(string: "1814")
    let RSC_FEATURE             = CBUUID(string: "2a54")
    let RSC_MEASUREMENT         = CBUUID(string: "2a53")
    
    var observers = AtomicList<RxObserver<BleRscNotification>>()
    
    public init(gattServiceTransmitter: BleAttributeTransportProtocol){
        super.init(serviceUuid: BleRscClient.RSC_SERVICE, gattServiceTransmitter: gattServiceTransmitter)
        addCharacteristicNotification(RSC_MEASUREMENT)
        addCharacteristicRead(RSC_FEATURE)
    }
    
    // from base
    override public func reset() {
        super.reset()
        RxUtils.postErrorAndClearList(observers, error: BleGattException.gattDisconnected)
    }
    
    override public func processServiceData(_ chr: CBUUID, data: Data, err: Int ){
        if( err == 0 ) {
            if (chr.isEqual(RSC_MEASUREMENT)) {
                var index = 0
                let flags = data[0]
                index += 1
                let strideLenPresent     = (flags & 0x01) == 0x01
                let totalDistancePresent = (flags & 0x02) == 0x02
                let running              = (flags & 0x04) == 0x04
                let speedMask = UInt16(data[index]) | UInt16(UInt16(data[index + 1]) << 8)
                let speed = (Double(speedMask)/256.0)*3.6 // km/h
                index += 2
                let cadence = data[index]
                index += 1
                
                var strideLength = 0
                var totalDistance = 0.0
                
                if(strideLenPresent){
                    strideLength = (Int(UInt16(data[index]) | UInt16(UInt16(data[index + 1]) << 8)))
                    index += 2
                }
                if(totalDistancePresent){
                    var distance=0
                    memcpy(&distance, (data.subdata(in: index..<(index+4)) as NSData).bytes, 4)
                    totalDistance = Double(distance)*0.1
                }
                RxUtils.emitNext(observers) { (observer) in
                    observer.obs.onNext(BleRscNotification(speed: speed, candence: cadence, strideLength: strideLength, distance: totalDistance, running: running, flags: flags))
                }
            }else if(chr.isEqual(RSC_FEATURE)){
                // do nothing
            }
        }
    }
    
    // api
    public func observeRscNotifications(_ checkConnection: Bool) -> Observable<BleRscNotification> {
        var object: RxObserver<BleRscNotification>!
        return Observable.create{ observer in
            object = RxObserver<BleRscNotification>.init(obs: observer)
            if !checkConnection || self.gattServiceTransmitter?.isConnected() ?? false {
                self.observers.append(object)
            } else {
                observer.onError(BleGattException.gattDisconnected)
            }
            return Disposables.create {
                self.observers.remove({ (item) -> Bool in
                    return item === object
                })
            }
        }.subscribeOn(baseConcurrentDispatchQueue)
    }
    
    public override func clientReady(_ checkConnection: Bool) -> Completable {
        return waitNotificationEnabled(RSC_MEASUREMENT, checkConnection: checkConnection)
    }
}
