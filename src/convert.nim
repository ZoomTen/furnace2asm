import readModule
import ./util
import ./types/[module, chip, pattern, instrument, instrumentType, sequence, notes]
import std/[sets, tables, enumerate, sugar, strutils]
import std/math
import std/options

const mapNote2Const: Table[Note, string] = [
  (nC, "C_"),
  (nCs, "C#"),
  (nD, "D_"),
  (nDs, "D#"),
  (nE, "E_"),
  (nF, "F_"),
  (nFs, "F#"),
  (nG, "G_"),
  (nGs, "G#"),
  (nA, "A_"),
  (nAs, "A#"),
  (nB, "B_"),
  (nOff, "__"),
  (nBlank, "__"),
  (nOffRel, "__"),
  (nRel, "__"),
  (nUnknown, "__"),
].toTable()

#[ `fade` is instead the wavetable ID for the wave channel ]#
type Envelope = tuple[start: range[0..15], fade: int]

var
  noteTypeDefined = false #[ used to determine whether or not to use `intensity` for envelope changes]#
  currentInstrument = -1
  dutyMacroCommandUsedOnce = false
  globalTiming: TimingInfo
  currentVolume = -1 #[ Furnace volume column ]#
  currentEnvelope: Envelope = (15, 0)

#[ a.k.a. the first parameter of `note_type`. ]#
const baseUnitTicks = 12 #[ represents a 1/16th note, or one whole row ]#
var currentUnitTicks = baseUnitTicks

proc moduleSpeedToGfTempo(timing: TimingInfo): int =
  # bpmify
  let bpm = (
    (120.0 * timing.clockSpeed) /
    ((timing.timeBase + 1) * 4 * (timing.speed[0] + timing.speed[1])).float *
    (timing.virtualTempo[0].float / timing.virtualTempo[1].float)
  )
  result = int(19296 / bpm)

proc findCertainEffect(row: NoteSeqCommand, effectId: int): Option[int16] {.inline.}

proc pattern2Seq(pattern: Pattern, moduleSpeed: int): NoteSeq =
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

  let cutRows =
    if frameCutOn > -1:
      pattern.rows[0 .. frameCutOn]
    else:
      pattern.rows

  var cmd: NoteSeqCommand
  for rowNumber, row in enumerate(cutRows):
    cmd.noteSignature = (row.note, row.octave.uint16)
    #[ Previously, `length` meant "how many rows does this
       note span?". This was very limiting and made triplets
       essentially impossible.
       
       What I *should have done instead* was make the length
       a factor of the speed initially, and then have the EDxx
       commands modify them. ]#
    cmd.length = moduleSpeed
    
    #[ Furthermore, playing with "row associated with previous
       note signature" or whatever made the logic quite brittle. ]#
    cmd.volume = row.volume
    cmd.effects = row.effects
    cmd.instrument = row.instrument

    #[ Since the length is now expressed in absolute ticks, the
       note delays are processed here. ]#
    let delayEffect = cmd.findCertainEffect(0xED)

    if row.note == nBlank:
      if len(result) > 0:
        #[ Each additional blank row increases the length
           of the previous note instead. ]#
        result[^1].length += moduleSpeed
      else:
        #[ Nothing is present, so at least add a rest note here. ]#
        result.add(cmd)
    else: #[ A note ]#
      if delayEffect.isSome:
        #[ Note delays shift THIS note later, which means lengthening
           the previous note and shortening this note. ]#
        if len(result) > 0:
          let delayValue = delayEffect.get.int
          if delayValue < moduleSpeed:
            result[^1].length += delayValue
            cmd.length -= delayValue
          #[ The delay effect won't take effect if the resulting value
             makes the current note have a length of 0. Well, we can't
             have that. For now, regardless of Furnace's actual behavior,
             it'll just be like nothing happened. ]#
      #[ After all the adjustments, we can finally add it to the note bin. ]#
      result.add(cmd)

