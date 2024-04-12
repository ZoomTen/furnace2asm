import binstreams
import zippy

import ./types/[module, chip, exceptions]
import ./util
import ./readInstrument
import ./readPattern
import tables
import strformat

const FurString = "-Furnace module-"

type FilePtrs = object
  songInfoPtr: int
  insPtr: seq[int]
  wavePtr: seq[int]
  samplePtr: seq[int]
  patternPtr: seq[int]

using
  module: var Module
  stream: var MemStream
  ptrs: var FilePtrs

proc readHeader(module, stream, ptrs) {.inline.} =
  if stream.readStr(16) != FurString:
    raise newException(ValueError, "Corrupted module file?")

  module.meta.version = stream.read(uint16)

  # stop right here
  if (module.meta.version < 127):
    raise newException(
      WrongVersionError,
      fmt"""Unsupported module version!

Supported versions are >127; you've loaded in a version {module.meta.version} module.
Versions corresponding to the valid range is > Furnace 0.6pre2.

If you're using an older version, you can open your file in the newer version
and then save again.""",
    )

  stream.setPosition 2, sspCur # reserved
  ptrs.songInfoPtr = int(stream.read(uint32))
  stream.setPosition 8, sspCur # reserved

proc readInfo(module, stream, ptrs) {.inline.} =
  stream.setPosition(ptrs.songInfoPtr)
  if stream.readStr(4) != "INFO":
    raise newException(ValueError, "Broken INFO header")

  stream.setPosition 4, sspCur

  module.timing.timeBase = stream.read(uint8)
  module.timing.speed = (stream.read(uint8), stream.read(uint8))
  module.timing.arpSpeed = stream.read(uint8)
  module.timing.clockSpeed = stream.read(float32)
  module.miscInfo.patternLength = stream.read(uint16)

  let orderLen = stream.read(uint16)

  module.timing.highlight = (stream.read(uint8), stream.read(uint8))

  let
    numInst = stream.read(uint16)
    numWave = stream.read(uint16)
    numSample = stream.read(uint16)
    numPatterns = stream.read(uint32)

  for i in 0 .. 31:
    let inChip = cast[ChipType](stream.read(uint8))
    if inChip != chEnd:
      if $inChip == "":
        raise
          newException(NotImplementedError, fmt"Unimplemented chip type {ord(inChip)}!")
      module.chips.add(ChipInfo(kind: inChip))
  for i in 0 .. 31:
    if i < module.chips.len:
      module.chips[i].volume = stream.read(int8).toFloat / 64.0
    else:
      discard stream.read(int8)
  for i in 0 .. 31:
    if i < module.chips.len:
      module.chips[i].panning = stream.read(int8)
    else:
      discard stream.read(int8)
  for i in 0 .. 31:
    if i < module.chips.len:
      module.chips[i].settings = stream.readStr(4)
    else:
      discard stream.readStr(4)

  module.meta.name = stream.readCStr()
  module.meta.author = stream.readCStr()
  module.miscInfo.tuning = stream.read(float32)
  # i STILL don't feel like deserializing this
  module.miscInfo.compatFlags = stream.readStr(20)

  for i in 0 ..< int(numInst):
    ptrs.insPtr.add int(stream.read(uint32))
  for i in 0 ..< int(numWave):
    ptrs.wavePtr.add int(stream.read(uint32))
  for i in 0 ..< int(numSample):
    ptrs.samplePtr.add int(stream.read(uint32))
  for i in 0 ..< int(numPatterns):
    ptrs.patternPtr.add int(stream.read(uint32))

  var numChannels: int
  for chip in module.chips:
    numChannels += chip.kind.numChannels

  # load orders
  for channel in 0 ..< numChannels:
    module.channelInfo.add(ChannelInfo())
    module.order[channel] = @[]
    for order in 0 ..< int(orderLen):
      module.order[channel].add(int(stream.read(uint8)))

  # fill channel info
  for channel in 0 ..< numChannels:
    module.channelInfo[channel].numEffects = stream.read(uint8)
  for channel in 0 ..< numChannels:
    module.channelInfo[channel].shown = stream.read(bool)
  for channel in 0 ..< numChannels:
    module.channelInfo[channel].collapsed = stream.read(bool)
  for channel in 0 ..< numChannels:
    module.channelInfo[channel].name = stream.readCStr()
  for channel in 0 ..< numChannels:
    module.channelInfo[channel].abbreviation = stream.readCStr()

  module.meta.comment = stream.readCStr()

  if module.meta.version >= 59:
    module.miscInfo.masterVolume = stream.read(float32)

  if module.meta.version >= 70:
    module.miscInfo.extendedCompatFlags &= stream.readStr(1)
  if module.meta.version >= 71:
    module.miscInfo.extendedCompatFlags &= stream.readStr(3)
  if module.meta.version >= 72:
    module.miscInfo.extendedCompatFlags &= stream.readStr(2)
  if module.meta.version >= 78:
    module.miscInfo.extendedCompatFlags &= stream.readStr(1)
  if module.meta.version >= 83:
    module.miscInfo.extendedCompatFlags &= stream.readStr(2)

proc readInstruments(module, stream, ptrs) {.inline.} =
  var insCounter = 0
  for i in ptrs.insPtr:
    stream.setPosition(i)
    case stream.peekStr(4)
    of "INST":
      # TODO
      raise newException(
        NotImplementedError, "The <127 instrument format is not implemented, sorry :("
      )
    of "INS2":
      module.instruments.add(stream.instrumentDev127FromStream(insCounter))
      insCounter += 1
    else:
      raise newException(NotImplementedError, "Unknown instrument format!")

proc readPattern(module, stream, ptrs) {.inline.} =
  for i in ptrs.patternPtr:
    stream.setPosition(i)
    module.patterns.add(stream.patternFromStream(module))

proc moduleFromFile*(inFileName: string): Module =
  var
    furIn: MemStream
    filePtrs: FilePtrs
  try:
    furIn = newMemStream(cast[seq[byte]](readFile(inFileName).uncompress), littleEndian)
  except ZippyError:
    # this must be an uncompressed file, then
    furIn = newMemStream(cast[seq[byte]](readFile(inFileName)), littleEndian)

  result = Module()

  # set default values
  result.miscInfo.masterVolume = 1.0

  result.readHeader(furIn, filePtrs)
  result.readInfo(furIn, filePtrs)
  result.readInstruments(furIn, filePtrs)
  # don't read wavetable and samples yet
  result.readPattern(furIn, filePtrs)
