import binstreams
import ./types/[pattern, module, notes]

using
    pattern: var Pattern
    stream: var MemStream
    module: var Module

proc readPattern(pattern, stream, module) =
    if stream.readStr(4) != "PATR":
        raise newException(ValueError, "Wrong pattern format")

    stream.setPosition 4, sspCur # reserved

    pattern.channel = stream.read(uint16)
    pattern.index = stream.read(uint16)
    
    stream.setPosition 4, sspCur # reserved

    let
        numEffects = module.channelInfo[pattern.channel].numEffects.int()
        patternLength = module.miscInfo.patternLength.int()
    
    for p in 0 ..< patternLength:
        var newRow = Row(
            note: Note(stream.read(uint16)),
            octave: stream.read(uint16),
            instrument: stream.read(int16),
            volume: stream.read(int16)
        )
        # get around Delek(tm) quality
        if newRow.note == nC:
            newRow.octave += 1
        
        for f in 0 ..< numEffects:
            newRow.effects.add((
                stream.read(int16),
                stream.read(int16)
            ))
        pattern.rows.add(newRow)

proc patternFromStream*(stream, module): Pattern =
    result = Pattern()
    result.readPattern(stream, module)