proc findCertainEffect(row: NoteSeqCommand, effectId: int): Option[int16] =
  let listEffects = collect(newSeq()):
    for effect in row.effects:
      if effect[0] == effectId:
        effect[1]
  if listEffects.len > 0:
    if listEffects[0] < 0: # clamp to 0
      result = some(0'i16)
    else:
      result = some(listEffects[0])
  else:
    result = none(int16)

func transposeNote(note: NoteSignature, n: int): NoteSignature =
  var
    (octaveOffset, noteOffset) = divmod(n, 12)
    newNote = note.note.int + noteOffset
  if newNote > nC.int:
    newNote = newNote - nC.int
  elif newNote < nCs.int:
    newNote += nC.int
  # I'm not sure about this case. :deflatemask:
  if n < 0:
    if newNote < note.note.int:
      octaveOffset -= 1
  return (note: Note(newNote), octave: uint16(int(note.octave) + octaveOffset))

proc seq2Asm(
    sequence: NoteSeq,
    instruments: seq[Instrument2],
    constName: string,
    channelNumber: 0 .. 3,
    useOldMacros: bool,
    enablePrism: bool,
    gen1Compat: bool,
    moduleSpeed: int
): seq[string] =
  noteTypeDefined = false
  result = @[]

  #[ handle notes above the supported length of 16 by cloning them ]#
  var safeNoteBin: NoteSeq
  for note in sequence:
    let maxLength = (16 * moduleSpeed)
    var newCmd = note
    if note.length > maxLength:
      let
        noteMult = floorDiv(int(note.length), maxLength)
        noteRemain = floorMod(note.length, maxLength)
      for i in 1 .. noteMult: # clone notes
        newCmd.length = maxLength
        safeNoteBin.add(newCmd)
      if noteRemain > 0: # add the remainder
        newCmd.length = noteRemain
        safeNoteBin.add(newCmd)
    else:
      safeNoteBin.add(note)

  var
    currentOctave = -1
    currentTone = -1
    currentDuty = -1
    currentStereo = -1
    insChanged = false #[ triggers output of a note_type or intensity command,
                          doesn't always have to be because the Furnace instrument
                          changed ]#
    currentArp = -1
    currentDutyCycleMacro = none(seq[int])

  # reset everything at the beginning except for
  # the wave channel where it might be useful to retain
  # this info between patterns
  if channelNumber != 2:
    currentInstrument = -1

  for note in safeNoteBin:
    var row = note
    #[ express the note length as a multiple of baseUnitTicks ]#
    let nTicks = int(
      (float(row.length) / float(moduleSpeed)) * baseUnitTicks
    )
    #[ calculate the best unitTicks to handle said note length ]#
    var candidateUnitTicks = 1
    for cand in 2..baseUnitTicks:
      if nTicks mod cand == 0:
        candidateUnitTicks = cand
    #[ now make the length relative to this new unit tick ]#
    row.length = int(float(nTicks) / float(candidateUnitTicks))

    if candidateUnitTicks != currentUnitTicks:
      currentUnitTicks = candidateUnitTicks

      result.add(
          if useOldMacros:
            "notetype $#, $$$#" % [$currentUnitTicks, toHex((currentEnvelope.start shl 4) or currentEnvelope.fade, 2)]
          else:
            "note_type $#, $#, $#" % [$currentUnitTicks, $currentEnvelope.start, $currentEnvelope.fade]
        )

    # before anything else, process instruments first
    block processInstruments:
      if channelNumber != 2:
        if (currentInstrument != row.instrument) and (row.instrument != -1):
          currentInstrument = row.instrument
          insChanged = true
      if (currentVolume != row.volume) and (row.volume != -1):
        currentVolume = row.volume
        insChanged = true

      if currentInstrument != -1:
        let dutyMacro = collect(newSeq()):
          for feature in instruments[currentInstrument].features:
            if feature.code == fcMacro:
              for m in feature.macroList:
                if m.kind == mcDuty:
                  if m.data.len == 4:
                    m.data
        if dutyMacro.len >= 1:
          dutyMacroCommandUsedOnce = true
          if currentDutyCycleMacro.isNone or
              (
                currentDutyCycleMacro.isSome and
                (dutyMacro[0] != currentDutyCycleMacro.get)
              ):
            currentDutyCycleMacro = dutyMacro[0].some
            result.add(
              if useOldMacros:
                "sound_duty $#, $#, $#, $#" % [
                  $(currentDutyCycleMacro.get()[3]),
                  $(currentDutyCycleMacro.get()[2]),
                  $(currentDutyCycleMacro.get()[1]),
                  $(currentDutyCycleMacro.get()[0]),
                ]
              else:
                "duty_cycle_pattern $#, $#, $#, $#" % [
                  $(currentDutyCycleMacro.get()[0]),
                  $(currentDutyCycleMacro.get()[1]),
                  $(currentDutyCycleMacro.get()[2]),
                  $(currentDutyCycleMacro.get()[3]),
                ]
            )
        else:
          currentDutyCycleMacro = none(seq[int])

    # each effect must be tied to a note!
    block processEffects:
      # change waveform (10xx)
      if channelNumber == 2:
        let newWaveIns = row.findCertainEffect(0x10)
        if newWaveIns.isSome and (newWaveIns.get != currentEnvelope.fade):
          currentEnvelope.fade = newWaveIns.get
          insChanged = true
      # pitch offset (E5xx), xx = 80 -> normal tuning
      let newPitch = row.findCertainEffect(0xe5)
      if newPitch.isSome and (newPitch.get != currentTone):
        currentTone = newPitch.get
        result.add(
          if gen1Compat:
            # parameter is ignored
            if useOldMacros: "toggleperfectpitch"
            else: "toggle_perfect_pitch"
          else:
            if useOldMacros:
              "tone $#" % [$(currentTone - 0x80)]
            else:
              "pitch_offset $#" % [$(currentTone - 0x80)]
        )
      # change duty cycle (12xx)
      if channelNumber <= 1:
        let newDuty = row.findCertainEffect(0x12)
        if newDuty.isSome and (newDuty.get != currentDuty):
          currentDuty = newDuty.get
          result.add(
            if useOldMacros:
              if dutyMacroCommandUsedOnce:
                "sound_duty $#, $#, $#, $#" %
                  [$currentDuty, $currentDuty, $currentDuty, $currentDuty]
              else:
                "dutycycle $#" % [$currentDuty]
            else:
              if dutyMacroCommandUsedOnce:
                "duty_cycle_pattern $#, $#, $#, $#" %
                  [$currentDuty, $currentDuty, $currentDuty, $currentDuty]
              else:
                "duty_cycle $#" % [$currentDuty]
          )
      # apply stereo effects (08xx ONLY)
      let newStereo = row.findCertainEffect(0x08)
      if newStereo.isSome and (newStereo.get != currentStereo):
        if newStereo.get < 0:
          currentStereo = 0xff
        else:
          currentStereo = newStereo.get
        let
          newStereoLeft = bool(currentStereo shr 4)
          newStereoRight = bool(currentStereo and 0b1111)
        if not gen1Compat:
          result.add(
            if useOldMacros:
              "stereopanning $$$#$#" %
                [if newStereoLeft: "f" else: "0", if newStereoRight: "f" else: "0"]
            else:
              "stereo_panning $#, $#" % [
                if newStereoLeft: "TRUE" else: "FALSE",
                if newStereoRight: "TRUE" else: "FALSE",
              ]
          )
      # apply speed effects (0Fxx)
      let newTempo = row.findCertainEffect(0x0f)
      if newTempo.isSome:
        var newTimingInfo = globalTiming
        newTimingInfo.speed = (newTempo.get.uint8, newTempo.get.uint8)
        result.add("tempo $#" % [$moduleSpeedToGfTempo(newTimingInfo)])

      # apply vibrato effects (04xy) -- do NOT use this for delayed vibrato!!
      let newVibrato = row.findCertainEffect(0x04)
      if newVibrato.isSome:
        let
          vibValue = newVibrato.get
          speed = (vibValue shr 4)
          depth = (vibValue and 0b1111)
        result.add(
          if useOldMacros:
            "vibrato 0, $$$#" % [((depth shl 4) or speed).uint8.toHex()]
          else:
            "vibrato 0, $#, $#" % [$depth, $speed]
        )

      if enablePrism:
        # apply arp effects (00xy)
        let newArp = row.findCertainEffect(0x00)
        if newArp.isSome and (newArp.get != currentArp):
          currentArp = newArp.get
          let
            newArpX = (currentArp and 0b11110000) shr 4
            newArpY = (currentArp and 0b1111)
          result.add("arp $#, $#" % [$newArpX, $newArpY])
        # apply pitch down (02xx) -> Pitch linearity should be set to None!
        if (let newPitchDown = row.findCertainEffect(0x02); newPitchDown.isSome):
          result.add("portadown $#" % [$(newPitchDown.get)])
        # apply pitch up (01xx) -> Pitch linearity should be set to None!
        if (let newPitchUp = row.findCertainEffect(0x01); newPitchUp.isSome):
          result.add("portaup $#" % [$(newPitchUp.get)])
        # apply note slide (E1xx)
        # Does not work as intended :(
        # let
        #   newNoteSlideUp = row.findCertainEffect(0xE1)
        #   newNoteSlideDown = row.findCertainEffect(0xE2)
        # if newNoteSlideUp.isSome:
        #   let
        #     value = newNoteSlideUp.get
        #     speed = (value and 0b11110000) shr 4
        #     semitones = (value and 0b1111)
        #     noteTo = transposeNote(row.noteSignature, semitones)
        #   result.add(
        #     "slidepitchto $#, $#, $#" %
        #       [$speed, $noteTo.octave, mapNote2Const[noteTo.note]]
        #   )
        # elif newNoteSlideDown.isSome:
        #   let
        #     value = newNoteSlideDown.get
        #     speed = (value and 0b11110000) shr 4
        #     semitones = -(value and 0b1111)
        #     noteTo = transposeNote(row.noteSignature, semitones)
        #   result.add(
        #     "slidepitchto $#, $#, $#" %
        #       [$speed, $noteTo.octave, mapNote2Const[noteTo.note]]
        #   )

    if insChanged:
      case channelNumber
      of 0, 1: # square waves
        var gbFeature: Ins2Feature

        block findGbFeature:
          for feature in instruments[currentInstrument].features:
            if feature.code == fcGb:
              gbFeature = feature
              break findGbFeature
          #[ ok, if we can't find one, assume the defaults,
             because that happens sometimes ]#
          gbFeature =
            Ins2Feature(code: fcGb, envVolume: 15, envLength: 2, envGoesUp: false)
        
        #[ Furnace quirk: the volume column overrides whatever is defined in the instrument
           and will stay like that, provided you haven't started playing from an affected
           pattern but instead from the beginning of the song. ]#
        currentEnvelope.start =
          if currentVolume != -1: currentVolume
          else: gbFeature.envVolume.int
        currentEnvelope.fade = (gbFeature.envLength or (uint8(gbFeature.envGoesUp) shl 3)).int

        result.add(
          if gen1Compat:
            if useOldMacros:
              "notetype $#, $$$#" % [$currentUnitTicks, toHex((currentEnvelope.start shl 4) or currentEnvelope.fade, 2)]
            else:
              "note_type $#, $#, $#" % [$currentUnitTicks, $currentEnvelope.start, $currentEnvelope.fade]
          else:
            if useOldMacros:
              if noteTypeDefined:
                "intensity $$$#" % [toHex((currentEnvelope.start shl 4) or currentEnvelope.fade, 2)]
              else:
                noteTypeDefined = true
                "notetype $#, $$$#" % [$currentUnitTicks, toHex((currentEnvelope.start shl 4) or currentEnvelope.fade, 2)]
            else:
              if noteTypeDefined:
                "volume_envelope $#, $#" % [$currentEnvelope.start, $currentEnvelope.fade]
              else:
                noteTypeDefined = true
                "note_type $#, $#, $#" % [$currentUnitTicks, $currentEnvelope.start, $currentEnvelope.fade]
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
        currentEnvelope.start = calculatedVolume

        if noteTypeDefined:
          result.add(
            if gen1Compat:
              if useOldMacros:
                "notetype $#, $$$#" % [$currentUnitTicks, ((currentEnvelope.start shl 4) + currentEnvelope.fade).toHex(2)]
              else:
                "note_type $#, $#, $#" % [$currentUnitTicks, $currentEnvelope.start, $currentEnvelope.fade]
            else:
              if useOldMacros:
                "intensity $$$#" % [((currentEnvelope.start shl 4) + currentEnvelope.fade).toHex(2)]
              else:
                "volume_envelope $#, $#" % [$currentEnvelope.start, $currentEnvelope.fade]
          )
        else:
          result.add(
            if useOldMacros:
              noteTypeDefined = true
              "notetype $#, $$$#" % [$currentUnitTicks, ((currentEnvelope.start shl 4) + currentEnvelope.fade).toHex(2)]
            else:
              noteTypeDefined = true
              "note_type $#, $#, $#" % [$currentUnitTicks, $currentEnvelope.start, $currentEnvelope.fade]
          )
      of 3: # noise channel, don't feel like doing anything
        discard
      insChanged = false
    
    # add notes
    if channelNumber == 3: # drum channel
      result.add(
        if useOldMacros:
          if mapNote2Const[row.noteSignature[0]] == "__":
            "note __, $#" % [$row.length]
          else:
            "note $#, $#" %
              ["DRUM_" & constName & "_" & row.instrument.toHex(2), $row.length]
        else:
          if mapNote2Const[row.noteSignature[0]] == "__":
            "rest $#" % [$row.length]
          else:
            "drum_note $#, $#" %
              ["DRUM_" & constName & "_" & row.instrument.toHex(2), $row.length]
      )
    else:
      if (row.noteSignature[1].int != currentOctave) and (row.noteSignature[1].int > 0):
        currentOctave = row.noteSignature[1].int
        if currentOctave < 2:
          currentOctave = 2 # clamp to gameboy min. of C-2
        result.add("octave $#" % [$(currentOctave - 1)])
      result.add(
        if useOldMacros:
          "note $#, $#" % [mapNote2Const[row.noteSignature[0]], $row.length]
        else:
          if mapNote2Const[row.noteSignature[0]] == "__":
            "rest $#" % [$row.length]
          else:
            "note $#, $#" % [mapNote2Const[row.noteSignature[0]], $row.length]
      )

  result.add(if useOldMacros: "endchannel" else: "sound_ret")

proc toPretAsm(
    module: Module, useOldMacros: bool = false, enablePrism: bool = false,
    gen1Compat: bool = false
): string =
  if not (len(module.chips) == 1 and module.chips[0].kind == chGb):
    raise newException(ValueError, "Must only contain 1 Game Boy chip!")

  result = ""

  let
    songName = module.meta.name.toTitle()
    constName = module.meta.name.toUpper().replace(" ", "_")

  globalTiming = module.timing

  if not gen1Compat:
    result &= "Music_$#:\n" % [songName]

    # always 4 channels, GSC format
    result &= (if useOldMacros: "\tchannelcount 4\n" else: "\tchannel_count 4\n")
    for i in 1 .. 4:
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

  let loopPoint =
    if jumpCommands.len > 1:
      raise
        newException(ValueError, "Only one 0Bxx command is allowed in the entire song!")
    elif jumpCommands.len == 0:
      -1
    else:
      jumpCommands[0]

  result &= "\n; Drum constants, replace with the proper values\n"

  for i in drumInstruments:
    if useOldMacros:
      result &=
        "$#DRUM_$#_$#\tEQU\tC_\n" %
        [(if (not useOldMacros) or enablePrism: "DEF " else: ""), constName, i.toHex(2)]
    else:
      result &=
        "$#DRUM_$#_$#\tEQU\t$$00\n" %
        [(if (not useOldMacros) or enablePrism: "DEF " else: ""), constName, i.toHex(2)]

  if not gen1Compat:
    result &= "\n; Drumset to use, replace with the proper value\n"
    result &=
      "$#DRUMSET_$#\tEQU\t$$00\n" %
      [(if (not useOldMacros) or enablePrism: "DEF " else: ""), constName]

  var orderIdx: int

  for channel, order in module.order.pairs():
    currentInstrument = -1
    currentEnvelope = (15, 0)
    orderIdx = 0
    dutyMacroCommandUsedOnce = false

    result &= "\nMusic_$#_Ch$#$#\n" % [songName, $(channel + 1),
      if gen1Compat:
        "::"
      else:
        ":"
    ]

    if channel == 0:
      result &= (
        if useOldMacros:
          "\ttempo $#\n\tvolume $$77\n" % [$module.timing.moduleSpeedToGfTempo]
        else:
          "\ttempo $#\n\tvolume 7, 7\n" % [$module.timing.moduleSpeedToGfTempo]
      )

    if channel == 3: # noise channel
      result &= (
        if useOldMacros:
          if gen1Compat:
            "\tnotetype 12\n"
          else:
            "\tnotetype 12\n\ttogglenoise DRUMSET_$#\n" % [constName]
        else:
          if gen1Compat:
            "\tdrum_speed 12\n"
          else:
            "\tdrum_speed 12\n\ttoggle_noise DRUMSET_$#\n" % [constName]
      )
    else:
      if channel == 2:
        currentEnvelope = (1, 0)
      result &= (
        if useOldMacros:
          if channel == 2: "\tnotetype 12, $10\n" else: "\tnotetype 12, $00\n"
        else:
          if channel == 2: "\tnote_type 12, 1, 0\n" else: "\tnote_type 12, 15, 0\n"
      )

    for patnum in order:
      if orderIdx == loopPoint:
        result &= ".loop\n"
      result &=
        "\t$# .pattern$#\n" %
        [if useOldMacros: "callchannel" else: "sound_call", $patnum]
      orderIdx += 1

    result &=
      "\t$#\n" % [
        if loopPoint != -1:
          if gen1Compat:
            if useOldMacros: "loopchannel 0, .loop" else: "sound_loop 0, .loop"
          else:
            if useOldMacros: "jumpchannel .loop" else: "sound_jump .loop"
        else:
          if useOldMacros: "endchannel" else: "sound_ret"
      ]

    for pattern in module.patterns:
      if (pattern.channel.int == channel):
        result &= "\n.pattern$#\n" % [$pattern.index]
        for line in pattern2Seq(pattern, globalTiming.speed[0].int).seq2Asm(
          module.instruments, constName, channel, useOldMacros, enablePrism, gen1Compat,
          globalTiming.speed[0].int
        ):
          result &= "\t$#\n" % [line]

proc convertFile*(inFile: string, useOldMacros, enablePrism, gen1Compat: bool): string =
  result = moduleFromFile(inFile).toPretAsm(useOldMacros, enablePrism, gen1Compat)
