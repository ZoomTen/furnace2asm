import readModule
import ./util
import ./types/[
    module, chip, pattern, instrument, instrumentType, sequence, notes
]
import std/[
    sets, tables, enumerate, sugar,
    strformat, strutils
]
import std/math

const mapNote2Const: Table[Note, string] = [
    (nC, "C_"), (nCs, "C#"), (nD, "D_"), (nDs, "D#"),
    (nE, "E_"), (nF,  "F_"), (nFs,"F#"), (nG,  "G_"),
    (nGs,"G#"), (nA,  "A_"), (nAs,"A#"), (nB,  "B_"),
    (nOff, "__"), (nBlank, "__"), (nOffRel, "__"), (nRel, "__"),
    (nUnknown, "__")
].toTable()

var
    noteTypeDefined = false
    currentInstrument = -1
    currentVolume = 15

proc moduleSpeedToGfTempo(timing: TimingInfo): int =
    # bpmify
    let bpm = (
        (120.0 * timing.clockSpeed) / (
            (timing.timeBase+1) * 4 * (
                timing.speed[0] + timing.speed[1]
            )
        ).float
    )
    result = int(19296 / bpm)

proc pattern2Seq(pattern: Pattern): NoteSeq =
    result = @[]
    # Find where the pattern cuts short

    var frameCutOn = -1

    block findFrameCut:
        for rowNumber, row in enumerate(pattern.rows):
            for effect in row.effects:
                case effect[0]
                of 0x0D, 0x0B, 0xFF:
                    frameCutOn = rowNumber
                    break findFrameCut
                else:
                    discard
    
    let cutRows = if frameCutOn > -1:
            pattern.rows[0 .. frameCutOn]
        else:
            pattern.rows
    
    var
        noteSignature: (Note, uint16)
        previousNoteSignature: (Note, uint16)
        rowAssocWithPrevNoteSig: Row
        noteLength: int
    
    for rowNumber, row in enumerate(cutRows): # what a handful
        noteSignature = (row.note, row.octave)

        if rowNumber == 0: # first row
            previousNoteSignature = noteSignature
            rowAssocWithPrevNoteSig = row
            noteLength = 1
        elif rowNumber == cutRows.len-1:
            if noteSignature == (nBlank, 0'u16):
                noteLength += 1
            else:
                result.add(NoteSeqCommand(
                    noteSignature: previousNoteSignature,
                    length: noteLength,
                    instrument: rowAssocWithPrevNoteSig.instrument,
                    volume: rowAssocWithPrevNoteSig.volume,
                    effects: rowAssocWithPrevNoteSig.effects
                ))
                noteLength = 1
                previousNoteSignature = noteSignature
                rowAssocWithPrevNoteSig = row
            result.add(NoteSeqCommand(
                noteSignature: previousNoteSignature,
                length: noteLength,
                instrument: rowAssocWithPrevNoteSig.instrument,
                volume: rowAssocWithPrevNoteSig.volume,
                effects: rowAssocWithPrevNoteSig.effects
            ))
        else:
            if noteSignature == (nBlank, 0'u16):
                noteLength += 1
            else:
                result.add(NoteSeqCommand(
                    noteSignature: previousNoteSignature,
                    length: noteLength,
                    instrument: rowAssocWithPrevNoteSig.instrument,
                    volume: rowAssocWithPrevNoteSig.volume,
                    effects: rowAssocWithPrevNoteSig.effects
                ))
                previousNoteSignature = noteSignature
                rowAssocWithPrevNoteSig = row
                noteLength = 1

proc findCertainEffect(row: NoteSeqCommand, effectId: int): int {.inline.} =
    let
        listEffects = collect(newSeq()):
            for effect in row.effects:
                if effect[0] == effectId:
                    effect[1]
    if listEffects.len > 0:
        result = listEffects[0]
    else:
        result = -999

proc seq2Asm(sequence: NoteSeq, instruments: seq[Instrument2], constName: string, channelNumber: 0 .. 3, useOldMacros: bool): seq[string] =
    noteTypeDefined = false
    result = @[]

    var safeNoteBin: NoteSeq

    #[
        handle notes above the supported length of 16
        by cloning them
    ]#
    for note in sequence:
        if note.length > 16:
            let
                noteMult = floorDiv(note.length, 16)
                noteRemain = floorMod(note.length, 16)
            for i in 1 .. noteMult: # clone notes
                safeNoteBin.add(NoteSeqCommand(
                    noteSignature: note.noteSignature,
                    length: 16,
                    instrument: note.instrument,
                    volume: note.volume,
                    effects: note.effects
                ))
            if noteRemain > 0: # add the remainder
                safeNoteBin.add(NoteSeqCommand(
                    noteSignature: note.noteSignature,
                    length: noteRemain,
                    instrument: note.instrument,
                    volume: note.volume,
                    effects: note.effects
                ))
        else:
            safeNoteBin.add(note)
    
    var
        currentWaveId = -1
        currentOctave = -1
        currentTone = -1
        currentDuty = -1
        currentStereo = -1
        insChanged = false
    
    for row in safeNoteBin:
        insChanged = false

        # before anything else, process instruments first
        block processInstruments:
            if channelNumber != 2:
                if (currentInstrument != row.instrument) and (row.instrument != -1):
                    currentInstrument = row.instrument
                    insChanged = true
            if (currentVolume != row.volume) and (row.volume != -1):
                currentVolume = row.volume
                insChanged = true          
        
        block processEffects:
            # change waveform ONLY thru 10xx
            if channelNumber == 2:
                let newWaveIns = row.findCertainEffect(0x10)
                if (newWaveIns != currentWaveId) and (newWaveIns != -999):
                    currentWaveId = newWaveIns
                    insChanged = true
            # pitch offset
            let newPitch = row.findCertainEffect(0xe5)
            if (newPitch != -999) and (newPitch != currentTone):
                currentTone = newPitch
                result.add(
                    if useOldMacros:
                        "tone $#" % [$(newPitch - 0x80)]
                    else:
                        "pitch_offset $#" % [$(newPitch - 0x80)]
                )
            # change duty cycle ONLY thru 12xx
            if channelNumber <= 1:
                let newDuty = row.findCertainEffect(0x12)
                if (newDuty != currentDuty) and (newDuty != -999):
                    currentDuty = newDuty
                    result.add(
                        if useOldMacros:
                            "dutycycle $#" % [$currentDuty]
                        else:
                            "duty_cycle $#" % [$currentDuty]
                    )
            # apply stereo effects
            let newStereo = row.findCertainEffect(0x08)
            if (newStereo != currentStereo) and (newStereo != -999):
                if newStereo < 0:
                    currentStereo = 0xff
                else:
                    currentStereo = newStereo
                let
                    newStereoLeft = bool(currentStereo shr 4)
                    newStereoRight = bool(currentStereo and 0b1111)
                result.add(
                    if useOldMacros:
                        "stereopanning $$$#$#" % [
                            if newStereoLeft: "f" else: "0",
                            if newStereoRight: "f" else: "0"
                        ]
                    else:
                        "stereo_panning $#, $#" % [
                            if newStereoLeft: "TRUE" else: "FALSE",
                            if newStereoRight: "TRUE" else: "FALSE"
                        ]
                )

        
        if insChanged:
            case channelNumber
            of 0, 1: # square waves
                var gbFeature: Ins2Feature
                
                block findGbFeature:
                    for feature in instruments[currentInstrument].features:
                        if feature.code == fcGb:
                            gbFeature = feature
                            break findGbFeature
                    #[
                        ok, if we can't find one, assume the defaults,
                        because that happens sometimes
                    ]#
                    gbFeature = Ins2Feature(
                        code: fcGb,
                        envVolume: 15,
                        envLength: 2,
                        envGoesUp: false
                    )
                
                let
                    startVolume = floor(
                        float(gbFeature.envVolume) * (currentVolume / 15)
                    ).int
                    calculatedLength = (
                        gbFeature.envLength or (uint8(gbFeature.envGoesUp) shl 3)
                    ).int
                
                result.add(
                    if useOldMacros:
                        if noteTypeDefined:
                            "intensity $$$#" % [toHex((startVolume shl 4) or calculatedLength, 2)]
                        else:
                            noteTypeDefined = true
                            "notetype 12, $$$#" % [toHex((startVolume shl 4) or calculatedLength, 2)]
                    else:
                        if noteTypeDefined:
                            "volume_envelope $#, $#" % [$startVolume, $calculatedLength]
                        else:
                            noteTypeDefined = true
                            "note_type 12, $#, $#" % [$startVolume, $calculatedLength]
                )
            of 2: # wave channel has a special note_type
                let
                    calculatedVolume = (
                        if currentVolume == -1: 1
                        elif currentVolume >= 12: 1
                        elif currentVolume >= 8: 2
                        elif currentVolume >= 4: 3
                        else: 3
                    )
                    envByte = (calculatedVolume, currentWaveId)
                
                if noteTypeDefined:
                    result.add(
                        if useOldMacros:
                            "intensity $$$#" % [
                                (
                                    (envByte[0] shl 4) + envByte[1]
                                ).toHex(2)
                            ]
                        else:
                            "intensity $#, $#" % [
                                $envByte[0], $envByte[1]
                            ]
                    )
                else:
                    result.add(
                        if useOldMacros:
                            "notetype 12, $$$#" % [
                                (
                                    (envByte[0] shl 4) + envByte[1]
                                ).toHex(2)
                            ]
                        else:
                            "note_type 12, $#, $#" % [
                                $envByte[0], $envByte[1]
                            ]
                    )
            of 3: # noise channel, don't feel like doing anything
                discard

        # add notes
        if channelNumber == 3: # drum channel
            result.add(
                if useOldMacros:
                    if mapNote2Const[row.noteSignature[0]] == "__":
                        "note __, $#" % [
                            $row.length
                        ]
                    else:
                        "note $#, $#" % [
                            "DRUM_" & constName & "_" & row.instrument.toHex(2),
                            $row.length
                        ]
                else:
                    if mapNote2Const[row.noteSignature[0]] == "__":
                        "rest $#" % [
                            $row.length
                        ]
                    else:
                        "drum_note $#, $#" % [
                            "DRUM_" & constName & "_" & row.instrument.toHex(2),
                            $row.length
                        ]
            )
        else:
            if (row.noteSignature[1].int != currentOctave) and (row.noteSignature[1].int > 0):
                currentOctave = row.noteSignature[1].int
                if currentOctave < 2:
                    currentOctave = 2  # clamp to gameboy min. of C-2
                result.add("octave $#" % [$(currentOctave - 1)])
            result.add(
                if useOldMacros:
                    "note $#, $#" % [
                        mapNote2Const[row.noteSignature[0]],
                        $row.length
                    ]
                else:
                    if mapNote2Const[row.noteSignature[0]] == "__":
                        "rest $#" % [
                            $row.length
                        ]
                    else:
                        "note $#, $#" % [
                            mapNote2Const[row.noteSignature[0]],
                            $row.length
                        ]
            )
    
    result.add(
        if useOldMacros: "endchannel" else: "sound_ret"
    )

