import Foundation
import IOKit

/// The Mac's System Management Controller, which runs the fans: Recall reads how many fans there
/// are and their speeds (no permission needed), the helper (app/Helper/main.swift) sets them
/// (root only). Keys are four letters: FNum the fan count, F0Mn/F0Mx/F0Ac fan 0's minimum,
/// maximum and current speed in rpm, F0Md (F0md on some Macs) its mode, F0Tg its target, Ftst
/// the unlock that M1 to M4 Macs need before a fan takes a target.
///
/// The structure and the Apple silicon write sequence follow Stats by Serhiy Mytrovtsiy (MIT;
/// licenses/STATS-MIT). Recall runs on Apple silicon only, so Intel's keys are left out.
final class SMC {
    struct Fan:Equatable { let index:Int;let minimum:Double;let maximum:Double }
    struct Value { var type:String;var bytes:[UInt8] }

    private var connection:io_connect_t=0

    init?() {
        let service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service,mach_task_self_,0,&connection) == kIOReturnSuccess else { return nil }
    }
    deinit { IOServiceClose(connection) }

    /// The fans this Mac has, with the speeds each can run at. Empty on a Mac without fans.
    var fans:[Fan] {
        guard let count=number("FNum"),count >= 1 else { return [] }
        return (0..<min(Int(count),10)).compactMap { i in
            guard let low=number("F\(i)Mn"),let high=number("F\(i)Mx"),high > low else { return nil }
            return Fan(index:i,minimum:low,maximum:high)
        }
    }

    func number(_ key:String)->Double? {
        guard let value=read(key) else { return nil }
        let b=value.bytes
        switch value.type {
        case "ui8 ": return b.count >= 1 ? Double(b[0]) : nil
        case "ui16": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32": return b.count >= 4 ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        case "flt ": return b.count >= 4 ? Double(b.withUnsafeBytes { $0.loadUnaligned(as:Float.self) }) : nil
        case "fpe2": return b.count >= 2 ? Double((Int(b[0]) << 6) + (Int(b[1]) >> 2)) : nil
        default: return nil
        }
    }

    // MARK: The driver's call (AppleSMC user client, selector 2)

    private struct KeyInfo { var size:UInt32=0;var type:UInt32=0;var attributes:UInt8=0 }
    private struct Call {
        var key:UInt32=0
        var version:(UInt8,UInt8,UInt8,UInt8,UInt16)=(0,0,0,0,0)
        var limits:(UInt16,UInt16,UInt32,UInt32,UInt32)=(0,0,0,0,0)
        var info=KeyInfo()
        var padding:UInt16=0
        var result:UInt8=0
        var status:UInt8=0
        var command:UInt8=0
        var data32:UInt32=0
        var bytes:(UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                   UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)=
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }
    private static let readBytes:UInt8=5,writeBytes:UInt8=6,readKeyInfo:UInt8=9

    private static func code(_ key:String)->UInt32? {
        let utf8=Array(key.utf8)
        guard utf8.count == 4 else { return nil }
        return utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
    private static func name(_ code:UInt32)->String {
        String(bytes:[24,16,8,0].map { UInt8(code >> $0 & 0xff) },encoding:.ascii) ?? ""
    }
    private func call(_ input:inout Call)->Call? {
        var output=Call(),size=MemoryLayout<Call>.stride
        guard IOConnectCallStructMethod(connection,2,&input,MemoryLayout<Call>.stride,&output,&size) == kIOReturnSuccess,
              output.result == 0 else { return nil }
        return output
    }
    private func info(_ key:UInt32)->KeyInfo? {
        var input=Call();input.key=key;input.command=Self.readKeyInfo
        guard let info=call(&input)?.info,info.size > 0,info.size <= 32 else { return nil }
        return info
    }

    func read(_ key:String)->Value? {
        guard let code=Self.code(key),let info=info(code) else { return nil }
        var input=Call();input.key=code;input.info.size=info.size;input.command=Self.readBytes
        guard var output=call(&input) else { return nil }
        let bytes=withUnsafeBytes(of:&output.bytes) { Array($0.prefix(Int(info.size))) }
        return Value(type:Self.name(info.type),bytes:bytes)
    }
    /// Writes the value's bytes (its type and size as read). False when the SMC refused it.
    func write(_ key:String,_ value:Value)->Bool {
        guard let code=Self.code(key) else { return false }
        var input=Call();input.key=code;input.info.size=UInt32(value.bytes.count);input.command=Self.writeBytes
        withUnsafeMutableBytes(of:&input.bytes) { raw in
            for (i,byte) in value.bytes.prefix(32).enumerated() { raw[i]=byte }
        }
        return call(&input) != nil
    }
}
