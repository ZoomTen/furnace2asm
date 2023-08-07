import binstreams
import ./types/[pattern, module, notes, exceptions]
import ./util
import std/strformat
import std/math

using
    pattern: var Pattern
    stream: var MemStream
    module: var Module

proc readPattern(pattern, stream, module) =
    stream.setPosition 4, sspCur # reserved

    pattern.channel = stream.read(uint16)
    pattern.index = stream.read(uint16)
    pattern.subsong = stream.read(uint16).uint8
    
    stream.setPosition 2, sspCur # reserved

    let
        numEffects = module.channelInfo[pattern.channel].numEffects.int()
        patternLength = module.miscInfo.patternLength.int()
    
    for p in 0 ..< patternLength:
        var newRow = Row(
            note: Note(stream.read(uint16)),
            octave: stream.read(uint16).int16, # use neg-octaves at risk
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

type
    Patn157Cmd = enum
        ptnHasNote
        ptnHasIns
        ptnHasVolume
        ptnHasFx
        ptnHasFxValue
        ptnHasFx0to3
        ptnHasFx4to7
    Patn157Cmds = set[Patn157Cmd]
    Patn157Fx0to3Cmd = enum
        ptnHasFx0
        ptnHasFx0Value
        ptnHasFx1
        ptnHasFx1Value
        ptnHasFx2
        ptnHasFx2Value
        ptnHasFx3
        ptnHasFx3Value
    Patn157Fx0to3Cmds = set[Patn157Fx0to3Cmd]
    Patn157Fx4to7Cmd = enum
        ptnHasFx4
        ptnHasFx4Value
        ptnHasFx5
        ptnHasFx5Value
        ptnHasFx6
        ptnHasFx6Value
        ptnHasFx7
        ptnHasFx7Value
    Patn157Fx4to7Cmds = set[Patn157Fx4to7Cmd]

proc fromPatn157NoteValue (noteVal: uint8): Note =
    let nv = floorMod(noteVal, 12)
    if nv == 0: nC
    else: Note(nv)

proc readPattern157(pattern, stream, module) =
    ## ver. 157 pattern format reader
    let patnContentSize = stream.read(uint32)
    var patnContents: MemStream = newMemStream(
        cast[seq[byte]](stream.readStr(patnContentSize)),
        littleEndian
    )
    pattern.subsong = patnContents.read(uint8)
    pattern.channel = patnContents.read(uint8)
    pattern.index = patnContents.read(uint16)
    pattern.name = patnContents.readCStr()

    let blankRow = Row(
        note: nBlank,
        instrument: -1,
        volume: -1
    )

    var rowsSoFar = 0

    while (var patByte = patnContents.read(uint8); patByte) != 0xff:
        if (patByte shr 7).bool:
            var skipRows = patByte and 0b1111111
            pattern.rows.add blankRow
            pattern.rows.add blankRow
            rowsSoFar.inc 2
            skipRows.inc
            while (skipRows.dec(); skipRows) != 0:
                pattern.rows.add blankRow
                rowsSoFar.inc 1
            continue

        var newRow = blankRow

        let patCmd0 = cast[Patn157Cmds](patByte)
        var
            patCmd1: Patn157Fx0to3Cmds = {}
            patCmd2: Patn157Fx4to7Cmds = {}

        if ptnHasFx0to3 in patCmd0:
            patCmd1 = cast[Patn157Fx0to3Cmds](patnContents.read(uint8))

        if ptnHasFx4to7 in patCmd0:
            patCmd2 = cast[Patn157Fx4to7Cmds](patnContents.read(uint8))

        if ptnHasNote in patCmd0:
            let noteValue = patnContents.read(uint8)
            case noteValue
            of 0..179:
                newRow.note = noteValue.fromPatn157NoteValue
                newRow.octave = floorDiv(noteValue.int16, 12)-5
            of 180:
                newRow.note = nOff
            of 181:
                newRow.note = nOffRel
            of 182:
                newRow.note = nRel
            else:
                raise newException(ValueError, fmt"Unknown note value at subsong {pattern.subsong}, ch {pattern.channel}, index {pattern.index} row {rowsSoFar}")

        if ptnHasIns in patCmd0:
            newRow.instrument = patnContents.read(uint8).int16

        if ptnHasVolume in patCmd0:
            newRow.volume = patnContents.read(uint8).int16

        # sorry

        if (ptnHasFx in patCmd0) or (ptnHasFx0 in patCmd1):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFxValue in patCmd0) or (ptnHasFx0Value in patCmd1):
            if (ptnHasFx in patCmd0) or (ptnHasFx0 in patCmd1):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx1 in patCmd1):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx1Value in patCmd1):
            if (ptnHasFx1 in patCmd1):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx2 in patCmd1):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx2Value in patCmd1):
            if (ptnHasFx2 in patCmd1):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx3 in patCmd1):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx3Value in patCmd1):
            if (ptnHasFx3 in patCmd1):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx4 in patCmd2):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx4Value in patCmd2):
            if (ptnHasFx4 in patCmd2):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx5 in patCmd2):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx5Value in patCmd2):
            if (ptnHasFx5 in patCmd2):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx6 in patCmd2):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx6Value in patCmd2):
            if (ptnHasFx6 in patCmd2):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        if (ptnHasFx7 in patCmd2):
            newRow.effects.add (patnContents.read(uint8).int16, -1.int16)

        if (ptnHasFx7Value in patCmd2):
            if (ptnHasFx7 in patCmd2):
                newRow.effects[^1][1] = patnContents.read(uint8).int16
            else:
                newRow.effects.add (-1.int16, patnContents.read(uint8).int16)

        pattern.rows.add newRow
        rowsSoFar.inc 1

    assert rowsSoFar <= module.miscInfo.patternLength.int

    for i in 0..<(module.miscInfo.patternLength.int-rowsSoFar):
        pattern.rows.add blankRow

    assert pattern.rows.len == module.miscInfo.patternLength.int


proc patternFromStream*(stream, module): Pattern =
    result = Pattern()
    case stream.readStr(4)
    of "PATR":
        result.readPattern(stream, module)
    of "PATN":
        result.readPattern157(stream, module)
    else:
        raise newException(NotImplementedError, "Unknown pattern format!")