proc toPretAsm(module: Module, useOldMacros: bool = false): string =
    if not(len(module.chips) == 1 and module.chips[0].kind == chGb):
        raise newException(ValueError, "Must only contain 1 Game Boy chip!")

    result = ""

    let
        songName = module.meta.name.toTitle()
        constName = module.meta.name.toUpper().replace(" ", "_")
    
    result &= "Music_$#:\n" % [songName]

    # always 4 channels, GSC format
    result &= (
        if useOldMacros:
            "\tchannelcount 4\n"
        else:
            "\tchannel_count 4\n"
    )
    for i in 1..4:
        result &= "\tchannel $#, Music_$#_Ch$#\n" % [$i, songName, $i]

    let
        drumInstruments = collect(initHashSet()):
            for pattern in module.patterns:
                if pattern.channel == 3:
                    for row in pattern.rows:
                        if row.instrument != -1:
                            {row.instrument}
        jumpCommands = collect(newSeq()):
            for pattern in module.patterns:
                for row in pattern.rows:
                    for effect in row.effects:
                        if effect[0] == 0x0b:
                            effect[1]
    
    let loopPoint = if jumpCommands.len > 1:
            raise newException(ValueError, "Only one 0Bxx command is allowed in the entire song!")
        elif jumpCommands.len == 0:
            -1
        else:
            jumpCommands[0]

    result &= "\n; Drum constants, replace with the proper values\n"

    for i in drumInstruments:
        result &= "DRUM_$#_$#\tEQU\t$$00\n" % [constName, i.toHex(2)]
    
    result &= "\n; Drumset to use, replace with the proper value\n"
    result &= "DRUMSET_$#\tEQU\t$$00\n" % [constName]
    
    var orderIdx: int

    for channel, order in module.order.pairs():
        currentInstrument = -1
        currentVolume = 15

        orderIdx = 0

        result &= "\nMusic_$#_Ch$#:\n" % [songName, $(channel+1)]
    
        if channel == 0:
            result &= (
                if useOldMacros:
                    "\ttempo $#\n\tvolume $$77\n" % [
                        $module.timing.moduleSpeedToGfTempo
                    ]
                else:
                    "\ttempo $#\n\tvolume 7, 7\n" % [
                        $module.timing.moduleSpeedToGfTempo
                    ]
            )

        if channel == 3: # noise channel
            result &= (
                if useOldMacros:
                    "\tnotetype 12\n\ttogglenoise DRUMSET_$#\n" % [constName]
                else:
                    "\tdrum_speed 12\n\ttoggle_noise DRUMSET_$#\n" % [constName]
            )
        else:
            result &= (
                if useOldMacros:
                    "\tnotetype 12, $00\n"
                else:
                    "\tnote_type 12, 15, 0\n"
            )
        
        for patnum in order:
            if orderIdx == loopPoint:
                result &= ".loop\n"
            result &= "\t$# .pattern$#\n" % [
                if useOldMacros: "callchannel" else: "sound_call",
                $patnum
            ]
            orderIdx += 1
        
        result &= "\t$#\n" % [
            if loopPoint != -1:
                if useOldMacros: "jumpchannel .loop" else: "sound_jump .loop"
            else:
                if useOldMacros: "endchannel" else: "sound_ret"
        ]

        for pattern in module.patterns:
            if (pattern.channel.int == channel):
                result &= "\n.pattern$#\n" % [$pattern.index]
                for line in pattern2Seq(pattern).seq2Asm(
                    module.instruments, constName, channel, useOldMacros
                ):
                    result &= "\t$#\n" % [line]

proc convertFile*(inFile: string, useOldMacros: bool): string =
    result = moduleFromFile(inFile).toPretAsm(useOldMacros)