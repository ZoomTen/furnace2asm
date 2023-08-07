import binstreams
import ./types/[instrument, instrumentType]
import ./util
import strutils

using
    instrument: var Instrument2
    stream: var MemStream

proc readDev127Header(instrument, stream) =
    if stream.readStr(4) != "INS2":
        raise newException(ValueError, "Not a dev127 instrument header")

    stream.setPosition 4, sspCur # skip size

    instrument.version = stream.read(uint16)
    instrument.kind = InstrumentType(stream.read(uint16))

proc readDev127Feature(instrument, stream): Ins2Feature =
    let featureCode = stream.readStr(2)
    try:
        result = Ins2Feature(
            code: parseEnum[Ins2FeatureCode](featureCode)
        )
    except ValueError:
        raise newException(ValueError, "Unknown feature code \"" & featureCode & "\" in instrument " & instrument.index.toHex(2))
    if result.code == fcEnd:
        return result
    let insContentSize = stream.read(uint16)
    var insContents: MemStream = newMemStream(
        cast[seq[byte]](stream.readStr(insContentSize)),
        littleEndian
    )
    case result.code
    of fcName:
        result.name = insContents.readCStr()
        instrument.name = result.name
    of fcGb:
        let
            env  = insContents.read(uint8).int
            sl   = insContents.read(uint8)
            fl   = insContents.read(uint8)
            hwsl = insContents.read(uint8).int
        
        result.envVolume = uint8(env and 0b1111)
        result.envGoesUp = bool((env and 0b10000) shr 4)
        result.envLength = uint8((env and 0b11100000) shr 5)
        result.soundLength = sl
        result.flags = cast[Ins2GbFlags](fl)
        for i in 0 ..< hwsl:
            result.hardwareSequence.add(insContents.readStr(3))
    of fcMacro:
        insContents.setPosition 2, sspCur # ignore header length
        while true:
            var newMacro = Ins2Macro(
                kind: Ins2MacroCode(insContents.read(uint8))
            )
            case newMacro.kind
            of mcStop:
                result.macroList.add(newMacro)
                break
            else:
                let length = insContents.read(uint8).int

                newMacro.loopPoint = insContents.read(uint8)
                newMacro.releasePoint = insContents.read(uint8)
                newMacro.mode = insContents.read(uint8)

                let openTypeWord = insContents.read(uint8)

                newMacro.isOpen = bool(openTypeWord and 0b1)
                newMacro.macType = Ins2MacroType((openTypeWord and 0b110) shr 1)
                newMacro.wordSize = Ins2MacroWordSize((openTypeWord and 0b11000000) shr 6)
                newMacro.delay = insContents.read(uint8)
                newMacro.speed = insContents.read(uint8)

                for i in 0 ..< length:
                    case newMacro.wordSize
                    of mwUint8:
                        newMacro.data.add(int(insContents.read(uint8)))
                    of mwInt8:
                        newMacro.data.add(int(insContents.read(int8)))
                    of mwInt16:
                        newMacro.data.add(int(insContents.read(int16)))
                    of mwInt32:
                        newMacro.data.add(int(insContents.read(int32)))

                result.macroList.add(newMacro)
    of fcEnd:
        discard

proc readDev127FeaturesList(instrument, stream) =
    while true:
        let newFeature = instrument.readDev127Feature(stream)
        instrument.features.add(newFeature)
        if newFeature.code == fcEnd:
            break

proc instrumentDev127FromStream*(stream: var MemStream, index: int): Instrument2 =
    result = Instrument2(index:index)
    result.readDev127Header(stream)
    result.readDev127FeaturesList(stream)
